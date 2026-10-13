-- ============================================================================
--  biashara_yangu — CORRECTIF 73 : CRÉER UNE ENTREPRISE AVEC SON PROPRIÉTAIRE
--  Migration 20260916000073_admin_entreprise_creation.sql
-- ============================================================================
--
--  ⛔ AUCUNE PUBLICATION. Correction de base uniquement.
--
--  LE PROBLÈME
--  -----------
--  Aujourd'hui la plateforme crée une entreprise VIDE : `entreprise_form_page`
--  insère une ligne dans `entreprises` (nom, ville, activité, grille) et rien
--  d'autre. Le patron doit S'INSCRIRE LUI-MÊME ensuite, et rien ne relie
--  formellement le compte à l'entreprise — le seul lien est
--  `utilisateurs.entreprise_id`, donc à l'envers.
--
--  Deux conséquences :
--    • impossible de retrouver le PATRON d'une entreprise sans deviner ;
--    • impossible de savoir QUI a apporté le compte (agent terrain,
--      gestionnaire des comptes, Super Admin) : aucun suivi des apporteurs.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--   1. trois colonnes sur `entreprises` :
--        • `proprietaire_id` — LE patron du compte (lien explicite) ;
--        • `cree_par`        — qui a créé le compte (NULL = auto-inscription) ;
--        • `cree_le`         — quand ;
--      + rattrapage des entreprises DÉJÀ existantes (aucune donnée inventée) ;
--   2. `rpc_admin_entreprise_creer(...)` — UNE SEULE opération :
--        compte du propriétaire (Auth + profil PROPRIETAIRE) → entreprise →
--        espace typé → dossier d'activation → les DEUX prix
--        (installation / mensuel, correctif 60) → essai de 7 jours → trace ;
--   3. `rpc_entreprise_fiche(id)` — LA FICHE UNIQUE en lecture : identité,
--        propriétaire, créateur, grille, les deux prix, montants et solde,
--        suivi (étape, dates, jours restants) et HISTORIQUE COMPLET
--        (dossiers d'activation + paiements = l'avance encaissée).
--
--  CE QUI N'EST PAS TOUCHÉ
--  -----------------------
--    • les prix et le moteur d'abonnement (correctifs 60/61/62) : on les
--      LIT, on ne les réécrit pas ;
--    • la double validation (module 14) : le compte créé reste
--      `en_attente_verification` et doit passer par Gestionnaire → Finance ;
--    • les écrans publiés : aucune signature existante n'est modifiée.
--
--  ⚠️ À exécuter dans Supabase → SQL Editor → coller → Run.
--  IDEMPOTENTE : relançable sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE LIEN EXPLICITE : PROPRIÉTAIRE + CRÉATEUR
-- ============================================================================
--  ⚠️ Aucune clé étrangère n'est ajoutée vers `utilisateurs(id)` :
--  l'expérience du module 17 (FK `journal_audit` → entreprise rendant les
--  lignes indestructibles) montre qu'une FK sur un journal bloque les
--  suppressions. Deux index suffisent pour les recherches.

alter table public.entreprises
  add column if not exists proprietaire_id uuid;
alter table public.entreprises
  add column if not exists cree_par uuid;
alter table public.entreprises
  add column if not exists cree_le timestamptz;

comment on column public.entreprises.proprietaire_id is
  'Correctif 73 — LE PATRON du compte (`utilisateurs.id`). Le lien historique `utilisateurs.entreprise_id` reste en place ; cette colonne rend le lien explicite côté plateforme.';

comment on column public.entreprises.cree_par is
  'Correctif 73 — qui a CRÉÉ le compte : agent terrain, gestionnaire des comptes ou Super Admin (`utilisateurs.id`). NULL = le patron s''est inscrit seul.';

comment on column public.entreprises.cree_le is
  'Correctif 73 — date de création du compte telle que vue par la plateforme.';

create index if not exists entreprises_proprietaire_idx
  on public.entreprises (proprietaire_id);
create index if not exists entreprises_cree_par_idx
  on public.entreprises (cree_par);


-- ============================================================================
--  2. RATTRAPAGE DES ENTREPRISES EXISTANTES
-- ============================================================================
--  Aucune donnée n'est inventée : on déduit le propriétaire de ce qui existe
--  déjà (`utilisateurs.entreprise_id` + `parent_id is null` = le patron).

update public.entreprises e
   set cree_le = coalesce(e.created_at, now())
 where e.cree_le is null;

update public.entreprises e
   set proprietaire_id = (
         select u.id
           from public.utilisateurs u
          where u.entreprise_id = e.id
          order by (u.parent_id is null) desc, u.created_at asc nulls last
          limit 1)
 where e.proprietaire_id is null
   and exists (select 1 from public.utilisateurs u where u.entreprise_id = e.id);


-- ============================================================================
--  3. CRÉER UNE ENTREPRISE **AVEC** SON PROPRIÉTAIRE
-- ============================================================================
--  Un seul appel = un compte complet et cohérent. Les validations passent
--  AVANT toute création : si une seule échoue, rien n'est créé.
--
--  Réutilise `public.creer_compte_plateforme(...)` (module 4) : le mot de
--  passe est haché par GoTrue (bcrypt) et la session de l'administrateur
--  n'est PAS remplacée.

create or replace function public.rpc_admin_entreprise_creer(
  p_nom                    text,
  p_ville_id               uuid    default null,
  p_activite_id            uuid    default null,
  p_groupe_tarifaire_id    uuid    default null,
  p_type_espace            text    default 'boutique',
  p_proprietaire_nom       text    default null,
  p_proprietaire_prenom    text    default null,
  p_proprietaire_email     text    default null,
  p_proprietaire_telephone text    default null,
  p_mot_de_passe           text    default null,
  p_prix_installation      numeric default null,
  p_prix_mensuel           numeric default null,
  p_note                   text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_role    text := public.mon_role();
  v_nom     text;
  v_email   text := lower(btrim(coalesce(p_proprietaire_email, '')));
  v_nomp    text;
  v_prenom  text;
  v_tel     text;
  v_type    text;
  v_deja    boolean := false;
  v_owner   uuid;
  v_ent     uuid;
  v_inst    numeric;
  v_mensuel numeric;
  v_essai   integer := 7;
  v_g_inst  numeric := 0;
  v_g_abont numeric := 0;
  v_note    text;
begin
  -- ---------------------------------------------------------------- droits
  if not (public.est_plateforme() or public.peut('entreprises', 'creer')) then
    raise exception 'DROIT_REFUSE|Seule la plateforme crée le compte d''une entreprise.';
  end if;

  -- ------------------------------------------------------------------ nom
  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null or length(v_nom) < 2 then
    raise exception 'NOM_REQUIS|Indiquez le nom de l''entreprise (2 caractères minimum).';
  end if;

  -- ------------------------------------------------- identité du patron
  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE|Adresse e-mail du propriétaire invalide.';
  end if;

  if p_mot_de_passe is null or length(p_mot_de_passe) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT|Le mot de passe doit comporter au moins 8 caractères.';
  end if;

  v_nomp   := nullif(btrim(coalesce(p_proprietaire_nom, '')), '');
  v_prenom := nullif(btrim(coalesce(p_proprietaire_prenom, '')), '');
  v_tel    := nullif(btrim(coalesce(p_proprietaire_telephone, '')), '');

  if v_nomp is null then
    raise exception 'NOM_PROPRIETAIRE_REQUIS|Indiquez le nom du propriétaire.';
  end if;

  -- --------------------------------------- catégorie d'activité (référentiel)
  v_type := lower(btrim(coalesce(p_type_espace, 'boutique')));
  if to_regclass('public.types_espaces_modules') is not null then
    if not exists (
      select 1 from public.types_espaces_modules t
       where t.type = v_type and t.actif
    ) then
      v_type := 'autre';
      if not exists (
        select 1 from public.types_espaces_modules t
         where t.type = v_type and t.actif
      ) then
        v_type := 'boutique';
      end if;
    end if;
  end if;

  -- ------------------------------------------- grille tarifaire (défauts)
  if p_groupe_tarifaire_id is not null then
    select coalesce(g.frais_ouverture, 0),
           coalesce(g.montant_abonnement, 0),
           coalesce(nullif(g.duree_essai_jours, 0), 7)
      into v_g_inst, v_g_abont, v_essai
      from public.groupes_tarifaires g
     where g.id = p_groupe_tarifaire_id;

    if not found then
      raise exception 'GRILLE_INTROUVABLE|Cette grille tarifaire n''existe plus.';
    end if;
  end if;

  -- Correctif 60 : le prix d'installation COMPREND le premier mois
  -- d'abonnement. Il reste modifiable entreprise par entreprise.
  if p_prix_installation is not null and p_prix_installation > 0 then
    v_inst := p_prix_installation;
  else
    v_inst := nullif(v_g_inst + v_g_abont, 0);
    if v_inst is null then
      v_inst := nullif(v_g_abont, 0);
    end if;
  end if;

  if p_prix_mensuel is not null and p_prix_mensuel > 0 then
    v_mensuel := p_prix_mensuel;
  else
    v_mensuel := nullif(v_g_abont, 0);
  end if;

  if v_inst is null or v_inst <= 0 then
    raise exception 'PRIX_INSTALLATION_REQUIS|Indiquez le prix d''installation (il comprend le premier mois d''abonnement).';
  end if;

  if v_mensuel is not null and v_mensuel <= 0 then
    raise exception 'MONTANT_INVALIDE|Le prix mensuel doit être supérieur à zéro.';
  end if;

  v_note := nullif(btrim(coalesce(p_note, '')), '');

  -- ------------------------------------------- 1) LE COMPTE DU PROPRIÉTAIRE
  select (count(*) > 0) into v_deja
    from public.utilisateurs u
   where lower(u.email) = v_email;

  v_owner := public.creer_compte_plateforme(
               v_email, p_mot_de_passe,
               v_nomp, coalesce(v_prenom, ''), 'PROPRIETAIRE');

  -- ----------------------------------------------------- 2) L'ENTREPRISE
  insert into public.entreprises (
    nom, ville_id, activite_id, groupe_tarifaire_id,
    statut, montant_total_du, montant_deja_paye,
    prix_installation, prix_abonnement_mensuel,
    date_expiration, activation_etape,
    proprietaire_id, cree_par, cree_le
  ) values (
    v_nom, p_ville_id, p_activite_id, p_groupe_tarifaire_id,
    'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum, v_inst, 0,
    v_inst, v_mensuel,
    now() + make_interval(days => v_essai), 'en_attente_verification',
    v_owner, auth.uid(), now()
  )
  returning id into v_ent;

  -- ------------------------------------ 3) L'ESPACE (identifiant = patron)
  insert into public.espaces (id, entreprise_id, nom, type, ville_id, actif)
  values (v_owner, v_ent, v_nom, v_type, p_ville_id, true)
  on conflict (id) do nothing;

  -- ---------------- 4) LE PROFIL APPLICATIF : rattachement + rôle NORMALISÉ
  update public.utilisateurs
     set entreprise_id   = v_ent,
         espace_actif_id = v_owner,
         telephone       = coalesce(v_tel, telephone),
         new_role        = coalesce(public.role_enum('PROPRIETAIRE'), new_role),
         role            = 'PROPRIETAIRE',
         valide          = 1
   where id = v_owner;

  -- --------------------------------------- 5) DOSSIER D'ACTIVATION (m14)
  insert into public.activations_entreprise (
    entreprise_id, etape, acteur_id, acteur_role, note
  ) values (
    v_ent, 'soumission', auth.uid(), v_role,
    coalesce(v_note, 'Création par la plateforme')
  );

  -- ------------------------------------------------------------ 6) TRACE
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'CREATION_ENTREPRISE', auth.uid(),
      jsonb_build_object(
        'entreprise_id', v_ent, 'nom', v_nom, 'type', v_type,
        'proprietaire_id', v_owner, 'proprietaire_email', v_email,
        'cree_par', auth.uid(), 'cree_par_role', v_role,
        'prix_installation', v_inst,
        'prix_abonnement_mensuel', v_mensuel,
        'essai_jours', v_essai,
        'compte_reutilise', v_deja,
        'mode', 'plateforme',
        'note', v_note
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', v_ent,
    'nom', v_nom,
    'type', v_type,
    'proprietaire_id', v_owner,
    'proprietaire_email', v_email,
    'prix_installation', v_inst,
    'prix_abonnement_mensuel', v_mensuel,
    'essai_jours', v_essai,
    'activation_etape', 'en_attente_verification',
    'compte_reutilise', v_deja
  );
end;
$$;

comment on function public.rpc_admin_entreprise_creer(
  text, uuid, uuid, uuid, text, text, text, text, text, text, numeric, numeric, text
) is
  'Correctif 73 — Crée une entreprise AVEC le compte de son propriétaire (Auth + profil PROPRIÉTAIRE), son espace typé, son dossier d''activation et ses deux prix (installation / mensuel). Enregistre aussi QUI a créé le compte (`cree_par`).';

revoke all on function public.rpc_admin_entreprise_creer(
  text, uuid, uuid, uuid, text, text, text, text, text, text, numeric, numeric, text
) from public, anon;
grant execute on function public.rpc_admin_entreprise_creer(
  text, uuid, uuid, uuid, text, text, text, text, text, text, numeric, numeric, text
) to authenticated;


-- ============================================================================
--  4. LA FICHE UNIQUE — TOUT EN UN SEUL APPEL
-- ============================================================================
--  Abonnement + installation + suivi + avance sur UNE SEULE fiche : c'est
--  exactement ce que renvoie cette fonction. Elle ne modifie RIEN.
--
--  Droits : la plateforme, ou l'entreprise elle-même (elle a droit à sa
--  propre fiche — c'est « Mon abonnement »).

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
  'Correctif 73 — LA FICHE UNIQUE d''une entreprise : identité, propriétaire, créateur, grille, les deux prix, montants et solde, suivi (étape, dates, jours restants) et historique complet (dossiers + paiements/avances). Lecture seule.';

revoke all on function public.rpc_entreprise_fiche(uuid) from public, anon;
grant execute on function public.rpc_entreprise_fiche(uuid) to authenticated;


-- ============================================================================
--  5. CONTRÔLE
-- ============================================================================
--  Ce bloc ne modifie rien : il VÉRIFIE que tout est en place et affiche le
--  résultat (le SQL Editor n'affiche que la dernière instruction).

do $verif_73$
declare
  v_cols   integer;
  v_idx    integer;
  v_fonc   integer;
  v_prop   integer;
  v_total  integer;
begin
  select count(*) into v_cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'entreprises'
     and column_name in ('proprietaire_id', 'cree_par', 'cree_le');

  if v_cols <> 3 then
    raise exception 'Correctif 73 : % colonne(s) sur 3 présente(s).', v_cols;
  end if;

  select count(*) into v_idx
    from pg_indexes
   where schemaname = 'public' and tablename = 'entreprises'
     and indexname in ('entreprises_proprietaire_idx', 'entreprises_cree_par_idx');

  if v_idx <> 2 then
    raise exception 'Correctif 73 : % index sur 2 présent(s).', v_idx;
  end if;

  select count(*) into v_fonc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('rpc_admin_entreprise_creer', 'rpc_entreprise_fiche');

  if v_fonc <> 2 then
    raise exception 'Correctif 73 : % fonction(s) sur 2 présente(s).', v_fonc;
  end if;

  -- Le rattrapage ne peut pas être parfait (un compte peut n'avoir aucun
  -- utilisateur rattaché) : on SIGNALE, on ne bloque pas.
  select count(*) into v_total from public.entreprises;
  select count(*) into v_prop from public.entreprises where proprietaire_id is not null;

  raise notice 'Correctif 73 pret : proprietaire retrouve pour % entreprise(s) sur %.',
    v_prop, v_total;
end $verif_73$;


select 'CORRECTIF 73 — PRET' as resultat,
       (select count(*) from public.entreprises) as entreprises,
       (select count(*) from public.entreprises where proprietaire_id is not null) as avec_proprietaire,
       (select count(*) from public.entreprises where cree_par is not null) as avec_createur,
       (select count(*) from public.entreprises where prix_installation is not null) as avec_prix_installation;
