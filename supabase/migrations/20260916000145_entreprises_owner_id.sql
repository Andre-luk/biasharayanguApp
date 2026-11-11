-- ============================================================================
--  biashara_yangu — MIGRATION 0145 : ROUTE B — UN PROPRIÉTAIRE,
--  PLUSIEURS ENTREPRISES (et donc plusieurs abonnements)
--
--  OBJECTIF MÉTIER
--    Le patron possède Urembo Market ET Hekima Pharma. Il ne veut PAS deux
--    comptes : il veut UN identifiant, deux entreprises, **deux abonnements
--    séparés** (12 500 FC chacun), et basculer de l'une à l'autre.
--
--  POURQUOI CETTE MIGRATION EST LA CLÉ DE VOÛTE
--    Jusqu'ici, une entreprise appartenait « implicitement » à l'utilisateur
--    dont `utilisateurs.entreprise_id` pointait vers elle. Un compte ne
--    pouvait donc avoir qu'UNE entreprise, et l'abonnement (porté par
--    l'entreprise) était de fait unique.
--
--    On ajoute `entreprises.owner_id` : le PROPRIÉTAIRE d'une entreprise est
--    désormais une donnée explicite, indépendante de l'entreprise active.
--    Le patron peut donc posséder N entreprises, chacune avec :
--      • son abonnement (statut, échéance, montant) ;
--      • ses boutiques (espaces), ses produits, son stock, ses ventes ;
--      • ses propres collaborateurs (facturés 2 500 chacun).
--
--  CORRECTION INDISPENSABLE DU COMPTAGE (sinon 15 000 au lieu de 12 500)
--    `abonnement_collaborateurs_actifs()` comptait TOUS les comptes rattachés
--    à l'entreprise — y compris le patron lui-même, puisque son
--    `entreprise_id` pointe vers l'entreprise qu'il consulte. Avec deux
--    entreprises, chaque facture aurait donc inclus le patron :
--        10 000 + 2 500 (patron) + 2 500 (collaborateur) = 15 000 ✗
--    Le patron est maintenant exclu par IDENTITÉ (`owner_id`), pas par rôle.
--
--  ⚠️ IDEMPOTENT — aucune donnée perdue.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE PROPRIÉTAIRE D'UNE ENTREPRISE DEVIENT EXPLICITE
-- ============================================================================

alter table public.entreprises
  add column if not exists owner_id uuid;

create index if not exists idx_entreprises_owner_id
  on public.entreprises (owner_id);

comment on column public.entreprises.owner_id is
  'Route B (0145) — propriétaire de l''entreprise (le patron). Un patron peut posséder plusieurs entreprises, chacune avec son abonnement.';

-- Reprise des données existantes : plusieurs replis, du plus sûr au plus large.
update public.entreprises e
   set owner_id = coalesce(
         -- 1. Le compte sans patron rattaché à cette entreprise.
         (select u.id from public.utilisateurs u
           where u.entreprise_id = e.id
             and u.parent_id is null
           order by u.created_at nulls last
           limit 1),
         -- 2. Un compte marqué PROPRIÉTAIRE de cette entreprise.
         (select u.id from public.utilisateurs u
           where u.entreprise_id = e.id
             and upper(coalesce(u.new_role::text, u.role)) = 'PROPRIETAIRE'
           order by u.created_at nulls last
           limit 1),
         -- 3. N'importe quel compte rattaché (comptes anciens).
         (select u.id from public.utilisateurs u
           where u.entreprise_id = e.id
           order by (u.parent_id is not null), u.created_at nulls last
           limit 1),
         -- 4. Convention historique : identifiant d'entreprise = UUID du patron.
         (select u.id from public.utilisateurs u where u.id = e.id)
       )
 where e.owner_id is null;

-- Un collaborateur hérite de l'entreprise de son patron (comptage par
-- entreprise, indispensable dès qu'un patron en possède plusieurs).
update public.utilisateurs c
   set entreprise_id = p.entreprise_id
  from public.utilisateurs p
 where c.parent_id = p.id
   and c.entreprise_id is null
   and p.entreprise_id is not null;

-- Toute NOUVELLE entreprise créée par l'application appartient au patron
-- connecté, jamais à « personne ».
create or replace function public.entreprises_definir_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.owner_id is null then
    new.owner_id := coalesce(
      nullif(auth.uid(), ''),
      (select u.id from public.utilisateurs u
        where u.entreprise_id = new.id and u.parent_id is null
        limit 1)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_entreprises_definir_owner on public.entreprises;
create trigger trg_entreprises_definir_owner
  before insert on public.entreprises
  for each row
  execute function public.entreprises_definir_owner();


-- ============================================================================
--  2. LE PATRON (indépendant de l'entreprise active)
-- ============================================================================

create or replace function public.mon_patron()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(u.parent_id, u.id)
    from public.utilisateurs u
   where u.id = auth.uid();
$$;

comment on function public.mon_patron() is
  'Route B (0145) — identifiant du patron du compte connecté, quel que soit l''entreprise ou la boutique active. Ne PAS confondre avec mon_proprietaire() (entreprise active).';

revoke all on function public.mon_patron() from public, anon;
grant execute on function public.mon_patron() to authenticated;


-- ============================================================================
--  3. LE COMPTAGE DES COLLABORATEURS EXCLUT LE PATRON
-- ============================================================================
--  Sans cela, chaque entreprise du patron serait facturée +2 500 pour lui.

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
  v_n     integer := 0;
  v_patron uuid;
begin
  if p_entreprise is null then
    return 0;
  end if;

  select coalesce(e.owner_id, p_entreprise) into v_patron
    from public.entreprises e
   where e.id = p_entreprise;

  select count(distinct u.id)
    into v_n
    from public.utilisateurs u
   where coalesce(u.valide, 1) <> 0
     -- Le patron n'est JAMAIS un collaborateur facturé.
     and u.id <> v_patron
     and u.id <> p_entreprise
     and lower(coalesce(u.role, '')) not in ('admin', 'super_admin', 'plateforme')
     and (
       u.entreprise_id = p_entreprise
       -- Repli historique : collaborateur rattaché au patron sans entreprise.
       -- ⚠️ Comparaison en TEXTE des deux côtés : selon les bases,
       --    `parent_id` est un uuid (récent) ou du texte (ancien) — et
       --    « uuid = text » n'existe pas en PostgreSQL.
       or (u.entreprise_id is null and u.parent_id::text = v_patron::text)
     );

  return coalesce(v_n, 0);
end;
$$;

comment on function public.abonnement_collaborateurs_actifs(uuid) is
  'Route B (0145) — collaborateurs facturables d''une entreprise : comptes validés de cette entreprise, PATRON EXCLU, doublons exclus.';


-- ============================================================================
--  4. CONTRÔLE
-- ============================================================================

select 'ENTREPRISES' as controle,
       count(*)                                              as total,
       count(*) filter (where owner_id is null)               as sans_proprietaire,
       count(*) filter (where owner_id is not null)           as avec_proprietaire
  from public.entreprises;

-- Patrons possédant déjà plusieurs entreprises (attendu : 0 avant la bascule).
select 'PATRONS MULTI' as controle,
       p.nom                                   as patron,
       p.email,
       count(*)                                as nb_entreprises,
       string_agg(e.nom, ' · ' order by e.nom) as entreprises
  from public.entreprises e
  join public.utilisateurs p on p.id = e.owner_id
 group by p.id, p.nom, p.email
having count(*) > 1
 order by count(*) desc;

-- Facturation par entreprise après correction (le patron ne doit PAS compter).
select 'FACTURATION' as controle,
       e.nom,
       e.statut,
       public.abonnement_prix_base(e.id)                     as base,
       public.abonnement_collaborateurs_actifs(e.id)         as nb_collaborateurs,
       public.abonnement_supplement_collaborateurs(e.id)     as supplement,
       public.abonnement_prix_base(e.id)
         + public.abonnement_supplement_collaborateurs(e.id) as total_du
  from public.entreprises e
 order by e.nom;
