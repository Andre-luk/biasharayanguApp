-- ============================================================================
--  biashara_yangu — CORRECTIF 55 : 10 QUOTAS IA OFFERTS
--  Migration 20260916000055_quotas_ia_biasharagroup.sql
-- ============================================================================
--
--  LE BESOIN
--  ---------
--  Offrir 10 quotas d'assistant IA au compte « biasharagroup@gmail.com »,
--  sans passer par le circuit d'achat (geste commercial).
--
--  COMMENT FONCTIONNE LE MODULE 13 (à respecter)
--  ---------------------------------------------
--  Il y a DEUX niveaux de solde :
--     • le POOL de l'entreprise (ligne sans utilisateur) — les quotas achetés
--       ou offerts y arrivent ;
--     • l'ALLOCATION de chaque membre — c'est ELLE qui est débitée quand le
--       membre utilise l'assistant (`rpc_agent_ia_debiter` ne cherche que
--       `utilisateur_id`, il ne retombe PAS sur le pool).
--  Et une règle : ATTRIBUER des quotas DÉBITE le pool du même montant. Le pool
--  est donc la réserve, l'allocation est la part consommable.
--
--  ⚠️ Conséquence : créditer le seul pool ne suffirait pas — le compte
--     verrait 10 quotas dans sa réserve mais ne pourrait toujours PAS poser de
--     question. Cette migration fait donc les DEUX :
--        1. elle crédite le pool de 10 (le cadeau) ;
--        2. elle attribue ces 10 au compte, pour qu'ils soient utilisables
--           immédiatement.
--     Résultat attendu : pool 0 · allocation du compte 10.
--     (Mettez `v_pour_le_compte := false` pour laisser les 10 dans le pool.)
--
--  IDEMPOTENTE : le don est repéré par son motif dans le journal
--  (`journal_audit`, action `AGENT_IA_QUOTAS_OFFERTS`). Relancer la migration
--  n'offre PAS 10 quotas de plus. Pour offrir un second lot, changez le motif.
--
--  Elle ne dépend PAS de la migration 52 (module « gestion des tokens ») :
--  le registre `agent_ia_distributions` n'est alimenté que s'il existe.
--
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


do $$
declare
  -- ─────────────────────────────  RÉGLAGES  ─────────────────────────────
  v_email          text    := 'biasharagroup@gmail.com';

  -- Nombre de quotas offerts.
  v_quotas         integer := 10;

  -- true  = les quotas sont aussi ATTRIBUÉS au compte (utilisables tout de suite)
  -- false = les quotas restent dans le POOL de l'entreprise (le propriétaire
  --         les distribuera lui-même depuis l'écran Quotas IA)
  v_pour_le_compte boolean := true;

  -- Motif servant AUSSI de repère d'idempotence : le changer permet d'offrir
  -- un nouveau lot plus tard.
  v_motif          text    := 'Migration 55 — 10 quotas offerts (geste commercial)';
  -- ───────────────────────────────────────────────────────────────────────

  v_user     public.utilisateurs;
  v_eid      uuid;
  v_nom      text;
  v_deja     integer := 0;
  v_tarif    numeric := 0;
  v_montant  numeric := 0;
  v_pool     integer := 0;
  v_alloc    integer := 0;
  v_has_dist boolean := false;
begin
  -- ------------------------------------------------------------------ 1) compte
  select * into v_user
    from public.utilisateurs u
   where lower(btrim(u.email)) = lower(btrim(v_email))
   limit 1;

  if v_user.id is null then
    raise exception 'Correctif 55 : aucun compte « % ».', v_email;
  end if;

  -- Entreprise du compte (ou celle de son patron : mêmes règles que
  -- public.mon_entreprise_id, qui couvre les comptes rattachés).
  select coalesce(u.entreprise_id, p.entreprise_id)
    into v_eid
    from public.utilisateurs u
    left join public.utilisateurs p on p.id = u.parent_id
   where u.id = v_user.id;

  if v_eid is null then
    raise exception 'Correctif 55 : le compte « % » n''est rattaché à aucune entreprise.', v_email;
  end if;

  select e.nom into v_nom from public.entreprises e where e.id = v_eid;

  -- ------------------------------------------------- 2) déjà offert ? (relance)
  --  Le repère est cherché dans `journal_audit`, qui existe toujours — et non
  --  dans `agent_ia_distributions` (créée par la migration 52) : cette migration
  --  doit pouvoir tourner même si le module « gestion des tokens » n'est pas
  --  encore installé.
  select count(*) into v_deja
    from public.journal_audit a
   where a.entreprise_id = v_eid
     and a.action = 'AGENT_IA_QUOTAS_OFFERTS'
     and a.details ->> 'motif' = v_motif;

  if v_deja > 0 then
    raise notice 'Correctif 55 : ce don a DEJA ete enregistre pour « % » — aucune ecriture (migration idempotente).', v_nom;
    return;
  end if;

  -- La table de traçabilité du module 13 bis n'est écrite que si elle existe.
  select exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'agent_ia_distributions'
  ) into v_has_dist;

  -- Valeur commerciale du cadeau (pour la traçabilité, rien n'est facturé).
  select coalesce(tarif_par_quota, 0) into v_tarif
    from public.agent_ia_config order by updated_at limit 1;
  v_tarif := coalesce(v_tarif, 96);
  v_montant := round(v_quotas * v_tarif, 2);

  raise notice 'Correctif 55 — dossier « % »', v_nom;
  raise notice '   quotas offerts : % (valeur % CDF, non factures)', v_quotas, v_montant;

  -- ------------------------------------------------------------- 3) le POOL
  --  `quotas_achetes_total` n'est PAS touché : un cadeau n'est pas un achat.
  insert into public.agent_ia_quotas (
    utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
  ) values (
    null, v_eid, v_quotas, 0
  )
  on conflict (entreprise_id) where utilisateur_id is null
  do update set
    quotas_disponibles = public.agent_ia_quotas.quotas_disponibles + excluded.quotas_disponibles,
    updated_at         = now();

  select q.quotas_disponibles into v_pool
    from public.agent_ia_quotas q
   where q.entreprise_id = v_eid and q.utilisateur_id is null;

  raise notice '   pool apres credit : %', coalesce(v_pool, 0);

  -- ------------------------------------------------- 4) attribution au compte
  --  Même règle que le circuit officiel : attribuer DÉBITE le pool du montant
  --  attribué. Le total (pool + allocation) reste donc inchangé.
  if v_pour_le_compte then
    update public.agent_ia_quotas q
       set quotas_disponibles = q.quotas_disponibles - v_quotas,
           updated_at         = now()
     where q.entreprise_id = v_eid
       and q.utilisateur_id is null
       and q.quotas_disponibles >= v_quotas
    returning q.quotas_disponibles into v_pool;

    if not found then
      raise exception 'Correctif 55 : pool insuffisant pour attribuer les % quotas (solde %).', v_quotas, coalesce(v_pool, 0);
    end if;

    insert into public.agent_ia_quotas (
      utilisateur_id, entreprise_id, quotas_disponibles, attribue_par, attribue_le
    ) values (
      v_user.id, v_eid, v_quotas, null, now()
    )
    on conflict (utilisateur_id)
    do update set
      quotas_disponibles = public.agent_ia_quotas.quotas_disponibles + excluded.quotas_disponibles,
      attribue_le        = excluded.attribue_le,
      updated_at         = now();

    select q.quotas_disponibles into v_alloc
      from public.agent_ia_quotas q
     where q.utilisateur_id = v_user.id;

    raise notice '   pool apres attribution : %', coalesce(v_pool, 0);
    raise notice '   allocation du compte   : %', coalesce(v_alloc, 0);

    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (
      gen_random_uuid(), v_eid, 'AGENT_IA_ATTRIBUTION', null,
      jsonb_build_object(
        'destinataire',  v_user.id,
        'compte',        v_email,
        'nombre_quotas', v_quotas,
        'pool_restant',  coalesce(v_pool, 0),
        'solde_membre',  coalesce(v_alloc, 0),
        'motif',         v_motif
      ),
      now()
    );
  end if;

  -- ------------------------------------------------------------- 5) traçabilité
  --  Le module 13 bis (migration 52) tient un registre dédié des dons. On
  --  l'alimente s'il est là ; sinon le journal suffit. L'instruction est dans un
  --  IF : PostgreSQL ne la prépare que si la branche est prise, donc aucune
  --  erreur « relation inexistante » lorsque la table est absente.
  if v_has_dist then
    insert into public.agent_ia_distributions (
      entreprise_id, quotas, montant_cdf, motif, par
    ) values (
      v_eid, v_quotas, v_montant, v_motif, null
    );
  end if;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), v_eid, 'AGENT_IA_QUOTAS_OFFERTS', null,
    jsonb_build_object(
      'compte',              v_email,
      'quotas',              v_quotas,
      'montant_cdf',         v_montant,
      'attribues_au_compte', v_pour_le_compte,
      'pool_restant',        coalesce(v_pool, 0),
      'allocation_compte',   coalesce(v_alloc, 0),
      'motif',               v_motif
    ),
    now()
  );

  raise notice 'Correctif 55 : % quota(s) offert(s) a « % ».', v_quotas, v_email;
end $$;


-- ============================================================================
--  CONTRÔLE FINAL — les soldes du compte
--  ⚠️ En DERNIER : le SQL Editor de Supabase n'affiche que le résultat de la
--     dernière instruction du script.
-- ============================================================================

with cible as (
  select coalesce(u.entreprise_id, p.entreprise_id) as eid,
         u.id                                       as uid,
         u.email                                    as email
    from public.utilisateurs u
    left join public.utilisateurs p on p.id = u.parent_id
   where lower(btrim(u.email)) = lower(btrim('biasharagroup@gmail.com'))
)
select c.email                                                          as compte,
       e.nom                                                            as entreprise,
       case when q.utilisateur_id is null
            then 'POOL (reserve de l entreprise)'
            else 'ALLOCATION du compte (utilisable)'
       end                                                              as ligne,
       coalesce(q.quotas_disponibles, 0)                                as quotas_disponibles,
       coalesce(q.quotas_utilises_total, 0)                             as quotas_utilises,
       coalesce(q.quotas_achetes_total, 0)                              as quotas_achetes,
       to_char(q.updated_at, 'DD/MM/YYYY HH24:MI')                      as maj
  from cible c
  left join public.entreprises e on e.id = c.eid
  left join public.agent_ia_quotas q
         on q.utilisateur_id = c.uid
         or (q.utilisateur_id is null and q.entreprise_id = c.eid)
 order by q.utilisateur_id nulls first;

-- ============================================================================
--  FIN — correctif 55.
-- ============================================================================
