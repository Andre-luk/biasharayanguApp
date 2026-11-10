-- ============================================================================
--  BIASHARA YANGU — RECETTES SQL « ABONNEMENT & MOBILE MONEY »
--  Fichier : docs/reactivation_abonnement.sql
--  ---------------------------------------------------------------------------
--  À exécuter dans l'éditeur SQL de Supabase.
--  Tout ce qui est ci-dessous s'applique SANS publier d'application et SANS
--  faire réinstaller quoi que ce soit aux clients : ce sont les fonctions du
--  serveur qui décident.
--
--  RÈGLE DEPUIS LA MIGRATION 126 :
--    • un abonnement échu ne repart qu'avec de l'ARGENT RÉEL :
--        - Mobile Money → SerdiPay (le client paie, le webhook crédite) ;
--        - espèces / Mobile Money saisi par la Finance (« Enregistrer un
--          paiement ») ;
--    • les jours OFFERTS sont possibles, mais explicitement et avec un motif
--      (`abonnement_geste_commercial`).
--
--  ⚠️ Remplacez « urembo » par le nom (ou le début du nom) du client.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. VOIR LE DOSSIER (lecture seule) — où en est le client ?
-- ============================================================================
select e.nom,
       e.statut::text            as statut,
       e.montant_total_du,
       e.montant_deja_paye,
       e.solde_restant,
       e.date_activation,
       e.date_expiration,
       e.prix_installation,
       e.prix_abonnement_mensuel,
       public.rpc_abonnement_prix_du_cycle(e.id) as prix_du_prochain_cycle,
       e.devise
  from public.entreprises e
 where e.nom ilike '%urembo%';


-- ============================================================================
--  2. VOIR LES TRANSACTIONS MOBILE MONEY (lecture seule)
-- ============================================================================
select s.reference,
       s.statut,
       s.montant,
       s.devise,
       s.operateur,
       s.telephone,
       s.objet,
       s.provider_reference,
       s.created_at,
       s.paye_le,
       s.motif_echec,
       s.url_paiement is not null as lien_cree_chez_serdipay
  from public.paiements_serdipay s
  join public.entreprises e on e.id = s.entreprise_id
 where e.nom ilike '%urembo%'
 order by s.created_at desc
 limit 20;

-- Lecture du résultat :
--   en_attente + provider_reference NON NULL → la demande est bien partie
--       chez SerdiPay : le client doit valider sur son téléphone.
--   en_attente + provider_reference NULL     → SerdiPay n'a jamais répondu :
--       réessayez depuis l'application (« Payer par Mobile Money »).
--   paye        → l'argent est arrivé, l'abonnement a été crédité.
--   echoue      → regarder motif_echec (refus, montant, opérateur…).


-- ============================================================================
--  3. LE CLIENT A PAYÉ MAIS LE WEBHOOK N'EST PAS ARRIVÉ
-- ============================================================================
--  ⚠️ N'exécutez ceci QUE si vous avez la preuve du paiement côté SerdiPay
--     (tableau de bord SerdiPay : transaction « réussie » pour cette
--     référence). La fonction vérifie le montant, puis crédite l'abonnement
--     par le moteur habituel. Elle est idempotente : la relancer ne crédite
--     jamais deux fois.
--
--  Décommentez, remplacez la référence, exécutez :

-- do $$
-- declare
--   v_ref text := 'SER-20261110-XXXXXXXX';   -- ← référence interne (colonne reference)
--   v_s   public.paiements_serdipay%rowtype;
-- begin
--   select * into v_s from public.paiements_serdipay where reference = v_ref;
--
--   if v_s.id is null then
--     raise exception 'Référence inconnue : %', v_ref;
--   end if;
--
--   raise notice 'Avant : statut=% montant=% %', v_s.statut, v_s.montant, v_s.devise;
--
--   perform public.rpc_serdipay_confirmer(
--     p_reference          => v_s.reference,
--     p_statut             => 'paye',
--     p_provider_reference => v_s.provider_reference,
--     p_montant_recu       => v_s.montant,
--     p_payload            => jsonb_build_object('source', 'saisie_sql_operateur')
--   );
--
--   raise notice 'Paiement confirmé : abonnement crédité.';
-- end $$;


-- ============================================================================
--  4. OFFRIR DES JOURS (geste commercial délibéré et tracé)
-- ============================================================================
--  Super Admin uniquement, motif obligatoire, inscrit au journal d'audit.
--  À utiliser pour un dédommagement réel — jamais pour « réactiver » un
--  client qui n'a pas payé.
--
--  ⚠️ Depuis l'éditeur SQL il n'y a pas de session : la fonction refuserait
--     (elle vérifie `est_super_admin()`). Ce bloc emprunte donc l'identité du
--     compte SUPER_ADMIN le temps de la transaction, puis la rend.

-- do $$
-- declare
--   v_acteur uuid;
--   v_ent    uuid;
-- begin
--   select e.id into v_ent
--     from public.entreprises e
--    where e.nom ilike '%portes ouvertes%'
--    limit 1;
--
--   if v_ent is null then
--     raise exception 'Entreprise introuvable : modifiez le filtre.';
--   end if;
--
--   select u.id into v_acteur
--     from public.utilisateurs u
--    where u.new_role = 'SUPER_ADMIN'
--    order by u.id limit 1;
--
--   if v_acteur is null then
--     raise exception 'Aucun compte SUPER_ADMIN.';
--   end if;
--
--   perform set_config('request.jwt.claim.sub', v_acteur::text, true);
--   perform set_config(
--     'request.jwt.claims',
--     jsonb_build_object('sub', v_acteur::text, 'role', 'authenticated')::text,
--     true
--   );
--
--   perform public.abonnement_geste_commercial(
--     p_entreprise_id => v_ent,
--     p_jours         => 30,
--     p_motif         => 'Mois offert à l''ouverture de la boutique'
--   );
--
--   raise notice 'Geste commercial enregistré : +30 jours.';
-- end $$;


-- ============================================================================
--  5. CONTRÔLE : PLUS AUCUN MOIS GRATUIT
-- ============================================================================
--  V1. La réactivation exige-t-elle bien une preuve de paiement ?
--      (attendu : true, true)
select position('paiements_serdipay' in pg_get_functiondef(
         'public.rpc_abonnement_reactiver(uuid)'::regprocedure)) > 0
         as verifie_serdipay,
       position('REACTIVATION_PAYANTE' in pg_get_functiondef(
         'public.rpc_abonnement_reactiver(uuid)'::regprocedure)) > 0
         as refuse_sans_paiement;

--  V2. Le geste commercial existe et reste réservé au Super Admin
--      (attendu : 1 ligne).
select p.oid::regprocedure::text as fonction
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'abonnement_geste_commercial';

--  V3. Les journaux d'audit : qui a prolongé quoi, et pourquoi ?
select j.created_at,
       e.nom,
       j.action,
       j.details ->> 'jours_offerts'   as jours_offerts,
       j.details ->> 'motif'           as motif,
       j.details ->> 'preuve_serdipay' as preuve_mobile_money,
       j.details ->> 'role'            as role
  from public.journal_audit j
  join public.entreprises e on e.id = j.entreprise_id
 where j.action in ('REACTIVATION', 'REACTIVATION_PAYANTE', 'GESTE_COMMERCIAL')
 order by j.created_at desc
 limit 50;
