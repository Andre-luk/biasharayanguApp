-- ============================================================================
--  biashara_yangu — MODULE 31 : VENDRE UN ARTICLE SANS SUIVI DE STOCK
--  ---------------------------------------------------------------------------
--  CE QUE LE PROPRIÉTAIRE DEMANDE
--    « Il y a des produits qui ne peuvent pas être comptés. Je dois pouvoir
--      activer "vendable sans stock" et vendre normalement. »
--
--  CE QUI EXISTAIT DÉJÀ
--    `produits.stock_illimite` (Module 23) était utilisé par la vente rapide
--    et les tableaux de bord, mais NI la caisse, NI le scanner, NI le serveur
--    ne le respectaient : un article non comptable (quantité 0) était refusé
--    avec « Stock insuffisant ».
--
--  CE QUE CE SCRIPT CORRIGE
--    `rpc_vente_valider` ne contrôle plus le stock quand l'article porte
--    `stock_illimite = true`. Tout le reste est INCHANGÉ : prix, remises,
--    cadeaux, numérotation, journal d'audit.
--
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

create or replace function public.rpc_vente_valider(
  p_lignes             jsonb,
  p_mode_paiement      text default 'especes',
  p_montant_recu       numeric default null,
  p_numero_transaction text default null,
  p_client_id          bigint default null,
  p_remise             numeric default 0,
  p_remise_type        text default null,
  p_cadeaux            jsonb default null,
  p_reference_locale   text default null
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
  -- ⚠️ `v_cond` est un `record` : on ne le LIT JAMAIS directement dans une
  -- expression (plpgsql lie ses champs AVANT d'exécuter l'expression, même
  -- dans une branche `case` non prise → « record "v_cond" is not assigned
  -- yet »). On recopie donc son libellé dans un texte, systématiquement.
  v_cond        record;
  v_cond_libelle text;
  v_qte_base    numeric;
  v_qte_vendue  numeric;
  v_prix_unit   numeric;
  v_prix_ligne  numeric;
  v_total       numeric := 0;
  v_total_cat   numeric := 0;
  v_negociation numeric := 0;
  v_lignes_retour jsonb := '[]'::jsonb;

  -- Module 25
  v_param       jsonb;
  v_neg_activee boolean := false;
  v_neg_max_pct numeric := 0;
  v_neg_prix_min numeric;
  v_neg_collabs jsonb := '[]'::jsonb;
  v_red_activee boolean := false;
  v_red_max_pct numeric := 0;
  v_red_max_montant numeric;
  v_red_collabs jsonb := '[]'::jsonb;
  v_cad_actifs  boolean := false;
  v_cad_collabs jsonb := '[]'::jsonb;
  v_bonus_auto  jsonb := '[]'::jsonb;
  v_auto        jsonb := '[]'::jsonb;
  v_regle       jsonb;
  v_valid_seuil numeric;
  v_est_patron  boolean;
  v_prix_nego   numeric;
  v_prix_cat    numeric;
  v_ecart       numeric;
  v_remise      numeric := 0;
  v_remise_type text;
  v_remise_taux numeric;
  v_cadeaux_in  jsonb := coalesce(p_cadeaux, '[]'::jsonb);
  v_cadeau      jsonb;
  v_cadeau_qte  numeric;
  v_cadeau_base numeric;
  v_cadeau_prix numeric;
  v_cadeau_val  numeric := 0;
  v_cadeau_cout numeric := 0;
  v_cadeau_cout_ligne numeric;
  v_cadeaux_retour jsonb := '[]'::jsonb;
  v_cout_cadeaux_complet boolean := true;
  v_reference   text := nullif(btrim(coalesce(p_reference_locale, '')), '');
  v_deja        record;
  v_validation  boolean := false;
begin
  -- 0. IDEMPOTENCE HORS LIGNE -------------------------------------------
  --  Une vente rejouée (réponse perdue, synchronisation relancée) ne doit
  --  jamais créer une deuxième vente, ni une deuxième sortie de stock.
  if v_reference is not null then
    select v2.numero_vente, v2.vente_uuid into v_deja
      from public.ventes v2
     where v2.reference_locale = v_reference
       and v2.owner_id = coalesce(public.mon_proprietaire(), auth.uid())
     limit 1;
    if found then
      return jsonb_build_object(
        'numero_vente',  v_deja.numero_vente,
        'vente_uuid',    v_deja.vente_uuid,
        'deja_enregistree', true,
        'total', (select coalesce(sum(x.prix), 0) from public.ventes x
                   where x.vente_uuid = v_deja.vente_uuid),
        'mode_paiement', v_mode,
        'date', now(),
        'lignes', coalesce((
          select jsonb_agg(jsonb_build_object(
                   'produit_id',    x.produit_id,
                   'nom',           p.nom,
                   'quantite_vendue', x.quantite,
                   'quantite_base', x.quantite,
                   'prix_unitaire', case when x.quantite > 0
                                         then round(x.prix / x.quantite, 2)
                                         else x.prix end,
                   'prix_catalogue', x.prix_catalogue,
                   'prix_negocie',  x.prix_negocie,
                   'total',         x.prix
                 ))
            from public.ventes x
            left join public.produits p on p.id = x.produit_id
           where x.vente_uuid = v_deja.vente_uuid
        ), '[]'::jsonb)
      );
    end if;
  end if;

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

  -- 1.c Réglages de la boutique -----------------------------------------
  select to_jsonb(p) into v_param
    from public.parametres_vente p
   where p.owner_id = v_owner;

  if v_param is null then
    -- Aucun réglage : négociation, réduction et cadeaux sont DÉSACTIVÉS.
    v_param := '{}'::jsonb;
  end if;

  v_neg_activee := coalesce((v_param->>'negociation_activee')::boolean, false);
  v_neg_max_pct := coalesce((v_param->>'negociation_max_pct')::numeric, 0);
  v_neg_prix_min := nullif(v_param->>'negociation_prix_min', '')::numeric;
  v_neg_collabs := coalesce(v_param->'negociation_collaborateurs', '[]'::jsonb);
  v_red_activee := coalesce((v_param->>'reduction_activee')::boolean, false);
  v_red_max_pct := coalesce((v_param->>'reduction_max_pct')::numeric, 0);
  v_red_max_montant := nullif(v_param->>'reduction_max_montant', '')::numeric;
  v_red_collabs := coalesce(v_param->'reduction_collaborateurs', '[]'::jsonb);
  v_cad_actifs := coalesce((v_param->>'cadeaux_actifs')::boolean, false);
  v_cad_collabs := coalesce(v_param->'cadeau_collaborateurs', '[]'::jsonb);
  v_bonus_auto := coalesce(v_param->'bonus_auto', '[]'::jsonb);
  v_valid_seuil := nullif(v_param->>'validation_seuil', '')::numeric;
  v_est_patron := (v_user = v_owner) or public.est_plateforme();

  -- 2 et 3. Vérification du stock (sous verrou) et relecture des prix ----
  --  On verrouille AUSSI les produits offerts : un cadeau consomme du stock.
  perform p.id
     from public.produits p
    where p.id in (
      select distinct (l->>'produit_id')::bigint
        from jsonb_array_elements(p_lignes) as l
      union
      select distinct (c->>'produit_id')::bigint
        from jsonb_array_elements(
               case when jsonb_typeof(v_cadeaux_in) = 'array'
                    then v_cadeaux_in else '[]'::jsonb end
             ) as c
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
           p.unite_mesure, p.prix_achat,
           -- ♾️ MODULE 31 — article vendu SANS suivi de stock.
           coalesce(p.stock_illimite, false) as stock_illimite
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

    -- ♾️ MODULE 31 — un article NON COMPTABLE (eau au robinet, service,
    --  fabrication à la demande) se vend toujours : aucun contrôle de stock.
    if not coalesce(v_produit.stock_illimite, false)
       and coalesce(v_produit.quantite, 0) < v_qte_base then
      raise exception 'STOCK_INSUFFISANT|Stock insuffisant pour % : % disponible(s), % demandé(s).',
        v_produit.nom, v_produit.quantite, v_qte_base;
    end if;

    -- Prix de référence : conditionnement (Module 5) ou unité de base.
    v_cond_id := nullif(v_ligne->>'conditionnement_id', '')::uuid;
    v_prix_unit := v_produit.prix_vente;
    v_cond_libelle := null;

    if v_cond_id is not null then
      select c.id, c.libelle, c.quantite_unites_base, c.prix_vente
        into v_cond
        from public.conditionnements c
       where c.id = v_cond_id
         and c.produit_id = v_produit_id;

      if not found then
        raise exception 'CONDITIONNEMENT_INVALIDE|Le conditionnement choisi pour % n''existe plus.', v_produit.nom;
      end if;

      v_cond_libelle := v_cond.libelle;
      v_prix_unit := v_cond.prix_vente;
    end if;

    v_prix_cat := round(v_prix_unit * v_qte_vendue, 2);

    -- 🔻 MODULE 25 — NÉGOCIATION DU PRIX DE LA LIGNE ---------------------
    --  Le prix catalogue reste intact : on n'écrit que le prix accepté.
    v_prix_nego := null;
    if v_ligne ? 'prix_negocie'
       and nullif(v_ligne->>'prix_negocie', '') is not null then
      v_prix_nego := (v_ligne->>'prix_negocie')::numeric;

      if v_prix_nego <= 0 then
        raise exception 'NEGOCIATION_HORS_LIMITE|Le prix négocié de % doit être supérieur à zéro.', v_produit.nom;
      end if;

      -- Prix identique au catalogue = pas une négociation (on ignore).
      if round(v_prix_nego, 2) = round(v_prix_unit, 2) then
        v_prix_nego := null;
      else
        -- Négociation vers le haut : jamais acceptée (c'est une erreur).
        if v_prix_nego > v_prix_unit then
          raise exception 'NEGOCIATION_HORS_LIMITE|Le prix négocié de % (%) dépasse le prix catalogue (%).',
            v_produit.nom, v_prix_nego, v_prix_unit;
        end if;

        if not v_neg_activee then
          raise exception 'NEGOCIATION_INTERDITE|La négociation des prix est désactivée pour votre boutique.';
        end if;

        if not v_est_patron
           and jsonb_array_length(v_neg_collabs) > 0
           and not (v_neg_collabs ? (v_user::text)) then
          raise exception 'NEGOCIATION_INTERDITE|Votre compte n''est pas autorisé à négocier les prix.';
        end if;

        v_ecart := round(((v_prix_unit - v_prix_nego) / nullif(v_prix_unit, 0)) * 100, 2);
        if not v_est_patron
           and v_ecart > v_neg_max_pct + 0.001 then
          raise exception 'NEGOCIATION_HORS_LIMITE|Remise négociée de % %% sur % : la limite est de % %%.',
            v_ecart, v_produit.nom, coalesce(v_neg_max_pct, 0);
        end if;

        if v_neg_prix_min is not null
           and v_prix_nego < v_neg_prix_min - 0.001
           and not v_est_patron then
          raise exception 'NEGOCIATION_HORS_LIMITE|Prix minimum autorisé pour % : %.',
            v_produit.nom, v_neg_prix_min;
        end if;

        v_prix_ligne := round(v_prix_nego * v_qte_vendue, 2);
        v_negociation := v_negociation + (v_prix_cat - v_prix_ligne);
      end if;
    end if;

    if v_prix_nego is null then
      v_prix_ligne := v_prix_cat;
    end if;

    v_total := v_total + v_prix_ligne;
    v_total_cat := v_total_cat + v_prix_cat;

    -- Ligne insérée dans `ventes` : le trigger du stock retire `v_qte_base`.
    insert into public.ventes (
      produit_id, quantite, prix, mode_paiement, date,
      owner_id, seller_id, client_id, conditionnement_id,
      numero_vente, vente_uuid,
      prix_catalogue, prix_negocie, est_cadeau, reference_locale
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
      v_vente_uuid,
      v_prix_cat,
      v_prix_nego,
      false,
      v_reference
    );

    -- La clé d'idempotence n'est écrite qu'une fois, sur la première ligne.
    if v_reference is not null then
      v_reference := null;
    end if;

    v_lignes_retour := v_lignes_retour || jsonb_build_object(
      'produit_id',      v_produit_id,
      'nom',             v_produit.nom,
      'conditionnement', v_cond_libelle,
      'unite',           coalesce(v_cond_libelle, v_produit.unite_mesure),
      'quantite_vendue', v_qte_vendue,
      'quantite_base',   v_qte_base,
      'prix_unitaire',   coalesce(v_prix_nego, v_prix_unit),
      'prix_catalogue',  v_prix_cat,
      'prix_negocie',    v_prix_nego,
      'total',           v_prix_ligne
    );
  end loop;

  -- 🎁 MODULE 25 — CADEAUX COMMERCIAUX ------------------------------------
  --  Un cadeau est une ligne de vente à 0 : le stock sort réellement, la
  --  caisse n'encaisse rien et le chiffre d'affaires ne bouge pas.

  --  BONUS AUTOMATIQUES : le propriétaire peut attacher un cadeau à un seuil
  --  d'achat. Chaque règle ne s'applique qu'UNE fois par vente — un client ne
  --  peut donc pas recevoir deux fois le même bonus.
  if v_cad_actifs and jsonb_typeof(v_bonus_auto) = 'array' then
    for v_regle in select * from jsonb_array_elements(v_bonus_auto)
    loop
      if coalesce((v_regle->>'actif')::boolean, true)
         and coalesce((v_regle->>'produit_id')::bigint, 0) > 0
         and v_total >= coalesce((v_regle->>'seuil_montant')::numeric, 0) then
        v_auto := v_auto || jsonb_build_object(
          'produit_id', coalesce((v_regle->>'produit_id')::bigint, 0),
          'quantite', greatest(coalesce((v_regle->>'quantite')::numeric, 1), 1),
          'source', 'auto',
          'regle_seuil', coalesce((v_regle->>'seuil_montant')::numeric, 0)
        );
      end if;
    end loop;

    if jsonb_array_length(v_auto) > 0 then
      v_cadeaux_in := coalesce(v_cadeaux_in, '[]'::jsonb) || v_auto;
    end if;
  end if;

  if jsonb_typeof(v_cadeaux_in) = 'array'
     and jsonb_array_length(v_cadeaux_in) > 0 then

    -- Les contrôles d'autorisation ne concernent que les cadeaux CHOISIS par
    -- le vendeur : un bonus automatique est décidé par le propriétaire, il
    -- s'applique donc sans liste blanche.
    if jsonb_typeof(coalesce(p_cadeaux, '[]'::jsonb)) = 'array'
       and jsonb_array_length(coalesce(p_cadeaux, '[]'::jsonb)) > 0 then

      if not v_cad_actifs then
        raise exception 'CADEAU_INTERDIT|Les cadeaux commerciaux sont désactivés pour votre boutique.';
      end if;

      if not v_est_patron
         and jsonb_array_length(v_cad_collabs) > 0
         and not (v_cad_collabs ? (v_user::text)) then
        raise exception 'CADEAU_INTERDIT|Votre compte n''est pas autorisé à offrir un produit.';
      end if;
    end if;

    for v_cadeau in select * from jsonb_array_elements(v_cadeaux_in)
    loop
      v_produit_id := nullif(v_cadeau->>'produit_id', '')::bigint;
      v_cadeau_qte := coalesce((v_cadeau->>'quantite')::numeric, 1);
      if v_produit_id is null or v_cadeau_qte <= 0 then
        raise exception 'LIGNE_INVALIDE|Un cadeau a une quantité invalide.';
      end if;

      select p.id, p.nom, p.owner_id, p.quantite, p.prix_vente,
             p.unite_mesure, p.prix_achat
        into v_produit
        from public.produits p
       where p.id = v_produit_id
         for update;

      if not found then
        raise exception 'PRODUIT_INTROUVABLE|Article offert n° % introuvable.', v_produit_id;
      end if;

      if v_produit.owner_id is distinct from v_owner and not public.est_plateforme() then
        raise exception 'HORS_BOUTIQUE|L''article offert % n''appartient pas à votre boutique.', v_produit.nom;
      end if;

      v_cond_id := nullif(v_cadeau->>'conditionnement_id', '')::uuid;
      v_cadeau_base := v_cadeau_qte;
      v_cadeau_prix := coalesce(v_produit.prix_vente, 0);
      v_cond_libelle := null;

      if v_cond_id is not null then
        select c.id, c.libelle, c.quantite_unites_base, c.prix_vente
          into v_cond
          from public.conditionnements c
         where c.id = v_cond_id and c.produit_id = v_produit_id;
        if not found then
          raise exception 'CONDITIONNEMENT_INVALIDE|Le conditionnement offert pour % n''existe plus.', v_produit.nom;
        end if;
        v_cond_libelle := v_cond.libelle;
        v_cadeau_base := v_cadeau_qte * coalesce(v_cond.quantite_unites_base, 1);
        v_cadeau_prix := coalesce(v_cond.prix_vente, v_cadeau_prix);
      else
        v_cadeau_base := coalesce((v_cadeau->>'quantite_base')::numeric, v_cadeau_qte);
      end if;

      if coalesce(v_produit.quantite, 0) < v_cadeau_base then
        raise exception 'CADEAU_STOCK|Impossible d''offrir % : % en stock, % demandé(s).',
          v_produit.nom, v_produit.quantite, v_cadeau_base;
      end if;

      -- Valeur au prix catalogue (ce que le cadeau aurait coûté au client).
      v_cadeau_val := v_cadeau_val + round(v_cadeau_prix * v_cadeau_qte, 2);
      -- Coût réel, seulement s'il est connu : sinon on ne l'invente pas.
      v_cadeau_cout_ligne := null;
      if coalesce(v_produit.prix_achat, 0) > 0 then
        v_cadeau_cout_ligne := round(v_produit.prix_achat * v_cadeau_base, 2);
        v_cadeau_cout := coalesce(v_cadeau_cout, 0) + v_cadeau_cout_ligne;
      else
        -- Un seul cadeau sans prix d'achat suffit à rendre le coût inconnu.
        v_cout_cadeaux_complet := false;
      end if;

      insert into public.ventes (
        produit_id, quantite, prix, mode_paiement, date,
        owner_id, seller_id, client_id, conditionnement_id,
        numero_vente, vente_uuid,
        prix_catalogue, prix_negocie, est_cadeau, reference_locale
      ) values (
        v_produit_id,
        v_cadeau_base,
        0,
        v_mode,
        now(),
        v_owner,
        v_user,
        p_client_id,
        v_cond_id,
        null,
        v_vente_uuid,
        round(v_cadeau_prix * v_cadeau_qte, 2),
        null,
        true,
        null
      );

      v_cadeaux_retour := v_cadeaux_retour || jsonb_build_object(
        'produit_id',     v_produit_id,
        'nom',            v_produit.nom,
        'conditionnement', v_cond_libelle,
        'quantite',       v_cadeau_qte,
        'quantite_base',  v_cadeau_base,
        'valeur',         round(v_cadeau_prix * v_cadeau_qte, 2),
        'cout',           v_cadeau_cout_ligne,
        'source',         coalesce(v_cadeau->>'source', 'manuel')
      );
    end loop;
  end if;

  -- 🔻 MODULE 25 — RÉDUCTION SUR LE TOTAL DU PANIER -----------------------
  v_remise_type := lower(btrim(coalesce(p_remise_type, 'montant')));
  if v_remise_type not in ('montant', 'pourcentage') then
    raise exception 'VALEUR_INVALIDE|Type de réduction inconnu : utilisez « montant » ou « pourcentage ».';
  end if;

  if coalesce(p_remise, 0) < 0 then
    raise exception 'REMISE_HORS_LIMITE|Une réduction ne peut pas être négative.';
  end if;

  if coalesce(p_remise, 0) > 0 then
    if not v_red_activee then
      raise exception 'REMISE_INTERDITE|Les réductions sont désactivées pour votre boutique.';
    end if;

    if not v_est_patron
       and jsonb_array_length(v_red_collabs) > 0
       and not (v_red_collabs ? (v_user::text)) then
      raise exception 'REMISE_INTERDITE|Votre compte n''est pas autorisé à accorder une réduction.';
    end if;

    if v_remise_type = 'pourcentage' then
      if p_remise > 100 then
        raise exception 'REMISE_HORS_LIMITE|Une réduction en pourcentage ne peut pas dépasser 100 %%.';
      end if;
      if not v_est_patron
         and p_remise > v_red_max_pct + 0.001 then
        raise exception 'REMISE_HORS_LIMITE|Réduction de % %% : la limite est de % %%.',
          p_remise, coalesce(v_red_max_pct, 0);
      end if;
      v_remise_taux := p_remise;
      v_remise := round(v_total * p_remise / 100, 2);
    else
      v_remise := round(p_remise, 2);
      v_remise_taux := case when v_total > 0
                            then round(v_remise / v_total * 100, 2)
                            else 0 end;
      if not v_est_patron
         and v_remise_taux > v_red_max_pct + 0.001 then
        raise exception 'REMISE_HORS_LIMITE|Réduction de % %% : la limite est de % %%.',
          v_remise_taux, coalesce(v_red_max_pct, 0);
      end if;
    end if;

    if v_red_max_montant is not null
       and not v_est_patron
       and v_remise > v_red_max_montant + 0.001 then
      raise exception 'REMISE_HORS_LIMITE|Réduction de % : le plafond est de %.',
        v_remise, v_red_max_montant;
    end if;

    if v_remise > v_total + 0.001 then
      raise exception 'REMISE_HORS_LIMITE|La réduction (%) dépasse le total du panier (%).',
        v_remise, v_total;
    end if;
  end if;

  -- Seuil de validation du responsable : au-delà, le collaborateur ne peut
  -- pas conclure seul la vente.
  if v_valid_seuil is not null
     and v_valid_seuil > 0
     and (v_remise + v_negociation) > v_valid_seuil + 0.001 then
    v_validation := true;
    if not v_est_patron then
      raise exception 'VALIDATION_REQUISE|Remise totale de % (négociation + réduction) : au-delà de % le responsable doit valider.',
        round(v_remise + v_negociation, 2), v_valid_seuil;
    end if;
  end if;

  v_total := greatest(round(v_total - v_remise, 2), 0);

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
    montant_total, mode_paiement, montant_recu, rendu, numero_transaction,
    montant_initial, remise_montant, remise_type, remise_taux
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
    p_numero_transaction,
    v_total_cat,
    v_remise,
    case when v_remise > 0 then v_remise_type else null end,
    case when v_remise > 0 then v_remise_taux else null end
  );

  -- 5.b Trace de la flexibilité commerciale ------------------------------
  if v_negociation > 0 or v_remise > 0
     or jsonb_array_length(v_cadeaux_retour) > 0 then
    insert into public.ventes_flexibilite (
      vente_uuid, owner_id, seller_id, numero_vente,
      total_initial, montant_negociation, remise_montant, remise_type,
      remise_taux, valeur_cadeaux, cout_cadeaux, cout_complet, cadeaux,
      total_final, validation_requise, date
    ) values (
      v_vente_uuid, v_owner, v_user, v_numero,
      v_total_cat, round(v_negociation, 2), v_remise,
      case when v_remise > 0 then v_remise_type else null end,
      case when v_remise > 0 then v_remise_taux else null end,
      round(v_cadeau_val, 2), v_cadeau_cout, v_cout_cadeaux_complet,
      v_cadeaux_retour,
      v_total, v_validation, now()
    )
    on conflict (vente_uuid) do nothing;
  end if;

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
      'total_catalogue', v_total_cat,
      'negociation',   round(v_negociation, 2),
      'remise',        v_remise,
      'cadeaux',       jsonb_array_length(v_cadeaux_retour),
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
    'total_initial', v_total_cat,
    'negociation',   round(v_negociation, 2),
    'remise',        v_remise,
    'remise_type',   case when v_remise > 0 then v_remise_type else null end,
    'valeur_cadeaux', round(v_cadeau_val, 2),
    'cadeaux',       v_cadeaux_retour,
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

comment on function public.rpc_vente_valider is
  'Modules 25 + 27 + 31 — vente atomique : prix catalogue/négocié, cadeaux, stock non suivi (stock_illimite) jamais bloqué.';

revoke all on function public.rpc_vente_valider from public, anon;
grant execute on function public.rpc_vente_valider to authenticated;


-- ============================================================================
--  VÉRIFICATION
-- ============================================================================

select p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'rpc_vente_valider';
