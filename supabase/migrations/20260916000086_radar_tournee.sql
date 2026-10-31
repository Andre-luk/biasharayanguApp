-- ============================================================================
--  biashara_yangu — PHASE 6 : RADAR DE TOURNÉE
--  ---------------------------------------------------------------------------
--  La fonctionnalité qui différencie Biashara Yangu d'un simple cahier :
--  le serveur REGARDE les tournées passées et dit, noir sur blanc :
--
--   1. ce qui manque, produit par produit (jamais un écart global anonyme) ;
--   2. à quel point un agent s'écarte de la norme, et POURQUOI ;
--   3. quelle quantité charger la prochaine fois (médiane réelle des ventes
--      de la même zone, corrigée du taux de retour observé, bornée par le
--      stock disponible) ;
--   4. quels clients gardent des récipients depuis trop longtemps.
--
--  RÈGLE ABSOLUE : tout est CALCULÉ sur des transactions réelles. Aucune
--  donnée inventée, aucune valeur « décorative ». Si l'historique est trop
--  mince, la réponse le dit (`historique_suffisant: false`) au lieu de
--  fabriquer une recommandation.
--
--  PRÉ-REQUIS : 20260916000080 (tournées) et 20260916000085 (casse/bonus),
--              20260916000084 (récipients) pour la valeur des consignes.
--  ⚠️ IDEMPOTENT : create or replace uniquement.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable ---------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'tournee_lignes'
       and column_name = 'quantite_casse'
  ) then
    raise exception 'Migration 0085 absente : exécutez 20260916000085_tournees_commissions_controle.sql.';
  end if;
end $$;


-- ============================================================================
--  1. RPC — RADAR D'UNE TOURNÉE (écarts nommés, reco, consignes à risque)
-- ============================================================================
--  p_tournee : la tournée à examiner (null = pas de tournée : on ne renvoie
--              alors que les recommandations et les consignes à risque).
--  p_zone    : zone à utiliser quand on prépare une tournée qui n'existe pas
--              encore (« Kinshasa-Est »…) ; à défaut, la zone de la tournée.
create or replace function public.rpc_radar_tournee(
  p_tournee uuid default null,
  p_zone    text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_owner     uuid;
  v_t_id      uuid;
  v_t_ref     text;
  v_t_statut  text;
  v_t_agent   uuid;
  v_t_jour    date;
  v_zone      text;
  v_ecarts    jsonb := '[]'::jsonb;
  v_reco      jsonb := '[]'::jsonb;
  v_risque    jsonb := '[]'::jsonb;
  v_confie    numeric := 0;
  v_vendu     numeric := 0;
  v_retourne  numeric := 0;
  v_bonus     numeric := 0;
  v_casse     numeric := 0;
  v_ecart     numeric := 0;
  v_valeur    numeric := 0;
  v_nb_prod   integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter le radar.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  -- ---- Tournée examinée -------------------------------------------------
  if p_tournee is not null then
    select t.id, t.reference, t.statut, t.agent_id, t.date_tournee,
           coalesce(t.zone_couverte, t.zone)
      into v_t_id, v_t_ref, v_t_statut, v_t_agent, v_t_jour, v_zone
      from public.tournees t
     where t.id = p_tournee
       and (t.owner_id = v_owner or t.agent_id = v_user or public.est_plateforme());

    if v_t_id is null then
      raise exception 'TOURNEE_INTROUVABLE|Cette tournée n''existe pas dans votre entreprise.';
    end if;

    -- Écarts, ligne par ligne : nommés, valorisés, jamais noyés.
    select
      coalesce(sum(l.quantite_attribuee), 0),
      coalesce(sum(l.quantite_vendue), 0),
      coalesce(sum(l.quantite_retournee), 0),
      coalesce(sum(l.quantite_bonus), 0),
      coalesce(sum(l.quantite_casse), 0),
      count(*)
      into v_confie, v_vendu, v_retourne, v_bonus, v_casse, v_nb_prod
      from public.tournee_lignes l
     where l.tournee_id = v_t_id;

    v_ecart := v_confie - v_vendu - v_retourne - v_bonus - v_casse;

    select coalesce(jsonb_agg(x order by x.nom), '[]'::jsonb)
      into v_ecarts
      from (
        select
          l.produit_id,
          l.nom_produit as nom,
          coalesce(l.unite, '') as unite,
          l.quantite_attribuee as attribuee,
          l.quantite_vendue as vendue,
          l.quantite_retournee as retournee,
          l.quantite_bonus as bonus,
          l.quantite_casse as casse,
          (l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
             - l.quantite_bonus - l.quantite_casse) as ecart,
          round(((l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
             - l.quantite_bonus - l.quantite_casse) * coalesce(l.prix_vente, 0))::numeric, 2) as valeur
          from public.tournee_lignes l
         where l.tournee_id = v_t_id
           and (l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
                - l.quantite_bonus - l.quantite_casse) <> 0
      ) x;

    select coalesce(sum(round(((l.quantite_attribuee - l.quantite_vendue - l.quantite_retournee
             - l.quantite_bonus - l.quantite_casse) * coalesce(l.prix_vente, 0))::numeric, 2)), 0)
      into v_valeur
      from public.tournee_lignes l
     where l.tournee_id = v_t_id;
  end if;

  if v_zone is null then
    v_zone := nullif(btrim(coalesce(p_zone, '')), '');
  end if;

  -- ---- Recommandation de chargement -------------------------------------
  -- Médiane des quantités VENDUES sur les 4 dernières tournées clôturées de
  -- la même zone, corrigée du taux de retour observé, bornée par le stock.
  select coalesce(jsonb_agg(x order by x.nom), '[]'::jsonb)
    into v_reco
    from (
      with dernieres as (
        select t.id
          from public.tournees t
         where t.owner_id = v_owner
           and t.statut = 'cloturee'
           and (v_t_id is null or t.id <> v_t_id)
           and (v_zone is null or coalesce(t.zone_couverte, t.zone, '') = v_zone)
           and (v_t_jour is null or t.date_tournee < v_t_jour)
         order by t.date_tournee desc
         limit 4
      ),
      histo as (
        select l.produit_id,
               percentile_cont(0.5) within group (order by l.quantite_vendue) as mediane,
               avg(case when l.quantite_attribuee > 0
                        then l.quantite_retournee / l.quantite_attribuee
                        else 0 end) as taux_retour,
               max(l.nom_produit) as nom,
               max(coalesce(l.unite, '')) as unite,
               count(*) as nb_tournees
          from public.tournee_lignes l
          join dernieres d on d.id = l.tournee_id
         group by l.produit_id
      )
      select
        h.produit_id,
        h.nom,
        h.unite,
        round(h.mediane::numeric, 2) as mediane_vendue,
        round(coalesce(h.taux_retour, 0)::numeric, 3) as taux_retour,
        h.nb_tournees,
        greatest(round((h.mediane * (1 - coalesce(h.taux_retour, 0)))::numeric, 2), 0) as quantite_suggeree,
        coalesce(pr.quantite, 0) as stock_disponible,
        least(
          greatest(round((h.mediane * (1 - coalesce(h.taux_retour, 0)))::numeric, 2), 0),
          greatest(coalesce(pr.quantite, 0), 0)
        ) as quantite_retenue
        from histo h
        left join public.produits pr on pr.id = h.produit_id
    ) x;

  -- ---- Clients à risque de consigne -------------------------------------
  -- 30 jours sans rendre un récipient : c'est long pour une bouteille.
  if to_regclass('public.recipients_types') is not null then
    select coalesce(jsonb_agg(x order by x.valeur desc, x.jours desc), '[]'::jsonb)
      into v_risque
      from (
        select
          c.id,
          c.client_id,
          coalesce(nullif(c.client_nom, ''), 'Client non nommé') as client_nom,
          c.libelle_contenant as libelle,
          (c.quantite - c.quantite_recuperee) as restant,
          (current_date - c.date_consigne::date) as jours,
          round(((c.quantite - c.quantite_recuperee) * coalesce(t.prix_consigne, 0))::numeric, 2) as valeur
          from public.consignes c
          left join public.recipients_types t
            on t.owner_id = c.owner_id
           and t.libelle = c.libelle_contenant
         where c.owner_id = v_owner
           and c.statut in ('chez_client', 'partielle')
           and (c.quantite - c.quantite_recuperee) > 0
           and (current_date - c.date_consigne::date) >= 30
         order by 7 desc, 6 desc
         limit 20
      ) x;
  else
    select coalesce(jsonb_agg(x order by x.jours desc), '[]'::jsonb)
      into v_risque
      from (
        select
          c.id,
          c.client_id,
          coalesce(nullif(c.client_nom, ''), 'Client non nommé') as client_nom,
          c.libelle_contenant as libelle,
          (c.quantite - c.quantite_recuperee) as restant,
          (current_date - c.date_consigne::date) as jours,
          0::numeric as valeur
          from public.consignes c
         where c.owner_id = v_owner
           and c.statut in ('chez_client', 'partielle')
           and (c.quantite - c.quantite_recuperee) > 0
           and (current_date - c.date_consigne::date) >= 30
         order by 6 desc
         limit 20
      ) x;
  end if;

  return jsonb_build_object(
    'ok', true,
    'tournee', case when v_t_id is null then null else jsonb_build_object(
      'id', v_t_id,
      'reference', v_t_ref,
      'statut', v_t_statut,
      'agent_id', v_t_agent,
      'date_tournee', v_t_jour,
      'zone', v_zone
    ) end,
    'zone', v_zone,
    'resume', jsonb_build_object(
      'produits', v_nb_prod,
      'quantite_confiee', v_confie,
      'quantite_vendue', v_vendu,
      'quantite_retournee', v_retourne,
      'quantite_bonus', v_bonus,
      'quantite_casse', v_casse,
      'ecart', v_ecart,
      'valeur_ecart', v_valeur
    ),
    'ecarts', v_ecarts,
    'recommandations', v_reco,
    'historique_suffisant', (v_reco <> '[]'::jsonb),
    'consignes_risque', v_risque
  );
end;
$$;

comment on function public.rpc_radar_tournee(uuid, text) is
  'Radar : écarts nommés et valorisés, recommandation de chargement (médiane 4 dernières tournées de la zone), clients à risque de consigne.';


-- ============================================================================
--  2. RPC — RADAR D'UN AGENT (score d'anomalie EXPLIQUÉ)
-- ============================================================================
--  Le score n'est pas une note magique : il est la somme pondérée de deux
--  constats mesurables, et chaque constat est renvoyé en clair.
--
--    • part « écart »  : quantités confiées qui ne sont ni vendues, ni
--      rendues, ni cassées, ni offertes. 5 % du confié = 100 % du poids.
--    • part « impayé » : ventes à crédit sur la période. 20 % du CA = 100 %.
--
--  score = 100 × (0.6 × part_ecart + 0.4 × part_impaye)
--  niveau : < 30 normal · 30-59 à surveiller · ≥ 60 alerte
create or replace function public.rpc_radar_agent(
  p_agent uuid default null,
  p_jours integer default 30
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
  v_agent    uuid;
  v_jours    integer := greatest(coalesce(p_jours, 30), 1);
  v_debut    date;
  v_nom      text;
  v_confie   numeric := 0;
  v_vendu    numeric := 0;
  v_retourne numeric := 0;
  v_bonus    numeric := 0;
  v_casse    numeric := 0;
  v_ecart    numeric := 0;
  v_ca       numeric := 0;
  v_credit   numeric := 0;
  v_nb       integer := 0;
  v_part_ecart  numeric := 0;
  v_part_credit numeric := 0;
  v_score    integer := 0;
  v_niveau   text := 'normal';
  v_motifs   jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter le radar.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  v_agent := coalesce(p_agent, v_user);

  -- Un agent ne consulte que son propre radar ; le patron consulte qui il veut.
  if v_agent <> v_user and v_user <> v_owner and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Vous ne pouvez consulter que votre propre radar.';
  end if;

  if not exists (
    select 1 from public.tournees t
     where t.agent_id = v_agent and t.owner_id = v_owner
  ) then
    raise exception 'AGENT_INVALIDE|Cet agent n''a aucune tournée dans votre entreprise.';
  end if;

  select coalesce(nullif(btrim(coalesce(u.nom, '') || ' ' || coalesce(u.prenom, '')), ''), 'Agent')
    into v_nom
    from public.utilisateurs u
   where u.id = v_agent;

  v_debut := current_date - v_jours;

  select
    coalesce(sum(l.quantite_attribuee), 0),
    coalesce(sum(l.quantite_vendue), 0),
    coalesce(sum(l.quantite_retournee), 0),
    coalesce(sum(l.quantite_bonus), 0),
    coalesce(sum(l.quantite_casse), 0),
    count(distinct t.id)
    into v_confie, v_vendu, v_retourne, v_bonus, v_casse, v_nb
    from public.tournees t
    join public.tournee_lignes l on l.tournee_id = t.id
   where t.agent_id = v_agent
     and t.owner_id = v_owner
     and t.date_tournee >= v_debut;

  v_ecart := v_confie - v_vendu - v_retourne - v_bonus - v_casse;

  select
    coalesce(sum(v.prix), 0),
    coalesce(sum(case when lower(coalesce(v.mode_paiement, '')) like 'credit%'
                      then v.prix else 0 end), 0)
    into v_ca, v_credit
    from public.ventes v
   where v.seller_id = v_agent
     and v.owner_id = v_owner
     and v.date::date >= v_debut;

  -- Parts normalisées (0 → 1), plafonnées : un cas extrême ne casse pas l'échelle.
  if v_confie > 0 then
    v_part_ecart := least(greatest(v_ecart / v_confie, 0) / 0.05, 1.0);
  end if;
  if v_ca > 0 then
    v_part_credit := least(greatest(v_credit / v_ca, 0) / 0.20, 1.0);
  end if;

  v_score := round(100 * (0.6 * v_part_ecart + 0.4 * v_part_credit));
  if v_score < 0 then v_score := 0; end if;
  if v_score > 100 then v_score := 100; end if;

  if v_score >= 60 then
    v_niveau := 'alerte';
  elsif v_score >= 30 then
    v_niveau := 'surveiller';
  else
    v_niveau := 'normal';
  end if;

  -- Motifs : on dit TOUJOURS pourquoi. Un score sans explication est un
  -- jugement, pas un outil.
  if v_ecart > 0 then
    v_motifs := v_motifs || jsonb_build_object(
      'code', 'ECART_MARCHANDISE',
      'libelle', 'Marchandise confiée non justifiée',
      'detail', concat_ws(' ',
        'Sur ', v_jours, 'jours :',
        trim(to_char(v_ecart, 'FM999999990.###')), 'unité(s) ni vendues, ni rendues, ni cassées, ni offertes'),
      'valeur', v_ecart
    );
  end if;

  if v_casse > 0 then
    v_motifs := v_motifs || jsonb_build_object(
      'code', 'CASSE',
      'libelle', 'Casse déclarée',
      'detail', concat(trim(to_char(v_casse, 'FM999999990.###')), ' unité(s) cassée(s) ou perdue(s)'),
      'valeur', v_casse
    );
  end if;

  if v_credit > 0 then
    v_motifs := v_motifs || jsonb_build_object(
      'code', 'CREDIT',
      'libelle', 'Ventes à crédit',
      'detail', concat(trim(to_char(v_credit, 'FM999999990.##')), ' non encaissés sur la période'),
      'valeur', v_credit
    );
  end if;

  if v_ecart < 0 then
    -- Vendu + rendu > confié : incohérence de saisie, à signaler telle quelle.
    v_motifs := v_motifs || jsonb_build_object(
      'code', 'INCOHERENCE',
      'libelle', 'Incohérence de quantités',
      'detail', 'Les quantités déclarées dépassent ce qui a été confié. Vérifiez les retours.',
      'valeur', v_ecart
    );
  end if;

  if v_motifs = '[]'::jsonb then
    v_motifs := jsonb_build_array(jsonb_build_object(
      'code', 'AUCUNE_ANOMALIE',
      'libelle', 'Aucune anomalie détectée',
      'detail', 'Tout ce qui a été confié est vendu, rendu, cassé ou offert.',
      'valeur', 0
    ));
  end if;

  return jsonb_build_object(
    'ok', true,
    'agent_id', v_agent,
    'agent_nom', coalesce(v_nom, 'Agent'),
    'jours', v_jours,
    'score', v_score,
    'niveau', v_niveau,
    'tournees', v_nb,
    'quantite_confiee', v_confie,
    'quantite_vendue', v_vendu,
    'quantite_retournee', v_retourne,
    'quantite_bonus', v_bonus,
    'quantite_casse', v_casse,
    'ecart', v_ecart,
    'taux_ecart', case when v_confie > 0 then round((v_ecart / v_confie)::numeric, 4) else 0 end,
    'chiffre_affaires', v_ca,
    'credit_ouvert', v_credit,
    'taux_credit', case when v_ca > 0 then round((v_credit / v_ca)::numeric, 4) else 0 end,
    'motifs', v_motifs
  );
end;
$$;

comment on function public.rpc_radar_agent(uuid, integer) is
  'Score d''anomalie d''un agent sur N jours, toujours accompagné de ses motifs chiffrés.';


-- ============================================================================
--  3. PRIVILÈGES
-- ============================================================================

revoke all on function public.rpc_radar_tournee(uuid, text) from public;
revoke all on function public.rpc_radar_agent(uuid, integer) from public;

grant execute on function public.rpc_radar_tournee(uuid, text) to authenticated;
grant execute on function public.rpc_radar_agent(uuid, integer) to authenticated;

-- ============================================================================
--  FIN — PHASE 6
-- ============================================================================
