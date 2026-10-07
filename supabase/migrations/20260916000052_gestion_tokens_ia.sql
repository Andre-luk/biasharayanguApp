-- ============================================================================
--  biashara_yangu — MODULE 13 bis : GESTION RÉELLE DES TOKENS IA
--  Migration 20260916000052_gestion_tokens_ia.sql
-- ============================================================================
--
--  À exécuter APRÈS les migrations 14, 15, 16, 17 (module 13) et 50.
--  IDEMPOTENTE.
--
--  POURQUOI CETTE MIGRATION
--  ------------------------
--  Jusqu'ici l'application facturait l'assistant IA sur les SEULS caractères de
--  la réponse. Or le coût réel payé à DeepSeek dépend essentiellement du
--  contexte ENVOYÉ (préambule + historique), re-facturé à chaque tour d'outil.
--
--  Mesures faites sur `supabase/functions/agent-ia/index.ts` :
--    • 37 outils → schéma JSON ≈ 10 400 caractères ;
--    • prompt système ≈ 2 530 caractères ;
--    → PRÉAMBULE ≈ 12 900 caractères ≈ 3 500 tokens, ENVOYÉ À CHAQUE TOUR ;
--    • jusqu'à 4 tours d'outils par question (`MAX_TOURS_OUTILS`).
--
--  Tarifs DeepSeek (modèle `deepseek-flash`, alias de `deepseek-chat`),
--  pour 1 million de tokens :
--     entrée non cachée : 0,15 $ (creuse) / 0,30 $ (pointe)
--     entrée cachée     : 0,003 $ (creuse) / 0,006 $ (pointe)
--     sortie            : 0,60 $ (creuse) / 1,20 $ (pointe)
--  Heures pleines : 01:00-04:00 et 06:00-10:00 UTC du lundi au vendredi
--  (= 02h-05h et 07h-11h à Kinshasa). TOUT LE RESTE est à moitié prix, week-ends
--  et jours fériés compris : en pratique l'essentiel du trafic est en heure creuse.
--
--  Nous retenons par PRUDENCE les tarifs de POINTE pour le calcul de marge :
--  la marge affichée est donc un MINIMUM, jamais une promesse trop optimiste.
--
--  LA FORMULE RETENUE
--  ------------------
--  Coût réel d'une question : ≈ 6 CDF (pointe, contexte complet, réponse moyenne).
--  Objectif métier : 2 $ de crédit DeepSeek → 30 $ de bénéfice, soit
--      2 $ = 5 600 CDF de coût  ÷  6 CDF  ≈  933 questions
--      recettes cibles = (2 + 30) $ = 32 $ = 89 600 CDF
--      89 600 ÷ 933 ≈ 96 CDF par question  →  coefficient de marge = ×16
--
--  D'où les réglages :
--      caracteres_par_quota = 400     (une réponse moyenne = 1 quota)
--      tarif_par_quota      = 96      (0,24 CDF le caractère)
--      prix_pack_10_quotas  = 860     (remise de 10 % sur le pack de 10)
--  Vérification : 933 × 96 = 89 568 CDF ≈ 31,99 $ → bénéfice ≈ 30 $ ✅
--
--  ⚠️ `tarif_par_quota` n'est plus borné à 100-150 CDF : la contrainte du
--     cahier des charges est ASSOUPLIE (1 à 1000) pour permettre cette formule.
--     Le tarif retenu (96) est donc légèrement sous l'ancienne borne basse.
--
--  CE QUE CETTE MIGRATION AJOUTE
--  -----------------------------
--    1. `agent_ia_config` : paramètres de coût réel, marge cible, change,
--       solde DeepSeek et seuil d'alerte ;
--    2. `public.agent_ia_usage`   — UNE ligne par appel IA : tokens réels
--       (entrée / cachée / sortie), coût réel en CDF, quotas débités, montant
--       facturé, marge. C'est la comptabilité réelle du service ;
--    3. `public.agent_ia_credits` — recharges du solde DeepSeek ;
--    4. `public.agent_ia_distributions` — dons de quotas tracés (Super Admin) ;
--    5. RPC : tableau de bord, journal d'usage, répartition par entreprise,
--       distribution de quotas, recharge du solde, enregistrement d'usage
--       (service_role, appelée par l'Edge Function).
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. CONTRÔLES PRÉALABLES
-- ============================================================================

do $$
declare
  v_table text;
  v_fonction text;
begin
  foreach v_table in array array['agent_ia_config', 'agent_ia_quotas', 'entreprises', 'utilisateurs'] loop
    if not exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = v_table
    ) then
      raise exception
        'Table public.% absente : exécutez d''abord les migrations du module 13.', v_table;
    end if;
  end loop;

  foreach v_fonction in array array['est_plateforme', 'est_super_admin'] loop
    if not exists (
      select 1 from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where p.proname = v_fonction and n.nspname = 'public'
    ) then
      raise exception
        'Fonction public.% absente : exécutez d''abord 20260916000006_module4_permissions.sql.', v_fonction;
    end if;
  end loop;
end $$;


-- ============================================================================
--  1. `agent_ia_config` — PARAMÈTRES DE COÛT, MARGE ET SOLDE
-- ============================================================================

--  1.a — Assouplissement de la borne du tarif par quota.
alter table public.agent_ia_config
  drop constraint if exists agent_ia_config_tarif_par_quota_check;

alter table public.agent_ia_config
  add constraint agent_ia_config_tarif_par_quota_check
  check (tarif_par_quota >= 1 and tarif_par_quota <= 1000);

--  1.b — Nouvelles colonnes (toutes avec valeur par défaut → ajout sans risque).
alter table public.agent_ia_config
  add column if not exists taux_marge numeric(8,3) not null default 16
    check (taux_marge >= 1 and taux_marge <= 1000),
  add column if not exists taux_usd_cdf numeric(10,2) not null default 2800
    check (taux_usd_cdf > 0),
  add column if not exists cout_cdf_par_million_entree numeric(12,2) not null default 840
    check (cout_cdf_par_million_entree >= 0),
  add column if not exists cout_cdf_par_million_cache numeric(12,2) not null default 16.8
    check (cout_cdf_par_million_cache >= 0),
  add column if not exists cout_cdf_par_million_sortie numeric(12,2) not null default 3360
    check (cout_cdf_par_million_sortie >= 0),
  add column if not exists solde_deepseek_usd numeric(12,2) not null default 0
    check (solde_deepseek_usd >= 0),
  add column if not exists alerte_solde_usd numeric(12,2) not null default 1
    check (alerte_solde_usd >= 0);

comment on column public.agent_ia_config.taux_marge is
  'Coefficient de marge appliqué au coût réel DeepSeek (16 = 2 $ de coût → 32 $ de recettes).';
comment on column public.agent_ia_config.cout_cdf_par_million_entree is
  'Coût CDF d''1 million de tokens d''entrée NON cachés (pointe : 0,30 $ × taux).';
comment on column public.agent_ia_config.cout_cdf_par_million_cache is
  'Coût CDF d''1 million de tokens d''entrée CACHÉS (pointe : 0,006 $ × taux).';
comment on column public.agent_ia_config.cout_cdf_par_million_sortie is
  'Coût CDF d''1 million de tokens de SORTIE (pointe : 1,20 $ × taux).';
comment on column public.agent_ia_config.taux_usd_cdf is
  'Change appliqué lors des conversions dollar ↔ franc congolais.';
comment on column public.agent_ia_config.solde_deepseek_usd is
  'Crédit DeepSeek restant (saisi ou incrémenté par les recharges).';
comment on column public.agent_ia_config.alerte_solde_usd is
  'Seuil sous lequel le tableau de bord affiche une alerte de recharge.';

--  1.c — Application de la formule retenue (uniquement sur la ligne existante).
--        Idempotente : relancer la migration réapplique les mêmes valeurs.
update public.agent_ia_config
   set caracteres_par_quota = 400,
       tarif_par_quota      = 96,
       prix_pack_10_quotas  = 860,
       updated_at           = now()
 where id = (select id from public.agent_ia_config order by updated_at limit 1);


-- ============================================================================
--  2. `public.agent_ia_usage` — COMPTABILITÉ RÉELLE DU SERVICE
-- ============================================================================
--  Une ligne par appel facturé. Sert à :
--    • vérifier la marge RÉELLE (coût DeepSeek vs montant facturé) ;
--    • suivre l'usage par entreprise / par utilisateur (distribution) ;
--    • estimer les questions restantes selon le solde DeepSeek.
--
--  Pas de clé étrangère sur `entreprise_id` : on reste tolérant (comme
--  `agent_ia_quotas`, voir migration 17) tout en indexant la colonne.

create table if not exists public.agent_ia_usage (
  id                  bigserial primary key,
  entreprise_id       uuid,
  utilisateur_id      uuid,
  source              text not null default 'agent-ia',
  modele              text,
  tokens_entree       integer not null default 0 check (tokens_entree >= 0),
  tokens_entree_cache integer not null default 0 check (tokens_entree_cache >= 0),
  tokens_sortie       integer not null default 0 check (tokens_sortie >= 0),
  tokens_total        integer not null default 0 check (tokens_total >= 0),
  cout_cdf            numeric(14,4) not null default 0,
  quotas_debites      integer not null default 0 check (quotas_debites >= 0),
  montant_cdf         numeric(14,2) not null default 0,
  marge_cdf           numeric(14,4) not null default 0,
  created_at          timestamptz not null default now()
);

comment on table public.agent_ia_usage is
  'Module 13 bis — Comptabilité réelle de l''assistant IA : tokens, coût DeepSeek, quotas débités et montant facturé, par appel.';
comment on column public.agent_ia_usage.tokens_entree_cache is
  'Tokens d''entrée servis depuis le cache DeepSeek (facturés ~50 fois moins cher).';
comment on column public.agent_ia_usage.source is
  'Origine de l''appel : agent-ia (application) ou admin-agents (API Biashara Group).';

create index if not exists idx_m13bis_usage_date
  on public.agent_ia_usage (created_at desc);
create index if not exists idx_m13bis_usage_entreprise
  on public.agent_ia_usage (entreprise_id, created_at desc);
create index if not exists idx_m13bis_usage_utilisateur
  on public.agent_ia_usage (utilisateur_id, created_at desc);
create index if not exists idx_m13bis_usage_source
  on public.agent_ia_usage (source, created_at desc);


-- ============================================================================
--  3. `public.agent_ia_credits` — RECHARGES DU SOLDE DEEPSEEK
-- ============================================================================

create table if not exists public.agent_ia_credits (
  id           uuid primary key default gen_random_uuid(),
  montant_usd  numeric(10,2) not null check (montant_usd > 0),
  taux_usd_cdf numeric(10,2) not null check (taux_usd_cdf > 0),
  montant_cdf  numeric(14,2) not null default 0,
  note         text,
  par          uuid references public.utilisateurs(id),
  created_at   timestamptz not null default now()
);

comment on table public.agent_ia_credits is
  'Module 13 bis — Historique des recharges du compte DeepSeek (montant, change, auteur).';

create index if not exists idx_m13bis_credits_date
  on public.agent_ia_credits (created_at desc);


-- ============================================================================
--  4. `public.agent_ia_distributions` — DONS DE QUOTAS TRACÉS
-- ============================================================================
--  Permet au Super Admin de créditer une entreprise sans passer par le circuit
--  d'achat (geste commercial, compensation d'incident, campagne marketing).
--  Chaque don est tracé : QUI a donné, COMBIEN, à QUI, POURQUOI.

create table if not exists public.agent_ia_distributions (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null,
  quotas        integer not null check (quotas <> 0),
  montant_cdf   numeric(14,2) not null default 0,
  motif         text,
  par           uuid references public.utilisateurs(id),
  created_at    timestamptz not null default now()
);

comment on table public.agent_ia_distributions is
  'Module 13 bis — Distribution manuelle de quotas par le Super Admin (geste commercial), tracée.';

create index if not exists idx_m13bis_distrib_date
  on public.agent_ia_distributions (created_at desc);
create index if not exists idx_m13bis_distrib_entreprise
  on public.agent_ia_distributions (entreprise_id, created_at desc);


-- ============================================================================
--  5. RPC `rpc_ia_usage_enregistrer` — SERVICE_ROLE (appelée par les Edge Functions)
-- ============================================================================
--  Calcule le coût réel à partir des tokens renvoyés par DeepSeek, puis
--  enregistre la ligne de comptabilité. Repli silencieux : une panne de
--  comptabilité ne doit JAMAIS empêcher une réponse à l'utilisateur.

create or replace function public.rpc_ia_usage_enregistrer(
  p_entreprise        uuid,
  p_utilisateur       uuid,
  p_source            text,
  p_modele            text,
  p_tokens_entree     integer,
  p_tokens_cache      integer,
  p_tokens_sortie     integer,
  p_quotas_debites    integer,
  p_montant_cdf       numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cfg   public.agent_ia_config%rowtype;
  v_entree_miss integer := greatest(coalesce(p_tokens_entree, 0) - coalesce(p_tokens_cache, 0), 0);
  v_cache       integer := greatest(coalesce(p_tokens_cache, 0), 0);
  v_sortie      integer := greatest(coalesce(p_tokens_sortie, 0), 0);
  v_cout        numeric(14,4);
  v_facture     numeric(14,2) := greatest(coalesce(p_montant_cdf, 0), 0);
  v_id          bigint;
begin
  select * into v_cfg from public.agent_ia_config order by updated_at limit 1;

  if v_cfg.id is null then
    return jsonb_build_object('ok', false, 'erreur', 'CONFIG_ABSENTE');
  end if;

  v_cout := round(
      (v_entree_miss / 1000000.0) * coalesce(v_cfg.cout_cdf_par_million_entree, 0)
    + (v_cache       / 1000000.0) * coalesce(v_cfg.cout_cdf_par_million_cache, 0)
    + (v_sortie      / 1000000.0) * coalesce(v_cfg.cout_cdf_par_million_sortie, 0)
  , 4);

  insert into public.agent_ia_usage (
    entreprise_id, utilisateur_id, source, modele,
    tokens_entree, tokens_entree_cache, tokens_sortie, tokens_total,
    cout_cdf, quotas_debites, montant_cdf, marge_cdf
  ) values (
    p_entreprise, p_utilisateur,
    coalesce(nullif(btrim(coalesce(p_source, '')), ''), 'agent-ia'),
    nullif(btrim(coalesce(p_modele, '')), ''),
    v_entree_miss, v_cache, v_sortie,
    v_entree_miss + v_cache + v_sortie,
    v_cout, greatest(coalesce(p_quotas_debites, 0), 0),
    v_facture, round(v_facture - v_cout, 4)
  )
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'usage_id', v_id,
    'cout_cdf', v_cout,
    'montant_cdf', v_facture,
    'marge_cdf', round(v_facture - v_cout, 4)
  );
end;
$$;

comment on function public.rpc_ia_usage_enregistrer(uuid, uuid, text, text, integer, integer, integer, integer, numeric) is
  'Module 13 bis — Enregistre une ligne de comptabilité IA (tokens + coût réel + facturé). service_role uniquement.';

revoke all on function public.rpc_ia_usage_enregistrer(uuid, uuid, text, text, integer, integer, integer, integer, numeric)
  from public, anon, authenticated;
grant execute on function public.rpc_ia_usage_enregistrer(uuid, uuid, text, text, integer, integer, integer, integer, numeric)
  to service_role;


-- ============================================================================
--  6. RPC `rpc_ia_tokens_tableau_bord` — PILOTAGE (plateforme)
-- ============================================================================

create or replace function public.rpc_ia_tokens_tableau_bord(p_jours integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_cfg      public.agent_ia_config%rowtype;
  v_debut    timestamptz;
  v_cout_tot numeric := 0; v_fact_tot numeric := 0; v_q_tot integer := 0;
  v_cout_per numeric := 0; v_fact_per numeric := 0; v_q_per integer := 0;
  v_cout_jour numeric := 0; v_fact_jour numeric := 0; v_q_jour integer := 0;
  v_tok_ent  bigint := 0; v_tok_cache bigint := 0; v_tok_sor bigint := 0;
  v_appels   bigint := 0;
  v_nb_ent   bigint := 0;
  v_cout_moyen numeric := 0;
  v_solde_cdf  numeric := 0;
  v_questions_restantes integer := 0;
  v_coef       numeric := 0;
  v_conso_pct  numeric := 0;
begin
  if not (public.est_plateforme() or public.est_super_admin()) then
    raise exception 'DROIT_REFUSE|Réservé au personnel de la plateforme.';
  end if;

  select * into v_cfg from public.agent_ia_config order by updated_at limit 1;
  if v_cfg.id is null then
    return jsonb_build_object('ok', false, 'erreur', 'CONFIG_ABSENTE');
  end if;

  v_debut := now() - (greatest(coalesce(p_jours, 30), 1) || ' days')::interval;

  -- Totaux depuis toujours.
  select coalesce(sum(cout_cdf), 0), coalesce(sum(montant_cdf), 0),
         coalesce(sum(quotas_debites), 0), count(*),
         coalesce(sum(tokens_entree), 0), coalesce(sum(tokens_entree_cache), 0),
         coalesce(sum(tokens_sortie), 0)
    into v_cout_tot, v_fact_tot, v_q_tot, v_appels,
         v_tok_ent, v_tok_cache, v_tok_sor
    from public.agent_ia_usage;

  -- Sur la période demandée.
  select coalesce(sum(cout_cdf), 0), coalesce(sum(montant_cdf), 0),
         coalesce(sum(quotas_debites), 0), count(*)
    into v_cout_per, v_fact_per, v_q_per, v_nb_ent
    from public.agent_ia_usage
   where created_at >= v_debut;

  -- Aujourd'hui (heure de Kinshasa).
  select coalesce(sum(cout_cdf), 0), coalesce(sum(montant_cdf), 0),
         coalesce(sum(quotas_debites), 0)
    into v_cout_jour, v_fact_jour, v_q_jour
    from public.agent_ia_usage
   where created_at >= date_trunc('day', now() at time zone 'Africa/Kinshasa') at time zone 'Africa/Kinshasa';

  -- Coût moyen d'une question (base : le coût total réellement constaté).
  if v_appels > 0 then
    v_cout_moyen := round(v_cout_tot / v_appels, 4);
  else
    -- Aucun historique : on part de l'estimation de référence (6 CDF).
    v_cout_moyen := 6;
  end if;

  v_solde_cdf := round(coalesce(v_cfg.solde_deepseek_usd, 0) * coalesce(v_cfg.taux_usd_cdf, 2800), 2);

  if v_cout_moyen > 0 then
    v_questions_restantes := floor(v_solde_cdf / v_cout_moyen)::integer;
  end if;

  if v_cout_tot > 0 then
    v_coef := round(v_fact_tot / v_cout_tot, 2);
  end if;

  if coalesce(v_cfg.solde_deepseek_usd, 0) + (v_cout_tot / nullif(v_cfg.taux_usd_cdf, 0)) > 0 then
    v_conso_pct := round(
      (v_cout_tot / nullif(v_cfg.taux_usd_cdf, 0))
      / (coalesce(v_cfg.solde_deepseek_usd, 0) + (v_cout_tot / nullif(v_cfg.taux_usd_cdf, 0))) * 100, 1);
  end if;

  return jsonb_build_object(
    'ok', true,
    'jours', greatest(coalesce(p_jours, 30), 1),

    -- Réglages en vigueur
    'tarif_par_quota',            v_cfg.tarif_par_quota,
    'caracteres_par_quota',       v_cfg.caracteres_par_quota,
    'prix_pack_10_quotas',        v_cfg.prix_pack_10_quotas,
    'quotas_offerts_inscription', v_cfg.quotas_offerts_inscription,
    'taux_marge',                 v_cfg.taux_marge,
    'taux_usd_cdf',               v_cfg.taux_usd_cdf,
    'actif',                      v_cfg.actif,

    -- Comptabilité (depuis toujours)
    'appels',            v_appels,
    'tokens_entree',     v_tok_ent,
    'tokens_cache',      v_tok_cache,
    'tokens_sortie',     v_tok_sor,
    'tokens_total',      v_tok_ent + v_tok_cache + v_tok_sor,
    'cout_cdf',          round(v_cout_tot, 2),
    'facture_cdf',       round(v_fact_tot, 2),
    'marge_cdf',         round(v_fact_tot - v_cout_tot, 2),
    'coefficient',       v_coef,
    'quotas_debites',    v_q_tot,
    'cout_moyen_question_cdf', v_cout_moyen,

    -- Période
    'periode_appels',      v_nb_ent,
    'periode_cout_cdf',    round(v_cout_per, 2),
    'periode_facture_cdf', round(v_fact_per, 2),
    'periode_marge_cdf',   round(v_fact_per - v_cout_per, 2),
    'periode_quotas',      v_q_per,

    -- Aujourd'hui
    'jour_cout_cdf',    round(v_cout_jour, 2),
    'jour_facture_cdf', round(v_fact_jour, 2),
    'jour_marge_cdf',   round(v_fact_jour - v_cout_jour, 2),
    'jour_quotas',      v_q_jour,

    -- Solde DeepSeek
    'solde_deepseek_usd', v_cfg.solde_deepseek_usd,
    'solde_cdf',          v_solde_cdf,
    'questions_restantes', v_questions_restantes,
    'consommation_pct',   greatest(least(coalesce(v_conso_pct, 0), 100), 0),
    'alerte_solde_usd',   v_cfg.alerte_solde_usd,
    'alerte',             coalesce(v_cfg.solde_deepseek_usd, 0) <= coalesce(v_cfg.alerte_solde_usd, 1)
  );
end;
$$;

comment on function public.rpc_ia_tokens_tableau_bord(integer) is
  'Module 13 bis — Tableau de bord des tokens IA : coût réel, marge, tokens, solde DeepSeek et questions restantes.';

revoke all on function public.rpc_ia_tokens_tableau_bord(integer) from public, anon;
grant execute on function public.rpc_ia_tokens_tableau_bord(integer) to authenticated;


-- ============================================================================
--  7. RPC `rpc_ia_usage_lister` — JOURNAL DÉTAILLÉ DES APPELS
-- ============================================================================

create or replace function public.rpc_ia_usage_lister(
  p_limite     integer default 100,
  p_decalage   integer default 0,
  p_entreprise uuid default null,
  p_source     text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limite   integer := least(greatest(coalesce(p_limite, 100), 1), 500);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_total    integer := 0;
  v_liste    jsonb := '[]'::jsonb;
  v_source   text := nullif(btrim(coalesce(p_source, '')), '');
begin
  if not (public.est_plateforme() or public.est_super_admin()) then
    raise exception 'DROIT_REFUSE|Réservé au personnel de la plateforme.';
  end if;

  select count(*) into v_total
    from public.agent_ia_usage u
   where (p_entreprise is null or u.entreprise_id = p_entreprise)
     and (v_source is null or u.source = v_source);

  select coalesce(jsonb_agg(s.t order by s.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select jsonb_build_object(
               'id', u.id,
               'created_at', u.created_at,
               'source', u.source,
               'modele', u.modele,
               'entreprise_id', u.entreprise_id,
               'entreprise', (select e.nom from public.entreprises e where e.id = u.entreprise_id),
               'utilisateur_id', u.utilisateur_id,
               'utilisateur', (select coalesce(nullif(btrim(coalesce(x.nom, '')), ''), x.email)
                                 from public.utilisateurs x where x.id = u.utilisateur_id),
               'tokens_entree', u.tokens_entree,
               'tokens_entree_cache', u.tokens_entree_cache,
               'tokens_sortie', u.tokens_sortie,
               'tokens_total', u.tokens_total,
               'cout_cdf', u.cout_cdf,
               'quotas_debites', u.quotas_debites,
               'montant_cdf', u.montant_cdf,
               'marge_cdf', u.marge_cdf
             ) as t,
             u.created_at
        from public.agent_ia_usage u
       where (p_entreprise is null or u.entreprise_id = p_entreprise)
         and (v_source is null or u.source = v_source)
       order by u.created_at desc
       limit v_limite offset v_decalage
    ) s;

  return jsonb_build_object('ok', true, 'total', v_total, 'usage', v_liste);
end;
$$;

comment on function public.rpc_ia_usage_lister(integer, integer, uuid, text) is
  'Module 13 bis — Journal des appels IA (tokens, coût, facturé, marge) pour le pilotage plateforme.';

revoke all on function public.rpc_ia_usage_lister(integer, integer, uuid, text) from public, anon;
grant execute on function public.rpc_ia_usage_lister(integer, integer, uuid, text) to authenticated;


-- ============================================================================
--  8. RPC `rpc_ia_usage_par_entreprise` — RÉPARTITION (qui consomme quoi)
-- ============================================================================

create or replace function public.rpc_ia_usage_par_entreprise(p_jours integer default 30)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_debut timestamptz := now() - (greatest(coalesce(p_jours, 30), 1) || ' days')::interval;
  v_liste jsonb := '[]'::jsonb;
  v_cfg   public.agent_ia_config%rowtype;
  v_par_quota numeric := 100;
begin
  if not (public.est_plateforme() or public.est_super_admin()) then
    raise exception 'DROIT_REFUSE|Réservé au personnel de la plateforme.';
  end if;

  select * into v_cfg from public.agent_ia_config order by updated_at limit 1;
  v_par_quota := greatest(coalesce(v_cfg.caracteres_par_quota, 400), 1);

  select coalesce(jsonb_agg(s.t order by s.cout_cdf desc), '[]'::jsonb)
    into v_liste
    from (
      select jsonb_build_object(
               'entreprise_id', u.entreprise_id,
               'entreprise', coalesce(
                 (select e.nom from public.entreprises e where e.id = u.entreprise_id),
                 'Sans entreprise'),
               'appels', count(*),
               'tokens_total', coalesce(sum(u.tokens_total), 0),
               'cout_cdf', round(coalesce(sum(u.cout_cdf), 0), 2),
               'facture_cdf', round(coalesce(sum(u.montant_cdf), 0), 2),
               'marge_cdf', round(coalesce(sum(u.montant_cdf), 0) - coalesce(sum(u.cout_cdf), 0), 2),
               'quotas_debites', coalesce(sum(u.quotas_debites), 0),
               'caracteres', coalesce(sum(u.quotas_debites), 0) * v_par_quota,
               'derniere_activite', max(u.created_at)
             ) as t,
             coalesce(sum(u.cout_cdf), 0) as cout_cdf
        from public.agent_ia_usage u
       where u.created_at >= v_debut
       group by u.entreprise_id
    ) s;

  return jsonb_build_object(
    'ok', true,
    'jours', greatest(coalesce(p_jours, 30), 1),
    'caracteres_par_quota', v_par_quota,
    'repartition', v_liste
  );
end;
$$;

comment on function public.rpc_ia_usage_par_entreprise(integer) is
  'Module 13 bis — Répartition de la consommation IA par entreprise (coût, facturé, marge, quotas).';

revoke all on function public.rpc_ia_usage_par_entreprise(integer) from public, anon;
grant execute on function public.rpc_ia_usage_par_entreprise(integer) to authenticated;


-- ============================================================================
--  9. RPC `rpc_ia_distribuer` — DON DE QUOTAS PAR LE SUPER ADMIN
-- ============================================================================

create or replace function public.rpc_ia_distribuer(
  p_entreprise uuid,
  p_quotas     integer,
  p_motif      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_cfg    public.agent_ia_config%rowtype;
  v_motif  text := nullif(btrim(coalesce(p_motif, '')), '');
  v_pool   public.agent_ia_quotas%rowtype;
  v_montant numeric := 0;
  v_solde  integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour distribuer des quotas.';
  end if;

  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin distribue des quotas.';
  end if;

  if p_entreprise is null then
    raise exception 'ENTREPRISE_REQUISE|Choisissez l''entreprise bénéficiaire.';
  end if;

  if p_quotas is null or p_quotas < 1 or p_quotas > 100000 then
    raise exception 'QUOTAS_INVALIDE|Indiquez un nombre de quotas entre 1 et 100000.';
  end if;

  if v_motif is null or length(v_motif) < 3 then
    raise exception 'MOTIF_REQUIS|Indiquez le motif du don (3 caractères minimum).';
  end if;

  select * into v_cfg from public.agent_ia_config order by updated_at limit 1;
  v_montant := round(p_quotas * coalesce(v_cfg.tarif_par_quota, 96), 2);

  -- Pool de l'entreprise (créé si absent).
  select * into v_pool
    from public.agent_ia_quotas
   where entreprise_id = p_entreprise and utilisateur_id is null;

  if v_pool.id is null then
    insert into public.agent_ia_quotas (utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total)
    values (null, p_entreprise, p_quotas, 0)
    returning * into v_pool;
  else
    update public.agent_ia_quotas
       set quotas_disponibles = coalesce(quotas_disponibles, 0) + p_quotas
     where id = v_pool.id
    returning * into v_pool;
  end if;

  v_solde := coalesce(v_pool.quotas_disponibles, 0);

  insert into public.agent_ia_distributions (entreprise_id, quotas, montant_cdf, motif, par)
  values (p_entreprise, p_quotas, v_montant, v_motif, v_user);

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    p_entreprise, 'AGENT_IA_QUOTAS_DISTRIBUES', v_user,
    jsonb_build_object(
      'quotas', p_quotas,
      'montant_cdf', v_montant,
      'motif', v_motif,
      'solde_pool', v_solde
    )
  );

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', p_entreprise,
    'quotas', p_quotas,
    'montant_cdf', v_montant,
    'solde_pool', v_solde
  );
end;
$$;

comment on function public.rpc_ia_distribuer(uuid, integer, text) is
  'Module 13 bis — Super Admin : crédite le pool de quotas d''une entreprise (don tracé, journalisé).';

revoke all on function public.rpc_ia_distribuer(uuid, integer, text) from public, anon;
grant execute on function public.rpc_ia_distribuer(uuid, integer, text) to authenticated;


-- ============================================================================
-- 10. RPC `rpc_ia_credit_recharger` — RECHARGE DU SOLDE DEEPSEEK
-- ============================================================================

create or replace function public.rpc_ia_credit_recharger(
  p_montant_usd numeric,
  p_taux_usd_cdf numeric default null,
  p_note        text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_cfg   public.agent_ia_config%rowtype;
  v_taux  numeric;
  v_solde numeric;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour enregistrer une recharge.';
  end if;

  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin gère le crédit DeepSeek.';
  end if;

  if p_montant_usd is null or p_montant_usd <= 0 or p_montant_usd > 100000 then
    raise exception 'MONTANT_INVALIDE|Indiquez un montant en dollars entre 0,01 et 100000.';
  end if;

  select * into v_cfg from public.agent_ia_config order by updated_at limit 1;
  v_taux := coalesce(nullif(p_taux_usd_cdf, 0), v_cfg.taux_usd_cdf, 2800);

  insert into public.agent_ia_credits (montant_usd, taux_usd_cdf, montant_cdf, note, par)
  values (p_montant_usd, v_taux, round(p_montant_usd * v_taux, 2),
          nullif(btrim(coalesce(p_note, '')), ''), v_user);

  update public.agent_ia_config
     set solde_deepseek_usd = coalesce(solde_deepseek_usd, 0) + p_montant_usd,
         taux_usd_cdf       = v_taux,
         updated_at         = now(),
         updated_by         = v_user
   where id = v_cfg.id
  returning solde_deepseek_usd into v_solde;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'AGENT_IA_CREDIT_RECHARGE', v_user,
    jsonb_build_object(
      'montant_usd', p_montant_usd,
      'taux_usd_cdf', v_taux,
      'solde_usd', v_solde,
      'note', nullif(btrim(coalesce(p_note, '')), '')
    )
  );

  return jsonb_build_object(
    'ok', true,
    'montant_usd', p_montant_usd,
    'taux_usd_cdf', v_taux,
    'solde_usd', v_solde
  );
end;
$$;

comment on function public.rpc_ia_credit_recharger(numeric, numeric, text) is
  'Module 13 bis — Super Admin : enregistre une recharge du compte DeepSeek et incrémente le solde suivi.';

revoke all on function public.rpc_ia_credit_recharger(numeric, numeric, text) from public, anon;
grant execute on function public.rpc_ia_credit_recharger(numeric, numeric, text) to authenticated;


-- ============================================================================
-- 11. `rpc_agent_ia_config_maj` — ÉTENDUE AUX PARAMÈTRES DE COÛT ET DE MARGE
-- ============================================================================
--  ⚠️ On SUPPRIME d'abord l'ancienne signature : ajouter des paramètres à une
--     fonction crée une SURCHARGE, et un appel à 5 arguments deviendrait
--     ambigu (« function is not unique »).

drop function if exists public.rpc_agent_ia_config_maj(numeric, integer, numeric, integer, boolean);

create or replace function public.rpc_agent_ia_config_maj(
  p_tarif_par_quota            numeric default null,
  p_caracteres_par_quota       integer default null,
  p_prix_pack_10_quotas        numeric default null,
  p_quotas_offerts_inscription integer default null,
  p_actif                      boolean default null,
  p_taux_marge                 numeric default null,
  p_taux_usd_cdf               numeric default null,
  p_cout_million_entree        numeric default null,
  p_cout_million_cache         numeric default null,
  p_cout_million_sortie        numeric default null,
  p_alerte_solde_usd           numeric default null
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
     and (p_tarif_par_quota < 1 or p_tarif_par_quota > 1000) then
    raise exception 'TARIF_INVALIDE|Le tarif doit être compris entre 1 et 1000 CDF par quota.';
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

  if p_taux_marge is not null and (p_taux_marge < 1 or p_taux_marge > 1000) then
    raise exception 'MARGE_INVALIDE|Le taux de marge doit être compris entre 1 et 1000.';
  end if;

  if p_taux_usd_cdf is not null and p_taux_usd_cdf <= 0 then
    raise exception 'TAUX_INVALIDE|Le taux de change doit être supérieur à 0.';
  end if;

  if p_alerte_solde_usd is not null and p_alerte_solde_usd < 0 then
    raise exception 'ALERTE_INVALIDE|Le seuil d''alerte ne peut pas être négatif.';
  end if;

  update public.agent_ia_config
     set tarif_par_quota            = coalesce(p_tarif_par_quota, tarif_par_quota),
         caracteres_par_quota       = coalesce(p_caracteres_par_quota, caracteres_par_quota),
         prix_pack_10_quotas        = coalesce(p_prix_pack_10_quotas, prix_pack_10_quotas),
         quotas_offerts_inscription = coalesce(p_quotas_offerts_inscription, quotas_offerts_inscription),
         actif                      = coalesce(p_actif, actif),
         taux_marge                 = coalesce(p_taux_marge, taux_marge),
         taux_usd_cdf               = coalesce(p_taux_usd_cdf, taux_usd_cdf),
         cout_cdf_par_million_entree = coalesce(p_cout_million_entree, cout_cdf_par_million_entree),
         cout_cdf_par_million_cache  = coalesce(p_cout_million_cache, cout_cdf_par_million_cache),
         cout_cdf_par_million_sortie = coalesce(p_cout_million_sortie, cout_cdf_par_million_sortie),
         alerte_solde_usd            = coalesce(p_alerte_solde_usd, alerte_solde_usd),
         updated_at                 = now(),
         updated_by                 = v_user
   where id = (select id from public.agent_ia_config order by updated_at limit 1)
  returning * into v_config;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'AGENT_IA_CONFIG', v_user,
    jsonb_build_object(
      'tarif_par_quota',            v_config.tarif_par_quota,
      'caracteres_par_quota',       v_config.caracteres_par_quota,
      'prix_pack_10_quotas',        v_config.prix_pack_10_quotas,
      'quotas_offerts_inscription', v_config.quotas_offerts_inscription,
      'actif',                      v_config.actif,
      'taux_marge',                 v_config.taux_marge,
      'taux_usd_cdf',               v_config.taux_usd_cdf,
      'cout_cdf_par_million_entree', v_config.cout_cdf_par_million_entree,
      'cout_cdf_par_million_cache',  v_config.cout_cdf_par_million_cache,
      'cout_cdf_par_million_sortie', v_config.cout_cdf_par_million_sortie,
      'alerte_solde_usd',            v_config.alerte_solde_usd
    )
  );

  return jsonb_build_object(
    'ok', true,
    'tarif_par_quota',            v_config.tarif_par_quota,
    'caracteres_par_quota',       v_config.caracteres_par_quota,
    'prix_pack_10_quotas',        v_config.prix_pack_10_quotas,
    'quotas_offerts_inscription', v_config.quotas_offerts_inscription,
    'actif',                      v_config.actif,
    'taux_marge',                 v_config.taux_marge,
    'taux_usd_cdf',               v_config.taux_usd_cdf,
    'cout_cdf_par_million_entree', v_config.cout_cdf_par_million_entree,
    'cout_cdf_par_million_cache',  v_config.cout_cdf_par_million_cache,
    'cout_cdf_par_million_sortie', v_config.cout_cdf_par_million_sortie,
    'alerte_solde_usd',            v_config.alerte_solde_usd
  );
end;
$$;

comment on function public.rpc_agent_ia_config_maj(numeric, integer, numeric, integer, boolean, numeric, numeric, numeric, numeric, numeric, numeric) is
  'Module 13 bis — Super Admin : tarifs, marge, coûts réels DeepSeek, change et seuil d''alerte (journalisé AGENT_IA_CONFIG).';

revoke all on function public.rpc_agent_ia_config_maj(numeric, integer, numeric, integer, boolean, numeric, numeric, numeric, numeric, numeric, numeric)
  from public, anon;
grant execute on function public.rpc_agent_ia_config_maj(numeric, integer, numeric, integer, boolean, numeric, numeric, numeric, numeric, numeric, numeric)
  to authenticated;


-- ============================================================================
-- 12. RLS — LECTURE SEULE, FILTRÉE
-- ============================================================================

alter table public.agent_ia_usage         enable row level security;
alter table public.agent_ia_credits       enable row level security;
alter table public.agent_ia_distributions enable row level security;

-- Usage : la plateforme voit tout ; chacun voit SES propres appels.
drop policy if exists m13bis_usage_lecture on public.agent_ia_usage;
create policy m13bis_usage_lecture on public.agent_ia_usage
  for select using (
    public.est_plateforme()
    or utilisateur_id = auth.uid()
  );

-- Crédits DeepSeek : plateforme uniquement (données financières de l'éditeur).
drop policy if exists m13bis_credits_lecture on public.agent_ia_credits;
create policy m13bis_credits_lecture on public.agent_ia_credits
  for select using (public.est_plateforme());

-- Distributions : la plateforme voit tout ; une entreprise voit les dons reçus.
drop policy if exists m13bis_distrib_lecture on public.agent_ia_distributions;
create policy m13bis_distrib_lecture on public.agent_ia_distributions
  for select using (
    public.est_plateforme()
    or entreprise_id in (
      select u.entreprise_id from public.utilisateurs u where u.id = auth.uid()
    )
  );

-- ⚠️ AUCUNE politique d'écriture : toutes les écritures passent par les RPC
--    `security definer` ci-dessus ou par l'Edge Function (service_role).


-- ============================================================================
-- 13. VÉRIFICATION — RUN SÉPARÉ
-- ============================================================================
--  -- 1. La formule est bien appliquée :
--  -- select tarif_par_quota, caracteres_par_quota, prix_pack_10_quotas,
--  --        taux_marge, solde_deepseek_usd
--  --   from public.agent_ia_config;
--  --    Attendu : 96 | 400 | 860 | 16 | 0
--  --
--  -- 2. Les nouvelles contraintes :
--  -- select conname, pg_get_constraintdef(oid) from pg_constraint
--  --  where conrelid = 'public.agent_ia_config'::regclass
--  --    and conname like '%tarif%';
--  --    Attendu : CHECK (tarif_par_quota >= 1 AND tarif_par_quota <= 1000)
--  --
--  -- 3. Simulation de la formule (à la main) :
--  --    réponse de   400 caractères → ceil(400/400)  = 1 quota →   96 CDF
--  --    réponse de 1 500 caractères → ceil(1500/400) = 4 quotas →  384 CDF
--  --    Calcul de l'objectif :
--  --      2 $ = 5 600 CDF de coût ÷ 6 CDF par question ≈ 933 questions
--  --      933 × 96 CDF = 89 568 CDF = 31,99 $
--  --      → bénéfice ≈ 30 $ pour 2 $ dépensés (coefficient ×16).
--  --
--  -- 4. Renseigner une recharge de test puis consulter le tableau de bord :
--  -- select public.rpc_ia_credit_recharger(2, 2800, 'Test');
--  -- select public.rpc_ia_tokens_tableau_bord(30);
-- ============================================================================
--  FIN — module 13 bis.
-- ============================================================================
