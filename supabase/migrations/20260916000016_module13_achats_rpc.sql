-- ============================================================================
--  biashara_yangu — MODULE 13 : ASSISTANT IA (DEEPSEEK) — ÉTAPE 6/7 (SQL)
--
--  Cette migration complète le module côté BASE :
--
--    1. `rpc_agent_ia_etat()` — état complet pour l'application : config
--       (tarifs), POOL de l'entreprise (créé au premier appel + BONUS DE
--       BIENVENUE crédité une seule fois), MON allocation, collaborateurs
--       (pour l'attribution par le patron), drapeaux propriétaire/plateforme ;
--    2. `rpc_agent_ia_demander_achat(...)` — un membre DEMANDE un pack ; le
--       MONTANT est calculé côté serveur (jamais fourni par le client) ;
--    3. `rpc_agent_ia_valider_achat(...)` — le SUPER ADMIN approuve/refuse ;
--       l'approbation CRÉDITE le pool (ou le demandeur s'il n'a pas
--       d'entreprise — cas des tests plateforme) ;
--    4. `rpc_agent_ia_marquer_paye(...)` — le PROPRIÉTAIRE règle depuis SA
--       CAISSE (la dépense est écrite dans `depenses`) ou le Super Admin
--       confirme l'encaissement ; le statut payé/impayé reste SUIVI ;
--    5. `rpc_agent_ia_attribuer(...)` — le PATRON distribue le pool vers un
--       membre (débit atomique du pool → crédit de l'allocation) ;
--    6. `rpc_agent_ia_config_maj(...)` — le Super Admin modifie les tarifs
--       (100-150 CDF, 20 caractères/quota, pack de 10, quotas offerts, actif) ;
--    7. PAGE `assistant_ia` — nouveau droit fin : PROPRIÉTAIRE, VENDEUR,
--       MAGASINIER et COMPTABLE_ENTREPRISE peuvent ouvrir l'assistant
--       (actions `voir` + `creer`) ;
--    8. `audit_niveau()` — niveaux des nouvelles actions
--       (AGENT_IA, AGENT_IA_ACHAT, AGENT_IA_ATTRIBUTION, AGENT_IA_CONFIG).
--
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable.
do $$
declare
  v_table text;
  v_fonction text;
begin
  foreach v_table in array array[
    'agent_ia_config', 'agent_ia_quotas', 'agent_ia_achats', 'depenses'
  ] loop
    if not exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = v_table
    ) then
      raise exception
        'Table public.% absente : exécutez d''abord les migrations du Module 13 (Étapes 1-2).', v_table;
    end if;
  end loop;

  foreach v_fonction in array array[
    'est_plateforme', 'est_super_admin', 'mon_role', 'mon_proprietaire',
    'actions_permissions', 'role_enum'
  ] loop
    if not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where p.proname = v_fonction and n.nspname = 'public'
    ) then
      raise exception
        'Fonction public.% absente : exécutez d''abord le Module 4.', v_fonction;
    end if;
  end loop;
end $$;


-- ============================================================================
--  1. `rpc_agent_ia_etat` — ÉTAT COMPLET POUR L'APPLICATION
-- ============================================================================
--  Crée le POOL de l'entreprise au premier appel et y crédite le bonus de
--  bienvenue (`quotas_offerts_inscription`) — UNE SEULE FOIS (la ligne pool
--  n'existe qu'une par entreprise, cf. index unique partiel de l'Étape 1).

create or replace function public.rpc_agent_ia_etat()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_plateforme boolean;
  v_owner      uuid;
  v_config     public.agent_ia_config%rowtype;
  v_pool       public.agent_ia_quotas%rowtype;
  v_moi        public.agent_ia_quotas%rowtype;
  v_collab     jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter vos quotas.';
  end if;

  v_plateforme := public.est_plateforme();

  select * into v_config from public.agent_ia_config limit 1;
  if v_config.id is null then
    raise exception 'CONFIG_ABSENTE|Configuration IA absente : exécutez 20260916000014_module13_agent_ia.sql.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- POOL de l'entreprise + bonus de bienvenue (une seule fois).
  if not v_plateforme then
    select * into v_pool
      from public.agent_ia_quotas
     where utilisateur_id is null
       and entreprise_id = v_owner;

    if v_pool.id is null then
      insert into public.agent_ia_quotas (
        utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
      ) values (
        null, v_owner, greatest(coalesce(v_config.quotas_offerts_inscription, 0), 0), 0
      )
      on conflict do nothing;

      select * into v_pool
        from public.agent_ia_quotas
       where utilisateur_id is null
         and entreprise_id = v_owner;
    end if;
  end if;

  -- Mon allocation personnelle.
  select * into v_moi
    from public.agent_ia_quotas
   where utilisateur_id = v_user;

  -- Collaborateurs de l'entreprise (pour l'attribution par le patron).
  if not v_plateforme and v_owner = v_user then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id',   u.id,
             'nom',  coalesce(nullif(btrim(u.nom), ''), u.email),
             'role', coalesce(u.new_role::text, u.role, '')
           ) order by u.nom), '[]'::jsonb)
      into v_collab
      from public.utilisateurs u
     where u.id <> v_user
       and (u.parent_id = v_owner or u.entreprise_id = v_owner);
  end if;

  return jsonb_build_object(
    'config', jsonb_build_object(
      'tarif_par_quota',           v_config.tarif_par_quota,
      'caracteres_par_quota',      v_config.caracteres_par_quota,
      'prix_pack_10_quotas',       v_config.prix_pack_10_quotas,
      'quotas_offerts_inscription', v_config.quotas_offerts_inscription,
      'actif',                     v_config.actif
    ),
    'pool', case when v_pool.id is null then null else jsonb_build_object(
      'quotas_disponibles',   v_pool.quotas_disponibles,
      'quotas_achetes_total', v_pool.quotas_achetes_total
    ) end,
    'moi', jsonb_build_object(
      'quotas_disponibles',    coalesce(v_moi.quotas_disponibles, 0),
      'quotas_utilises_total', coalesce(v_moi.quotas_utilises_total, 0),
      'quotas_achetes_total',  coalesce(v_moi.quotas_achetes_total, 0)
    ),
    'role',            public.mon_role(),
    'est_proprietaire', (not v_plateforme and v_owner = v_user),
    'est_plateforme',  v_plateforme,
    'est_super_admin', public.est_super_admin(),
    'collaborateurs',  v_collab
  );
end;
$$;

comment on function public.rpc_agent_ia_etat() is
  'Module 13 — État IA pour l''application : config, pool (+ bonus de bienvenue une fois), mon allocation, collaborateurs.';


-- ============================================================================
--  2. `rpc_agent_ia_demander_achat` — DEMANDE DE PACK (MONTANT SERVEUR)
-- ============================================================================

create or replace function public.rpc_agent_ia_demander_achat(
  p_nombre_quotas integer,
  p_mode_paiement text default 'especes',
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_plateforme boolean;
  v_owner      uuid;
  v_config     public.agent_ia_config%rowtype;
  v_mode       text := lower(btrim(coalesce(p_mode_paiement, 'especes')));
  v_montant    numeric(12,2);
  v_id         uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour demander des quotas.';
  end if;

  -- Packs autorisés (cahier des charges).
  if p_nombre_quotas is null or p_nombre_quotas not in (10, 20, 50, 100) then
    raise exception 'PACK_INVALIDE|Choisissez un pack de 10, 20, 50 ou 100 quotas.';
  end if;

  if v_mode not in ('especes', 'mobile_money', 'carte', 'virement') then
    raise exception 'MODE_INVALIDE|Mode de paiement inconnu.';
  end if;

  select * into v_config from public.agent_ia_config limit 1;
  if v_config.id is null or v_config.actif is not true then
    raise exception 'ASSISTANT_INDISPONIBLE|L''assistant IA n''est pas activé.';
  end if;

  v_plateforme := public.est_plateforme();
  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- Montant calculé côté SERVEUR : (quotas / 10) × prix du pack de 10.
  v_montant := round((p_nombre_quotas::numeric / 10.0) * v_config.prix_pack_10_quotas, 2);

  insert into public.agent_ia_achats (
    utilisateur_id, entreprise_id, nombre_quotas, montant_cdf,
    mode_paiement, statut, statut_paiement, enregistre_par, note
  ) values (
    v_user,
    case when v_plateforme then null else v_owner end,
    p_nombre_quotas, v_montant,
    v_mode, 'demande', 'impaye', v_user, nullif(btrim(coalesce(p_note, '')), '')
  )
  returning id into v_id;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'AGENT_IA_ACHAT', v_user,
    jsonb_build_object(
      'etape',         'demande',
      'achat_id',      v_id,
      'nombre_quotas', p_nombre_quotas,
      'montant_cdf',   v_montant,
      'mode_paiement', v_mode,
      'boutique',      case when v_plateforme then null else v_owner end
    )
  );

  return jsonb_build_object(
    'achat_id',        v_id,
    'statut',          'demande',
    'statut_paiement', 'impaye',
    'nombre_quotas',   p_nombre_quotas,
    'montant_cdf',     v_montant
  );
end;
$$;

comment on function public.rpc_agent_ia_demander_achat(integer, text, text) is
  'Module 13 — Demande d''achat d''un pack de quotas (montant calculé serveur) ; le Super Admin valide ensuite.';


-- ============================================================================
--  3. `rpc_agent_ia_valider_achat` — SUPER ADMIN : APPROUVER / REFUSER
-- ============================================================================

create or replace function public.rpc_agent_ia_valider_achat(
  p_achat_id  uuid,
  p_approuver boolean,
  p_note      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_achat  public.agent_ia_achats%rowtype;
  v_note   text := nullif(btrim(coalesce(p_note, '')), '');
  v_credit integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour traiter les demandes.';
  end if;

  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin valide les demandes de quotas.';
  end if;

  select * into v_achat
    from public.agent_ia_achats
   where id = p_achat_id
     for update;

  if v_achat.id is null then
    raise exception 'ACHAT_INTROUVABLE|Demande introuvable.';
  end if;

  if v_achat.statut <> 'demande' then
    raise exception 'DEJA_TRAITE|Cette demande a déjà été traitée (%).', v_achat.statut;
  end if;

  if p_approuver is true then
    update public.agent_ia_achats
       set statut     = 'approuve',
           valide_par = v_user,
           valide_le  = now(),
           note       = coalesce(v_note, note)
     where id = v_achat.id;

    if v_achat.entreprise_id is not null then
      -- Crédit du POOL de l'entreprise (upsert atomique).
      insert into public.agent_ia_quotas (
        utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
      ) values (
        null, v_achat.entreprise_id, v_achat.nombre_quotas, v_achat.nombre_quotas
      )
      on conflict (entreprise_id) where utilisateur_id is null
      do update set
        quotas_disponibles   = public.agent_ia_quotas.quotas_disponibles   + excluded.quotas_disponibles,
        quotas_achetes_total = public.agent_ia_quotas.quotas_achetes_total + excluded.quotas_achetes_total,
        updated_at           = now();
    else
      -- Pas d'entreprise (tests plateforme) : crédit direct du demandeur.
      insert into public.agent_ia_quotas (
        utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
      ) values (
        v_achat.utilisateur_id, null, v_achat.nombre_quotas, v_achat.nombre_quotas
      )
      on conflict (utilisateur_id)
      do update set
        quotas_disponibles   = public.agent_ia_quotas.quotas_disponibles   + excluded.quotas_disponibles,
        quotas_achetes_total = public.agent_ia_quotas.quotas_achetes_total + excluded.quotas_achetes_total,
        updated_at           = now();
    end if;

    v_credit := v_achat.nombre_quotas;
  else
    update public.agent_ia_achats
       set statut     = 'refuse',
           valide_par = v_user,
           valide_le  = now(),
           note       = coalesce(v_note, note)
     where id = v_achat.id;
  end if;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'AGENT_IA_ACHAT', v_user,
    jsonb_build_object(
      'etape',         case when p_approuver then 'approuve' else 'refuse' end,
      'achat_id',      v_achat.id,
      'nombre_quotas', v_achat.nombre_quotas,
      'montant_cdf',   v_achat.montant_cdf,
      'demandeur',     v_achat.utilisateur_id,
      'credite',       v_credit,
      'note',          v_note,
      'boutique',      v_achat.entreprise_id
    )
  );

  return jsonb_build_object(
    'achat_id',        v_achat.id,
    'statut',          case when p_approuver then 'approuve' else 'refuse' end,
    'statut_paiement', v_achat.statut_paiement,
    'montant_cdf',     v_achat.montant_cdf,
    'quotas_credites', v_credit
  );
end;
$$;

comment on function public.rpc_agent_ia_valider_achat(uuid, boolean, text) is
  'Module 13 — Super Admin : approuve (crédite le pool) ou refuse une demande de quotas.';


-- ============================================================================
--  4. `rpc_agent_ia_marquer_paye` — PAIEMENT SUIVI (CAISSE ou PLATEFORME)
-- ============================================================================
--  • PROPRIÉTAIRE : il paie depuis SA caisse → une DÉPENSE est écrite dans
--    `depenses` (catégorie « ia ») par la RPC officielle du Module 10 ;
--  • SUPER ADMIN : il confirme l'encaissement (pas de dépense interne).
--  Le montant reste TOUJOURS visible sur la ligne d'achat, payé ou non.

create or replace function public.rpc_agent_ia_marquer_paye(
  p_achat_id uuid,
  p_note     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user             uuid := auth.uid();
  v_sa               boolean;
  v_achat            public.agent_ia_achats%rowtype;
  v_note             text := nullif(btrim(coalesce(p_note, '')), '');
  v_est_proprietaire boolean := false;
  v_owner            uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer le paiement.';
  end if;

  v_sa := public.est_super_admin();

  select * into v_achat
    from public.agent_ia_achats
   where id = p_achat_id
     for update;

  if v_achat.id is null then
    raise exception 'ACHAT_INTROUVABLE|Demande introuvable.';
  end if;

  if v_achat.statut_paiement = 'paye' then
    raise exception 'PAIEMENT_DEJA|Ce paiement est déjà marqué payé.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  v_est_proprietaire :=
    (not v_sa)
    and v_achat.entreprise_id is not null
    and v_achat.entreprise_id = v_owner
    and public.mon_role() = 'PROPRIETAIRE';

  if not (v_sa or v_est_proprietaire) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire de l''entreprise (caisse) ou le Super Admin peut marquer ce paiement payé.';
  end if;

  update public.agent_ia_achats
     set statut_paiement = 'paye',
         note            = coalesce(v_note, note)
   where id = v_achat.id;

  -- L'entreprise paie DEPUIS SA CAISSE : écriture officielle de dépense.
  if v_est_proprietaire then
    perform public.rpc_depense_creer(
      p_motif     => 'Quotas IA — ' || v_achat.nombre_quotas || ' quotas',
      p_montant   => v_achat.montant_cdf,
      p_categorie => 'ia'
    );
  end if;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'PAIEMENT_ENREGISTRE', v_user,
    jsonb_build_object(
      'type',        'quotas_ia',
      'achat_id',    v_achat.id,
      'montant_cdf', v_achat.montant_cdf,
      'par',         case when v_sa then 'super_admin' else 'proprietaire' end,
      'boutique',    v_achat.entreprise_id
    )
  );

  return jsonb_build_object(
    'achat_id',        v_achat.id,
    'statut_paiement', 'paye',
    'montant_cdf',     v_achat.montant_cdf
  );
end;
$$;

comment on function public.rpc_agent_ia_marquer_paye(uuid, text) is
  'Module 13 — Marque un achat payé : dépense de caisse si le propriétaire encaisse, simple confirmation pour le Super Admin.';


-- ============================================================================
--  5. `rpc_agent_ia_attribuer` — LE PATRON DISTRIBUE LE POOL
-- ============================================================================

create or replace function public.rpc_agent_ia_attribuer(
  p_utilisateur uuid,
  p_quotas      integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user           uuid := auth.uid();
  v_owner          uuid;
  v_pool_restant   integer;
  v_solde_dest     integer;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour attribuer des quotas.';
  end if;

  if public.est_plateforme() or public.mon_role() <> 'PROPRIETAIRE' then
    raise exception 'DROIT_REFUSE|Seul le propriétaire distribue les quotas de son entreprise.';
  end if;

  if p_utilisateur is null or p_quotas is null or p_quotas < 1 or p_quotas > 10000 then
    raise exception 'PARAMETRES_INVALIDES|Choisissez un membre et un nombre de quotas valide.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- Le destinataire doit appartenir à l'entreprise.
  if not exists (
    select 1 from public.utilisateurs u
     where u.id = p_utilisateur
       and (u.id = v_owner or u.parent_id = v_owner or u.entreprise_id = v_owner)
  ) then
    raise exception 'HORS_BOUTIQUE|Ce collaborateur n''appartient pas à votre entreprise.';
  end if;

  -- Débit ATOMIQUE du pool.
  update public.agent_ia_quotas q
     set quotas_disponibles = q.quotas_disponibles - p_quotas,
         updated_at         = now()
   where q.utilisateur_id is null
     and q.entreprise_id = v_owner
     and q.quotas_disponibles >= p_quotas
  returning q.quotas_disponibles into v_pool_restant;

  if not found then
    raise exception 'POOL_INSUFFISANT|Le pool de votre entreprise ne contient pas assez de quotas : demandez ou achetez un pack.';
  end if;

  -- Crédit de l'allocation du membre (upsert).
  insert into public.agent_ia_quotas (
    utilisateur_id, entreprise_id, quotas_disponibles, attribue_par, attribue_le
  ) values (
    p_utilisateur, v_owner, p_quotas, v_user, now()
  )
  on conflict (utilisateur_id)
  do update set
    quotas_disponibles = public.agent_ia_quotas.quotas_disponibles + excluded.quotas_disponibles,
    attribue_par       = excluded.attribue_par,
    attribue_le        = excluded.attribue_le,
    updated_at         = now()
  returning quotas_disponibles into v_solde_dest;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'AGENT_IA_ATTRIBUTION', v_user,
    jsonb_build_object(
      'destinataire',   p_utilisateur,
      'nombre_quotas',  p_quotas,
      'pool_restant',   v_pool_restant,
      'solde_membre',   v_solde_dest,
      'boutique',       v_owner
    )
  );

  return jsonb_build_object(
    'ok',                true,
    'pool_restant',      v_pool_restant,
    'solde_destinataire', v_solde_dest
  );
end;
$$;

comment on function public.rpc_agent_ia_attribuer(uuid, integer) is
  'Module 13 — Le propriétaire attribue des quotas du pool à un membre (débit atomique + trace).';


-- ============================================================================
--  6. `rpc_agent_ia_config_maj` — SUPER ADMIN : RÉGLAGES IA
-- ============================================================================

create or replace function public.rpc_agent_ia_config_maj(
  p_tarif_par_quota            numeric default null,
  p_caracteres_par_quota       integer default null,
  p_prix_pack_10_quotas        numeric default null,
  p_quotas_offerts_inscription integer default null,
  p_actif                      boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_config public.agent_ia_config%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier la configuration.';
  end if;

  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin modifie la configuration IA.';
  end if;

  if p_tarif_par_quota is not null
     and (p_tarif_par_quota < 100 or p_tarif_par_quota > 150) then
    raise exception 'TARIF_INVALIDE|Le tarif doit être compris entre 100 et 150 CDF par quota.';
  end if;

  if p_caracteres_par_quota is not null
     and (p_caracteres_par_quota < 1 or p_caracteres_par_quota > 500) then
    raise exception 'CARACTERES_INVALIDE|Le nombre de caractères par quota doit être entre 1 et 500.';
  end if;

  if p_prix_pack_10_quotas is not null and p_prix_pack_10_quotas < 0 then
    raise exception 'PRIX_INVALIDE|Le prix du pack ne peut pas être négatif.';
  end if;

  if p_quotas_offerts_inscription is not null
     and (p_quotas_offerts_inscription < 0 or p_quotas_offerts_inscription > 1000) then
    raise exception 'OFFERTS_INVALIDE|Les quotas offerts doivent être entre 0 et 1000.';
  end if;

  update public.agent_ia_config
     set tarif_par_quota            = coalesce(p_tarif_par_quota, tarif_par_quota),
         caracteres_par_quota       = coalesce(p_caracteres_par_quota, caracteres_par_quota),
         prix_pack_10_quotas        = coalesce(p_prix_pack_10_quotas, prix_pack_10_quotas),
         quotas_offerts_inscription = coalesce(p_quotas_offerts_inscription, quotas_offerts_inscription),
         actif                      = coalesce(p_actif, actif),
         updated_at                 = now(),
         updated_by                 = v_user
   where id = (select id from public.agent_ia_config limit 1)
  returning * into v_config;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'AGENT_IA_CONFIG', v_user,
    jsonb_build_object(
      'tarif_par_quota',            v_config.tarif_par_quota,
      'caracteres_par_quota',       v_config.caracteres_par_quota,
      'prix_pack_10_quotas',        v_config.prix_pack_10_quotas,
      'quotas_offerts_inscription', v_config.quotas_offerts_inscription,
      'actif',                      v_config.actif
    )
  );

  return jsonb_build_object(
    'tarif_par_quota',            v_config.tarif_par_quota,
    'caracteres_par_quota',       v_config.caracteres_par_quota,
    'prix_pack_10_quotas',        v_config.prix_pack_10_quotas,
    'quotas_offerts_inscription', v_config.quotas_offerts_inscription,
    'actif',                      v_config.actif
  );
end;
$$;

comment on function public.rpc_agent_ia_config_maj(numeric, integer, numeric, integer, boolean) is
  'Module 13 — Super Admin : met à jour les tarifs/réglages de l''assistant IA (journalisé AGENT_IA_CONFIG).';


-- ============================================================================
--  7. PERMISSIONS — PAGE `assistant_ia`
-- ============================================================================

create or replace function public.pages_permissions()
returns text[]
language sql
immutable
as $$
  select array[
    'dashboard', 'entreprises', 'utilisateurs', 'villes', 'activites',
    'groupes_tarifaires', 'abonnements', 'paiements', 'finance', 'audit',
    'securite', 'notifications', 'assistance', 'parametres', 'ventes',
    'caisse', 'scanner', 'panier', 'articles', 'stock', 'clients',
    'fournisseurs', 'depenses', 'collaborateurs', 'qr_codes', 'rapports',
    'assistant_ia'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4, + securite Module 12, + assistant_ia Module 13).';

-- Matrice par défaut — copie Module 12 + page `assistant_ia` pour les rôles
-- d'entreprise (voir + creer).
create or replace function public.permissions_defaut(p_role text)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_role    text := upper(btrim(coalesce(p_role, '')));
  v_pages   text[];
  v_actions text[];
  v_result  jsonb := '{}'::jsonb;
  v_page    text;
begin
  -- SUPER_ADMIN : toutes les pages, toutes les actions.
  if v_role = 'SUPER_ADMIN' then
    select jsonb_object_agg(p, to_jsonb(public.actions_permissions()))
      into v_result
      from unnest(public.pages_permissions()) as p;
    return coalesce(v_result, '{}'::jsonb);
  end if;

  case v_role
    when 'GESTIONNAIRE_COMPTES' then
      v_pages   := array['entreprises', 'utilisateurs', 'villes', 'activites',
                         'groupes_tarifaires', 'abonnements', 'assistance',
                         'notifications'];
      v_actions := array['voir', 'creer', 'modifier'];

    when 'FINANCE_LAPERLE' then
      v_pages   := array['dashboard', 'abonnements', 'paiements', 'finance',
                         'rapports', 'audit', 'notifications'];
      v_actions := array['voir', 'creer', 'valider'];

    when 'SUPPORT' then
      v_pages   := array['dashboard', 'assistance', 'entreprises', 'utilisateurs',
                         'abonnements', 'notifications'];
      v_actions := array['voir'];

    when 'PROPRIETAIRE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'scanner', 'panier',
                         'articles', 'qr_codes', 'stock', 'clients', 'fournisseurs',
                         'finance', 'depenses', 'collaborateurs', 'rapports',
                         'abonnements', 'audit', 'assistant_ia', 'parametres'];
      v_actions := public.actions_permissions();

    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier', 'assistant_ia'];
      v_actions := array['voir', 'creer'];

    when 'MAGASINIER' then
      v_pages   := array['stock', 'articles', 'qr_codes', 'rapports',
                         'assistant_ia'];
      v_actions := array['voir'];

    when 'COMPTABLE_ENTREPRISE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'depenses', 'rapports',
                         'finance', 'assistant_ia', 'parametres'];
      v_actions := array['voir'];

    else
      return '{}'::jsonb;
  end case;

  foreach v_page in array v_pages loop
    v_result := jsonb_set(v_result, array[v_page], to_jsonb(v_actions), true);
  end loop;

  -- Exceptions par page.
  v_result := case v_role
    when 'SUPPORT' then v_result
      || jsonb_build_object('assistance',    to_jsonb(array['voir', 'modifier']))
      || jsonb_build_object('notifications', to_jsonb(array['voir', 'modifier']))
    when 'MAGASINIER' then v_result
      || jsonb_build_object('stock',        to_jsonb(array['voir', 'creer', 'modifier']))
      || jsonb_build_object('qr_codes',     to_jsonb(array['voir', 'creer']))
      || jsonb_build_object('assistant_ia', to_jsonb(array['voir', 'creer']))
    when 'COMPTABLE_ENTREPRISE' then v_result
      || jsonb_build_object('depenses',     to_jsonb(array['voir', 'creer', 'valider']))
      || jsonb_build_object('rapports',     to_jsonb(array['voir', 'valider']))
      || jsonb_build_object('assistant_ia', to_jsonb(array['voir', 'creer']))
    else v_result
  end;

  return v_result;
end;
$$;

comment on function public.permissions_defaut(text) is
  'Matrice des permissions par défaut (Module 4, + audit/securite Module 12, + assistant_ia Module 13).';


-- ============================================================================
--  8. NIVEAUX D'AUDIT DES ACTIONS IA
-- ============================================================================

create or replace function public.audit_niveau(p_action text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_action, '')))
    -- CRITIQUE : argent, droits, cycle de vie des comptes.
    when 'CREATION_ENTREPRISE'        then 'CRITIQUE'
    when 'CHANGEMENT_STATUT'          then 'CRITIQUE'
    when 'REACTIVATION'               then 'CRITIQUE'
    when 'CHANGEMENT_ROLE'            then 'CRITIQUE'
    when 'PERMISSIONS_MODIFIEES'      then 'CRITIQUE'
    when 'PERMISSIONS_REINITIALISEES' then 'CRITIQUE'
    when 'PRIX_MODIFIE'               then 'CRITIQUE'
    when 'ANNULATION_VENTE'           then 'CRITIQUE'
    when 'VENTE_SUPPRIMEE'            then 'CRITIQUE'
    when 'UTILISATEUR_SUPPRIME'       then 'CRITIQUE'
    when 'ENTREPRISE_SUPPRIMEE'       then 'CRITIQUE'
    when 'AGENT_IA_CONFIG'            then 'CRITIQUE'
    -- HAUT : opérations financières et mouvements de stock.
    when 'VENTE'                      then 'HAUT'
    when 'PAIEMENT_ENREGISTRE'        then 'HAUT'
    when 'PAIEMENT_DETTE'             then 'HAUT'
    when 'DETTE'                      then 'HAUT'
    when 'DEPENSE'                    then 'HAUT'
    when 'CLOTURE_CAISSE'             then 'HAUT'
    when 'APPROVISIONNEMENT'          then 'HAUT'
    when 'AJUSTEMENT'                 then 'HAUT'
    when 'INVENTAIRE'                 then 'HAUT'
    when 'STOCK_MODIFIE'              then 'HAUT'
    when 'ARTICLE_SUPPRIME'           then 'HAUT'
    when 'CHANGEMENT_ACTIVATION'      then 'HAUT'
    when 'IMPORT_PRODUITS'            then 'HAUT'
    when 'AGENT_IA_ACHAT'             then 'HAUT'
    -- MOYEN : administration courante et sessions.
    when 'CONNEXION'                  then 'MOYEN'
    when 'DECONNEXION'                then 'MOYEN'
    when 'CONNEXION_ECHEC'            then 'MOYEN'
    when 'ARTICLE_CREE'               then 'MOYEN'
    when 'ARTICLE_MODIFIE'            then 'MOYEN'
    when 'CONDITIONNEMENT_AJOUTE'     then 'MOYEN'
    when 'CONDITIONNEMENT_MODIFIE'    then 'MOYEN'
    when 'CONDITIONNEMENT_SUPPRIME'   then 'MOYEN'
    when 'UTILISATEUR_CREE'           then 'MOYEN'
    when 'UTILISATEUR_MODIFIE'        then 'MOYEN'
    when 'ENTREPRISE_MODIFIEE'        then 'MOYEN'
    when 'RELANCE_DETTE'              then 'MOYEN'
    when 'AGENT_IA'                   then 'MOYEN'
    when 'AGENT_IA_ATTRIBUTION'       then 'MOYEN'
    when 'RAPPORT'                    then 'INFO'
    else 'INFO'
  end;
$$;

comment on function public.audit_niveau(text) is
  'Niveau de gravité d''une action du journal d''audit (+ actions IA — Module 13).';


-- ============================================================================
--  9. DROITS D'EXÉCUTION
-- ============================================================================

revoke all on function public.rpc_agent_ia_etat() from public;
grant execute on function public.rpc_agent_ia_etat() to authenticated;

revoke all on function public.rpc_agent_ia_demander_achat(integer, text, text) from public;
grant execute on function public.rpc_agent_ia_demander_achat(integer, text, text) to authenticated;

revoke all on function public.rpc_agent_ia_valider_achat(uuid, boolean, text) from public;
grant execute on function public.rpc_agent_ia_valider_achat(uuid, boolean, text) to authenticated;

revoke all on function public.rpc_agent_ia_marquer_paye(uuid, text) from public;
grant execute on function public.rpc_agent_ia_marquer_paye(uuid, text) to authenticated;

revoke all on function public.rpc_agent_ia_attribuer(uuid, integer) from public;
grant execute on function public.rpc_agent_ia_attribuer(uuid, integer) to authenticated;

revoke all on function public.rpc_agent_ia_config_maj(numeric, integer, numeric, integer, boolean) from public;
grant execute on function public.rpc_agent_ia_config_maj(numeric, integer, numeric, integer, boolean) to authenticated;


-- ============================================================================
--  10. VÉRIFICATIONS
-- ============================================================================

-- 10.a Les nouvelles RPC existent
select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'rpc_agent_ia_etat', 'rpc_agent_ia_demander_achat',
     'rpc_agent_ia_valider_achat', 'rpc_agent_ia_marquer_paye',
     'rpc_agent_ia_attribuer', 'rpc_agent_ia_config_maj'
   )
 order by p.proname;

-- 10.b La page `assistant_ia` est déclarée
select position('assistant_ia' in array_to_string(public.pages_permissions(), ',')) > 0
       as page_assistant_ia_presente;

-- 10.c La matrice du VENDEUR contient l'assistant
select public.permissions_defaut('VENDEUR') -> 'assistant_ia' as vendeur_assistant_ia;

-- 10.d Niveaux d'audit des actions IA
select public.audit_niveau('AGENT_IA')             as agent_ia,
       public.audit_niveau('AGENT_IA_ACHAT')       as agent_ia_achat,
       public.audit_niveau('AGENT_IA_ATTRIBUTION') as agent_ia_attribution,
       public.audit_niveau('AGENT_IA_CONFIG')      as agent_ia_config;
