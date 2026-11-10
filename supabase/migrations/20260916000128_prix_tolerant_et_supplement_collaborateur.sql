-- ============================================================================
--  BIASHARA YANGU — MIGRATION 128
--  « uuid = text » NE PEUT PLUS BLOQUER + SUPPLÉMENT COLLABORATEUR FACTURÉ
--  ---------------------------------------------------------------------------
--  TROIS PROBLÈMES RÉELS (10/11/2026)
--
--  1️⃣ LE PAIEMENT ÉCHOUE ENCORE SUR « uuid = text »
--     `rpc_abonnement_prix_du_cycle` et `rpc_abonnement_type_cycle` comptent
--     les versements d'une entreprise ainsi :
--         where p.entreprise_id = p_entreprise     -- texte = uuid
--     Tant que la colonne `paiements_abonnements_laperle.entreprise_id` n'est
--     pas un `uuid`, l'écran de paiement ne peut PAS charger le dossier.
--     → Ce script retente la conversion (sans perte, comme 0125) ET réécrit
--       les deux fonctions pour qu'elles comparent en TEXTE des deux côtés.
--       Après, le paiement fonctionne même si la conversion reste impossible.
--
--  2️⃣ LE SUPPLÉMENT COLLABORATEUR N'EST PAS FACTURÉ
--     `abonnement_collaborateurs_actifs` excluait tout compte dont l'ancien
--     rôle vaut `admin`. Or un collaborateur créé par le patron hérite de ce
--     rôle : il n'était donc jamais compté, et le +2 500 CDF par collaborateur
--     n'apparaissait nulle part. (Cas signalé : la collaboratrice d'Urembo
--     Market.)
--     → Le propriétaire est désormais exclu par IDENTITÉ (son identifiant
--       d'utilisateur est celui d'une entreprise), plus par son rôle.
--
--  3️⃣ LE MONTANT DEMANDÉ IGNORAIT CE SUPPLÉMENT
--     `rpc_abonnement_preparer_renouvellement` figeait `montant_total_du` au
--     prix de BASE. Le client payait donc 10 000 alors que le moteur attendait
--     12 500 (base + collaboratrice) et le dossier restait « en attente de
--     complément », sans activation.
--     → Le montant figé inclut désormais le supplément, et la réponse détaille
--       base / supplément / total.
--
--  ⚠️ IDEMPOTENT — AUCUNE DONNÉE PERDUE — à exécuter dans l'éditeur SQL.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. CONVERSION EN uuid (retentée : idempotente et sans perte)
-- ============================================================================

do $$
declare
  v_type  text;
  v_total bigint;
  v_bad   bigint;
begin
  select data_type into v_type
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'paiements_abonnements_laperle'
     and column_name = 'entreprise_id';

  if v_type is null then
    raise notice '128 — table paiements_abonnements_laperle absente : rien à faire.';
    return;
  end if;

  if v_type = 'uuid' then
    raise notice '128 — paiements_abonnements_laperle.entreprise_id est déjà en uuid.';
    return;
  end if;

  select count(*),
         count(*) filter (
           where entreprise_id is not null
             and btrim(entreprise_id) <> ''
             and btrim(entreprise_id) !~
                 '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
         )
    into v_total, v_bad
    from public.paiements_abonnements_laperle;

  if coalesce(v_bad, 0) > 0 then
    raise warning
      '128 — % ligne(s) sur % ne sont pas des uuid : conversion NON effectuée. '
      'Les fonctions ci-dessous comparent désormais en texte : le paiement fonctionnera quand même.',
      v_bad, v_total;
    return;
  end if;

  alter table public.paiements_abonnements_laperle
    alter column entreprise_id type uuid
    using nullif(btrim(entreprise_id), '')::uuid;

  raise notice '128 — paiements_abonnements_laperle.entreprise_id converti en uuid (% lignes).', v_total;
exception
  when others then
    raise warning '128 — conversion impossible (% : %). La colonne reste en texte ; les fonctions tolérantes prennent le relais.',
      sqlstate, sqlerrm;
end $$;

do $$
declare
  v_type  text;
  v_total bigint;
  v_bad   bigint;
begin
  select data_type into v_type
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'agent_ia_achats'
     and column_name = 'entreprise_id';

  if v_type is null or v_type = 'uuid' then
    return;
  end if;

  select count(*),
         count(*) filter (
           where entreprise_id is not null
             and btrim(entreprise_id) <> ''
             and btrim(entreprise_id) !~
                 '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
         )
    into v_total, v_bad
    from public.agent_ia_achats;

  if coalesce(v_bad, 0) > 0 then
    raise warning '128 — agent_ia_achats : % valeur(s) non-uuid, conversion ignorée.', v_bad;
    return;
  end if;

  alter table public.agent_ia_achats
    alter column entreprise_id type uuid
    using nullif(btrim(entreprise_id), '')::uuid;

  raise notice '128 — agent_ia_achats.entreprise_id converti en uuid (% lignes).', v_total;
exception
  when others then
    raise warning '128 — agent_ia_achats : conversion impossible (% : %).', sqlstate, sqlerrm;
end $$;


-- ============================================================================
--  2. PRIX DU CYCLE — comparaison TOLÉRANTE AUX TYPES
-- ============================================================================

create or replace function public.rpc_abonnement_prix_du_cycle(
  p_entreprise uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_e         public.entreprises%rowtype;
  v_grille    numeric := 0;
  v_paiements integer := 0;
  v_prix      numeric := 0;
begin
  select * into v_e from public.entreprises where id = p_entreprise;
  if not found then
    return 0;
  end if;

  -- Combien de versements ont déjà été enregistrés sur ce dossier ?
  -- (0 = le client n'a encore JAMAIS payé : c'est le premier cycle payant.)
  -- ⚠️ 128 : comparaison en TEXTE des deux côtés. Cette table est historique,
  --    sa colonne peut être en `text` alors que `p_entreprise` est un `uuid` ;
  --    sans ce `::text` PostgreSQL lève « operator does not exist: uuid = text »
  --    et l'écran de paiement ne peut pas charger le dossier.
  select count(*) into v_paiements
    from public.paiements_abonnements_laperle p
   where p.entreprise_id::text = p_entreprise::text;

  -- 1️⃣ PREMIER CYCLE PAYANT et installation définie → c'est elle qu'on
  --    réclame (elle comprend le premier mois). Installation à 0/NULL =
  --    offerte : on ne réclame rien et on passe au mensuel.
  if v_paiements = 0 and coalesce(v_e.prix_installation, 0) > 0 then
    return v_e.prix_installation;
  end if;

  select coalesce(g.montant_abonnement, 0)
    into v_grille
    from public.groupes_tarifaires g
   where g.id = v_e.groupe_tarifaire_id;

  -- 2️⃣ Renouvellement : le MENSUEL, jamais l'installation.
  v_prix := coalesce(
    nullif(v_e.prix_abonnement_mensuel, 0),
    nullif(v_grille, 0),
    case
      when coalesce(v_e.montant_total_du, 0) > 0
       and coalesce(v_e.montant_total_du, 0) <> coalesce(v_e.prix_installation, -1)
        then v_e.montant_total_du
      else 0
    end,
    0
  );

  return coalesce(v_prix, 0);
end;
$$;

comment on function public.rpc_abonnement_prix_du_cycle(uuid) is
  'Prix du prochain cycle (installation au premier cycle payant, puis mensuel). '
  'Migration 128 : comparaison tolérante aux types hérités (texte/uuid).';


-- ============================================================================
--  3. NATURE DU CYCLE — comparaison TOLÉRANTE AUX TYPES
-- ============================================================================

create or replace function public.rpc_abonnement_type_cycle(
  p_entreprise uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
           when (select count(*) from public.paiements_abonnements_laperle p
                  where p.entreprise_id::text = p_entreprise::text) = 0
            and coalesce((select e.prix_installation from public.entreprises e
                           where e.id = p_entreprise), 0) > 0
             then 'installation'
           else 'abonnement'
         end;
$$;

comment on function public.rpc_abonnement_type_cycle(uuid) is
  'Nature du prochain cycle : « installation » (premier cycle payant) ou « abonnement ». '
  'Migration 128 : comparaison tolérante aux types hérités.';


-- ============================================================================
--  4. QUI EST UN COLLABORATEUR FACTURABLE ? (correctif 128)
-- ============================================================================
--  AVANT : tout compte dont l'ancien rôle vaut `admin` était exclu. Or un
--  collaborateur créé par le patron reçoit ce rôle → jamais facturé.
--  APRÈS : le propriétaire est écarté par IDENTITÉ, pas par son rôle :
--    • un patron est un compte dont l'identifiant EST celui d'une entreprise ;
--    • `new_role = 'PROPRIETAIRE'` est écarté aussi (comptes modernes) ;
--    • les rôles de la plateforme ne sont jamais facturés.

create or replace function public.abonnement_collaborateurs_actifs(
  p_entreprise uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_n integer := 0;
begin
  if p_entreprise is null then
    return 0;
  end if;

  select count(distinct u.id)
    into v_n
    from public.utilisateurs u
   where coalesce(u.valide, 1) <> 0
     -- Jamais un patron : son compte porte l'identifiant d'une entreprise.
     and not exists (
       select 1 from public.entreprises e where e.id = u.id
     )
     and coalesce(upper(btrim(u.new_role::text)), '') not in (
           'PROPRIETAIRE', 'SUPER_ADMIN', 'GESTIONNAIRE_COMPTES',
           'FINANCE_LAPERLE', 'SUPPORT', 'AGENT_TERRAIN'
         )
     and lower(coalesce(u.role::text, '')) not in ('super_admin', 'plateforme')
     and (
       u.entreprise_id = p_entreprise
       or u.parent_id = p_entreprise::text
     );

  return coalesce(v_n, 0);
end;
$$;

comment on function public.abonnement_collaborateurs_actifs(uuid) is
  'Module 26 / correctif 128 — comptes collaborateurs facturables : rattachés à '
  'l''entreprise, validés, hors propriétaire (exclu par identité) et hors plateforme.';


-- ============================================================================
--  5. LE MONTANT DEMANDÉ INCLUT LE SUPPLÉMENT
-- ============================================================================
--  Reprise de la migration 090, avec un seul changement de fond :
--     montant_total_du = prix du cycle + supplément collaborateurs
--  Sans cela, le client payait le prix de base, le moteur attendait le total
--  et le dossier restait « en attente de complément ».

create or replace function public.rpc_abonnement_preparer_renouvellement(
  p_entreprise uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_id     uuid;
  v_e      public.entreprises%rowtype;
  v_prix   numeric := 0;
  v_supp   numeric := 0;
  v_total  numeric := 0;
  v_type   text := 'abonnement';
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour payer votre abonnement.';
  end if;

  v_owner := public.mon_proprietaire();
  v_id := coalesce(p_entreprise, public.mon_entreprise_id(), v_owner, v_user);

  select * into v_e from public.entreprises where id = v_id for update;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  -- Portée STRICTE : l'entreprise de l'appelant (ou un membre de sa société),
  -- jamais celle d'un tiers. La plateforme garde son droit d'intervention.
  if not (v_user = v_e.id
          or v_id = coalesce(v_owner, v_e.id)
          or v_user = v_owner
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
  end if;

  v_type := public.rpc_abonnement_type_cycle(v_id);

  -- L'abonnement court encore : on n'ouvre rien, on ne facture rien.
  if not (v_e.statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
          or (v_e.date_expiration is not null and v_e.date_expiration < now())) then
    return jsonb_build_object(
      'ok', true,
      'entreprise_id', v_id,
      'cycle_ouvert', false,
      'motif', 'CYCLE_EN_COURS',
      'type_cycle', v_type,
      'solde_restant', coalesce(v_e.solde_restant, 0),
      'prix_mensuel', public.rpc_abonnement_prix_du_cycle(v_id),
      'supplement_collaborateurs', public.abonnement_supplement_collaborateurs(v_id),
      'devise', coalesce(v_e.devise, 'CDF')
    );
  end if;

  -- Un cycle est déjà ouvert avec un solde : le client paie, on ne touche
  -- surtout pas au montant (double facturation impossible).
  if coalesce(v_e.solde_restant, 0) > 0.001 then
    return jsonb_build_object(
      'ok', true,
      'entreprise_id', v_id,
      'cycle_ouvert', true,
      'motif', 'DEJA_OUVERT',
      'type_cycle', v_type,
      'solde_restant', coalesce(v_e.solde_restant, 0),
      'prix_mensuel', public.rpc_abonnement_prix_du_cycle(v_id),
      'supplement_collaborateurs', public.abonnement_supplement_collaborateurs(v_id),
      'devise', coalesce(v_e.devise, 'CDF')
    );
  end if;

  v_prix := public.rpc_abonnement_prix_du_cycle(v_id);
  if v_prix <= 0 then
    raise exception 'PRIX_ABSENT|Aucun abonnement n''est défini pour ce compte : contactez la plateforme.';
  end if;

  -- 🔧 128 : le supplément collaborateurs fait partie du cycle.
  v_supp  := public.abonnement_supplement_collaborateurs(v_id);
  v_total := round(v_prix + v_supp, 2);

  -- Nouveau cycle. `statut = EN_ATTENTE_COMPLEMENT` FIGE le montant :
  -- le moteur ne rouvre un cycle que sur `EXPIRE` ou solde nul ; il créditera
  -- donc exactement ce montant-là (installation ou mensuel + collaborateurs).
  update public.entreprises
     set montant_total_du          = v_total,
         montant_deja_paye         = 0,
         supplement_collaborateurs = v_supp,
         statut                    = 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum,
         updated_at                = now()
   where id = v_id;

  begin
    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), v_id, 'CYCLE_RENOUVELLEMENT_OUVERT', v_user,
      jsonb_build_object(
        'montant', v_total,
        'prix_base', v_prix,
        'supplement_collaborateurs', v_supp,
        'type_cycle', v_type,
        'statut_avant', v_e.statut,
        'expiration', v_e.date_expiration
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', v_id,
    'cycle_ouvert', true,
    'motif', 'CYCLE_OUVERT',
    'type_cycle', v_type,
    'solde_restant', v_total,
    'prix_mensuel', v_prix,
    'supplement_collaborateurs', v_supp,
    'devise', coalesce(v_e.devise, 'CDF')
  );
end;
$$;

comment on function public.rpc_abonnement_preparer_renouvellement(uuid) is
  'Ouvre le cycle suivant (installation au premier cycle payant, puis mensuel) et '
  'FIGE le montant — supplément collaborateurs INCLUS (correctif 128).';


-- ============================================================================
--  6. CONTRÔLES — ce que dit la base maintenant
-- ============================================================================

-- V1. Les deux fonctions comparent-elles en texte ? (attendu : true, true)
select position('entreprise_id::text' in pg_get_functiondef(
         'public.rpc_abonnement_prix_du_cycle(uuid)'::regprocedure)) > 0
         as prix_tolerant,
       position('entreprise_id::text' in pg_get_functiondef(
         'public.rpc_abonnement_type_cycle(uuid)'::regprocedure)) > 0
         as type_tolerant;

-- V2. Types réels des colonnes en cause.
select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and column_name = 'entreprise_id'
   and table_name in ('paiements_abonnements_laperle',
                      'agent_ia_achats',
                      'paiements_serdipay')
 order by table_name;

-- V3. Collaborateurs facturés, supplément et ÉTAT DU DOSSIER, pour les 20
--     dernières boutiques. Vérifiez qu'aucun patron n'apparaît avec
--     1 collaborateur par erreur.
select e.nom,
       public.abonnement_collaborateurs_actifs(e.id)      as collaborateurs,
       public.abonnement_prix_collaborateur()             as prix_unitaire,
       public.abonnement_supplement_collaborateurs(e.id)  as supplement,
       public.rpc_abonnement_prix_du_cycle(e.id)          as prix_base,
       public.rpc_abonnement_prix_du_cycle(e.id)
         + public.abonnement_supplement_collaborateurs(e.id) as prochain_cycle,
       e.statut::text                as statut,
       e.date_expiration,
       e.montant_total_du,
       e.montant_deja_paye,
       e.solde_restant,
       e.activation_etape
  from public.entreprises e
 order by e.created_at desc
 limit 20;

-- Lecture : un dossier en `ESSAI_7J` avec `solde_restant = 2500` signifie que
-- le supplément collaborateurs n'a pas été encaissé : l'essai de 7 jours a
-- remplacé le mois complet. Il suffit d'enregistrer le complément
-- (« Enregistrer un paiement ») pour passer ACTIF + 30 jours.
