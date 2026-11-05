-- ============================================================================
--  biashara_yangu — MODULE 26 : ABONNEMENT AU NOMBRE DE COLLABORATEURS
--  ---------------------------------------------------------------------------
--  CE QUE LE PROPRIÉTAIRE DEMANDE (05/11/2026)
--    « Le prix de l'abonnement doit suivre le nombre de collaborateurs
--      actifs : 2 500 FC par collaborateur, configurable par la plateforme. »
--
--  CE QUE CE SCRIPT AJOUTE (rien n'est remplacé, tout s'ajoute)
--    1. `app_settings` clé `abonnement_collaborateur`
--       { prix_unitaire: 2500, prorata: false }  ← réglage CENTRAL ;
--    2. `public.abonnement_collaborateurs_actifs(uuid)` — qui est facturé ;
--    3. `public.abonnement_prix_base(uuid)` — le prix d'avant ce module
--       (ex-`rpc_abonnement_prix_du_cycle`, repris à l'identique) ;
--    4. `rpc_abonnement_prix_du_cycle` = BASE + SUPPLÉMENT ;
--    5. `public.abonnement_detail_collaborateurs(uuid)` — le détail affiché
--       au propriétaire (base, nombre, prix unitaire, supplément, total) ;
--    6. `public.abonnement_collaborateurs_periodes` — l'HISTORIQUE : combien
--       de collaborateurs ont été facturés, et à quel prix, par période ;
--    7. le MOTEUR de paiement (`rpc_abonnement_enregistrer_paiement`) ajoute
--       le supplément à CHAQUE OUVERTURE DE CYCLE ;
--    8. un trigger sur `utilisateurs` : activer / désactiver un collaborateur
--       met à jour le dossier immédiatement, sans action de l'utilisateur.
--
--  ⚠️ RÈGLES RESPECTÉES
--    • le propriétaire n'est jamais compté comme collaborateur ;
--    • un collaborateur désactivé (`valide = 0`) n'est plus facturé ;
--    • un compte ayant plusieurs rôles dans la même entreprise ne compte
--      qu'UNE fois (`count(distinct id)`) ;
--    • deux entreprises différentes comptent séparément ;
--    • une facture déjà émise ou une période déjà payée n'est JAMAIS
--      recalculée : le montant dû du cycle en cours n'est pas modifié quand
--      un collaborateur s'ajoute (sauf `prorata = true`, et alors seulement
--      à la hausse) ;
--    • idempotent : peut être relancé.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'rpc_abonnement_prix_du_cycle' and n.nspname = 'public'
  ) then
    raise exception
      'Module 3 absent : exécutez d''abord 20260916000097_prix_cycle_aligne_sur_le_moteur.sql.';
  end if;
end $$;


-- ============================================================================
--  1. LE RÉGLAGE CENTRAL
-- ============================================================================
--  `on conflict do nothing` : si la plateforme a déjà changé le prix, il est
--  CONSERVÉ (ce script ne réécrit jamais un réglage existant).

insert into public.app_settings (key, value, updated_at)
values (
  'abonnement_collaborateur',
  jsonb_build_object('prix_unitaire', 2500, 'prorata', false),
  now()
)
on conflict (key) do nothing;

comment on table public.app_settings is
  'Réglages de la plateforme. Clé « abonnement_collaborateur » : prix unitaire par collaborateur actif et politique prorata.';


-- ============================================================================
--  2. LE PRIX UNITAIRE (lu par toutes les fonctions ci-dessous)
-- ============================================================================

create or replace function public.abonnement_prix_collaborateur()
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
           nullif((select (value ->> 'prix_unitaire')::numeric
                     from public.app_settings
                    where key = 'abonnement_collaborateur'), 0),
           2500
         );
$$;

comment on function public.abonnement_prix_collaborateur() is
  'Module 26 — prix d''un collaborateur actif par période (2 500 FC par défaut, réglable par la plateforme).';

grant execute on function public.abonnement_prix_collaborateur() to authenticated;


-- ============================================================================
--  3. QUI EST FACTURÉ ?
-- ============================================================================
--  Un collaborateur ACTIF = un compte rattaché à l'entreprise, validé, qui
--  n'est pas le propriétaire et n'appartient pas à la plateforme.
--
--  Rattachement : `entreprise_id` (Module 15) OU `parent_id` (comptes créés
--  par le patron depuis l'application). Un même compte n'est compté qu'une
--  fois, même s'il possède plusieurs rôles ou les deux rattachements.

create or replace function public.abonnement_collaborateurs_actifs(
  p_entreprise uuid
)
returns integer
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_n integer := 0;
begin
  if p_entreprise is null then
    return 0;
  end if;

  select count(distinct u.id)
    into v_n
    from public.utilisateurs u
   where u.id <> p_entreprise
     and coalesce(u.valide, 1) <> 0
     and lower(coalesce(u.role, '')) not in ('admin', 'super_admin', 'plateforme')
     and (
       u.entreprise_id = p_entreprise
       or u.parent_id = p_entreprise::text
     );

  return coalesce(v_n, 0);
end;
$$;

comment on function public.abonnement_collaborateurs_actifs(uuid) is
  'Module 26 — nombre de comptes collaborateurs réellement actifs et facturables d''une entreprise (propriétaire exclu, doublons exclus).';

grant execute on function public.abonnement_collaborateurs_actifs(uuid) to authenticated;


-- ============================================================================
--  4. LE SUPPLÉMENT
-- ============================================================================

create or replace function public.abonnement_supplement_collaborateurs(
  p_entreprise uuid
)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select round(
           public.abonnement_collaborateurs_actifs(p_entreprise)
           * public.abonnement_prix_collaborateur(),
           2
         );
$$;

comment on function public.abonnement_supplement_collaborateurs(uuid) is
  'Module 26 — supplément dû pour les collaborateurs actifs (nombre × prix unitaire).';

grant execute on function public.abonnement_supplement_collaborateurs(uuid) to authenticated;


-- ============================================================================
--  5. LE PRIX DE BASE (identique à l'existant)
-- ============================================================================
--  C'est EXACTEMENT la règle du correctif 97 : installation seulement si le
--  compte n'a jamais été activé, sinon prix mensuel. Ce module ne la change
--  pas — il ajoute le supplément par-dessus.

create or replace function public.abonnement_prix_base(
  p_entreprise uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_e      public.entreprises%rowtype;
  v_grille numeric := 0;
  v_prix   numeric := 0;
begin
  select * into v_e from public.entreprises where id = p_entreprise;
  if not found then
    return 0;
  end if;

  if v_e.date_activation is null
     and coalesce(v_e.prix_installation, 0) > 0 then
    return v_e.prix_installation;
  end if;

  select coalesce(g.montant_abonnement, 0)
    into v_grille
    from public.groupes_tarifaires g
   where g.id = v_e.groupe_tarifaire_id;

  v_prix := coalesce(
    nullif(v_e.prix_abonnement_mensuel, 0),
    nullif(v_grille, 0),
    case
      when coalesce(v_e.montant_total_du, 0) > 0
       and coalesce(v_e.montant_total_du, 0) <> coalesce(v_e.prix_installation, -1)
        then v_e.montant_total_du - coalesce(v_e.supplement_collaborateurs, 0)
      else 0
    end,
    nullif(v_e.prix_installation, 0),
    0
  );

  if v_e.date_activation is not null
     and coalesce(v_e.prix_installation, 0) > 0
     and v_prix = coalesce(v_e.prix_installation, 0) then
    select coalesce(g.montant_abonnement, 0)
      into v_prix
      from public.groupes_tarifaires g
     where g.id = v_e.groupe_tarifaire_id;
    v_prix := coalesce(nullif(v_prix, 0), v_e.prix_abonnement_mensuel, 0);
  end if;

  return coalesce(v_prix, 0);
end;
$$;

comment on function public.abonnement_prix_base(uuid) is
  'Module 26 — prix de base du prochain cycle (hors supplément collaborateurs) : installation au premier cycle, puis mensuel.';

grant execute on function public.abonnement_prix_base(uuid) to authenticated;


-- Colonne : supplément réellement inclus dans le cycle EN COURS. Elle permet
-- de ne jamais le compter deux fois et de l'afficher au propriétaire.
alter table public.entreprises
  add column if not exists supplement_collaborateurs numeric not null default 0;

comment on column public.entreprises.supplement_collaborateurs is
  'Module 26 — supplément collaborateurs déjà inclus dans montant_total_du du cycle en cours.';


-- ============================================================================
--  6. LE PRIX DU CYCLE, SUPPLÉMENT INCLUS
-- ============================================================================

create or replace function public.rpc_abonnement_prix_du_cycle(
  p_entreprise uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_base       numeric := 0;
  v_supplement numeric := 0;
begin
  v_base := public.abonnement_prix_base(p_entreprise);
  if v_base <= 0 then
    -- Aucun prix : on ne fabrique pas un supplément tout seul.
    return 0;
  end if;

  v_supplement := public.abonnement_supplement_collaborateurs(p_entreprise);
  return round(v_base + v_supplement, 2);
end;
$$;

comment on function public.rpc_abonnement_prix_du_cycle(uuid) is
  'Module 26 — prix du prochain cycle = base (installation ou mensuel) + supplément des collaborateurs actifs.';

revoke all on function public.rpc_abonnement_prix_du_cycle(uuid) from public, anon;
grant execute on function public.rpc_abonnement_prix_du_cycle(uuid) to authenticated;


-- ============================================================================
--  7. LE DÉTAIL AFFICHÉ AU PROPRIÉTAIRE
-- ============================================================================

create or replace function public.abonnement_detail_collaborateurs(
  p_entreprise uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_owner   uuid;
  v_id      uuid;
  v_e       public.entreprises%rowtype;
  v_base    numeric := 0;
  v_nb      integer := 0;
  v_unite   numeric := 0;
  v_supp    numeric := 0;
  v_encours numeric := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter votre abonnement.';
  end if;

  v_owner := public.mon_proprietaire();
  v_id := coalesce(p_entreprise, public.mon_entreprise_id(), v_owner, v_user);

  select * into v_e from public.entreprises where id = v_id;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  if not (v_user = v_e.id
          or v_user = v_owner
          or v_id = coalesce(v_owner, v_e.id)
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
  end if;

  v_base  := public.abonnement_prix_base(v_id);
  v_nb    := public.abonnement_collaborateurs_actifs(v_id);
  v_unite := public.abonnement_prix_collaborateur();
  v_supp  := round(v_nb * v_unite, 2);

  -- Ce qui est RÉELLEMENT dû sur le cycle en cours (figé à son ouverture).
  v_encours := coalesce(v_e.montant_total_du, 0);

  return jsonb_build_object(
    'entreprise_id',      v_id,
    'base',               round(v_base, 2),
    'nb_collaborateurs',  v_nb,
    'prix_unitaire',      v_unite,
    'supplement',         v_supp,
    'total_prochain_cycle', round(v_base + v_supp, 2),
    'cycle_en_cours',     v_encours,
    'supplement_cycle_en_cours', coalesce(v_e.supplement_collaborateurs, 0),
    'deja_paye',          coalesce(v_e.montant_deja_paye, 0),
    'solde_restant',      coalesce(v_e.solde_restant, 0),
    'echeance',           v_e.date_expiration,
    'prorata',            coalesce(
                            (select (value ->> 'prorata')::boolean
                               from public.app_settings
                              where key = 'abonnement_collaborateur'),
                            false),
    'devise',             coalesce(v_e.devise, 'CDF')
  );
end;
$$;

comment on function public.abonnement_detail_collaborateurs(uuid) is
  'Module 26 — détail de facturation : base, collaborateurs actifs, prix unitaire, supplément, total, échéance.';

grant execute on function public.abonnement_detail_collaborateurs(uuid) to authenticated;


-- ============================================================================
--  8. HISTORIQUE DES PÉRIODES FACTURÉES
-- ============================================================================
--  Une ligne par entreprise et par période (mois d'ouverture du cycle) : on
--  peut toujours répondre à « combien de collaborateurs m'ont été facturés
--  en octobre ? » même si l'équipe a changé depuis.

create table if not exists public.abonnement_collaborateurs_periodes (
  entreprise_id      uuid not null,
  periode            date not null,
  nb_collaborateurs  integer not null default 0,
  prix_unitaire      numeric not null default 0,
  supplement         numeric not null default 0,
  base               numeric not null default 0,
  total              numeric not null default 0,
  calcule_le         timestamptz not null default now(),
  primary key (entreprise_id, periode)
);

comment on table public.abonnement_collaborateurs_periodes is
  'Module 26 — historique du nombre de collaborateurs facturés et du supplément, par entreprise et par période.';

create index if not exists idx_abo_collab_periodes
  on public.abonnement_collaborateurs_periodes (entreprise_id, periode desc);

alter table public.abonnement_collaborateurs_periodes enable row level security;

drop policy if exists abo_collab_periodes_lecture
  on public.abonnement_collaborateurs_periodes;
create policy abo_collab_periodes_lecture
  on public.abonnement_collaborateurs_periodes
  for select to authenticated
  using (
    entreprise_id = auth.uid()
    or entreprise_id = public.mon_proprietaire()
    or public.est_plateforme()
  );


-- Enregistre (ou met à jour) la photographie de la période en cours.
-- (`returns void` : appelée par `perform`, et par le trigger. Un `record`
--  obligerait l'appelant à décrire ses colonnes.)
create or replace function public.abonnement_photographier_periode(
  p_entreprise uuid,
  p_base       numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base numeric;
  v_nb   integer;
  v_unit numeric;
  v_supp numeric;
  v_periode date := date_trunc('month', now())::date;
begin
  v_base := coalesce(p_base, public.abonnement_prix_base(p_entreprise));
  v_nb   := public.abonnement_collaborateurs_actifs(p_entreprise);
  v_unit := public.abonnement_prix_collaborateur();
  v_supp := round(v_nb * v_unit, 2);

  insert into public.abonnement_collaborateurs_periodes as per (
    entreprise_id, periode, nb_collaborateurs, prix_unitaire,
    supplement, base, total, calcule_le
  ) values (
    p_entreprise, v_periode, v_nb, v_unit, v_supp, v_base,
    round(v_base + v_supp, 2), now()
  )
  on conflict (entreprise_id, periode) do update set
    nb_collaborateurs = excluded.nb_collaborateurs,
    prix_unitaire     = excluded.prix_unitaire,
    supplement        = excluded.supplement,
    base              = excluded.base,
    total             = excluded.total,
    calcule_le        = now();
end;
$$;

comment on function public.abonnement_photographier_periode(uuid, numeric) is
  'Module 26 — enregistre dans l''historique le nombre de collaborateurs facturés de la période en cours.';

revoke all on function public.abonnement_photographier_periode(uuid, numeric) from public, anon;


-- ============================================================================
--  9. ACTUALISATION AUTOMATIQUE (activation / désactivation)
-- ============================================================================
--  Appelée par le trigger sur `utilisateurs`. Elle ne touche JAMAIS au
--  montant d'un cycle déjà soldé, ni à une période payée.

create or replace function public.abonnement_actualiser_collaborateurs(
  p_entreprise uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_e         public.entreprises%rowtype;
  v_nb        integer;
  v_unit      numeric;
  v_supp      numeric;
  v_base      numeric;
  v_prorata   boolean := false;
  v_nouveau   numeric;
  v_solde     numeric;
begin
  if p_entreprise is null then
    return jsonb_build_object('ok', false, 'motif', 'ENTREPRISE_ABSENTE');
  end if;

  -- Un utilisateur ne peut recalculer QUE son entreprise (la plateforme et
  -- les appels internes — trigger, auth.uid() NULL — restent libres).
  if auth.uid() is not null
     and auth.uid() <> p_entreprise
     and p_entreprise is distinct from public.mon_proprietaire()
     and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
  end if;

  select * into v_e from public.entreprises where id = p_entreprise;
  if not found then
    return jsonb_build_object('ok', false, 'motif', 'ENTREPRISE_INTROUVABLE');
  end if;

  v_nb   := public.abonnement_collaborateurs_actifs(p_entreprise);
  v_unit := public.abonnement_prix_collaborateur();
  v_supp := round(v_nb * v_unit, 2);
  v_base := public.abonnement_prix_base(p_entreprise);

  begin
    perform public.abonnement_photographier_periode(p_entreprise, v_base);
  exception when others then
    null;  -- l'historique ne doit jamais bloquer l'équipe
  end;

  v_solde := coalesce(v_e.solde_restant,
                      greatest(coalesce(v_e.montant_total_du, 0)
                               - coalesce(v_e.montant_deja_paye, 0), 0));

  -- Cycle déjà soldé, ou fermé : rien à modifier. Le supplément partira au
  -- prochain renouvellement — c'est la politique par défaut.
  if v_solde <= 0 or v_e.date_activation is null then
    return jsonb_build_object(
      'ok', true, 'motif', 'PROCHAIN_RENOUVELLEMENT',
      'nb_collaborateurs', v_nb, 'supplement', v_supp);
  end if;

  -- Prorata ACTIVÉ : le cycle en cours tient compte du nouveau nombre.
  -- On ne fait QUE AUGMENTER : jamais de baisse sur une période entamée.
  select coalesce((value ->> 'prorata')::boolean, false)
    into v_prorata
    from public.app_settings
   where key = 'abonnement_collaborateur';

  if not coalesce(v_prorata, false) then
    return jsonb_build_object(
      'ok', true, 'motif', 'PROCHAIN_RENOUVELLEMENT',
      'nb_collaborateurs', v_nb, 'supplement', v_supp);
  end if;

  v_nouveau := round(v_base + v_supp, 2);

  if v_nouveau > coalesce(v_e.montant_total_du, 0) + 0.001 then
    update public.entreprises
       set montant_total_du        = v_nouveau,
           supplement_collaborateurs = v_supp,
           updated_at              = now()
     where id = p_entreprise;

    begin
      insert into public.journal_audit (
        id, entreprise_id, action, utilisateur_id, details, created_at
      ) values (
        gen_random_uuid(), p_entreprise, 'ABONNEMENT_COLLABORATEURS', auth.uid(),
        jsonb_build_object(
          'nb_collaborateurs', v_nb,
          'prix_unitaire', v_unit,
          'supplement', v_supp,
          'nouveau_total', v_nouveau,
          'prorata', true
        ),
        now()
      );
    exception when others then null;
    end;

    return jsonb_build_object(
      'ok', true, 'motif', 'PRORATA_APPLIQUE',
      'nb_collaborateurs', v_nb, 'supplement', v_supp,
      'nouveau_total', v_nouveau);
  end if;

  return jsonb_build_object(
    'ok', true, 'motif', 'AUCUN_CHANGEMENT',
    'nb_collaborateurs', v_nb, 'supplement', v_supp);
end;
$$;

comment on function public.abonnement_actualiser_collaborateurs(uuid) is
  'Module 26 — recalcule le nombre de collaborateurs facturables ; met à jour le cycle en cours seulement si le prorata est activé (et jamais à la baisse).';

grant execute on function public.abonnement_actualiser_collaborateurs(uuid) to authenticated;


-- Trigger : toute activation / désactivation / suppression met à jour le
-- dossier. Un échec ici ne doit jamais empêcher de gérer l'équipe.
create or replace function public.trg_utilisateurs_maj_collaborateurs()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_entreprise uuid;
begin
  -- ⚠️ Sur un DELETE, `new` n'existe pas : lire `old` AVANT toute autre
  -- chose évite l'erreur « record new is not assigned yet ».
  if tg_op = 'DELETE' then
    v_entreprise := coalesce(
      nullif(old.entreprise_id::text, '')::uuid,
      nullif(old.parent_id, '')::uuid
    );
  else
    v_entreprise := coalesce(
      nullif(new.entreprise_id::text, '')::uuid,
      nullif(new.parent_id, '')::uuid
    );
    if v_entreprise is null and tg_op = 'UPDATE' then
      v_entreprise := coalesce(
        nullif(old.entreprise_id::text, '')::uuid,
        nullif(old.parent_id, '')::uuid
      );
    end if;
  end if;

  if v_entreprise is not null then
    begin
      perform public.abonnement_actualiser_collaborateurs(v_entreprise);
    exception when others then
      raise warning 'Module 26 — actualisation collaborateurs ignorée : %', sqlerrm;
    end;
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

do $$
begin
  if exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'utilisateurs'
  ) then
    execute 'drop trigger if exists trg_utilisateurs_collaborateurs on public.utilisateurs';
    execute 'create trigger trg_utilisateurs_collaborateurs
               after insert or update of valide, entreprise_id, parent_id
               or delete on public.utilisateurs
               for each row execute function public.trg_utilisateurs_maj_collaborateurs()';
    raise notice 'Module 26 — trigger collaborateurs installé.';
  end if;
end $$;


-- ============================================================================
--  10. LE MOTEUR DE PAIEMENT AJOUTE LE SUPPLÉMENT
-- ============================================================================
--  Reprise INTÉGRALE du moteur (correctif 62). Une seule différence : au
--  moment où un cycle est ouvert, le supplément collaborateurs est ajouté au
--  prix de base, et le montant est figé dans `supplement_collaborateurs`.

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
  -- Module 26
  v_supplement    numeric := 0;
  v_supp_ecrire   numeric;
  v_base_prix     numeric;
begin
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

  select coalesce(g.duree_abonnement_jours, 30)
    into v_duree
    from public.groupes_tarifaires g
   where g.id = v_entreprise.groupe_tarifaire_id;
  v_duree := coalesce(v_duree, 30);

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

  if v_solde <= 0 or v_statut_avant = 'EXPIRE' then

    v_premier_cycle := (v_entreprise.date_activation is null);

    if v_premier_cycle then
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

      v_inst_ecrire := v_total;

    else
      v_total := coalesce(
        nullif(v_entreprise.prix_abonnement_mensuel, 0),
        nullif(v_abo_grille, 0),
        case
          when v_entreprise.prix_installation is not null
               and v_total = v_entreprise.prix_installation
            then null
          --  On retire le supplément du cycle précédent : il sera recalculé
          --  juste après, sinon il serait compté deux fois.
          else nullif(v_total - coalesce(v_entreprise.supplement_collaborateurs, 0), 0)
        end,
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

      v_mens_ecrire := v_total;
    end if;

    -- 🧮 MODULE 26 — SUPPLÉMENT COLLABORATEURS ---------------------------
    --  Ajouté APRÈS l'apprentissage des prix de base : `prix_abonnement_mensuel`
    --  ne contient jamais le supplément, il est recalculé à chaque cycle.
    v_base_prix  := v_total;
    v_supplement := public.abonnement_supplement_collaborateurs(p_entreprise_id);
    v_total      := round(v_total + v_supplement, 2);
    v_supp_ecrire := v_supplement;

    begin
      perform public.abonnement_photographier_periode(p_entreprise_id, v_base_prix);
    exception when others then null;
    end;

    v_paye  := 0;
    v_solde := v_total;
  end if;

  if p_montant > v_solde + 0.001 then
    raise exception 'MONTANT_SUPERIEUR';
  end if;

  v_nouveau_paye  := v_paye + p_montant;
  v_nouveau_solde := greatest(v_solde - p_montant, 0);

  if v_nouveau_solde <= 0 and v_statut_avant <> 'SUSPENDU' then
    v_activer := true;
    v_prolongation := v_duree;

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
         prix_installation       = coalesce(v_inst_ecrire, prix_installation),
         prix_abonnement_mensuel = coalesce(v_mens_ecrire, prix_abonnement_mensuel),
         supplement_collaborateurs = coalesce(v_supp_ecrire, supplement_collaborateurs),
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
      'montant',        p_montant,
      'type',           v_type,
      'total_cycle',    v_total,
      'supplement_collaborateurs', v_supplement,
      'collaborateurs_actifs', public.abonnement_collaborateurs_actifs(p_entreprise_id),
      'reste_a_payer',  v_nouveau_solde
    ),
    now()
  );

  return v_entreprise;
end;
$$;

comment on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) is
  'Module 26 — moteur de paiement : cycle = base + supplément collaborateurs actifs, figé à l''ouverture.';

revoke all on function public.rpc_abonnement_enregistrer_paiement(uuid, numeric, text, text, text) from public, anon;


-- ============================================================================
--  11. RÉGLAGE DU PRIX PAR LA PLATEFORME
-- ============================================================================

create or replace function public.rpc_abonnement_parametres_collaborateur_lire()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_value jsonb;
begin
  select value into v_value
    from public.app_settings
   where key = 'abonnement_collaborateur';

  return coalesce(v_value,
                  jsonb_build_object('prix_unitaire', 2500, 'prorata', false));
end;
$$;

grant execute on function public.rpc_abonnement_parametres_collaborateur_lire() to authenticated;

create or replace function public.rpc_abonnement_parametres_collaborateur_definir(
  p_prix_unitaire numeric,
  p_prorata       boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.est_plateforme() or public.est_super_admin()) then
    raise exception 'DROIT_REFUSE|Seule la plateforme règle le prix par collaborateur.';
  end if;

  if p_prix_unitaire is null or p_prix_unitaire < 0 then
    raise exception 'VALEUR_INVALIDE|Le prix par collaborateur ne peut pas être négatif.';
  end if;

  insert into public.app_settings as s (key, value, updated_at)
  values (
    'abonnement_collaborateur',
    jsonb_build_object(
      'prix_unitaire', p_prix_unitaire,
      'prorata', coalesce(p_prorata, false)
    ),
    now()
  )
  on conflict (key) do update
    set value = excluded.value,
        updated_at = now();

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'ABONNEMENT_PRIX_COLLABORATEUR', v_user,
    jsonb_build_object('prix_unitaire', p_prix_unitaire,
                       'prorata', coalesce(p_prorata, false)),
    now()
  );

  return jsonb_build_object('prix_unitaire', p_prix_unitaire,
                            'prorata', coalesce(p_prorata, false));
end;
$$;

comment on function public.rpc_abonnement_parametres_collaborateur_definir(numeric, boolean) is
  'Module 26 — prix unitaire par collaborateur actif (plateforme) et politique prorata.';

revoke all on function public.rpc_abonnement_parametres_collaborateur_definir(numeric, boolean) from public, anon;
grant execute on function public.rpc_abonnement_parametres_collaborateur_definir(numeric, boolean) to authenticated;


-- ============================================================================
--  12. RATTRAPAGE : photographier les périodes en cours
-- ============================================================================
--  Utile pour que l'historique existe dès l'installation du module.

do $$
declare
  r record;
  n integer := 0;
begin
  for r in select id from public.entreprises loop
    begin
      perform public.abonnement_photographier_periode(r.id, null);
      n := n + 1;
    exception when others then null;
    end;
  end loop;
  raise notice 'Module 26 — % période(s) photographiée(s).', n;
end $$;


-- ============================================================================
--  13. VÉRIFICATIONS
-- ============================================================================

select public.abonnement_prix_collaborateur() as prix_unitaire,
       (select value from public.app_settings
         where key = 'abonnement_collaborateur') as reglage;

select p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'abonnement_prix_collaborateur',
     'abonnement_collaborateurs_actifs',
     'abonnement_supplement_collaborateurs',
     'abonnement_prix_base',
     'abonnement_detail_collaborateurs',
     'abonnement_actualiser_collaborateurs'
   )
 order by p.proname;
