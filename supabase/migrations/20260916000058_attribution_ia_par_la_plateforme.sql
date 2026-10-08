-- ============================================================================
--  biashara_yangu — CORRECTIF 58 : LE SUPER ADMIN PEUT ATTRIBUER DES QUOTAS
--  Migration 20260916000058_attribution_ia_par_la_plateforme.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--     L'application publiée n'est pas touchée : elle se contente de LIRE ce
--     que cette fonction lui renvoie.
--
--  LA QUESTION
--  -----------
--  « Pourquoi, quand j'attribue depuis le Super Admin, rien ne marche et
--    c'est vide ? »
--
--  LA RÉPONSE — TROIS VERROUS, TOUS DANS `rpc_agent_ia_etat`
--  ---------------------------------------------------------
--  Le correctif 56 a bien réparé le DROIT d'attribuer côté serveur
--  (`rpc_agent_ia_attribuer` : le personnel plateforme passe désormais).
--  Mais l'ÉCRAN ne sait rien afficher, pour trois raisons qui n'ont pas
--  encore été corrigées :
--
--    1. LA SECTION N'EST JAMAIS CONSTRUITE.
--       L'écran « Quotas IA » n'affiche la carte « Attribuer des quotas »
--       que si le serveur renvoie `est_proprietaire: true`
--       (`achat_quotas_page.dart`). Or cette fonction renvoie
--       `not v_plateforme and role = 'PROPRIETAIRE'` : pour le personnel de
--       la plateforme c'est TOUJOURS faux. Aucun bouton, aucune liste.
--
--    2. LA LISTE DES MEMBRES EST VIDE.
--       La requête des collaborateurs est enfermée dans `if not v_plateforme`,
--       donc `v_collab` reste vide pour le personnel plateforme : le menu
--       « Collaborateur » affiche « Aucun collaborateur ». C'est le « c'est
--       vide » constaté. Et un personnel plateforme n'a évidemment aucun
--       collaborateur dans SON entreprise : la liste doit venir d'ailleurs.
--
--    3. LE BOUTON SERAIT GRISÉ DE TOUTE FAÇON.
--       Le bouton « Attribuer les quotas » est désactivé quand le pool vaut 0.
--       Le personnel plateforme n'ayant pas d'entreprise, aucun pool n'était
--       chargé (`pool: null`) → pool = 0 → bouton mort.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--  Elle redéfinit UNE SEULE fonction, `rpc_agent_ia_etat`, avec trois
--  changements — et rien d'autre :
--
--    ✅ `est_proprietaire` devient vrai pour le personnel plateforme, ce qui
--       révèle la carte d'attribution dans l'application DÉJÀ PUBLIÉE ;
--    ✅ la liste des cibles devient celle des PATRONS de boutique (c'est
--       l'intention métier : « l'attribution va vers le propriétaire, et le
--       propriétaire distribue ensuite à son équipe ») ;
--    ✅ le pool affiché devient le TOTAL des réserves d'entreprises — la
--       réserve que la plateforme peut distribuer.
--
--  ⚠️ EFFETS DE BORD ASSUMÉS (2 phrases de l'écran « Demandes & achats »)
--  ---------------------------------------------------------------------
--  Le même drapeau pilote le libellé du bouton « Marquer ce paiement payé » :
--  le personnel plateforme lira « Une dépense "Quotas IA" sera écrite dans la
--  caisse de l'entreprise » au lieu de « la plateforme a encaissé ce montant ».
--  La BASE, elle, ne change pas : `rpc_agent_ia_marquer_paye` n'écrit une
--  dépense QUE pour un vrai propriétaire (jamais pour un Super Admin). C'est
--  donc un texte imprécis, sans conséquence comptable. Le nettoyage définitif
--  tient en deux lignes de Dart, à faire à la PROCHAINE compilation (voir la
--  note en fin de fichier) — pas maintenant, l'application est publiée.
--
--  CE QUI N'EST PAS TOUCHÉ
--  -----------------------
--    • `rpc_agent_ia_attribuer` (déjà correct depuis le 56) ;
--    • les pools, les allocations, les montants : AUCUNE écriture de données.
--      Cette migration ne fait que redéfinir une fonction de LECTURE.
--  IDEMPOTENTE : relançable sans effet de bord.
--
--  ⚠️ À EXÉCUTER APRÈS les correctifs 56 et 57.
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. PRÉ-REQUIS
-- ============================================================================

do $verif_prerequis$
begin
  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'mon_role'
  ) then
    raise exception 'fonction public.mon_role() absente : executez d''abord 20260916000006_module4_permissions.sql.';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'entreprise_de_proprietaire'
  ) then
    raise exception 'fonction public.entreprise_de_proprietaire() absente : executez d''abord 20260916000038_module17_verrouillage_comptes.sql.';
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'mon_entreprise_id'
  ) then
    raise exception 'fonction public.mon_entreprise_id() absente : executez d''abord 20260916000050_fix_rls_entreprises.sql.';
  end if;
end $verif_prerequis$;


-- ============================================================================
--  1. `rpc_agent_ia_etat` — L'ÉTAT VU PAR LE SUPER ADMIN
-- ============================================================================
--  Base : version du correctif 56 (elle-même issue de la migration 17).
--  Seules les trois lignes signalées « CORRECTIF 58 » changent. Tout le reste
--  est repris à l'identique, y compris le bonus de bienvenue et le repli
--  `mon_entreprise_id()` → identifiant du compte.

create or replace function public.rpc_agent_ia_etat()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user            uuid := auth.uid();
  v_plateforme      boolean;
  v_role            text;
  v_soc             uuid;
  v_config          public.agent_ia_config%rowtype;
  v_pool            public.agent_ia_quotas%rowtype;
  v_moi             public.agent_ia_quotas%rowtype;
  v_collab          jsonb := '[]'::jsonb;
  v_reserve         bigint := 0;
  v_reserve_achetes bigint := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter vos quotas.';
  end if;

  v_plateforme := public.est_plateforme();
  v_role       := public.mon_role();

  select * into v_config from public.agent_ia_config limit 1;
  if v_config.id is null then
    raise exception 'CONFIG_ABSENTE|Configuration IA absente : exécutez 20260916000014_module13_agent_ia.sql.';
  end if;

  -- S'assurer qu'une entreprise (abonnement) existe pour la boutique.
  -- Best-effort : si la création échoue, les quotas fonctionnent quand même.
  -- Le personnel plateforme n'a pas de boutique : on ne crée rien pour lui.
  if not v_plateforme then
    begin
      perform public.rpc_entreprise_creer(null);
    exception when others then null;
    end;
  end if;

  v_soc := public.mon_entreprise_id();
  if v_soc is null then
    -- Repli : entreprise indisponible (compte plateforme, dossier incomplet).
    v_soc := v_user;
  end if;

  -- ── POOL ────────────────────────────────────────────────────────────────
  --  CORRECTIF 58 : le personnel plateforme n'a pas de pool propre — la
  --  réserve qu'il peut distribuer est le TOTAL des réserves d'entreprises.
  --  Sans ce total, l'écran afficherait « Pool actuel : 0 » et désactiverait
  --  le bouton d'attribution (troisième verrou).
  if v_plateforme then
    select coalesce(sum(q.quotas_disponibles), 0),
           coalesce(sum(q.quotas_achetes_total), 0)
      into v_reserve, v_reserve_achetes
      from public.agent_ia_quotas q
     where q.utilisateur_id is null;
  else
    select * into v_pool
      from public.agent_ia_quotas
     where utilisateur_id is null
       and entreprise_id = v_soc;

    if v_pool.id is null then
      insert into public.agent_ia_quotas (
        utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total
      ) values (
        null, v_soc, greatest(coalesce(v_config.quotas_offerts_inscription, 0), 0), 0
      )
      on conflict do nothing;

      select * into v_pool
        from public.agent_ia_quotas
       where utilisateur_id is null
         and entreprise_id = v_soc;
    end if;
  end if;

  -- Mon allocation personnelle.
  select * into v_moi
    from public.agent_ia_quotas
   where utilisateur_id = v_user;

  -- ── CIBLES POSSIBLES ────────────────────────────────────────────────────
  if v_plateforme then
    --  CORRECTIF 58 : la plateforme distribue aux PATRONS de boutique (et à
    --  eux seuls : ce sont eux qui répartissent ensuite dans leur équipe).
    --  Le libellé porte le nom de la boutique, sans quoi deux patrons
    --  homonymes seraient indiscernables dans la liste déroulante.
    select coalesce(jsonb_agg(jsonb_build_object(
             'id',   u.id,
             'nom',  coalesce(nullif(btrim(u.nom), ''), u.email, 'Compte sans nom')
                     || coalesce(' — ' || nullif(btrim(e.nom), ''), '')
                     || case when e.id is null then ' (sans boutique)' else '' end
                     || case when upper(coalesce(e.statut::text, '')) = 'SUSPENDU'
                             then ' (abonnement suspendu)' else '' end,
             'role', coalesce(u.new_role::text, u.role, '')
           ) order by e.nom nulls last, u.nom), '[]'::jsonb)
      into v_collab
      from public.utilisateurs u
      left join public.entreprises e
             on e.id = public.entreprise_de_proprietaire(u.id)
     where public.mon_role(u.id) = 'PROPRIETAIRE';
  else
    -- Collaborateurs de l'entreprise (pour l'attribution par le patron).
    -- Correctif 56 : on accepte aussi les comptes rattachés à l'ENTREPRISE
    -- (`entreprise_id`), et pas seulement ceux rattachés au patron.
    select coalesce(jsonb_agg(jsonb_build_object(
             'id',   u.id,
             'nom',  coalesce(nullif(btrim(u.nom), ''), u.email),
             'role', coalesce(u.new_role::text, u.role, '')
           ) order by u.nom), '[]'::jsonb)
      into v_collab
      from public.utilisateurs u
     where u.id <> v_user
       and (u.parent_id = v_user or u.entreprise_id = v_soc);
  end if;

  return jsonb_build_object(
    'config', jsonb_build_object(
      'tarif_par_quota',           v_config.tarif_par_quota,
      'caracteres_par_quota',      v_config.caracteres_par_quota,
      'prix_pack_10_quotas',       v_config.prix_pack_10_quotas,
      'quotas_offerts_inscription', v_config.quotas_offerts_inscription,
      'actif',                     v_config.actif
    ),
    'pool', case
              when v_plateforme then jsonb_build_object(
                'quotas_disponibles',   v_reserve,
                'quotas_achetes_total', v_reserve_achetes
              )
              when v_pool.id is null then null
              else jsonb_build_object(
                'quotas_disponibles',   v_pool.quotas_disponibles,
                'quotas_achetes_total', v_pool.quotas_achetes_total
              )
            end,
    'moi', jsonb_build_object(
      'quotas_disponibles',    coalesce(v_moi.quotas_disponibles, 0),
      'quotas_utilises_total', coalesce(v_moi.quotas_utilises_total, 0),
      'quotas_achetes_total',  coalesce(v_moi.quotas_achetes_total, 0)
    ),
    'role',            v_role,
    --  CORRECTIF 58 : le personnel plateforme passe aussi. Ce drapeau est le
    --  SEUL levier que la base puisse actionner pour révéler — ou non — la
    --  carte d'attribution dans une application déjà publiée.
    'est_proprietaire', (v_plateforme or v_role = 'PROPRIETAIRE'),
    'est_plateforme',  v_plateforme,
    'est_super_admin', public.est_super_admin(),
    'collaborateurs',  v_collab
  );
end;
$$;

comment on function public.rpc_agent_ia_etat() is
  'Module 13 — État IA : config, pool (total des réserves pour la plateforme), allocation, cibles (patrons pour la plateforme). Correctif 58 : le personnel plateforme peut attribuer des quotas.';

revoke all on function public.rpc_agent_ia_etat() from public, anon;
grant execute on function public.rpc_agent_ia_etat() to authenticated;


-- ============================================================================
--  2. VÉRIFICATION — la version active porte-t-elle bien le correctif ?
-- ============================================================================

do $verif_correctif$
declare
  v_droit   boolean;
  v_cibles  boolean;
  v_reserve boolean;
begin
  select position('v_plateforme or v_role = ''PROPRIETAIRE''' in pg_get_functiondef(p.oid)) > 0,
         position('entreprise_de_proprietaire(u.id)' in pg_get_functiondef(p.oid)) > 0,
         position('sum(q.quotas_disponibles)' in pg_get_functiondef(p.oid)) > 0
    into v_droit, v_cibles, v_reserve
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_agent_ia_etat';

  if not coalesce(v_droit, false) then
    raise exception 'Correctif 58 : le droit plateforme n''est pas en place.';
  end if;

  if not coalesce(v_cibles, false) then
    raise exception 'Correctif 58 : la liste des patrons n''est pas en place.';
  end if;

  if not coalesce(v_reserve, false) then
    raise exception 'Correctif 58 : le total des reserves n''est pas en place.';
  end if;

  raise notice 'Correctif 58 : les trois verrous sont leves.';
end $verif_correctif$;


-- ============================================================================
--  RAPPORT FINAL — ce que le Super Admin verra dans l'application
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select '1. COMPTE PLATEFORME' as bloc,
       left(u.id::text, 8) as cle,
       coalesce(nullif(btrim(u.nom), ''), u.email, 'Compte sans nom') as libelle,
       0::bigint as valeur,
       'role ' || public.mon_role(u.id)
         || ' — carte d''attribution '
         || case when public.mon_role(u.id) in
                      ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE', 'SUPPORT')
                 then 'AFFICHÉE' else 'masquée' end as detail
  from public.utilisateurs u
 where public.mon_role(u.id) in
       ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE', 'SUPPORT')

union all

select '2. PATRON CIBLE',
       left(u.id::text, 8),
       coalesce(nullif(btrim(u.nom), ''), u.email, 'Compte sans nom')
         || coalesce(' — ' || nullif(btrim(e.nom), ''), '')
         || case when e.id is null then ' (sans boutique)' else '' end,
       coalesce((select a.quotas_disponibles
                   from public.agent_ia_quotas a
                  where a.utilisateur_id = u.id), 0)::bigint,
       'allocation du patron — entreprise '
         || coalesce(left(public.entreprise_de_proprietaire(u.id)::text, 8), 'INTROUVABLE')
  from public.utilisateurs u
  left join public.entreprises e
         on e.id = public.entreprise_de_proprietaire(u.id)
 where public.mon_role(u.id) = 'PROPRIETAIRE'

union all

select '3. RESERVE',
       left(q.entreprise_id::text, 8),
       coalesce(nullif(btrim(e.nom), ''),
                case when exists (select 1 from public.utilisateurs x
                                   where x.id = q.entreprise_id)
                     then '⚠️ cle = un COMPTE (a nettoyer)'
                     else '⚠️ entreprise inconnue' end),
       q.quotas_disponibles::bigint,
       'achetes ' || q.quotas_achetes_total
  from public.agent_ia_quotas q
  left join public.entreprises e on e.id = q.entreprise_id
 where q.utilisateur_id is null

 order by 1, 3;


-- ============================================================================
--  NOTE POUR LA PROCHAINE COMPILATION (à faire un jour, pas maintenant)
--  ------------------------------------------------------------------------
--  Deux lignes de `lib/pages/achat_quotas_page.dart` deviendront alors
--  inutilement restrictives, dès que le drapeau `est_proprietaire` sert aussi
--  au personnel plateforme :
--
--    • la carte d'attribution gagnerait à tester explicitement le droit réel
--      (`estProprietaire || estPlateforme`) plutôt qu'un drapeau détourné ;
--    • le libellé de « Marquer ce paiement payé » doit dire « la plateforme a
--      encaissé » quand `estPlateforme` est vrai, et « dépense écrite dans la
--      caisse » seulement pour un vrai propriétaire.
--
--  Aucune urgence : la base ne se trompe pas, seul un texte est imprécis.
-- ============================================================================
