-- ============================================================================
--  BIASHARA YANGU — MIGRATION 129
--  `solde_restant` REDEVIENT COHÉRENT (total dû − déjà payé)
--  ---------------------------------------------------------------------------
--  CE QUE MONTRE LA VÉRIFICATION V3 DE LA MIGRATION 128
--    Kamm'es          : total 10 000, payé 10 000  → solde 30 000  ❌
--    Les Trois Frères : total  5 000, payé  5 000  → solde 15 000  ❌
--    Jean business    : total 30 000, payé 30 000  → solde null    ❌
--
--  POURQUOI
--    `solde_restant` était une colonne GÉNÉRÉE par la base. La migration 0094
--    l'a transformée en colonne ordinaire — parce que plusieurs fonctions y
--    écrivaient (erreur 428C9 « is a generated column »).
--
--    Mais la dernière version du moteur (`rpc_abonnement_enregistrer_paiement`,
--    migration 0115) N'ÉCRIT PLUS cette colonne : elle écrit
--    `montant_total_du` et `montant_deja_paye` seulement. Depuis, personne ne
--    recalcule le solde : il est resté FIGÉ à sa dernière valeur, parfois
--    fausse ou nulle.
--
--  CONSÉQUENCE CONCRÈTE
--    • `rpc_serdipay_ouvrir` demande `solde_restant` comme montant à payer :
--      un solde périmé donne un montant faux, ou 0 → refus « SOLDE_NUL ».
--    • `rpc_abonnement_preparer_renouvellement` croit un cycle déjà ouvert
--      (`DEJA_OUVERT`) et réclame un montant qui n'existe plus.
--    • `rpc_abonnement_reactiver` refuserait pour « solde restant » alors que
--      tout est payé.
--
--  LA CORRECTION
--    1. Un TRIGGER recalcule `solde_restant` à CHAQUE écriture sur
--       `entreprises` : solde = greatest(total dû − déjà payé, 0).
--       C'est exactement la sémantique de l'ancienne colonne générée, mais
--       sans l'erreur 428C9 (le trigger corrige, il ne rejette pas).
--       Plus aucune fonction n'a besoin d'y penser.
--    2. Les soldes existants sont RÉPARÉS une fois pour toutes.
--
--  ⚠️ IDEMPOTENT — à exécuter après la migration 128.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE SOLDE EST TOUJOURS DÉRIVÉ DU TOTAL ET DU PAYÉ
-- ============================================================================

create or replace function public.entreprises_solde_restant()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Un solde est par définition « ce qu'il reste à payer ».
  -- Les triggers sont prioritaires : une valeur écrite à la main est
  -- immédiatement recalculée, donc elle ne peut plus devenir incohérente.
  new.solde_restant := greatest(
                         coalesce(new.montant_total_du, 0)
                         - coalesce(new.montant_deja_paye, 0),
                         0
                       );
  return new;
end;
$$;

comment on function public.entreprises_solde_restant() is
  'Migration 129 — entretient entreprises.solde_restant = total dû − déjà payé '
  '(sémantique de l''ancienne colonne générée, sans l''erreur 428C9).';

drop trigger if exists trg_entreprises_solde_restant on public.entreprises;
create trigger trg_entreprises_solde_restant
  before insert or update on public.entreprises
  for each row execute function public.entreprises_solde_restant();


-- ============================================================================
--  2. RÉPARATION DES SOLDES EXISTANTS
-- ============================================================================

do $$
declare
  v_avant   numeric;
  v_apres   numeric;
  v_faux    integer;
  v_total   integer;
begin
  select count(*) filter (
           where coalesce(solde_restant, 0) <>
                 greatest(coalesce(montant_total_du, 0)
                          - coalesce(montant_deja_paye, 0), 0)
         ),
         count(*)
    into v_faux, v_total
    from public.entreprises;

  select coalesce(sum(coalesce(solde_restant, 0)), 0) into v_avant
    from public.entreprises;

  -- L'UPDATE déclenche le trigger : chaque solde est recalculé.
  update public.entreprises
     set solde_restant = greatest(
                           coalesce(montant_total_du, 0)
                           - coalesce(montant_deja_paye, 0),
                           0
                         )
   where coalesce(solde_restant, 0) <>
         greatest(coalesce(montant_total_du, 0)
                  - coalesce(montant_deja_paye, 0), 0);

  select coalesce(sum(coalesce(solde_restant, 0)), 0) into v_apres
    from public.entreprises;

  raise notice
    '129 — % solde(s) incohérent(s) sur % dossier(s). Somme des soldes : % → %.',
    v_faux, v_total, v_avant, v_apres;

  if v_faux = 0 then
    raise notice '129 — tous les soldes étaient déjà cohérents.';
  end if;
end $$;


-- ============================================================================
--  3. CONTRÔLES
-- ============================================================================

-- V1. Le trigger est-il en place ? (attendu : 1 ligne)
select event_object_table as table_cible,
       trigger_name,
       action_timing,
       event_manipulation
  from information_schema.triggers
 where trigger_schema = 'public'
   and trigger_name = 'trg_entreprises_solde_restant';

-- V2. Cohérence : combien de dossiers ont encore un solde faux ?
--     (attendu : 0)
select count(*) as soldes_incoherents
  from public.entreprises
 where coalesce(solde_restant, 0) <>
       greatest(coalesce(montant_total_du, 0)
                - coalesce(montant_deja_paye, 0), 0);

-- V3. Le prochain cycle et l'état réel de chaque dossier.
select e.nom,
       e.statut::text                as statut,
       public.abonnement_collaborateurs_actifs(e.id)     as collaborateurs,
       public.rpc_abonnement_prix_du_cycle(e.id)         as prix_base,
       public.abonnement_supplement_collaborateurs(e.id) as supplement,
       public.rpc_abonnement_prix_du_cycle(e.id)
         + public.abonnement_supplement_collaborateurs(e.id) as prochain_cycle,
       e.montant_total_du,
       e.montant_deja_paye,
       e.solde_restant,
       e.date_expiration
  from public.entreprises e
 order by e.created_at desc
 limit 20;

-- Lecture attendue après cette migration :
--   • statut ACTIF et solde_restant = 0  → dossier réglé, rien à demander ;
--   • statut EXPIRE avec solde 0         → le prochain cycle est à vendre
--                                          (prix ci-dessus) ;
--   • statut EXPIRE / ESSAI_7J avec solde > 0 → un règlement est en attente.

-- V4. QUI EST COMPTÉ COMME COLLABORATEUR ? (contrôle du supplément)
--     Utile pour repérer un compte de test ou un ancien compte qui ferait
--     facturer 2 500 CDF de trop. Comparaison en texte : `utilisateurs` est
--     une table historique.
select e.nom                                  as entreprise,
       u.email,
       u.new_role::text                       as role_metier,
       u.role::text                           as role_herite,
       u.valide,
       case
         when exists (select 1 from public.entreprises x
                       where x.id::text = u.id::text)
           then 'PATRON (non facturé)'
         when coalesce(upper(btrim(u.new_role::text)), '') in (
                'PROPRIETAIRE', 'SUPER_ADMIN', 'GESTIONNAIRE_COMPTES',
                'FINANCE_LAPERLE', 'SUPPORT', 'AGENT_TERRAIN')
           then 'PLATEFORME (non facturé)'
         else 'FACTURÉ  '
       end                                    as traitement
  from public.utilisateurs u
  join public.entreprises e on e.id::text = u.entreprise_id::text
 where coalesce(u.valide, 1) <> 0
 order by e.nom, u.email
 limit 80;
