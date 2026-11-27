-- ============================================================================
--  biashara_yangu — MIGRATION 0181
--  ISOLATION STRICTE PAR ESPACE (= ENTREPRISE) + ÉQUIPE PAR ESPACE
-- ---------------------------------------------------------------------------
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase, APRÈS la 0180.
--  ⚠️ IDEMPOTENT : relançable sans effet de bord.
--  ⚠️ Aucune donnée métier n'est modifiée (produits, ventes, caisse…).
--
--  ════════════════════════════════════════════════════════════════════════
--  MODÈLE MÉTIER VALIDÉ PAR LE PROPRIÉTAIRE
--  ════════════════════════════════════════════════════════════════════════
--   • « Boutique » est un TYPE d'entreprise parmi d'autres (pharmacie,
--     pressing, hôtel…). Il n'y a pas de différence de nature entre une
--     entreprise et une boutique : UNE ENTREPRISE = UN ESPACE DE DONNÉES.
--   • Un propriétaire peut posséder PLUSIEURS entreprises, mais chacune est
--     TOTALEMENT distincte : les données ne se mélangent jamais.
--   • Un collaborateur appartient à UNE entreprise (donc UN espace) et
--     n'apparaît que dans l'équipe de CET espace.
--
--  ════════════════════════════════════════════════════════════════════════
--  CE QUI EST CORRIGÉ ICI
--  ════════════════════════════════════════════════════════════════════════
--  ① LISTE DE L'ÉQUIPE — `rpc_collaborateurs_lister()` filtrait seulement
--     `parent_id = mon_patron()`. Un vendeur de l'entreprise A apparaissait
--     dans « Mon Équipe » du patron travaillant sur B. Désormais : uniquement
--     les collaborateurs de l'ESPACE ACTIF (repli : même entreprise pour les
--     comptes historiques sans espace).
--
--  ② MODIFICATION / SUPPRESSION — `rpc_collaborateur_maj()` et
--     `rpc_collaborateur_supprimer()` vérifiaient seulement `parent_id`.
--     Elles exigent maintenant que la cible soit dans l'espace actif.
--
--  ③ CRÉATION — `entreprise_id` du collaborateur est déduite de l'ESPACE
--     choisi (et non plus de l'entreprise courante du patron), ce qui évite
--     les paires incohérentes (entreprise A + espace B).
--
--  ④ RLS `utilisateurs` — les policies `zz_lecture_utilisateurs`,
--     `zz_maj_utilisateurs` et « Accès via parent_id » autorisaient
--     `parent_id = auth.uid()` sans borne : lecture ET modification de TOUS
--     les collaborateurs du compte. Elles sont bornées à l'espace actif.
--     On conserve : son propre profil, et la lecture de SON PATRON.
--
--  ⑤ `rpc_espaces_lister()` — `actif_id` renvoyait `espace_actif_id` BRUT,
--     sans contrôle d'entreprise, alors que `mon_proprietaire()` le vérifie.
--     Les deux répondent désormais la même valeur.
--
--  ⑥ TRIGGER `zzz_owner_espace` — option A : un `owner_id` déjà renseigné
--     et qui désigne un ESPACE VALIDE est PRÉSERVÉ. Une vente encaissée hors
--     ligne dans l'entreprise B n'est plus ré-estampillée sur l'entreprise
--     active au moment de la synchronisation (la RLS refuse alors la ligne
--     tant que B n'est pas actif : elle est rejouée plus tard, jamais
--     déplacée).
--
--  ⑦ PAIEMENTS PLATEFORME — `paiements_abonnement` et
--     `paiements_abonnements_laperle` étaient lisibles par TOUT compte
--     connecté (`USING (true)`). Lecture réservée à `est_plateforme()`.
--
--  ⑧ FINANCE — `depenses`, `dettes`, `paiements_dette` et
--     `clotures_caisse` n'étaient bornées que par `acces_finance_entreprise`
--     (qui accepte encore `auth.uid() = owner_id`, héritage de la 1ʳᵉ
--     entreprise). Une policy RESTRICTIVE les borne à l'espace actif.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. HELPERS (autonomes : la 0181 ne dépend pas de la 0180)
-- ============================================================================

-- 0.a Entreprise d'un espace.
create or replace function public.espace_entreprise(p_espace uuid)
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select s.entreprise_id
    from public.espaces s
   where s.id = p_espace
   limit 1;
$$;

comment on function public.espace_entreprise(uuid) is
  '0181 — entreprise propriétaire d''un espace (boutique).';

revoke all on function public.espace_entreprise(uuid) from public, anon;
grant execute on function public.espace_entreprise(uuid) to authenticated;


-- 0.b Type normalisé d'un espace (idempotent avec 0180).
create or replace function public.espace_type(p_espace uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select lower(btrim(coalesce(s.type, '')))
    from public.espaces s
   where s.id = p_espace;
$$;

revoke all on function public.espace_type(uuid) from public, anon;
grant execute on function public.espace_type(uuid) to authenticated;


-- 0.c Cet espace est-il un pressing ? (idempotent avec 0180)
create or replace function public.espace_est_pressing(p_espace uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.espace_type(p_espace) = 'pressing', false);
$$;

revoke all on function public.espace_est_pressing(uuid) from public, anon;
grant execute on function public.espace_est_pressing(uuid) to authenticated;


-- ============================================================================
--  1. ESPACE PAR DÉFAUT D'UN COLLABORATEUR — TOUJOURS DANS L'ENTREPRISE
--     OÙ LE PATRON TRAVAILLE (l'espace actif).
-- ============================================================================
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
  v_actif uuid := public.mon_proprietaire();
  v_ent   uuid;
  v_pris  uuid;
begin
  if p_owner is null then
    return null;
  end if;

  -- Entreprise de TRAVAIL = celle de l'espace actif (repli : patron).
  v_ent := public.espace_entreprise(v_actif);
  if v_ent is null then
    select u.entreprise_id into v_ent
      from public.utilisateurs u
     where u.id = p_owner;
  end if;

  -- 1. L'espace demandé, s'il appartient à l'entreprise de travail.
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

  -- 2. L'espace actif de l'utilisateur connecté.
  if v_actif is not null and exists (
    select 1 from public.espaces s
     where s.id = v_actif
       and s.actif
  ) then
    return v_actif;
  end if;

  -- 3. Premier espace actif de l'entreprise de travail.
  select s.id into v_pris
    from public.espaces s
   where v_ent is not null
     and s.entreprise_id = v_ent
     and s.actif
   order by s.created_at nulls last, s.nom
   limit 1;

  if v_pris is not null then
    return v_pris;
  end if;

  -- 4. Compatibilité historique (l'espace porte l'id du patron).
  if exists (select 1 from public.espaces s where s.id = p_owner) then
    return p_owner;
  end if;

  return null;
end;
$$;

comment on function public.espace_collaborateur_valide(uuid, uuid) is
  '0181 — espace d''un collaborateur : espace demandé, sinon ESPACE ACTIF, sinon premier espace de l''entreprise de travail.';

revoke all on function public.espace_collaborateur_valide(uuid, uuid) from public, anon;
grant execute on function public.espace_collaborateur_valide(uuid, uuid) to authenticated;


-- ============================================================================
--  2. SÉLECTEUR — `actif_id` = `mon_proprietaire()` (valeur VÉRIFIÉE)
-- ============================================================================
create or replace function public.rpc_espaces_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_patron  uuid;
  v_role    text := public.mon_role();
  v_max     integer := 1;
  v_nb_ent  integer := 0;
  v_actif   uuid;
  v_liste   jsonb := '[]'::jsonb;
  v_ent_collab uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour voir vos entreprises.';
  end if;

  v_patron := public.mon_patron();
  if v_patron is null then
    return jsonb_build_object(
      'espaces', '[]'::jsonb, 'actif_id', null, 'max_espaces', 1,
      'role', v_role, 'peut_creer', false, 'raison', 'aucune_entreprise');
  end if;

  -- Un collaborateur est borné à SON entreprise.
  select u.entreprise_id into v_ent_collab
    from public.utilisateurs u
   where u.id = v_user
     and u.parent_id is not null;

  -- Quota : nombre d'ENTREPRISES autorisées par le pack.
  select greatest(coalesce(max(g.max_espaces), 1), 1) into v_max
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.owner_id = v_patron;

  select count(*) into v_nb_ent
    from public.entreprises e
   where e.owner_id = v_patron;

  -- ✅ L'ACTIF EST LA VALEUR VÉRIFIÉE PAR LE SERVEUR (même que `owner_id`).
  v_actif := public.mon_proprietaire();

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',            s.id,
           'nom',           s.nom,
           'type',          s.type,
           'actif',         s.actif,
           'est_actif',     s.id = v_actif,
           'entreprise_id',   e.id,
           'entreprise_nom',  e.nom,
           'etat_abonnement', e.statut::text,
           'date_expiration', e.date_expiration,
           'created_at',    s.created_at
         ) order by e.created_at nulls first, s.created_at, s.nom), '[]'::jsonb)
    into v_liste
    from public.entreprises e
    join public.espaces s on s.entreprise_id = e.id
   where e.owner_id = v_patron
     and (v_ent_collab is null or e.id = v_ent_collab);

  if v_actif is null then
    select s.id into v_actif
      from public.entreprises e
      join public.espaces s on s.entreprise_id = e.id
     where e.owner_id = v_patron
       and (v_ent_collab is null or e.id = v_ent_collab)
       and s.actif
     order by e.created_at nulls first, s.created_at, s.nom
     limit 1;
  end if;

  return jsonb_build_object(
    'espaces',     v_liste,
    'actif_id',    v_actif,
    'max_espaces', v_max,
    'nb_entreprises', v_nb_ent,
    'role',        v_role,
    'peut_creer',  (v_role = 'PROPRIETAIRE' and v_nb_ent < v_max),
    'raison',      case
                     when v_role <> 'PROPRIETAIRE' then 'role'
                     when v_nb_ent >= v_max then 'quota'
                     else null
                   end
  );
end;
$$;

comment on function public.rpc_espaces_lister() is
  '0181 — sélecteur : entreprises du patron (ou de la sienne pour un collaborateur) ; actif_id = mon_proprietaire().';

revoke all on function public.rpc_espaces_lister() from public, anon;
grant execute on function public.rpc_espaces_lister() to authenticated;


-- ============================================================================
--  3. LISTE DE L'ÉQUIPE — UNIQUEMENT L'ESPACE ACTIF
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
  v_espace uuid;
  v_ent    uuid;
  v_lignes jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  -- ✅ LE PATRON (utilisateur), jamais l'espace.
  v_owner  := coalesce(public.mon_patron(), v_user);
  -- ✅ L'ESPACE DE TRAVAIL (boutique = entreprise).
  v_espace := public.mon_proprietaire();
  v_ent    := public.espace_entreprise(v_espace);

  if v_ent is null then
    select u.entreprise_id into v_ent
      from public.utilisateurs u
     where u.id = v_user;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',           u.id,
           'nom',          coalesce(u.nom, ''),
           'prenom',       coalesce(u.prenom, ''),
           'email',        coalesce(u.email, ''),
           'telephone',    coalesce(u.telephone, ''),
           'role',         coalesce(u.new_role::text, public.role_herite(u.role)),
           'actif',        coalesce(u.valide, 1) = 1,
           'espace_id',    u.espace_actif_id,
           'espace_nom',   coalesce(s.nom, ''),
           'entreprise_id', u.entreprise_id,
           'role_pressing', u.role_pressing
         ) order by coalesce(u.nom, ''), coalesce(u.prenom, '')), '[]'::jsonb)
    into v_lignes
    from public.utilisateurs u
    left join public.espaces s on s.id = u.espace_actif_id
   where u.parent_id = v_owner
     and (
       -- 1. Collaborateurs de l'ESPACE ACTIF (règle demandée).
       (v_espace is not null and u.espace_actif_id = v_espace)
       -- 2. Comptes historiques sans espace : même ENTREPRISE seulement.
       or (v_espace is not null
           and u.espace_actif_id is null
           and v_ent is not null
           and u.entreprise_id = v_ent)
       -- 3. Aucun espace connu : repli borné à l'entreprise.
       or (v_espace is null
           and v_ent is not null
           and u.entreprise_id = v_ent)
     );

  return jsonb_build_object(
    'proprietaire_id', v_owner,
    'espace_id',       v_espace,
    'entreprise_id',   v_ent,
    'lignes',          v_lignes
  );
end;
$$;

comment on function public.rpc_collaborateurs_lister() is
  '0181 — équipe de l''ESPACE ACTIF uniquement (jamais les collaborateurs d''une autre entreprise du patron).';

revoke all on function public.rpc_collaborateurs_lister() from public, anon;
grant execute on function public.rpc_collaborateurs_lister() to authenticated;


-- ============================================================================
--  4. CRÉER UN COLLABORATEUR — DANS L'ESPACE ACTIF
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

  -- 🧭 L'ESPACE ACTIF DÉCIDE : l'entreprise du collaborateur en découle.
  v_espace := public.espace_collaborateur_valide(v_owner, p_espace_id);
  v_ent    := public.espace_entreprise(v_espace);

  if v_ent is null then
    select u.entreprise_id into v_ent
      from public.utilisateurs u
     where u.id = v_owner;
  end if;

  -- Un espace imposé hors de l'entreprise de travail est refusé explicitement
  -- (au lieu de retomber silencieusement sur un autre espace).
  if p_espace_id is not null
     and v_ent is not null
     and public.espace_entreprise(p_espace_id) is distinct from v_ent then
    raise exception 'ESPACE_HORS_PERIMETRE|Cette boutique n''appartient pas à l''entreprise où vous travaillez. Changez d''entreprise d''abord.';
  end if;

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
      'entreprise', v_ent,
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
    'entreprise_id', v_ent,
    'role_pressing', v_metier_pressing
  );
end;
$$;

comment on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid) is
  '0181 — crée un collaborateur dans l''ESPACE ACTIF ; entreprise_id déduite de cet espace.';

revoke all on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid)
  from public, anon;
grant execute on function public.rpc_collaborateur_creer(text, text, text, text, text, text, uuid)
  to authenticated;


-- ============================================================================
--  5. MODIFIER UN COLLABORATEUR — CIBLE LIMITÉE À L'ESPACE ACTIF
-- ============================================================================
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
  v_espace   uuid;          -- espace ACTIF (périmètre)
  v_ent      uuid;
  v_cible_espace uuid;      -- nouvel espace demandé (ou null = inchangé)
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

  if not (v_role = any (public.roles_entreprise_attribuables())) then
    raise exception 'ROLE_INVALIDE|Rôle inconnu.';
  end if;

  v_espace := public.mon_proprietaire();
  v_ent    := public.espace_entreprise(v_espace);

  if v_ent is null then
    select u.entreprise_id into v_ent
      from public.utilisateurs u
     where u.id = v_owner;
  end if;

  -- ✅ La cible doit appartenir à l'ESPACE ACTIF (repli : son entreprise).
  if not exists (
    select 1
      from public.utilisateurs u
     where u.id = p_id
       and u.parent_id = v_owner
       and (
         (v_espace is not null and u.espace_actif_id = v_espace)
         or (v_espace is not null
             and u.espace_actif_id is null
             and v_ent is not null
             and u.entreprise_id = v_ent)
         or (v_espace is null
             and v_ent is not null
             and u.entreprise_id = v_ent)
       )
  ) then
    raise exception 'COLLABORATEUR_HORS_PERIMETRE|Ce collaborateur n''appartient pas à l''entreprise où vous travaillez.';
  end if;

  if p_id = v_user then
    raise exception 'ACTION_INTERDITE|Vous ne pouvez pas modifier votre propre compte par cet écran.';
  end if;

  -- Espace cible : null = on ne change pas.
  if p_espace_id is not null then
    if v_ent is not null
       and public.espace_entreprise(p_espace_id) is distinct from v_ent then
      raise exception 'ESPACE_HORS_PERIMETRE|Cette boutique n''appartient pas à l''entreprise où vous travaillez.';
    end if;
    v_cible_espace := public.espace_collaborateur_valide(v_owner, p_espace_id);
  end if;

  v_pressing := public.espace_est_pressing(
    coalesce(v_cible_espace,
             (select u.espace_actif_id from public.utilisateurs u where u.id = p_id),
             v_espace));

  v_metier := case
                when not v_pressing then null
                when v_role = 'PROPRIETAIRE' then 'responsable'
                when v_role = 'MAGASINIER'   then 'atelier'
                when v_role = 'VENDEUR'      then 'caisse'
                else null
              end;

  update public.utilisateurs
     set nom       = coalesce(nullif(btrim(coalesce(p_nom, '')), ''), nom),
         prenom    = coalesce(btrim(coalesce(p_prenom, '')), prenom),
         telephone = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''), telephone),
         new_role  = coalesce(public.role_enum(v_role), new_role),
         valide    = case when coalesce(p_actif, true) then 1 else 0 end,
         espace_actif_id = coalesce(v_cible_espace, espace_actif_id),
         entreprise_id   = coalesce(
           public.espace_entreprise(v_cible_espace), entreprise_id),
         role_pressing = case
                           when v_cible_espace is null then role_pressing
                           when v_pressing then coalesce(role_pressing, v_metier)
                           else null
                         end,
         press_actif = case
                         when v_cible_espace is null then press_actif
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
                       'boutique', v_owner, 'espace', v_cible_espace,
                       'espace_type', public.espace_type(v_cible_espace),
                       'pressing', v_pressing),
    now()
  );

  return jsonb_build_object(
    'ok', true, 'id', p_id, 'role', v_role,
    'espace_id', v_cible_espace,
    'role_pressing', case when v_pressing then v_metier else null end);
end;
$$;

comment on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid) is
  '0181 — modification d''un collaborateur de l''ESPACE ACTIF uniquement.';

revoke all on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid)
  from public, anon;
grant execute on function public.rpc_collaborateur_maj(uuid, text, text, text, text, boolean, text, uuid)
  to authenticated;


-- ============================================================================
--  6. SUPPRIMER UN COLLABORATEUR — CIBLE LIMITÉE À L'ESPACE ACTIF
-- ============================================================================
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
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_espace uuid;
  v_ent    uuid;
  v_cible  public.utilisateurs%rowtype;
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

  -- ✅ Périmètre : uniquement l'espace actif (repli : son entreprise).
  if not public.est_plateforme() then
    v_espace := public.mon_proprietaire();
    v_ent    := public.espace_entreprise(v_espace);

    if not (
      (v_espace is not null and v_cible.espace_actif_id = v_espace)
      or (v_espace is not null
          and v_cible.espace_actif_id is null
          and v_ent is not null
          and v_cible.entreprise_id = v_ent)
      or (v_espace is null
          and v_ent is not null
          and v_cible.entreprise_id = v_ent)
    ) then
      raise exception 'COLLABORATEUR_HORS_PERIMETRE|Ce collaborateur n''appartient pas à l''entreprise où vous travaillez.';
    end if;
  end if;

  -- Détache les éventuels rattachements enfants (compatibilité historique).
  update public.utilisateurs set parent_id = null where parent_id = p_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COLLABORATEUR_SUPPRIME', p_id,
    jsonb_build_object('par', v_user, 'boutique', v_owner,
                       'espace', v_cible.espace_actif_id,
                       'email', v_cible.email),
    now()
  );

  delete from public.utilisateurs where id = p_id;

  begin
    delete from auth.users where id = p_id;
  exception when others then
    null;
  end;

  return jsonb_build_object('ok', true, 'id', p_id);
end;
$$;

comment on function public.rpc_collaborateur_supprimer(uuid, text) is
  '0181 — suppression d''un collaborateur de l''ESPACE ACTIF uniquement.';

revoke all on function public.rpc_collaborateur_supprimer(uuid, text) from public, anon;
grant execute on function public.rpc_collaborateur_supprimer(uuid, text) to authenticated;


-- ============================================================================
--  7. RLS `utilisateurs` — BORNÉE À L'ESPACE ACTIF
-- ============================================================================
--  Conservé : son propre profil, son patron (affichage du nom), la plateforme,
--  les gardes agents de terrain, l'insertion de son propre profil.

drop policy if exists "Accès via parent_id" on public.utilisateurs;
create policy "Accès via parent_id" on public.utilisateurs
  for select to authenticated
  using (
    (
      parent_id = auth.uid()
      and (
        espace_actif_id = public.mon_proprietaire()
        or (
          espace_actif_id is null
          and entreprise_id = public.espace_entreprise(public.mon_proprietaire())
        )
      )
    )
    or id::text = (auth.jwt() -> 'user_metadata' ->> 'parent_id')
    or id = public.mon_patron()
  );

drop policy if exists zz_lecture_utilisateurs on public.utilisateurs;
create policy zz_lecture_utilisateurs on public.utilisateurs
  for select to authenticated
  using (
    public.est_plateforme()
    or id::text = (auth.uid())::text
    or id = public.mon_patron()
    or (
      parent_id::text = (auth.uid())::text
      and (
        espace_actif_id = public.mon_proprietaire()
        or (
          espace_actif_id is null
          and entreprise_id = public.espace_entreprise(public.mon_proprietaire())
        )
      )
    )
  );

drop policy if exists zz_maj_utilisateurs on public.utilisateurs;
create policy zz_maj_utilisateurs on public.utilisateurs
  for update to authenticated
  using (
    public.est_plateforme()
    or id = auth.uid()
    or (
      parent_id = auth.uid()
      and (
        espace_actif_id = public.mon_proprietaire()
        or (
          espace_actif_id is null
          and entreprise_id = public.espace_entreprise(public.mon_proprietaire())
        )
      )
    )
  )
  with check (
    public.est_plateforme()
    or id = auth.uid()
    or (
      parent_id = auth.uid()
      and (
        espace_actif_id = public.mon_proprietaire()
        or (
          espace_actif_id is null
          and entreprise_id = public.espace_entreprise(public.mon_proprietaire())
        )
      )
    )
  );


-- ============================================================================
--  8. TRIGGER `owner_id` — OPTION A : PRÉSERVER UN ESPACE VALIDE
-- ============================================================================
create or replace function public.owner_espace_actif()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_espace uuid;
begin
  -- Administration plateforme : elle choisit explicitement le propriétaire.
  if public.est_plateforme() then
    return new;
  end if;

  -- Option A — la valeur fournie désigne DÉJÀ un espace valide : on la garde.
  -- (Une vente encaissée hors ligne dans une autre entreprise n'est donc plus
  --  ré-attribuée à l'entreprise active ; la RLS refusera la ligne tant que
  --  cette entreprise n'est pas active, et la synchronisation la rejouera.)
  if new.owner_id is not null
     and exists (
       select 1
         from public.espaces s
        where s.id = new.owner_id
          and coalesce(s.actif, true)
     ) then
    return new;
  end if;

  v_espace := public.mon_proprietaire();
  new.owner_id := coalesce(v_espace, new.owner_id, auth.uid());
  return new;
end;
$$;

comment on function public.owner_espace_actif() is
  '0181 — owner_id : espace valide déjà fourni conservé ; sinon espace de travail actif (mon_proprietaire()), sinon identité.';


-- ============================================================================
--  9. PAIEMENTS PLATEFORME — LECTURE RÉSERVÉE À LA PLATEFORME
-- ============================================================================
drop policy if exists paiements_lecture on public.paiements_abonnement;
drop policy if exists paiements_lecture_plateforme on public.paiements_abonnement;
create policy paiements_lecture_plateforme on public.paiements_abonnement
  for select to authenticated
  using (public.est_plateforme());

drop policy if exists paiements_laperle_lecture on public.paiements_abonnements_laperle;
drop policy if exists paiements_laperle_lecture_plateforme on public.paiements_abonnements_laperle;
create policy paiements_laperle_lecture_plateforme on public.paiements_abonnements_laperle
  for select to authenticated
  using (public.est_plateforme());


-- ============================================================================
--  10. FINANCE — POLICY RESTRICTIVE PAR ESPACE ACTIF
-- ============================================================================
--  Les policies permissives existantes (m10_*) restent en place : elles
--  portent les droits métier (`peut(...)`). La policy RESTRICTIVE ci-dessous
--  ajoute la borne d'ESPACE (et laisse passer la plateforme).

drop policy if exists m10b_depenses_espace_restrictif on public.depenses;
create policy m10b_depenses_espace_restrictif on public.depenses
  as restrictive for all to authenticated
  using (owner_id = public.mon_proprietaire() or public.est_plateforme())
  with check (owner_id = public.mon_proprietaire() or public.est_plateforme());

drop policy if exists m10b_dettes_espace_restrictif on public.dettes;
create policy m10b_dettes_espace_restrictif on public.dettes
  as restrictive for all to authenticated
  using (owner_id = public.mon_proprietaire() or public.est_plateforme())
  with check (owner_id = public.mon_proprietaire() or public.est_plateforme());

drop policy if exists m10b_paiements_dette_espace_restrictif on public.paiements_dette;
create policy m10b_paiements_dette_espace_restrictif on public.paiements_dette
  as restrictive for all to authenticated
  using (owner_id = public.mon_proprietaire() or public.est_plateforme())
  with check (owner_id = public.mon_proprietaire() or public.est_plateforme());

drop policy if exists m10b_clotures_caisse_espace_restrictif on public.clotures_caisse;
create policy m10b_clotures_caisse_espace_restrictif on public.clotures_caisse
  as restrictive for all to authenticated
  using (owner_id = public.mon_proprietaire() or public.est_plateforme())
  with check (owner_id = public.mon_proprietaire() or public.est_plateforme());


-- ============================================================================
--  11. PÉRIMÈTRE DES VENTES — L'UUID DU PATRON N'ENTRE PLUS DEDANS
-- ============================================================================
--  Symptôme rapporté : « quand Urembo vend 1 000 FC, Hekima affiche aussi
--  1 000 FC ». Même propriétaire, deux entreprises DISTINCTES.
--
--  Cause : `perimetre_entreprise()` (0179) ajoutait `entreprises.owner_id`
--  (l'UUID du patron), commun à TOUTES ses entreprises. Or cet UUID est aussi
--  l'identifiant du TOUT PREMIER espace créé à l'inscription : chaque
--  entreprise récupérait donc ce premier espace dans son périmètre — et ses
--  ventes.

create or replace function public.perimetre_entreprise(
  p_entreprise_id uuid default null
)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eid uuid;
  v_arr text[];
begin
  v_eid := public.resoudre_entreprise(p_entreprise_id);

  if v_eid is not null then
    select coalesce(array_agg(distinct x::text), array[]::text[])
      into v_arr
      from (
        select s.id as x
          from public.espaces s
         where s.entreprise_id::text = v_eid::text
        union
        select u.id
          from public.utilisateurs u
         where u.entreprise_id::text = v_eid::text
        union
        -- ⚠️ L'UUID du patron n'est ajouté QUE si l'entreprise n'a AUCUN
        --    espace (comptes d'avant le module 15). Dès qu'elle a ses propres
        --    espaces, il n'apporte rien et appartient à toutes les entreprises
        --    du patron : c'est lui qui mélangeait les ventes.
        select e.owner_id
          from public.entreprises e
         where e.id = v_eid
           and e.owner_id is not null
           and not exists (
             select 1 from public.espaces s2
              where s2.entreprise_id = e.id)
      ) t;
  end if;

  -- Repli : entreprise introuvable (compte sans entreprise) → comportement
  -- historique, limité au propriétaire de l'utilisateur.
  if v_arr is null or coalesce(array_length(v_arr, 1), 0) = 0 then
    v_arr := array[
      coalesce(public.mon_proprietaire(), auth.uid())::text
    ];
  end if;

  return array_remove(v_arr, null);
end;
$$;

comment on function public.perimetre_entreprise(uuid) is
  '0181 — identifiants porteurs de données d''une entreprise : ses espaces + ses utilisateurs (+ UUID du patron seulement si aucun espace).';

grant execute on function public.perimetre_entreprise(uuid) to authenticated;


-- ============================================================================
--  12. ENTREPRISE COURANTE — CELLE DE L'ESPACE ACTIF (VÉRIFIÉ)
-- ============================================================================
create or replace function public.entreprise_courante()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- 1. l'entreprise de l'ESPACE DE TRAVAIL actif (mon_proprietaire())
    (select s.entreprise_id
       from public.espaces s
      where s.id = public.mon_proprietaire()
      limit 1),
    -- 2. l'entreprise de rattachement du compte (mise à jour à la bascule)
    (select u.entreprise_id
       from public.utilisateurs u
      where u.id = auth.uid()
      limit 1),
    -- 3. une entreprise dont l'utilisateur est propriétaire
    (select e.id
       from public.entreprises e
      where e.owner_id = auth.uid()
      order by e.created_at nulls last, e.nom
      limit 1)
  );
$$;

comment on function public.entreprise_courante() is
  '0181 — entreprise de l''ESPACE DE TRAVAIL actif (jamais la première par ordre alphabétique quand un espace est connu).';

grant execute on function public.entreprise_courante() to authenticated;


-- ============================================================================
--  13. RÉPARATION — `espace_actif_id` D'UNE AUTRE ENTREPRISE
-- ============================================================================
--  Un espace actif qui pointe hors de l'entreprise du compte faisait écrire
--  les ventes sous l'UUID du patron (repli) → donc dans la mauvaise
--  entreprise. On le replace sur le premier espace actif de SON entreprise.

update public.utilisateurs u
   set espace_actif_id = (
         select s.id
           from public.espaces s
          where s.entreprise_id = u.entreprise_id
            and s.actif
          order by s.created_at nulls last, s.nom
          limit 1)
 where u.entreprise_id is not null
   and u.espace_actif_id is not null
   and not exists (
     select 1
       from public.espaces s2
      where s2.id = u.espace_actif_id
        and s2.entreprise_id = u.entreprise_id);

update public.utilisateurs u
   set espace_actif_id = (
         select s.id
           from public.espaces s
          where s.entreprise_id = u.entreprise_id
            and s.actif
          order by s.created_at nulls last, s.nom
          limit 1)
 where u.entreprise_id is not null
   and u.espace_actif_id is null
   and exists (
     select 1
       from public.espaces s
      where s.entreprise_id = u.entreprise_id
        and s.actif);


-- ============================================================================
--  14. VERDICT (une seule ligne)
-- ============================================================================
select 'Correctif 0181 — isolation espace/équipe + périmètres installés | équipe : ' ||
       coalesce((select count(*)::text
                   from public.utilisateurs u
                  where u.parent_id is not null), '0') ||
       ' collaborateur(s) au total | trigger owner_id: ' ||
       case when exists (select 1 from pg_proc p
                          join pg_namespace n on n.oid = p.pronamespace
                         where n.nspname = 'public'
                           and p.proname = 'owner_espace_actif')
            then 'OK' else 'ABSENT' end ||
       ' | paiements: plateforme seule | finance: restrictive OK' ||
       ' | périmètres qui se croisent : ' ||
       coalesce((
         select count(*)::text
           from (
             select public.perimetre_entreprise(e1.id) as p1,
                    public.perimetre_entreprise(e2.id) as p2
               from public.entreprises e1
               join public.entreprises e2
                 on e2.owner_id = e1.owner_id
                and e2.id > e1.id
              where e1.owner_id is not null
           ) x
          where x.p1 && x.p2
       ), '0') as verdict;
