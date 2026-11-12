-- ============================================================================
--  biashara_yangu — MIGRATION 0157 : COHÉRENCE D'UN ESPACE MÉTIER
--  (pharmacie d'un patron multi-entreprises : articles, péremption, équipe)
--
--  OBSERVATION (12/11/2026) — compte josephissa@gmail.com
--    1. Dans l'entreprise « HEKIMA PHARMA », il encode un article : il est
--       accepté… puis l'écran Articles est VIDE et le tableau de bord
--       affiche 0 article.
--    2. Le formulaire n'offre PAS la date de péremption, alors que l'accueil
--       affiche déjà les rubriques « Expirations ».
--    3. Il ne peut pas créer de collaborateur : « seul le propriétaire peut
--       créer un collaborateur ».
--
--  CAUSE UNIQUE
--    Depuis le module 15, `owner_id` ne porte plus l'UUID du patron mais
--    l'UUID de l'ESPACE de travail (`utilisateurs.espace_actif_id`).
--    `mon_proprietaire()` joue donc DEUX rôles incompatibles :
--      • la PORTÉE DES DONNÉES (quel espace on lit/écrit) ;
--      • l'IDENTITÉ DU PROPRIÉTAIRE (qui a le droit de faire quoi).
--    Résultat dans une deuxième entreprise :
--      • `v_user = mon_proprietaire()` est FAUX (espace ≠ utilisateur) →
--        « DROIT_REFUSE » partout où l'on vérifie le patron ;
--      • et comme `mon_proprietaire()` n'honore `espace_actif_id` que si
--        l'espace appartient à l'entreprise COURANTE du compte, un
--        `entreprise_id` resté sur l'autre entreprise fait retomber la
--        lecture sur l'UUID du patron : les articles écrits sous l'espace
--        pharmacie deviennent INVISIBLES.
--
--  CE QUE FAIT CE SCRIPT (idempotent, aucune donnée supprimée)
--    1. `mon_proprietaire()` : le PATRON peut travailler dans n'importe
--       laquelle de SES entreprises (le collaborateur reste cloisonné).
--    2. `rpc_collaborateur_creer()` : l'identité du patron passe par
--       `mon_patron()` (UUID utilisateur) et non plus par la portée des
--       données. La création de collaborateur remarche dans toutes les
--       entreprises du compte.
--    3. Réparation : `utilisateurs.entreprise_id` est aligné sur
--       l'entreprise de l'espace actif.
--    4. `entreprises.type_activite` reçoit le métier de ses espaces
--       (pharmacie → module `lots_expiration` → champ date de péremption).
--    5. Verdict en UNE ligne (l'éditeur SQL n'affiche que le dernier
--       résultat).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. `mon_proprietaire()` — LA PORTÉE DES DONNÉES, PAS L'IDENTITÉ
-- ============================================================================
--  Règles :
--    • l'espace actif est retenu s'il existe et s'il est actif ET
--        – qu'il appartient à l'entreprise courante du compte, ou
--        – que l'utilisateur est le PATRON et que l'entreprise est à lui.
--    • sinon repli historique : UUID du patron (espace par défaut).
--  Un collaborateur ne peut donc JAMAIS sortir de son entreprise.

create or replace function public.mon_proprietaire()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- 1. L'espace de travail choisi, s'il est encore valable.
    (select u.espace_actif_id
       from public.utilisateurs u
      where u.id = auth.uid()
        and u.espace_actif_id is not null
        and exists (
          select 1
            from public.espaces s
           where s.id = u.espace_actif_id
             and s.actif
             and (
               s.entreprise_id = u.entreprise_id
               -- Le patron peut travailler dans n'importe laquelle de SES
               -- entreprises (route B : un propriétaire, plusieurs affaires).
               or (u.parent_id is null
                   and exists (
                     select 1 from public.entreprises e
                      where e.id = s.entreprise_id
                        and e.owner_id = u.id))
             )
        )),
    -- 2. Repli historique : l'UUID du patron (espace par défaut).
    (select coalesce(u.parent_id, u.id)
       from public.utilisateurs u
      where u.id = auth.uid())
  );
$$;

comment on function public.mon_proprietaire() is
  'Module 15/0157 — PORTÉE DES DONNÉES : espace de travail actif (ou UUID du patron). Ne jamais l''utiliser comme identité du propriétaire : voir mon_patron().';

revoke all on function public.mon_proprietaire() from public, anon;
grant execute on function public.mon_proprietaire() to authenticated;


-- ============================================================================
--  2. `rpc_collaborateur_creer()` — L'IDENTITÉ PASSE PAR `mon_patron()`
-- ============================================================================

drop function if exists public.rpc_collaborateur_creer(text, text, text, text, text, text);

create or replace function public.rpc_collaborateur_creer(
  p_nom          text,
  p_prenom       text,
  p_email        text,
  p_telephone    text,
  p_mot_de_passe text,
  p_role         text,
  p_espace_id    uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_role    text := upper(btrim(coalesce(p_role, '')));
  v_email   text := lower(btrim(coalesce(p_email, '')));
  v_nom     text := nullif(btrim(coalesce(p_nom, '')), '');
  v_prenom  text := coalesce(btrim(coalesce(p_prenom, '')), '');
  v_tel     text := nullif(btrim(coalesce(p_telephone, '')), '');
  v_role_enum public.role_utilisateur_enum;
  v_cible   uuid;
  v_existant uuid;
  v_nom_complet text;
  v_espace  uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer un collaborateur.';
  end if;

  -- ⚠️ 0157 : `mon_patron()` = UUID de l'utilisateur patron (identité).
  --    `mon_proprietaire()` = UUID de l'espace (portée des données) : il ne
  --    doit JAMAIS servir ici, sinon la création échoue dès la deuxième
  --    entreprise du même patron.
  v_owner := public.mon_patron();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- Seul le propriétaire du compte crée des comptes (ou la plateforme).
  if not (v_user = v_owner or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut créer un collaborateur.';
  end if;

  if v_nom is null then
    raise exception 'NOM_REQUIS|Indiquez le nom du collaborateur.';
  end if;

  if v_email = '' or position('@' in v_email) = 0 or position('.' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE|Indiquez une adresse e-mail valide (elle sert d''identifiant de connexion).';
  end if;

  if p_mot_de_passe is null or length(p_mot_de_passe) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT|Le mot de passe doit comporter au moins 8 caractères.';
  end if;

  if not (v_role = any (public.roles_entreprise_attribuables())) then
    raise exception 'ROLE_INVALIDE|Rôle inconnu : choisissez propriétaire, vendeur, magasinier ou comptable.';
  end if;

  v_role_enum := public.role_enum(v_role);

  -- 🧩 BOUTIQUE : validée (appartient à l'entreprise), sinon espace par défaut.
  v_espace := public.espace_collaborateur_valide(v_owner, p_espace_id);

  -- Compte déjà existant (même adresse) ?
  select u.id into v_existant
    from public.utilisateurs u
   where lower(u.email) = v_email
   limit 1;

  if v_existant is not null then
    if exists (
      select 1 from public.utilisateurs u
       where u.id = v_existant
         and u.parent_id is not null
         and u.parent_id <> v_owner
    ) then
      raise exception 'COMPTE_EXISTANT|Cette adresse e-mail appartient déjà au collaborateur d''une autre entreprise.';
    end if;

    if v_existant = v_owner then
      raise exception 'COMPTE_EXISTANT|Cette adresse est celle du propriétaire : choisissez une autre adresse.';
    end if;

    update auth.users
       set encrypted_password = crypt(p_mot_de_passe, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at         = now()
     where id = v_existant;

    v_cible := v_existant;
  else
    v_cible := public.creer_compte_plateforme(
      v_email, p_mot_de_passe, v_nom, v_prenom, v_role);
  end if;

  update public.utilisateurs
     set nom             = v_nom,
         prenom          = v_prenom,
         email           = v_email,
         telephone       = coalesce(v_tel, telephone),
         role            = 'collaborator',
         new_role        = coalesce(v_role_enum, public.role_enum('VENDEUR')),
         valide          = 1,
         parent_id       = v_owner,
         -- L'entreprise porte l'abonnement : jamais l'identifiant du patron.
         entreprise_id   = coalesce(
                             (select u.entreprise_id from public.utilisateurs u
                               where u.id = v_owner),
                             entreprise_id),
         -- La BOUTIQUE où travaille le collaborateur.
         espace_actif_id = coalesce(v_espace, espace_actif_id)
   where id = v_cible;

  select coalesce(nullif(btrim(coalesce(u.prenom, '') || ' ' || coalesce(u.nom, '')), ''),
                  u.email)
    into v_nom_complet
    from public.utilisateurs u where u.id = v_cible;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COLLABORATEUR_CREE', v_cible,
    jsonb_build_object(
      'role',      v_role,
      'email',     v_email,
      'par',       v_user,
      'boutique',  v_owner,
      'espace',    v_espace
    ),
    now()
  );

  return jsonb_build_object(
    'ok',       true,
    'id',       v_cible,
    'email',    v_email,
    'role',     v_role,
    'nom',      v_nom_complet,
    'espace_id', v_espace
  );
end;
$$;

comment on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid) is
  'Crée un collaborateur rattaché au patron (route B : fonctionne dans TOUTES ses entreprises). 0157 — identité via mon_patron().';

revoke all on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid) from public, anon;
grant execute on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid) to authenticated;


-- ============================================================================
--  3. RÉPARATION — L'ENTREPRISE COURANTE SUIT L'ESPACE ACTIF
-- ============================================================================
--  Sans cela, `mon_proprietaire()` doit se rabattre sur le repli historique
--  et les données de l'espace choisi restent invisibles pour un collaborateur.

update public.utilisateurs u
   set entreprise_id = s.entreprise_id
  from public.espaces s
 where s.id = u.espace_actif_id
   and u.entreprise_id is distinct from s.entreprise_id
   and u.parent_id is null;   -- patrons uniquement : un collaborateur est
                              -- toujours rattaché à l'entreprise de son patron


-- ============================================================================
--  4. LE MÉTIER DE L'ENTREPRISE SUIT SES ESPACES (péremption pharmacie)
-- ============================================================================
--  `rpc_mes_modules()` lit `entreprises.type_activite` en premier. Tant
--  qu'elle est vide, l'entreprise hérite du profil « boutique » et le
--  formulaire d'article n'affiche ni lot ni date de péremption.
--
--  Règle : on ne remplit QUE si le métier est vide et que TOUS les espaces
--  de l'entreprise portent le même type spécialisé (jamais de supposition).

with candidat as (
  select e.id,
         min(s.type) as type_unique,
         count(distinct s.type) as nb_types
    from public.entreprises e
    join public.espaces s on s.entreprise_id = e.id
   where nullif(btrim(coalesce(e.type_activite, '')), '') is null
   group by e.id
)
update public.entreprises e
   set type_activite = c.type_unique
  from candidat c
 where e.id = c.id
   and c.nb_types = 1
   and c.type_unique in ('pharmacie', 'hotel', 'restaurant', 'depot', 'boutique');


-- ============================================================================
--  5. VERDICT — UNE SEULE LIGNE
-- ============================================================================

with patron as (
  select u.id, u.entreprise_id, u.espace_actif_id, u.parent_id
    from public.utilisateurs u
   where u.parent_id is null
   order by u.created_at
   limit 1
)select jsonb_pretty(
  jsonb_build_object(
    'script', '0157 cohérence espace métier',
    'pharmacie', (
      select jsonb_build_object(
        'entreprise', e.nom,
        'type_activite', e.type_activite,
        'espace', s.nom,
        'espace_actif', (s.id = (select p.espace_actif_id from patron p)),
        'articles_visibles_pour_le_patron',
          (select count(*) from public.produits pr where pr.owner_id = s.id)
      )
        from public.entreprises e
        join public.espaces s on s.entreprise_id = e.id
       where lower(coalesce(e.type_activite, '')) = 'pharmacie'
       order by e.created_at
       limit 1
    ),
    'reste_a_faire',
      'Relancer l''application (ou se déconnecter/reconnecter) pour que la '
      'portée des données soit relue depuis le serveur.'
  )
) as verdict;
