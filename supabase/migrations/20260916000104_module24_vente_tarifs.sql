-- =============================================================================
-- MODULE 24 — LA GRILLE TARIFAIRE S'APPLIQUE RÉELLEMENT EN CAISSE (0104)
-- =============================================================================
-- La migration 0103 a créé `dist_tarifs` (bidon neuf, eau + échange,
-- remplissage, bidon vide, remplacement). Mais la vente (`dist_vente_enregistrer`)
-- continuait de prendre `dist_produits.prix_vente` : la grille était décorative.
--
-- Ce script :
--   1. ajoute `dist_ventes.type_operation` (historique de l'opération vendue) ;
--   2. remplace `dist_vente_enregistrer` en ajoutant `p_type_operation`
--      (défaut `standard`) et en résolvant le prix AINSI :
--         grille active (owner, produit, type) → sinon prix catalogue.
--      Le prix retenu est FIGÉ dans `dist_vente_lignes.prix_unitaire` : modifier
--      la grille ensuite ne change aucune facture passée.
--
-- ⚠️ Compatibilité : l'ancien appel (5 paramètres) reste valide — le 6e a une
--    valeur par défaut. Aucune donnée existante n'est modifiée.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Traçabilité du type d'opération sur la vente
-- -----------------------------------------------------------------------------
alter table public.dist_ventes
  add column if not exists type_operation text not null default 'standard';

comment on column public.dist_ventes.type_operation is
  'Module 24 §9 — type d''opération de la vente (standard, bidon_neuf, eau_avec_echange, remplissage, bidon_vide, remplacement_endommage).';

-- -----------------------------------------------------------------------------
-- 2. Vente : prix issu de la grille tarifaire
-- -----------------------------------------------------------------------------
create or replace function public.dist_vente_enregistrer(
  p_client_id      uuid,
  p_lignes         jsonb,
  p_montant_paye   numeric default null,
  p_mode           text default 'especes',
  p_note           text default null,
  p_type_operation text default 'standard'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_commercial uuid := auth.uid();
  v_id uuid;
  v_num text;
  v_l record;
  v_prod record;
  v_total numeric(16,2) := 0;
  v_paye numeric(16,2);
  v_prix numeric(16,2);
  v_type text := lower(btrim(coalesce(p_type_operation, 'standard')));
  v_tarif numeric(16,2);
begin
  perform public.dist_exige(array['commercial']);

  if v_type not in ('standard', 'bidon_neuf', 'eau_avec_echange',
                    'remplissage', 'bidon_vide', 'remplacement_endommage') then
    raise exception 'TYPE_OPERATION_INVALIDE|Type d''opération inconnu.';
  end if;

  if p_lignes is null or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNES_VIDES|Ajoutez au moins un produit vendu.';
  end if;

  if p_client_id is not null and not exists (
    select 1 from public.dist_clients c
     where c.id = p_client_id and c.owner_id = v_owner
       and c.commercial_id = v_commercial and c.actif
  ) then
    raise exception 'CLIENT_INTROUVABLE|Ce client ne vous appartient pas.';
  end if;

  v_num := public.dist_numero(v_owner, 'FAC');

  insert into public.dist_ventes (
    owner_id, numero, commercial_id, client_id, mode_paiement, note,
    type_operation
  ) values (
    v_owner, v_num, v_commercial, p_client_id,
    coalesce(nullif(btrim(p_mode), ''), 'especes'),
    nullif(btrim(coalesce(p_note, '')), ''),
    v_type
  ) returning id into v_id;

  for v_l in
    select * from jsonb_to_recordset(p_lignes)
      as x(produit_id uuid, quantite numeric, prix_unitaire numeric)
  loop
    if v_l.produit_id is null or v_l.quantite is null or v_l.quantite <= 0 then
      raise exception 'QUANTITE_INVALIDE|Quantité vendue invalide.';
    end if;

    select p.nom, p.prix_vente into v_prod
      from public.dist_produits p
     where p.id = v_l.produit_id and p.owner_id = v_owner and p.actif;

    if v_prod.nom is null then
      raise exception 'PRODUIT_INCONNU|Un des produits n''existe pas.';
    end if;

    -- 1) grille tarifaire active pour ce type d'opération,
    -- 2) puis tarif `standard` de la grille,
    -- 3) sinon prix catalogue du produit.
    v_tarif := null;

    select t.prix into v_tarif
      from public.dist_tarifs t
     where t.owner_id = v_owner
       and t.produit_id = v_l.produit_id
       and t.type_operation = v_type
       and t.actif
     limit 1;

    if v_tarif is null and v_type <> 'standard' then
      select t.prix into v_tarif
        from public.dist_tarifs t
       where t.owner_id = v_owner
         and t.produit_id = v_l.produit_id
         and t.type_operation = 'standard'
         and t.actif
       limit 1;
    end if;

    v_prix := coalesce(v_tarif, v_prod.prix_vente, 0);

    -- Le stock PERSONNEL du commercial est le seul débité ici.
    perform public.dist_bouger_commercial(v_owner, v_commercial,
      v_l.produit_id, -v_l.quantite, 'vente_commercial',
      'vente', v_id, 'Vente ' || v_num);

    insert into public.dist_vente_lignes (
      vente_id, produit_id, nom_produit, quantite, prix_unitaire, total
    ) values (
      v_id, v_l.produit_id, v_prod.nom, v_l.quantite, v_prix,
      round((v_l.quantite * v_prix)::numeric, 2)
    );

    v_total := v_total + round((v_l.quantite * v_prix)::numeric, 2);
  end loop;

  v_paye := coalesce(p_montant_paye, v_total);
  if v_paye < 0 or v_paye > v_total + 0.009 then
    raise exception 'MONTANT_INVALIDE|Le montant reçu doit être compris entre 0 et le total.';
  end if;

  update public.dist_ventes
     set total = v_total,
         montant_paye = v_paye,
         credit = v_total - v_paye
   where id = v_id;

  perform public.dist_journaliser(v_owner, 'VENTE_DISTRIBUTION',
    'dist_ventes', v_id,
    jsonb_build_object('numero', v_num, 'total', v_total,
                       'paye', v_paye, 'credit', v_total - v_paye,
                       'commercial_id', v_commercial,
                       'type_operation', v_type));

  return public.dist_facture_json(v_id);
end;
$$;

comment on function public.dist_vente_enregistrer(uuid, jsonb, numeric, text, text, text)
  is 'Module 24 §9 — vente du commercial ; prix résolu par la grille tarifaire puis le catalogue, figé sur la ligne.';

-- -----------------------------------------------------------------------------
-- 3. Privilèges (les deux signatures coexistent : on couvre les deux)
-- -----------------------------------------------------------------------------
revoke all on function public.dist_vente_enregistrer(uuid, jsonb, numeric, text, text, text)
  from public, anon;
grant execute on function public.dist_vente_enregistrer(uuid, jsonb, numeric, text, text, text)
  to authenticated;

-- L'ancienne signature en 5 paramètres est supprimée : un appel à 5 arguments
-- résout désormais la fonction à 6 paramètres (valeur par défaut).
drop function if exists public.dist_vente_enregistrer(uuid, jsonb, numeric, text, text);

-- =============================================================================
-- FIN — la grille tarifaire s'applique en caisse
-- =============================================================================
