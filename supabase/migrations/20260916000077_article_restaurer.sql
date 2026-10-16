-- ============================================================================
--  biashara_yangu — CORRECTIF 77 : VENDRE DEPUIS LA CAISSE
--                  (« Article n° 83 introuvable : il a peut-être été
--                   supprimé. »)
--  Migration 20260916000077_article_restaurer.sql
-- ============================================================================
--
--  ⛔ AUCUNE PUBLICATION. Correction de base uniquement.
--
--  LE PROBLÈME, EXPLIQUÉ PAR LA BASE
--  ---------------------------------
--  Le constat du patron : « quand je vends un produit simplement dans la
--  caisse, le produit se vend ; mais quand je passe par le panier et que je
--  valide la vente, on m'écrit : Article n° 83 introuvable : il a peut-être
--  été supprimé. »
--
--  Vérifié en direct sur la base (au 16/10/2026) :
--    • la boutique du patron possède 8 articles : n° 503 à 588 ;
--    • le n° 83 n'existe pas — et n'a jamais existé dans ce catalogue ;
--    • le même appel avec le n° 503 fonctionne : le serveur répond
--      « Stock insuffisant pour Eau Dasani » — la vente, elle, est saine.
--    ⇒ Le serveur ne reçoit PAS le numéro de l'article : il reçoit un autre
--      numéro. Le téléphone envoie l'identifiant **interne de son propre
--      fichier local** (1, 2, 3… 83), au lieu du numéro de la base.
--      C'est l'application qui doit corriger cela (correctif 77 côté Dart).
--
--  CE QUE LA BASE PEUT FAIRE, ELLE — ET CE QU'ELLE NE PEUT PAS
--  ---------------------------------------------------------
--  ⚠️ CE N'EST PAS LA SOLUTION AU PROBLÈME DE LA CAISSE. Le constat du patron
--     porte sur Urembo Market et *presque tous* ses articles : le téléphone
--     n'envoie qu'un NUMÉRO, et aucun numéro ne permet de deviner de quel
--     article il s'agit (nul ne sait ce que valait « 83 » sur ce téléphone).
--     La seule vraie solution est la mise à jour de l'application : elle
--     enverra désormais le numéro de la base (correctif 77 côté Dart).
--
--  En attendant, un téléphone déjà installé continuera d'envoyer ses anciens
--  numéros. La base peut donc **recréer un article SOUS LE NUMÉRO EXACT** que
--  ce téléphone réclame : l'article « réapparaît » et redevient vendable,
--  sans aucune mise à jour. C'est un outil de RÉPARATION PONCTUELLE (article
--  supprimé qu'on veut faire revivre sous son ancien numéro), jamais un
--  traitement de masse.
--
--  Pour une boutique entière, la solution immédiate est le SCANNER : il relit
--  l'article dans la base, donc avec le bon numéro. L'écran des QR codes
--  imprime une planche d'étiquettes pour tous les articles d'une boutique.
--
--  D'où deux outils, réservés au propriétaire et à la plateforme :
--
--   1. `rpc_articles_verifier([numéros])` — LECTURE : pour chaque numéro, dit
--      s'il existe, à qui il appartient et quel article c'est.
--      Sert à dresser la liste de ce qui manque avant de réparer.
--
--   2. `rpc_article_restaurer(numéro, nom, prix…)` — ÉCRITURE : recrée
--      l'article sous ce numéro précis. Refuse si le numéro est déjà pris (en
--      le disant, avec le nom de l'article qui l'occupe), et PRÉVIENT si un
--      article du même nom existe déjà — jamais de doublon silencieux.
--
--  ⚠️ On ne devine JAMAIS à quoi correspond un numéro : c'est le patron (ou
--     la plateforme) qui donne le nom et les prix de l'article, tels qu'ils
--     s'affichent sur son téléphone. Un article inventé fausserait le stock
--     et la caisse.
--
--  ⚠️ À exécuter dans Supabase → SQL Editor → coller → Run.
--  IDEMPOTENTE : relançable sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. `rpc_articles_verifier` — QUE DEVIENNENT CES NUMÉROS ? (LECTURE)
-- ============================================================================
--  Lecture seule, sans aucun effet : pour chaque numéro reçu, on répond
--  EXISTE / INTROUVABLE, avec le nom de l'article et sa boutique. Un numéro
--  peut appartenir à une AUTRE boutique : c'est précisément le cas à
--  détecter avant toute réparation.

create or replace function public.rpc_articles_verifier(
  p_boutique uuid default null,
  p_numeros  jsonb default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_boutique uuid := coalesce(p_boutique, public.mon_proprietaire(), auth.uid());
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour verifier un article.';
  end if;

  if not (public.est_plateforme()
          or v_boutique = auth.uid()
          or v_boutique = public.mon_proprietaire()) then
    raise exception 'DROIT_REFUSE|Vous ne pouvez pas consulter le catalogue de cette boutique.';
  end if;

  if p_numeros is null or jsonb_typeof(p_numeros) <> 'array' then
    raise exception 'LISTE_INVALIDE|Indiquez une liste de numeros (ex. [83, 91]).';
  end if;

  return jsonb_build_object(
    'ok', true,
    'boutique', v_boutique,
    'articles', coalesce((
      select jsonb_agg(jsonb_build_object(
               'numero',       n.numero,
               'existe',       (p.id is not null),
               'nom',          p.nom,
               'prix_vente',   p.prix_vente,
               'prix_achat',   p.prix_achat,
               'quantite',     p.quantite,
               'unite_mesure', p.unite_mesure,
               'categorie',    p.categorie,
               'boutique',     p.owner_id,
               'dans_ma_boutique', (p.owner_id = v_boutique)
             ) order by n.numero)
        from (
          select distinct nullif(btrim(x), '')::bigint as numero
            from jsonb_array_elements_text(p_numeros) as x
        ) n
        left join public.produits p on p.id = n.numero
       where n.numero is not null
    ), '[]'::jsonb)
  );
end $$;

comment on function public.rpc_articles_verifier(uuid, jsonb) is
  'Correctif 77 — LECTURE : pour une liste de numeros d''articles, dit lesquels existent, lesquels sont introuvables, et a quelle boutique ils appartiennent. Sert a preparer une reparation (telephones deja installes qui envoient d''anciens numeros).';


-- ============================================================================
--  2. `rpc_article_restaurer` — RECRÉER L'ARTICLE SOUS SON NUMÉRO
-- ============================================================================
--  Le téléphone réclame le n° 83 : on recrée l'article AVEC le n° 83.
--  `public.produits.id` accepte un numéro imposé (`generated by default as
--  identity`) : la suite automatique n'est pas perturbée pour autant.

create or replace function public.rpc_article_restaurer(
  p_numero       bigint,
  p_nom          text,
  p_prix_vente   numeric,
  p_boutique     uuid    default null,
  p_prix_achat   numeric default 0,
  p_quantite     numeric default 0,
  p_unite_mesure text    default 'unité',
  p_categorie    text    default '',
  p_seuil_alerte integer default 5,
  p_description  text    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_boutique  uuid := coalesce(p_boutique, public.mon_proprietaire(), auth.uid());
  v_nom       text := btrim(coalesce(p_nom, ''));
  v_unite     text := coalesce(nullif(btrim(coalesce(p_unite_mesure, '')), ''), 'unité');
  v_categorie text := coalesce(btrim(coalesce(p_categorie, '')), '');
  v_occupant  record;
  v_meme_nom  record;
begin
  -- ---------------------------------------------------------- 1. SESSION
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour reparer un article.';
  end if;

  if not (public.est_plateforme()
          or v_boutique = auth.uid()
          or v_boutique = public.mon_proprietaire()) then
    raise exception 'DROIT_REFUSE|Vous ne pouvez pas modifier le catalogue de cette boutique.';
  end if;

  -- ----------------------------------- 2. TOUT VÉRIFIER AVANT D'ÉCRIRE
  if v_boutique is null then
    raise exception 'BOUTIQUE_REQUISE|Indiquez la boutique concernee.';
  end if;

  if p_numero is null or p_numero < 1 then
    raise exception 'NUMERO_INVALIDE|Le numero de l''article doit etre un entier positif (celui affiche dans le message d''erreur).';
  end if;

  if length(v_nom) < 2 then
    raise exception 'NOM_REQUIS|Donnez le nom de l''article, tel qu''il s''affiche dans l''application (2 caracteres au moins).';
  end if;

  if coalesce(p_prix_vente, -1) < 0 then
    raise exception 'PRIX_INVALIDE|Le prix de vente ne peut pas etre negatif.';
  end if;

  if coalesce(p_prix_achat, 0) < 0 then
    raise exception 'PRIX_INVALIDE|Le prix d''achat ne peut pas etre negatif.';
  end if;

  if coalesce(p_quantite, 0) < 0 then
    raise exception 'QUANTITE_INVALIDE|La quantite en stock ne peut pas etre negative.';
  end if;

  -- ------------------------------- 3. LE NUMÉRO EST-IL DÉJÀ OCCUPÉ ?
  select p.id, p.nom, p.owner_id
    into v_occupant
    from public.produits p
   where p.id = p_numero;

  if found then
    if v_occupant.owner_id = v_boutique then
      -- L'article est déjà là : rien à réparer, on le dit (jamais d'écrasement).
      return jsonb_build_object(
        'ok', false,
        'motif', 'DEJA_LA',
        'produit_id', v_occupant.id,
        'nom', v_occupant.nom,
        'message', format(
          'Rien a reparer : le numero %s est deja celui de « %s » dans cette boutique.',
          p_numero, v_occupant.nom)
      );
    end if;

    -- Le numéro appartient à une AUTRE boutique : on refuse, et on le nomme.
    return jsonb_build_object(
      'ok', false,
      'motif', 'NUMERO_PRIS',
      'produit_id', v_occupant.id,
      'nom', v_occupant.nom,
      'message', format(
        'Le numero %s est deja pris par « %s » (une autre boutique). '
        'Verifiez le numero affiche dans le message d''erreur, ou enregistrez '
        'l''article normalement depuis « Nouvel article ».',
        p_numero, v_occupant.nom)
    );
  end if;

  -- ---------------------- 4. LE MÊME NOM EXISTE-T-IL DÉJÀ CHEZ NOUS ?
  --  On ne bloque pas (le patron peut vouloir deux lignes), mais on le DIT :
  --  un doublon silencieux fausserait le stock et les rapports.
  select p.id, p.nom
    into v_meme_nom
    from public.produits p
   where p.owner_id = v_boutique
     and public.biashara_normaliser(p.nom) = public.biashara_normaliser(v_nom)
   order by p.id
   limit 1;

  -- --------------------- 5. LA CRÉATION, SOUS LE NUMÉRO DEMANDÉ
  --  Le déclencheur `ARTICLE_CREE` du journal d'audit s'exécute aussi : la
  --  création est donc tracée deux fois (création + réparation), ce qui est
  --  exact — l'article a bel et bien été créé.
  insert into public.produits (
    id, nom, categorie, prix_achat, prix_vente, quantite, unite_mesure,
    owner_id, seuil_alerte, description, created_at, updated_at
  ) values (
    p_numero, v_nom, v_categorie,
    coalesce(p_prix_achat, 0), coalesce(p_prix_vente, 0), coalesce(p_quantite, 0),
    v_unite, v_boutique, greatest(coalesce(p_seuil_alerte, 5), 0),
    p_description, now(), now()
  );

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'ARTICLE_RESTAURE', auth.uid(),
    jsonb_build_object(
      'produit_id', p_numero,
      'nom',        v_nom,
      'boutique',   v_boutique,
      'quantite',   coalesce(p_quantite, 0),
      'prix_vente', coalesce(p_prix_vente, 0),
      'motif',      'article reclame par un telephone avec un numero absent de la base',
      'deja_present_avec_ce_nom', case
        when v_meme_nom.id is null then null
        else jsonb_build_object('produit_id', v_meme_nom.id, 'nom', v_meme_nom.nom)
      end
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'produit_id', p_numero,
    'nom', v_nom,
    'boutique', v_boutique,
    'avertissement', case
      when v_meme_nom.id is null then null
      else format('Attention : « %s » existe deja dans cette boutique sous le numero %s.',
                  v_meme_nom.nom, v_meme_nom.id)
    end,
    'message', format(
      'Article « %s » recree sous le numero %s : les telephones qui reclament ce numero peuvent de nouveau le vendre.',
      v_nom, p_numero)
  );
end $$;

comment on function public.rpc_article_restaurer(bigint, text, numeric, uuid, numeric, numeric, text, text, integer, text) is
  'Correctif 77 — REPARATION : recree un article SOUS LE NUMERO exact qu''un telephone deja installe reclame (« Article n° 83 introuvable »), afin qu''il redevienne vendable sans mise a jour de l''application. Refuse un numero deja occupe et signale un doublon de nom.';


-- ============================================================================
--  3. DROITS
-- ============================================================================
--  Les deux outils sont ouverts au personnel connecté : la fonction
--  elle-même vérifie que l'appelant est bien le propriétaire de la boutique
--  (ou la plateforme). Aucun accès anonyme.

revoke all on function public.rpc_articles_verifier(uuid, jsonb) from public, anon;
revoke all on function public.rpc_article_restaurer(bigint, text, numeric, uuid,
                                                    numeric, numeric, text, text,
                                                    integer, text) from public, anon;
grant execute on function public.rpc_articles_verifier(uuid, jsonb) to authenticated;
grant execute on function public.rpc_article_restaurer(bigint, text, numeric, uuid,
                                                       numeric, numeric, text, text,
                                                       integer, text) to authenticated;


-- ============================================================================
--  4. CONTRÔLE
-- ============================================================================

do $verif_77$
declare
  v_f1 integer;
  v_f2 integer;
begin
  select count(*) into v_f1
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_articles_verifier';

  select count(*) into v_f2
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_article_restaurer';

  if v_f1 <> 1 or v_f2 <> 1 then
    raise exception 'Correctif 77 : les outils de reparation sont incomplets (verifier=%, restaurer=%).',
      v_f1, v_f2;
  end if;

  if not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = 'rpc_article_restaurer'
       and p.prosecdef
  ) then
    raise exception 'Correctif 77 : la reparation doit etre `security definer`.';
  end if;

  raise notice 'Correctif 77 pret : reparer un article sous son numero est possible.';
end $verif_77$;


-- ============================================================================
--  MODE D'EMPLOI (à recopier tel quel dans le SQL Editor)
-- ============================================================================
--
--  a) Vérifier ce que deviennent les numéros qui échouent :
--
--     select public.rpc_articles_verifier(
--       p_numeros => '[83, 91, 503]'::jsonb          -- sans p_boutique : la vôtre
--     );
--
--  b) Recréer un article sous le numéro réclamé (le nom et les prix sont
--     ceux affichés dans l'application) :
--
--     select public.rpc_article_restaurer(
--       p_numero       => 83,
--       p_nom          => 'Nom de l''article',
--       p_prix_vente   => 2000,
--       p_prix_achat   => 1500,
--       p_quantite     => 10,
--       p_unite_mesure => 'piece'
--     );
--
--     → « ok: true » : le téléphone peut vendre cet article immédiatement.
--
--     `p_boutique` n'est à préciser QUE depuis un compte plateforme (Super
--     Admin), pour réparer la boutique d'un client : c'est
--     `public.produits.owner_id` (l'identifiant du propriétaire), que l'on
--     lit avec :
--
--       select id, owner_id, nom from public.produits order by id;
--
--  c) Contrôler le résultat :
--
--     select id, nom, prix_vente, quantite, owner_id
--       from public.produits where id = 83;
--
--     select action, details, created_at from public.journal_audit
--      where action = 'ARTICLE_RESTAURE' order by created_at desc limit 5;
-- ============================================================================

-- ============================================================================
--  RAPPORT FINAL
-- ============================================================================

select 'CORRECTIF 77 — ACTIF' as resultat,
       (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('rpc_articles_verifier', 'rpc_article_restaurer')) as outils_installes,
       (select count(*) from public.produits)                                as articles_en_base,
       (select count(distinct owner_id) from public.produits)                as boutiques_concernees,
       (select count(*) from public.journal_audit where action = 'ARTICLE_RESTAURE') as reparations_deja_faites;
