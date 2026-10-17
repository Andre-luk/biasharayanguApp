-- ============================================================================
--  biashara_yangu — CORRECTIF 78 : LE MARCHÉ SE REMPLIT TOUT SEUL
--  Migration 20260916000078_marketplace_automatique.sql
-- ============================================================================
--
--  LE CONSTAT DU PATRON
--  --------------------
--  « Le marketplace doit être en mesure d'interroger et d'afficher tous les
--    produits à partir de la base de données, sans que la boutique ne publie :
--    ça doit détecter automatiquement. »
--
--  POURQUOI UN ARTICLE N'APPARAISSAIT PAS
--  --------------------------------------
--  Trois verrous, tous « fermés par défaut ». Il fallait donc configurer
--  chaque article, une boutique à la fois — trop long, et impossible à tenir
--  en démonstration devant un client :
--
--    1. la VITRINE devait être marquée « visible publiquement »
--       (`espaces.visible_publiquement`, défaut FAUX) ;
--    2. la BOUTIQUE devait avoir des COORDONNÉES GPS — la vue publique
--       refusait toute boutique sans latitude/longitude, même complète ;
--    3. chaque ARTICLE devait avoir une ligne de publication
--       (`produits_publications.publie`), créée à la main.
--
--  CE QUE FAIT CE CORRECTIF
--  ------------------------
--  1. La vitrine est visible PAR DÉFAUT (nouvelle valeur par défaut + reprise
--     des boutiques existantes). Le commerçant peut toujours la retirer :
--     c'est un choix, plus une formalité.
--  2. La vue publique n'exige PLUS les coordonnées : une boutique sans
--     position est affichée (elle apparaît simplement en fin de liste, sans
--     distance). La position reste utile pour le tri et la carte, jamais
--     obligatoire.
--  3. Chaque article créé est PUBLIÉ AUTOMATIQUEMENT : un déclencheur crée sa
--     ligne de publication (publié + disponible), avec l'espace de sa
--     boutique. Les articles existants sont repris en une fois.
--
--  ⇒ Créer un article suffit : il est dans le marché à la seconde suivante.
--    Aucune configuration, aucune case à cocher.
--
--  CE QUI EST PRÉSERVÉ (et ne doit pas être cassé)
--  -----------------------------------------------
--   • un article VOLONTAIREMENT retiré du marché (`publie = false`) n'est
--     JAMAIS republié par le déclencheur : le déclencheur ne crée la ligne
--     que si elle n'existe pas ;
--   • une boutique en attente de validation, rejetée ou suspendue reste
--     invisible (contrôles du module 14 conservés) ;
--   • les prix d'achat, les stocks exacts et les données internes ne sortent
--     toujours pas : la vue publique garde sa liste blanche ;
--   • la vérification de l'abonnement (module 19) est inchangée.
--
--  ⚠️ À exécuter dans Supabase → SQL Editor → coller → Run.
--  IDEMPOTENTE : relançable sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA VITRINE EST VISIBLE PAR DÉFAUT
-- ============================================================================
--  `visible_publiquement` reste une colonne modifiable (Paramètres → Ma
--  vitrine) : on change seulement ce qui se passe QUAND ON NE CHOISIT PAS.

alter table public.espaces
  alter column visible_publiquement set default true;

comment on column public.espaces.visible_publiquement is
  'Correctif 78 — Vitrine visible dans le marché public. VRAI par défaut : créer sa boutique suffit pour être trouvé. Repasser à FAUX retire la boutique du marché (choix explicite du commerçant ou de la plateforme).';

do $m78_vitrine$
declare
  v_reprises integer := 0;
begin
  update public.espaces
     set visible_publiquement = true
   where not visible_publiquement;

  get diagnostics v_reprises = row_count;
  raise notice 'Correctif 78 : % vitrine(s) rendue(s) visible(s) par defaut.', v_reprises;
end $m78_vitrine$;


-- ============================================================================
--  2. LA VUE PUBLIQUE N'EXIGE PLUS LES COORDONNÉES GPS
-- ============================================================================
--  Recopie EXACTE de la vue du module 19 (même liste blanche de colonnes),
--  avec UNE seule différence : les deux conditions
--      `e.latitude is not null and e.longitude is not null`
--  disparaissent. Une boutique sans position est donc visible ; le tri par
--  distance la place simplement en fin de liste (`nulls last` côté RPC).

create or replace view public.v_biashara_boutiques
as
  select
    e.id                as espace_id,
    e.nom               as nom,
    e.slug              as slug,
    coalesce(e.type, 'boutique') as type,
    e.description_publique as description,
    e.telephone_public  as telephone,
    e.whatsapp          as whatsapp,
    e.horaires          as horaires,
    e.logo_url          as logo_url,
    e.photo_url         as photo_url,
    e.adresse           as adresse,
    e.quartier          as quartier,
    e.avenue            as avenue,
    e.numero            as numero,
    e.point_repere      as point_repere,
    e.latitude          as latitude,
    e.longitude         as longitude,
    e.statut_localisation as statut_localisation,
    e.precision_localisation as precision_localisation,
    e.ville_id          as ville_id,
    (select v.nom from public.villes v where v.id = e.ville_id) as ville,
    (select v.pays from public.villes v where v.id = e.ville_id) as pays,
    (select u.id
       from public.utilisateurs u
      where u.entreprise_id = e.entreprise_id
        and u.parent_id is null
      order by u.created_at
      limit 1) as owner_id,
    e.created_at        as created_at,
    coalesce(t.activation_etape, 'actif') as activation_etape,
    coalesce(t.statut::text, '') as statut_abonnement
  from public.espaces e
  join public.entreprises t on t.id = e.entreprise_id
 where e.visible_publiquement
   and e.actif
   -- 🔓 CORRECTIF 78 : plus de condition sur latitude/longitude.
   and coalesce(t.activation_etape, 'actif') in ('actif', 'restreint')
   and coalesce(t.statut::text, '') <> 'SUSPENDU';

comment on view public.v_biashara_boutiques is
  'Module 19 / correctif 78 — Vue PUBLIQUE des boutiques participantes (liste blanche de colonnes). Les coordonnées GPS ne sont plus obligatoires : une boutique sans position est visible, simplement classée sans distance.';


-- ============================================================================
--  3. CHAQUE ARTICLE EST PUBLIÉ AUTOMATIQUEMENT
-- ============================================================================
--  L'espace de rattachement est résolu par le propriétaire de l'article
--  (`produits.owner_id` → `utilisateurs.entreprise_id` → premier espace).
--  Si aucune boutique n'est encore créée, la ligne de publication est posée
--  SANS espace : elle sera rattachée à la première apparition d'un espace
--  (voir le rattrapage du point 4).

create or replace function public.trg_m78_publication_auto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_espace uuid;
begin
  -- Un article sans propriétaire ne peut pas être montré publiquement.
  if new.owner_id is null then
    return new;
  end if;

  -- L'espace (boutique) du propriétaire : c'est lui qui porte la vitrine.
  select e.id
    into v_espace
    from public.espaces e
    join public.utilisateurs u on u.entreprise_id = e.entreprise_id
   where u.id = new.owner_id
   order by e.created_at
   limit 1;

  -- `on conflict do nothing` : un article RETIRÉ du marché par le commerçant
  -- (publie = false) n'est jamais remis en ligne par surprise.
  --
  -- ⚠️ La publication est un CONFORT, jamais une condition : le déclencheur de
  --    blocage du module 19 refuse les comptes rejetés/suspendus, et cette
  --    erreur ne doit pas empêcher l'enregistrement d'un article.
  begin
    insert into public.produits_publications (
      produit_id, owner_id, espace_id, publie, disponible
    ) values (
      new.id, new.owner_id, v_espace, true, true
    )
    on conflict (produit_id) do nothing;
  exception
    when others then
      raise warning 'Correctif 78 : publication automatique impossible pour l''article % (%).',
        new.id, sqlerrm;
  end;

  return new;
end $$;

comment on function public.trg_m78_publication_auto() is
  'Correctif 78 — Creer un article le publie automatiquement dans le marche (ligne produits_publications). Ne republie jamais un article volontairement retire.';

drop trigger if exists trg_m78_publication_auto on public.produits;
create trigger trg_m78_publication_auto
  after insert on public.produits
  for each row
  execute function public.trg_m78_publication_auto();


-- ============================================================================
--  4. REPRISE DES ARTICLES DÉJÀ EN BASE
-- ============================================================================
--  Tout article sans ligne de publication en reçoit une, avec l'espace de sa
--  boutique. Les articles retirés (ligne existante avec publie = false) ne
--  sont pas touchés.

do $m78_publications$
declare
  v_crees integer := 0;
begin
  insert into public.produits_publications (
    produit_id, owner_id, espace_id, publie, disponible
  )
  select p.id,
         p.owner_id,
         (select e.id
            from public.espaces e
            join public.utilisateurs u on u.entreprise_id = e.entreprise_id
           where u.id = p.owner_id
           order by e.created_at
           limit 1),
         true,
         true
    from public.produits p
   where p.owner_id is not null
     -- Les comptes rejetés ou suspendus restent hors du marché (blocage du
     -- module 19) : on ne provoque pas d'erreur, on les écarte.
     and public.biashara_compte_operationnel(
           (select u.entreprise_id from public.utilisateurs u where u.id = p.owner_id))
     and not exists (
       select 1 from public.produits_publications pb where pb.produit_id = p.id
     );

  get diagnostics v_crees = row_count;
  raise notice 'Correctif 78 : % article(s) publie(s) automatiquement.', v_crees;
end $m78_publications$;

--  Rattrapage : une publication posée sans espace (boutique pas encore créée)
--  est rattachée dès qu'un espace existe pour son propriétaire.
do $m78_espaces$
declare
  v_rattaches integer := 0;
begin
  update public.produits_publications pb
     set espace_id = (select e.id
                        from public.espaces e
                        join public.utilisateurs u on u.entreprise_id = e.entreprise_id
                       where u.id = pb.owner_id
                       order by e.created_at
                       limit 1),
         updated_at = now()
   where pb.espace_id is null
     and public.biashara_compte_operationnel(
           (select u.entreprise_id from public.utilisateurs u where u.id = pb.owner_id))
     and exists (select 1
                   from public.espaces e
                   join public.utilisateurs u on u.entreprise_id = e.entreprise_id
                  where u.id = pb.owner_id);

  get diagnostics v_rattaches = row_count;
  raise notice 'Correctif 78 : % publication(s) rattachee(s) a leur vitrine.', v_rattaches;
end $m78_espaces$;


-- ============================================================================
--  5. CONTRÔLE
-- ============================================================================

do $verif_78$
declare
  v_trg      integer;
  v_sans_pub integer;
  v_invisib  integer;
  v_defaut   text;
begin
  select count(*) into v_trg
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
   where c.relname = 'produits'
     and t.tgname = 'trg_m78_publication_auto'
     and not t.tgisinternal;

  if v_trg <> 1 then
    raise exception 'Correctif 78 : le declencheur de publication automatique est absent.';
  end if;

  select count(*) into v_sans_pub
    from public.produits p
   where p.owner_id is not null
     and not exists (select 1 from public.produits_publications pb where pb.produit_id = p.id);

  select count(*) into v_invisib
    from public.espaces
   where not visible_publiquement;

  select coalesce(column_default, '') into v_defaut
    from information_schema.columns
   where table_schema = 'public' and table_name = 'espaces'
     and column_name = 'visible_publiquement';

  if v_sans_pub > 0 then
    raise warning 'Correctif 78 : % article(s) restent sans publication (proprietaire absent ?).', v_sans_pub;
  end if;

  raise notice 'Correctif 78 pret : vitrines visibles = %, defaut de colonne = %, articles sans publication = %.',
    (select count(*) from public.espaces where visible_publiquement), v_defaut, v_sans_pub;
end $verif_78$;


-- ============================================================================
--  RAPPORT FINAL
-- ============================================================================

select 'CORRECTIF 78 — ACTIF' as resultat,
       (select count(*) from public.produits
         where owner_id is not null)                              as articles_en_base,
       (select count(*) from public.produits_publications
         where publie)                                            as articles_publies,
       (select count(*) from public.espaces)                      as boutiques,
       (select count(*) from public.espaces where visible_publiquement) as boutiques_visibles,
       (select count(*) from public.v_biashara_boutiques)         as boutiques_dans_le_marche;
