-- ============================================================================
--  biashara_yangu — MIGRATION 0151 : FIN DES FONCTIONS AMBIGUËS
--                   + CRÉATION ET RATTACHEMENT DU PRESSING DE lucjean@gmail.com
--
--  PROBLÈMES SIGNALÉS (12/11/2026)
--    • « Dans Mes entreprises : 0 entreprise(s) sur 1 autorisé. »
--    • « Quand je veux créer une entreprise en choisissant pressing :
--        could not choose the best candidate function between:
--        public.rpc_espace_creer(p_nom => text, p_type => text,
--                                p_ville_id => uuid)
--        public.rpc_espace_creer(p_nom => text, p_type => text,
--                                p_ville_id => uuid, p_jours_essai => integer,
--                                p_frais_installation_offert => boolean) »
--
--  CAUSE
--    Les migrations successives ont AJOUTÉ des paramètres (avec valeur par
--    défaut) au lieu de remplacer l'ancienne fonction. PostgreSQL garde donc
--    DEUX fonctions du même nom : un appel qui ne précise pas les nouveaux
--    paramètres correspond aux deux → PostgREST refuse de choisir.
--    (C'est arrivé sur plusieurs fonctions : rpc_entreprise_creer,
--     rpc_espace_creer, rpc_collaborateur_creer/maj, etc.)
--
--  CE QUE FAIT CE SCRIPT
--    1. Supprime les ANCIENNES signatures devenues ambiguës — uniquement
--       quand la nouvelle existe (aucun risque de trouer l'API).
--    2. Diagnostique le compte lucjean@gmail.com (entreprises, espaces, quota).
--    3. Crée — ou répare — son ENTREPRISE DE PRESSING : entreprise, boutique
--       de type `pressing`, rattachement du compte, forfait pressing, essai.
--    4. Vérifie qu'il ne reste AUCUNE fonction ambiguë.
--
--  ⚠️ IDEMPOTENT : relançable sans doublon.
--  ⚠️ Aucune donnée supprimée (seules d'anciennes VERSIONS DE FONCTIONS
--     obsolètes le sont, jamais des lignes de données).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LES ANCIENNES SURCHARGES DISPARAISSENT
-- ============================================================================
--  Règle : on ne supprime une ancienne signature QUE si la nouvelle est
--  présente. La nouvelle accepte tous les anciens appels (paramètres ajoutés
--  avec `default`), donc aucune application publiée ne casse.

do $$
declare
  v_rec       record;
  v_gardee_ok boolean;
begin
  for v_rec in
    select * from (values
      ('rpc_espace_creer',        'text, text, uuid',
       'text, text, uuid, integer, boolean'),
      ('rpc_entreprise_creer',    'text, text',
       'text, text, text'),
      ('rpc_entreprise_creer',    'text',
       'text, text, text'),
      ('rpc_collaborateur_creer', 'text, text, text, text, text, text',
       'text, text, text, text, text, text, uuid'),
      ('rpc_collaborateur_maj',   'uuid, text, text, text, text, boolean, text',
       'uuid, text, text, text, text, boolean, text, uuid'),
      ('rpc_agent_code_emettre',  'uuid',
       'uuid, boolean'),
      ('rpc_serdipay_ouvrir',     'text, uuid, text, text, uuid',
       'text, uuid, text, text, uuid, numeric'),
      ('dist_vente_enregistrer',  'uuid, jsonb, numeric, text, text',
       'uuid, jsonb, numeric, text, text, text, text'),
      ('dist_bonus_declarer',     'uuid, text, numeric, text, text, uuid',
       'uuid, text, numeric, text, text, uuid, text')
    ) as t(fonction, ancienne, gardee)
  loop
    select exists (
      select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = v_rec.fonction
         and pg_get_function_identity_arguments(p.oid) = v_rec.gardee
    ) into v_gardee_ok;

    if not v_gardee_ok then
      raise notice '0151 — %(%) absente de la base : ancienne version conservée.',
        v_rec.fonction, v_rec.gardee;
      continue;
    end if;

    if exists (
      select 1 from pg_proc p
        join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and p.proname = v_rec.fonction
         and pg_get_function_identity_arguments(p.oid) = v_rec.ancienne
    ) then
      execute format('drop function public.%I(%s)', v_rec.fonction, v_rec.ancienne);
      raise notice '0151 — ancienne surcharge supprimée : %(%)',
        v_rec.fonction, v_rec.ancienne;
    end if;
  end loop;
end $$;


-- ============================================================================
--  2. ÉTAT DES LIEUX — lucjean@gmail.com
-- ============================================================================

select 'COMPTE' as etape,
       u.id,
       u.email,
       coalesce(u.nom, '') || ' ' || coalesce(u.prenom, '') as nom,
       coalesce(u.new_role::text, u.role) as role,
       u.valide,
       u.parent_id,
       u.entreprise_id  as entreprise_active,
       u.espace_actif_id as espace_actif
  from public.utilisateurs u
 where lower(u.email) = 'lucjean@gmail.com';

select 'ENTREPRISES DU COMPTE' as etape,
       e.id,
       e.nom,
       e.owner_id,
       e.type_activite,
       e.statut::text as statut,
       g.nom          as groupe_tarifaire,
       (select count(*) from public.espaces s where s.entreprise_id = e.id)
                      as nb_boutiques
  from public.utilisateurs u
  join public.entreprises e
    on e.owner_id = coalesce(u.parent_id, u.id)
    or e.id = u.entreprise_id
  left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
 where lower(u.email) = 'lucjean@gmail.com';

select 'BOUTIQUES DU COMPTE' as etape,
       s.id,
       s.nom,
       s.type,
       s.actif,
       e.nom as entreprise
  from public.utilisateurs u
  join public.espaces s
    on s.id = u.espace_actif_id
    or s.entreprise_id = u.entreprise_id
    or s.entreprise_id in (
         select e2.id from public.entreprises e2
          where e2.owner_id = coalesce(u.parent_id, u.id))
  left join public.entreprises e on e.id = s.entreprise_id
 where lower(u.email) = 'lucjean@gmail.com';


-- ============================================================================
--  3. SON ENTREPRISE DE PRESSING : CRÉÉE, PUIS RATTACHÉE
-- ============================================================================
--    • entreprise « Pressing <nom du patron> » (ou le nom déjà présent) ;
--    • boutique de type `pressing` → modules dépôts / atelier / retraits ;
--    • forfait pressing (10 000 FC/mois) et essai de 7 jours ;
--    • le compte devient PROPRIÉTAIRE de cette entreprise et y bascule.

do $$
declare
  -- ─────────────────────────── PARAMÈTRES ───────────────────────────
  v_email       text    := 'lucjean@gmail.com';
  v_nom_force   text    := null;      -- ex. 'Pressing Luc Jean' ; null = auto
  v_jours_essai integer := 7;
  -- ──────────────────────────────────────────────────────────────────

  v_uid      uuid;
  v_patron   uuid;
  v_nom_cpt  text;
  v_nom      text;
  v_ent      uuid;
  v_esp      uuid;
  v_grille   uuid;
  v_act      uuid;
  v_type_ok  boolean := false;
  v_total    numeric;
begin
  select u.id, coalesce(u.parent_id, u.id),
         nullif(btrim(coalesce(u.nom, '') || ' ' || coalesce(u.prenom, '')), '')
    into v_uid, v_patron, v_nom_cpt
    from public.utilisateurs u
   where lower(u.email) = lower(v_email)
   limit 1;

  if v_uid is null then
    raise warning '0151 — % introuvable : aucun compte à rattacher.', v_email;
    return;
  end if;

  -- 1) L'entreprise existe-t-elle déjà pour ce patron ?
  select e.id into v_ent
    from public.entreprises e
   where e.owner_id = v_patron
      or (e.owner_id is null and e.id = (select u.entreprise_id
                                           from public.utilisateurs u
                                          where u.id = v_uid))
   order by e.created_at nulls first
   limit 1;

  v_nom := coalesce(
             nullif(btrim(coalesce(v_nom_force, '')), ''),
             case when v_nom_cpt is not null
                  then 'Pressing ' || v_nom_cpt
                  else 'Pressing' end);

  if v_ent is null then
    insert into public.entreprises (nom, owner_id)
    values (v_nom, v_patron)
    returning id into v_ent;

    raise notice '0151 — entreprise « % » créée pour %.', v_nom, v_email;
  else
    select e.nom into v_nom from public.entreprises e where e.id = v_ent;
    raise notice '0151 — entreprise existante réutilisée : « % » (%).', v_nom, v_ent;
  end if;

  -- 2) Le type `pressing` est-il accepté (contrainte élargie par la 0150) ?
  begin
    update public.entreprises
       set owner_id      = coalesce(owner_id, v_patron),
           type_activite = 'pressing',
           updated_at    = now()
     where id = v_ent;
    v_type_ok := true;
  exception
    when others then
      -- Base pas encore migrée par 0150 (ou colonne absente) : on garde le
      -- type tel quel — la catégorie de l'ESPACE suffit à activer les
      -- modules du pressing.
      update public.entreprises
         set owner_id = coalesce(owner_id, v_patron),
             updated_at = now()
       where id = v_ent;
      raise warning '0151 — type_activite non écrit (%) : exécutez la migration 0150.', sqlerrm;
  end;

  -- 3) La boutique (espace) de type pressing.
  select s.id into v_esp
    from public.espaces s
   where s.entreprise_id = v_ent
     and (s.type = 'pressing'
          or lower(coalesce(s.nom, '')) = lower(v_nom))
   order by (s.type = 'pressing') desc, s.created_at
   limit 1;

  if v_esp is null then
    select s.id into v_esp
      from public.espaces s
     where s.entreprise_id = v_ent
     order by s.created_at
     limit 1;
  end if;

  if v_esp is null then
    insert into public.espaces (entreprise_id, nom, type, actif)
    values (v_ent, v_nom, 'pressing', true)
    returning id into v_esp;
    raise notice '0151 — boutique pressing créée : % (%)', v_nom, v_esp;
  else
    -- On ne RENOMME pas une boutique existante (le patron peut l'avoir
    -- nommée lui-même) : on change seulement sa catégorie.
    update public.espaces
       set type  = 'pressing',
           actif = true
     where id = v_esp;
    raise notice '0151 — boutique existante convertie en pressing : % (%)',
      (select s.nom from public.espaces s where s.id = v_esp), v_esp;
  end if;

  -- 4) Le compte devient PROPRIÉTAIRE de cette entreprise et y bascule.
  update public.utilisateurs
     set entreprise_id   = v_ent,
         espace_actif_id = v_esp,
         new_role        = coalesce(new_role, public.role_enum('PROPRIETAIRE')),
         role            = case when parent_id is null
                                then 'PROPRIETAIRE'
                                else role end
   where id = v_uid;

  raise notice '0151 — % rattaché à « % » / boutique %.', v_email, v_nom, v_esp;

  -- 5) Forfait pressing (si la migration 0150 l'a créé).
  select g.id into v_grille
    from public.groupes_tarifaires g
    left join public.activites a on a.id = g.activite_id
   where lower(coalesce(g.nom, '')) like '%pressing%'
      or lower(coalesce(a.nom, '')) like '%pressing%'
   order by g.created_at nulls first
   limit 1;

  select a.id into v_act
    from public.activites a
   where lower(coalesce(a.nom, '')) like '%pressing%'
   order by a.created_at
   limit 1;

  -- 6) Abonnement : essai de 7 jours, installation offerte, montant dû réel.
  update public.entreprises
     set statut              = 'ESSAI_7J'::public.statut_abonnement_enum,
         activation_etape    = 'actif',
         date_activation     = coalesce(date_activation, now()),
         date_expiration     = coalesce(date_expiration,
                                        now() + make_interval(days => v_jours_essai)),
         prix_installation   = 0,
         groupe_tarifaire_id = coalesce(groupe_tarifaire_id, v_grille),
         updated_at          = now()
   where id = v_ent
     and (date_expiration is null or date_expiration < now());

  v_total := public.abonnement_prix_base(v_ent)
             + public.abonnement_supplement_collaborateurs(v_ent);

  update public.entreprises
     set montant_total_du = coalesce(nullif(v_total, 0), montant_total_du, 0),
         updated_at       = now()
   where id = v_ent;

  -- 7) Trace.
  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (gen_random_uuid(), v_ent, 'ENTREPRISE_PRESSING_RATTACHEE', null,
            jsonb_build_object(
              'email',     v_email,
              'entreprise', v_nom,
              'espace_id', v_esp,
              'type',      'pressing',
              'essai_jours', v_jours_essai,
              'type_activite_ecrit', v_type_ok),
            now());
  exception when others then null;
  end;

  raise notice '0151 — TERMINÉ. % est propriétaire de « % » (pressing), montant dû % FC.',
    v_email, v_nom, coalesce(v_total, 0);
end $$;


-- ============================================================================
--  4. CONTRÔLES
-- ============================================================================

select 'APRÈS — COMPTE' as etape,
       u.email,
       coalesce(u.new_role::text, u.role)                  as role,
       e.nom                                               as entreprise,
       e.type_activite,
       e.statut::text                                      as statut,
       to_char(e.date_expiration, 'DD/MM/YYYY HH24:MI')    as echeance,
       (select s.nom from public.espaces s where s.id = u.espace_actif_id)
                                                           as boutique,
       (select s.type from public.espaces s where s.id = u.espace_actif_id)
                                                           as type_boutique,
       e.montant_total_du
  from public.utilisateurs u
  left join public.entreprises e
    on e.id = u.entreprise_id
    or e.owner_id = coalesce(u.parent_id, u.id)
 where lower(u.email) = 'lucjean@gmail.com';

-- Le quota vu par « Mes entreprises » : 1 entreprise / 1 autorisé.
select 'QUOTA (MES ENTREPRISES)' as etape,
       count(distinct e.id)                                        as entreprises,
       coalesce(max(g.max_espaces), 1)                             as autorisees
  from public.entreprises e
  left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
  join public.utilisateurs u on u.id = coalesce(e.owner_id, e.id)
 where lower(u.email) = 'lucjean@gmail.com';

-- Plus aucune fonction du même nom avec deux signatures différentes ?
select 'FONCTIONS AMBIGUËS' as controle,
       count(*) as restantes,
       coalesce(string_agg(nom || ' : ' || signatures, ' | '), 'aucune') as detail
  from (
    select p.proname as nom,
           string_agg(pg_get_function_identity_arguments(p.oid), '  ||  ') as signatures,
           count(*) as nb
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname like 'rpc\_%'
     group by p.proname
    having count(*) > 1
  ) s;

select 'MIGRATION 0151 TERMINÉE' as controle,
       'Dans l''application : déconnexion → reconnexion sur lucjean@gmail.com.' as consigne;
