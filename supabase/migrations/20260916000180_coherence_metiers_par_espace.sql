-- ============================================================================
--  biashara_yangu — MIGRATION 0180 / CORRECTIF 180
--  COHÉRENCE DES MÉTIERS : CADRE CHAQUE DÉCISION SUR L'ESPACE, PAS SUR
--  L'ENTREPRISE.
-- ---------------------------------------------------------------------------
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase, APRÈS la 0179.
--  ⚠️ IDEMPOTENT : relançable sans effet de bord.
--
--  ════════════════════════════════════════════════════════════════════════
--  CE QUI A ÉTÉ CONSTATÉ
--  ════════════════════════════════════════════════════════════════════════
--  « Une boutique qui passe à la place de pressing » : dans un compte qui
--  possède une boutique ET un pressing, la boutique se comporte comme un
--  pressing (elle ne peut plus vendre, ses collaborateurs reçoivent un métier
--  de pressing, les écrans Dépôts/Atelier/Retraits apparaissent).
--
--  IL Y A AVAIT QUATRE CAUSES, TOUTES LIÉES AU MÊME CONFUSION :
--    « l'entreprise fait du pressing » ≠ « CET espace de travail est un
--      pressing ».
--
--  ① MIGRATION 0153 — « TOUS les espaces du compte passent en pressing ».
--     Un compte boutique + pressing s'est donc retrouvé avec DEUX espaces
--     typés `pressing`. La boutique est devenue un pressing aux yeux de
--     toute l'application.
--
--  ② MIGRATION 0177 — `trg_ventes_interdire_pressing` bloquait la vente dès
--     que l'ENTREPRISE possédait un espace pressing :
--         if entreprise_est_pressing(entreprise) then raise ...
--     Une boutique du même groupe ne pouvait donc plus vendre un seul
--     article : « VENTE_INTERDITE_PRESSING ».
--
--  ③ MIGRATION 0177 — `rpc_collaborateur_creer` / `_maj` attribuaient un
--     MÉTIER PRESSING (`caisse`, `atelier`…) selon l'entreprise, et
--     affectaient par défaut le collaborateur à l'espace PRESSING. Un
--     vendeur de boutique se retrouvait donc avec les écrans du pressing.
--
--  ④ `pressing_role()` (et donc toute la matrice de permissions) répondait
--     le métier pressing même quand l'espace de travail actif était une
--     boutique : les menus du pressing restaient visibles.
--
--  ════════════════════════════════════════════════════════════════════════
--  CE QUE FAIT CETTE MIGRATION
--  ════════════════════════════════════════════════════════════════════════
--  1. Des HELPERS qui répondent toujours par ESPACE :
--       `espace_type()`, `espace_est_pressing()`, `espace_utilise_pressing()`,
--       `mon_espace_actif()`, `contexte_pressing()`.
--  2. `pressing_role()` / `pressing_exige()` / `pressing_entreprise()` :
--     plus aucun métier pressing hors d'un espace pressing.
--  3. La garde de vente ne bloque QUE l'espace qui vend — une boutique du
--     même groupe vend normalement.
--  4. Deux triggers de cohérence :
--       • `utilisateurs` : pas de métier pressing sans espace pressing ;
--       • `ventes` : la garde corrigée.
--  5. Réparation des données :
--       • métiers pressing invalides effacés ;
--       • personnel pressing sans espace de travail replacé dans le pressing ;
--       • espaces typés `pressing` par erreur (0153) : quand un compte a
--         DEUX espaces « pressing » et qu'un seul vend réellement des
--         articles, celui-là redevient une `boutique`.
--  6. `rpc_collaborateur_creer` / `_maj` : l'ESPACE choisi décide du métier.
--  7. Vérifications : un tableau par entreprise / espace / compte.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. HELPERS — TOUJOURS PAR ESPACE
-- ============================================================================

-- 1.a Type normalisé d'un espace.
create or replace function public.espace_type(p_espace uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(btrim(coalesce(s.type, '')))
    from public.espaces s
   where s.id::text = p_espace::text;
$$;

comment on function public.espace_type(uuid) is
  'Correctif 180 — type normalisé d''un espace (boutique, pharmacie, pressing, hotel…).';

grant execute on function public.espace_type(uuid) to authenticated;


-- 1.b CET espace est-il un pressing ?
create or replace function public.espace_est_pressing(p_espace uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.espace_type(p_espace) = 'pressing', false);
$$;

comment on function public.espace_est_pressing(uuid) is
  'Correctif 180 — vrai si CET espace de travail est un pressing (et non si une entreprise en possède un).';

grant execute on function public.espace_est_pressing(uuid) to authenticated;


-- 1.c CET espace UTILISE-T-IL le pressing ?
--     Vrai si le type est « pressing », ou si le profil de modules de ce
--     type contient les dépôts pressing (boutique qui a activé le module).
create or replace function public.espace_utilise_pressing(p_espace uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    public.espace_type(p_espace) = 'pressing'
    or exists (
      select 1
        from public.types_espaces_modules t
       where t.type = coalesce(nullif(public.espace_type(p_espace), ''), 'boutique')
         and t.actif
         and jsonb_typeof(t.modules) = 'array'
         and t.modules @> '["press_depots"]'::jsonb
    ),
    false
  );
$$;

comment on function public.espace_utilise_pressing(uuid) is
  'Correctif 180 — vrai si CET espace travaille avec le module pressing (type pressing, ou profil de modules contenant les dépôts).';

grant execute on function public.espace_utilise_pressing(uuid) to authenticated;


-- 1.d Quel est l'ESPACE DE TRAVAIL actif de l'utilisateur connecté ?
--     Même résolution que `rpc_mes_modules()` : espace actif explicite,
--     sinon première espace de son entreprise (jamais l'entreprise entière).
create or replace function public.mon_espace_actif()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- 1. l'espace de travail renvoyé par le module 15 (si c'en est un)
    (select s.id
       from public.espaces s
      where s.id::text = public.mon_proprietaire()::text
        and coalesce(s.actif, true)
      limit 1),
    -- 2. l'espace explicitement actif de l'utilisateur
    (select s.id
       from public.utilisateurs u
       join public.espaces s on s.id = u.espace_actif_id
      where u.id = auth.uid()
        and coalesce(s.actif, true)
      limit 1),
    -- 3. repli identique au profil de modules : première espace de l'entreprise
    (select s.id
       from public.utilisateurs u
       join public.espaces s on s.entreprise_id = u.entreprise_id
      where u.id = auth.uid()
        and coalesce(s.actif, true)
      order by s.created_at nulls last, s.nom
      limit 1)
  );
$$;

comment on function public.mon_espace_actif() is
  'Correctif 180 — espace de travail réellement actif de l''utilisateur (jamais l''entreprise entière).';

grant execute on function public.mon_espace_actif() to authenticated;


-- 1.e LE CONTEXTE PRESSING — la seule source de vérité.
create or replace function public.contexte_pressing()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_espace uuid := public.mon_espace_actif();
  v_type   text := public.espace_type(v_espace);
  v_ent    uuid;
  v_actif  boolean := false;
  v_role   text := 'aucun';
  v_metier text;
begin
  if v_espace is not null then
    select s.entreprise_id into v_ent
      from public.espaces s
     where s.id = v_espace;

    v_actif := public.espace_utilise_pressing(v_espace);
  end if;

  if v_actif then
    -- Le propriétaire de l'entreprise est propriétaire du pressing.
    if exists (
      select 1 from public.entreprises e
       where e.id = v_ent
         and e.owner_id = auth.uid()
    ) then
      v_role := 'proprietaire';
    else
      select lower(btrim(coalesce(u.role_pressing, ''))) into v_metier
        from public.utilisateurs u
       where u.id = auth.uid();
      v_role := coalesce(nullif(v_metier, ''), 'aucun');
    end if;
  end if;

  return jsonb_build_object(
    'actif',        v_actif,
    'role',         v_role,
    'espace_id',    v_espace,
    'espace_type',  v_type,
    'entreprise_id', v_ent,
    -- Conservé pour les diagnostics : l'entreprise possède-t-elle un pressing ?
    'entreprise_possede_pressing', public.entreprise_est_pressing(v_ent)
  );
end;
$$;

comment on function public.contexte_pressing() is
  'Correctif 180 — contexte pressing de l''ESPACE DE TRAVAIL : actif, rôle métier, espace et entreprise. Hors d''un espace pressing, actif = false et rôle = aucun.';

grant execute on function public.contexte_pressing() to authenticated;


-- 1.f Droits : aucune de ces fonctions n'est ouverte au public anonyme.
revoke all on function public.espace_type(uuid) from public, anon;
revoke all on function public.espace_est_pressing(uuid) from public, anon;
revoke all on function public.espace_utilise_pressing(uuid) from public, anon;
revoke all on function public.mon_espace_actif() from public, anon;
revoke all on function public.contexte_pressing() from public, anon;

grant execute on function public.espace_type(uuid) to authenticated;
grant execute on function public.espace_est_pressing(uuid) to authenticated;
grant execute on function public.espace_utilise_pressing(uuid) to authenticated;
grant execute on function public.mon_espace_actif() to authenticated;
grant execute on function public.contexte_pressing() to authenticated;


-- ============================================================================
--  2. LE PRESSING NE DÉBORDE PLUS DE SON ESPACE
-- ============================================================================

-- 2.a Métier pressing du compte connecté (réponse « aucun » hors pressing).
create or replace function public.pressing_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.contexte_pressing() ->> 'role', 'aucun');
$$;

comment on function public.pressing_role() is
  'Module 35 + correctif 180 — métier du compte dans SON ESPACE DE TRAVAIL : proprietaire, responsable, accueil, atelier, caisse ou aucun (aucun hors d''un espace pressing).';

revoke all on function public.pressing_role() from public, anon;
grant execute on function public.pressing_role() to authenticated;


-- 2.b Contrôle d'accès par métier — refuse aussi hors d'un espace pressing.
create or replace function public.pressing_exige(p_roles text[])
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ctx  jsonb := public.contexte_pressing();
  v_role text  := coalesce(public.contexte_pressing() ->> 'role', 'aucun');
begin
  v_role := coalesce(v_ctx ->> 'role', 'aucun');
  -- 🚫 L'espace de travail est connu ET ce n'est pas un pressing : refus.
  --    (Un espace inconnu reste toléré : on n'enferme personne.)
  if coalesce(v_ctx ->> 'espace_id', '') <> ''
     and not coalesce((v_ctx ->> 'actif')::boolean, false) then
    raise exception
      'PRESSING_INACTIF|Votre espace de travail actuel n''est pas un pressing. Choisissez l''espace Pressing pour utiliser cet écran.';
  end if;

  -- Le propriétaire passe toujours ; un compte sans métier garde ses droits.
  if v_role in ('proprietaire', 'aucun') then
    return;
  end if;

  if p_roles is null or not (v_role = any (p_roles)) then
    raise exception
      'ROLE_PRESSING_REFUSE|Votre métier dans le pressing (%) ne permet pas cette action.',
      v_role;
  end if;
end;
$$;

comment on function public.pressing_exige(text[]) is
  'Module 35 + correctif 180 — refuse l''action hors d''un espace pressing, ou si le métier du collaborateur n''est pas dans la liste (le patron passe toujours).';

revoke all on function public.pressing_exige(text[]) from public, anon;
grant execute on function public.pressing_exige(text[]) to authenticated;


-- 2.c Entreprise du pressing = celle de l'ESPACE de travail.
create or replace function public.pressing_entreprise()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(public.contexte_pressing() ->> 'entreprise_id', '')::uuid,
    public.mon_entreprise_id(),
    public.mon_proprietaire(),
    auth.uid()
  );
$$;

comment on function public.pressing_entreprise() is
  'Module 35 + correctif 180 — entreprise de l''ESPACE DE TRAVAIL, utilisée par les tables du pressing.';

revoke all on function public.pressing_entreprise() from public, anon;
grant execute on function public.pressing_entreprise() to authenticated;


-- ============================================================================
--  3. LA GARDE DE VENTE NE VISE QUE L'ESPACE QUI VEND
-- ============================================================================
--  Avant : dès que l'ENTREPRISE possédait un pressing, TOUTES ses ventes
--  étaient refusées — y compris celles de la boutique du même groupe.
--  Désormais : seule une vente enregistrée DANS un espace pressing est
--  refusée.

create or replace function public.trg_ventes_interdire_pressing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_espace uuid;
begin
  -- 1. Cas normal : `owner_id` porte l'ESPACE de travail.
  select s.id into v_espace
    from public.espaces s
   where s.id::text = new.owner_id::text
   limit 1;

  -- 2. `owner_id` porte un UTILISATEUR : on regarde son espace de travail.
  if v_espace is null then
    select u.espace_actif_id into v_espace
      from public.utilisateurs u
     where u.id::text = new.owner_id::text
       and u.espace_actif_id is not null
     limit 1;
  end if;

  -- 3. Aucun espace identifié (comptes historiques) : on ne bloque pas.
  --    Les écrans restent protégés côté application.
  if public.espace_est_pressing(v_espace) then
    raise exception
      'VENTE_INTERDITE_PRESSING|Cet espace de travail est un pressing : enregistrez un dépôt, pas une vente d''article.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ventes_interdire_pressing on public.ventes;
create trigger trg_ventes_interdire_pressing
  before insert on public.ventes
  for each row execute function public.trg_ventes_interdire_pressing();

comment on function public.trg_ventes_interdire_pressing() is
  '0177 + correctif 180 — bloque les ventes d''articles dans un ESPACE pressing (une boutique du même groupe vend normalement).';


-- ============================================================================
--  4. COHÉRENCE PERMANENTE : MÉTIER PRESSING ⇔ ESPACE PRESSING
-- ============================================================================

-- 4.a Un compte ne peut pas garder un métier pressing s'il travaille ailleurs.
create or replace function public.trg_utilisateurs_metier_pressing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text;
begin
  if new.espace_actif_id is not null then
    v_type := public.espace_type(new.espace_actif_id);

    if v_type is not null and v_type <> 'pressing' then
      -- 🔒 Un vendeur de boutique n'est pas « caisse » d'un pressing.
      new.role_pressing := null;
      new.press_actif   := false;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_utilisateurs_metier_pressing on public.utilisateurs;
create trigger trg_utilisateurs_metier_pressing
  before insert or update of espace_actif_id, role_pressing on public.utilisateurs
  for each row execute function public.trg_utilisateurs_metier_pressing();

comment on function public.trg_utilisateurs_metier_pressing() is
  'Correctif 180 — un compte dont l''espace de travail n''est pas un pressing ne peut pas conserver un métier pressing.';


-- 4.b Réparation : métiers pressing invalides (espace non pressing).
update public.utilisateurs u
   set role_pressing = null,
       press_actif   = false
 where u.role_pressing is not null
   and u.espace_actif_id is not null
   and not public.espace_est_pressing(u.espace_actif_id);

-- 4.c Réparation : personnel pressing sans espace de travail → l'espace pressing.
update public.utilisateurs u
   set espace_actif_id = (
         select s.id
           from public.espaces s
          where s.entreprise_id = u.entreprise_id
            and lower(btrim(coalesce(s.type, ''))) = 'pressing'
          order by s.created_at nulls last, s.nom
          limit 1)
 where u.espace_actif_id is null
   and u.role_pressing is not null
   and u.entreprise_id is not null
   and exists (
         select 1 from public.espaces s2
          where s2.entreprise_id = u.entreprise_id
            and lower(btrim(coalesce(s2.type, ''))) = 'pressing');


-- 4.d Réparation des espaces mal typés par la migration 0153.
--     Règle volontairement étroite : un compte avec EXACTEMENT DEUX espaces
--     typés « pressing », dont UN SEUL a réellement enregistré des ventes
--     d'articles → cet espace redevient une « boutique ». Aucune autre
--     situation n'est touchée.
do $$
declare
  v_ent   uuid;
  v_a     uuid;
  v_b     uuid;
  v_va    bigint;
  v_vb    bigint;
  v_nom   text;
begin
  for v_ent in
    select s.entreprise_id
      from public.espaces s
     where lower(btrim(coalesce(s.type, ''))) = 'pressing'
     group by s.entreprise_id
    having count(*) = 2
  loop
    select min(s.id::text)::uuid, max(s.id::text)::uuid into v_a, v_b
      from public.espaces s
     where s.entreprise_id = v_ent
       and lower(btrim(coalesce(s.type, ''))) = 'pressing';

    select count(*) into v_va from public.ventes v where v.owner_id::text = v_a::text;
    select count(*) into v_vb from public.ventes v where v.owner_id::text = v_b::text;

    -- Il faut un seul espace « qui vend des articles » et l'autre silencieux.
    continue when not ((v_va > 0 and v_vb = 0) or (v_vb > 0 and v_va = 0));

    declare
      v_cible uuid := case when v_va > 0 then v_a else v_b end;
    begin
      select s.nom into v_nom from public.espaces s where s.id = v_cible;

      -- 🔎 Sécurité : cet espace ne doit pas être l'espace de travail des
      -- comptes ayant un métier pressing (ce serait le vrai pressing).
      if exists (
        select 1 from public.utilisateurs u
         where u.espace_actif_id = v_cible
           and u.role_pressing is not null
      ) then
        raise notice
          'CORRECTIF 180 — espace « % » laissé en pressing : il est l''espace de travail de comptes pressing.',
          v_nom;
        continue;
      end if;

      update public.espaces
         set type = 'boutique'
       where id = v_cible;

      raise notice
        'CORRECTIF 180 — espace « % » retypé en boutique (il enregistre des ventes d''articles, pas des dépôts).',
        v_nom;
    end;
  end loop;
end $$;


-- ============================================================================
--  5. COLLABORATEURS : L'ESPACE CHOISI DÉCIDE DU MÉTIER
-- ============================================================================

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
  v_ent     uuid;
  v_pressing boolean := false;
  v_metier_pressing text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer un collaborateur.';
  end if;

  v_owner := coalesce(public.mon_patron(), v_user);

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

  select u.entreprise_id into v_ent
    from public.utilisateurs u where u.id = v_owner;

  -- 🧭 CORRECTIF 180 — L'ESPACE DÉCIDE, PAS L'ENTREPRISE.
  --    Ordre : espace demandé → espace où le PATRON travaille en ce moment
  --    → espace par défaut de son entreprise. Plus jamais « le pressing »
  --    par défaut : un vendeur de boutique restait enfermé dans le pressing.
  v_espace := coalesce(
    public.espace_collaborateur_valide(v_owner, p_espace_id),
    public.mon_espace_actif(),
    public.espace_collaborateur_valide(v_owner, null)
  );

  v_pressing := public.espace_est_pressing(v_espace);

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

  v_metier_pressing := case
                         when not v_pressing then null
                         when v_role = 'PROPRIETAIRE' then 'responsable'
                         when v_role = 'MAGASINIER'   then 'atelier'
                         when v_role = 'VENDEUR'      then 'caisse'
                         else null
                       end;

  update public.utilisateurs
     set nom             = v_nom,
         prenom          = v_prenom,
         email           = v_email,
         telephone       = coalesce(v_tel, telephone),
         role            = 'collaborator',
         new_role        = coalesce(v_role_enum, public.role_enum('VENDEUR')),
         valide          = 1,
         parent_id       = v_owner,
         entreprise_id   = coalesce(v_ent, entreprise_id),
         espace_actif_id = coalesce(v_espace, espace_actif_id),
         -- 🧺 Métier pressing UNIQUEMENT si l'espace choisi est un pressing.
         role_pressing   = coalesce(role_pressing, v_metier_pressing),
         press_actif     = case when v_pressing then true else false end
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
      'espace',    v_espace,
      'espace_type', public.espace_type(v_espace),
      'pressing',  v_pressing,
      'role_pressing', v_metier_pressing
    ),
    now()
  );

  return jsonb_build_object(
    'ok',       true,
    'id',       v_cible,
    'email',    v_email,
    'role',     v_role,
    'nom',      v_nom_complet,
    'espace_id', v_espace,
    'role_pressing', v_metier_pressing
  );
end;
$$;

comment on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid) is
  '0177 + correctif 180 — crée un collaborateur dans l''espace choisi (ou celui du patron) ; métier pressing seulement si CET espace est un pressing.';

revoke all on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid)
  from public, anon;
grant execute on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid)
  to authenticated;


create or replace function public.rpc_collaborateur_maj(
  p_id           uuid,
  p_nom          text,
  p_prenom       text,
  p_telephone    text,
  p_role         text,
  p_actif        boolean default true,
  p_mot_de_passe text default null,
  p_espace_id    uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_role     text := upper(btrim(coalesce(p_role, '')));
  v_espace   uuid;
  v_ent      uuid;
  v_pressing boolean := false;
  v_metier   text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_owner := coalesce(public.mon_patron(), v_user);

  if not (v_user = v_owner or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut modifier un collaborateur.';
  end if;

  if not exists (
    select 1 from public.utilisateurs u
     where u.id = p_id and u.parent_id = v_owner
  ) then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''appartient pas à votre entreprise.';
  end if;

  if p_id = v_user then
    raise exception 'ACTION_INTERDITE|Vous ne pouvez pas modifier votre propre compte par cet écran.';
  end if;

  if not (v_role = any (public.roles_entreprise_attribuables())) then
    raise exception 'ROLE_INVALIDE|Rôle inconnu.';
  end if;

  -- 🧭 CORRECTIF 180 — l'espace du collaborateur décide de son métier.
  v_espace := coalesce(
    public.espace_collaborateur_valide(v_owner, p_espace_id),
    (select u.espace_actif_id from public.utilisateurs u where u.id = p_id),
    public.mon_espace_actif()
  );

  v_pressing := public.espace_est_pressing(v_espace);

  v_metier := case
                when not v_pressing then null
                when v_role = 'PROPRIETAIRE' then 'responsable'
                when v_role = 'MAGASINIER'   then 'atelier'
                when v_role = 'VENDEUR'      then 'caisse'
                else null
              end;

  select u.entreprise_id into v_ent
    from public.utilisateurs u where u.id = v_owner;

  update public.utilisateurs
     set nom       = coalesce(nullif(btrim(coalesce(p_nom, '')), ''), nom),
         prenom    = coalesce(btrim(coalesce(p_prenom, '')), prenom),
         telephone = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''), telephone),
         new_role  = coalesce(public.role_enum(v_role), new_role),
         valide    = case when coalesce(p_actif, true) then 1 else 0 end,
         espace_actif_id = coalesce(v_espace, espace_actif_id),
         -- 🧺 Hors pressing : le métier pressing est retiré (plus de menus
         --    Dépôts/Atelier/Retraits dans une boutique).
         role_pressing = case
                           when v_espace is null then role_pressing
                           when v_pressing then coalesce(role_pressing, v_metier)
                           else null
                         end,
         press_actif = case
                         when v_espace is null then press_actif
                         else v_pressing
                       end
   where id = p_id;

  if p_mot_de_passe is not null and length(p_mot_de_passe) >= 8 then
    update auth.users
       set encrypted_password = crypt(p_mot_de_passe, gen_salt('bf')),
           updated_at         = now()
     where id = p_id;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COLLABORATEUR_MAJ', p_id,
    jsonb_build_object('role', v_role, 'actif', p_actif, 'par', v_user,
                       'boutique', v_owner, 'espace', v_espace,
                       'espace_type', public.espace_type(v_espace),
                       'pressing', v_pressing),
    now()
  );

  return jsonb_build_object(
    'ok', true, 'id', p_id, 'role', v_role, 'espace_id', v_espace,
    'role_pressing', case when v_pressing then v_metier else null end);
end;
$$;

comment on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid) is
  '0177 + correctif 180 — modifie un collaborateur ; le métier pressing suit l''ESPACE de travail choisi.';

revoke all on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid)
  from public, anon;
grant execute on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid)
  to authenticated;


-- ============================================================================
--  6. VÉRIFICATIONS
-- ============================================================================

-- 6.a Le tableau des espaces : type, activité réelle sur 30 jours.
select e.nom                      as entreprise,
       s.nom                      as espace,
       coalesce(s.type, '(vide)') as type,
       coalesce(s.actif, true)    as actif,
       (select count(*) from public.ventes v
         where v.owner_id::text = s.id::text
           and (v.date::timestamptz at time zone 'Africa/Lubumbashi')
                 >= ((now() at time zone 'Africa/Lubumbashi')::date - 30)::timestamp) as ventes_articles_30j,
       public.espace_est_pressing(s.id) as est_pressing
  from public.espaces s
  join public.entreprises e on e.id = s.entreprise_id
 order by e.nom, s.nom;

-- 6.b Les comptes qui portent un métier pressing : leur espace doit être un
--     pressing. Toute ligne `est_pressing = false` est une incohérence
--     (elle est réparée par la section 4, et empêchée par le trigger).
select u.email,
       coalesce(u.new_role::text, u.role) as role,
       u.role_pressing,
       s.nom                              as espace,
       coalesce(s.type, '(aucun)')        as type_espace,
       public.espace_est_pressing(s.id)   as est_pressing
  from public.utilisateurs u
  left join public.espaces s on s.id = u.espace_actif_id
 where u.role_pressing is not null
 order by est_pressing, u.email;

-- 6.c Contexte de la session courante (si connecté).
do $$
declare
  v_ctx jsonb;
begin
  if auth.uid() is null then
    raise notice 'CORRECTIF 180 — contexte non calculé (aucune session connectée dans l''éditeur SQL).';
    return;
  end if;

  v_ctx := public.contexte_pressing();
  raise notice 'CORRECTIF 180 — contexte : %', jsonb_pretty(v_ctx);
end $$;

-- 6.d Les triggers de cohérence sont-ils en place ?
select c.relname        as table,
       t.tgname         as trigger,
       p.proname        as fonction
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_proc  p on p.oid = t.tgfoid
 where not t.tgisinternal
   and t.tgname in ('trg_ventes_interdire_pressing',
                    'trg_utilisateurs_metier_pressing')
 order by c.relname;
