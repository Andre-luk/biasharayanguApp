-- ============================================================================
--  biashara_yangu — PHASE 8 : LE RAPPORT DE TOURNÉE IMPRIMABLE
--  ---------------------------------------------------------------------------
--  La question du patron d'une entreprise de distribution :
--
--    « L'agent a emmené 200 bouteilles mardi. Il en a vendu 150, en a rendu
--      30, il en manque 20. On a produit 500 ce jour-là. Où est écrit tout
--      ça, sur UNE feuille que je peux imprimer et classer ? »
--
--  RÉPONSE : `rpc_rapport_tournee_detail` rassemble, pour une tournée :
--    • l'en-tête (référence, date, agent, zone, objectif, commission) ;
--    • la MOUVEMENT par produit : confié / vendu / rendu / offert / cassé /
--      manquant, avec la valeur du manquant ;
--    • les REÇUS de la tournée (numéro de vente, heure, montant) ;
--    • la PRODUCTION du jour (ce qui est entré en stock) ;
--    • les totaux.
--
--  ⚠️ Aucun chiffre n'est saisi : tout est relu dans les tables de faits.
--     L'écart est calculé, jamais déclaré.
--
--  ⚠️ La DOTATION ne retire rien du stock (c'est une réservation) ; le stock
--     ne baisse qu'à la VENTE (trigger du module 8). Ce que l'agent rend n'a
--     donc pas à être rajouté : il n'est jamais sorti. Le rapport le dit
--     explicitement (`stock_mouvemente = false`) pour éviter les doubles
--     entrées manuelles.
--
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'tournee_lignes'
       and column_name = 'quantite_bonus'
  ) then
    raise exception 'Migration 0085 absente : exécutez 20260916000085_tournees_commissions_controle.sql.';
  end if;
end $$;


-- ============================================================================
--  1. PROFIL DE MODULES « DISTRIBUTION » (production incluse)
-- ============================================================================
--  Une entreprise d'eau minérale PRODUIT ce qu'elle distribue. Sans le module
--  `production`, l'écran de production n'existe pas dans son espace.
--  On crée donc un type d'espace dédié ; les autres profils ne bougent pas.
insert into public.types_espaces_modules (type, libelle, modules)
values (
  'distribution',
  'Distribution (production & tournées)',
  '["ventes","produits","stock","qr","caisse","clients","finance","employes",
    "rapports","assistant_ia","distribution","production"]'::jsonb
)
on conflict (type) do nothing;


-- ============================================================================
--  2. RAPPORT DÉTAILLÉ D'UNE TOURNÉE
-- ============================================================================

create or replace function public.rpc_rapport_tournee_detail(
  p_tournee uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_owner    uuid;
  v_t        public.tournees%rowtype;
  v_societe  text;
  v_agent    text;
  v_devise   text := 'CDF';
  v_jour     date;
  v_lignes   jsonb := '[]'::jsonb;
  v_recus    jsonb := '[]'::jsonb;
  v_prods    jsonb := '[]'::jsonb;
  v_confie   numeric := 0;
  v_vendu    numeric := 0;
  v_rendu    numeric := 0;
  v_bonus    numeric := 0;
  v_casse    numeric := 0;
  v_manquant numeric := 0;
  v_valeur   numeric := 0;
  v_ca       numeric := 0;
  v_nb_recus integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter ce rapport.';
  end if;

  select * into v_t from public.tournees where id = p_tournee;
  if not found then
    raise exception 'TOURNEE_INTROUVABLE|Cette tournée n''existe plus.';
  end if;

  v_owner := v_t.owner_id;

  if not (v_user = v_t.owner_id or v_user = v_t.agent_id
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette tournée.';
  end if;

  select coalesce(e.nom, '') into v_societe
    from public.entreprises e where e.id = v_owner;
  select coalesce(e.devise, 'CDF') into v_devise
    from public.entreprises e where e.id = v_owner;
  v_devise := coalesce(v_devise, 'CDF');

  select coalesce(nullif(btrim(coalesce(u.nom, '') || ' ' || coalesce(u.prenom, '')), ''),
                  'Agent')
    into v_agent
    from public.utilisateurs u where u.id = v_t.agent_id;

  v_jour := coalesce(v_t.date_tournee, v_t.cree_le::date);

  -- ---- Mouvement par produit : le cœur du rapport -----------------------
  select coalesce(jsonb_agg(x order by x.nom), '[]'::jsonb)
    into v_lignes
    from (
      select
        l.produit_id,
        l.nom_produit as nom,
        coalesce(l.unite, '') as unite,
        l.quantite_attribuee as confie,
        l.quantite_vendue as vendu,
        l.quantite_retournee as rendu,
        l.quantite_bonus as offert,
        l.quantite_casse as casse,
        (l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
           - l.quantite_bonus - l.quantite_casse) as manquant,
        coalesce(l.prix_vente, 0) as prix_vente,
        round((l.quantite_vendue * coalesce(l.prix_vente, 0))::numeric, 2) as valeur_vendue,
        round(((l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
           - l.quantite_bonus - l.quantite_casse) * coalesce(l.prix_vente, 0))::numeric, 2)
          as valeur_manquant
        from public.tournee_lignes l
       where l.tournee_id = p_tournee
    ) x;

  select
    coalesce(sum(l.quantite_attribuee), 0),
    coalesce(sum(l.quantite_vendue), 0),
    coalesce(sum(l.quantite_retournee), 0),
    coalesce(sum(l.quantite_bonus), 0),
    coalesce(sum(l.quantite_casse), 0),
    coalesce(sum(round(((l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
           - l.quantite_bonus - l.quantite_casse) * coalesce(l.prix_vente, 0))::numeric, 2)), 0)
    into v_confie, v_vendu, v_rendu, v_bonus, v_casse, v_valeur
    from public.tournee_lignes l
   where l.tournee_id = p_tournee;

  v_manquant := v_confie - v_vendu - v_rendu - v_bonus - v_casse;

  -- ---- Les reçus (une ligne par panier) --------------------------------
  select coalesce(jsonb_agg(x order by x.heure), '[]'::jsonb)
    into v_recus
    from (
      select
        coalesce(v.numero_vente, '(sans numéro)') as numero,
        min(v.date) as heure,
        round(sum(v.prix)::numeric, 2) as total,
        count(*) as nb_lignes
        from public.ventes v
       where v.tournee_id = p_tournee
       group by v.vente_uuid, v.numero_vente
    ) x;

  select coalesce(sum(v.prix), 0), count(distinct coalesce(v.vente_uuid::text, v.numero_vente))
    into v_ca, v_nb_recus
    from public.ventes v
   where v.tournee_id = p_tournee;

  -- ---- La production du jour (ce qui est entré en stock) ---------------
  if to_regclass('public.productions') is not null then
    select coalesce(jsonb_agg(x order by x.nom), '[]'::jsonb)
      into v_prods
      from (
        select
          p.produit_id,
          coalesce(pr.nom, 'Article #' || p.produit_id) as nom,
          sum(case when p.statut = 'terminee' then p.quantite_reelle else 0 end) as produite,
          sum(case when p.statut = 'terminee' then p.pertes else 0 end) as pertes,
          count(*) filter (where p.statut = 'terminee') as nb
          from public.productions p
          left join public.produits pr on pr.id = p.produit_id
         where p.owner_id = v_owner
           and coalesce(p.terminee_le::date, p.created_at::date) = v_jour
         group by p.produit_id, pr.nom
      ) x;
  end if;

  return jsonb_build_object(
    'ok', true,
    'entete', jsonb_build_object(
      'tournee_id', v_t.id,
      'reference', v_t.reference,
      'date_tournee', v_jour,
      'zone', coalesce(v_t.zone_couverte, v_t.zone, ''),
      'statut', v_t.statut,
      'agent_id', v_t.agent_id,
      'agent_nom', v_agent,
      'entreprise', v_societe,
      'devise', v_devise,
      'objectif_montant', v_t.objectif_montant,
      'commission_taux', v_t.commission_taux,
      'commission_montant', v_t.commission_montant,
      'cloturee_le', v_t.cloturee_le
    ),
    'lignes', v_lignes,
    'recus', v_recus,
    'productions', v_prods,
    'totaux', jsonb_build_object(
      'confie', v_confie,
      'vendu', v_vendu,
      'rendu', v_rendu,
      'offert', v_bonus,
      'casse', v_casse,
      'manquant', v_manquant,
      'valeur_manquant', v_valeur,
      'chiffre_affaires', v_ca,
      'nb_recus', v_nb_recus
    ),
    -- Ce que le patron doit comprendre avant de toucher au stock :
    -- la dotation est une réservation, seule la vente a fait bouger le stock.
    'stock_mouvemente', false,
    'note_stock',
      'La dotation ne retire pas le stock : seules les ventes le diminuent. '
      'Ce que l''agent rapporte est donc déjà en stock — inutile de le saisir '
      'à nouveau.'
  );
end;
$$;

comment on function public.rpc_rapport_tournee_detail(uuid) is
  'Rapport imprimable d''une tournée : mouvement par produit (confié/vendu/rendu/offert/cassé/manquant), reçus, production du jour et totaux.';

revoke all on function public.rpc_rapport_tournee_detail(uuid) from public, anon;
grant execute on function public.rpc_rapport_tournee_detail(uuid) to authenticated;


-- ============================================================================
--  FIN — PHASE 8
-- ============================================================================
