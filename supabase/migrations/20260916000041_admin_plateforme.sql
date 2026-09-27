-- ============================================================================
--  MODULE 20 — ADMINISTRATION PLATEFORME (audit final de professionnalisation)
--  Migration 20260916000041_admin_plateforme.sql
-- ============================================================================
--
--  POURQUOI CETTE MIGRATION
--  ------------------------
--  L'audit final a montré trois manques RÉELS côté plateforme :
--
--   1. aucune modération du CATALOGUE PUBLIC : si une boutique publie un
--      article illicite ou trompeur, la plateforme n'a aucun moyen de le
--      retirer du marketplace ;
--   2. aucun écran d'administration des ESPACES (boutiques/magasins) :
--      impossible de suspendre une boutique sans passer par sa fiche
--      entreprise, impossible de voir l'ensemble du parc ;
--   3. suppression d'un utilisateur par un `delete` direct, sans analyse des
--      dépendances — risque d'échec de contrainte ou de données orphelines,
--      alors que les ventes, paiements, dettes et audits doivent rester
--      traçables.
--
--  Elle AJOUTE uniquement :
--     • 3 colonnes de traçabilité de modération sur `produits_publications` ;
--     • les pages de permission `boutiques` et `moderation` ;
--     • 6 RPC `security definer` réservées au personnel plateforme.
--
--  Aucune table n'est supprimée, aucune donnée n'est transformée, et les
--  fonctions `pages_permissions()` / `permissions_defaut()` sont RECRÉÉES à
--  l'identique de la migration 40, augmentées des deux nouvelles pages.
--
--  ⚠️ Comme la migration 40, celle-ci est exécutée par l'utilisateur dans le
--     SQL Editor Supabase (le DDL n'est pas possible via PostgREST).
--     Elle est IDEMPOTENTE : rejouable sans erreur.
-- ============================================================================


-- ============================================================================
--  1. TRAÇABILITÉ DE LA MODÉRATION SUR LES PUBLICATIONS
-- ============================================================================
--  Une publication retirée par la plateforme doit dire POURQUOI et PAR QUI.
--  Ces colonnes sont également visibles du commerçant : il comprend la
--  décision au lieu de constater une disparition.

alter table public.produits_publications
  add column if not exists moderation_note text,
  add column if not exists moderation_le   timestamptz,
  add column if not exists moderation_par  uuid;

comment on column public.produits_publications.moderation_note is
  'Module 20 — Motif du retrait/republishage par la plateforme (visible du commerçant : il doit comprendre la décision).';
comment on column public.produits_publications.moderation_le is
  'Module 20 — Date de la dernière décision de modération.';
comment on column public.produits_publications.moderation_par is
  'Module 20 — Membre de l''équipe plateforme ayant pris la décision.';

create index if not exists idx_produits_publications_moderation
  on public.produits_publications (moderation_le desc)
  where moderation_le is not null;


-- ============================================================================
--  2. OUTIL INTERNE — CONTRÔLE D'ACCÈS PLATEFORME
-- ============================================================================
--  Toutes les RPC ci-dessous sont réservées au personnel plateforme. Le
--  contrôle est refait DANS chaque fonction (jamais seulement dans
--  l'application), et le message est préfixé par un code stable que la
--  couche Dart sait traduire.

create or replace function public.biashara_exiger_plateforme()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.est_plateforme() then
    raise exception 'ACCES_REFUSE|Cette action est réservée à l''équipe plateforme.';
  end if;
end;
$$;

comment on function public.biashara_exiger_plateforme() is
  'Module 20 — Lève une exception si l''appelant n''appartient pas au personnel plateforme.';


-- ============================================================================
--  3. RPC — PARC DES BOUTIQUES (ESPACES) DE TOUTE LA PLATEFORME
-- ============================================================================

create or replace function public.rpc_admin_espaces_lister(
  p_recherche text default null,
  p_filtre    text default 'tous',
  p_limite    integer default 100,
  p_decalage  integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_q        text := public.biashara_normaliser(p_recherche);
  v_filtre   text := lower(btrim(coalesce(p_filtre, 'tous')));
  v_limite   integer := least(greatest(coalesce(p_limite, 100), 1), 300);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_liste    jsonb := '[]'::jsonb;
  v_total    integer := 0;
  v_actifs   integer := 0;
  v_visibles integer := 0;
begin
  perform public.biashara_exiger_plateforme();

  if v_filtre not in ('tous', 'actifs', 'inactifs', 'visibles', 'non_visibles') then
    v_filtre := 'tous';
  end if;

  -- Compteurs globaux (indépendants de la page affichée).
  select count(*),
         count(*) filter (where e.actif),
         count(*) filter (where e.visible_publiquement)
    into v_total, v_actifs, v_visibles
    from public.espaces e;

  select coalesce(jsonb_agg(jsonb_build_object(
           'espace_id',  s.id,
           'nom',        s.nom,
           'type',       s.type,
           'actif',      s.actif,
           'visible_publiquement', s.visible_publiquement,
           'statut_localisation',  s.statut_localisation,
           'ville',      s.ville,
           'quartier',   s.quartier,
           'entreprises_id', s.entreprise_id,
           'entreprise', s.entreprise,
           'entreprise_statut', s.entreprise_statut,
           'activation_etape',  s.activation_etape,
           'nb_produits',        s.nb_produits,
           'nb_produits_publies', s.nb_produits_publies,
           'latitude',   s.latitude,
           'longitude',  s.longitude,
           'created_at', s.created_at
         ) order by s.entreprise, s.nom), '[]'::jsonb)
    into v_liste
    from (
      select e.id, e.nom, e.type, e.actif, e.visible_publiquement,
             e.statut_localisation, e.quartier, e.latitude, e.longitude,
             e.created_at, e.entreprise_id,
             ent.nom as entreprise,
             coalesce(ent.statut::text, '') as entreprise_statut,
             coalesce(ent.activation_etape, 'actif') as activation_etape,
             (select v.nom from public.villes v where v.id = e.ville_id) as ville,
             (select count(*) from public.produits_publications pb
               where pb.espace_id = e.id) as nb_produits,
             (select count(*) from public.produits_publications pb
               where pb.espace_id = e.id and pb.publie) as nb_produits_publies
        from public.espaces e
        left join public.entreprises ent on ent.id = e.entreprise_id
    ) s
   where (v_q = '' or public.biashara_normaliser(
            coalesce(s.nom, '') || ' ' || coalesce(s.entreprise, '') || ' '
            || coalesce(s.ville, '') || ' ' || coalesce(s.quartier, ''))
          like '%' || v_q || '%')
     and (
       v_filtre = 'tous'
       or (v_filtre = 'actifs' and s.actif)
       or (v_filtre = 'inactifs' and not s.actif)
       or (v_filtre = 'visibles' and s.visible_publiquement)
       or (v_filtre = 'non_visibles' and not s.visible_publiquement)
     )
   order by s.entreprise, s.nom
   limit v_limite offset v_decalage;

  return jsonb_build_object(
    'ok', true,
    'total', jsonb_build_object(
      'espaces', v_total, 'actifs', v_actifs, 'visibles', v_visibles),
    'espaces', v_liste
  );
end;
$$;

comment on function public.rpc_admin_espaces_lister(text, text, integer, integer) is
  'Module 20 — Parc complet des boutiques/espaces de la plateforme (recherche, filtres, compteurs). Réservé au personnel plateforme.';


create or replace function public.rpc_admin_espace_statut(
  p_espace_id uuid,
  p_actif     boolean default null,
  p_visible   boolean default null,
  p_motif     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_avant  public.espaces;
  v_apres  public.espaces;
begin
  perform public.biashara_exiger_plateforme();

  if p_espace_id is null then
    raise exception 'ESPACE_INCONNU|Aucune boutique indiquée.';
  end if;

  select * into v_avant from public.espaces where id = p_espace_id;
  if v_avant.id is null then
    raise exception 'ESPACE_INCONNU|Cette boutique est introuvable.';
  end if;

  if p_actif is null and p_visible is null then
    raise exception 'DONNEES_INVALIDES|Indiquez au moins un changement (activation ou visibilité).';
  end if;

  -- Une boutique désactivée ne peut pas rester visible du public : les deux
  -- notions sont liées, on évite donc un état incohérent.
  update public.espaces
     set actif      = coalesce(p_actif, actif),
         visible_publiquement =
           case
             when p_visible is not null then p_visible
             when coalesce(p_actif, actif) is false then false
             else visible_publiquement
           end,
         updated_at = now()
   where id = p_espace_id
   returning * into v_apres;

  -- Journal d'audit : best-effort, jamais bloquant (le schéma de
  -- `journal_audit` est antérieur et évolutif).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      v_apres.entreprise_id,
      case when v_apres.actif then 'BIASHARA_BOUTIQUE_ACTIVEE'
           else 'BIASHARA_BOUTIQUE_DESACTIVEE' end,
      auth.uid(),
      jsonb_build_object(
        'espace_id', v_apres.id,
        'actif_avant', v_avant.actif,
        'actif_apres', v_apres.actif,
        'visible_avant', v_avant.visible_publiquement,
        'visible_apres', v_apres.visible_publiquement,
        'motif', nullif(btrim(coalesce(p_motif, '')), '')
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'espace_id', v_apres.id,
    'actif', v_apres.actif,
    'visible_publiquement', v_apres.visible_publiquement
  );
end;
$$;

comment on function public.rpc_admin_espace_statut(uuid, boolean, boolean, text) is
  'Module 20 — Active/désactive et rend visible/invisible une boutique, avec motif journalisé. La désactivation retire automatiquement la boutique du catalogue public.';


-- ============================================================================
--  4. RPC — MODÉRATION DU CATALOGUE PUBLIC
-- ============================================================================

create or replace function public.rpc_admin_publications_lister(
  p_recherche text default null,
  p_filtre    text default 'toutes',
  p_espace_id uuid default null,
  p_limite    integer default 100,
  p_decalage  integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_q        text := public.biashara_normaliser(p_recherche);
  v_filtre   text := lower(btrim(coalesce(p_filtre, 'toutes')));
  v_limite   integer := least(greatest(coalesce(p_limite, 100), 1), 300);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_liste    jsonb := '[]'::jsonb;
  v_total    integer := 0;
  v_publiees integer := 0;
  v_retirees integer := 0;
begin
  perform public.biashara_exiger_plateforme();

  if v_filtre not in ('toutes', 'publiees', 'retirees', 'indisponibles') then
    v_filtre := 'toutes';
  end if;

  select count(*),
         count(*) filter (where pb.publie),
         count(*) filter (where not pb.publie)
    into v_total, v_publiees, v_retirees
    from public.produits_publications pb
   where p_espace_id is null or pb.espace_id = p_espace_id;

  select coalesce(jsonb_agg(jsonb_build_object(
           'publication_id', t.id,
           'produit_id',     t.produit_id,
           'nom',            t.nom,
           'categorie',      t.categorie,
           'prix',           t.prix,
           'unite',          t.unite,
           'photo',          t.photo,
           'publie',         t.publie,
           'disponible',     t.disponible,
           'espace_id',      t.espace_id,
           'boutique',       t.boutique,
           'boutique_slug',  t.boutique_slug,
           'ville',          t.ville,
           'moderation_note', t.moderation_note,
           'moderation_le',   t.moderation_le,
           'mis_a_jour_le',   t.updated_at
         ) order by t.moderation_le desc nulls last, t.updated_at desc), '[]'::jsonb)
    into v_liste
    from (
      select pb.id, pb.produit_id, p.nom, nullif(btrim(p.categorie), '') as categorie,
             coalesce(pb.prix_public, p.prix_vente) as prix,
             coalesce(nullif(btrim(pb.unite), ''), p.unite_mesure) as unite,
             coalesce(pb.photo_url, p.photo) as photo,
             pb.publie,
             (pb.disponible and coalesce(p.quantite, 0) > 0) as disponible,
             pb.espace_id, pb.moderation_note, pb.moderation_le, pb.updated_at,
             e.nom as boutique, e.slug as boutique_slug,
             (select v.nom from public.villes v where v.id = e.ville_id) as ville
        from public.produits_publications pb
        join public.produits p on p.id = pb.produit_id
        left join public.espaces e on e.id = pb.espace_id
       where (p_espace_id is null or pb.espace_id = p_espace_id)
         and (
           v_q = ''
           or public.biashara_normaliser(
                coalesce(p.nom, '') || ' ' || coalesce(p.categorie, '') || ' '
                || coalesce(pb.mots_cles, '') || ' ' || coalesce(e.nom, ''))
              like '%' || v_q || '%'
         )
         and (
           v_filtre = 'toutes'
           or (v_filtre = 'publiees' and pb.publie)
           or (v_filtre = 'retirees' and not pb.publie)
           or (v_filtre = 'indisponibles' and pb.publie and not pb.disponible)
         )
    ) t;

  return jsonb_build_object(
    'ok', true,
    'total', jsonb_build_object(
      'publications', v_total, 'publiees', v_publiees, 'retirees', v_retirees),
    'publications', v_liste
  );
end;
$$;

comment on function public.rpc_admin_publications_lister(text, text, uuid, integer, integer) is
  'Module 20 — Inventaire du catalogue public (toutes boutiques) avec recherche et filtres, pour la modération.';


create or replace function public.rpc_admin_publication_statut(
  p_publication_id uuid,
  p_publie          boolean,
  p_motif           text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pub public.produits_publications;
  v_nom text;
begin
  perform public.biashara_exiger_plateforme();

  select * into v_pub from public.produits_publications
   where id = p_publication_id;
  if v_pub.id is null then
    raise exception 'PRODUIT_INCONNU|Cette publication est introuvable.';
  end if;

  -- Retirer un article du catalogue public est une décision de modération :
  -- le motif est obligatoire pour que le commerçant comprenne.
  if not p_publie and nullif(btrim(coalesce(p_motif, '')), '') is null then
    raise exception 'MOTIF_MANQUANT|Indiquez le motif du retrait : le commerçant doit savoir pourquoi.';
  end if;

  update public.produits_publications
     set publie          = p_publie,
         moderation_note = nullif(btrim(coalesce(p_motif, '')), ''),
         moderation_le   = now(),
         moderation_par  = auth.uid(),
         updated_at      = now()
   where id = p_publication_id
   returning * into v_pub;

  select p.nom into v_nom from public.produits p where p.id = v_pub.produit_id;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      (select e.entreprise_id from public.espaces e where e.id = v_pub.espace_id),
      case when p_publie then 'BIASHARA_PUBLICATION_REPUBLIEE'
           else 'BIASHARA_PUBLICATION_RETIREE' end,
      auth.uid(),
      jsonb_build_object(
        'publication_id', v_pub.id,
        'produit_id', v_pub.produit_id,
        'produit', v_nom,
        'espace_id', v_pub.espace_id,
        'motif', nullif(btrim(coalesce(p_motif, '')), '')
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'publication_id', v_pub.id,
    'publie', v_pub.publie,
    'moderation_note', v_pub.moderation_note
  );
end;
$$;

comment on function public.rpc_admin_publication_statut(uuid, boolean, text) is
  'Module 20 — Retire un article du catalogue public (ou le republie) avec motif obligatoire, journalisé et visible du commerçant.';


-- ============================================================================
--  5. RPC — SUPPRESSION D'UTILISATEUR : ANALYSER AVANT D'AGIR
-- ============================================================================
--  Principe : aucune donnée de gestion n'est jamais détruite. Une vente, une
--  dette, un paiement ou une ligne d'audit doivent rester lisibles après le
--  départ d'un collaborateur. Trois stratégies sont donc proposées, dans cet
--  ordre de préférence :
--    1. 'desactivation'  : le compte ne peut plus se connecter (réversible) ;
--    2. 'anonymisation'  : désactivation + effacement des nom/prénom/avatar
--       (le compte devient « Compte supprimé », les historiques restent) ;
--    3. 'suppression'    : suppression RÉELLE, autorisée uniquement si
--       l'utilisateur ne porte AUCUNE donnée de gestion.
--  Le diagnostic doit être consulté AVANT (rpc_admin_utilisateur_dependances).

create or replace function public.rpc_admin_utilisateur_dependances(
  p_utilisateur_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  -- Tables rattachées à l'utilisateur par `owner_id` (données de gestion).
  v_owner_tables text[][] := array[
    array['produits',              'owner_id'],
    array['produits_publications', 'owner_id'],
    array['ventes',                'owner_id'],
    array['clients',               'owner_id'],
    array['dettes',                'owner_id'],
    array['paiements_dette',       'owner_id'],
    array['depenses',              'owner_id'],
    array['caisse',                'owner_id'],
    array['clotures_caisse',       'owner_id'],
    array['publicites',            'owner_id'],
    array['liens_attribution',     'owner_id']
  ];
  v_detail   jsonb := '{}'::jsonb;
  v_total    integer := 0;
  v_n        integer;
  v_i        integer;
  v_table    text;
  v_colonne  text;
  v_espaces  integer := 0;
  v_employes integer := 0;
  v_entreprise uuid;
  v_patron   boolean := false;
begin
  perform public.biashara_exiger_plateforme();

  if p_utilisateur_id is null then
    raise exception 'UTILISATEUR_INCONNU|Aucun utilisateur indiqué.';
  end if;

  -- L'utilisateur existe-t-il, et quel est son rattachement ?
  select u.entreprise_id, (u.parent_id is null)
    into v_entreprise, v_patron
    from public.utilisateurs u
   where u.id = p_utilisateur_id;

  if not found then
    raise exception 'UTILISATEUR_INCONNU|Cet utilisateur est introuvable.';
  end if;

  -- Comptage défensif : une table ou une colonne absente du schéma ne doit
  -- jamais faire échouer le diagnostic (le schéma a évolué par modules).
  v_i := 1;
  loop
    exit when v_i > array_length(v_owner_tables, 1);
    v_table   := v_owner_tables[v_i][1];
    v_colonne := v_owner_tables[v_i][2];
    v_i := v_i + 1;

    if to_regclass('public.' || v_table) is null then
      continue;
    end if;

    v_n := 0;
    begin
      execute format(
        'select count(*) from public.%I where %I = $1', v_table, v_colonne)
        into v_n
        using p_utilisateur_id;
    exception when others then
      v_n := 0;
    end;

    if v_n > 0 then
      v_detail := v_detail || jsonb_build_object(v_table, v_n);
      v_total := v_total + v_n;
    end if;
  end loop;

  -- Espaces (boutiques) rattachés à l'entreprise de l'utilisateur.
  if v_entreprise is not null then
    select count(*) into v_espaces
      from public.espaces e where e.entreprise_id = v_entreprise;
  end if;

  -- Collaborateurs rattachés directement à cet utilisateur.
  select count(*) into v_employes
    from public.utilisateurs u where u.parent_id = p_utilisateur_id;

  return jsonb_build_object(
    'ok', true,
    'utilisateur_id', p_utilisateur_id,
    'entreprise_id', v_entreprise,
    'est_patron', v_patron,
    'nb_espaces', v_espaces,
    'nb_collaborateurs', v_employes,
    'total_donnees', v_total,
    'detail', v_detail,
    -- Règles de décision, calculées côté serveur : l'application n'a pas à
    -- les réinventer (une seule source de vérité).
    'suppression_possible', (v_total = 0 and v_espaces = 0 and v_employes = 0),
    'anonymisation_possible', true,
    'recommandation',
      case
        when v_total = 0 and v_espaces = 0 and v_employes = 0
          then 'suppression'
        when v_patron
          then 'anonymisation'
        else 'desactivation'
      end
  );
end;
$$;

comment on function public.rpc_admin_utilisateur_dependances(uuid) is
  'Module 20 — Diagnostic des dépendances d''un utilisateur (données de gestion, espaces, collaborateurs) et stratégie recommandée AVANT toute suppression.';


create or replace function public.rpc_admin_utilisateur_supprimer(
  p_utilisateur_id uuid,
  p_mode           text default 'desactivation',
  p_motif          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode    text := lower(btrim(coalesce(p_mode, 'desactivation')));
  v_dep     jsonb;
  v_total   integer;
  v_espaces integer;
  v_employes integer;
  v_patron  boolean;
  v_espaces_ids uuid[];
  v_entreprise uuid;
begin
  perform public.biashara_exiger_plateforme();

  if v_mode not in ('desactivation', 'anonymisation', 'suppression') then
    raise exception 'MODE_INCONNU|Stratégie inconnue : %', v_mode;
  end if;

  if p_utilisateur_id is null then
    raise exception 'UTILISATEUR_INCONNU|Aucun utilisateur indiqué.';
  end if;

  -- Le diagnostic est TOUJOURS recalculé ici : l'application ne peut pas
  -- contourner une contrainte en envoyant une décision périmée.
  v_dep := public.rpc_admin_utilisateur_dependances(p_utilisateur_id);
  v_total    := coalesce((v_dep ->> 'total_donnees')::integer, 0);
  v_espaces  := coalesce((v_dep ->> 'nb_espaces')::integer, 0);
  v_employes := coalesce((v_dep ->> 'nb_collaborateurs')::integer, 0);
  v_patron   := coalesce((v_dep ->> 'est_patron')::boolean, false);
  v_entreprise := nullif(v_dep ->> 'entreprise_id', '')::uuid;

  -- 1) SUPPRESSION RÉELLE : uniquement un compte sans aucune attache.
  if v_mode = 'suppression' then
    if v_total > 0 or v_espaces > 0 or v_employes > 0 then
      raise exception
        'SUPPRESSION_IMPOSSIBLE|Ce compte porte % donnée(s) de gestion, % boutique(s) et % collaborateur(s). Une suppression réelle effacerait des historiques (ventes, paiements, dettes, audit) : utilisez la désactivation ou l''anonymisation.',
        v_total, v_espaces, v_employes;
    end if;

    delete from public.utilisateurs where id = p_utilisateur_id;

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (v_entreprise, 'ADMIN_UTILISATEUR_SUPPRIME', auth.uid(),
              jsonb_build_object('utilisateur_id', p_utilisateur_id,
                                 'motif', nullif(btrim(coalesce(p_motif, '')), '')));
    exception when others then null;
    end;

    return jsonb_build_object('ok', true, 'mode', 'suppression',
                              'utilisateur_id', p_utilisateur_id);
  end if;

  -- 2) ANONYMISATION : on garde la traçabilité, plus l'identité.
  --    Un PATRON est refusé ici : transférez d'abord la propriété de
  --    l'entreprise, sinon plus personne ne pourrait la gérer.
  if v_mode = 'anonymisation' then
    if v_patron and v_espaces > 0 then
      select array_agg(e.id) into v_espaces_ids
        from public.espaces e where e.entreprise_id = v_entreprise;

      raise exception
        'PROPRIETE_A_TRANSFERER|Ce compte est le propriétaire de l''entreprise et de % boutique(s). Transférez d''abord la propriété (ou désactivez le compte) : une anonymisation laisserait l''entreprise sans responsable.',
        v_espaces;
    end if;

    update public.utilisateurs
       set valide    = 0,
           new_role  = null,
           nom       = 'Compte supprimé',
           prenom    = null,
           avatar    = null
     where id = p_utilisateur_id;

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (v_entreprise, 'ADMIN_UTILISATEUR_ANONYMISE', auth.uid(),
              jsonb_build_object('utilisateur_id', p_utilisateur_id,
                                 'donnees_conservees', v_total,
                                 'motif', nullif(btrim(coalesce(p_motif, '')), '')));
    exception when others then null;
    end;

    return jsonb_build_object('ok', true, 'mode', 'anonymisation',
                              'utilisateur_id', p_utilisateur_id);
  end if;

  -- 3) DÉSACTIVATION (défaut) : réversible, aucune donnée touchée.
  update public.utilisateurs
     set valide   = 0,
         new_role = null
   where id = p_utilisateur_id;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (v_entreprise, 'ADMIN_UTILISATEUR_DESACTIVE', auth.uid(),
            jsonb_build_object('utilisateur_id', p_utilisateur_id,
                               'motif', nullif(btrim(coalesce(p_motif, '')), '')));
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'mode', 'desactivation',
                            'utilisateur_id', p_utilisateur_id);
end;
$$;

comment on function public.rpc_admin_utilisateur_supprimer(uuid, text, text) is
  'Module 20 — Désactive, anonymise ou supprime réellement un utilisateur, après recalcul serveur des dépendances. Les historiques de gestion ne sont jamais détruits.';


-- ============================================================================
--  6. PERMISSIONS — PAGES `boutiques` ET `moderation`
-- ============================================================================
--  Recréées à l'identique de la migration 40, augmentées des deux pages
--  d'administration plateforme. `SUPER_ADMIN` reste couvert automatiquement
--  (toutes les pages de `pages_permissions()`).

create or replace function public.pages_permissions()
returns text[]
language sql
immutable
as $$
  select array[
    'dashboard', 'entreprises', 'utilisateurs', 'villes', 'activites',
    'groupes_tarifaires', 'abonnements', 'paiements', 'finance', 'audit',
    'securite', 'notifications', 'assistance', 'parametres', 'ventes',
    'caisse', 'scanner', 'panier', 'articles', 'stock', 'clients',
    'fournisseurs', 'depenses', 'collaborateurs', 'qr_codes', 'rapports',
    'assistant_ia',
    -- 🏨 MODULE 16 C2 — hôtel.
    'chambres', 'reservations', 'reception',
    -- 🍽️ MODULE 16 C3 — restaurant.
    'tables', 'commandes', 'cuisine',
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    'salles', 'evenements',
    -- 🥖 MODULE 16 C5 — boulangerie.
    'production',
    -- 🛒 MODULE 19 — marketplace local géolocalisé.
    'publications', 'visibilite', 'publicites',
    -- 🛡️ MODULE 20 — administration plateforme.
    'boutiques', 'moderation'
  ];
$$;

comment on function public.pages_permissions() is
  'Liste officielle des pages de permission (Module 4, + M12, + M13, + hôtel C2, + restaurant C3, + salle des fêtes C4, + boulangerie C5, + marketplace M19, + administration plateforme M20).';

create or replace function public.permissions_defaut(p_role text)
returns jsonb
language plpgsql
immutable
as $$
declare
  v_role    text := upper(btrim(coalesce(p_role, '')));
  v_pages   text[];
  v_actions text[];
  v_result  jsonb := '{}'::jsonb;
  v_page    text;
begin
  if v_role = 'SUPER_ADMIN' then
    select jsonb_object_agg(p, to_jsonb(public.actions_permissions()))
      into v_result
      from unnest(public.pages_permissions()) as p;
    return coalesce(v_result, '{}'::jsonb);
  end if;

  case v_role
    when 'GESTIONNAIRE_COMPTES' then
      v_pages   := array['entreprises', 'utilisateurs', 'villes', 'activites',
                         'groupes_tarifaires', 'abonnements', 'assistance',
                         'notifications',
                         -- 🛡️ MODULE 20 — parc des boutiques et modération.
                         'boutiques', 'moderation'];
      v_actions := array['voir', 'creer', 'modifier'];

    when 'FINANCE_LAPERLE' then
      v_pages   := array['dashboard', 'abonnements', 'paiements', 'finance',
                         'rapports', 'audit', 'notifications'];
      v_actions := array['voir', 'creer', 'valider'];

    when 'SUPPORT' then
      v_pages   := array['dashboard', 'assistance', 'entreprises', 'utilisateurs',
                         'abonnements', 'notifications',
                         -- 🛡️ MODULE 20 — consultation seulement : le support
                         -- constate et oriente, il ne modère pas le catalogue.
                         'boutiques'];
      v_actions := array['voir'];

    when 'PROPRIETAIRE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'scanner', 'panier',
                         'articles', 'qr_codes', 'stock', 'clients', 'fournisseurs',
                         'finance', 'depenses', 'collaborateurs', 'rapports',
                         'abonnements', 'audit', 'assistant_ia', 'parametres',
                         'chambres', 'reservations', 'reception',
                         'tables', 'commandes', 'cuisine',
                         'salles', 'evenements',
                         'production',
                         'publications', 'visibilite', 'publicites'];
      v_actions := public.actions_permissions();

    when 'VENDEUR' then
      v_pages   := array['ventes', 'caisse', 'scanner', 'panier', 'assistant_ia',
                         'chambres', 'reservations', 'reception',
                         'tables', 'commandes', 'cuisine',
                         'salles', 'evenements',
                         'production'];
      v_actions := array['voir', 'creer'];

    when 'MAGASINIER' then
      v_pages   := array['stock', 'articles', 'qr_codes', 'rapports',
                         'assistant_ia', 'production'];
      v_actions := array['voir'];

    when 'COMPTABLE_ENTREPRISE' then
      v_pages   := array['dashboard', 'ventes', 'caisse', 'depenses', 'rapports',
                         'finance', 'assistant_ia', 'parametres'];
      v_actions := array['voir'];

    else
      return '{}'::jsonb;
  end case;

  foreach v_page in array v_pages loop
    v_result := jsonb_set(v_result, array[v_page], to_jsonb(v_actions), true);
  end loop;

  -- Exceptions par page.
  v_result := case v_role
    when 'SUPPORT' then v_result
      || jsonb_build_object('assistance',    to_jsonb(array['voir', 'modifier']))
      || jsonb_build_object('notifications', to_jsonb(array['voir', 'modifier']))
    when 'MAGASINIER' then v_result
      || jsonb_build_object('stock',        to_jsonb(array['voir', 'creer', 'modifier']))
      || jsonb_build_object('qr_codes',     to_jsonb(array['voir', 'creer']))
      || jsonb_build_object('assistant_ia', to_jsonb(array['voir', 'creer']))
      || jsonb_build_object('production',   to_jsonb(array['voir', 'creer', 'modifier']))
    when 'COMPTABLE_ENTREPRISE' then v_result
      || jsonb_build_object('depenses',     to_jsonb(array['voir', 'creer', 'valider']))
      || jsonb_build_object('rapports',     to_jsonb(array['voir', 'valider']))
      || jsonb_build_object('assistant_ia', to_jsonb(array['voir', 'creer']))
    when 'VENDEUR' then v_result
      || jsonb_build_object('chambres', to_jsonb(array['voir']))
      || jsonb_build_object('tables',   to_jsonb(array['voir']))
      || jsonb_build_object('salles',   to_jsonb(array['voir']))
    else v_result
  end;

  return v_result;
end;
$$;

comment on function public.permissions_defaut(text) is
  'Matrice des permissions par défaut (Module 4 → Module 20 : marketplace M19 + administration plateforme M20).';


-- ============================================================================
--  7. DROITS
-- ============================================================================
--  Aucune de ces fonctions n'est accessible sans compte, et le contrôle
--  `est_plateforme()` est refait à l'intérieur de chacune.

revoke all on function public.biashara_exiger_plateforme() from public;
revoke all on function public.biashara_exiger_plateforme() from anon;
grant execute on function public.biashara_exiger_plateforme() to authenticated;

revoke all on function public.rpc_admin_espaces_lister(text, text, integer, integer) from public;
revoke all on function public.rpc_admin_espaces_lister(text, text, integer, integer) from anon;
grant execute on function public.rpc_admin_espaces_lister(text, text, integer, integer) to authenticated;

revoke all on function public.rpc_admin_espace_statut(uuid, boolean, boolean, text) from public;
revoke all on function public.rpc_admin_espace_statut(uuid, boolean, boolean, text) from anon;
grant execute on function public.rpc_admin_espace_statut(uuid, boolean, boolean, text) to authenticated;

revoke all on function public.rpc_admin_publications_lister(text, text, uuid, integer, integer) from public;
revoke all on function public.rpc_admin_publications_lister(text, text, uuid, integer, integer) from anon;
grant execute on function public.rpc_admin_publications_lister(text, text, uuid, integer, integer) to authenticated;

revoke all on function public.rpc_admin_publication_statut(uuid, boolean, text) from public;
revoke all on function public.rpc_admin_publication_statut(uuid, boolean, text) from anon;
grant execute on function public.rpc_admin_publication_statut(uuid, boolean, text) to authenticated;

revoke all on function public.rpc_admin_utilisateur_dependances(uuid) from public;
revoke all on function public.rpc_admin_utilisateur_dependances(uuid) from anon;
grant execute on function public.rpc_admin_utilisateur_dependances(uuid) to authenticated;

revoke all on function public.rpc_admin_utilisateur_supprimer(uuid, text, text) from public;
revoke all on function public.rpc_admin_utilisateur_supprimer(uuid, text, text) from anon;
grant execute on function public.rpc_admin_utilisateur_supprimer(uuid, text, text) to authenticated;


-- ============================================================================
--  8. VÉRIFICATIONS (résultats visibles dans le SQL Editor)
-- ============================================================================

-- 8.a Colonnes de modération présentes (attendu : 3).
select count(*) as colonnes_moderation
  from information_schema.columns
 where table_schema = 'public' and table_name = 'produits_publications'
   and column_name in ('moderation_note', 'moderation_le', 'moderation_par');

-- 8.b Nouvelles pages de permission déclarées (attendu : true).
select position('boutiques' in array_to_string(public.pages_permissions(), ',')) > 0
         as page_boutiques,
       position('moderation' in array_to_string(public.pages_permissions(), ',')) > 0
         as page_moderation;

-- 8.c Matrice GESTIONNAIRE_COMPTES (attendu : true, true) et SUPPORT
--     (attendu : true, false — le support ne modère pas).
select (public.permissions_defaut('GESTIONNAIRE_COMPTES') ? 'boutiques')    as gestionnaire_boutiques,
       (public.permissions_defaut('GESTIONNAIRE_COMPTES') ? 'moderation')   as gestionnaire_moderation,
       (public.permissions_defaut('SUPPORT') ? 'boutiques')                 as support_boutiques,
       (public.permissions_defaut('SUPPORT') ? 'moderation')                as support_moderation;

-- 8.d Les 6 RPC d'administration existent (attendu : 6).
select count(*) as rpc_admin
  from information_schema.routines
 where routine_schema = 'public'
   and routine_name in (
     'rpc_admin_espaces_lister', 'rpc_admin_espace_statut',
     'rpc_admin_publications_lister', 'rpc_admin_publication_statut',
     'rpc_admin_utilisateur_dependances', 'rpc_admin_utilisateur_supprimer'
   );

-- 8.e Exemples d'appel (compte plateforme connecté) :
--     select public.rpc_admin_espaces_lister(null, 'tous', 50, 0);
--     select public.rpc_admin_espaces_lister('lubumbashi', 'visibles', 50, 0);
--     select public.rpc_admin_publications_lister(null, 'toutes', null, 50, 0);
--     select public.rpc_admin_utilisateur_dependances('<uuid>');
--     select public.rpc_admin_publication_statut('<uuid>', false, 'Prix trompeur');
--     select public.rpc_admin_espace_statut('<uuid>', false, null, 'Contenu illicite');

-- ============================================================================
--  FIN — Module 20 (administration plateforme).
-- ============================================================================
