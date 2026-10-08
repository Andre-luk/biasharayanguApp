-- ============================================================================
--  biashara_yangu — AUDIT COMPLET DE L'ABONNEMENT
--  tools/audit_abonnement_complet.sql
-- ============================================================================
--
--  ⛔ LECTURE SEULE — ce script N'ÉCRIT RIEN. Aucune donnée n'est modifiée.
--
--  À QUOI IL SERT
--  --------------
--  Répondre à une seule question : « est-ce que tout est cohérent entre TOUS
--  les comptes ? » Il croise, pour chaque entreprise, son statut, son étape
--  d'activation, ses montants, ses dates, ses DEUX prix et son niveau
--  d'abonnement, puis signale les incohérences.
--
--  ⚠️ En SQL Editor, `auth.uid()` est vide : les fonctions qui dépendent de
--  la session ne sont pas utilisées ici — tout est lu depuis les tables.
--
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


with ent as (
  select e.id,
         e.nom,
         e.statut::text                               as statut,
         coalesce(e.activation_etape, '—')             as etape,
         e.montant_total_du,
         e.montant_deja_paye,
         e.solde_restant,
         e.date_activation,
         e.date_expiration,
         e.prix_installation,
         e.prix_abonnement_mensuel,
         e.niveau_abonnement,
         e.groupe_tarifaire_id,
         (select count(*) from public.utilisateurs u
           where u.entreprise_id = e.id)              as nb_comptes,
         (select count(*) from public.utilisateurs u
           where u.entreprise_id = e.id
             and public.mon_role(u.id) = 'PROPRIETAIRE') as nb_patrons
    from public.entreprises e
),

problemes as (
  -- ── Cohérence statut / échéance ─────────────────────────────────────────
  select '2. ANOMALIES' as bloc,
         '⛔'          as gravite,
         nom           as sujet,
         'ACTIF alors que l''abonnement est échu depuis le '
         || to_char(date_expiration, 'DD/MM/YYYY') as detail
    from ent
   where statut = 'ACTIF'
     and date_expiration is not null
     and date_expiration < now()

  union all

  select '2. ANOMALIES', '⛔', nom,
         'EXPIRE alors que l''échéance est future ('
         || to_char(date_expiration, 'DD/MM/YYYY') || ')'
    from ent
   where statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
     and date_expiration is not null
     and date_expiration > now()

  -- ── Cohérence des montants ─────────────────────────────────────────────
  union all

  select '2. ANOMALIES', '⛔', nom,
         'TROP-PERCU : paye ' || (montant_deja_paye)::text
         || ' pour un du de ' || (montant_total_du)::text
    from ent
   where coalesce(montant_deja_paye, 0) > coalesce(montant_total_du, 0) + 0.001

  union all

  select '2. ANOMALIES', '⛔', nom,
         'ACTIF avec un solde restant de ' || (solde_restant)::text
    from ent
   where statut = 'ACTIF'
     and coalesce(solde_restant, 0) > 0.001

  union all

  select '2. ANOMALIES', '⚠️', nom,
         'Montant du absent ou nul (l''activation a pu s''appuyer sur la grille)'
    from ent
   where coalesce(montant_total_du, 0) <= 0
     and statut <> 'SUSPENDU'

  union all

  select '2. ANOMALIES', '⚠️', nom,
         'date_activation VIDEO alors que le statut est ' || statut
    from ent
   where date_activation is null
     and statut in ('ACTIF', 'EXPIRE', 'EN_ATTENTE_COMPLEMENT')

  -- ── Les deux prix de l'abonnement ──────────────────────────────────────
  union all

  select '2. ANOMALIES', '⚠️', nom,
         'Aucun PRIX MENSUEL connu : le prochain renouvellement demandera une saisie'
    from ent
   where date_activation is not null
     and coalesce(prix_abonnement_mensuel, 0) <= 0
     and coalesce((select g.montant_abonnement
                     from public.groupes_tarifaires g
                    where g.id = groupe_tarifaire_id), 0) <= 0

  union all

  select '2. ANOMALIES', '⚠️', nom,
         'Prix d''installation inconnu (le moteur ne peut pas detecter une refacturation)'
    from ent
   where date_activation is not null
     and coalesce(prix_installation, 0) <= 0

  -- ── Rattachement des comptes ───────────────────────────────────────────
  union all

  select '2. ANOMALIES', '⛔', nom,
         'AUCUN compte utilisateur rattache a cette entreprise'
    from ent
   where nb_comptes = 0

  union all

  select '2. ANOMALIES', '⚠️', nom,
         'Aucun PROPRIETAIRE rattache (' || nb_comptes || ' compte(s) pourtant)'
    from ent
   where nb_comptes > 0 and nb_patrons = 0

  union all

  select '2. ANOMALIES', '⚠️', nom,
         nb_patrons || ' PROPRIETAIRES rattaches : verifiez qui commande'
    from ent
   where nb_patrons > 1

  -- ── Niveau d'abonnement ────────────────────────────────────────────────
  union all

  select '2. ANOMALIES', 'ℹ️', nom,
         'Aucun niveau d''abonnement : toutes les fonctionnalites restent visibles (fail-open)'
    from ent
   where coalesce(niveau_abonnement, '') = ''
     and groupe_tarifaire_id is null
)

select '0. RESUME' as bloc, 'ℹ️' as gravite, 'Entreprises' as sujet,
       count(*)::text || ' au total · ' as detail
  from public.entreprises

union all
select '0. RESUME', 'ℹ️', 'Comptes utilisateurs',
       count(*)::text from public.utilisateurs

union all
select '0. RESUME', 'ℹ️', 'Abonnements ACTIFS',
       count(*)::text from public.entreprises where statut = 'ACTIF'

union all
select '0. RESUME', 'ℹ️', 'Abonnements EXPIRE / en attente',
       count(*)::text from public.entreprises
        where statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')

union all
select '0. RESUME', 'ℹ️', 'Abonnements SUSPENDUS',
       count(*)::text from public.entreprises where statut = 'SUSPENDU'

union all
select '0. RESUME', 'ℹ️', 'Encaisse total (CDF)',
       coalesce(sum(montant_deja_paye), 0)::text from public.entreprises

union all
select '0. RESUME', 'ℹ️', 'Solde restant total (CDF)',
       coalesce(sum(solde_restant), 0)::text from public.entreprises

union all
select '0. RESUME', 'ℹ️', 'Niveaux d''abonnement au catalogue',
       count(*)::text from public.niveaux_abonnement

-- ── Les comptes utilisateurs orphelins ────────────────────────────────────
union all

select '3. COMPTES SANS ENTREPRISE', '⚠️',
       coalesce(nullif(btrim(u.nom), ''), u.email, u.id::text),
       'role ' || public.mon_role(u.id)
       || ' · entreprise_id '
       || coalesce(left(u.entreprise_id::text, 8), 'VIDE')
       || case when u.parent_id is null then '' else ' · rattache a ' || left(u.parent_id::text, 8) end
  from public.utilisateurs u
 where u.entreprise_id is null

order by 1, 3, 4;
