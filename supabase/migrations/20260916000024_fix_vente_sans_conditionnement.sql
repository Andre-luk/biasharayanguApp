-- ============================================================================
--  biashara_yangu — CORRECTIF 24 : VENTE QUI PLANTE SANS CONDITIONNEMENT
--  (erreur « record "v_cond" is not assigned yet » / 55000)
--
--  PROBLÈME (constaté le 18/09/2026 en test de bout en bout) :
--    `rpc_vente_valider` déclarait `v_cond record` (structure indéterminée)
--    et ne l'assignait QUE si la ligne vendue avait un conditionnement.
--    Or l'expression de sortie `case ... else v_cond.libelle end` référence
--    le record : PL/pgSQL doit connaître sa structure AVANT d'exécuter la
--    CASE → toute vente d'un article SANS conditionnement échouait avec :
--      « The tuple structure of a not-yet-assigned record is indeterminate.
--         record "v_cond" is not assigned yet ».
--
--  CORRECTIF :
--    `v_cond public.conditionnements%rowtype` — la structure est connue dès
--    la déclaration (champs NULL tant que non assigné) — et le chargement
--    devient `select c.* into v_cond`. La vente d'articles sans
--    conditionnement passe désormais normalement.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================


create or replace function public.rpc_vente_valider(
  p_lignes             jsonb,
  p_mode_paiement      text default 'especes',
  p_montant_recu       numeric default null,
  p_numero_transaction text default null,
  p_client_id          bigint default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user        uuid := auth.uid();
  v_owner       uuid;
  v_mode        text := coalesce(nullif(btrim(lower(coalesce(p_mode_paiement, ''))), ''), 'especes');
  v_numero      text;
  v_vente_uuid  uuid := gen_random_uuid();
  v_ligne       jsonb;
  v_produit_id  bigint;
  v_produit     record;
  v_cond_id     uuid;
  v_cond        public.conditionnements%rowtype;
  v_qte_base    numeric;
  v_qte_vendue  numeric;
  v_prix_unit   numeric;
  v_prix_ligne  numeric;
  v_total       numeric := 0;
  v_lignes_retour jsonb := '[]'::jsonb;
begin
  -- 1.a Session et rôle ------------------------------------------------
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour encaisser.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not (public.peut('caisse', 'creer') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''encaisser une vente.';
  end if;

  -- 1.b Panier -----------------------------------------------------------
  if p_lignes is null
     or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'PANIER_VIDE|Le panier est vide : ajoutez au moins un article.';
  end if;

  -- 2 et 3. Vérification du stock (sous verrou) et relecture des prix ----
  --  D'abord : verrouillage de TOUS les articles du panier, dans un ordre
  --  stable (ids croissants). Deux encaissements simultanés ne peuvent donc
  --  jamais s'interbloquer, et le stock lu reste figé jusqu'au commit.
  perform p.id
     from public.produits p
    where p.id in (
      select distinct (l->>'produit_id')::bigint
        from jsonb_array_elements(p_lignes) as l
    )
    order by p.id
      for update;

  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_produit_id := nullif(v_ligne->>'produit_id', '')::bigint;
    if v_produit_id is null then
      raise exception 'LIGNE_INVALIDE|Une ligne du panier n''a pas d''article.';
    end if;

    v_qte_base := coalesce((v_ligne->>'quantite')::numeric, 0);
    if v_qte_base <= 0 then
      raise exception 'LIGNE_INVALIDE|Quantité invalide pour l''article %.', v_produit_id;
    end if;

    v_qte_vendue := coalesce((v_ligne->>'quantite_vendue')::numeric, v_qte_base);

    -- Verrou : toute vente concurrente sur le même article attend ici.
    select p.id, p.nom, p.owner_id, p.quantite, p.prix_vente,
           p.unite_mesure
      into v_produit
      from public.produits p
     where p.id = v_produit_id
       for update;

    if not found then
      raise exception 'PRODUIT_INTROUVABLE|Article n° % introuvable : il a peut-être été supprimé.', v_produit_id;
    end if;

    if v_produit.owner_id is distinct from v_owner
       and not public.est_plateforme() then
      raise exception 'HORS_BOUTIQUE|L''article % n''appartient pas à votre boutique.', v_produit.nom;
    end if;

    if coalesce(v_produit.quantite, 0) < v_qte_base then
      raise exception 'STOCK_INSUFFISANT|Stock insuffisant pour % : % disponible(s), % demandé(s).',
        v_produit.nom, v_produit.quantite, v_qte_base;
    end if;

    -- Prix de référence : conditionnement (Module 5) ou unité de base.
    v_cond_id := nullif(v_ligne->>'conditionnement_id', '')::uuid;
    v_prix_unit := v_produit.prix_vente;

    if v_cond_id is not null then
      select c.*
        into v_cond
        from public.conditionnements c
       where c.id = v_cond_id
         and c.produit_id = v_produit_id;

      if not found then
        raise exception 'CONDITIONNEMENT_INVALIDE|Le conditionnement choisi pour % n''existe plus.', v_produit.nom;
      end if;

      v_prix_unit := v_cond.prix_vente;
    end if;

    v_prix_ligne := round(v_prix_unit * v_qte_vendue, 2);
    v_total := v_total + v_prix_ligne;

    -- Ligne insérée dans `ventes` : le trigger du stock retire `v_qte_base`.
    insert into public.ventes (
      produit_id, quantite, prix, mode_paiement, date,
      owner_id, seller_id, client_id, conditionnement_id,
      numero_vente, vente_uuid
    ) values (
      v_produit_id,
      v_qte_base,
      v_prix_ligne,
      v_mode,
      now(),
      v_owner,
      v_user,
      p_client_id,
      v_cond_id,
      null,          -- numéro attribué juste après (une seule fois)
      v_vente_uuid
    );

    v_lignes_retour := v_lignes_retour || jsonb_build_object(
      'produit_id',      v_produit_id,
      'nom',             v_produit.nom,
      'conditionnement', case when v_cond_id is null then null else v_cond.libelle end,
      'unite',           case when v_cond_id is null then v_produit.unite_mesure else v_cond.libelle end,
      'quantite_vendue', v_qte_vendue,
      'quantite_base',   v_qte_base,
      'prix_unitaire',   v_prix_unit,
      'total',           v_prix_ligne
    );
  end loop;

  -- 4. Numéro de vente unique (compteur journalier par boutique) ---------
  v_numero := public.prochain_numero_vente(v_owner);

  -- Le numéro n'est écrit qu'une fois toutes les lignes validées.
  update public.ventes
     set numero_vente = v_numero
   where vente_uuid = v_vente_uuid
     and numero_vente is null;

  -- 4.b Contrôle du montant reçu (espèces) AVANT l'encaissement.
  if v_mode = 'especes'
     and p_montant_recu is not null
     and p_montant_recu < v_total then
    raise exception 'MONTANT_INSUFFISANT|Montant reçu insuffisant : % attendu, % reçu.',
      v_total, p_montant_recu;
  end if;

  -- 5. Encaissement (caisse) ---------------------------------------------
  insert into public.caisse (
    vente_uuid, numero_vente, owner_id, seller_id, client_id,
    montant_total, mode_paiement, montant_recu, rendu, numero_transaction
  ) values (
    v_vente_uuid,
    v_numero,
    v_owner,
    v_user,
    p_client_id,
    v_total,
    v_mode,
    p_montant_recu,
    case
      when p_montant_recu is null then null
      else greatest(round(p_montant_recu - v_total, 2), 0)
    end,
    p_numero_transaction
  );

  -- 6. Journal d'audit -----------------------------------------------------
  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    null,
    'VENTE',
    v_user,
    jsonb_build_object(
      'numero_vente',  v_numero,
      'vente_uuid',    v_vente_uuid,
      'boutique',      v_owner,
      'total',         v_total,
      'mode_paiement', v_mode,
      'nb_lignes',     jsonb_array_length(p_lignes)
    ),
    now()
  );

  -- 7. Récapitulatif renvoyé à l'application -------------------------------
  return jsonb_build_object(
    'numero_vente',  v_numero,
    'vente_uuid',    v_vente_uuid,
    'total',         v_total,
    'mode_paiement', v_mode,
    'montant_recu',  p_montant_recu,
    'rendu', case
      when p_montant_recu is null then null
      else greatest(round(p_montant_recu - v_total, 2), 0)
    end,
    'date',   now(),
    'lignes', v_lignes_retour
  );
end;
$$;

revoke all on function public.rpc_vente_valider(jsonb, text, numeric, text, bigint) from public;
revoke all on function public.rpc_vente_valider(jsonb, text, numeric, text, bigint) from anon;
grant execute on function public.rpc_vente_valider(jsonb, text, numeric, text, bigint) to authenticated;
