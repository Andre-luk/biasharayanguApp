-- ============================================================================
--  biashara_yangu — MODULE 13 : ASSISTANT IA (DEEPSEEK) — ÉTAPE 1
--
--  Cette migration pose UNIQUEMENT le SOCLE DE DONNÉES du module :
--     1. `public.agent_ia_config`         — tarifs & réglages (singleton) ;
--     2. `public.agent_ia_quotas`         — soldes : POOL par entreprise +
--        attributions par utilisateur (le patron distribue) ;
--     3. `public.agent_ia_achats`         — demandes de packs → validation du
--        Super Admin → suivi du PAIEMENT (payé / impayé, montant TOUJOURS
--        affiché même impayé — exigence métier) ;
--     4. `public.agent_ia_conversations`  — tout message échangé avec l'IA ;
--     5. `public.agent_ia_actions`        — tout outil exécuté par l'agent ;
--     6. RLS : chacun voit SES données ; le propriétaire voit son entreprise ;
--        le personnel plateforme voit tout. AUCUNE écriture directe : les
--        écritures passeront par l'Edge Function `agent-ia` (service_role) et
--        les RPC `security definer` (Étape 2).
--
--  MODÈLE ÉCONOMIQUE (décisions utilisateur) :
--     • 1 quota = `caracteres_par_quota` caractères de réponse utile (20) ;
--     • tarif 100 à 150 CDF par quota (150 par défaut) ;
--     • packs : 10 = 1 000 CDF, 20 = 2 000, 50 = 5 000, 100 = 10 000
--       (proportionnels au prix du pack de 10, configurable) ;
--     • 5 quotas offerts à l'inscription (`quotas_offerts_inscription`) ;
--     • le solde est PARTAGÉ par entreprise (pool) : le patron ATTRIBUE des
--       quotas à chaque membre, qui ne peut PAS dépasser son allocation
--       (protection anti-abus) ;
--     • l'achat suit le circuit : DEMANDE → Super Admin reçoit → approuve →
--       quotas créditent le pool ; l'entreprise paie depuis sa caisse et le
--       statut payé/impayé reste visible sur CHAQUE achat.
--
--  ⚠️ ÉTAPE 1 UNIQUEMENT : aucune RPC, aucune Edge Function ici — ils
--     arrivent à l'Étape 2 après validation.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉ-REQUIS
--    Modules 4 (peut / est_plateforme / est_super_admin / mon_proprietaire)
--    et 1 (entreprises, utilisateurs) exécutés.
--
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable : les objets indispensables.
do $$
declare
  v_table text;
  v_fonction text;
begin
  foreach v_table in array array['utilisateurs', 'entreprises'] loop
    if not exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = v_table
    ) then
      raise exception
        'Table public.% absente : exécutez d''abord les migrations des modules précédents.', v_table;
    end if;
  end loop;

  foreach v_fonction in array array[
    'peut', 'est_plateforme', 'est_super_admin', 'mon_proprietaire'
  ] loop
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
--  1. `public.agent_ia_config` — TARIFS & RÉGLAGES (SINGLETON)
-- ============================================================================
--  Une seule ligne (index unique sur constante). Modifiable par le Super
--  Admin (écran « Configuration IA » à l'Étape 2 via RPC dédiée).

create table if not exists public.agent_ia_config (
  id                        uuid primary key default gen_random_uuid(),
  tarif_par_quota           numeric not null default 150
    check (tarif_par_quota >= 100 and tarif_par_quota <= 150),
  caracteres_par_quota      integer not null default 20
    check (caracteres_par_quota between 1 and 500),
  prix_pack_10_quotas       numeric not null default 1000
    check (prix_pack_10_quotas >= 0),
  quotas_offerts_inscription integer not null default 5
    check (quotas_offerts_inscription >= 0 and quotas_offerts_inscription <= 1000),
  actif                     boolean not null default true,
  updated_at                timestamptz not null default now(),
  updated_by                uuid references public.utilisateurs(id)
);

comment on table public.agent_ia_config is
  'Module 13 — Réglages de l''assistant IA : tarif/quota (100-150 CDF), taille d''un quota, prix du pack de 10, quotas offerts, activation.';
comment on column public.agent_ia_config.tarif_par_quota is
  'CDF facturés par quota consommé (borné 100-150 — exigence du cahier des charges).';
comment on column public.agent_ia_config.caracteres_par_quota is
  'Nombre de caractères de réponse utile comptant pour 1 quota (défaut 20, arrondi supérieur).';

-- Une seule ligne de configuration.
create unique index if not exists idx_m13_config_singleton
  on public.agent_ia_config ((true));

-- Configuration par défaut (Partie 8 du cahier des charges).
insert into public.agent_ia_config (
  tarif_par_quota, caracteres_par_quota, prix_pack_10_quotas,
  quotas_offerts_inscription, actif
)
select 150, 20, 1000, 5, true
where not exists (select 1 from public.agent_ia_config);


-- ============================================================================
--  2. `public.agent_ia_quotas` — SOLDE PARTAGÉ + ATTRIBUTIONS DU PATRON
-- ============================================================================
--  DEUX types de lignes :
--    • LIGNE POOL (utilisateur_id IS NULL) : quotas ACHETÉS pour l'entreprise
--      (un index unique partiel garantit UNE seule ligne pool par entreprise) ;
--    • LIGNES UTILISATEUR : allocations ATTRIBUÉES par le patron à chaque
--      membre (`attribue_par`, `attribue_le`). Un membre ne consomme QUE son
--      allocation — c'est ce qui empêche les abus sur le pool.
--
--  Le débit quotidien (Étape 2) :
--    1. consommation → ligne utilisateur (quotas_disponibles - n) ;
--    2. le pool n'est entamé que par la VALIDATION d'une attribution/achat.

create table if not exists public.agent_ia_quotas (
  id                     uuid primary key default gen_random_uuid(),
  utilisateur_id         uuid references public.utilisateurs(id) on delete cascade,
  entreprise_id          uuid references public.entreprises(id) on delete cascade,
  quotas_disponibles     integer not null default 0
    check (quotas_disponibles >= 0),
  quotas_utilises_total  integer not null default 0
    check (quotas_utilises_total >= 0),
  quotas_achetes_total   integer not null default 0
    check (quotas_achetes_total >= 0),
  attribue_par           uuid references public.utilisateurs(id),
  attribue_le            timestamptz,
  updated_at             timestamptz not null default now()
);

comment on table public.agent_ia_quotas is
  'Module 13 — Soldes de quotas IA : une ligne POOL par entreprise (utilisateur_id NULL) + une ligne par utilisateur (allocation attribuée par le patron).';
comment on column public.agent_ia_quotas.attribue_par is
  'Auteur de la dernière attribution (le patron) — traçabilité des distributions.';

-- Un seul solde par utilisateur (les NULL des lignes pool ne comptent pas).
create unique index if not exists idx_m13_quotas_unique_utilisateur
  on public.agent_ia_quotas (utilisateur_id);

-- Un seul POOL par entreprise.
create unique index if not exists idx_m13_quotas_pool_entreprise
  on public.agent_ia_quotas (entreprise_id)
  where utilisateur_id is null;

create index if not exists idx_m13_quotas_entreprise
  on public.agent_ia_quotas (entreprise_id);


-- ============================================================================
--  3. `public.agent_ia_achats` — DEMANDES, VALIDATION, PAIEMENT
-- ============================================================================
--  Circuit métier (décisions utilisateur) :
--    1. la boutique DEMANDE un pack → ligne `statut = 'demande'` ;
--    2. le Super Admin REÇOIT la demande → `approuve` ou `refuse` ;
--    3. à l'approbation, les quotas créditent le POOL de l'entreprise ;
--    4. `statut_paiement` suit l'argent : 'impaye' ou 'paye' — le montant
--       (`montant_cdf`) est TOUJOURS affiché, y compris pour un impayé ;
--    5. l'entreprise règle depuis sa caisse (écriture de caisse à l'Étape 2).

create table if not exists public.agent_ia_achats (
  id               uuid primary key default gen_random_uuid(),
  utilisateur_id   uuid not null references public.utilisateurs(id), -- demandeur
  entreprise_id    uuid references public.entreprises(id) on delete set null,
  nombre_quotas    integer not null check (nombre_quotas > 0 and nombre_quotas <= 100000),
  montant_cdf      numeric not null check (montant_cdf >= 0),
  mode_paiement    text not null default 'especes',
  statut           text not null default 'demande'
    check (statut in ('demande', 'approuve', 'refuse')),
  statut_paiement  text not null default 'impaye'
    check (statut_paiement in ('impaye', 'paye')),
  enregistre_par   uuid references public.utilisateurs(id),
  valide_par       uuid references public.utilisateurs(id),
  valide_le        timestamptz,
  note             text,
  created_at       timestamptz not null default now()
);

comment on table public.agent_ia_achats is
  'Module 13 — Achats de packs de quotas IA : demande → validation Super Admin → crédit du pool ; le montant et le statut payé/impayé restent visibles.';
comment on column public.agent_ia_achats.statut_paiement is
  'impaye = montant dû affiché en entier (exigence métier) ; paye = réglé (la caisse de l''entreprise est mouvementée à l''Étape 2).';

create index if not exists idx_m13_achats_entreprise_date
  on public.agent_ia_achats (entreprise_id, created_at desc);
create index if not exists idx_m13_achats_demandeur_date
  on public.agent_ia_achats (utilisateur_id, created_at desc);
create index if not exists idx_m13_achats_statuts
  on public.agent_ia_achats (statut, statut_paiement);


-- ============================================================================
--  4. `public.agent_ia_conversations` — TOUT MESSAGE ÉCHANGÉ
-- ============================================================================
--  Historique complet (stockage illimité — décision utilisateur) : messages
--  utilisateur, réponses assistant, appels d'outils. Sert de contexte à
--  l'Edge Function ET de preuve (qui a demandé quoi).

create table if not exists public.agent_ia_conversations (
  id               uuid primary key default gen_random_uuid(),
  utilisateur_id   uuid not null references public.utilisateurs(id) on delete cascade,
  entreprise_id    uuid references public.entreprises(id) on delete set null,
  role             text not null check (role in ('user', 'assistant', 'system', 'tool')),
  contenu          text,
  tool_calls       jsonb,
  tool_call_id     text,
  action_executee  text,
  quotas_consommes integer not null default 0 check (quotas_consommes >= 0),
  created_at       timestamptz not null default now()
);

comment on table public.agent_ia_conversations is
  'Module 13 — Historique des conversations avec l''assistant IA (contexte + traçabilité ; quotas consommés par message).';

create index if not exists idx_m13_conversations_utilisateur
  on public.agent_ia_conversations (utilisateur_id, created_at desc);
create index if not exists idx_m13_conversations_entreprise
  on public.agent_ia_conversations (entreprise_id, created_at desc);


-- ============================================================================
--  5. `public.agent_ia_actions` — TOUT OUTIL EXÉCUTÉ PAR L'AGENT
-- ============================================================================
--  Chaque outil (vente, stock, rapport…) appelé par l'agent laisse une ligne :
--  paramètres, résultat, succès/échec, quotas consommés. C'est la piste
--  d'audit de l'IA, en complément de `public.journal_audit`.

create table if not exists public.agent_ia_actions (
  id               uuid primary key default gen_random_uuid(),
  utilisateur_id   uuid not null references public.utilisateurs(id) on delete cascade,
  entreprise_id    uuid references public.entreprises(id) on delete set null,
  outil            text not null,
  parametres       jsonb,
  resultat         jsonb,
  succes           boolean not null default true,
  quotas_consommes integer not null default 0 check (quotas_consommes >= 0),
  created_at       timestamptz not null default now()
);

comment on table public.agent_ia_actions is
  'Module 13 — Journal des outils exécutés par l''agent IA (paramètres, résultat, succès, quotas).';

create index if not exists idx_m13_actions_utilisateur
  on public.agent_ia_actions (utilisateur_id, created_at desc);
create index if not exists idx_m13_actions_outil
  on public.agent_ia_actions (outil, created_at desc);


-- ============================================================================
--  6. RLS — CHACUN VOIT SES DONNÉES ; LA PLATEFORME SUPERVISE
-- ============================================================================
--  • CONFIG : lisible par tout compte connecté (afficher les tarifs) ;
--  • QUOTAS : sa ligne + le pool de son entreprise + tout (propriétaire de
--    l'entreprise / personnel plateforme) ;
--  • ACHATS : ses demandes + celles de son entreprise + tout (plateforme) ;
--  • CONVERSATIONS / ACTIONS : les siennes + celles de son entreprise
--    (le patron supervise) + tout (plateforme).
--
--  ⚠️ AUCUNE écriture directe : tout passe par l'Edge Function (service_role)
--  ou les RPC `security definer` de l'Étape 2.

alter table public.agent_ia_config        enable row level security;
alter table public.agent_ia_quotas        enable row level security;
alter table public.agent_ia_achats        enable row level security;
alter table public.agent_ia_conversations enable row level security;
alter table public.agent_ia_actions       enable row level security;

-- Repartir proprement (idempotence).
do $$
declare
  v_table text;
  r record;
begin
  foreach v_table in array array[
    'agent_ia_config', 'agent_ia_quotas', 'agent_ia_achats',
    'agent_ia_conversations', 'agent_ia_actions'
  ] loop
    for r in
      select policyname
        from pg_policies
       where schemaname = 'public' and tablename = v_table
    loop
      execute format('drop policy if exists %I on public.%I', r.policyname, v_table);
    end loop;
  end loop;
end $$;

-- 6.a Config : lecture pour tous les comptes connectés.
create policy m13_config_lecture on public.agent_ia_config
  for select to authenticated
  using (true);

-- 6.b Quotas : sa ligne, le pool de son entreprise, la supervision.
create policy m13_quotas_lecture on public.agent_ia_quotas
  for select to authenticated
  using (
    utilisateur_id = auth.uid()
    or public.est_plateforme()
    or entreprise_id = (case
                          when public.mon_proprietaire() is null then auth.uid()
                          else public.mon_proprietaire()
                        end)
  );

-- 6.c Achats : le demandeur, sa boutique (montant + statut payé/impayé),
--     le personnel plateforme (le Super Admin traite les demandes).
create policy m13_achats_lecture on public.agent_ia_achats
  for select to authenticated
  using (
    utilisateur_id = auth.uid()
    or public.est_plateforme()
    or entreprise_id = (case
                          when public.mon_proprietaire() is null then auth.uid()
                          else public.mon_proprietaire()
                        end)
  );

-- 6.d Conversations : l'auteur, sa boutique, la plateforme.
create policy m13_conversations_lecture on public.agent_ia_conversations
  for select to authenticated
  using (
    utilisateur_id = auth.uid()
    or public.est_plateforme()
    or entreprise_id = (case
                          when public.mon_proprietaire() is null then auth.uid()
                          else public.mon_proprietaire()
                        end)
  );

-- 6.e Actions : mêmes règles que les conversations.
create policy m13_actions_lecture on public.agent_ia_actions
  for select to authenticated
  using (
    utilisateur_id = auth.uid()
    or public.est_plateforme()
    or entreprise_id = (case
                          when public.mon_proprietaire() is null then auth.uid()
                          else public.mon_proprietaire()
                        end)
  );

-- Défense en profondeur : lecture seule côté client, aucune écriture directe.
revoke all on public.agent_ia_config        from public;
revoke all on public.agent_ia_quotas        from public;
revoke all on public.agent_ia_achats        from public;
revoke all on public.agent_ia_conversations from public;
revoke all on public.agent_ia_actions       from public;

revoke all on public.agent_ia_config        from anon;
revoke all on public.agent_ia_quotas        from anon;
revoke all on public.agent_ia_achats        from anon;
revoke all on public.agent_ia_conversations from anon;
revoke all on public.agent_ia_actions       from anon;

revoke insert, update, delete, truncate on public.agent_ia_config        from authenticated;
revoke insert, update, delete, truncate on public.agent_ia_quotas        from authenticated;
revoke insert, update, delete, truncate on public.agent_ia_achats        from authenticated;
revoke insert, update, delete, truncate on public.agent_ia_conversations from authenticated;
revoke insert, update, delete, truncate on public.agent_ia_actions       from authenticated;

grant select on public.agent_ia_config        to authenticated;
grant select on public.agent_ia_quotas        to authenticated;
grant select on public.agent_ia_achats        to authenticated;
grant select on public.agent_ia_conversations to authenticated;
grant select on public.agent_ia_actions       to authenticated;


-- ============================================================================
--  7. VÉRIFICATIONS
-- ============================================================================

-- 7.a Tables créées
select table_name
  from information_schema.tables
 where table_schema = 'public'
   and table_name like 'agent_ia_%'
 order by table_name;

-- 7.b Configuration par défaut (doit renvoyer UNE ligne)
select tarif_par_quota, caracteres_par_quota, prix_pack_10_quotas,
       quotas_offerts_inscription, actif
  from public.agent_ia_config;

-- 7.c Policies (doivent toutes commencer par `m13_`)
select tablename, policyname, cmd
  from pg_policies
 where schemaname = 'public'
   and tablename like 'agent_ia_%'
 order by tablename, policyname;

-- 7.d Index
select indexname from pg_indexes
 where schemaname = 'public'
   and tablename like 'agent_ia_%'
 order by indexname;


-- ============================================================================
--  8. CONTRÔLES MANUELS UTILES (à exécuter au besoin, compte connecté)
-- ============================================================================
--  (Les écritures seront réservées à l'Edge Function et aux RPC de l'Étape 2 ;
--   en attendant, contrôlez simplement la lecture :)
--
-- Lecture des tarifs :
--
-- select * from public.agent_ia_config;
--
-- Mon solde + le pool de mon entreprise :
--
-- select utilisateur_id, entreprise_id, quotas_disponibles,
--        quotas_utilises_total, quotas_achetes_total, attribue_le
--   from public.agent_ia_quotas
--  where utilisateur_id = auth.uid()
--     or (utilisateur_id is null
--         and entreprise_id = (case when public.mon_proprietaire() is null
--                                   then auth.uid()
--                                   else public.mon_proprietaire() end));
--
-- Mes demandes d'achat (montant toujours affiché, payé ou non) :
--
-- select nombre_quotas, montant_cdf, statut, statut_paiement, created_at
--   from public.agent_ia_achats
--  where utilisateur_id = auth.uid()
--  order by created_at desc;
