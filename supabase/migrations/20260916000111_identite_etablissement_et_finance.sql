-- ============================================================================
--  biashara_yangu — MODULE 27 : IDENTITÉ DE L'ÉTABLISSEMENT & VISION FINANCIÈRE
--  ---------------------------------------------------------------------------
--  CE QUE LE COMMERÇANT DEMANDE (07/11/2026)
--    « La facture doit porter le nom, l'adresse, le téléphone, le logo de MON
--      établissement, et si j'en ai, mon numéro RCCM et mon identifiant
--      national — sans jamais inventer ce qui manque. »
--    « La Finance doit voir les revenus des abonnements, les paiements
--      Mobile Money et ce qui a réellement été encaissé. »
--
--  CE QUE CE SCRIPT AJOUTE (rien n'est supprimé)
--    1. `espaces.rccm`, `espaces.id_national`, `espaces.email_public` :
--       les mentions légales de l'établissement (FACULTATIVES) ;
--    2. `etablissement_fiche()` — tout ce qu'une facture doit afficher, en un
--       appel, avec `null` (jamais une valeur inventée) quand l'information
--       manque ;
--    3. `etablissement_identite_enregistrer(...)` — le propriétaire renseigne
--       son identité depuis l'application ;
--    4. `finance_abonnements_resume(debut, fin)` — facturé / encaissé / dû,
--       par période, avec la part des suppléments collaborateurs ;
--    5. `finance_serdipay_transactions(...)` — traçabilité Mobile Money :
--       qui a payé, quelle référence, quel statut (aucune donnée inventée).
--
--  ⚠️ IDEMPOTENT — réexécutable sans risque.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'espaces'
  ) then
    raise exception
      'Table public.espaces absente : exécutez d''abord le module 19 (marketplace).';
  end if;
end $$;


-- ============================================================================
--  1. MENTIONS LÉGALES DE L'ÉTABLISSEMENT
-- ============================================================================
--  Toutes FACULTATIVES : une facture sans RCCM reste parfaitement valable,
--  elle n'affiche simplement pas la ligne.

alter table public.espaces add column if not exists rccm         text;
alter table public.espaces add column if not exists id_national  text;
alter table public.espaces add column if not exists email_public text;

comment on column public.espaces.rccm is
  'Module 27 — numéro RCCM de l''établissement (facultatif, affiché sur la facture s''il existe).';
comment on column public.espaces.id_national is
  'Module 27 — identifiant national / ID fiscal de l''établissement (facultatif).';
comment on column public.espaces.email_public is
  'Module 27 — e-mail affiché sur les documents commerciaux (facultatif).';


-- ============================================================================
--  2. LA FICHE « ÉTABLISSEMENT » POUR LES FACTURES
-- ============================================================================
--  Renvoie TOUT ce dont une facture a besoin, en une fois :
--    nom, adresse complète, ville, quartier, téléphone, e-mail, logo,
--    RCCM, identifiant national.
--
--  ⚠️ Les champs absents valent `null`. L'application n'écrit JAMAIS
--     « RCCM : — » ni une adresse inventée : elle masque la ligne.

create or replace function public.etablissement_fiche(
  p_owner uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_espace public.espaces%rowtype;
  v_user_row public.utilisateurs%rowtype;
  v_adresse text;
begin
  v_owner := coalesce(p_owner, public.mon_proprietaire(), v_user);
  if v_owner is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter votre établissement.';
  end if;

  -- Portée : son entreprise, ou la plateforme.
  if v_owner <> v_user
     and v_owner is distinct from public.mon_proprietaire()
     and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cet établissement.';
  end if;

  select * into v_user_row from public.utilisateurs where id = v_owner;

  -- L'espace actif du propriétaire, sinon le premier de son compte.
  select * into v_espace
    from public.espaces
   where owner_id = v_owner
   order by (id = (select espace_actif_id from public.utilisateurs where id = v_owner)) desc,
            created_at asc nulls last
   limit 1;

  -- Adresse reconstituée : numéro, avenue, quartier, repère (sans doublon,
  -- sans virgule orpheline). `null` si rien n'est renseigné.
  if v_espace.id is not null then
    v_adresse := nullif(
      btrim(
        concat_ws(', ',
          nullif(btrim(coalesce(v_espace.numero, '')), ''),
          nullif(btrim(coalesce(v_espace.avenue, '')), ''),
          nullif(btrim(coalesce(v_espace.quartier, '')), ''),
          nullif(btrim(coalesce(v_espace.adresse, '')), ''),
          nullif(btrim(coalesce(v_espace.point_repere, '')), '')
        )
      ),
      ''
    );
  end if;

  return jsonb_build_object(
    'owner_id',   v_owner,
    'espace_id',  v_espace.id,
    'nom',        coalesce(
                    nullif(btrim(coalesce(v_espace.nom, '')), ''),
                    nullif(btrim(concat_ws(' ', v_user_row.prenom, v_user_row.nom)), '')
                  ),
    'adresse',    v_adresse,
    'quartier',   nullif(btrim(coalesce(v_espace.quartier, '')), ''),
    'avenue',     nullif(btrim(coalesce(v_espace.avenue, '')), ''),
    'numero',     nullif(btrim(coalesce(v_espace.numero, '')), ''),
    'repere',     nullif(btrim(coalesce(v_espace.point_repere, '')), ''),
    'ville',      (select v.nom from public.villes v where v.id = v_espace.ville_id),
    'telephone',  coalesce(
                    nullif(btrim(coalesce(v_espace.telephone, '')), ''),
                    nullif(btrim(coalesce(v_user_row.telephone, '')), '')
                  ),
    'whatsapp',   nullif(btrim(coalesce(v_espace.whatsapp, '')), ''),
    'email',      coalesce(
                    nullif(btrim(coalesce(v_espace.email_public, '')), ''),
                    nullif(btrim(coalesce(v_user_row.email, '')), '')
                  ),
    'logo_url',   nullif(btrim(coalesce(v_espace.logo_url, '')), ''),
    'rccm',       nullif(btrim(coalesce(v_espace.rccm, '')), ''),
    'id_national', nullif(btrim(coalesce(v_espace.id_national, '')), ''),
    'devise',     coalesce(nullif(btrim(coalesce(
                    (select e.devise from public.entreprises e where e.id = v_owner), '')), ''), 'CDF')
  );
end;
$$;

comment on function public.etablissement_fiche(uuid) is
  'Module 27 — identité de l''établissement pour les documents commerciaux (RCCM et ID national facultatifs, null si absents).';

grant execute on function public.etablissement_fiche(uuid) to authenticated;


-- ============================================================================
--  3. ENREGISTREMENT DE L'IDENTITÉ (propriétaire)
-- ============================================================================

create or replace function public.etablissement_identite_enregistrer(
  p_nom         text default null,
  p_adresse     text default null,
  p_quartier    text default null,
  p_avenue      text default null,
  p_numero      text default null,
  p_repere      text default null,
  p_telephone   text default null,
  p_email       text default null,
  p_rccm        text default null,
  p_id_national text default null,
  p_logo_url    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_espace uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour modifier votre établissement.';
  end if;

  v_owner := coalesce(public.mon_proprietaire(), v_user);
  if v_owner <> v_user and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul le propriétaire règle l''identité de l''établissement.';
  end if;

  select id into v_espace
    from public.espaces
   where owner_id = v_owner
   order by (id = (select espace_actif_id from public.utilisateurs where id = v_owner)) desc,
            created_at asc nulls last
   limit 1;

  if v_espace is null then
    raise exception 'ETABLISSEMENT_ABSENT|Aucun espace n''est rattaché à ce compte.';
  end if;

  update public.espaces
     set nom          = coalesce(nullif(btrim(coalesce(p_nom, '')), ''), nom),
         adresse      = coalesce(nullif(btrim(coalesce(p_adresse, '')), ''), adresse),
         quartier     = coalesce(nullif(btrim(coalesce(p_quartier, '')), ''), quartier),
         avenue       = coalesce(nullif(btrim(coalesce(p_avenue, '')), ''), avenue),
         numero       = coalesce(nullif(btrim(coalesce(p_numero, '')), ''), numero),
         point_repere = coalesce(nullif(btrim(coalesce(p_repere, '')), ''), point_repere),
         telephone    = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''), telephone),
         email_public = coalesce(nullif(btrim(coalesce(p_email, '')), ''), email_public),
         rccm         = coalesce(nullif(btrim(coalesce(p_rccm, '')), ''), rccm),
         id_national  = coalesce(nullif(btrim(coalesce(p_id_national, '')), ''), id_national),
         logo_url     = coalesce(nullif(btrim(coalesce(p_logo_url, '')), ''), logo_url),
         updated_at   = now()
   where id = v_espace;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_owner, 'IDENTITE_ETABLISSEMENT', v_user,
    jsonb_build_object(
      'espace_id', v_espace,
      'rccm_renseigne', nullif(btrim(coalesce(p_rccm, '')), '') is not null,
      'id_national_renseigne', nullif(btrim(coalesce(p_id_national, '')), '') is not null
    ),
    now()
  );

  return public.etablissement_fiche(v_owner);
end;
$$;

comment on function public.etablissement_identite_enregistrer(
  text, text, text, text, text, text, text, text, text, text, text
) is
  'Module 27 — le propriétaire renseigne l''identité de son établissement (RCCM et ID national facultatifs).';

grant execute on function public.etablissement_identite_enregistrer(
  text, text, text, text, text, text, text, text, text, text, text
) to authenticated;


-- ============================================================================
--  4. VISION FINANCIÈRE DES ABONNEMENTS (plateforme)
-- ============================================================================
--  Trois chiffres toujours DISTINCTS :
--    • facturé  — ce que les cycles ouverts demandent ;
--    • encaissé — ce qui a réellement été enregistré comme payé ;
--    • dû       — ce qui reste à recouvrer.

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

  -- Réservé à la plateforme (Finance, Super Admin).
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
         coalesce(sum(coalesce(e.montant_total_du, 0)), 0),
         coalesce(sum(coalesce(e.montant_deja_paye, 0)), 0),
         coalesce(sum(greatest(coalesce(e.montant_total_du, 0)
                               - coalesce(e.montant_deja_paye, 0), 0)), 0),
         coalesce(sum(coalesce(e.supplement_collaborateurs, 0)), 0)
    into v_nb_total, v_nb_actifs, v_nb_expires, v_nb_attente, v_nb_partiels,
         v_facture, v_encaisse, v_du, v_supplements
    from public.entreprises e;

  select count(*),
         coalesce(sum(p.montant) filter (where p.mode_paiement = 'especes'), 0),
         coalesce(sum(p.montant) filter (where p.mode_paiement in ('mobile_money', 'mobile', 'serdipay')), 0),
         coalesce(sum(p.montant) filter (where p.mode_paiement = 'carte'), 0),
         coalesce(sum(p.montant) filter (where p.mode_paiement is null
                                            or p.mode_paiement not in ('especes', 'mobile_money', 'mobile', 'serdipay', 'carte')), 0)
    into v_nb_paiements, v_especes, v_mobile, v_carte, v_autres
    from public.paiements_abonnements_laperle p
   where p.created_at >= v_debut and p.created_at < v_fin;

  select coalesce(jsonb_agg(x order by x->>'jour'), '[]'::jsonb)
    into v_par_jour
    from (
      select jsonb_build_object(
               'jour', to_char(p.created_at::date, 'YYYY-MM-DD'),
               'montant', round(sum(p.montant), 2),
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
    -- Période demandée :
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
  'Module 27 — vision Finance : facturé, encaissé, dû, suppléments collaborateurs et répartition par moyen de paiement.';

grant execute on function public.finance_abonnements_resume(date, date) to authenticated;


-- ============================================================================
--  5. TRAÇABILITÉ MOBILE MONEY / SERDIPAY
-- ============================================================================
--  On n'affiche QUE ce que le prestataire a réellement renvoyé. Quand une
--  information manque, le champ vaut `null` : l'écran écrit « non communiqué ».

-- Informations de règlement : remplies SEULEMENT si SerdiPay les communique
-- (aucune n'est déduite ni inventée).
alter table public.paiements_serdipay add column if not exists nom_payeur    text;
alter table public.paiements_serdipay add column if not exists frais         numeric(14, 2);
alter table public.paiements_serdipay add column if not exists montant_net   numeric(14, 2);
alter table public.paiements_serdipay add column if not exists rapproche_le  timestamptz;
alter table public.paiements_serdipay add column if not exists rapproche_par uuid;

comment on column public.paiements_serdipay.nom_payeur is
  'Module 27 — nom du payeur tel que transmis par SerdiPay (NULL si non communiqué).';
comment on column public.paiements_serdipay.frais is
  'Module 27 — frais de transaction annoncés par SerdiPay (NULL si non communiqués).';
comment on column public.paiements_serdipay.montant_net is
  'Module 27 — montant net reçu annoncé par SerdiPay (NULL si non communiqué).';
comment on column public.paiements_serdipay.rapproche_le is
  'Module 27 — date du rapprochement manuel avec le relevé du prestataire.';

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
                                    where e.id = s.entreprise_id),
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
                                     from public.utilisateurs u where u.id = s.utilisateur_id),
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
                            where e.id = s.entreprise_id), '') ilike '%' || v_like || '%')
         and (nullif(btrim(coalesce(p_statut, '')), '') is null
              or s.statut = p_statut)
       order by s.created_at desc
       limit greatest(coalesce(p_limite, 100), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.finance_serdipay_transactions(text, text, integer) is
  'Module 27 — transactions Mobile Money : qui a payé, quelle référence, quel statut. Aucune valeur inventée.';

grant execute on function public.finance_serdipay_transactions(text, text, integer) to authenticated;


-- ============================================================================
--  6. VÉRIFICATIONS
-- ============================================================================

select column_name
  from information_schema.columns
 where table_schema = 'public' and table_name = 'espaces'
   and column_name in ('rccm', 'id_national', 'email_public')
 order by column_name;

select p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('etablissement_fiche',
                     'etablissement_identite_enregistrer',
                     'finance_abonnements_resume',
                     'finance_serdipay_transactions')
 order by p.proname;
