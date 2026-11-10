-- ============================================================================
--  BIASHARA YANGU — VÉRIFIER QUE LES CORRECTIFS SONT BIEN INSTALLÉS
--  Fichier : docs/verifier_correctifs.sql
--  ---------------------------------------------------------------------------
--  À exécuter dans l'éditeur SQL de Supabase — LECTURE SEULE.
--
--  Une ligne par correctif, avec `installe` à true/false. Si une ligne est à
--  false, rejouez le fichier de migration correspondant (ils sont tous
--  idempotents) : le problème correspondant n'est PAS corrigé.
--
--  Aucune donnée n'est modifiée.
-- ============================================================================

with defs as (
  select p.proname,
         pg_get_function_identity_arguments(p.oid) as args,
         pg_get_functiondef(p.oid)                   as src
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
)
select '0124 — garde-fous Mobile Money tolérants aux types' as correctif,
       exists (
         select 1 from defs
          where proname = 'paiement_mm_exige_serdipay'
            and position('entreprise_id::text' in src) > 0
       ) as installe

union all

select '0125/0128 — colonne entreprise_id convertie en uuid',
       coalesce((
         select c.data_type = 'uuid'
           from information_schema.columns c
          where c.table_schema = 'public'
            and c.table_name = 'paiements_abonnements_laperle'
            and c.column_name = 'entreprise_id'
       ), false)

union all

select '0126 — réactivation payante + geste commercial',
       exists (select 1 from defs
                where proname = 'rpc_abonnement_reactiver'
                  and position('REACTIVATION_PAYANTE' in src) > 0)
       and exists (select 1 from defs
                    where proname = 'abonnement_geste_commercial')

union all

select '0127 — payer plusieurs mois sur un dossier échu',
       exists (select 1 from defs
                where proname = 'abonnement_ouvrir_avance_multi'
                  and position('EN_ATTENTE_COMPLEMENT' in src) > 0)

union all

select '0128 — prix/type de cycle tolérants + collaborateurs corrigés',
       exists (select 1 from defs
                where proname = 'rpc_abonnement_prix_du_cycle'
                  and position('entreprise_id::text' in src) > 0)
       and exists (select 1 from defs
                    where proname = 'rpc_abonnement_type_cycle'
                      and position('entreprise_id::text' in src) > 0)
       and exists (select 1 from defs
                    where proname = 'abonnement_collaborateurs_actifs'
                      and position('u.id::text' in src) > 0)

union all

select '0129 — solde_restant entretenu par trigger',
       exists (
         select 1 from information_schema.triggers t
          where t.trigger_schema = 'public'
            and t.trigger_name = 'trg_entreprises_solde_restant'
       )

union all

select '0130 — le webhook peut créditer (ancien rôle admin)',
       exists (select 1 from defs
                where proname = 'rpc_serdipay_confirmer'
                  and position('role::text' in src) > 0)

union all

select '0131 — créditer un paiement déjà encaissé',
       exists (select 1 from defs
                where proname = 'abonnement_crediter_paiement_serdipay')

order by correctif;


-- ---------------------------------------------------------------------------
--  BONUS : qui peut créditer un paiement SerdiPay ?
-- ---------------------------------------------------------------------------
--  Au moins une ligne `peut_crediter = true` est indispensable, sinon le
--  webhook échouera en ACCES_REFUSE (correctif 0130).

select u.email,
       u.new_role::text                              as role_metier,
       u.role::text                                  as ancien_role,
       lower(coalesce(u.role::text, '')) = 'admin'   as peut_crediter
  from public.utilisateurs u
 where lower(coalesce(u.role::text, '')) = 'admin'
    or coalesce(u.new_role::text, '') in ('FINANCE_LAPERLE', 'SUPER_ADMIN')
 order by peut_crediter desc, u.new_role, u.email;
