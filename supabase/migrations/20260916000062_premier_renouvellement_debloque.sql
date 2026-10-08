-- ============================================================================
--  biashara_yangu — CORRECTIF 62 : LE PREMIER RENOUVELLEMENT SE DÉBLOQUE SEUL
--  Migration 20260916000062_premier_renouvellement_debloque.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  LE RAPPORT DU CORRECTIF 61
--  --------------------------
--     • Biashara Group : installation désormais CONNUE (30 000) ✅ ; le
--       piège est fermé (prochain montant = 0 au lieu de 30 000) ✅ ;
--       verdict « ⛔ À FIXER — saisir le prix mensuel négocié » ;
--     • Boutique Jean-Luc Takalashi : 23 000 ✅.
--
--  LE PROBLÈME QUE CE VERDICT A MIS AU JOUR
--  ----------------------------------------
--  Trois écrans de l'application encaissent un abonnement :
--     • « Valider le paiement » (écran Finance) — il FIXE le montant dû avant
--       d'encaisser ✅ le renouvellement passe, et le prix mensuel est appris ;
--     • « Enregistrer un paiement » (Module 3) — il encaisse DIRECTEMENT,
--       sans fixer le montant ;
--     • « Encaisser un paiement » (fiche entreprise) — idem.
--
--  Sur ces deux derniers, un compte « À FIXER » ne pouvait PAS renouveler :
--  le moteur ne trouvait aucun prix et refusait. Il fallait donc passer par
--  du SQL pour la PREMIÈRE fois, puis plus jamais.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--  Elle ajoute une QUATRIÈME source de prix, utilisée seulement quand toutes
--  les autres sont vides :
--
--     LE MONTANT QUE L'OPÉRATEUR VIENT D'ENREGISTRER.
--
--  C'est exactement le prix négocié du mois : le commerçant a payé cette
--  somme, elle devient le prix mensuel de l'entreprise (colonne
--  `prix_abonnement_mensuel`), donc les renouvellements suivants n'ont plus
--  rien à saisir. Le modele reste « prix discuté avec l'entreprise,
--  modifiable ».
--
--  ⚠️ LE GARDE-FOU EST INTACT : si la somme saisie est EXACTEMENT le prix
--  d'installation (le premier mois déjà payé), le moteur REFUSE toujours, avec
--  le même message clair. Un encaissement ne peut donc pas refacturer
--  l'installation, même saisi à la main.
--
--  Ordre de résolution au RENOUVELLEMENT (inchangé pour le reste) :
--     1. prix mensuel de l'entreprise (modifiable) ;
--     2. abonnement de la grille du pack ;
--     3. montant du cycle précédent — jamais s'il égale l'installation ;
--     4. ⬅ NOUVEAU : le montant encaissé — jamais s'il égale l'installation.
--
--  Le PREMIER cycle n'est pas concerné (chaîne de prix inchangée).
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 61.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  LE MOTEUR — QUATRIÈME SOURCE DE PRIX AU RENOUVELLEMENT
-- ============================================================================
--  Réécriture complète (base : correctif 61). Une seule branche change :
--  le calcul du prix au renouvellement. Tout le reste — garde d'accès,
--  statuts, prolongation, historique, audit, apprentissage — est repris à
--  l'identique.

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
      --  appliqué, pour pouvoir, plus tard, refuser de le réclamer à nouveau.
      v_inst_ecrire := v_total;

    else
      -- ══ RENOUVELLEMENT — PRIX MENSUEL SEUL ══════════════════════════════
      --  Le prix d'installation (premier mois inclus) NE DOIT JAMAIS être
      --  rejoué. Les trois premiers replis sont ceux du correctif 61.
      v_total := coalesce(
        --  1. le prix mensuel propre à l'entreprise (négocié, modifiable) ;
        nullif(v_entreprise.prix_abonnement_mensuel, 0),
        --  2. l'abonnement de la grille du pack ;
        nullif(v_abo_grille, 0),
        --  3. le montant du cycle précédent — sauf s'il s'agit encore du
        --     prix d'installation ;
        case
          when v_entreprise.prix_installation is not null
               and v_total = v_entreprise.prix_installation
            then null
          else nullif(v_total, 0)
        end,
        --  4. CORRECTIF 62 — LE MONTANT ENCAISSÉ. Quand aucun prix n'est
        --     encore connu, la somme que l'opérateur vient d'enregistrer EST
        --     le prix négocié du mois : elle est retenue ci-dessous comme
        --     prix mensuel de l'entreprise. C'est ce qui permet aux écrans
        --     « Enregistrer un paiement » et « Encaisser un paiement » de
        --     fonctionner dès le premier renouvellement, sans passer par SQL.
        case
          when v_entreprise.prix_installation is not null
               and p_montant = v_entreprise.prix_installation
            then null
          else p_montant
        end,
        0
      );

      if v_total <= 0 then
        raise exception
          'PRIX_MENSUEL_ABSENT|La somme saisie correspond exactement au prix d''installation (%, premier mois deja inclus) : elle ne peut pas etre reclamee une seconde fois. Saisissez le montant negocie du mois.',
          coalesce(v_entreprise.prix_installation, 0);
      end if;

      --  APPRENTISSAGE : le montant retenu devient le prix mensuel de
      --  l'entreprise — modifiable ensuite (rpc_abonnement_definir_prix).
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
      'correctif', '62'
    ),
    now()
  );

  return v_entreprise;
end;
$$;

comment on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) is
  'Moteur d''abonnement. Correctif 60 : premier cycle = prix d''installation (mois inclus), suivants = prix mensuel. 61 : un renouvellement ne rejoue jamais l''installation et apprend le prix mensuel. 62 : à défaut de tout prix connu, le montant encaissé fait foi (jamais s''il égale l''installation).';

revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from public;
revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from anon;
grant execute on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) to authenticated;


-- ============================================================================
--  CONTRÔLE
-- ============================================================================

do $verif_deblocage$
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
    raise exception 'Correctif 62 : moteur d''abonnement introuvable.';
  end if;

  if position('and p_montant = v_entreprise.prix_installation' in v_def) = 0 then
    raise exception 'Correctif 62 : la quatrieme source de prix n''est pas en place.';
  end if;

  if position('PRIX_MENSUEL_ABSENT' in v_def) = 0 then
    raise exception 'Correctif 62 : le refus explicite a ete perdu.';
  end if;

  if position('v_mens_ecrire' in v_def) = 0 then
    raise exception 'Correctif 62 : l''apprentissage du prix mensuel a ete perdu.';
  end if;

  if position('v_premier_cycle := (v_entreprise.date_activation is null)' in v_def) = 0
     or position('v_statut_avant = ''EXPIRE'' then' in v_def) = 0 then
    raise exception 'Correctif 62 : les correctifs 60 ou 53 ont ete perdus — ne poursuivez pas.';
  end if;

  raise notice 'Correctif 62 : le premier renouvellement se debloque seul.';
end $verif_deblocage$;


-- ============================================================================
--  RAPPORT FINAL
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
           then 'prix d''installation applique'
         when coalesce(e.prix_abonnement_mensuel, 0) > 0
           then 'OK — prix mensuel de l''entreprise'
         when coalesce(g.montant_abonnement, 0) > 0
           then 'OK — abonnement de la grille'
         when coalesce(e.montant_total_du, 0) > 0
              and (e.prix_installation is null
                   or e.montant_total_du is distinct from e.prix_installation)
           then 'OK — reprise du dernier montant'
         else 'OK — prix retenu au 1er encaissement (correctif 62)'
       end                               as verdict
  from public.entreprises e
  left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
 order by e.nom;


-- ============================================================================
--  NOTE — BIASHARA GROUP : PLUS RIEN À FAIRE
--  ------------------------------------------------------------------------
--  Au prochain renouvellement, quel que soit l'écran utilisé
--  (« Enregistrer un paiement », « Encaisser un paiement » ou « Valider le
--  paiement » de la Finance), saisissez le montant négocié du mois
--  (5 000, 10 000…) :
--
--    • le renouvellement est accepté : le montant encaissé fait foi ;
--    • il devient le prix mensuel de l'entreprise (colonne `prix_mensuel` du
--      rapport, qui se remplira) ;
--    • les renouvellements suivants n'ont plus STRICTEMENT RIEN à saisir.
--
--  Seul cas encore refusé, volontairement : une somme égale au prix
--  d'installation (30 000 ici) — ce serait refacturer le premier mois.
--
--  Corriger un prix à la main, à tout moment :
--
--    select public.rpc_abonnement_definir_prix(
--             '<uuid-de-l-entreprise>'::uuid,
--             null,      -- installation : inchangée
--             5000       -- prix mensuel négocié
--           );
-- ============================================================================
