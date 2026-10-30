-- ============================================================================
--  BIASHARA YANGU — MIGRATION 0083
--  TYPE D'ACTIVITÉ DE L'ENTREPRISE : « boutique » ou « distribution »
--  ---------------------------------------------------------------------------
--  OBJECTIF
--  --------
--  La plateforme doit savoir, pour CHAQUE entreprise, si elle exploite une
--  boutique (commerce de détail classique) ou une entreprise de DISTRIBUTION
--  (agents, tournées, consignes, récipients). Cette information pilote :
--    • les écrans affichés (une boutique ne voit pas les tournées) ;
--    • les forfaits proposés (chaque type a ses propres grilles).
--
--  ⚠️ RÈGLE D'OR — AUCUNE RÉGRESSION
--  ----------------------------------
--  `type_activite` vaut NULL par défaut. NULL = « non renseigné » et
--  l'application conserve EXACTEMENT le comportement actuel (tout est visible).
--  Le filtrage n'a lieu que lorsque le type est renseigné. Aucune entreprise
--  existante ne perd donc l'accès à une fonctionnalité après cette migration.
--
--  CONTENU
--  -------
--    1. Colonne `entreprises.type_activite`       (+ contrainte de domaine)
--    2. Colonne `groupes_tarifaires.type_activite` (forfaits par type)
--    3. Colonne `niveaux_abonnement.type_activite` (niveaux par type)
--    4. `rpc_entreprise_type_activite()`          → lecture (client)
--    5. `rpc_entreprise_definir_type_activite()`  → écriture (plateforme/proprio)
--    6. `rpc_forfaits_lister(p_type)`             → forfaits d'un type
--
--  Aucune table n'est supprimée, aucune donnée n'est réécrite.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 1. COLONNES
-- ---------------------------------------------------------------------------
alter table public.entreprises
  add column if not exists type_activite text;

alter table public.groupes_tarifaires
  add column if not exists type_activite text;

alter table public.niveaux_abonnement
  add column if not exists type_activite text;

-- ---------------------------------------------------------------------------
-- 2. CONTRAINTES DE DOMAINE (NULL autorisé = non renseigné)
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'entreprises_type_activite_check'
       and conrelid = 'public.entreprises'::regclass
  ) then
    alter table public.entreprises
      add constraint entreprises_type_activite_check
      check (type_activite is null or type_activite in ('boutique', 'distribution'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'groupes_tarifaires_type_activite_check'
       and conrelid = 'public.groupes_tarifaires'::regclass
  ) then
    alter table public.groupes_tarifaires
      add constraint groupes_tarifaires_type_activite_check
      check (type_activite is null or type_activite in ('boutique', 'distribution'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'niveaux_abonnement_type_activite_check'
       and conrelid = 'public.niveaux_abonnement'::regclass
  ) then
    alter table public.niveaux_abonnement
      add constraint niveaux_abonnement_type_activite_check
      check (type_activite is null or type_activite in ('boutique', 'distribution'));
  end if;
end $$;

comment on column public.entreprises.type_activite is
  'boutique | distribution | NULL (non renseigné → comportement historique : tout visible)';

-- ---------------------------------------------------------------------------
-- 3. LECTURE DU TYPE (client)
-- ---------------------------------------------------------------------------
-- Retourne le type d'activité de l'entreprise du compte courant.
-- `null` = non renseigné (l'application n'applique alors aucun filtrage).
create or replace function public.rpc_entreprise_type_activite(
  p_entreprise_id uuid default null
)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_entreprise uuid;
  v_type       text;
begin
  v_entreprise := coalesce(p_entreprise_id, public.mon_entreprise_id());

  if v_entreprise is null then
    return null;
  end if;

  -- Un compte ne lit que son entreprise (ou celle qu'il gère, ou la
  -- plateforme). Le contrôle est délégué à la RLS déjà en place sur
  -- `entreprises` : si la ligne n'est pas lisible, on renvoie null.
  select e.type_activite
    into v_type
    from public.entreprises e
   where e.id = v_entreprise;

  return v_type;
exception
  when others then
    -- fail-open : en cas de doute, on ne filtre rien.
    return null;
end;
$$;

revoke all on function public.rpc_entreprise_type_activite(uuid) from public;
grant execute on function public.rpc_entreprise_type_activite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 4. ÉCRITURE DU TYPE (plateforme ou propriétaire de l'entreprise)
-- ---------------------------------------------------------------------------
create or replace function public.rpc_entreprise_definir_type_activite(
  p_entreprise_id uuid,
  p_type          text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text;
begin
  v_type := nullif(btrim(lower(coalesce(p_type, ''))), '');

  if v_type is not null and v_type not in ('boutique', 'distribution') then
    raise exception 'TYPE_ACTIVITE_INVALIDE|Type d''activité inconnu : %', p_type;
  end if;

  if not (
    public.est_plateforme()
    or p_entreprise_id = public.mon_entreprise_id()
  ) then
    raise exception 'DROIT_REFUSE|Vous ne pouvez pas modifier cette entreprise.';
  end if;

  update public.entreprises
     set type_activite = v_type,
         updated_at    = now()
   where id = p_entreprise_id;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Entreprise introuvable.';
  end if;

  return v_type;
end;
$$;

revoke all on function public.rpc_entreprise_definir_type_activite(uuid, text) from public;
grant execute on function public.rpc_entreprise_definir_type_activite(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 5. FORFAITS D'UN TYPE (les forfaits sans type restent proposés partout)
-- ---------------------------------------------------------------------------
create or replace function public.rpc_forfaits_lister(p_type text default null)
returns table (
  id                      uuid,
  nom                     text,
  activite_id             uuid,
  type_activite           text,
  frais_ouverture         numeric,
  montant_abonnement      numeric,
  duree_essai_jours       integer,
  duree_abonnement_jours  integer,
  prix_par_collaborateur  numeric,
  max_espaces             integer
)
language sql
stable
security definer
set search_path = public
as $$
  select g.id,
         g.nom,
         g.activite_id,
         g.type_activite,
         g.frais_ouverture,
         g.montant_abonnement,
         g.duree_essai_jours,
         g.duree_abonnement_jours,
         g.prix_par_collaborateur,
         g.max_espaces
    from public.groupes_tarifaires g
   where case
           when p_type is null then true
           -- un forfait non typé reste visible pour tous les types
           else g.type_activite is null or g.type_activite = p_type
         end
   order by g.montant_abonnement nulls last, g.nom;
$$;

revoke all on function public.rpc_forfaits_lister(text) from public;
grant execute on function public.rpc_forfaits_lister(text) to authenticated;

commit;

-- ============================================================================
--  CONTRÔLE (à exécuter séparément pour vérifier) :
--
--    select count(*) filter (where type_activite is null) as non_renseignees,
--           count(*) filter (where type_activite = 'boutique') as boutiques,
--           count(*) filter (where type_activite = 'distribution') as distributions,
--           count(*) as total
--      from public.entreprises;
-- ============================================================================
