-- ============================================================================
--  biashara_yangu — CORRECTIF 177
--  ÉQUIPE (bon espace, bon rôle), ANALYSE TOUS MÉTIERS, QR PAR BOUTIQUE
--
--  PROBLÈMES CONSTATÉS (20/11/2026, tests client)
--  ---------------------------------------------
--  P1. « Un collaborateur créé dans le pressing n'est pas dans son espace :
--      il n'y a que la caisse. »
--      → trois causes cumulées :
--        (a) `rpc_collaborateurs_lister` et `rpc_collaborateur_maj` filtrent
--            sur `parent_id = mon_proprietaire()`. Or `mon_proprietaire()`
--            renvoie l'UUID de l'ESPACE, pas celui du patron : dès que le
--            patron a plusieurs entreprises, la liste de son équipe est
--            VIDE et toute modification échoue ;
--        (b) `espace_collaborateur_valide()` retombe sur « l'espace dont
--            l'id = patron », c'est-à-dire l'espace de la PREMIÈRE entreprise :
--            un collaborateur créé pour une autre entreprise atterrit dans la
--            mauvaise boutique, donc avec les mauvais modules (caisse seule
--            du profil boutique) ;
--        (c) la création générique (`rpc_collaborateur_creer`) ne renseigne
--            pas `role_pressing` : le collaborateur n'a aucun rôle métier
--            dans le pressing, quel que soit son rôle d'entreprise.
--
--  P2. « Analyse des ventes : impossible de produire le rapport pour le
--      moment » — pour un PRESSING.
--      → `rpc_rapport_entreprise_analyse` (0175) ne lisait que la table
--        `ventes`. Un pressing vend des PRESTATIONS (`pressing_lignes`) :
--        sa table `ventes` est vide. En plus, le rapport utilisait une TABLE
--        TEMPORAIRE (refusée sur certains rôles/transactions) et la requête
--        ne renvoyait que les 10 premiers produits.
--
--  P3. « Le rapport doit être pour TOUS les produits, par meilleure vente. »
--      → la limite `limit 10` est retirée ; le rapport classe TOUS les
--        produits du mieux vendu au moins vendu.
--
--  P4. « Le QR code doit compter tout ce qui a déjà été produit par chaque
--      boutique. »
--      → les compteurs ne regardaient que les émissions facturées depuis
--        0175. On ajoute le nombre de QR codes RÉELLEMENT existants
--        (un par article + un par emballage) et la répartition PAR BOUTIQUE.
--
--  ⚠️ AUCUNE donnée n'est supprimée. Les réparations ne remplissent que des
--     champs vides ou manifestement faux (`espace_actif_id` hors entreprise,
--     `role_pressing` absent pour un compte de pressing).
--
--  PRÉREQUIS : 0174, 0175 et 0176 exécutées.
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ===========================================================================
--  0. NETTOYAGE DES SURCHARGES HISTORIQUES
-- ===========================================================================
--  Les migrations 0140 (sans `p_espace_id`) et 0143/0157 (avec `p_espace_id`
--  par défaut) ont laissé DEUX fonctions du même nom. PostgREST peut alors
--  répondre « function is not unique » (PGRST203)… ou appeler l'ANCIENNE, qui
--  n'a pas la correction de portée. On supprime les versions sans
--  `p_espace_id` : un seul comportement possible.

do $$
declare
  v_signature text;
begin
  for v_signature in
    select format('public.%I(%s)',
                  p.proname,
                  pg_get_function_identity_arguments(p.oid))
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname in ('rpc_collaborateur_creer', 'rpc_collaborateur_maj')
       and pg_get_function_identity_arguments(p.oid) not like '%p_espace_id%'
  loop
    raise notice '0177 — suppression de la surcharge historique %', v_signature;
    execute 'drop function if exists ' || v_signature;
  end loop;
end $$;


-- ===========================================================================
--  1. ESPACE DE TRAVAIL D'UN COLLABORATEUR — LE BON PAR DÉFAUT
-- ===========================================================================
--  Avant : « l'espace dont l'id est celui du patron » = première entreprise.
--  Après :
--    1. l'espace demandé, s'il appartient bien à l'entreprise du patron ;
--    2. l'espace ACTIF du patron, s'il appartient à cette entreprise ;
--    3. le premier espace actif de l'entreprise (du plus ancien au plus
--       récent) — jamais celui d'une autre entreprise ;
--    4. compatibilité historique : l'espace dont l'id = patron.

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
  v_ent    uuid;
  v_actif  uuid;
begin
  if p_owner is null then
    return null;
  end if;

  select u.entreprise_id, u.espace_actif_id
    into v_ent, v_actif
    from public.utilisateurs u
   where u.id = p_owner;

  -- 1. L'espace demandé, s'il est dans l'entreprise du patron.
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

  if v_ent is not null then
    -- 2. L'espace de travail actuel du patron, s'il est dans SON entreprise.
    if v_actif is not null and exists (
      select 1 from public.espaces s
       where s.id = v_actif
         and s.entreprise_id = v_ent
         and s.actif
    ) then
      return v_actif;
    end if;

    -- 3. Le premier espace actif de l'entreprise.
    select s.id into v_actif
      from public.espaces s
     where s.entreprise_id = v_ent
       and s.actif
     order by s.created_at nulls last, s.nom
     limit 1;

    if v_actif is not null then
      return v_actif;
    end if;
  end if;

  -- 4. Compatibilité historique (l'espace porte l'id du patron).
  if exists (select 1 from public.espaces s where s.id = p_owner) then
    return p_owner;
  end if;

  return null;
end;
$$;

comment on function public.espace_collaborateur_valide(uuid, uuid) is
  '0177 — espace de travail d''un collaborateur : espace demandé, sinon espace actif du patron, sinon premier espace actif de SON entreprise (jamais celui d''une autre entreprise).';

revoke all on function public.espace_collaborateur_valide(uuid, uuid)
  from public, anon;
grant execute on function public.espace_collaborateur_valide(uuid, uuid)
  to authenticated;


-- ===========================================================================
--  2. HELPER — L'ENTREPRISE EST-ELLE UN PRESSING ?
-- ===========================================================================

create or replace function public.entreprise_est_pressing(p_entreprise uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    exists (
      select 1 from public.espaces s
       where s.entreprise_id = p_entreprise
         and lower(btrim(coalesce(s.type, ''))) = 'pressing'
    ),
    false
  );
$$;

comment on function public.entreprise_est_pressing(uuid) is
  '0177 — vrai si l''entreprise possède au moins un espace de type « pressing ».';

revoke all on function public.entreprise_est_pressing(uuid) from public, anon;
grant execute on function public.entreprise_est_pressing(uuid)
  to authenticated;


-- ===========================================================================
--  3. LISTE DE L'ÉQUIPE — LE PATRON, PAS L'ESPACE
-- ===========================================================================
--  `mon_proprietaire()` = UUID d'ESPACE : l'utiliser comme `parent_id`
--  renvoyait toujours une liste vide pour un patron multi-entreprises.

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

  -- ✅ LE PATRON (utilisateurs.id), jamais l'espace.
  v_owner := coalesce(public.mon_patron(), v_user);

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',           u.id,
           'nom',          coalesce(u.nom, ''),
           'prenom',       coalesce(u.prenom, ''),
           'email',        coalesce(u.email, ''),
           'telephone',    coalesce(u.telephone, ''),
           'role',         coalesce(u.new_role::text, public.role_herite(u.role)),
           'actif',        coalesce(u.valide, 1) = 1,
           'espace_id',    u.espace_actif_id,
           'role_pressing', u.role_pressing
         ) order by coalesce(u.nom, ''), coalesce(u.prenom, '')), '[]'::jsonb)
    into v_lignes
    from public.utilisateurs u
   where u.parent_id = v_owner;

  return jsonb_build_object(
    'proprietaire_id', v_owner,
    'lignes', v_lignes
  );
end;
$$;

comment on function public.rpc_collaborateurs_lister() is
  '0177 — équipe du patron : filtre sur mon_patron() (et non mon_proprietaire(), qui renvoyait l''espace et donc une liste vide).';

revoke all on function public.rpc_collaborateurs_lister() from public, anon;
grant execute on function public.rpc_collaborateurs_lister() to authenticated;


-- ===========================================================================
--  4. MODIFIER UN COLLABORATEUR — PATRON + RÔLE MÉTIER
-- ===========================================================================

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
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  -- ✅ LE PATRON (utilisateurs.id) : `mon_proprietaire()` renvoie un ESPACE et
  --    faisait échouer la modification dès la deuxième entreprise.
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

  -- Espace demandé (validé) ; `null` = on ne change pas la boutique.
  if p_espace_id is not null then
    v_espace := public.espace_collaborateur_valide(v_owner, p_espace_id);
  end if;

  select u.entreprise_id into v_ent
    from public.utilisateurs u where u.id = v_owner;
  if v_ent is not null then
    v_pressing := public.entreprise_est_pressing(v_ent);
  end if;

  update public.utilisateurs
     set nom       = coalesce(nullif(btrim(coalesce(p_nom, '')), ''), nom),
         prenom    = coalesce(btrim(coalesce(p_prenom, '')), prenom),
         telephone = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''), telephone),
         new_role  = coalesce(public.role_enum(v_role), new_role),
         valide    = case when coalesce(p_actif, true) then 1 else 0 end,
         espace_actif_id = coalesce(v_espace, espace_actif_id),
         -- 🧺 Si le compte n'a pas encore de métier pressing, on le déduit du
         --    rôle choisi : le collaborateur joue alors son rôle DANS le
         --    pressing (accueil, atelier ou caisse) et non plus « aucun ».
         role_pressing = coalesce(
                           role_pressing,
                           case
                             when not v_pressing then null
                             when v_role = 'PROPRIETAIRE' then 'responsable'
                             when v_role = 'MAGASINIER'   then 'atelier'
                             when v_role = 'VENDEUR'      then 'caisse'
                             else null
                           end),
         press_actif = case when v_pressing then true else press_actif end
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
                       'pressing', v_pressing),
    now()
  );

  return jsonb_build_object(
    'ok', true, 'id', p_id, 'role', v_role, 'espace_id', v_espace);
end;
$$;

comment on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid) is
  '0177 — modification d''un collaborateur : portée mon_patron() (et non l''espace), rôle pressing déduit du rôle d''entreprise quand il manque.';

revoke all on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid)
  from public, anon;
grant execute on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid)
  to authenticated;


-- ===========================================================================
--  5. SUPPRIMER UN COLLABORATEUR — MÊME CORRECTION DE PORTÉE (0176)
-- ===========================================================================

create or replace function public.rpc_collaborateur_supprimer(
  p_id           uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_cible public.utilisateurs%rowtype;
  v_auth  boolean := false;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if p_id is null then
    raise exception 'COLLABORATEUR_INTROUVABLE|Aucun collaborateur choisi.';
  end if;

  v_owner := coalesce(public.mon_patron(), v_user);
  if not (v_user = v_owner or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut supprimer un collaborateur.';
  end if;

  if upper(btrim(coalesce(p_confirmation, ''))) <> 'SUPPRIMER' then
    raise exception 'CONFIRMATION_REQUISE|Tapez SUPPRIMER pour confirmer la suppression.';
  end if;

  select * into v_cible from public.utilisateurs where id = p_id;
  if not found then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''existe plus.';
  end if;

  if p_id = v_user then
    raise exception 'ACTION_INTERDITE|Vous ne pouvez pas supprimer votre propre compte par cet écran.';
  end if;

  if p_id = v_owner then
    raise exception 'DROIT_REFUSE|Le propriétaire de l''entreprise ne peut pas être supprimé ici.';
  end if;

  if v_cible.parent_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''appartient pas à votre entreprise.';
  end if;

  begin
    update public.utilisateurs set parent_id = null where parent_id = p_id;
  exception when others then null;
  end;

  begin
    update public.agent_ia_config set updated_by = null where updated_by = p_id;
  exception when others then null;
  end;

  begin
    delete from public.utilisateurs where id = p_id;
  exception
    when foreign_key_violation then
      raise exception
        'SUPPRESSION_BLOQUEE|Un historique bloque encore ce compte : exécutez d''abord la migration 174 (journal d''audit sans clé étrangère), puis réessayez.';
  end;

  begin
    delete from auth.users where id = p_id;
    v_auth := true;
  exception when others then
    v_auth := false;
  end;

  begin
    insert into public.journal_audit (
      entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      null, 'COLLABORATEUR_SUPPRIME', v_user,
      jsonb_build_object(
        'collaborateur_id', p_id, 'email', v_cible.email,
        'nom', v_cible.nom, 'role', v_cible.new_role::text,
        'compte_auth_supprime', v_auth, 'boutique', v_owner
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true, 'id', p_id, 'compte_auth_supprime', v_auth);
end;
$$;

comment on function public.rpc_collaborateur_supprimer(uuid, text) is
  '0177 — suppression d''un collaborateur : portée mon_patron() (corrige la portée espace de 0176).';

revoke all on function public.rpc_collaborateur_supprimer(uuid, text)
  from public, anon;
grant execute on function public.rpc_collaborateur_supprimer(uuid, text)
  to authenticated;


-- ===========================================================================
--  6. CRÉER UN COLLABORATEUR — L'ESPACE PRESSING ET LE MÉTIER
-- ===========================================================================

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

  -- ⚠️ `mon_patron()` = l'UTILISATEUR patron ; `mon_proprietaire()` = l'ESPACE.
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

  if v_ent is not null then
    v_pressing := public.entreprise_est_pressing(v_ent);
  end if;

  -- 🧺 Entreprise de pressing et aucune boutique précisée → l'espace pressing.
  if p_espace_id is null and v_pressing then
    select s.id into v_espace
      from public.espaces s
     where s.entreprise_id = v_ent
       and lower(btrim(coalesce(s.type, ''))) = 'pressing'
     order by s.created_at nulls last, s.nom
     limit 1;
  end if;

  v_espace := coalesce(
    v_espace,
    public.espace_collaborateur_valide(v_owner, p_espace_id)
  );

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
         -- 🧺 Le collaborateur reçoit un MÉTIER dans le pressing : sans lui,
         --    `pressing_role()` répond « aucun » et l'application ne lui
         --    ouvre aucun écran métier (dépôts, atelier, retraits).
         role_pressing   = coalesce(role_pressing, v_metier_pressing),
         press_actif     = case when v_pressing then true else press_actif end
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
  '0177 — crée un collaborateur : espace de SON entreprise (pressing en priorité), et métier pressing déduit du rôle (responsable/atelier/caisse).';

revoke all on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid)
  from public, anon;
grant execute on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid)
  to authenticated;


-- ===========================================================================
--  7. ÉQUIPE DU PRESSING — ESPACE PRESSING D'ABORD
-- ===========================================================================

create or replace function public.press_collaborateur_creer(
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
  v_ent      uuid := public.pressing_entreprise();
  v_patron   uuid := public.mon_patron();
  v_espace   uuid;
  v_role     text := lower(btrim(coalesce(p_role, '')));
  v_email    text := lower(btrim(coalesce(p_email, '')));
  v_nom      text := nullif(btrim(coalesce(p_nom, '')), '');
  v_prenom   text := coalesce(btrim(coalesce(p_prenom, '')), '');
  v_tel      text := nullif(btrim(coalesce(p_telephone, '')), '');
  v_new_role text;
  v_user     uuid;
  v_existant uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.pressing_role() in ('proprietaire', 'responsable')) then
    raise exception 'DROIT_REFUSE|Seul le patron ou le responsable peut créer un collaborateur.';
  end if;

  if v_ent is null or v_patron is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Aucune entreprise rattachée à ce compte.';
  end if;

  if v_role not in ('responsable', 'accueil', 'atelier', 'caisse') then
    raise exception 'ROLE_INVALIDE|Métier inconnu : choisissez responsable, accueil, atelier ou caisse.';
  end if;

  if v_nom is null then
    raise exception 'NOM_REQUIS|Indiquez le nom du collaborateur.';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE|Indiquez une adresse e-mail valide (elle sert d''identifiant de connexion).';
  end if;

  if p_mot_de_passe is null or length(p_mot_de_passe) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT|Le mot de passe doit comporter au moins 8 caractères.';
  end if;

  -- ✅ L'ESPACE PRESSING en priorité : c'est lui qui porte les modules
  --    (dépôts, atelier, retraits). Un autre espace de la même entreprise
  --    affichait « seulement la caisse » au collaborateur.
  select s.id into v_espace
    from public.espaces s
   where s.entreprise_id = v_ent
     and lower(btrim(coalesce(s.type, ''))) = 'pressing'
   order by s.created_at nulls last, s.nom
   limit 1;

  v_espace := coalesce(
    v_espace,
    public.espace_collaborateur_valide(v_patron, null)
  );

  -- ⛔ Jamais l'entreprise comme espace : `espace_actif_id` est une clé
  --    étrangère vers `espaces(id)`.
  if v_espace is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Aucun espace de travail trouvé pour ce pressing.';
  end if;

  v_new_role := case v_role
                  when 'responsable' then 'PROPRIETAIRE'
                  when 'atelier'     then 'MAGASINIER'
                  else 'VENDEUR'
                end;

  select u.id into v_existant
    from public.utilisateurs u
   where lower(u.email) = v_email
   limit 1;

  if v_existant is not null then
    if exists (
      select 1 from public.utilisateurs u
       where u.id = v_existant
         and u.parent_id is not null
         and u.parent_id <> v_patron
    ) then
      raise exception 'COMPTE_EXISTANT|Cette adresse e-mail appartient déjà au collaborateur d''une autre entreprise.';
    end if;

    if v_existant = v_patron then
      raise exception 'COMPTE_EXISTANT|Cette adresse est celle du propriétaire : choisissez une autre adresse.';
    end if;

    update auth.users
       set encrypted_password = crypt(p_mot_de_passe, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_existant;

    v_user := v_existant;
  else
    v_user := public.creer_compte_plateforme(
      v_email, p_mot_de_passe, v_nom, v_prenom, v_new_role);
  end if;

  update public.utilisateurs
     set nom             = v_nom,
         prenom          = v_prenom,
         email           = v_email,
         telephone       = coalesce(v_tel, telephone),
         role            = 'collaborator',
         new_role        = coalesce(public.role_enum(v_new_role), new_role),
         valide          = 1,
         parent_id       = v_patron,
         entreprise_id   = coalesce(
                             (select u.entreprise_id from public.utilisateurs u
                               where u.id = v_patron),
                             v_ent),
         espace_actif_id = v_espace,
         role_pressing   = v_role,
         press_actif     = true
   where id = v_user;

  begin
    insert into public.journal_audit (
      entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      null, 'PRESS_COLLABORATEUR_CREE', v_user,
      jsonb_build_object('role_pressing', v_role, 'email', v_email,
                         'boutique', v_ent, 'patron', v_patron,
                         'espace', v_espace),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'id', v_user, 'email', v_email,
                            'role', v_role, 'espace_id', v_espace);
end;
$$;

comment on function public.press_collaborateur_creer(text, text, text, text, text, text) is
  '0177 — collaborateur du pressing rattaché à l''ESPACE PRESSING (et non au premier espace de l''entreprise) : il retrouve ses écrans métier à la connexion.';

revoke all on function public.press_collaborateur_creer(text, text, text, text, text, text)
  from public, anon;
grant execute on function public.press_collaborateur_creer(text, text, text, text, text, text)
  to authenticated;


-- ===========================================================================
--  8. RÉPARATION — COLLABORATEURS DANS LE MAUVAIS ESPACE
-- ===========================================================================
--  Aucune donnée métier n'est touchée : on ne corrige que le POSTE DE TRAVAIL
--  (`espace_actif_id`) des comptes qui pointent hors de leur entreprise.

-- 8.a Comptes de pressing : direction l'espace pressing de leur entreprise.
update public.utilisateurs u
   set espace_actif_id = x.espace
  from (
        select distinct on (s.entreprise_id)
               s.entreprise_id, s.id as espace
          from public.espaces s
         where lower(btrim(coalesce(s.type, ''))) = 'pressing'
         order by s.entreprise_id, s.created_at nulls last, s.nom
       ) x
 where u.role_pressing is not null
   and u.entreprise_id = x.entreprise_id
   and (
     u.espace_actif_id is null
     or not exists (
       select 1 from public.espaces e
        where e.id = u.espace_actif_id
          and lower(btrim(coalesce(e.type, ''))) = 'pressing'
     )
   );

-- 8.c Collaborateurs pressing historiques sans métier : attribuer le rôle
--     métier le plus restrictif correspondant à leur rôle d'entreprise.
--     On n'accorde jamais `responsable` à un VENDEUR/MAGASINIER/COMPTABLE.
update public.utilisateurs u
   set role_pressing = case upper(coalesce(u.new_role::text, ''))
                         when 'PROPRIETAIRE' then 'responsable'
                         when 'MAGASINIER' then 'atelier'
                         when 'VENDEUR' then 'accueil'
                         else null
                       end,
       press_actif = true
 where u.parent_id is not null
   and u.role_pressing is null
   and public.entreprise_est_pressing(u.entreprise_id)
   and upper(coalesce(u.new_role::text, '')) in
       ('PROPRIETAIRE', 'MAGASINIER', 'VENDEUR');

-- 8.b Tout collaborateur dont l'espace n'appartient pas à son entreprise.
update public.utilisateurs u
   set espace_actif_id = x.espace
  from (
        select distinct on (s.entreprise_id)
               s.entreprise_id, s.id as espace
          from public.espaces s
         where s.actif
         order by s.entreprise_id, s.created_at nulls last, s.nom
       ) x
 where u.parent_id is not null
   and u.entreprise_id = x.entreprise_id
   and (
     u.espace_actif_id is null
     or not exists (
       select 1 from public.espaces e
        where e.id = u.espace_actif_id
          and e.entreprise_id = u.entreprise_id
     )
   );


-- ===========================================================================
--  9. ANALYSE DES VENTES — TOUS LES MÉTIERS, TOUS LES PRODUITS
-- ===========================================================================

-- 9.0 Garde serveur : le pressing ne vend pas d'articles boutique.
--     `PermissionService` bloque aussi les routes côté client, mais cette
--     barrière protège les RPC et INSERT directs (dont `rpc_vente_valider`).
create or replace function public.trg_ventes_interdire_pressing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid;
begin
  select s.entreprise_id into v_ent
    from public.espaces s
   where s.id = new.owner_id;

  if v_ent is null then
    select u.entreprise_id into v_ent
      from public.utilisateurs u
     where u.id = new.owner_id;
  end if;

  if v_ent is not null and public.entreprise_est_pressing(v_ent) then
    raise exception
      'VENTE_INTERDITE_PRESSING|Un pressing enregistre des dépôts et prestations, pas des ventes boutique.';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_ventes_interdire_pressing on public.ventes;
create trigger trg_ventes_interdire_pressing
  before insert on public.ventes
  for each row execute function public.trg_ventes_interdire_pressing();

comment on function public.trg_ventes_interdire_pressing() is
  '0177 — bloque les ventes d''articles boutique dans un pressing, y compris via RPC ou INSERT direct.';

-- 9.a Les lignes analysables : ventes d'articles ET prestations de pressing.
--     Aucune table temporaire (refusée sur certains rôles) : une fonction
--     `stable` que l'on interroge dans un CTE.
create or replace function public.analyse_lignes_ventes(
  p_entreprise_id uuid,
  p_debut         date,
  p_fin           date
)
returns table (
  source      text,
  ref         text,
  nom         text,
  quantite    numeric,
  prix        numeric,
  prix_achat  numeric,
  local_date  timestamp
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_perim uuid[] := array[]::uuid[];
begin
  select coalesce(array_agg(distinct x), array[]::uuid[]) into v_perim
    from (
      select s.id as x
        from public.espaces s
       where s.entreprise_id = p_entreprise_id
      union
      select u.id
        from public.utilisateurs u
       where u.entreprise_id = p_entreprise_id
      union
      select e.owner_id
        from public.entreprises e
       where e.id = p_entreprise_id and e.owner_id is not null
    ) t;

  -- 1. Ventes d'articles (boutique, pharmacie, dépôt, distribution…).
  return query
  select 'boutique'::text,
         v.produit_id::text,
         coalesce(nullif(btrim(coalesce(p.nom, '')), ''), 'Article supprimé'),
      coalesce(v.quantite, 0)::numeric,
      coalesce(v.prix, 0)::numeric,
      coalesce(p.prix_achat, 0)::numeric,
         (v.date at time zone 'Africa/Lubumbashi')
    from public.ventes v
    left join public.produits p on p.id = v.produit_id
   where v.owner_id = any(v_perim)
     and v.date >= p_debut::timestamptz
     and v.date < (p_fin + 1)::timestamptz;

  -- 2. Prestations du pressing (un pressing ne remplit pas `ventes`).
  if to_regclass('public.pressing_lignes') is not null
     and to_regclass('public.pressing_commandes') is not null then
    return query execute $q$
      select 'pressing'::text,
             l.prestation_id::text,
             coalesce(nullif(btrim(coalesce(l.prestation_nom, '')), ''),
                      nullif(btrim(coalesce(l.designation, '')), ''),
                      'Prestation'),
             coalesce(l.quantite, 1),
             coalesce(l.prix, 0),
             0::numeric,
             (c.date_depot at time zone 'Africa/Lubumbashi')
        from public.pressing_lignes l
        join public.pressing_commandes c on c.id = l.commande_id
       where c.entreprise_id = $1
         and coalesce(c.statut, '') <> 'ANNULEE'
         and c.date_depot >= ($2::date)::timestamptz
         and c.date_depot < (($3::date) + 1)::timestamptz
    $q$ using p_entreprise_id, p_debut, p_fin;
  end if;
end;
$$;

comment on function public.analyse_lignes_ventes(uuid, date, date) is
  '0177 — lignes analysables d''une entreprise sur une période : ventes d''articles + prestations de pressing (sans table temporaire).';

revoke all on function public.analyse_lignes_ventes(uuid, date, date)
  from public, anon;
grant execute on function public.analyse_lignes_ventes(uuid, date, date)
  to authenticated;


-- 9.b Le rapport : TOUS les produits, classés par meilleure vente.
create or replace function public.rpc_rapport_entreprise_analyse(
  p_entreprise_id uuid,
  p_debut         date,
  p_fin           date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nom       text;
  v_debut     date := coalesce(p_debut, current_date - 6);
  v_fin       date := coalesce(p_fin, current_date);
  v_ca        numeric := 0;
  v_ventes    bigint := 0;
  v_articles  numeric := 0;
  v_marge     numeric := 0;
  v_panier    numeric := 0;
  v_nb_prod   integer := 0;
  v_src_bout  integer := 0;
  v_src_press integer := 0;
  v_top       jsonb := '[]'::jsonb;
  v_jours     jsonb := '[]'::jsonb;
  v_moments   jsonb := '[]'::jsonb;
  v_best_prod jsonb;
  v_best_jour jsonb;
  v_best_mom  jsonb;
  v_conseils  jsonb := '[]'::jsonb;
  v_simul     jsonb := '{}'::jsonb;
  v_part      numeric := 0;
  v_jour_nom  text;
  v_mom_nom   text;
  v_objectif  numeric := 0.10;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select e.nom into v_nom
    from public.entreprises e
   where e.id = p_entreprise_id;

  if v_nom is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  if not (public.est_plateforme()
          or exists (select 1 from public.entreprises e
                      where e.id = p_entreprise_id
                        and e.owner_id in (auth.uid(), public.mon_patron()))) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette entreprise.';
  end if;

  if v_fin < v_debut then
    raise exception 'PERIODE_INVALIDE|La date de fin précède la date de début.';
  end if;

  -- Tous les totaux en UNE seule lecture des lignes.
  with lignes as (
    select * from public.analyse_lignes_ventes(p_entreprise_id, v_debut, v_fin)
  )
  select
    coalesce((select sum(l.prix) from lignes l), 0),
    (select count(*) from lignes),
    coalesce((select sum(l.quantite) from lignes l), 0),
    coalesce((select sum(l.prix - coalesce(l.prix_achat, 0) * l.quantite)
                from lignes l), 0),
    (select count(distinct l.nom) from lignes l),
    (select count(*) from lignes l where l.source = 'boutique'),
    (select count(*) from lignes l where l.source = 'pressing')
  into v_ca, v_ventes, v_articles, v_marge, v_nb_prod, v_src_bout, v_src_press;

  if v_ventes > 0 then
    v_panier := round(v_ca / v_ventes, 2);
  end if;

  -- 🏆 TOUS les produits, du meilleur au moins vendu (plus de `limit 10`).
  with lignes as (
    select * from public.analyse_lignes_ventes(p_entreprise_id, v_debut, v_fin)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'rang',     x.rang,
           'nom',      x.nom,
           'quantite', x.qte,
           'ca',       x.ca,
           'part',     case when v_ca > 0 then round(100 * x.ca / v_ca, 1) else 0 end
         ) order by x.rang), '[]'::jsonb)
    into v_top
    from (
      select a.nom,
             sum(a.quantite) as qte,
             sum(a.prix)     as ca,
             row_number() over (order by sum(a.prix) desc, sum(a.quantite) desc, a.nom) as rang
        from lignes a
       group by a.nom
    ) x;

  if jsonb_array_length(v_top) > 0 then
    v_best_prod := v_top->0;
    v_part := coalesce((v_best_prod->>'part')::numeric, 0);
  end if;

  -- Jours de la semaine (0 = dimanche côté PostgreSQL).
  with lignes as (
    select * from public.analyse_lignes_ventes(p_entreprise_id, v_debut, v_fin)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'dow', d.dow, 'jour', d.jour, 'ca', d.ca, 'ventes', d.nb
         ) order by d.dow), '[]'::jsonb)
    into v_jours
    from (
      select extract(dow from a.local_date)::int as dow,
             case extract(dow from a.local_date)::int
               when 0 then 'Dimanche' when 1 then 'Lundi' when 2 then 'Mardi'
               when 3 then 'Mercredi' when 4 then 'Jeudi' when 5 then 'Vendredi'
               else 'Samedi' end as jour,
             sum(a.prix) as ca,
             count(*)    as nb
        from lignes a
       group by 1
    ) d;

  select j into v_best_jour
    from jsonb_array_elements(v_jours) j
   order by (j->>'ca')::numeric desc
   limit 1;

  -- Moments de la journée.
  with lignes as (
    select * from public.analyse_lignes_ventes(p_entreprise_id, v_debut, v_fin)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'moment', m.moment, 'ca', m.ca, 'ventes', m.nb
         ) order by m.ca desc), '[]'::jsonb)
    into v_moments
    from (
      select case
               when extract(hour from a.local_date) between 6  and 10 then 'Matin (6h–11h)'
               when extract(hour from a.local_date) between 11 and 14 then 'Midi (11h–15h)'
               when extract(hour from a.local_date) between 15 and 18 then 'Après-midi (15h–19h)'
               when extract(hour from a.local_date) between 19 and 22 then 'Soir (19h–23h)'
               else 'Nuit (23h–6h)'
             end as moment,
             sum(a.prix) as ca,
             count(*)    as nb
        from lignes a
       group by 1
    ) m;

  v_best_mom := v_moments->0;

  -- Conseils (calculés sur les données réelles, jamais inventés).
  if v_ventes = 0 then
    v_conseils := jsonb_build_array(jsonb_build_object(
      'titre', 'Aucune vente sur la période',
      'detail', 'Choisissez une autre période, ou vérifiez que les ventes sont bien enregistrées dans cette entreprise.'));
  else
    if v_best_jour is not null then
      v_jour_nom := coalesce(v_best_jour->>'jour', '');
      v_conseils := v_conseils || jsonb_build_object(
        'titre', format('Votre meilleur jour : %s', v_jour_nom),
        'detail', format('%s réalise %s CDF. Prévoyez le stock et le personnel ce jour-là, et lancez vos promotions la veille.',
                         v_jour_nom,
                         to_char(coalesce((v_best_jour->>'ca')::numeric, 0), 'FM999G999G999G999')));
    end if;

    if v_best_mom is not null then
      v_mom_nom := coalesce(v_best_mom->>'moment', '');
      v_conseils := v_conseils || jsonb_build_object(
        'titre', format('Votre pic d''activité : %s', v_mom_nom),
        'detail', format('Ce créneau pèse %s CDF. Assurez la disponibilité des produits phares et la présence d''un vendeur supplémentaire.',
                         to_char(coalesce((v_best_mom->>'ca')::numeric, 0), 'FM999G999G999G999')));
    end if;

    if v_best_prod is not null and v_part >= 40 then
      v_conseils := v_conseils || jsonb_build_object(
        'titre', 'Trop dépendant d''un seul produit',
        'detail', format('« %s » représente %s %% du chiffre d''affaires. Développez 2 produits complémentaires pour sécuriser les revenus.',
                         v_best_prod->>'nom',
                         to_char(v_part, 'FM990.0')));
    elsif v_best_prod is not null then
      v_conseils := v_conseils || jsonb_build_object(
        'titre', 'Un produit moteur à pousser',
        'detail', format('« %s » est votre meilleure vente (%s CDF). Mettez-le en avant et proposez-le systématiquement : c''est le levier le plus rapide.',
                         v_best_prod->>'nom',
                         to_char(coalesce((v_best_prod->>'ca')::numeric, 0), 'FM999G999G999G999')));
    end if;

    if v_panier > 0 then
      v_conseils := v_conseils || jsonb_build_object(
        'titre', format('Panier moyen : %s CDF', to_char(v_panier, 'FM999G999G999G999')),
        'detail', 'Proposez un article complémentaire à chaque vente (lot, accessoire, produit d''appel) : +10 % sur le panier suffit à augmenter le revenu sans nouveau client.');
    end if;

    if v_marge > 0 then
      v_conseils := v_conseils || jsonb_build_object(
        'titre', 'Marge estimée sur la période',
        'detail', format('Marge brute estimée : %s CDF (sur les produits dont le prix d''achat est renseigné). Renseignez les prix d''achat manquants pour un calcul complet.',
                         to_char(v_marge, 'FM999G999G999G999')));
    end if;
  end if;

  -- Simulation : le produit n°1 progresse de 10 %.
  if v_best_prod is not null then
    v_simul := jsonb_build_object(
      'produit', v_best_prod->>'nom',
      'ca_actuel', coalesce((v_best_prod->>'ca')::numeric, 0),
      'objectif_pct', 10,
      'ca_supplementaire', round(coalesce((v_best_prod->>'ca')::numeric, 0) * v_objectif, 2),
      'ca_projete', round(v_ca + coalesce((v_best_prod->>'ca')::numeric, 0) * v_objectif, 2),
      'message', format('Si « %s » progresse de 10 %%, la boutique gagne environ %s CDF de plus sur la période.',
                        v_best_prod->>'nom',
                        to_char(round(coalesce((v_best_prod->>'ca')::numeric, 0) * v_objectif, 2), 'FM999G999G999G999'))
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', p_entreprise_id,
    'entreprise_nom', v_nom,
    'debut', v_debut,
    'fin', v_fin,
    'devise', 'CDF',
    'totaux', jsonb_build_object(
      'ca', v_ca, 'ventes', v_ventes, 'articles', v_articles,
      'panier_moyen', v_panier, 'marge', v_marge),
    'nb_produits', v_nb_prod,
    'sources', jsonb_build_object(
      'boutique', v_src_bout, 'pressing', v_src_press),
    'top_produits', v_top,
    'jours', v_jours,
    'moments', v_moments,
    'meilleur_produit', v_best_prod,
    'meilleur_jour', v_best_jour,
    'meilleur_moment', v_best_mom,
    'conseils', v_conseils,
    'simulation', v_simul
  );
end;
$$;

comment on function public.rpc_rapport_entreprise_analyse(uuid, date, date) is
  '0177 — analyse commerciale : ventes d''articles ET prestations de pressing, TOUS les produits classés par meilleure vente, sans table temporaire.';

revoke all on function public.rpc_rapport_entreprise_analyse(uuid, date, date)
  from public, anon;
grant execute on function public.rpc_rapport_entreprise_analyse(uuid, date, date)
  to authenticated;


-- ===========================================================================
-- 10. QR CODES — CE QUI EXISTE, CE QUI A ÉTÉ FACTURÉ, PAR BOUTIQUE
-- ===========================================================================
--  « Codes existants » = un QR par article + un QR par emballage : c'est tout
--  ce qu'une boutique peut avoir déjà produit. Les revenus, eux, ne comptent
--  que les émissions réellement facturées (`qr_codes_emis`).

create or replace function public.rpc_qr_tarif_etat()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_val     jsonb;
  v_prix    numeric := 150;
  v_devise  text := 'CDF';
  v_nb      bigint := 0;
  v_total   numeric := 0;
  v_mois    numeric := 0;
  v_exist   bigint := 0;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select s.value into v_val from public.app_settings s where s.key = 'qr_codes';
  if v_val is not null then
    v_prix   := coalesce((v_val->>'prix')::numeric, v_prix);
    v_devise := coalesce(nullif(v_val->>'devise', ''), v_devise);
  end if;

  select count(*), coalesce(sum(q.total), 0) into v_nb, v_total
    from public.qr_codes_emis q;

  select coalesce(sum(q.total), 0) into v_mois
    from public.qr_codes_emis q
   where q.created_at >= date_trunc('month', now());

  -- Tout ce qui peut avoir déjà été produit : 1 QR par article + 1 par
  -- emballage. Plateforme = toutes les boutiques ; sinon, l'espace courant.
  select count(*) into v_exist
    from (
      select p.id::text as code
        from public.produits p
       where public.est_plateforme()
          or p.owner_id = public.mon_proprietaire()
      union all
      select c.qr_code_id::text
        from public.conditionnements c
        join public.produits p2 on p2.id = c.produit_id
       where c.qr_code_id is not null
         and (public.est_plateforme()
              or p2.owner_id = public.mon_proprietaire())
    ) t;

  return jsonb_build_object(
    'ok', true,
    'prix', v_prix,
    'devise', v_devise,
    'nb_qr', v_nb,
    'revenus_total', v_total,
    'revenus_mois', v_mois,
    'codes_existants', v_exist
  );
end;
$$;

comment on function public.rpc_qr_tarif_etat() is
  '0177 — tarif QR + nombre de QR facturés + nombre de QR EXISTANTS (articles et emballages) de la boutique.';

revoke all on function public.rpc_qr_tarif_etat() from public, anon;
grant execute on function public.rpc_qr_tarif_etat() to authenticated;


-- 10.b Tableau de bord plateforme : QR facturés ET QR existants.
create or replace function public.rpc_admin_tableau_bord()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_total      numeric := 0;
  v_nb         bigint  := 0;
  v_mois       numeric := 0;
  v_jour       numeric := 0;
  v_qr_prix    numeric := 150;
  v_qr_nb      bigint  := 0;
  v_qr_total   numeric := 0;
  v_qr_mois    numeric := 0;
  v_qr_exist   bigint  := 0;
  v_entreprises bigint := 0;
  v_comptes    bigint  := 0;
  v_produits   bigint  := 0;
  v_val        jsonb;
  v_par_ent    jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Réservé à la plateforme.';
  end if;

  -- 💰 Revenus réels : uniquement les paiements CONFIRMÉS par SerdiPay.
  select coalesce(sum(s.montant), 0), count(*)
    into v_total, v_nb
    from public.paiements_serdipay s
   where s.statut = 'paye';

  select coalesce(sum(s.montant), 0) into v_mois
    from public.paiements_serdipay s
   where s.statut = 'paye'
     and coalesce(s.paye_le, s.created_at) >= date_trunc('month', now());

  select coalesce(sum(s.montant), 0) into v_jour
    from public.paiements_serdipay s
   where s.statut = 'paye'
     and coalesce(s.paye_le, s.created_at) >= date_trunc('day', now());

  -- 🏷️ QR codes : facturés (revenus) + existants (tout ce qui est produit).
  select s.value into v_val from public.app_settings s where s.key = 'qr_codes';
  if v_val is not null then
    v_qr_prix := coalesce((v_val->>'prix')::numeric, v_qr_prix);
  end if;

  select count(*), coalesce(sum(q.total), 0) into v_qr_nb, v_qr_total
    from public.qr_codes_emis q;

  select coalesce(sum(q.total), 0) into v_qr_mois
    from public.qr_codes_emis q
   where q.created_at >= date_trunc('month', now());

  select
    (select count(*) from public.produits)
    + (select count(*) from public.conditionnements c where c.qr_code_id is not null)
    into v_qr_exist;

  select count(*) into v_entreprises from public.entreprises;
  select count(*) into v_comptes from public.utilisateurs;
  select count(*) into v_produits from public.produits;

  -- Répartition par boutique (tout ce qui a été produit + ce qui est facturé).
  select coalesce(jsonb_agg(jsonb_build_object(
           'entreprise_id', e.id,
           'nom', e.nom,
           'codes_existants', coalesce(a.articles, 0) + coalesce(a.emballages, 0),
           'emis', coalesce(q.nb, 0),
           'revenus', coalesce(q.total, 0)
         ) order by e.nom), '[]'::jsonb)
    into v_par_ent
    from public.entreprises e
    left join lateral (
      select
        (select count(*)
           from public.produits p
           join public.espaces s on s.id = p.owner_id
          where s.entreprise_id = e.id) as articles,
        (select count(*)
           from public.conditionnements c
           join public.produits p on p.id = c.produit_id
           join public.espaces s on s.id = p.owner_id
          where s.entreprise_id = e.id
            and c.qr_code_id is not null) as emballages
    ) a on true
    left join lateral (
      select count(*) as nb, coalesce(sum(q2.total), 0) as total
        from public.qr_codes_emis q2
       where q2.entreprise_id = e.id
    ) q on true;

  return jsonb_build_object(
    'ok', true,
    'devise', 'CDF',
    'serdipay', jsonb_build_object(
      'total', v_total, 'mois', v_mois, 'jour', v_jour, 'paiements', v_nb),
    'qr', jsonb_build_object(
      'prix', v_qr_prix, 'nb', v_qr_nb, 'total', v_qr_total,
      'mois', v_qr_mois, 'existants', v_qr_exist),
    'qr_par_entreprise', v_par_ent,
    'compteurs', jsonb_build_object(
      'entreprises', v_entreprises,
      'comptes', v_comptes,
      'produits', v_produits)
  );
end;
$$;

comment on function public.rpc_admin_tableau_bord() is
  '0177 — tableau de bord plateforme : SerdiPay confirmé, QR facturés ET existants, répartition des QR par boutique.';

revoke all on function public.rpc_admin_tableau_bord() from public, anon;
grant execute on function public.rpc_admin_tableau_bord() to authenticated;


-- ===========================================================================
-- 11. VÉRIFICATIONS (lecture seule)
-- ===========================================================================

-- 11.a Les fonctions installées (attendu : 11 lignes).
select p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('espace_collaborateur_valide', 'entreprise_est_pressing',
                     'rpc_collaborateurs_lister', 'rpc_collaborateur_maj',
                     'rpc_collaborateur_supprimer', 'rpc_collaborateur_creer',
                     'press_collaborateur_creer', 'analyse_lignes_ventes',
                     'rpc_rapport_entreprise_analyse',
                     'rpc_qr_tarif_etat', 'rpc_admin_tableau_bord')
 order by 1;

-- 11.b Collaborateurs dont l'espace n'appartient pas à leur entreprise
--      (attendu : 0 ligne après la réparation).
select u.id, u.email, u.entreprise_id, u.espace_actif_id
  from public.utilisateurs u
 where u.parent_id is not null
   and u.espace_actif_id is not null
   and not exists (
     select 1 from public.espaces s
      where s.id = u.espace_actif_id
        and s.entreprise_id = u.entreprise_id
   );

-- 11.c Collaborateurs de pressing sans métier (attendu : 0 ligne).
select u.id, u.email, u.role_pressing
  from public.utilisateurs u
 where u.parent_id is not null
   and public.entreprise_est_pressing(u.entreprise_id)
   and u.role_pressing is null;

-- 11.d Garde serveur présente (attendu : 1 ligne).
select t.tgname
  from pg_trigger t
  join pg_class r on r.oid = t.tgrelid
  join pg_namespace n on n.oid = r.relnamespace
 where n.nspname = 'public'
   and r.relname = 'ventes'
   and t.tgname = 'trg_ventes_interdire_pressing'
   and not t.tgisinternal;
