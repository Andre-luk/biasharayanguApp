-- ============================================================================
--  biashara_yangu — MODULE 1 : GESTION DES ENTREPRISES
--  Script idempotent : peut être exécuté plusieurs fois sans effet de bord.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  CE QUE FAIT CE SCRIPT
--    1. Trigger `updated_at` automatique sur public.entreprises
--    2. Policies de lecture des référentiels (villes / activités / groupes)
--    3. Policies de gestion de public.entreprises
--    4. Publication temps réel de public.entreprises
--    5. Fonction d'encaissement d'un paiement (atomique)
--    6. Fonction d'expiration automatique des abonnements échus
--
--  ⚠️ AUCUNE table ni colonne n'est créée : le schéma que vous m'avez
--     communiqué est utilisé tel quel.
-- ============================================================================


-- ============================================================================
--  1. TRIGGER `updated_at` AUTOMATIQUE
-- ============================================================================
--  Le champ est également envoyé par l'application. Ce trigger garantit qu'il
--  reste correct même si la ligne est modifiée depuis le Dashboard Supabase.

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_entreprises_set_updated_at on public.entreprises;

create trigger trg_entreprises_set_updated_at
  before update on public.entreprises
  for each row
  execute function public.set_updated_at();


-- ============================================================================
--  2. POLICIES DE LECTURE DES RÉFÉRENTIELS
-- ============================================================================
--  Les trois référentiels doivent être lisibles par tout utilisateur
--  authentifié : sans cela les listes déroulantes du formulaire restent vides.
--
--  REMARQUE IMPORTANTE : `create policy` n'a AUCUN effet tant que
--  `enable row level security` n'a pas été exécuté sur la table. Si la RLS est
--  déjà active sur ces tables (cas le plus courant), ces policies prennent
--  effet immédiatement. Sinon, rien ne change — voir la section 3 ter.

drop policy if exists "referentiels_villes_lecture" on public.villes;
create policy "referentiels_villes_lecture" on public.villes
  for select to authenticated using (true);

drop policy if exists "referentiels_activites_lecture" on public.activites;
create policy "referentiels_activites_lecture" on public.activites
  for select to authenticated using (true);

drop policy if exists "referentiels_groupes_lecture" on public.groupes_tarifaires;
create policy "referentiels_groupes_lecture" on public.groupes_tarifaires
  for select to authenticated using (true);


-- ============================================================================
--  3. POLICIES DE GESTION DE public.entreprises
-- ============================================================================
--  Lecture pour tout utilisateur authentifié, écriture réservée aux admins.
--  Un admin est un utilisateur dont public.utilisateurs.role = 'admin'
--  (même convention que celle utilisée par l'application).

drop policy if exists "entreprises_lecture" on public.entreprises;
create policy "entreprises_lecture" on public.entreprises
  for select to authenticated using (true);

drop policy if exists "entreprises_ecriture_admin" on public.entreprises;
create policy "entreprises_ecriture_admin" on public.entreprises
  for all to authenticated
  using (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  )
  with check (
    exists (
      select 1 from public.utilisateurs u
      where u.id = auth.uid() and u.role = 'admin'
    )
  );


-- ============================================================================
--  3 ter. (OPTIONNEL) ACTIVER LA RLS — À NE FAIRE QUE SI NÉCESSAIRE
-- ============================================================================
--  Décommentez UNIQUEMENT si les tables ci-dessus n'ont PAS la RLS active et
--  que vous souhaitez la protection qu'apportent les policies ci-dessus.
--  ⚠️ Activer la RLS sans policy correcte verrouille l'accès aux données.
--
-- alter table public.villes              enable row level security;
-- alter table public.activites           enable row level security;
-- alter table public.groupes_tarifaires  enable row level security;
-- alter table public.entreprises         enable row level security;


-- ============================================================================
--  4. TEMPS RÉEL
-- ============================================================================
--  Permet à l'écran « Entreprises » de se rafraîchir quand une autre session
--  modifie une ligne. Sans effet si la table est déjà publiée.

do $$
begin
  alter publication supabase_realtime add table public.entreprises;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

-- Nécessaire pour recevoir l'ancienne valeur lors des suppressions.
alter table public.entreprises replica identity full;


-- ============================================================================
--  5. INDEX (confort de navigation, sans impact fonctionnel)
-- ============================================================================

create index if not exists idx_entreprises_statut
  on public.entreprises (statut);
create index if not exists idx_entreprises_nom
  on public.entreprises (nom);
create index if not exists idx_entreprises_date_expiration
  on public.entreprises (date_expiration);
create index if not exists idx_groupes_tarifaires_activite
  on public.groupes_tarifaires (activite_id);


-- ============================================================================
--  6. ENCAISSEMENT D'UN PAIEMENT D'ABONNEMENT
-- ============================================================================
--  Met à jour UNIQUEMENT montant_deja_paye et solde_restant.
--  Ni le statut, ni les dates ne sont touchés.
--
--  Le verrou `for update` rend l'opération atomique : deux encaissements
--  simultanés ne peuvent pas se perdre l'un l'autre.

create or replace function public.rpc_enregistrer_paiement(
  p_entreprise_id uuid,
  p_montant       numeric
)
returns public.entreprises
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ligne  public.entreprises;
  v_paye   numeric;
  v_total  numeric;
  v_solde  numeric;
begin
  -- Réservé aux administrateurs.
  if not exists (
    select 1 from public.utilisateurs u
    where u.id = auth.uid() and u.role = 'admin'
  ) then
    raise exception 'ACCES_REFUSE';
  end if;

  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE';
  end if;

  select * into v_ligne
  from public.entreprises
  where id = p_entreprise_id
  for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_paye  := coalesce(v_ligne.montant_deja_paye, 0);
  v_total := coalesce(v_ligne.montant_total_du, 0);
  v_solde := coalesce(v_ligne.solde_restant, greatest(v_total - v_paye, 0));

  if p_montant > v_solde then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  update public.entreprises
     set montant_deja_paye = v_paye + p_montant,
         solde_restant      = greatest(v_solde - p_montant, 0),
         updated_at         = now()
   where id = p_entreprise_id
   returning * into v_ligne;

  return v_ligne;
end;
$$;

grant execute on function public.rpc_enregistrer_paiement(uuid, numeric)
  to authenticated;


-- ============================================================================
--  7. EXPIRATION AUTOMATIQUE DES ABONNEMENTS ÉCHUS
-- ============================================================================
--  Passe en EXPIRE les entreprises dont la date_expiration est dépassée et
--  dont le statut est encore ESSAI_7J ou ACTIF.
--
--  Appelée automatiquement par l'application à chaque chargement de la liste.
--  Elle est volontairement sans danger : elle ne touche jamais aux dates ni
--  aux montants.

create or replace function public.rpc_actualiser_statuts_abonnements()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nb integer;
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE';
  end if;

  update public.entreprises
     set statut     = 'EXPIRE',
         updated_at = now()
   where statut in ('ESSAI_7J', 'ACTIF')
     and date_expiration is not null
     and date_expiration < now();

  get diagnostics v_nb = row_count;
  return v_nb;
end;
$$;

grant execute on function public.rpc_actualiser_statuts_abonnements()
  to authenticated;


-- ============================================================================
--  8. VÉRIFICATION
-- ============================================================================
--  À exécuter après le script pour contrôler l'état des lieux.

select
  (select count(*) from public.villes)              as nb_villes,
  (select count(*) from public.activites)           as nb_activites,
  (select count(*) from public.groupes_tarifaires)  as nb_groupes_tarifaires,
  (select count(*) from public.entreprises)         as nb_entreprises;

-- Doit renvoyer les 5 statuts attendus.
select unnest(enum_range(null::public.statut_abonnement_enum)) as statuts_disponibles;
