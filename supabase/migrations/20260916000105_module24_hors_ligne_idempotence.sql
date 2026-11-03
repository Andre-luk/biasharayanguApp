-- =============================================================================
-- MODULE 24 — HORS-LIGNE : IDEMPOTENCE DES OPÉRATIONS (0105)
-- =============================================================================
-- Le commercial peut désormais vendre sans réseau (§12 du cahier des charges).
-- Les opérations sont rejouées à la reconnexion ; il faut donc que le serveur
-- sache reconnaître une opération DÉJÀ appliquée, sinon un simple timeout
-- (réponse perdue) créerait une seconde vente et débiterait deux fois le stock.
--
-- Ce script ajoute une RÉFÉRENCE LOCALE (UUID généré sur le téléphone) :
--   • `dist_ventes.reference_locale`     — unique par entreprise ;
--   • `dist_bonus_dommages.reference_locale` — idem ;
-- et fait en sorte que les RPC correspondantes, si l'opération existe déjà,
-- RENVOIENT le résultat existant au lieu de la recréer.
--
-- Aucune donnée existante n'est modifiée : les colonnes sont nullables et les
-- index sont partiels (`where ... is not null`).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Colonnes et index d'unicité
-- -----------------------------------------------------------------------------
alter table public.dist_ventes
  add column if not exists reference_locale text;

create unique index if not exists dist_ventes_ref_locale_uidx
  on public.dist_ventes (owner_id, reference_locale)
  where reference_locale is not null;

comment on column public.dist_ventes.reference_locale is
  'Module 24 §12 — identifiant unique généré hors ligne par le téléphone du commercial (idempotence de la synchronisation).';

alter table public.dist_bonus_dommages
  add column if not exists reference_locale text;

create unique index if not exists dist_bonus_ref_locale_uidx
  on public.dist_bonus_dommages (owner_id, reference_locale)
  where reference_locale is not null;

comment on column public.dist_bonus_dommages.reference_locale is
  'Module 24 §12 — identifiant unique généré hors ligne (évite un double bonus à la synchronisation).';

-- -----------------------------------------------------------------------------
-- 2. Vente idempotente
-- -----------------------------------------------------------------------------
create or replace function public.dist_vente_enregistrer(
  p_client_id       uuid,
  p_lignes          jsonb,
  p_montant_paye    numeric default null,
  p_mode            text default 'especes',
  p_note            text default null,
  p_type_operation  text default 'standard',
  p_reference_locale text default null
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
  v_exist uuid;
  v_num text;
  v_l record;
  v_prod record;
  v_total numeric(16,2) := 0;
  v_paye numeric(16,2);
  v_prix numeric(16,2);
  v_type text := lower(btrim(coalesce(p_type_operation, 'standard')));
  v_ref text := nullif(btrim(coalesce(p_reference_locale, '')), '');
  v_tarif numeric(16,2);
begin
  perform public.dist_exige(array['commercial']);

  -- ♻️ Idempotence : la même référence locale ne crée jamais deux ventes.
  if v_ref is not null then
    select id into v_exist
      from public.dist_ventes
     where owner_id = v_owner and reference_locale = v_ref;

    if v_exist is not null then
      return public.dist_facture_json(v_exist);
    end if;
  end if;

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
    type_operation, reference_locale
  ) values (
    v_owner, v_num, v_commercial, p_client_id,
    coalesce(nullif(btrim(p_mode), ''), 'especes'),
    nullif(btrim(coalesce(p_note, '')), ''),
    v_type, v_ref
  ) returning id into v_id;

  for v_l in
    select * from jsonb_to_recordset(p_lignes)
      as x(produit_id uuid, quantite numeric)
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
                       'type_operation', v_type,
                       'hors_ligne', v_ref is not null));

  return public.dist_facture_json(v_id);
end;
$$;

comment on function public.dist_vente_enregistrer(uuid, jsonb, numeric, text, text, text, text)
  is 'Module 24 §9/§12 — vente du commercial ; grille tarifaire + idempotence par référence locale.';

revoke all on function public.dist_vente_enregistrer(uuid, jsonb, numeric, text, text, text, text)
  from public, anon;
grant execute on function public.dist_vente_enregistrer(uuid, jsonb, numeric, text, text, text, text)
  to authenticated;

-- L'ancienne signature (6 paramètres) est retirée : un appel à 6 arguments
-- résout désormais la version à 7 paramètres (valeur par défaut).
drop function if exists public.dist_vente_enregistrer(uuid, jsonb, numeric, text, text, text);

-- -----------------------------------------------------------------------------
-- 3. Bonus idempotent
-- -----------------------------------------------------------------------------
create or replace function public.dist_bonus_declarer(
  p_produit      uuid,
  p_nature       text,
  p_quantite     numeric,
  p_motif        text,
  p_justificatif text default null,
  p_commercial   uuid default null,
  p_reference_locale text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner  uuid := public.dist_owner_requis();
  v_role   text := public.dist_role();
  v_nat    text := lower(btrim(coalesce(p_nature, '')));
  v_motif  text := btrim(coalesce(p_motif, ''));
  v_comm   uuid := coalesce(p_commercial, auth.uid());
  v_ref    text := nullif(btrim(coalesce(p_reference_locale, '')), '');
  v_exist  uuid;
  v_prod   record;
  v_id     uuid;
begin
  if v_role = 'aucun' then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette distribution.';
  end if;

  -- ♻️ Idempotence : une même déclaration hors ligne n'est jamais doublée.
  if v_ref is not null then
    select id into v_exist
      from public.dist_bonus_dommages
     where owner_id = v_owner and reference_locale = v_ref;

    if v_exist is not null then
      return jsonb_build_object('ok', true, 'id', v_exist,
                                'statut', 'en_attente', 'deja', true);
    end if;
  end if;

  -- Un commercial ne déclare que pour lui-même ; la direction pour autrui.
  if v_comm <> auth.uid()
     and v_role not in ('proprietaire', 'gerant') then
    raise exception 'DROIT_REFUSE|Vous ne pouvez déclarer que pour vous-même.';
  end if;

  if v_nat not in ('bonus', 'endommage', 'casse', 'perdu') then
    raise exception 'NATURE_INVALIDE|Précisez : bonus, endommagé, cassé ou perdu.';
  end if;

  if p_quantite is null or p_quantite <= 0 then
    raise exception 'QUANTITE_INVALIDE|La quantité doit être supérieure à zéro.';
  end if;

  if length(v_motif) < 3 then
    raise exception 'MOTIF_REQUIS|Indiquez le motif (3 caractères minimum).';
  end if;

  select * into v_prod from public.dist_produits
   where id = p_produit and owner_id = v_owner;
  if v_prod.id is null then
    raise exception 'PRODUIT_INCONNU|Ce produit fini n''existe pas.';
  end if;

  insert into public.dist_bonus_dommages (
    owner_id, commercial_id, produit_id, nom_produit, nature,
    quantite, prix_unitaire, valeur, motif, justificatif, declare_par,
    reference_locale
  ) values (
    v_owner, v_comm, v_prod.id, v_prod.nom, v_nat,
    p_quantite, coalesce(v_prod.prix_vente, 0),
    round(p_quantite * coalesce(v_prod.prix_vente, 0), 2),
    v_motif, nullif(btrim(coalesce(p_justificatif, '')), ''), auth.uid(),
    v_ref
  )
  returning id into v_id;

  perform public.dist_journaliser(v_owner, 'BONUS_DECLARE', 'dist_bonus_dommages', v_id,
    jsonb_build_object('nature', v_nat, 'produit', v_prod.nom,
                       'quantite', p_quantite, 'commercial', v_comm,
                       'hors_ligne', v_ref is not null));

  return jsonb_build_object('ok', true, 'id', v_id, 'statut', 'en_attente');
end;
$$;

comment on function public.dist_bonus_declarer(uuid, text, numeric, text, text, uuid, text)
  is 'Module 24 §10/§12 — déclare un bonus/dommage ; idempotent par référence locale.';

revoke all on function public.dist_bonus_declarer(uuid, text, numeric, text, text, uuid, text)
  from public, anon;
grant execute on function public.dist_bonus_declarer(uuid, text, numeric, text, text, uuid, text)
  to authenticated;

drop function if exists public.dist_bonus_declarer(uuid, text, numeric, text, text, uuid);

-- =============================================================================
-- FIN — idempotence de la synchronisation hors ligne
-- =============================================================================
