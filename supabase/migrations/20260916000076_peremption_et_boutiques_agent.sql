-- ============================================================================
--  biashara_yangu — CORRECTIF 76 : PÉREMPTION PARTOUT, ET LES BOUTIQUES DE
--                                L'AGENT
--  Migration 20260916000076_peremption_et_boutiques_agent.sql
-- ============================================================================
--
--  ⛔ AUCUNE PUBLICATION. Correction de base uniquement.
--
--  DEUX DEMANDES DU PATRON, DEUX CORRECTIONS
--  -----------------------------------------
--
--  1) « la date de péremption est dans la pharmacie et pas dans la boutique,
--      il faut ajouter »
--     Le champ « Lot & péremption » (et donc le suivi des expirations) est
--     piloté par le MODULE `lots_expiration`. Il n'était activé que pour les
--     profils pharmacie / boutique ? Non : uniquement pharmacie. Une
--     alimentation, un dépôt de boissons ou une boutique vendent aussi des
--     produits qui périment.
--     ⇒ Le module est ACTIVÉ pour les profils GÉNÉRIQUES (boutique, dépôt,
--       autre). Les profils métier (hôtel, restaurant, salle des fêtes…) ne
--       sont PAS touchés : ils n'en ont pas besoin.
--     L'Expert peut le retirer activité par activité depuis
--     « Référentiels → Types d'activités ».
--
--  2) « j'ai vérifié dans l'agent qui a créé la boutique, je ne trouve rien
--      comme entreprise alors que c'est cet agent qui a tout créé ; les
--      boutiques que l'agent crée doivent figurer dans ses boutiques et
--      l'agent peut suivre les abonnements »
--     L'agent terrain n'est PAS un rôle de plateforme au sens de la base
--     (`est_plateforme()` = Super Admin, Gestionnaire des comptes, Finance,
--     Assistance) : les règles RLS de `entreprises` ne lui montrent donc
--     AUCUNE entreprise. Il ne « trouvait rien » — c'est normal, et ce n'est
--     pas ce qu'on veut.
--     ⇒ `rpc_agent_mes_boutiques()` : lecture, EN LECTURE SEULE, des
--       entreprises que l'agent a lui-même créées (`entreprises.cree_par`,
--       correctif 73) OU pour lesquelles il a traité un dossier (une demande
--       de code porte `demande_par`). Avec le suivi complet de l'abonnement :
--       étape, statut, échéance, jours restants, montants, solde, dossier
--       ouvert ou non.
--
--  3) POUR QUE « MES BOUTIQUES » NE RESTE PAS VIDE
--     La page « Mes boutiques » de l'agent lit `rpc_admin_espaces_lister`,
--     qui filtre sur `entreprises.agent_id` — le RÉFÉRENT désigné par la
--     « prise en charge ». Or, quand l'agent crée lui-même le compte depuis
--     le back-office, personne ne prend en charge le dossier : `agent_id`
--     reste vide et l'agent ne voit RIEN de ce qu'il vient de créer.
--     ⇒ Deux verrous levés, sans jamais retirer un référent existant :
--       a. un déclencheur : le créateur d'une entreprise en devient
--          automatiquement le référent s'il est AGENT TERRAIN ;
--       b. une reprise des données déjà saisies (même règle, en une fois).
--     ⇒ Et la FICHE devient lisible par cet agent (`rpc_entreprise_fiche`),
--       pour qu'il puisse suivre l'abonnement du client qu'il a apporté.
--
--  CE QUI N'EST PAS TOUCHÉ
--  -----------------------
--   • l'agent n'écrit RIEN depuis ces fonctions : elles sont `stable` et ne
--     font que lire. Il ne peut ni encaisser, ni activer, ni modifier un prix
--     par ce chemin — la Finance garde la main ;
--   • un référent DÉJÀ désigné n'est jamais remplacé (la prise en charge
--     reste prioritaire) ;
--   • les profils métier et leurs personnalisations ;
--   • les entreprises dont il n'est ni l'auteur, ni le référent.
--
--  ⚠️ À exécuter dans Supabase → SQL Editor → coller → Run.
--  IDEMPOTENTE : relançable sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA PÉREMPTION POUR LES ACTIVITÉS GÉNÉRIQUES
-- ============================================================================
--  Ajout idempotent : on n'ajoute le module QUE s'il est absent, et on ne
--  touche jamais à un profil personnalisé qui l'aurait retiré « exprès »…
--  impossible à distinguer d'un retrait par défaut, donc on ajoute — un
--  retrait reste possible en un clic depuis l'écran des types d'activités.

do $m76_modules$
declare
  v_ajoutes integer := 0;
begin
  if to_regclass('public.types_espaces_modules') is null then
    raise notice 'Correctif 76 : referentiel des activites absent, etape ignoree.';
    return;
  end if;

  update public.types_espaces_modules t
     set modules = t.modules || '["lots_expiration"]'::jsonb
   where t.type in ('boutique', 'depot', 'autre')
     and t.actif
     and not (t.modules @> '["lots_expiration"]'::jsonb);

  get diagnostics v_ajoutes = row_count;
  raise notice 'Correctif 76 : module peremption ajoute a % profil(s).', v_ajoutes;
end $m76_modules$;


-- ============================================================================
--  2. LE CRÉATEUR DEVIENT LE RÉFÉRENT (UNIQUEMENT S'IL EST AGENT TERRAIN)
-- ============================================================================
--  `agent_id` = l'agent terrain qui a apporté / pris en charge le client.
--  C'est sur cette colonne que repose TOUT le cloisonnement de la page
--  « Mes boutiques ». On la remplit donc dès la création, sans jamais écraser
--  un référent déjà nommé (la prise en charge manuelle reste prioritaire).

create or replace function public.agent_referent_automatique()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  --  Le créateur est un agent terrain et a bien créé ce compte lui-même :
  --  le dossier est à lui. Sinon, on ne touche à rien.
  if new.agent_id is null
     and new.cree_par is not null
     and new.cree_par = auth.uid()
     and public.est_agent_terrain()
  then
    new.agent_id := new.cree_par;
  end if;
  return new;
end $$;

comment on function public.agent_referent_automatique() is
  'Correctif 76 — Le créateur d''une entreprise en devient le RÉFÉRENT s''il est agent terrain (renseigne `agent_id`). Ne remplace jamais un référent déjà désigné : la prise en charge manuelle reste prioritaire.';

drop trigger if exists trg_agent_referent_automatique on public.entreprises;
create trigger trg_agent_referent_automatique
  before insert on public.entreprises
  for each row
  execute function public.agent_referent_automatique();

--  Reprise des comptes créés AVANT ce correctif : même règle, appliquée en
--  une fois. Un agent terrain est reconnu par son rôle effectif, comme
--  partout ailleurs (`new_role`, sinon conversion du rôle hérité).
do $m76_reprise$
declare
  v_repris integer := 0;
begin
  update public.entreprises e
     set agent_id = e.cree_par
    from public.utilisateurs u
   where u.id = e.cree_par
     and e.agent_id is null
     and e.cree_par is not null
     and coalesce(
           nullif(upper(btrim(coalesce(u.new_role::text, ''))), ''),
           public.role_herite(u.role),
           'INCONNU') = 'AGENT_TERRAIN';

  get diagnostics v_repris = row_count;
  raise notice 'Correctif 76 : % compte(s) rattache(s) a leur agent createur.', v_repris;
end $m76_reprise$;


-- ============================================================================
--  3. LES BOUTIQUES DE L'AGENT, AVEC LE SUIVI DE L'ABONNEMENT
-- ============================================================================
--  Lecture seule. Aucune écriture, aucun encaissement, aucune activation :
--  l'agent SUIT, la Finance décide.

create or replace function public.rpc_agent_mes_boutiques()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_role  text := public.mon_role();
  v_agent boolean := public.est_agent_terrain();
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour voir vos boutiques.';
  end if;

  --  Un agent terrain voit SES boutiques. La plateforme peut appeler la même
  --  fonction : elle obtient alors les comptes qu'elle a créés elle-même.
  if not (public.est_plateforme() or v_agent) then
    raise exception 'DROIT_REFUSE|Reserve au personnel de la plateforme.';
  end if;

  return jsonb_build_object(
    'ok', true,
    'role', v_role,
    'boutiques', coalesce((
      select jsonb_agg(x order by x->>'cree_le' desc nulls last)
        from (
          select jsonb_build_object(
                   'entreprise_id',        e.id,
                   'nom',                  e.nom,
                   'type',                 (select s.type from public.espaces s
                                             where s.entreprise_id = e.id
                                             limit 1),
                   'statut',               e.statut,
                   'activation_etape',     e.activation_etape,
                   'cree_le',              e.cree_le,
                   'date_activation',      e.date_activation,
                   'date_expiration',      e.date_expiration,
                   'jours_restants',       case
                                             when e.date_expiration is null then null
                                             else (e.date_expiration::date - current_date)
                                           end,
                   'prix_installation',    e.prix_installation,
                   'prix_abonnement_mensuel', e.prix_abonnement_mensuel,
                   'total_du',             e.montant_total_du,
                   'deja_paye',            e.montant_deja_paye,
                   'solde',                e.solde_restant,
                   'proprietaire_nom',     p.nom,
                   'proprietaire_email',   p.email,
                   'proprietaire_telephone', coalesce(p.telephone,
                                                      (select u.telephone
                                                         from public.utilisateurs u
                                                        where u.id = e.proprietaire_id)),
                   'dossiers_en_attente',  (select count(*)
                                              from public.codes_validation_agent c
                                             where c.entreprise_id = e.id
                                               and c.statut in ('EN_ATTENTE', 'EMIS'))
                 ) as x
            from public.entreprises e
            left join public.utilisateurs p on p.id = e.proprietaire_id
           where e.agent_id = v_user
              or e.cree_par = v_user
              or exists (select 1
                           from public.codes_validation_agent c
                          where c.entreprise_id = e.id
                            and c.demande_par = v_user)
        ) liste
    ), '[]'::jsonb));
end $$;

comment on function public.rpc_agent_mes_boutiques() is
  'Correctif 76 — LES BOUTIQUES DE L''AGENT : les entreprises dont il est le référent (agent_id), qu''il a créées (cree_par) ou dont il a traité un dossier, avec le suivi complet de l''abonnement (étape, échéance, jours restants, montants, solde). Lecture seule : l''agent suit, la Finance encaisse et active.';

revoke all on function public.rpc_agent_mes_boutiques() from public, anon;
grant execute on function public.rpc_agent_mes_boutiques() to authenticated;


-- ============================================================================
--  4. LA FICHE DU CLIENT QU'IL A APPORTÉ
-- ============================================================================
--  Recopie EXACTE de la fiche du correctif 73, avec UNE seule différence :
--  l'agent référent (ou créateur) du compte y a accès. Le contenu renvoyé est
--  identique — il n'y a donc pas deux façons de lire un abonnement.

create or replace function public.rpc_entreprise_fiche(
  p_entreprise_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role   text := public.mon_role();
  v_e      public.entreprises;
  v_prop   jsonb;
  v_crea   jsonb;
  v_grille jsonb;
  v_paye   numeric := 0;
  v_proch  numeric;
begin
  select * into v_e
    from public.entreprises
   where id = p_entreprise_id;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  if not (
    public.est_plateforme()
    or public.agent_detient_entreprise(p_entreprise_id)
    or exists (
      select 1 from public.utilisateurs u
       where u.id = auth.uid()
         and (u.entreprise_id = p_entreprise_id or u.id = v_e.proprietaire_id))
  ) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette fiche.';
  end if;

  -- ------------------------------------------------------- LE PROPRIÉTAIRE
  select jsonb_build_object(
           'id', u.id, 'nom', u.nom, 'prenom', u.prenom,
           'email', u.email, 'telephone', u.telephone,
           'role', public.mon_role(u.id),
           'valide', u.valide)
    into v_prop
    from public.utilisateurs u
   where u.id = coalesce(
           v_e.proprietaire_id,
           (select u2.id
              from public.utilisateurs u2
             where u2.entreprise_id = p_entreprise_id
             order by (u2.parent_id is null) desc, u2.created_at asc nulls last
             limit 1));

  -- ---------------------------------------------------------- LE CRÉATEUR
  if v_e.cree_par is not null then
    select jsonb_build_object(
             'id', u.id, 'nom', u.nom, 'email', u.email,
             'role', public.mon_role(u.id))
      into v_crea
      from public.utilisateurs u
     where u.id = v_e.cree_par;
  end if;

  -- ------------------------------------------------------------- LA GRILLE
  if v_e.groupe_tarifaire_id is not null then
    select jsonb_build_object(
             'id', g.id, 'nom', g.nom,
             'frais_ouverture', g.frais_ouverture,
             'montant_abonnement', g.montant_abonnement,
             'duree_essai_jours', g.duree_essai_jours,
             'duree_abonnement_jours', g.duree_abonnement_jours,
             'prix_par_collaborateur', g.prix_par_collaborateur,
             'max_espaces', g.max_espaces)
      into v_grille
      from public.groupes_tarifaires g
     where g.id = v_e.groupe_tarifaire_id;
  end if;

  -- ----------------------------------------------- L'AVANCE (déjà encaissée)
  select coalesce(sum(p.montant), 0) into v_paye
    from public.paiements_abonnements_laperle p
   where p.entreprise_id = p_entreprise_id;

  -- Montant qui sera réclamé au prochain encaissement (règle du correctif 60).
  v_proch := case
    when v_e.date_activation is null
      then coalesce(v_e.prix_installation, v_e.montant_total_du)
    else coalesce(v_e.prix_abonnement_mensuel, v_e.montant_total_du)
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise', to_jsonb(v_e),
    'proprietaire', v_prop,
    'cree_par', v_crea,
    'grille', v_grille,
    'prix', jsonb_build_object(
      'installation',   v_e.prix_installation,
      'mensuel',        v_e.prix_abonnement_mensuel,
      'total_du',       v_e.montant_total_du,
      'deja_paye',      v_e.montant_deja_paye,
      'solde',          v_e.solde_restant,
      'paiements_cumules', v_paye,
      'prochain_montant',  v_proch
    ),
    'suivi', jsonb_build_object(
      'statut',            v_e.statut,
      'activation_etape',  v_e.activation_etape,
      'jours_restants',    case
                             when v_e.date_expiration is null then null
                             else (v_e.date_expiration::date - current_date)
                           end,
      'date_activation',   v_e.date_activation,
      'date_expiration',   v_e.date_expiration,
      'verifie_par',       v_e.verifie_par,
      'verifie_le',        v_e.verifie_le,
      'valide_par_finance', v_e.valide_par_finance,
      'valide_le_finance',  v_e.valide_le_finance
    ),
    'droits', jsonb_build_object(
      'peut_gerer_prix', v_role in ('FINANCE_LAPERLE', 'AGENT_TERRAIN',
                                    'GESTIONNAIRE_COMPTES', 'SUPER_ADMIN'),
      'peut_verifier',   v_role in ('GESTIONNAIRE_COMPTES', 'SUPER_ADMIN'),
      'peut_valider',    v_role in ('FINANCE_LAPERLE', 'SUPER_ADMIN'),
      'peut_creer',      public.est_plateforme() or public.peut('entreprises', 'creer')
    ),
    'historique', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'etape', a.etape, 'montant', a.montant,
                 'mode_paiement', a.mode_paiement,
                 'reference', a.reference_transaction,
                 'note', a.note, 'acteur_role', a.acteur_role,
                 'created_at', a.created_at)
               order by a.created_at desc)
        from public.activations_entreprise a
       where a.entreprise_id = p_entreprise_id), '[]'::jsonb),
    'paiements', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'id', p.id, 'montant', p.montant,
                 'type_paiement', p.type_paiement,
                 'mode_paiement', p.mode_paiement,
                 'note', p.note,
                 'total_apres', p.total_apres,
                 'solde_apres', p.solde_apres,
                 'prolongation_jours', p.prolongation_jours,
                 'created_at', p.created_at)
               order by p.created_at desc)
        from public.paiements_abonnements_laperle p
       where p.entreprise_id = p_entreprise_id), '[]'::jsonb)
  );
end;
$$;

comment on function public.rpc_entreprise_fiche(uuid) is
  'Correctif 73/76 — LA FICHE UNIQUE d''une entreprise : identité, propriétaire, créateur, grille, les deux prix, montants et solde, suivi (étape, dates, jours restants) et historique complet (dossiers + paiements/avances). Lecture seule. Accessible à la plateforme, au propriétaire, et depuis le correctif 76 à l''agent référent ou créateur du compte.';

revoke all on function public.rpc_entreprise_fiche(uuid) from public, anon;
grant execute on function public.rpc_entreprise_fiche(uuid) to authenticated;


-- ============================================================================
--  5. CONTRÔLE
-- ============================================================================

do $verif_76$
declare
  v_fonc    integer;
  v_trg     integer;
  v_mods    integer;
  v_gener   integer;
  v_agents  integer;
  v_pending integer;
begin
  select count(*) into v_fonc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_agent_mes_boutiques';

  if v_fonc <> 1 then
    raise exception 'Correctif 76 : la fonction des boutiques de l''agent est absente.';
  end if;

  select count(*) into v_trg
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
   where c.relname = 'entreprises'
     and t.tgname = 'trg_agent_referent_automatique'
     and not t.tgisinternal;

  if v_trg <> 1 then
    raise exception 'Correctif 76 : le rattachement automatique de l''agent createur est absent.';
  end if;

  if to_regclass('public.types_espaces_modules') is not null then
    select count(*) into v_mods
      from public.types_espaces_modules t
     where t.actif and t.modules @> '["lots_expiration"]'::jsonb;

    select count(*) into v_gener
      from public.types_espaces_modules
     where type in ('boutique', 'depot', 'autre') and actif;

    raise notice 'Correctif 76 : % profil(s) actif(s) ont la peremption (dont les % profils generiques).',
      v_mods, v_gener;
  end if;

  -- Combien de comptes attendent encore d'être rattachés à leur agent ?
  select count(*) into v_pending
    from public.entreprises e
    join public.utilisateurs u on u.id = e.cree_par
   where e.agent_id is null
     and coalesce(
           nullif(upper(btrim(coalesce(u.new_role::text, ''))), ''),
           public.role_herite(u.role),
           'INCONNU') = 'AGENT_TERRAIN';

  select count(*) into v_agents
    from public.entreprises where agent_id = cree_par and agent_id is not null;

  if v_pending > 0 then
    raise warning 'Correctif 76 : % compte(s) cree(s) par un agent restent sans referent (agent_id vide).', v_pending;
  end if;

  raise notice 'Correctif 76 pret : % compte(s) rattache(s) a leur agent createur.', v_agents;
end $verif_76$;


-- ============================================================================
--  RAPPORT FINAL
-- ============================================================================

select 'CORRECTIF 76 — ACTIF' as resultat,
       (select count(*) from public.types_espaces_modules t
         where t.actif and t.modules @> '["lots_expiration"]'::jsonb) as profils_avec_peremption,
       (select count(*) from public.types_espaces_modules where actif)      as profils_actifs,
       (select count(*) from public.entreprises where cree_par is not null) as entreprises_avec_createur,
       (select count(*) from public.entreprises
         where agent_id is not null and agent_id = cree_par)                as rattachees_a_leur_agent,
       (select count(*) from public.codes_validation_agent
         where demande_par is not null)                                     as dossiers_traites_par_un_agent;
