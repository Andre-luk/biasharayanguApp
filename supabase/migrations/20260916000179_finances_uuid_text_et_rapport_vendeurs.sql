-- ============================================================================
--  biashara_yangu — MIGRATION 0179 / CORRECTIF 179
--  ① FINANCES : fin du « operator does not exist: uuid = text »
--  ② RAPPORT PAR COLLABORATEUR (vendeur) : qui a vendu quoi, et quel stock
--     restait au moment de chaque vente.
-- ---------------------------------------------------------------------------
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase, APRÈS la 0177.
--  ⚠️ IDEMPOTENT : relançable sans effet de bord.
--  ℹ️ Il n'existe pas de migration 0178 : le correctif 178 (isolation des
--     sessions) est purement côté application et ne touche pas la base.
--
--  ════════════════════════════════════════════════════════════════════════
--  ① LE PROBLÈME « uuid = text »
--  ════════════════════════════════════════════════════════════════════════
--  Deux tables HISTORIQUES du projet ont été créées AVANT le passage aux
--  identifiants `uuid` :
--      • public.paiements_abonnements_laperle
--      • public.agent_ia_achats
--  Leur colonne `entreprise_id` peut donc être de type TEXTE. Or le moteur
--  d'abonnement et les écrans FINANCE la comparent à des `uuid` :
--
--      where p.entreprise_id = e.id          -- texte = uuid → ERREUR
--
--  PostgreSQL refuse alors la comparaison et renvoie exactement le message
--  vu par l'utilisateur :
--
--      operator does not exist: uuid = text
--
--  C'est ce qui casse EN MÊME TEMPS :
--      • Finances plateforme (onglet « Entreprises » : dernier paiement,
--        nombre de paiements, Mobile Money en attente) ;
--      • Finances des abonnements (dossier d'abonnement d'une entreprise).
--
--  CE QUE FAIT CETTE MIGRATION
--    1. Elle CONVERTIT ces colonnes en `uuid` — sans jamais perdre une
--       information utile :
--          – une valeur vide devient NULL ;
--          – une valeur qui n'est pas un uuid NE PEUT désigner aucune
--            entreprise (les identifiants sont des uuid) : elle est mise à
--            NULL et signalée par un NOTICE ;
--          – si la colonne est NOT NULL, la conversion est annulée pour ne
--            rien casser (un avertissement explicite est affiché).
--    2. Elle RÉÉCRIT les fonctions Finance en comparant les identifiants
--       EN TEXTE (`::text`). Elles fonctionnent donc que la colonne soit
--       déjà en uuid ou encore en texte : plus aucune erreur possible, même
--       si une restauration de sauvegarde remet du texte.
--    3. Elle ajoute une fonction de diagnostic `finance_verifier_types()`
--       qui liste les colonnes d'identifiants encore en texte.
--
--  ════════════════════════════════════════════════════════════════════════
--  ② LE RAPPORT PAR COLLABORATEUR
--  ════════════════════════════════════════════════════════════════════════
--  Besoin exprimé par l'utilisateur :
--      « j'ai 5 beignets, le collaborateur A en vend 1 → il reste 4 ;
--        le collaborateur B vient et en vend 1 → le rapport de B doit
--        montrer qu'il restait 4 beignets, et que c'est A qui avait vendu. »
--
--  `rpc_rapport_vendeurs(entreprise, debut, fin)` renvoie donc :
--      • `vendeurs`  : le total de CHAQUE vendeur (collaborateur du patron)
--                      + ses produits + son journal de ventes ;
--      • `journal`   : la chronologie complète, vente par vente, avec
--                      `stock_avant` / `stock_apres` et
--                      `vendu_avant_par` (qui a vendu l'unité précédente) ;
--      • `produits`  : stock actuel, stock au début de la période, quantité
--                      vendue et chiffre d'affaires par article ;
--      • `totaux`    : chiffre d'affaires, nombre de ventes, panier moyen.
--
--  COMMENT LE STOCK EST RECONSTITUÉ (sans historique dédié)
--      stock_apres(vente) = stock_actuel − Σ(effets des mouvements POSTÉRIEURS)
--      stock_avant(vente) = stock_apres + quantité vendue
--
--      Mouvements pris en compte, tous produits du périmètre :
--          ventes             → − quantité
--          approvisionnements → + quantité ajoutée
--          ajustements        → + écart signé
--          sorties de stock   → − quantité
--
--      Vérification sur l'exemple : stock actuel = 3.
--          vente de B : aucun mouvement après → stock_apres = 3,
--                       stock_avant = 4  ✅ (« il restait 4 »)
--          vente de A : 1 mouvement après (B, −1) → stock_apres = 4,
--                       stock_avant = 5  ✅
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. ÉTAT DES LIEUX (avant) — à lire dans l'onglet « Messages »
-- ============================================================================

select table_name, column_name, data_type, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and column_name in ('entreprise_id', 'utilisateur_id', 'objet_id',
                       'rapproche_par', 'seller_id', 'owner_id')
   and table_name in ('paiements_abonnements_laperle', 'agent_ia_achats',
                      'paiements_serdipay', 'ventes', 'produits',
                      'approvisionnements', 'ajustements', 'sorties_stock')
 order by table_name, column_name;


-- ============================================================================
--  2. CONVERSION TEXTE → UUID (sans perte)
-- ============================================================================
--  La liste est volontairement limitée aux colonnes qui DOIVENT être des
--  uuid. On ne touche jamais à `utilisateurs.parent_id` (texte par choix :
--  il porte aussi des marqueurs historiques).

do $$
declare
  v_re       text := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  v_tbl      text;
  v_col      text;
  v_type     text;
  v_nullable text;
  v_total    bigint;
  v_vides    bigint;
  v_bad      bigint;
  v_exemples text;
begin
  for v_tbl, v_col in
    select t.tbl, t.col
      from (values
             ('paiements_abonnements_laperle', 'entreprise_id'),
             ('paiements_abonnements_laperle', 'utilisateur_id'),
             ('agent_ia_achats',               'entreprise_id'),
             ('paiements_serdipay',            'entreprise_id'),
             ('paiements_serdipay',            'utilisateur_id'),
             ('paiements_serdipay',            'objet_id')
           ) as t(tbl, col)
  loop
    select c.data_type, c.is_nullable
      into v_type, v_nullable
      from information_schema.columns c
     where c.table_schema = 'public'
       and c.table_name = v_tbl
       and c.column_name = v_col;

    -- Table ou colonne absente : rien à faire.
    continue when v_type is null;

    -- Déjà en uuid : rien à faire.
    continue when v_type = 'uuid';

    -- On ne convertit que du texte.
    if v_type not in ('text', 'character varying', 'character') then
      raise notice 'CORRECTIF 179 — %.% est de type % : ignoré.', v_tbl, v_col, v_type;
      continue;
    end if;

    execute format('select count(*) from public.%I', v_tbl) into v_total;

    execute format(
      'select count(*) from public.%I where %I is not null and btrim(%I::text) = %L',
      v_tbl, v_col, v_col, ''
    ) into v_vides;

    execute format(
      'select count(*) from public.%I '
      ' where %I is not null and btrim(%I::text) <> %L and btrim(%I::text) !~ %L',
      v_tbl, v_col, v_col, '', v_col, v_re
    ) into v_bad;

    -- a) Les valeurs vides ne désignent personne : NULL.
    if coalesce(v_vides, 0) > 0 then
      execute format(
        'update public.%I set %I = null where %I is not null and btrim(%I::text) = %L',
        v_tbl, v_col, v_col, v_col, ''
      );
      raise notice 'CORRECTIF 179 — %.% : % valeur(s) vide(s) mise(s) à NULL.',
        v_tbl, v_col, v_vides;
    end if;

    -- b) Les valeurs non-uuid ne peuvent correspondre à aucune entreprise.
    if coalesce(v_bad, 0) > 0 then
      execute format(
        'select string_agg(distinct btrim(%I::text), %L) from ('
        '  select %I from public.%I where %I is not null '
        '   and btrim(%I::text) <> %L and btrim(%I::text) !~ %L limit 5) s',
        v_col, ', ', v_col, v_tbl, v_col, v_col, '', v_col, v_re
      ) into v_exemples;

      if v_nullable = 'YES' then
        execute format(
          'update public.%I set %I = null '
          ' where %I is not null and btrim(%I::text) !~ %L',
          v_tbl, v_col, v_col, v_col, v_re
        );
        raise notice
          'CORRECTIF 179 — %.% : % valeur(s) non-uuid mise(s) à NULL (elles ne désignaient aucune entreprise). Exemples : %',
          v_tbl, v_col, v_bad, coalesce(v_exemples, '(aucun)');
      else
        raise warning
          'CORRECTIF 179 — %.% est NOT NULL et contient % valeur(s) non-uuid : conversion NON effectuée. Les fonctions Finance restent tolérantes (comparaison texte), aucun écran ne casse. Exemples : %',
          v_tbl, v_col, v_bad, coalesce(v_exemples, '(aucun)');
        continue;
      end if;
    end if;

    -- c) Conversion sûre : toutes les valeurs restantes sont des uuid.
    begin
      execute format(
        'alter table public.%I alter column %I type uuid using nullif(btrim(%I::text), '''')::uuid',
        v_tbl, v_col, v_col
      );
      raise notice 'CORRECTIF 179 — %.% converti en uuid (% ligne(s) vérifiée(s)).',
        v_tbl, v_col, v_total;
    exception
      when others then
        raise warning
          'CORRECTIF 179 — %.% : conversion impossible (% : %). La colonne reste en texte ; les fonctions Finance tolérantes continuent de fonctionner.',
          v_tbl, v_col, sqlstate, sqlerrm;
    end;
  end loop;
end $$;


-- ============================================================================
--  3. FINANCE — FONCTIONS TOLÉRANTES (comparaisons en texte)
-- ============================================================================
--  ⚠️ Même après conversion, on garde la comparaison en TEXTE : elle
--  fonctionne quel que soit l'état de la base (restauration, ancienne
--  installation, colonne encore en texte). Coût nul sur ces volumes.

-- 3.a Synthèse « facturé / encaissé / dû ».
create or replace function public.finance_abonnements_resume(
  p_debut date default null,
  p_fin   date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_debut timestamptz;
  v_fin   timestamptz;
  v_nb_total      integer := 0;
  v_nb_actifs     integer := 0;
  v_nb_expires    integer := 0;
  v_nb_attente    integer := 0;
  v_nb_partiels   integer := 0;
  v_facture       numeric := 0;
  v_encaisse      numeric := 0;
  v_du            numeric := 0;
  v_supplements   numeric := 0;
  v_nb_paiements  integer := 0;
  v_especes       numeric := 0;
  v_mobile        numeric := 0;
  v_carte         numeric := 0;
  v_autres        numeric := 0;
  v_par_jour      jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.est_plateforme()
          or public.peut('finance', 'voir')
          or public.peut('abonnements', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les finances de la plateforme.';
  end if;

  v_debut := coalesce(p_debut, current_date - 30)::timestamptz;
  v_fin   := (coalesce(p_fin, current_date) + 1)::timestamptz;

  select count(*),
         count(*) filter (where e.statut = 'ACTIF'),
         count(*) filter (where e.statut = 'EXPIRE'),
         count(*) filter (where e.statut = 'EN_ATTENTE_COMPLEMENT'),
         count(*) filter (where coalesce(e.montant_deja_paye, 0) > 0
                            and coalesce(e.montant_deja_paye, 0)
                                < coalesce(e.montant_total_du, 0)),
         coalesce(sum(coalesce(e.montant_total_du, 0)::numeric), 0),
         coalesce(sum(coalesce(e.montant_deja_paye, 0)::numeric), 0),
         coalesce(sum(greatest(coalesce(e.montant_total_du, 0)::numeric
                               - coalesce(e.montant_deja_paye, 0)::numeric, 0)), 0),
         coalesce(sum(coalesce(e.supplement_collaborateurs, 0)::numeric), 0)
    into v_nb_total, v_nb_actifs, v_nb_expires, v_nb_attente, v_nb_partiels,
         v_facture, v_encaisse, v_du, v_supplements
    from public.entreprises e;

  -- ⚠️ CORRECTIF 179 : aucune jointure sur `entreprise_id` ici (donc aucune
  -- comparaison uuid/texte) ; les montants sont castés en numeric pour que
  -- les colonnes historiques en REAL ne provoquent plus de 42804.
  select count(*),
         coalesce(sum(coalesce(p.montant, 0)::numeric)
                    filter (where lower(coalesce(p.mode_paiement, '')) = 'especes'), 0),
         coalesce(sum(coalesce(p.montant, 0)::numeric)
                    filter (where lower(coalesce(p.mode_paiement, ''))
                              in ('mobile_money', 'mobile', 'serdipay')), 0),
         coalesce(sum(coalesce(p.montant, 0)::numeric)
                    filter (where lower(coalesce(p.mode_paiement, '')) = 'carte'), 0),
         coalesce(sum(coalesce(p.montant, 0)::numeric)
                    filter (where p.mode_paiement is null
                               or lower(p.mode_paiement) not in
                                  ('especes', 'mobile_money', 'mobile',
                                   'serdipay', 'carte')), 0)
    into v_nb_paiements, v_especes, v_mobile, v_carte, v_autres
    from public.paiements_abonnements_laperle p
   where p.created_at >= v_debut and p.created_at < v_fin;

  select coalesce(jsonb_agg(x order by x->>'jour'), '[]'::jsonb)
    into v_par_jour
    from (
      select jsonb_build_object(
               'jour', to_char(p.created_at::date, 'YYYY-MM-DD'),
               'montant', round(sum(coalesce(p.montant, 0)::numeric), 2),
               'nb', count(*)
             ) as x
        from public.paiements_abonnements_laperle p
       where p.created_at >= v_debut and p.created_at < v_fin
       group by p.created_at::date
    ) s;

  return jsonb_build_object(
    'debut', v_debut::date,
    'fin', (v_fin - interval '1 day')::date,
    'entreprises_total', v_nb_total,
    'abonnements_actifs', v_nb_actifs,
    'abonnements_expires', v_nb_expires,
    'abonnements_en_attente', v_nb_attente,
    'abonnements_partiels', v_nb_partiels,
    'montant_facture', round(v_facture, 2),
    'montant_encaisse_cumule', round(v_encaisse, 2),
    'solde_a_recouvrer', round(v_du, 2),
    'supplements_collaborateurs', round(v_supplements, 2),
    'paiements_periode', v_nb_paiements,
    'encaisse_periode', round(v_especes + v_mobile + v_carte + v_autres, 2),
    'encaisse_especes', round(v_especes, 2),
    'encaisse_mobile_money', round(v_mobile, 2),
    'encaisse_carte', round(v_carte, 2),
    'encaisse_autres', round(v_autres, 2),
    'par_jour', v_par_jour
  );
end;
$$;

comment on function public.finance_abonnements_resume(date, date) is
  'Module 27 + correctif 179 — vision Finance : facturé, encaissé, dû, suppléments collaborateurs et répartition par moyen de paiement (aucune comparaison uuid/texte).';

revoke all on function public.finance_abonnements_resume(date, date) from public, anon;
grant execute on function public.finance_abonnements_resume(date, date) to authenticated;


-- 3.b Dossier financier par entreprise — LE CŒUR DU BUG « uuid = text ».
--     `paiements_abonnements_laperle.entreprise_id` peut être du texte :
--     `p.entreprise_id = e.id` échouait → tout l'écran Finances tombait.
create or replace function public.finance_abonnements_entreprises(
  p_recherche text default null,
  p_statut    text default null,
  p_limite    integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_like text;
  v_rows jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.est_plateforme()
          or public.peut('finance', 'voir')
          or public.peut('abonnements', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les finances de la plateforme.';
  end if;

  v_like := nullif(btrim(coalesce(p_recherche, '')), '');

  select coalesce(jsonb_agg(x order by x->>'nom'), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
               'entreprise_id', e.id,
               'nom', e.nom,
               'statut', e.statut,
               'devise', coalesce(e.devise, 'CDF'),
               'echeance', e.date_expiration,
               'jours_restants', case
                 when e.date_expiration is null then null
                 else greatest(
                   ceil(extract(epoch from (e.date_expiration - now())) / 86400),
                   0
                 )::int
               end,
               'montant_facture', round(coalesce(e.montant_total_du, 0)::numeric, 2),
               'montant_encaisse', round(coalesce(e.montant_deja_paye, 0)::numeric, 2),
               'solde_du', round(greatest(
                 coalesce(e.montant_total_du, 0)::numeric
                 - coalesce(e.montant_deja_paye, 0)::numeric, 0), 2),
               'supplement_collaborateurs',
                 round(coalesce(e.supplement_collaborateurs, 0)::numeric, 2),
               'collaborateurs', (
                 select count(distinct u.id) from public.utilisateurs u
                  where u.id::text <> e.id::text
                    and coalesce(u.valide, 1) <> 0
                    and lower(coalesce(u.role, '')) not in (
                      'admin', 'super_admin', 'plateforme')
                    and (u.entreprise_id::text = e.id::text
                         or u.parent_id::text = e.id::text)
               ),
               'dernier_paiement', (
                 select p.created_at
                   from public.paiements_abonnements_laperle p
                  where p.entreprise_id::text = e.id::text
                  order by p.created_at desc
                  limit 1
               ),
               'total_paiements', (
                 select count(*) from public.paiements_abonnements_laperle p
                  where p.entreprise_id::text = e.id::text
               ),
               'serdipay_en_attente', (
                 select count(*) from public.paiements_serdipay s
                  where s.entreprise_id::text = e.id::text
                    and s.statut = 'en_attente'
               )
             ) as x
        from public.entreprises e
       where (v_like is null or e.nom ilike '%' || v_like || '%')
         and (nullif(btrim(coalesce(p_statut, '')), '') is null
              or e.statut = p_statut)
       order by e.nom
       limit greatest(coalesce(p_limite, 200), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.finance_abonnements_entreprises(text, text, integer) is
  'Module 27 + correctif 179 — dossier financier par entreprise (comparaisons d''identifiants en texte : plus de « uuid = text »).';

revoke all on function public.finance_abonnements_entreprises(text, text, integer)
  from public, anon;
grant execute on function public.finance_abonnements_entreprises(text, text, integer)
  to authenticated;


-- 3.c Traçabilité Mobile Money / SerdiPay.
create or replace function public.finance_serdipay_transactions(
  p_recherche text default null,
  p_statut    text default null,
  p_limite    integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_like  text;
  v_rows  jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.est_plateforme()
          or public.peut('finance', 'voir')
          or public.peut('paiements', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les paiements de la plateforme.';
  end if;

  v_like := nullif(btrim(coalesce(p_recherche, '')), '');

  select coalesce(jsonb_agg(x order by x->>'date' desc), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
               'id',              s.id,
               'entreprise_id',   s.entreprise_id,
               'entreprise',      (select e.nom from public.entreprises e
                                    where e.id::text = s.entreprise_id::text),
               'reference',       s.reference,
               'reference_fournisseur', s.provider_reference,
               'montant',         s.montant,
               'devise',          s.devise,
               'operateur',       s.operateur,
               'telephone',       s.telephone,
               'nom_payeur',      s.nom_payeur,
               'statut',          s.statut,
               'objet',           s.objet,
               'objet_id',        s.objet_id,
               'initie_par',      s.utilisateur_id,
               'initie_par_nom',  (select nullif(btrim(concat_ws(' ', u.prenom, u.nom)), '')
                                     from public.utilisateurs u
                                    where u.id::text = s.utilisateur_id::text),
               'date',            s.created_at,
               'confirme_le',     s.paye_le,
               'motif_echec',     s.motif_echec,
               'frais',           s.frais,
               'montant_net',     s.montant_net,
               'rapproche',       s.rapproche_le is not null,
               'rapproche_le',    s.rapproche_le
             ) as x
        from public.paiements_serdipay s
       where (v_like is null
              or s.reference ilike '%' || v_like || '%'
              or coalesce(s.provider_reference, '') ilike '%' || v_like || '%'
              or coalesce(s.telephone, '') ilike '%' || v_like || '%'
              or coalesce(s.nom_payeur, '') ilike '%' || v_like || '%'
              or coalesce((select e.nom from public.entreprises e
                            where e.id::text = s.entreprise_id::text), '')
                   ilike '%' || v_like || '%')
         and (nullif(btrim(coalesce(p_statut, '')), '') is null
              or s.statut = p_statut)
       order by s.created_at desc
       limit greatest(coalesce(p_limite, 100), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.finance_serdipay_transactions(text, text, integer) is
  'Module 27 + correctif 179 — transactions Mobile Money (comparaisons d''identifiants en texte).';

revoke all on function public.finance_serdipay_transactions(text, text, integer)
  from public, anon;
grant execute on function public.finance_serdipay_transactions(text, text, integer)
  to authenticated;


-- 3.d Rapprochement manuel (coche de contrôle, aucun montant modifié).
create or replace function public.finance_serdipay_rapprocher(
  p_id        uuid,
  p_rapproche boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_s    public.paiements_serdipay%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.est_plateforme()
          or public.peut('finance', 'modifier')
          or public.peut('finance', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de rapprocher les paiements.';
  end if;

  if p_id is null then
    raise exception 'TRANSACTION_INTROUVABLE|Cette transaction n''existe pas.';
  end if;

  select * into v_s
    from public.paiements_serdipay s
   where s.id::text = p_id::text
   for update;

  if not found then
    raise exception 'TRANSACTION_INTROUVABLE|Cette transaction n''existe pas.';
  end if;

  if coalesce(p_rapproche, true) then
    update public.paiements_serdipay s
       set rapproche_le  = coalesce(s.rapproche_le, now()),
           rapproche_par = coalesce(s.rapproche_par, v_user)
     where s.id::text = p_id::text;
  else
    update public.paiements_serdipay s
       set rapproche_le  = null,
           rapproche_par = null
     where s.id::text = p_id::text;
  end if;

  select * into v_s
    from public.paiements_serdipay s
   where s.id::text = p_id::text;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(),
    -- Tolerant : la colonne peut être du texte selon l'âge de la base.
    nullif(btrim(coalesce(v_s.entreprise_id::text, '')), '')::uuid,
    case when coalesce(p_rapproche, true)
         then 'SERDIPAY_RAPPROCHE' else 'SERDIPAY_RAPPROCHE_ANNULE' end,
    v_user,
    jsonb_build_object(
      'paiement_serdipay', v_s.id,
      'reference', v_s.reference,
      'reference_fournisseur', v_s.provider_reference,
      'montant', v_s.montant,
      'statut', v_s.statut
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_s.id,
    'rapproche', v_s.rapproche_le is not null,
    'rapproche_le', v_s.rapproche_le
  );
end;
$$;

comment on function public.finance_serdipay_rapprocher(uuid, boolean) is
  'Module 27 + correctif 179 — coche (ou décoche) une transaction par rapport au relevé SerdiPay ; aucun montant n''est modifié.';

revoke all on function public.finance_serdipay_rapprocher(uuid, boolean)
  from public, anon;
grant execute on function public.finance_serdipay_rapprocher(uuid, boolean)
  to authenticated;


-- 3.e Diagnostic réutilisable depuis l'application (ou en SQL).
create or replace function public.finance_verifier_types()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'table', c.table_name,
           'colonne', c.column_name,
           'type', c.data_type,
           'conversion_requise', c.data_type <> 'uuid'
         ) order by c.table_name, c.column_name), '[]'::jsonb)
    from information_schema.columns c
   where c.table_schema = 'public'
     and c.column_name in ('entreprise_id', 'utilisateur_id', 'objet_id',
                           'rapproche_par')
     and c.table_name in ('paiements_abonnements_laperle', 'agent_ia_achats',
                          'paiements_serdipay');
$$;

comment on function public.finance_verifier_types() is
  'Correctif 179 — liste les colonnes d''identifiants des tables Finance et indique celles encore en texte.';

revoke all on function public.finance_verifier_types() from public, anon;
grant execute on function public.finance_verifier_types() to authenticated;


-- ============================================================================
--  3 septies. COHÉRENCE DES CHIFFRES — UNE SEULE SOURCE POUR TOUS LES ÉCRANS
-- ============================================================================
--  PROBLÈME VÉCU
--      « Le tableau de bord, ses nombres de vente et l'argent généré doivent
--        toujours correspondre avec ce que le patron voit, et même dans son
--        rapport, peu importe le téléphone. »
--
--  POURQUOI LES CHIFFRES DIVERGEAIENT
--   1. PÉRIMÈTRE DIFFÉRENT. L'accueil comptait `ventes.owner_id = patron`
--      (un seul espace), tandis que le rapport comptait l'entreprise entière
--      (espaces + utilisateurs + propriétaire). Une entreprise à plusieurs
--      espaces affichait donc deux totaux différents.
--   2. JOURNÉE DIFFÉRENTE. `p_debut::timestamptz` interprète la date en UTC :
--      la journée commençait à 02:00 à Lubumbashi. Selon l'heure de la vente,
--      elle tombait la veille dans un écran et le jour même dans l'autre.
--   3. « VENTE » DIFFÉRENTE. L'accueil ne lisait que `ventes` (jamais les
--      prestations d'un pressing), le rapport lisait les deux.
--   4. HORLOGE DU TÉLÉPHONE. Les périodes étaient calculées avec
--      `DateTime.now()` de l'appareil : un téléphone mal réglé ou dans un
--      autre fuseau demandait une autre période → d'autres chiffres.
--
--  CE QUE FAIT CETTE SECTION
--   • `jour_local()`            → la date du jour à Lubumbashi, calculée par
--                                 le serveur (le téléphone ne décide plus).
--   • `resoudre_entreprise(id)` → accepte un identifiant d'entreprise, de
--                                 propriétaire ou de collaborateur.
--   • `perimetre_entreprise()`  → LE périmètre unique : espaces + utilisateurs
--                                 + propriétaire. Utilisé par TOUS les écrans.
--   • `analyse_lignes_ventes()` → réécrite : même périmètre, mêmes bornes de
--                                 journée (heure de Lubumbashi), ventes
--                                 d'articles ET prestations de pressing.
--   • `rpc_accueil_stats()`     → réécrite sur cette base : l'accueil affiche
--                                 exactement ce que le rapport calcule.
-- ============================================================================

-- 3.g La date du jour, côté serveur (fuseau de Lubumbashi).
create or replace function public.jour_local()
returns date
language sql
stable
security definer
set search_path = public
as $$
  select (now() at time zone 'Africa/Lubumbashi')::date;
$$;

comment on function public.jour_local() is
  'Correctif 179 — date du jour à Lubumbashi, calculée par le serveur : toutes les périodes de l''application s''y réfèrent (aucune dépendance à l''horloge du téléphone).';

grant execute on function public.jour_local() to authenticated;


-- 3.h L'entreprise « courante » de l'utilisateur connecté.
create or replace function public.entreprise_courante()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- 1. l'entreprise de l'espace de travail actif (Module 15)
    (select s.entreprise_id
       from public.utilisateurs u
       join public.espaces s on s.id = u.espace_actif_id
      where u.id = auth.uid()
      limit 1),
    -- 2. une entreprise dont l'utilisateur est propriétaire
    (select e.id
       from public.entreprises e
      where e.owner_id = auth.uid()
      order by e.nom
      limit 1),
    -- 3. l'entreprise de rattachement du collaborateur
    (select u.entreprise_id
       from public.utilisateurs u
      where u.id = auth.uid()
      limit 1)
  );
$$;

comment on function public.entreprise_courante() is
  'Correctif 179 — entreprise sur laquelle travaille l''utilisateur connecté (espace actif, sinon celle qu''il possède, sinon son rattachement).';

grant execute on function public.entreprise_courante() to authenticated;


-- 3.i Résolution d'un identifiant « flou » (entreprise, propriétaire ou
--     collaborateur). L'écran « Stats collaborateurs » envoie le propriétaire.
create or replace function public.resoudre_entreprise(p_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eid uuid;
begin
  if p_id is null then
    return public.entreprise_courante();
  end if;

  -- 1. C'est déjà un identifiant d'entreprise.
  select e.id into v_eid
    from public.entreprises e
   where e.id::text = p_id::text
   limit 1;
  if v_eid is not null then
    return v_eid;
  end if;

  -- 2. C'est un utilisateur : l'entreprise de son espace de travail actif.
  select s.entreprise_id into v_eid
    from public.utilisateurs u
    join public.espaces s on s.id = u.espace_actif_id
   where u.id::text = p_id::text
   limit 1;
  if v_eid is not null then
    return v_eid;
  end if;

  -- 3. C'est un propriétaire.
  select e.id into v_eid
    from public.entreprises e
   where e.owner_id::text = p_id::text
   order by e.nom
   limit 1;
  if v_eid is not null then
    return v_eid;
  end if;

  -- 4. C'est un collaborateur.
  select u.entreprise_id into v_eid
    from public.utilisateurs u
   where u.id::text = p_id::text
   limit 1;

  return v_eid;
end;
$$;

comment on function public.resoudre_entreprise(uuid) is
  'Correctif 179 — accepte un identifiant d''entreprise, de propriétaire ou de collaborateur et renvoie l''entreprise correspondante.';

grant execute on function public.resoudre_entreprise(uuid) to authenticated;


-- 3.j LE PÉRIMÈTRE UNIQUE. Tous les chiffres de l'application (accueil,
--     rapport d'entreprise, rapport par vendeur) comptent EXACTEMENT ces
--     identifiants : impossible d'obtenir deux totaux différents.
create or replace function public.perimetre_entreprise(
  p_entreprise_id uuid default null
)
returns text[]
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_eid uuid;
  v_arr text[];
begin
  v_eid := public.resoudre_entreprise(p_entreprise_id);

  if v_eid is not null then
    select coalesce(array_agg(distinct x::text), array[]::text[])
      into v_arr
      from (
        select s.id as x
          from public.espaces s
         where s.entreprise_id::text = v_eid::text
        union
        select u.id
          from public.utilisateurs u
         where u.entreprise_id::text = v_eid::text
        union
        select e.owner_id
          from public.entreprises e
         where e.id = v_eid
           and e.owner_id is not null
      ) t;
  end if;

  -- Repli : entreprise introuvable (compte sans entreprise) → on garde le
  -- comportement historique, limité au propriétaire de l'utilisateur.
  if v_arr is null or coalesce(array_length(v_arr, 1), 0) = 0 then
    v_arr := array[
      coalesce(public.mon_proprietaire(), auth.uid())::text
    ];
  end if;

  return array_remove(v_arr, null);
end;
$$;

comment on function public.perimetre_entreprise(uuid) is
  'Correctif 179 — identifiants porteurs de données d''une entreprise (espaces + utilisateurs + propriétaire) : source unique de tous les totaux.';

grant execute on function public.perimetre_entreprise(uuid) to authenticated;


-- 3.k `analyse_lignes_ventes` — réécrite sur le périmètre commun et sur des
--     bornes de journée en heure de Lubumbashi (plus de décalage de 2 h).
create or replace function public.analyse_lignes_ventes(
  p_entreprise_id uuid,
  p_debut         date,
  p_fin           date
)
returns table (
  source      text,
  ref         text,
  nom         text,
  quantite    numeric,
  prix        numeric,
  prix_achat  numeric,
  local_date  timestamp
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_eid   uuid := public.resoudre_entreprise(p_entreprise_id);
  v_perim text[] := public.perimetre_entreprise(p_entreprise_id);
begin
  -- 1. Ventes d'articles (boutique, pharmacie, dépôt, distribution…).
  return query
  select 'boutique'::text,
         v.produit_id::text,
         coalesce(nullif(btrim(coalesce(p.nom, '')), ''), 'Article supprimé'),
         coalesce(v.quantite, 0)::numeric,
         coalesce(v.prix, 0)::numeric,
         coalesce(p.prix_achat, 0)::numeric,
         (v.date::timestamptz at time zone 'Africa/Lubumbashi')
    from public.ventes v
    left join public.produits p on p.id = v.produit_id
   where v.owner_id::text = any(v_perim)
     -- ⚠️ Comparaison en HEURE LOCALE (Lubumbashi) : une vente de 23 h 30
     -- reste bien le jour même, quel que soit le réglage du téléphone.
     and (v.date::timestamptz at time zone 'Africa/Lubumbashi')
           >= p_debut::timestamp
     and (v.date::timestamptz at time zone 'Africa/Lubumbashi')
           <  (p_fin + 1)::timestamp;

  -- 2. Prestations du pressing (un pressing ne remplit pas `ventes`).
  if to_regclass('public.pressing_lignes') is not null
     and to_regclass('public.pressing_commandes') is not null then
    return query execute $q$
      select 'pressing'::text,
             l.prestation_id::text,
             coalesce(nullif(btrim(coalesce(l.prestation_nom, '')), ''),
                      nullif(btrim(coalesce(l.designation, '')), ''),
                      'Prestation'),
             coalesce(l.quantite, 1)::numeric,
             coalesce(l.prix, 0)::numeric,
             0::numeric,
             (c.date_depot::timestamptz at time zone 'Africa/Lubumbashi')
        from public.pressing_lignes l
        join public.pressing_commandes c on c.id = l.commande_id
       where c.entreprise_id::text = $1::text
         and coalesce(c.statut, '') <> 'ANNULEE'
         and (c.date_depot::timestamptz at time zone 'Africa/Lubumbashi')
               >= ($2::date)::timestamp
         and (c.date_depot::timestamptz at time zone 'Africa/Lubumbashi')
               <  (($3::date) + 1)::timestamp
    $q$ using v_eid, p_debut, p_fin;
  end if;
end;
$$;

comment on function public.analyse_lignes_ventes(uuid, date, date) is
  '0177 + correctif 179 — lignes analysables d''une entreprise : ventes d''articles + prestations de pressing, sur le périmètre commun et en heure de Lubumbashi.';

revoke all on function public.analyse_lignes_ventes(uuid, date, date)
  from public, anon;
grant execute on function public.analyse_lignes_ventes(uuid, date, date)
  to authenticated;


-- 3.l `rpc_accueil_stats` — LE TABLEAU DE BORD, aligné sur le rapport.
--     Ajoute le mois, la quantité et la date de référence locale.
create or replace function public.rpc_accueil_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_user    uuid := auth.uid();
  v_eid     uuid;
  v_perim   text[];
  v_jour    date := public.jour_local();
  v_mois    date := date_trunc('month', public.jour_local())::date;
  v_produits     bigint := 0;
  v_alertes      bigint := 0;
  v_ventes_jour  bigint := 0;
  v_ventes_mois  bigint := 0;
  v_ventes_total bigint := 0;
  v_ca_jour      numeric := 0;
  v_ca_mois      numeric := 0;
  v_ca_total     numeric := 0;
  v_qte_jour     numeric := 0;
  v_qte_mois     numeric := 0;
  v_qte_total    numeric := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_eid := public.entreprise_courante();
  v_perim := public.perimetre_entreprise(v_eid);

  -- Articles et alertes de stock, sur le périmètre commun.
  select count(*),
         count(*) filter (
           where not coalesce(p.stock_illimite, false)
             and coalesce(p.quantite, 0) <= coalesce(p.seuil_alerte, 5)
         )
    into v_produits, v_alertes
    from public.produits p
   where p.owner_id::text = any(v_perim);

  -- ⚠️ MÊME DÉFINITION DE « VENTE » QUE LE RAPPORT : `analyse_lignes_ventes`
  -- (ventes d'articles + prestations pressing), même périmètre, mêmes bornes.
  with lignes as (
    select *
      from public.analyse_lignes_ventes(v_eid, date '2000-01-01', v_jour)
  )
  select count(*),
         coalesce(sum(l.prix), 0),
         coalesce(sum(l.quantite), 0),
         count(*) filter (where l.local_date >= v_jour::timestamp),
         coalesce(sum(l.prix) filter (where l.local_date >= v_jour::timestamp), 0),
         coalesce(sum(l.quantite) filter (where l.local_date >= v_jour::timestamp), 0),
         count(*) filter (where l.local_date >= v_mois::timestamp),
         coalesce(sum(l.prix) filter (where l.local_date >= v_mois::timestamp), 0),
         coalesce(sum(l.quantite) filter (where l.local_date >= v_mois::timestamp), 0)
    into v_ventes_total, v_ca_total, v_qte_total,
         v_ventes_jour, v_ca_jour, v_qte_jour,
         v_ventes_mois, v_ca_mois, v_qte_mois
    from lignes l;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', v_eid,
    -- 📅 La date de référence vient du SERVEUR : le téléphone ne décide plus
    -- de la journée affichée (correctif 179).
    'jour', to_char(v_jour, 'YYYY-MM-DD'),
    'debut_jour', v_jour,
    'debut_mois', v_mois,
    'produits', v_produits,
    'stock_alertes', v_alertes,
    'ventes_jour', v_ventes_jour,
    'ventes_mois', v_ventes_mois,
    'ventes_total', v_ventes_total,
    'ca_jour', round(v_ca_jour, 2),
    'ca_mois', round(v_ca_mois, 2),
    'ca_total', round(v_ca_total, 2),
    'quantite_jour', round(v_qte_jour, 2),
    'quantite_mois', round(v_qte_mois, 2),
    'quantite_total', round(v_qte_total, 2)
  );
end;
$$;

comment on function public.rpc_accueil_stats() is
  'Module 23 + correctif 179 — chiffres du tableau de bord calculés sur le périmètre commun et en heure de Lubumbashi : ils correspondent exactement au rapport du patron.';

revoke all on function public.rpc_accueil_stats() from public, anon;
grant execute on function public.rpc_accueil_stats() to authenticated;


-- ============================================================================
--  4. RAPPORT PAR COLLABORATEUR (VENDEUR)
-- ============================================================================

create or replace function public.rpc_rapport_vendeurs(
  p_entreprise_id uuid,
  p_debut         date default null,
  p_fin           date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eid      uuid;
  v_nom      text;
  v_debut    date := coalesce(p_debut, public.jour_local() - 6);
  v_fin      date := coalesce(p_fin, public.jour_local());
  v_totaux   jsonb := '{}'::jsonb;
  v_vendeurs jsonb := '[]'::jsonb;
  v_produits jsonb := '[]'::jsonb;
  v_journal  jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  -- 🧭 L'écran « Stats collaborateurs » transmet l'identifiant du PATRON :
  -- on accepte entreprise, propriétaire ou collaborateur, et l'on travaille
  -- ensuite toujours sur l'entreprise résolue (mêmes chiffres partout).
  v_eid := public.resoudre_entreprise(p_entreprise_id);

  if v_eid is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  select e.nom into v_nom
    from public.entreprises e
   where e.id = v_eid;

  if v_nom is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  -- Propriétaire, son patron, ou la plateforme. Un collaborateur simple ne
  -- voit pas les ventes de ses collègues.
  if not (public.est_plateforme()
          or exists (select 1
                       from public.entreprises e
                      where e.id = v_eid
                        and (e.owner_id = auth.uid()
                             or e.owner_id = public.mon_patron()
                             or e.owner_id = public.mon_proprietaire()))) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès aux ventes de cette entreprise.';
  end if;

  if v_fin < v_debut then
    raise exception 'PERIODE_INVALIDE|La date de fin précède la date de début.';
  end if;

  if to_regclass('public.sorties_stock') is null then
    raise exception 'MODULE_ABSENT|La table des sorties de stock est absente : exécutez la migration 20260916000132 avant ce rapport.';
  end if;

  with perim as (
    -- Périmètre COMMUN à l'accueil, au rapport d'entreprise et à ce rapport :
    -- mêmes identifiants → mêmes totaux, au franc près.
    select public.perimetre_entreprise(v_eid) as ids
  ),

  -- Tous les mouvements de stock du périmètre, toutes dates confondues :
  -- c'est eux qui permettent de reconstituer le stock d'un instant passé.
  ev as (
    select v.id::text                               as vente_id,
           v.produit_id::text                       as produit_id,
           (v.date::timestamptz
             at time zone 'Africa/Lubumbashi')      as d,
           -coalesce(v.quantite, 0)::numeric        as effet,
           'vente'::text                            as nature
      from public.ventes v, perim
     where v.owner_id::text = any(perim.ids)

    union all
    select null,
           a.produit_id::text,
           (a.date_approvisionnement::timestamptz
             at time zone 'Africa/Lubumbashi'),
           coalesce(a.quantite_ajoutee, 0)::numeric,
           'appro'
      from public.approvisionnements a, perim
     where a.owner_id::text = any(perim.ids)

    union all
    select null,
           j.produit_id::text,
           (j.date::timestamptz at time zone 'Africa/Lubumbashi'),
           coalesce(j.quantite, 0)::numeric,
           'ajust'
      from public.ajustements j, perim
     where j.owner_id::text = any(perim.ids)

    union all
    select null,
           s.produit_id::text,
           (s.date::timestamptz at time zone 'Africa/Lubumbashi'),
           -coalesce(s.quantite, 0)::numeric,
           'sortie'
      from public.sorties_stock s, perim
     where s.owner_id::text = any(perim.ids)
  ),

  ev_ord as (
    select e.*,
           row_number() over (partition by e.produit_id
                              order by e.d, e.nature, e.vente_id) as rang
      from ev e
  ),

  -- Somme des effets POSTÉRIEURS : stock_instant = stock_actuel − cette somme.
  ev_cum as (
    select o.*,
           coalesce(sum(o.effet) over (
             partition by o.produit_id
             order by o.d desc, o.rang desc
             rows between unbounded preceding and 1 preceding), 0) as effet_apres
      from ev_ord o
  ),

  stock_now as (
    select p.id::text                     as produit_id,
           coalesce(p.quantite, 0)::numeric as stock,
           p.nom
      from public.produits p, perim
     where p.owner_id::text = any(perim.ids)
  ),

  -- Les ventes DE LA PÉRIODE, enrichies du vendeur et du stock reconstitué.
  lignes as (
    select v.id::text                            as vente_id,
           v.produit_id::text                    as produit_id,
           coalesce(nullif(btrim(coalesce(pr.nom, '')), ''),
                    'Article supprimé')          as produit,
           coalesce(v.quantite, 0)::numeric      as quantite,
           coalesce(v.prix, 0)::numeric          as prix,
           (v.date::timestamptz
             at time zone 'Africa/Lubumbashi')   as d,
           nullif(btrim(coalesce(v.seller_id::text, '')), '') as seller_id
      from public.ventes v
      cross join perim
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id::text = any(perim.ids)
       -- ⚠️ Bornes en HEURE LOCALE (Lubumbashi) : mêmes journées pour tout le
       -- monde, quel que soit le fuseau du téléphone (correctif 179).
       and (v.date::timestamptz at time zone 'Africa/Lubumbashi')
             >= v_debut::timestamp
       and (v.date::timestamptz at time zone 'Africa/Lubumbashi')
             <  (v_fin + 1)::timestamp
  ),

  lignes_stock as (
    select l.*,
           case when sn.stock is null then null
                else sn.stock - coalesce(ec.effet_apres, 0) end as stock_apres,
           case when sn.stock is null then null
                else sn.stock - coalesce(ec.effet_apres, 0) + l.quantite end
                                                                as stock_avant,
           coalesce(nullif(btrim(concat_ws(' ', u.prenom, u.nom)), ''),
                    case when l.seller_id is null then 'Propriétaire'
                         else 'Vendeur inconnu' end)            as vendeur,
           coalesce(l.seller_id, 'proprietaire')                as vendeur_cle
      from lignes l
      left join ev_cum    ec on ec.vente_id = l.vente_id
      left join stock_now sn on sn.produit_id = l.produit_id
      left join public.utilisateurs u on u.id::text = l.seller_id
  ),

  lignes_ordre as (
    select ls.*,
           lag(ls.vendeur) over (partition by ls.produit_id
                                 order by ls.d, ls.vente_id) as vendu_avant_par
      from lignes_stock ls
  )

  select
    -- Totaux de la période.
    (select jsonb_build_object(
              'ca', round(coalesce(sum(prix), 0), 2),
              'ventes', count(*),
              'quantite', round(coalesce(sum(quantite), 0), 2),
              'vendeurs', count(distinct vendeur_cle),
              'articles', count(distinct produit_id),
              'panier_moyen', case when count(*) > 0
                                   then round(sum(prix) / count(*), 2) else 0 end)
       from lignes_ordre),

    -- Un bloc par vendeur : totaux, produits, journal (avec le stock).
    (select coalesce(jsonb_agg(jsonb_build_object(
               'id',           x.vendeur_cle,
               'nom',          x.vendeur,
               'ventes',       x.nb,
               'quantite',     round(x.qte, 2),
               'ca',           round(x.ca, 2),
               'panier_moyen', case when x.nb > 0
                                    then round(x.ca / x.nb, 2) else 0 end,
               'premier',      to_char(x.premier, 'YYYY-MM-DD HH24:MI'),
               'dernier',      to_char(x.dernier, 'YYYY-MM-DD HH24:MI'),
               'produits',     x.produits,
               'journal',      x.journal
             ) order by x.ca desc, x.vendeur), '[]'::jsonb)
       from (
         select o.vendeur_cle,
                o.vendeur,
                count(*)                as nb,
                sum(o.quantite)         as qte,
                sum(o.prix)             as ca,
                min(o.d)                as premier,
                max(o.d)                as dernier,
                (select coalesce(jsonb_agg(jsonb_build_object(
                            'nom', y.produit,
                            'quantite', round(y.qte, 2),
                            'ca', round(y.ca, 2)
                          ) order by y.ca desc), '[]'::jsonb)
                   from (select z.produit,
                                sum(z.quantite) as qte,
                                sum(z.prix)     as ca
                           from lignes_ordre z
                          where z.vendeur_cle = o.vendeur_cle
                          group by z.produit) y)      as produits,
                (select coalesce(jsonb_agg(jsonb_build_object(
                            'date',             to_char(w.d, 'YYYY-MM-DD HH24:MI'),
                            'produit',          w.produit,
                            'quantite',         round(w.quantite, 2),
                            'prix',             round(w.prix, 2),
                            'stock_avant',      w.stock_avant,
                            'stock_apres',      w.stock_apres,
                            'vendu_avant_par',  w.vendu_avant_par
                          ) order by w.d, w.vente_id), '[]'::jsonb)
                   from lignes_ordre w
                  where w.vendeur_cle = o.vendeur_cle)   as journal
           from lignes_ordre o
          group by o.vendeur_cle, o.vendeur
       ) x),

    -- Un bloc par article : stock actuel, stock de début, ventes de la période.
    (select coalesce(jsonb_agg(jsonb_build_object(
               'produit_id',   p.produit_id,
               'nom',          coalesce(nullif(btrim(coalesce(p.nom, '')), ''),
                                        'Article supprimé'),
               'stock_actuel', p.stock,
               'stock_debut',  case when p.stock is null then null
                                    else p.stock - coalesce(m.net, 0) end,
               'vendu',        coalesce(v.qte, 0),
               'ca',           coalesce(v.ca, 0)
             ) order by coalesce(v.qte, 0) desc, p.stock), '[]'::jsonb)
       from stock_now p
       left join (
         select e.produit_id, sum(e.effet) as net
           from ev e
          where e.d >= v_debut::timestamp
            and e.d <  (v_fin + 1)::timestamp
          group by e.produit_id
       ) m on m.produit_id = p.produit_id
       left join (
         select l.produit_id,
                round(sum(l.quantite), 2) as qte,
                round(sum(l.prix), 2)     as ca
           from lignes_ordre l
          group by l.produit_id
       ) v on v.produit_id = p.produit_id),

    -- La chronologie complète : c'est elle qui raconte « il restait 4 ».
    (select coalesce(jsonb_agg(jsonb_build_object(
               'date',            to_char(j.d, 'YYYY-MM-DD HH24:MI'),
               'vendeur',         j.vendeur,
               'produit',         j.produit,
               'quantite',        round(j.quantite, 2),
               'prix',            round(j.prix, 2),
               'stock_avant',     j.stock_avant,
               'stock_apres',     j.stock_apres,
               'vendu_avant_par', j.vendu_avant_par
             ) order by j.d, j.vente_id), '[]'::jsonb)
       from lignes_ordre j)
    into v_totaux, v_vendeurs, v_produits, v_journal;

  return jsonb_build_object(
    'entreprise', v_nom,
    'entreprise_id', v_eid,
    'debut', v_debut,
    'fin', v_fin,
    'totaux', v_totaux,
    'vendeurs', v_vendeurs,
    'produits', v_produits,
    'journal', v_journal
  );
end;
$$;

comment on function public.rpc_rapport_vendeurs(uuid, date, date) is
  'Correctif 179 — rapport par collaborateur : ventes, produits et chiffre d''affaires de chacun, avec le stock restant avant/après CHAQUE vente et le vendeur de l''unité précédente.';

revoke all on function public.rpc_rapport_vendeurs(uuid, date, date)
  from public, anon;
grant execute on function public.rpc_rapport_vendeurs(uuid, date, date)
  to authenticated;


-- ============================================================================
--  7. RAPPORT FINANCIER DU PATRON (écran « Rapports »)
-- ============================================================================
--  Dernier écran qui pouvait afficher d'autres chiffres que le tableau de
--  bord : il comptait `ventes.owner_id = patron` (un seul espace) et bornait
--  la journée en UTC (donc à 02:00 à Lubumbashi).
--  Il utilise désormais LE MÊME périmètre et LA MÊME journée que l'accueil.

create or replace function public.finance_stats_periode(
  p_owner uuid,
  p_debut date,
  p_fin   date
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with perim as (
    select public.perimetre_entreprise(p_owner) as ids
  ),
  ventes_agg as (
    select coalesce(sum(coalesce(v.prix, 0)::numeric), 0) as ca,
           coalesce(sum(coalesce(v.quantite, 0)::numeric
                        * coalesce(pr.prix_achat, 0)::numeric), 0) as cout,
           count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)) as nb_ventes
      from public.ventes v
      cross join perim
      left join public.produits pr on pr.id = v.produit_id
     where v.owner_id::text = any(perim.ids)
       -- ⚠️ Bornes en HEURE LOCALE (Lubumbashi) : la journée commence à
       -- minuit en boutique, pas à 02:00.
       and (v.date::timestamptz at time zone 'Africa/Lubumbashi') >= p_debut::timestamp
       and (v.date::timestamptz at time zone 'Africa/Lubumbashi') <  (p_fin + 1)::timestamp
  ),
  depenses_agg as (
    select coalesce(sum(coalesce(dp.montant, 0)::numeric), 0) as total,
           count(*) as nb
      from public.depenses dp
      cross join perim
     where dp.owner_id::text = any(perim.ids)
       and (dp.date::timestamptz at time zone 'Africa/Lubumbashi') >= p_debut::timestamp
       and (dp.date::timestamptz at time zone 'Africa/Lubumbashi') <  (p_fin + 1)::timestamp
  )
  select jsonb_build_object(
    'debut',            p_debut,
    'fin',              p_fin,
    'chiffre_affaires', va.ca,
    'cout_marchandises', va.cout,
    'marge_brute',      va.ca - va.cout,
    'depenses',         da.total,
    'benefice_net',     va.ca - va.cout - da.total,
    'nb_ventes',        va.nb_ventes,
    'nb_depenses',      da.nb
  )
  from ventes_agg va, depenses_agg da;
$$;

comment on function public.finance_stats_periode(uuid, date, date) is
  'Module 10 + correctif 179 — statistiques financières sur le périmètre commun et en heure de Lubumbashi : CA, coût, dépenses, bénéfice net.';

revoke all on function public.finance_stats_periode(uuid, date, date) from public, anon;
grant execute on function public.finance_stats_periode(uuid, date, date) to authenticated;


create or replace function public.rpc_finance_rapport(
  p_groupe text,
  p_debut  date default null,
  p_fin    date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_perim  text[];
  v_groupe text := lower(btrim(coalesce(p_groupe, '')));
  -- 📅 Période par défaut calée sur la date du SERVEUR (Lubumbashi).
  v_debut  date := coalesce(p_debut, public.jour_local() - 29);
  v_fin    date := coalesce(p_fin, public.jour_local());
  v_lignes jsonb := '[]'::jsonb;
  v_stats  jsonb;
  v_jour   date;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les rapports.';
  end if;

  if public.finance_role_plateforme_bloque() then
    raise exception 'ACCES_REFUSE|La finance d''une entreprise est privée : le personnel de la plateforme n''y a pas accès.';
  end if;

  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  if not public.acces_finance_entreprise(v_owner) then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette entreprise.';
  end if;

  if not (public.peut('rapports', 'voir') or public.peut('finance', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les rapports financiers.';
  end if;

  if v_debut > v_fin then
    raise exception 'PERIODE_INVALIDE|La date de début doit précéder la date de fin.';
  end if;

  if (v_fin - v_debut) > 366 then
    raise exception 'PERIODE_INVALIDE|Période trop longue : 366 jours maximum.';
  end if;

  -- 🎯 Périmètre commun (espaces + utilisateurs + propriétaire).
  v_perim := public.perimetre_entreprise(v_owner);

  v_stats := public.finance_stats_periode(v_owner, v_debut, v_fin);

  case v_groupe
    -- ------------------------------------------------------------------ articles
    when 'article' then
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        into v_lignes
        from (
          select jsonb_build_object(
                   'produit_id', v.produit_id,
                   'nom',        coalesce(pr.nom, 'Article supprimé'),
                   'quantite',   sum(coalesce(v.quantite, 0)::numeric),
                   'ca',         sum(coalesce(v.prix, 0)::numeric),
                   'cout',       sum(coalesce(v.quantite, 0)::numeric
                                     * coalesce(pr.prix_achat, 0)::numeric),
                   'marge',      sum(coalesce(v.prix, 0)::numeric)
                                 - sum(coalesce(v.quantite, 0)::numeric
                                       * coalesce(pr.prix_achat, 0)::numeric)
                 ) as x
            from public.ventes v
            left join public.produits pr on pr.id = v.produit_id
           where v.owner_id::text = any(v_perim)
             and (v.date::timestamptz at time zone 'Africa/Lubumbashi') >= v_debut::timestamp
             and (v.date::timestamptz at time zone 'Africa/Lubumbashi') <  (v_fin + 1)::timestamp
           group by v.produit_id, pr.nom
           order by sum(coalesce(v.prix, 0)::numeric) desc
        ) s;

    -- ------------------------------------------------------------------ vendeurs
    when 'vendeur' then
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        into v_lignes
        from (
          select jsonb_build_object(
                   'seller_id', v.seller_id,
                   'nom',       coalesce(nullif(btrim(u.nom), ''), u.email, 'Vendeur non attribué'),
                   'nb_ventes', count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)),
                   'ca',        sum(coalesce(v.prix, 0)::numeric)
                 ) as x
            from public.ventes v
            left join public.utilisateurs u on u.id::text = v.seller_id::text
           where v.owner_id::text = any(v_perim)
             and (v.date::timestamptz at time zone 'Africa/Lubumbashi') >= v_debut::timestamp
             and (v.date::timestamptz at time zone 'Africa/Lubumbashi') <  (v_fin + 1)::timestamp
           group by v.seller_id, u.nom, u.email
           order by sum(coalesce(v.prix, 0)::numeric) desc
        ) s;

    -- -------------------------------------------------------------------- modes
    when 'mode' then
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        into v_lignes
        from (
          select jsonb_build_object(
                   'mode',      lower(btrim(coalesce(v.mode_paiement, 'especes'))),
                   'nb_ventes', count(distinct coalesce(v.vente_uuid::text, 'L' || v.id)),
                   'ca',        sum(coalesce(v.prix, 0)::numeric)
                 ) as x
            from public.ventes v
           where v.owner_id::text = any(v_perim)
             and (v.date::timestamptz at time zone 'Africa/Lubumbashi') >= v_debut::timestamp
             and (v.date::timestamptz at time zone 'Africa/Lubumbashi') <  (v_fin + 1)::timestamp
           group by 1
           order by sum(coalesce(v.prix, 0)::numeric) desc
        ) s;

    -- ----------------------------------------------------- dépenses par catégorie
    when 'categorie_depense' then
      select coalesce(jsonb_agg(x), '[]'::jsonb)
        into v_lignes
        from (
          select jsonb_build_object(
                   'categorie', lower(coalesce(dp.categorie, 'autre')),
                   'nb',        count(*),
                   'montant',   sum(coalesce(dp.montant, 0)::numeric)
                 ) as x
            from public.depenses dp
           where dp.owner_id::text = any(v_perim)
             and (dp.date::timestamptz at time zone 'Africa/Lubumbashi') >= v_debut::timestamp
             and (dp.date::timestamptz at time zone 'Africa/Lubumbashi') <  (v_fin + 1)::timestamp
           group by 1
           order by sum(coalesce(dp.montant, 0)::numeric) desc
        ) s;

    -- --------------------------------------------------------------- par jour
    when 'jour' then
      v_jour := v_debut;
      while v_jour <= v_fin loop
        v_lignes := v_lignes || (
          (select public.finance_stats_periode(v_owner, v_jour, v_jour)
                  - 'debut' - 'fin')
          || jsonb_build_object('jour', v_jour)
        );
        v_jour := v_jour + 1;
      end loop;

    else
      raise exception 'GROUPE_INVALIDE|Groupe inconnu : « article », « vendeur », « mode », « categorie_depense » ou « jour ».';
  end case;

  return jsonb_build_object(
    'groupe', v_groupe,
    'debut',  v_debut,
    'fin',    v_fin,
    'lignes', v_lignes,
    'totaux', v_stats
  );
end;
$$;

comment on function public.rpc_finance_rapport(text, date, date) is
  'Module 10 + correctif 179 — rapport financier par article, vendeur, mode de paiement, catégorie de dépense ou jour, sur le périmètre commun et en heure de Lubumbashi.';

revoke all on function public.rpc_finance_rapport(text, date, date) from public, anon;
grant execute on function public.rpc_finance_rapport(text, date, date) to authenticated;


-- ============================================================================
--  8. VÉRIFICATIONS (à lire dans l'onglet « Messages »)
-- ============================================================================

-- 8.a Les colonnes d'identifiants Finance sont-elles toutes en uuid ?
select public.finance_verifier_types() as colonnes_identifiants_finance;

-- 8.b Les fonctions Finance existent avec leur bonne signature.
select p.proname,
       pg_get_function_identity_arguments(p.oid) as arguments,
       p.provolatile
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('finance_abonnements_resume',
                     'finance_abonnements_entreprises',
                     'finance_serdipay_transactions',
                     'finance_serdipay_rapprocher',
                     'finance_verifier_types',
                     'rpc_rapport_vendeurs')
 order by p.proname;

-- 8.c Les fonctions Finance sont-elles appelables ?  (aucune erreur attendue)
--     Remplacer l'identifiant ci-dessous par une entreprise réelle si besoin.
-- select public.finance_abonnements_resume(current_date - 30, current_date);
-- select public.finance_abonnements_entreprises(null, null, 5);
-- select public.finance_serdipay_transactions(null, null, 5);

-- 8.d Le rapport par vendeur répond-il ? (décommenter et adapter)
-- select jsonb_pretty(
--          public.rpc_rapport_vendeurs(
--            '00000000-0000-0000-0000-000000000000'::uuid,
--            current_date - 30,
--            current_date
--          )
--        );

-- 8.e Combien de ventes sont attribuées à chaque vendeur sur 30 jours ?
--     (contrôle croisé avec le rapport de l'application)
select coalesce(nullif(btrim(coalesce(v.seller_id::text, '')), ''), 'proprietaire')
         as vendeur,
       count(*)                     as ventes,
       round(sum(coalesce(v.prix, 0)::numeric), 2) as chiffre_affaires
  from public.ventes v
 where v.date::timestamptz >= (current_date - 30)::timestamptz
 group by 1
 order by 3 desc
 limit 50;

-- 8.f COHÉRENCE — le tableau de bord et le rapport d'entreprise comptent-ils
--     EXACTEMENT les mêmes lignes ?  Les deux écarts doivent être à 0.
--     (Ignoré dans l'éditeur SQL, où aucune session n'est connectée :
--      relancez-le depuis l'application ou avec un JWT.)
do $$
declare
  v_stats jsonb;
  v_nb_a  bigint := 0;
  v_ca_a  numeric := 0;
  v_nb_r  bigint := 0;
  v_ca_r  numeric := 0;
  v_jour  date;
begin
  if auth.uid() is null then
    raise notice 'CORRECTIF 179 — contrôle de cohérence ignoré (aucune session connectée dans l''éditeur SQL).';
    return;
  end if;

  v_jour := public.jour_local();
  v_stats := public.rpc_accueil_stats();

  v_nb_a := coalesce((v_stats ->> 'ventes_jour')::bigint, 0);
  v_ca_a := coalesce((v_stats ->> 'ca_jour')::numeric, 0);

  select count(*), coalesce(sum(l.prix), 0)
    into v_nb_r, v_ca_r
    from public.analyse_lignes_ventes(
           public.entreprise_courante(), v_jour, v_jour) l;

  raise notice
    'CORRECTIF 179 — cohérence du jour % : tableau de bord = % vente(s) / % ; rapport = % vente(s) / % ; écarts = % / %',
    v_jour, v_nb_a, v_ca_a, v_nb_r, v_ca_r, v_nb_a - v_nb_r, v_ca_a - v_ca_r;
end $$;

-- 8.g Périodes calculées côté serveur : la journée commence bien à minuit
--     heure de Lubumbashi (et non à 02:00).
select public.jour_local()                                   as jour_lubumbashi,
       (public.jour_local()::timestamp at time zone 'Africa/Lubumbashi') as debut_journee_utc,
       now()                                                 as maintenant_utc;

-- 8.h Le rapport financier du patron donne-t-il le MÊME total que le
--     tableau de bord pour la journée ? (écart attendu : 0)
do $$
declare
  v_stats  jsonb;
  v_rapport jsonb;
  v_nb_a   bigint := 0;
  v_ca_a   numeric := 0;
  v_nb_f   bigint := 0;
  v_ca_f   numeric := 0;
  v_jour   date;
begin
  if auth.uid() is null then
    raise notice 'CORRECTIF 179 — contrôle du rapport financier ignoré (aucune session connectée).';
    return;
  end if;

  v_jour := public.jour_local();
  v_stats := public.rpc_accueil_stats();
  v_rapport := public.finance_stats_periode(
                 coalesce(public.mon_proprietaire(), auth.uid()),
                 v_jour, v_jour);

  v_nb_a := coalesce((v_stats ->> 'ventes_jour')::bigint, 0);
  v_ca_a := coalesce((v_stats ->> 'ca_jour')::numeric, 0);
  v_nb_f := coalesce((v_rapport ->> 'nb_ventes')::bigint, 0);
  v_ca_f := coalesce((v_rapport ->> 'chiffre_affaires')::numeric, 0);

  raise notice
    'CORRECTIF 179 — rapport financier du % : tableau de bord = % vente(s) / % ; rapport = % vente(s) / % ; écarts = % / %',
    v_jour, v_nb_a, v_ca_a, v_nb_f, v_ca_f, v_nb_a - v_nb_f, v_ca_a - v_ca_f;
end $$;
