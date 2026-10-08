-- ============================================================================
--  biashara_yangu — CORRECTIF 61 : NE PLUS JAMAIS REFACTURER L'INSTALLATION
--  Migration 20260916000061_renouvellement_prix_mensuel.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  CE QUE LE RAPPORT DU CORRECTIF 60 A RÉVÉLÉ
--  ------------------------------------------
--     • Boutique Jean-Luc Takalashi : grille à 23 000 → prochain cycle
--       correctement facturé 23 000 ✅ (le mécanisme marche) ;
--     • Biashara Group : AUCUN prix (installation null, mensuel null,
--       grille à 0) → le moteur est retombé sur sa dernière solution de
--       repli, le montant du cycle précédent (30 000) → LE PIÈGE EST INTACT.
--
--  Pourquoi : le correctif 60 ne pouvait copier qu'un prix EXISTANT quelque
--  part. Or la grille de ce compte est vide (décision du patron : le prix est
--  NÉGOCIÉ entreprise par entreprise, pas fixé par pack).
--
--  LA DÉCISION COMMERCIALE (patron)
--  --------------------------------
--     • le prix mensuel est NÉGOCIÉ avec chaque entreprise et MODIFIABLE ;
--     • la grille tarifaire n'est donc pas renseignée : c'est normal ;
--     • en revanche, un renouvellement qui rejoue le prix d'installation
--       (le premier mois) est INACCEPTABLE : il faut refuser, pas deviner.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--    1. RENSEIGNE le prix d'installation des comptes déjà activés dont il
--       est encore inconnu — sans quoi le moteur ne peut PAS reconnaître le
--       piège. On prend le montant du dernier cycle CONCLU, à condition qu'il
--       dépasse l'abonnement de la grille (donc qu'il contenait autre chose
--       que le mois : l'installation). C'est le cas de Biashara Group :
--       30 000 > 0 → installation = 30 000.
--
--    2. DURCIT le moteur sur les RENOUVELLEMENTS uniquement :
--         • il ne rejoue JAMAIS un montant égal au prix d'installation ;
--         • s'il ne reste aucune source de prix, il REFUSE avec un message
--           clair au lieu de facturer le premier mois une seconde fois ;
--         • il APPREND : le montant négocié d'un renouvellement devient le
--           prix mensuel de l'entreprise (modifiable ensuite).
--
--  ⚠️ L'APPLICATION PUBLIÉE CONTINUE DE FONCTIONNER
--  ------------------------------------------------
--  L'écran Finance déjà publié négocie le montant du cycle
--  (`rpc_activation_definir_montant_total`). Donc, concrètement, pour
--  Biashara Group : l'opérateur saisit le prix négocié (5 000 ou 10 000) →
--  ce montant DIFFÈRE de l'installation (30 000) → le renouvellement passe
--  normalement ET le prix mensuel est retenu pour la suite.
--  Aucune saisie SQL n'est nécessaire : le geste habituel suffit.
--
--  Le PREMIER cycle n'est pas concerné : sa chaîne de prix reste inchangée.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 60.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE PRIX D'INSTALLATION MANQUANT (sans lui, impossible de détecter le piège)
-- ============================================================================
--  Règle : pour un compte DÉJÀ ACTIVÉ dont le cycle est soldé, le montant du
--  dernier cycle était le prix d'installation SI ET SEULEMENT SI il dépasse
--  l'abonnement de la grille (sinon ce n'était que le mois). On ne touche à
--  rien quand la valeur est déjà connue (ex. Jean-Luc Takalashi : 63 000).

update public.entreprises e
   set prix_installation = e.montant_total_du
 where e.prix_installation is null
   and e.date_activation is not null
   and coalesce(e.montant_total_du, 0) > 0
   and coalesce(e.montant_deja_paye, 0) >= coalesce(e.montant_total_du, 0)
   and coalesce(e.montant_total_du, 0)
       > coalesce((select g.montant_abonnement
                     from public.groupes_tarifaires g
                    where g.id = e.groupe_tarifaire_id), 0);


-- ============================================================================
--  2. LE MOTEUR — RENOUVELLEMENT SÛR
-- ============================================================================
--  Réécriture complète (base : correctif 60). Seule la branche
--  « renouvellement » change, plus deux écritures d'apprentissage. Tout le
--  reste — garde d'accès, statuts, prolongation, historique, audit — est
--  repris à l'identique.

create or replace function public.rpc_abonnement_enregistrer_paiement(
  p_entreprise_id uuid,
  p_montant       numeric,
  p_type_paiement text default 'AVANCE',
  p_mode_paiement text default null,
  p_note          text default null
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise    public.entreprises;
  v_type          text;
  v_duree         integer := 0;
  v_paye          numeric;
  v_total         numeric;
  v_solde         numeric;
  v_statut_avant  text;
  v_nouveau_paye  numeric;
  v_nouveau_solde numeric;
  v_prolongation  integer := 0;
  v_base          timestamptz;
  v_activer       boolean := false;
  v_abo_grille    numeric := 0;
  v_ouv_grille    numeric := 0;
  v_premier_cycle boolean := false;
  v_inst_ecrire   numeric;
  v_mens_ecrire   numeric;
begin
  -- Réservé aux administrateurs (inchangé, migration 23).
  if not exists (
    select 1 from public.utilisateurs u
    where u.id = auth.uid() and u.role = 'admin'
  ) then
    raise exception 'ACCES_REFUSE';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE';
  end if;

  v_type := upper(btrim(coalesce(p_type_paiement, 'AVANCE')));
  if v_type not in ('AVANCE', 'SOLDE', 'RENOUVELLEMENT') then
    raise exception 'TYPE_PAIEMENT_INVALIDE';
  end if;

  select * into v_entreprise
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_statut_avant := v_entreprise.statut::text;

  -- Durée d'abonnement de la grille tarifaire (30 jours par défaut).
  select coalesce(g.duree_abonnement_jours, 30)
    into v_duree
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_duree := coalesce(v_duree, 30);

  -- Les deux prix de la grille, pour les replis.
  select coalesce(g.montant_abonnement, 0),
         coalesce(g.frais_ouverture, 0)
    into v_abo_grille, v_ouv_grille
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_abo_grille := coalesce(v_abo_grille, 0);
  v_ouv_grille := coalesce(v_ouv_grille, 0);

  v_paye  := coalesce(v_entreprise.montant_deja_paye, 0);
  v_total := coalesce(v_entreprise.montant_total_du, 0);
  v_solde := coalesce(v_entreprise.solde_restant, greatest(v_total - v_paye, 0));

  -- Ouverture d'un nouveau cycle de facturation si :
  --   - le cycle courant est soldé (renouvellement), ou
  --   - l'abonnement est échu.
  --   Correctif 53 : « EN_ATTENTE_COMPLEMENT » n'ouvre PAS un nouveau cycle.
  if v_solde <= 0 or v_statut_avant = 'EXPIRE' then

    v_premier_cycle := (v_entreprise.date_activation is null);

    if v_premier_cycle then
      -- ══ PREMIER CYCLE — PRIX D'INSTALLATION (le mois 1 est inclus) ══════
      --  Ordre de résolution inchangé depuis le 60 :
      --    1. prix propre à l'entreprise ; 2. montant négocié déjà porté
      --    (l'écran Finance publié) ; 3. grille du pack.
      v_total := coalesce(
        nullif(v_entreprise.prix_installation, 0),
        nullif(v_total, 0),
        nullif(v_ouv_grille + v_abo_grille, 0),
        nullif(v_abo_grille, 0),
        0
      );

      if v_total <= 0 then
        raise exception 'MONTANT_TOTAL_INCONNU';
      end if;

      --  APPRENTISSAGE : on retient le prix d'installation réellement
      --  appliqué. Sans cette trace, il serait impossible, plus tard, de
      --  distinguer « le montant du mois » de « l'installation + le mois ».
      v_inst_ecrire := v_total;

    else
      -- ══ RENOUVELLEMENT — PRIX MENSUEL SEUL (correctif 61) ═══════════════
      --  Le prix d'installation NE DOIT JAMAIS être rejoué : il contient
      --  déjà le premier mois. C'est ce repli qui refacturait 30 000 CDF à
      --  Biashara Group.
      v_total := coalesce(
        nullif(v_entreprise.prix_abonnement_mensuel, 0),
        nullif(v_abo_grille, 0),
        --  Dernière solution : le montant du cycle précédent — SAUF s'il
        --  s'agit encore du prix d'installation.
        case
          when v_entreprise.prix_installation is not null
               and v_total = v_entreprise.prix_installation
            then null
          else nullif(v_total, 0)
        end,
        0
      );

      if v_total <= 0 then
        raise exception
          'PRIX_MENSUEL_ABSENT|Aucun prix mensuel n''est defini pour cette entreprise. Saisissez le montant negocie du mois : le prix d''installation ne peut pas etre reclame une seconde fois.';
      end if;

      --  APPRENTISSAGE : le montant negocie d'un renouvellement devient le
      --  prix mensuel de l'entreprise — modifiable ensuite. C'est exactement
      --  le modele voulu : « le prix discute avec l'entreprise ».
      v_mens_ecrire := v_total;
    end if;

    v_paye  := 0;
    v_solde := v_total;
  end if;

  if p_montant > v_solde + 0.001 then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  v_nouveau_paye  := v_paye + p_montant;
  v_nouveau_solde := greatest(v_solde - p_montant, 0);

  -- Cycle intégralement réglé : activation.
  --  Un compte SUSPENDU n'est jamais réactivé par un paiement.
  if v_nouveau_solde <= 0 and v_statut_avant <> 'SUSPENDU' then
    v_activer := true;
    v_prolongation := v_duree;

    -- Renouvellement anticipé : on repart de la date d'expiration si elle est
    -- encore future pour ne perdre aucun jour payé ; sinon de maintenant.
    if v_statut_avant = 'ACTIF'
       and v_entreprise.date_expiration is not null
       and v_entreprise.date_expiration > now() then
      v_base := v_entreprise.date_expiration;
    else
      v_base := now();
    end if;
  end if;

  update public.entreprises
     set montant_total_du   = v_total,
         montant_deja_paye  = v_nouveau_paye,
         --  Les deux prix appris (NULL = on ne touche pas à l'existant).
         prix_installation       = coalesce(v_inst_ecrire, prix_installation),
         prix_abonnement_mensuel = coalesce(v_mens_ecrire, prix_abonnement_mensuel),
         -- `solde_restant` est GÉNÉRÉ (total − payé) : jamais écrit ici.
         statut             = case
                                when v_activer then 'ACTIF'::public.statut_abonnement_enum
                                when v_statut_avant = 'EXPIRE'
                                  then 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum
                                else v_entreprise.statut
                              end,
         date_activation    = case
                                when v_activer
                                  then coalesce(v_entreprise.date_activation, now())
                                else v_entreprise.date_activation
                              end,
         date_expiration    = case
                                when v_activer
                                  then v_base + make_interval(days => v_duree)
                                else v_entreprise.date_expiration
                              end,
         updated_at         = now()
   where id = p_entreprise_id
   returning * into v_entreprise;

  -- Historique Module 3 (table dédiée, séparée de paiements_abonnement).
  insert into public.paiements_abonnements_laperle (
    id, entreprise_id, montant, type_paiement, mode_paiement,
    note, total_apres, solde_apres, prolongation_jours,
    enregistre_par, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    p_montant,
    v_type,
    nullif(btrim(p_mode_paiement), ''),
    nullif(btrim(p_note), ''),
    v_entreprise.montant_deja_paye,
    v_entreprise.solde_restant,
    v_prolongation,
    auth.uid(),
    now()
  );

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    p_entreprise_id,
    'PAIEMENT_ENREGISTRE',
    auth.uid(),
    jsonb_build_object(
      'montant', p_montant,
      'type_paiement', v_type,
      'mode_paiement', nullif(btrim(p_mode_paiement), ''),
      'statut_avant', v_statut_avant,
      'statut_apres', v_entreprise.statut::text,
      'solde_apres', v_entreprise.solde_restant,
      'prolongation_jours', v_prolongation,
      'premier_cycle', v_premier_cycle,
      'montant_du_cycle', v_total,
      'installation_apprise', v_inst_ecrire,
      'mensuel_appris', v_mens_ecrire,
      'correctif', '61'
    ),
    now()
  );

  return v_entreprise;
end;
$$;

comment on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) is
  'Moteur d''abonnement. Correctif 60 : premier cycle = prix d''installation (mois inclus), suivants = prix mensuel. Correctif 61 : un renouvellement ne rejoue JAMAIS le prix d''installation et apprend le prix mensuel négocié.';

revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from public;
revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from anon;
grant execute on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) to authenticated;


-- ============================================================================
--  3. CONTRÔLE
-- ============================================================================

do $verif_renouvellement$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_abonnement_enregistrer_paiement'
   limit 1;

  if v_def is null then
    raise exception 'Correctif 61 : moteur d''abonnement introuvable.';
  end if;

  if position('PRIX_MENSUEL_ABSENT' in v_def) = 0 then
    raise exception 'Correctif 61 : le refus explicite n''est pas en place.';
  end if;

  if position('v_mens_ecrire' in v_def) = 0
     or position('v_inst_ecrire' in v_def) = 0 then
    raise exception 'Correctif 61 : l''apprentissage des prix n''est pas en place.';
  end if;

  if position('v_premier_cycle := (v_entreprise.date_activation is null)' in v_def) = 0 then
    raise exception 'Correctif 61 : le correctif 60 a ete perdu — ne poursuivez pas.';
  end if;

  if position('v_statut_avant = ''EXPIRE'' then' in v_def) = 0 then
    raise exception 'Correctif 61 : le correctif 53 (complement) a ete perdu — ne poursuivez pas.';
  end if;

  raise notice 'Correctif 61 : renouvellement sur.';
end $verif_renouvellement$;


-- ============================================================================
--  RAPPORT FINAL — verdict entreprise par entreprise
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select e.nom                             as entreprise,
       e.statut::text                    as statut,
       case when e.date_activation is null
            then '1. premier cycle' else '2. renouvellement' end as prochain_cycle,
       e.prix_installation               as installation,
       e.prix_abonnement_mensuel         as prix_mensuel,
       coalesce(g.montant_abonnement, 0) as grille,
       e.montant_total_du                as total_du_actuel,
       case
         when e.date_activation is null
           then coalesce(nullif(e.prix_installation, 0),
                         nullif(e.montant_total_du, 0),
                         nullif(coalesce(g.frais_ouverture, 0)
                                + coalesce(g.montant_abonnement, 0), 0),
                         nullif(g.montant_abonnement, 0), 0)
         else coalesce(nullif(e.prix_abonnement_mensuel, 0),
                       nullif(g.montant_abonnement, 0),
                       case when e.prix_installation is not null
                             and coalesce(e.montant_total_du, 0) = e.prix_installation
                            then 0
                            else nullif(e.montant_total_du, 0) end,
                       0)
       end                               as prochain_montant_du,
       case
         when e.date_activation is null
           then 'installation (1er cycle)'
         when coalesce(e.prix_abonnement_mensuel, 0) > 0
              or coalesce(g.montant_abonnement, 0) > 0
           then 'OK — prix mensuel connu'
         when coalesce(e.montant_total_du, 0) > 0
              and (e.prix_installation is null
                   or e.montant_total_du is distinct from e.prix_installation)
           then 'OK — repli sur le dernier montant negocie'
         else '⛔ A FIXER — saisir le prix mensuel negocie'
       end                               as verdict
  from public.entreprises e
  left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
 order by e.nom;


-- ============================================================================
--  NOTE — CE QU'IL FAUT FAIRE POUR BIASHARA GROUP
--  ------------------------------------------------------------------------
--  Rien en SQL : au prochain renouvellement, dans la fenêtre
--  « Valider le paiement » de l'application (écran Finance), saisissez le
--  montant NÉGOCIÉ du mois (5 000, 10 000…).
--
--    • ce montant diffère de l'installation (30 000) → le renouvellement est
--      accepté ;
--    • il est retenu comme prix mensuel de l'entreprise (voir la colonne
--      `prix_mensuel` du rapport, qui se remplira) ;
--    • les renouvellements suivants n'auront plus rien à saisir.
--
--  Pour fixer (ou corriger) les prix à la main, à tout moment :
--
--    select public.rpc_abonnement_definir_prix(
--             '<uuid-de-l-entreprise>'::uuid,
--             null,      -- installation : inchangée
--             5000       -- prix mensuel négocié
--           );
-- ============================================================================
