-- =============================================================================
-- ABONNEMENT — TOUT COMPTE A UNE GRILLE TARIFAIRE (0107)
-- =============================================================================
-- Constat : les entreprises créées depuis « setup » (mode simple) arrivaient
-- SANS grille tarifaire (`groupe_tarifaire_id` vide), donc sans prix :
--   • montant dû = 0 → « montant à régler 0 CDF » sur l'écran SerdiPay ;
--   • renouvellement proposé au prix d'une autre grille (10 000 au lieu de
--     20 000 pour la distribution) ;
--   • abonnement « non calculé » alors que l'essai de 7 jours tourne.
--
-- Ce script :
--   1. dote automatiquement toute entreprise sans grille d'une grille par
--      défaut (celle de son type d'activité, sinon la moins chère) ;
--   2. répare les entreprises existantes dans la même situation ;
--   3. re-renseigne le MONTANT DÛ des essais encore à 0 (règle de la 0106).
--
-- Aucune donnée n'est supprimée. Un compte qui a déjà une grille n'est pas
-- touché. Aucun montant payé n'est modifié.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Attribution d'une grille par défaut (création ET modification)
-- -----------------------------------------------------------------------------
create or replace function public.entreprise_grille_par_defaut()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.groupe_tarifaire_id is not null then
    return new;
  end if;

  -- 1) la grille du MÊME type d'activité (distribution ≠ boutique)…
  if new.type_activite is not null then
    select g.id into new.groupe_tarifaire_id
      from public.groupes_tarifaires g
     where g.type_activite = new.type_activite
     order by g.montant_abonnement, g.nom
     limit 1;
  end if;

  -- 2) …sinon la grille la moins chère, pour ne jamais laisser un compte
  --    sans abonnement calculable.
  if new.groupe_tarifaire_id is null then
    select g.id into new.groupe_tarifaire_id
      from public.groupes_tarifaires g
     order by g.montant_abonnement, g.nom
     limit 1;
  end if;

  return new;
end;
$$;

revoke all on function public.entreprise_grille_par_defaut()
  from public, anon, authenticated;

drop trigger if exists trg_entreprise_grille_defaut on public.entreprises;
create trigger trg_entreprise_grille_defaut
  before insert or update of groupe_tarifaire_id, type_activite
  on public.entreprises
  for each row execute function public.entreprise_grille_par_defaut();

comment on function public.entreprise_grille_par_defaut() is
  'Abonnement — attribue une grille tarifaire à toute entreprise qui n''en a pas (0107).';

-- -----------------------------------------------------------------------------
-- 2. Réparation des entreprises créées avant ce correctif
-- -----------------------------------------------------------------------------
do $$
declare
  v_grilles integer := 0;
begin
  -- 2a. Grille manquante : celle du type d'activité, sinon la moins chère.
  with cible as (
    select e.id,
           (
             select g.id
               from public.groupes_tarifaires g
              where e.type_activite is not null
                and g.type_activite = e.type_activite
              order by g.montant_abonnement, g.nom
              limit 1
           ) as grille_type,
           (
             select g.id
               from public.groupes_tarifaires g
              order by g.montant_abonnement, g.nom
              limit 1
           ) as grille_min
      from public.entreprises e
     where e.groupe_tarifaire_id is null
  )
  update public.entreprises e
     set groupe_tarifaire_id = coalesce(c.grille_type, c.grille_min),
         updated_at = now()
    from cible c
   where e.id = c.id
     and coalesce(c.grille_type, c.grille_min) is not null;

  get diagnostics v_grilles = row_count;
  raise notice 'Entreprises dotées d''une grille tarifaire : %', v_grilles;
end $$;

do $$
declare
  v_montants integer := 0;
begin
  -- 2b. Montant dû des essais encore à 0 (règle 0106, rejouée ici car la
  --     grille vient seulement d'être attribuée).
  with cible as (
    select e.id,
           coalesce(
             nullif(e.prix_installation, 0),
             nullif(g.montant_abonnement, 0),
             0) as prix
      from public.entreprises e
      left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
     where e.statut = 'ESSAI_7J'
       and coalesce(e.montant_total_du, 0) = 0
       and coalesce(e.montant_deja_paye, 0) = 0
  )
  update public.entreprises e
     set montant_total_du = c.prix,
         updated_at = now()
    from cible c
   where e.id = c.id
     and c.prix > 0;

  get diagnostics v_montants = row_count;
  raise notice 'Essais dont le montant dû a été renseigné : %', v_montants;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Contrôle
-- -----------------------------------------------------------------------------
-- select e.nom, e.statut, e.type_activite, g.nom as grille,
--        g.montant_abonnement, e.montant_total_du, e.montant_deja_paye,
--        e.solde_restant
--   from public.entreprises e
--   left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
--  order by e.created_at desc
--  limit 15;

-- =============================================================================
-- FIN — tout compte a une grille et un montant dû
-- =============================================================================
