-- ============================================================================
--  biashara_yangu — MIGRATION 0143 : AFFECTER UN COLLABORATEUR À UNE BOUTIQUE
--
--  DEMANDE
--    Un propriétaire a deux ou trois boutiques sur le même compte. Il veut
--    décider **qui travaille où** : « Rachel à Portes Ouvertes, Abi à la
--    deuxième boutique ».
--
--  RAPPEL DU CLOISONNEMENT (migration 0019 + correctif applicatif)
--    • chaque ESPACE (`public.espaces`) = une boutique ;
--    • les données métier sont rattachées à l'espace actif :
--      `mon_proprietaire()` renvoie `utilisateurs.espace_actif_id` de
--      l'utilisateur connecté, avec repli sur l'UUID du patron ;
--    • l'espace par défaut porte l'UUID du patron (compatibilité totale).
--
--  CE QUE FAIT CE SCRIPT
--    1. `rpc_collaborateur_creer` accepte un espace : le collaborateur est
--       directement affecté à la boutique choisie.
--    2. `rpc_collaborateur_maj` permet de le déplacer d'une boutique à
--       l'autre (ou de le remettre sur la boutique principale).
--    3. `rpc_collaborateurs_lister` renvoie la boutique de chacun.
--
--  GARDE-FOUS
--    • l'espace choisi doit appartenir à l'ENTREPRISE du propriétaire et être
--      actif : on ne peut pas placer quelqu'un dans la boutique d'autrui ;
--    • un espace inconnu est ignoré (repli sur l'espace par défaut) ;
--    • le propriétaire reste seul à pouvoir affecter (comme le reste).
--
--  Codes : ESPACE_INVALIDE | DROIT_REFUSE | SESSION_ABSENTE (+ ceux de 0140)
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. CONTRÔLES
-- ============================================================================

do $$
begin
  if to_regclass('public.espaces') is null then
    raise exception 'Table public.espaces introuvable : exécutez le module 15.';
  end if;
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'utilisateurs'
       and column_name = 'espace_actif_id'
  ) then
    raise exception 'Colonne utilisateurs.espace_actif_id absente : exécutez le module 15.';
  end if;
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'rpc_collaborateur_creer'
  ) then
    raise exception 'Migration 0140 absente : exécutez 20260916000140_collaborateurs_sans_code.sql.';
  end if;
end $$;


-- ============================================================================
--  1. L'ESPACE D'UN COLLABORATEUR — VALIDÉ
-- ============================================================================
--  Renvoie l'espace demandé s'il appartient bien à l'entreprise du patron,
--  sinon l'espace par défaut (l'UUID du patron) s'il existe, sinon NULL
--  (le collaborateur suivra alors la boutique active du patron).

create or replace function public.espace_collaborateur_valide(
  p_owner  uuid,
  p_espace uuid
)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent uuid;
begin
  if p_owner is null then
    return null;
  end if;

  select u.entreprise_id into v_ent
    from public.utilisateurs u
   where u.id = p_owner;

  if p_espace is not null and v_ent is not null then
    if exists (
      select 1 from public.espaces s
       where s.id = p_espace
         and s.entreprise_id = v_ent
         and s.actif
    ) then
      return p_espace;
    end if;
  end if;

  -- Repli : l'espace par défaut (UUID du patron), s'il existe.
  if exists (select 1 from public.espaces s where s.id = p_owner) then
    return p_owner;
  end if;

  return null;
end;
$$;

comment on function public.espace_collaborateur_valide(uuid, uuid) is
  'Espace de travail d''un collaborateur : espace demandé s''il appartient à l''entreprise du patron, sinon l''espace par défaut.';

revoke all on function public.espace_collaborateur_valide(uuid, uuid) from public, anon;
grant execute on function public.espace_collaborateur_valide(uuid, uuid) to authenticated;


-- ============================================================================
--  2. CRÉER UN COLLABORATEUR DANS UNE BOUTIQUE
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
  'Crée le compte d''un collaborateur rattaché à l''entreprise du propriétaire, avec son rôle et sa boutique — sans code d''invitation.';

revoke all on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid) from public, anon;
grant execute on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid) to authenticated;


-- ============================================================================
--  3. LISTER L'ÉQUIPE AVEC SA BOUTIQUE
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
           'actif',     coalesce(u.valide, 1) = 1,
           'espace_id', u.espace_actif_id,
           'espace_nom', (select s.nom from public.espaces s
                           where s.id = u.espace_actif_id)
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
  'Liste les collaborateurs du propriétaire : rôle, état et boutique affectée.';

revoke all on function public.rpc_collaborateurs_lister() from public, anon;
grant execute on function public.rpc_collaborateurs_lister() to authenticated;


-- ============================================================================
--  4. DÉPLACER UN COLLABORATEUR D'UNE BOUTIQUE À L'AUTRE
-- ============================================================================

drop function if exists public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text);

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
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_role   text := upper(btrim(coalesce(p_role, '')));
  v_espace uuid;
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

  if not exists (
    select 1 from public.utilisateurs u
     where u.id = p_id and u.parent_id::text = v_owner::text
  ) then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''appartient pas à votre entreprise.';
  end if;

  if p_id = v_user then
    raise exception 'ACTION_INTERDITE|Vous ne pouvez pas modifier votre propre compte par cet écran.';
  end if;

  if not (v_role = any (public.roles_entreprise_attribuables())) then
    raise exception 'ROLE_INVALIDE|Rôle inconnu.';
  end if;

  -- Espace demandé (validé) ; `null` = on ne change pas la boutique.
  if p_espace_id is not null then
    v_espace := public.espace_collaborateur_valide(v_owner, p_espace_id);
  end if;

  update public.utilisateurs
     set nom       = coalesce(nullif(btrim(coalesce(p_nom, '')), ''), nom),
         prenom    = coalesce(btrim(coalesce(p_prenom, '')), prenom),
         telephone = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''), telephone),
         new_role  = coalesce(public.role_enum(v_role), new_role),
         valide    = case when coalesce(p_actif, true) then 1 else 0 end,
         espace_actif_id = coalesce(v_espace, espace_actif_id)
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
                       'boutique', v_owner, 'espace', v_espace),
    now()
  );

  return jsonb_build_object(
    'ok', true, 'id', p_id, 'role', v_role, 'espace_id', v_espace);
end;
$$;

comment on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid) is
  'Change le rôle, l''état, le mot de passe ou la BOUTIQUE d''un collaborateur de l''entreprise.';

revoke all on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid) from public, anon;
grant execute on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid) to authenticated;


-- ============================================================================
--  5. CONTRÔLE
-- ============================================================================

select 'MIGRATION 0143 PRÊTE' as controle,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public'
                  and p.proname = 'rpc_collaborateur_creer'
                  and pg_get_function_identity_arguments(p.oid) like '%uuid')
         as creation_avec_espace,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public'
                  and p.proname = 'rpc_collaborateur_maj'
                  and pg_get_function_identity_arguments(p.oid) like '%uuid, uuid%')
         as maj_avec_espace,
       (select count(*) from public.utilisateurs u
         where u.parent_id is not null and u.espace_actif_id is not null)
         as collaborateurs_affectes;

-- Détail : qui travaille dans quelle boutique.
select coalesce(p.nom, '(patron inconnu)') as patron,
       coalesce(u.nom, '') || ' ' || coalesce(u.prenom, '') as collaborateur,
       u.email,
       coalesce(u.new_role::text, u.role) as role,
       coalesce(s.nom, '(boutique par défaut)') as boutique
  from public.utilisateurs u
  left join public.utilisateurs p on p.id = u.parent_id
  left join public.espaces s on s.id = u.espace_actif_id
 where u.parent_id is not null
 order by p.nom nulls last, u.nom;
