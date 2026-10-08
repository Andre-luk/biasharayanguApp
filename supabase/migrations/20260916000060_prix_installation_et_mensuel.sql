-- ============================================================================
--  biashara_yangu — CORRECTIF 60 : DEUX PRIX PAR ENTREPRISE
--  Migration 20260916000060_prix_installation_et_mensuel.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  LE PROBLÈME
--  -----------
--  Aujourd'hui chaque entreprise ne porte qu'UN SEUL montant d'abonnement
--  (`entreprises.montant_total_du`), qui sert à la fois :
--     • de « frais d'installation + premier mois » à l'ouverture du compte ;
--     • de prix du cycle suivant au renouvellement.
--
--  Or le montant négocié porté par l'entreprise PRIME sur la grille tarifaire
--  (correctif 43). Conséquence : un client qui a payé 30 000 CDF
--  d'installation (premier mois INCLUS) se voit réclamer 30 000 CDF À NOUVEAU
--  au renouvellement, alors que seul le mois suivant est dû.
--
--  LA RÈGLE MÉTIER VOULUE
--  ----------------------
--     • PREMIER cycle  : PRIX D'INSTALLATION — il comprend déjà le premier
--       mois d'abonnement. Exemple : 30 000 CDF payés = installation + mois 1.
--     • Cycles SUIVANTS : PRIX MENSUEL seul. Exemple : 5 000 ou 10 000 CDF,
--       selon ce qui a été convenu avec l'entreprise.
--     • Chaque entreprise a SES deux prix (négociés), pré-remplis depuis la
--       grille tarifaire de son pack et modifiables entreprise par entreprise.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--    1. ajoute deux colonnes à `entreprises` :
--         • `prix_installation`       — le prix du 1er cycle (mois inclus) ;
--         • `prix_abonnement_mensuel` — le prix des cycles suivants ;
--    2. les PRÉ-REMPLIT : installation = le montant déjà négocié (ou
--       frais d'ouverture + abonnement de la grille), mensuel = l'abonnement
--       de la grille du pack ;
--    3. réécrit le MOTEUR d'abonnement (`rpc_abonnement_enregistrer_paiement`)
--       pour qu'il applique le bon prix selon le cycle ;
--    4. garde `rpc_activation_definir_montant_total` COHÉRENTE : l'écran
--       Finance DÉJÀ PUBLIÉ continue de négocier le prix du 1er cycle, et
--       cette valeur alimente désormais aussi `prix_installation` ;
--    5. ajoute `rpc_abonnement_definir_prix` (les deux prix d'un coup), pour
--       le futur écran d'administration.
--
--  ⚠️ COMPATIBILITÉ AVEC L'APPLICATION PUBLIÉE
--  -------------------------------------------
--  `montant_total_du` GARDE EXACTEMENT SON RÔLE : c'est le dû du CYCLE EN
--  COURS (le moteur le réécrit à chaque nouveau cycle). L'application publiée
--  continue donc d'afficher « Montant total dû / déjà payé / solde restant »
--  sans le moindre changement — mais avec le BON montant : installation au
--  1er cycle, mensuel ensuite. Les deux nouvelles colonnes lui sont invisibles.
--
--  ⚠️ À VÉRIFIER APRÈS EXÉCUTION : le rapport final affiche, pour CHAQUE
--  entreprise, le montant qui sera réclamé au prochain cycle. Si le prix
--  mensuel d'une entreprise n'est pas le bon, corrigez-le (voir la note de
--  fin de fichier) : la grille tarifaire peut encore porter l'ancien montant
--  « installation incluse ».
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LES DEUX COLONNES
-- ============================================================================

alter table public.entreprises
  add column if not exists prix_installation       numeric,
  add column if not exists prix_abonnement_mensuel numeric;

comment on column public.entreprises.prix_installation is
  'Prix d''installation du compte : il COMPREND le premier mois d''abonnement. Appliqué au premier cycle uniquement. NULL = utiliser le montant négocié puis la grille. Correctif 60.';

comment on column public.entreprises.prix_abonnement_mensuel is
  'Prix d''un mois d''abonnement, appliqué À PARTIR DU DEUXIÈME cycle (renouvellements). NULL = utiliser l''abonnement de la grille du pack. Correctif 60.';


-- ============================================================================
--  2. PRÉ-REMPLISSAGE
-- ============================================================================
--  Aucun montant n'est inventé : on reprend ceux qui existent déjà.

--  2.a Prix MENSUEL : l'abonnement de la grille du pack de l'entreprise.
update public.entreprises e
   set prix_abonnement_mensuel = nullif(g.montant_abonnement, 0)
  from public.groupes_tarifaires g
 where g.id = e.groupe_tarifaire_id
   and e.prix_abonnement_mensuel is null
   and coalesce(g.montant_abonnement, 0) > 0;

--  2.b Prix d'INSTALLATION des comptes JAMAIS ACTIVÉS (= encore au 1er cycle) :
--      le montant déjà négocié s'il existe — c'est celui que la Finance a
--      fixé —, sinon frais d'ouverture + abonnement de la grille.
update public.entreprises e
   set prix_installation = coalesce(
         nullif(e.montant_total_du, 0),
         (select nullif(coalesce(g.frais_ouverture, 0)
                        + coalesce(g.montant_abonnement, 0), 0)
            from public.groupes_tarifaires g
           where g.id = e.groupe_tarifaire_id)
       )
 where e.prix_installation is null
   and e.date_activation is null;

--  2.c Prix d'INSTALLATION des comptes DÉJÀ ACTIVÉS : ils ne repasseront
--      jamais par le premier cycle ; on renseigne la référence de la grille,
--      à titre indicatif.
update public.entreprises e
   set prix_installation = (
         select nullif(coalesce(g.frais_ouverture, 0)
                       + coalesce(g.montant_abonnement, 0), 0)
           from public.groupes_tarifaires g
          where g.id = e.groupe_tarifaire_id)
 where e.prix_installation is null
   and e.date_activation is not null;


-- ============================================================================
--  3. LE MOTEUR D'ABONNEMENT
-- ============================================================================
--  Réécriture COMPLÈTE de la version live (= migration 23, patchée par les
--  correctifs 43 pour le montant négocié et 53 pour le complément). Deux
--  modifications seulement, signalées « CORRECTIF 60 » :
--     • la condition de nouveau cycle (inchangée depuis le 53) ;
--     • le calcul du montant dû, remplacé par la règle des deux prix.
--  Tout le reste est repris à l'identique — y compris la garde d'accès, les
--  statuts, la prolongation, l'historique et le journal d'audit.

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

  -- CORRECTIF 60 : les deux prix de la grille, pour les replis.
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
  --   Correctif 53 : « EN_ATTENTE_COMPLEMENT » n'ouvre PAS un nouveau cycle —
  --   c'est le MÊME cycle, les versements s'additionnent.
  if v_solde <= 0 or v_statut_avant = 'EXPIRE' then

    -- ══ CORRECTIF 60 — LE BON PRIX SELON LE CYCLE ═════════════════════════
    --  • PREMIER cycle (compte jamais activé, donc `date_activation` vide) :
    --    le PRIX D'INSTALLATION. Il comprend DÉJÀ le premier mois — c'est
    --    pourquoi il ne doit plus être réclamé au renouvellement.
    --  • Cycles SUIVANTS : le PRIX MENSUEL seul.
    --
    --  Ordre de résolution, du plus précis au plus général :
    --    1. prix propre à l'entreprise (colonnes du correctif 60) ;
    --    2. montant négocié déjà porté par l'entreprise (montant_total_du) ;
    --    3. grille tarifaire du pack.
    --  Le repli n° 2 est ce qui préserve l'écran Finance DÉJÀ PUBLIÉ : il
    --  négocie le montant du premier cycle via
    --  `rpc_activation_definir_montant_total`, qui alimente aussi
    --  `prix_installation` (voir section 4).
    v_premier_cycle := (v_entreprise.date_activation is null);

    if v_premier_cycle then
      v_total := coalesce(
        nullif(v_entreprise.prix_installation, 0),
        nullif(v_total, 0),
        nullif(v_ouv_grille + v_abo_grille, 0),
        nullif(v_abo_grille, 0),
        0
      );
    else
      v_total := coalesce(
        nullif(v_entreprise.prix_abonnement_mensuel, 0),
        nullif(v_abo_grille, 0),
        nullif(v_total, 0),
        0
      );
    end if;

    if v_total <= 0 then
      raise exception 'MONTANT_TOTAL_INCONNU';
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
  --  Un compte SUSPENDU n'est jamais réactivé par un paiement : la
  --  réactivation reste une décision de l'administrateur.
  if v_nouveau_solde <= 0 and v_statut_avant <> 'SUSPENDU' then
    v_activer := true;
    v_prolongation := v_duree;

    -- Renouvellement anticipé : on repart de la date d'expiration si elle est
    -- encore future pour ne perdre aucun jour payé ; sinon de maintenant
    -- (essai, abonnement échu, attente de complément).
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

  -- Journal d'audit (le trigger ci-dessus trace en plus le changement de
  -- statut, le cas échéant).
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
      'correctif', '60'
    ),
    now()
  );

  return v_entreprise;
end;
$$;

comment on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) is
  'Moteur d''abonnement : enregistre un paiement, ouvre un nouveau cycle si nécessaire. Correctif 60 : le PREMIER cycle facture le prix d''installation (premier mois inclus), les suivants le prix mensuel.';

revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from public;
revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from anon;
grant execute on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) to authenticated;


-- ============================================================================
--  4. L'ÉCRAN FINANCE PUBLIÉ RESTE COHÉRENT
-- ============================================================================
--  La fenêtre « Valider le paiement » de l'application DÉJÀ PUBLIÉE appelle
--  cette RPC pour négocier le montant. On la reprend à l'identique, avec une
--  seule addition : au premier cycle, ce montant EST le prix d'installation,
--  donc on le recopie dans la nouvelle colonne. Sans cela, un prix
--  d'installation pré-rempli l'emporterait sur la saisie de l'opérateur.

create or replace function public.rpc_activation_definir_montant_total(
  p_entreprise_id uuid,
  p_montant       numeric,
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role  text := public.mon_role();
  v_e     public.entreprises;
  v_avant numeric;
  v_note  text := nullif(btrim(coalesce(p_note, '')), '');
begin
  -- Plateau : finance, agent terrain, gestionnaire des comptes ou Super Admin.
  if v_role not in ('FINANCE_LAPERLE', 'AGENT_TERRAIN',
                    'GESTIONNAIRE_COMPTES', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seuls la finance, un agent terrain ou le gestionnaire des comptes fixent le montant dû d''un abonnement.';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Indiquez le montant total dû (valeur supérieure à zéro).';
  end if;

  select * into v_e from public.entreprises
   where id = p_entreprise_id for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  v_avant := coalesce(v_e.montant_total_du, 0);

  update public.entreprises
     set montant_total_du = p_montant,
         -- CORRECTIF 60 : au premier cycle, ce montant négocié EST le prix
         -- d'installation (le premier mois est inclus). On le recopie pour
         -- que le moteur distingue correctement installation et mensuel.
         prix_installation = case
                               when v_e.date_activation is null then p_montant
                               else v_e.prix_installation
                             end,
         updated_at       = now()
   where id = p_entreprise_id
   returning * into v_e;

  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (
      gen_random_uuid(), p_entreprise_id, 'MONTANT_TOTAL_FIXE', auth.uid(),
      jsonb_build_object(
        'montant_avant', v_avant,
        'montant_apres', p_montant,
        'deja_paye', coalesce(v_e.montant_deja_paye, 0),
        'solde_restant', v_e.solde_restant,
        'prix_installation', v_e.prix_installation,
        'note', v_note
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', p_entreprise_id,
    'montant_total_du', p_montant,
    'montant_avant', v_avant,
    'montant_deja_paye', coalesce(v_e.montant_deja_paye, 0),
    'solde_restant', v_e.solde_restant,
    'prix_installation', v_e.prix_installation
  );
end;
$$;

comment on function public.rpc_activation_definir_montant_total(uuid, numeric, text) is
  'Module 21 — Fixe le montant total dû d''un abonnement (le solde_restant généré suit automatiquement). Correctif 60 : au premier cycle, alimente aussi le prix d''installation.';

revoke all on function public.rpc_activation_definir_montant_total(uuid, numeric, text)
  from public, anon;
grant execute on function public.rpc_activation_definir_montant_total(uuid, numeric, text)
  to authenticated;


-- ============================================================================
--  5. NOUVELLE RPC — FIXER LES DEUX PRIX D'UNE ENTREPRISE
-- ============================================================================
--  Destinée au futur écran d'administration (et utilisable tout de suite en
--  SQL). Un paramètre laissé à NULL n'est PAS modifié.

create or replace function public.rpc_abonnement_definir_prix(
  p_entreprise_id uuid,
  p_installation  numeric default null,
  p_mensuel       numeric default null,
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role           text := public.mon_role();
  v_e              public.entreprises;
  v_inst_avant     numeric;
  v_mensuel_avant  numeric;
  v_note           text := nullif(btrim(coalesce(p_note, '')), '');
begin
  if v_role not in ('FINANCE_LAPERLE', 'AGENT_TERRAIN',
                    'GESTIONNAIRE_COMPTES', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seuls la finance, un agent terrain, le gestionnaire des comptes ou le Super Admin fixent les prix d''un abonnement.';
  end if;

  if p_installation is null and p_mensuel is null then
    raise exception 'PARAMETRES_VIDES|Indiquez au moins un prix (installation ou mensuel).';
  end if;

  if p_installation is not null and p_installation <= 0 then
    raise exception 'MONTANT_INVALIDE|Le prix d''installation doit être supérieur à zéro.';
  end if;

  if p_mensuel is not null and p_mensuel <= 0 then
    raise exception 'MONTANT_INVALIDE|Le prix mensuel doit être supérieur à zéro.';
  end if;

  select * into v_e from public.entreprises
   where id = p_entreprise_id for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  v_inst_avant    := v_e.prix_installation;
  v_mensuel_avant := v_e.prix_abonnement_mensuel;

  update public.entreprises
     set prix_installation       = coalesce(p_installation, v_e.prix_installation),
         prix_abonnement_mensuel = coalesce(p_mensuel, v_e.prix_abonnement_mensuel),
         updated_at              = now()
   where id = p_entreprise_id
   returning * into v_e;

  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (
      gen_random_uuid(), p_entreprise_id, 'PRIX_ABONNEMENT_FIXE', auth.uid(),
      jsonb_build_object(
        'installation_avant', v_inst_avant,
        'installation_apres', v_e.prix_installation,
        'mensuel_avant', v_mensuel_avant,
        'mensuel_apres', v_e.prix_abonnement_mensuel,
        'note', v_note
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', p_entreprise_id,
    'prix_installation', v_e.prix_installation,
    'prix_abonnement_mensuel', v_e.prix_abonnement_mensuel,
    'cycle', case when v_e.date_activation is null
                  then 'premier (installation)' else 'renouvellement (mensuel)' end
  );
end;
$$;

comment on function public.rpc_abonnement_definir_prix(uuid, numeric, numeric, text) is
  'Correctif 60 — Fixe le prix d''installation (premier mois inclus) et le prix mensuel d''une entreprise. NULL = ne pas modifier.';

revoke all on function public.rpc_abonnement_definir_prix(uuid, numeric, numeric, text)
  from public, anon;
grant execute on function public.rpc_abonnement_definir_prix(uuid, numeric, numeric, text)
  to authenticated;


-- ============================================================================
--  6. CONTRÔLE — le moteur applique-t-il bien les deux prix ?
-- ============================================================================

do $verif_prix$
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
    raise exception 'Correctif 60 : moteur d''abonnement introuvable.';
  end if;

  if position('v_premier_cycle := (v_entreprise.date_activation is null)' in v_def) = 0 then
    raise exception 'Correctif 60 : la detection du premier cycle n''est pas en place.';
  end if;

  if position('prix_abonnement_mensuel' in v_def) = 0
     or position('prix_installation' in v_def) = 0 then
    raise exception 'Correctif 60 : le moteur ne lit pas les deux prix.';
  end if;

  if position('v_statut_avant = ''EXPIRE'' then' in v_def) = 0 then
    raise exception 'Correctif 60 : le correctif 53 (complement) a ete perdu — ne poursuivez pas, transmettez ce message.';
  end if;

  raise notice 'Correctif 60 : les deux prix sont en place dans le moteur.';
end $verif_prix$;


-- ============================================================================
--  RAPPORT FINAL — le prix qui sera réclamé au PROCHAIN cycle
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select e.nom                        as entreprise,
       e.statut::text               as statut,
       case when e.date_activation is null
            then '1. premier cycle → INSTALLATION'
            else '2. renouvellement → MENSUEL' end as prochain_cycle,
       e.prix_installation          as prix_installation,
       e.prix_abonnement_mensuel    as prix_mensuel,
       coalesce(g.montant_abonnement, 0) as grille_mensuel,
       e.montant_total_du           as total_du_actuel,
       coalesce(e.montant_deja_paye, 0)  as deja_paye,
       e.solde_restant              as solde_actuel,
       case when e.date_activation is null
            then coalesce(nullif(e.prix_installation, 0),
                          nullif(e.montant_total_du, 0),
                          nullif(coalesce(g.frais_ouverture, 0)
                                 + coalesce(g.montant_abonnement, 0), 0),
                          nullif(g.montant_abonnement, 0),
                          0)
            else coalesce(nullif(e.prix_abonnement_mensuel, 0),
                          nullif(g.montant_abonnement, 0),
                          nullif(e.montant_total_du, 0),
                          0)
       end                          as prochain_montant_du
  from public.entreprises e
  left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
 order by e.nom;


-- ============================================================================
--  NOTE — CORRIGER UN PRIX APRÈS COUP (à exécuter à la main, si besoin)
--  ------------------------------------------------------------------------
--  Le rapport ci-dessus affiche, pour chaque entreprise, le montant qui sera
--  réclamé au prochain cycle. Si un prix mensuel est encore l'ancien montant
--  « installation incluse », corrigez-le :
--
--    select public.rpc_abonnement_definir_prix(
--             '<uuid-de-l-entreprise>'::uuid,
--             null,      -- prix d'installation : inchangé
--             5000       -- NOUVEAU prix mensuel, en CDF
--           );
--
--  Ou directement, pour une remise à niveau en masse :
--
--    update public.entreprises
--       set prix_abonnement_mensuel = 5000
--     where id = '<uuid-de-l-entreprise>';
--
--  ⚠️ La GRILLE TARIFAIRE joue le rôle de valeur par défaut : si
--     `groupes_tarifaires.montant_abonnement` porte encore un montant qui
--     incluait l'installation, pensez à la corriger aussi (écran
--     « Référentiels → Groupes tarifaires »), sans quoi les NOUVELLES
--     entreprises hériteront de ce montant.
--
--  ℹ️ OBSERVATION (non corrigée ici, volontairement) : dans le moteur,
--     `v_duree` reste à 0 si l'entreprise n'a aucune grille tarifaire
--     affectée (`coalesce(v_duree, 30)` ne rattrape pas un 0). Un compte sans
--     pack activé obtient donc 0 jour de prolongation. Signalez-le si cela
--     vous gêne : le correctif tient en une ligne.
-- ============================================================================
