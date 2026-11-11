-- ============================================================================
--  biashara_yangu — MIGRATION 0140 : LE PROPRIÉTAIRE CRÉE SES COMPTES
--
--  DEMANDE
--    « Le propriétaire doit pouvoir créer les comptes de ses collaborateurs
--      sans passer par un code d'invitation — directement avec son entreprise
--      et le rôle. Comme la distribution et le pressing. »
--
--  POURQUOI LE CODE D'INVITATION DISPARAÎT
--    Jusqu'ici, la seule façon d'ajouter un vendeur était de lui donner le
--    « code boutique » (l'identifiant du patron) et de le laisser s'inscrire
--    lui-même. Trois défauts :
--      1. le patron ne crée rien : il attend que l'autre s'inscrive ;
--      2. le code est l'identifiant interne du patron — le partager, c'est
--         livrer une clé ;
--      3. l'inscription passait par `auth.signUp` côté application : la
--         session du PATRON était remplacée par celle du nouvel employé.
--
--  CE QUE FAIT CETTE MIGRATION (le même mécanisme que la distribution et le
--  pressing, déjà en production)
--    1. `rpc_collaborateur_creer` : le propriétaire saisit nom, prénom, e-mail,
--       téléphone, mot de passe et RÔLE → le serveur crée le VRAI compte Auth
--       (mot de passe haché) et la fiche rattachée à SON entreprise.
--    2. `rpc_collaborateurs_lister` : l'équipe de l'entreprise (rôle, état).
--    3. `rpc_collaborateur_maj` : changer le rôle, désactiver, réinitialiser
--       le mot de passe.
--
--  GARDE-FOUS
--    • seul le propriétaire (ou la plateforme) crée / modifie un collaborateur ;
--    • un rôle de la PLATEFORME (SUPER_ADMIN, GESTIONNAIRE, FINANCE, SUPPORT)
--      ne peut JAMAIS être attribué par une entreprise ;
--    • un collaborateur d'une autre entreprise est invisible et intouchable ;
--    • un compte ne peut pas se désactiver lui-même par cette voie.
--
--  Codes : SESSION_ABSENTE | DROIT_REFUSE | NOM_REQUIS | EMAIL_INVALIDE |
--          MOT_DE_PASSE_TROP_COURT | ROLE_INVALIDE | COMPTE_EXISTANT |
--          COLLABORATEUR_INTROUVABLE | ACTION_INTERDITE
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if to_regclass('public.utilisateurs') is null then
    raise exception 'Table public.utilisateurs introuvable : exécutez le module 4.';
  end if;
  if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                  where p.proname = 'creer_compte_plateforme' and n.nspname = 'public') then
    raise exception 'Fonction creer_compte_plateforme absente : exécutez 20260916000007.';
  end if;
end $$;


-- ============================================================================
--  1. RÔLES QU'UNE ENTREPRISE PEUT DONNER
-- ============================================================================
--  Volontairement FERMÉ : aucun rôle de plateforme ne figure ici.

create or replace function public.roles_entreprise_attribuables()
returns text[]
language sql
immutable
as $$
  select array['PROPRIETAIRE', 'VENDEUR', 'MAGASINIER', 'COMPTABLE_ENTREPRISE']::text[];
$$;

comment on function public.roles_entreprise_attribuables() is
  'Rôles d''entreprise qu''un propriétaire peut attribuer à un collaborateur (aucun rôle de plateforme).';


-- ============================================================================
--  2. CRÉER UN COLLABORATEUR (sans code d'invitation)
-- ============================================================================

create or replace function public.rpc_collaborateur_creer(
  p_nom          text,
  p_prenom       text,
  p_email        text,
  p_telephone    text,
  p_mot_de_passe text,
  p_role         text
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
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer un collaborateur.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- Seul le propriétaire de l'entreprise crée des comptes (ou la plateforme).
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
         -- ⚠️ `entreprise_id` doit être l'ENTREPRISE du patron (elle porte
         -- l'abonnement et cloisonne les données), jamais l'identifiant du
         -- patron : sinon les écrans liés (`espaces`, marketplace,
         -- abonnement, distribution…) ne retrouvent plus l'entreprise.
         entreprise_id   = coalesce(
                             (select u.entreprise_id
                                from public.utilisateurs u
                               where u.id = v_owner),
                             entreprise_id),
         -- L'espace par défaut porte l'UUID du patron : on ne l'écrit que si
         -- cet espace existe (la clé étrangère le vérifie).
         espace_actif_id = case
                             when exists (select 1 from public.espaces s
                                           where s.id = v_owner)
                             then v_owner
                             else espace_actif_id
                           end
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
      'boutique',  v_owner
    ),
    now()
  );

  return jsonb_build_object(
    'ok',    true,
    'id',    v_cible,
    'email', v_email,
    'role',  v_role,
    'nom',   v_nom_complet
  );
end;
$$;

comment on function public.rpc_collaborateur_creer(text, text, text, text, text, text) is
  'Crée le compte d''un collaborateur rattaché à l''entreprise du propriétaire, avec son rôle — sans code d''invitation.';

revoke all on function public.rpc_collaborateur_creer(text, text, text, text, text, text) from public, anon;
grant execute on function public.rpc_collaborateur_creer(text, text, text, text, text, text) to authenticated;


-- ============================================================================
--  3. LISTER L'ÉQUIPE
-- ============================================================================

create or replace function public.rpc_collaborateurs_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_lignes jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',        u.id,
           'nom',       coalesce(u.nom, ''),
           'prenom',    coalesce(u.prenom, ''),
           'email',     coalesce(u.email, ''),
           'telephone', coalesce(u.telephone, ''),
           'role',      coalesce(u.new_role::text, public.role_herite(u.role)),
           'actif',     coalesce(u.valide, 1) = 1
         ) order by coalesce(u.nom, ''), coalesce(u.prenom, '')), '[]'::jsonb)
    into v_lignes
    from public.utilisateurs u
   where u.parent_id::text = v_owner::text;

  return jsonb_build_object(
    'proprietaire_id', v_owner,
    'lignes', v_lignes
  );
end;
$$;

comment on function public.rpc_collaborateurs_lister() is
  'Liste les collaborateurs rattachés au propriétaire (rôle effectif et état du compte).';

revoke all on function public.rpc_collaborateurs_lister() from public, anon;
grant execute on function public.rpc_collaborateurs_lister() to authenticated;


-- ============================================================================
--  4. MODIFIER UN COLLABORATEUR
-- ============================================================================

create or replace function public.rpc_collaborateur_maj(
  p_id           uuid,
  p_nom          text,
  p_prenom       text,
  p_telephone    text,
  p_role         text,
  p_actif        boolean default true,
  p_mot_de_passe text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_role   text := upper(btrim(coalesce(p_role, '')));
  v_cible  public.utilisateurs%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not (v_user = v_owner or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut modifier un collaborateur.';
  end if;

  select * into v_cible
    from public.utilisateurs u
   where u.id = p_id and u.parent_id::text = v_owner::text;

  if not found then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''appartient pas à votre entreprise.';
  end if;

  if p_id = v_user then
    raise exception 'ACTION_INTERDITE|Vous ne pouvez pas modifier votre propre compte par cet écran.';
  end if;

  if not (v_role = any (public.roles_entreprise_attribuables())) then
    raise exception 'ROLE_INVALIDE|Rôle inconnu.';
  end if;

  update public.utilisateurs
     set nom       = coalesce(nullif(btrim(coalesce(p_nom, '')), ''), nom),
         prenom    = coalesce(btrim(coalesce(p_prenom, '')), prenom),
         telephone = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''), telephone),
         new_role  = coalesce(public.role_enum(v_role), new_role),
         valide    = case when coalesce(p_actif, true) then 1 else 0 end
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
                       'boutique', v_owner),
    now()
  );

  return jsonb_build_object('ok', true, 'id', p_id, 'role', v_role);
end;
$$;

comment on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text) is
  'Change le rôle, l''état ou le mot de passe d''un collaborateur de l''entreprise.';

revoke all on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text) from public, anon;
grant execute on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text) to authenticated;


-- ============================================================================
--  5. CONTRÔLE
-- ============================================================================

select 'MIGRATION 0140 PRÊTE' as controle,
       (select count(*) from public.utilisateurs where parent_id is not null)
         as collaborateurs_rattaches,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.proname = 'rpc_collaborateur_creer' and n.nspname = 'public')
         as rpc_creation_ok,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.proname = 'rpc_collaborateurs_lister' and n.nspname = 'public')
         as rpc_liste_ok;
