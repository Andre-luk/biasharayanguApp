-- ============================================================================
--  biashara_yangu — MIGRATION 0150 : « PRESSING » DEVIENT UNE VRAIE ACTIVITÉ
--  (activité dans les groupes tarifaires + réparation d'un espace pressing)
--
--  PROBLÈMES SIGNALÉS (12/11/2026)
--    • « Lorsque je crée un compte sur setup en sélectionnant pressing, c'est
--       la boutique qui se crée et non un pressing. »
--    • « Dans groupes tarification, pressing n'existe pas. »
--    • « Quand je me reconnecte, il y a “espace entreprise”. »
--    • « La boutique liée à lucjean@gmail.com, c'est ça le pressing. »
--
--  CAUSES
--    1. `public.activites` (le MÉTIER affiché dans « Groupes tarification »)
--       ne contenait pas « Pressing & Blanchisserie » → aucun groupe
--       tarifaire pressing ne pouvait exister, et un pressing n'avait aucun
--       forfait à sa mesure.
--    2. Les contraintes `*_type_activite_check` n'autorisaient que
--       `boutique` et `distribution` : un espace pressing ne pouvait pas
--       être typé comme tel côté entreprise.
--    3. L'application (repli de `setup_page.dart`) renvoyait `boutique`
--       quand la RPC de création n'était pas disponible : un pressing créé
--       par ce chemin devenait une boutique. (Corrigé côté Dart : la
--       catégorie choisie est maintenant transmise.)
--
--  CE QUE FAIT CE SCRIPT
--    1. Ajoute l'activité « Pressing & Blanchisserie » dans `public.activites`.
--    2. Vérifie/rafraîchit le profil de modules `pressing`.
--    3. Élargit les contraintes de type d'activité à TOUS les types connus
--       (boutique, distribution, pressing, hôtel, pharmacie, restaurant…).
--    4. Crée le groupe tarifaire « Pressing & Blanchisserie — Standard »
--       (base 10 000 FC/mois, essai 7 jours, cycle 30 jours, 2 500 FC par
--       collaborateur — la plateforme peut l'ajuster ensuite dans l'écran).
--    5. Répare le pressing de `lucjean@gmail.com` : son espace passe en
--       type `pressing` (donc ses modules métier), et son entreprise suit.
--    6. Contrôle final + disponibilité des sorties de stock.
--
--  ⚠️ IDEMPOTENT : relançable sans doublon ni changement de prix.
--  ⚠️ Aucune donnée supprimée ; aucun montant d'abonnement payé n'est touché.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  0. ÉTAT DES LIEUX (AVANT) — le compte de lucjean@gmail.com
-- ============================================================================

select 'AVANT — COMPTE' as etape,
       u.email,
       coalesce(u.new_role::text, u.role) as role,
       u.entreprise_id                    as entreprise_active,
       u.espace_actif_id                  as espace_actif
  from public.utilisateurs u
 where lower(u.email) = 'lucjean@gmail.com';

select 'AVANT — ESPACES' as etape,
       s.nom                as espace,
       s.type,
       e.nom                as entreprise,
       e.type_activite,
       e.statut::text       as abonnement,
       g.nom                as groupe_tarifaire,
       e.montant_total_du
  from public.utilisateurs u
  left join public.espaces s
    on s.id = u.espace_actif_id
    or s.entreprise_id = u.entreprise_id
    or s.entreprise_id in (select e2.id from public.entreprises e2 where e2.owner_id = u.id)
  left join public.entreprises e on e.id = s.entreprise_id
  left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
 where lower(u.email) = 'lucjean@gmail.com';


-- ============================================================================
--  1. L'ACTIVITÉ « PRESSING & BLANCHISSERIE » DANS LE RÉFÉRENTIEL DES MÉTIERS
-- ============================================================================
--  C'est CETTE liste qu'affiche l'écran « Groupes tarification » : sans la
--  ligne, le pack pressing était impossible à créer.

do $$
declare
  v_cols text[];
  v_sql  text;
  v_id   uuid := gen_random_uuid();
begin
  if to_regclass('public.activites') is null then
    raise warning 'public.activites absente : activité pressing non ajoutée.';
    return;
  end if;

  if exists (
    select 1 from public.activites
     where lower(coalesce(nom, '')) like '%pressing%'
  ) then
    raise notice '0150 — l''activité « Pressing » existe déjà.';
    return;
  end if;

  select array_agg(column_name) into v_cols
    from information_schema.columns
   where table_schema = 'public' and table_name = 'activites';

  v_sql := 'insert into public.activites (nom';
  if 'id'          = any(v_cols) then v_sql := v_sql || ', id'; end if;
  if 'description'  = any(v_cols) then v_sql := v_sql || ', description'; end if;
  if 'actif'        = any(v_cols) then v_sql := v_sql || ', actif'; end if;

  v_sql := v_sql || ') values (''Pressing & Blanchisserie''';
  if 'id'          = any(v_cols) then
    v_sql := v_sql || format(', %L::uuid', v_id);
  end if;
  if 'description' = any(v_cols) then
    v_sql := v_sql ||
      ', ''Nettoyage à sec, lavage, repassage, détachage et remise des vêtements.''';
  end if;
  if 'actif'       = any(v_cols) then v_sql := v_sql || ', true'; end if;
  v_sql := v_sql || ')';

  execute v_sql;
  raise notice '0150 — activité « Pressing & Blanchisserie » ajoutée.';
exception
  when others then
    raise warning '0150 — activité pressing non ajoutée : %', sqlerrm;
end $$;


-- ============================================================================
--  2. LE PROFIL DE MODULES « PRESSING » (rappel tolérant)
-- ============================================================================
--  Il est créé par la migration 0120 ; cette section ne fait que le rendre
--  actif s'il avait été désactivé, sans jamais toucher à sa liste de modules
--  (l'Expert peut l'avoir personnalisée).

do $$
declare
  v_actif boolean;
begin
  if to_regclass('public.types_espaces_modules') is null then
    return;
  end if;

  if not exists (
    select 1 from public.types_espaces_modules where type = 'pressing'
  ) then
    insert into public.types_espaces_modules (type, libelle, modules)
    values (
      'pressing',
      'Pressing & Blanchisserie',
      '["pressing_depots","pressing_atelier","pressing_retraits","clients","finance","employes","rapports","assistant_ia"]'::jsonb
    );
    raise notice '0150 — profil « pressing » créé.';
    return;
  end if;

  select exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'types_espaces_modules'
       and column_name = 'actif'
  ) into v_actif;

  if v_actif then
    execute 'update public.types_espaces_modules set actif = true where type = ''pressing''';
  end if;
end $$;


-- ============================================================================
--  3. LES TYPES D'ACTIVITÉ DEVIENNENT CEUX DU RÉFÉRENTIEL
-- ============================================================================
--  Les contraintes de la migration 0083 ne connaissaient que `boutique` et
--  `distribution` : un pressing (ou un hôtel) ne pouvait pas être typé.
--  La liste reprend exactement l'énuméré Dart `TypeEspace`, pour que les
--  deux côtés ne divergent plus.

do $$
declare
  v_tbl        text;
  v_con        text;
  v_types      text[] := array[
    'boutique', 'distribution', 'pressing', 'depot', 'hotel', 'pharmacie',
    'restaurant', 'salle_fetes', 'boulangerie', 'boucherie', 'mode',
    'salon_de_coiffure', 'autre'
  ];
  v_nom_con    text;
begin
  foreach v_tbl in array array['entreprises', 'groupes_tarifaires', 'niveaux_abonnement']
  loop
    if to_regclass('public.' || v_tbl) is null then
      continue;
    end if;

    if not exists (
      select 1 from information_schema.columns
       where table_schema = 'public' and table_name = v_tbl
         and column_name = 'type_activite'
    ) then
      continue;
    end if;

    -- Toute contrainte CHECK existante sur `type_activite` est retirée
    -- (quel que soit son nom), puis reposée avec la liste élargie.
    for v_con in
      select c.conname
        from pg_constraint c
        join pg_class r on r.oid = c.conrelid
        join pg_namespace n on n.oid = r.relnamespace
       where n.nspname = 'public'
         and r.relname = v_tbl
         and c.contype = 'c'
         and pg_get_constraintdef(c.oid) ilike '%type_activite%'
    loop
      execute format('alter table public.%I drop constraint %I', v_tbl, v_con);
    end loop;

    v_nom_con := v_tbl || '_type_activite_check';

    execute format(
      'alter table public.%I add constraint %I '
      'check (type_activite is null or type_activite = any (%L::text[]))',
      v_tbl, v_nom_con, v_types
    );

    raise notice '0150 — contrainte % élargie.', v_nom_con;
  end loop;
end $$;


-- ============================================================================
--  4. LE GROUPE TARIFAIRE « PRESSING & BLANCHISSERIE — STANDARD »
-- ============================================================================
--  Sans ce forfait, un pressing n'a aucun prix propre : la grille par défaut
--  retombait sur le pack le moins cher (celui de la boutique).
--
--  Valeurs : base 10 000 FC / mois, essai 7 jours, cycle 30 jours, 2 500 FC
--  par collaborateur (réglage central de la plateforme), 1 entreprise.
--  La plateforme peut tout modifier ensuite depuis « Groupes tarification ».

do $$
declare
  v_act uuid;
  v_id  uuid;
begin
  if to_regclass('public.groupes_tarifaires') is null then
    raise warning 'public.groupes_tarifaires absente : pack pressing non créé.';
    return;
  end if;

  select id into v_act
    from public.activites
   where lower(coalesce(nom, '')) like '%pressing%'
   order by created_at
   limit 1;

  if v_act is null then
    raise warning '0150 — activité pressing introuvable : pack non créé.';
    return;
  end if;

  -- Déjà un pack pour cette activité ? On ne le réécrit pas (un prix
  -- négocié avec un client ne doit jamais être écrasé par une migration).
  select g.id into v_id
    from public.groupes_tarifaires g
   where g.activite_id = v_act
      or lower(coalesce(g.nom, '')) like '%pressing%'
   order by g.created_at nulls first
   limit 1;

  if v_id is not null then
    raise notice '0150 — pack pressing déjà présent (%), inchangé.', v_id;
    return;
  end if;

  begin
    insert into public.groupes_tarifaires (
      id, activite_id, nom, frais_ouverture, montant_abonnement,
      duree_essai_jours, duree_abonnement_jours, prix_par_collaborateur,
      max_espaces, modules, type_activite
    ) values (
      gen_random_uuid(), v_act, 'Pressing & Blanchisserie — Standard', 0, 10000,
      7, 30, 2500,
      1, '[]'::jsonb, 'pressing'
    );
    raise notice '0150 — pack « Pressing & Blanchisserie — Standard » créé (10 000 FC/mois).';
  exception
    when undefined_column then
      -- Base plus ancienne : on insère le minimum indispensable.
      begin
        insert into public.groupes_tarifaires (
          id, activite_id, nom, frais_ouverture, montant_abonnement,
          duree_essai_jours, duree_abonnement_jours, prix_par_collaborateur
        ) values (
          gen_random_uuid(), v_act, 'Pressing & Blanchisserie — Standard', 0, 10000,
          7, 30, 2500
        );
        raise notice '0150 — pack pressing créé (colonnes optionnelles absentes).';
      exception
        when others then
          raise warning '0150 — pack pressing non créé : %', sqlerrm;
      end;
    when others then
      raise warning '0150 — pack pressing non créé : %', sqlerrm;
  end;
end $$;


-- ============================================================================
--  5. RÉPARATION DU PRESSING DE `lucjean@gmail.com`
-- ============================================================================
--  « La boutique liée à lucjean@gmail.com, c'est ça le pressing. »
--
--  L'espace est reconnu comme pressing si :
--    • c'est son SEUL espace (cas normal d'un compte créé depuis setup), ou
--    • son nom (ou celui de son entreprise) contient « press ».
--  Rien d'autre n'est touché : ni le stock, ni les ventes, ni les montants.

do $$
declare
  v_uid        uuid;
  v_nb_espaces integer := 0;
  v_rec        record;
begin
  select u.id into v_uid
    from public.utilisateurs u
   where lower(u.email) = 'lucjean@gmail.com'
   limit 1;

  if v_uid is null then
    raise notice '0150 — lucjean@gmail.com introuvable : réparation ignorée.';
    return;
  end if;

  select count(*) into v_nb_espaces
    from public.espaces s
   where s.id = (select u.espace_actif_id from public.utilisateurs u where u.id = v_uid)
      or s.entreprise_id = (select u.entreprise_id from public.utilisateurs u where u.id = v_uid)
      or s.entreprise_id in (
           select e.id from public.entreprises e where e.owner_id = v_uid);

  for v_rec in
    select s.id, s.nom, coalesce(s.type, '(vide)') as type
      from public.espaces s
     where (
             s.id = (select u.espace_actif_id from public.utilisateurs u where u.id = v_uid)
             or s.entreprise_id = (select u.entreprise_id from public.utilisateurs u where u.id = v_uid)
             or s.entreprise_id in (
                  select e.id from public.entreprises e where e.owner_id = v_uid)
           )
       and coalesce(s.type, '') <> 'pressing'
       and (
             v_nb_espaces = 1
             or lower(coalesce(s.nom, '')) like '%press%'
             or lower(coalesce(
                  (select e.nom from public.entreprises e where e.id = s.entreprise_id),
                  '')) like '%press%'
           )
  loop
    update public.espaces set type = 'pressing' where id = v_rec.id;
    raise notice '0150 — espace « % » (%) → pressing.', v_rec.nom, v_rec.type;
  end loop;

  -- L'entreprise suit son espace : la grille par défaut (triggers 0107)
  -- choisira alors le pack pressing, sans réécrire un abonnement existant.
  update public.entreprises e
     set type_activite = 'pressing',
         updated_at    = now()
   where (
           e.owner_id = v_uid
           or e.id = (select u.entreprise_id from public.utilisateurs u where u.id = v_uid)
         )
     and coalesce(e.type_activite, '') <> 'pressing'
     and exists (
           select 1 from public.espaces s
            where s.entreprise_id = e.id and s.type = 'pressing');

  raise notice '0150 — réparation du pressing terminée (% espace(s) du compte).', v_nb_espaces;
end $$;


-- ============================================================================
--  6. CONTRÔLE (APRÈS)
-- ============================================================================

select 'APRÈS — ESPACES' as etape,
       u.email,
       s.nom                  as espace,
       s.type,
       e.nom                  as entreprise,
       e.type_activite,
       g.nom                  as groupe_tarifaire,
       e.montant_total_du
  from public.utilisateurs u
  left join public.espaces s
    on s.id = u.espace_actif_id
    or s.entreprise_id = u.entreprise_id
    or s.entreprise_id in (select e2.id from public.entreprises e2 where e2.owner_id = u.id)
  left join public.entreprises e on e.id = s.entreprise_id
  left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
 where lower(u.email) = 'lucjean@gmail.com';

select 'ACTIVITÉS DISPONIBLES' as etape, a.nom
  from public.activites a
 order by a.nom;

select 'PACKS TARIFAIRES' as etape,
       g.nom,
       a.nom                         as activite,
       g.montant_abonnement          as mensuel,
       g.duree_essai_jours           as essai,
       g.duree_abonnement_jours      as cycle,
       coalesce(g.type_activite, '(commun)') as type_activite
  from public.groupes_tarifaires g
  left join public.activites a on a.id = g.activite_id
 order by g.montant_abonnement, g.nom;

-- Les sorties de stock (consommation du propriétaire, offert, perte…) sont
-- indépendantes du pressing : ce contrôle rappelle simplement si elles sont
-- installées. Si `rpc_sortie_ok` est faux, exécuter
-- 20260916000132_sorties_stock_speciales.sql.
select 'SORTIES DE STOCK' as etape,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where p.proname = 'rpc_stock_sortie' and n.nspname = 'public') > 0 as rpc_sortie_ok,
       to_regclass('public.sorties_stock') is not null as table_sorties_ok,
       (select count(*) from pg_trigger t
         where t.tgname = 'trg_sorties_stock_appliquer'
           and not t.tgisinternal) > 0 as stock_applique_ok;

select 'MIGRATION 0150 TERMINÉE' as controle,
       'Reconnectez-vous dans l''application pour recharger la catégorie et les modules.' as consigne;
