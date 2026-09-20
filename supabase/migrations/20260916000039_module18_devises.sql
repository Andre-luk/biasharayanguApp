-- ============================================================================
--  biashara_yangu — MODULE 18 : DEVISES DE TRAVAIL & TAUX DE CONVERSION
--
--  OBJECTIF
--  ─────────────────────────────────────────────────────────────────────────
--  Chaque entreprise travaille dans SA devise :
--    • CDF — franc congolais (défaut, comportement actuel) ;
--    • USD — dollar américain.
--
--  Le choix s'applique à TOUS les montants de l'entreprise : prix d'achat et
--  de vente des articles, ventes, dépenses, caisse, dettes, rapports,
--  paiements, abonnements (équivalent affiché), assistant IA…
--
--  ⚠️ RÈGLE DE SÉCURITÉ (à comprendre avant d'utiliser l'écran) :
--     la devise est une UNITÉ DE LECTURE/SAISIE. Changer de devise ne
--     convertit PAS les montants déjà enregistrés (15 000 reste 15 000) :
--     l'écran affiche un avertissement explicite et un SIMULATEUR permet de
--     convertir mentalement avant de changer.
--
--  TAUX DE CONVERSION (`1 USD = X CDF`)
--  ─────────────────────────────────────────────────────────────────────────
--    • taux PLATEFORME : `app_settings['devises']`
--      = {"taux_usd_cdf": 2800, "devise_defaut": "CDF"} — réglé par le
--        SUPER_ADMIN (écran admin « Devises & taux ») ;
--    • taux ENTREPRISE (optionnel) : `entreprises.taux_usd_cdf` — le patron
--      peut imposer le sien (ex. 2 850) ; `null` = taux de la plateforme.
--    • `taux_change_effectif(entreprise)` = entreprise → plateforme → 2 800.
--
--  CONTENU
--    1. colonnes `entreprises.devise` (défaut du compte) et
--       `espaces.devise` (devise propre à chaque entreprise du compte)
--       + `entreprises.taux_usd_cdf` ;
--    2. réglage plateforme `app_settings['devises']` ;
--    3. helpers `devise_libelle()`, `devise_symbole()`, `taux_change_effectif()` ;
--    4. `rpc_devise_etat()`        — état + taux + simulateur (client) ;
--    5. `rpc_devise_configurer()`  — PROPRIÉTAIRE (ou Super Admin) ;
--    6. `rpc_devise_plateforme_definir()` — SUPER_ADMIN ;
--    7. `audit_niveau()` — + DEVISE_CONFIG (CRITIQUE) ;
--    8. vérifications.
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans effet de bord (aucune donnée modifiée
--  à part les valeurs par défaut des nouvelles colonnes).
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. COLONNES DE DEVISE SUR `entreprises`
-- ============================================================================
--  `CDF` par défaut : les entreprises existantes gardent EXACTEMENT leur
--  comportement actuel (aucune régression).

alter table public.entreprises
  add column if not exists devise text not null default 'CDF';

do $$
begin
  alter table public.entreprises
    drop constraint if exists chk_entreprises_devise;
  alter table public.entreprises
    add constraint chk_entreprises_devise
    check (devise in ('CDF', 'USD'));
end $$;

comment on column public.entreprises.devise is
  'Module 18 — Devise de travail par défaut du compte (CDF / USD) : héritée par les espaces qui n''ont pas la leur.';

-- Dévise PROPRE À UN ESPACE (module 15) : un patron qui gère une boutique en
-- CDF ET un hôtel en USD peut régler chaque espace séparément. `null` (défaut)
-- = devise du compte (`entreprises.devise`).
alter table public.espaces
  add column if not exists devise text;

do $$
begin
  alter table public.espaces
    drop constraint if exists chk_espaces_devise;
  alter table public.espaces
    add constraint chk_espaces_devise
    check (devise is null or devise in ('CDF', 'USD'));
end $$;

comment on column public.espaces.devise is
  'Module 18 — Devise de travail de CET espace (CDF/USD). NULL = devise du compte.';

-- Taux de conversion propre à l'entreprise (optionnel).
alter table public.entreprises
  add column if not exists taux_usd_cdf numeric;

do $$
begin
  alter table public.entreprises
    drop constraint if exists chk_entreprises_taux_usd_cdf;
  alter table public.entreprises
    add constraint chk_entreprises_taux_usd_cdf
    check (taux_usd_cdf is null or (taux_usd_cdf > 0 and taux_usd_cdf <= 1000000));
end $$;

comment on column public.entreprises.taux_usd_cdf is
  'Module 18 — Taux de change propre à l''entreprise (1 USD = X CDF). NULL = taux de la plateforme.';


-- ============================================================================
--  2. RÉGLAGE PLATEFORME `app_settings['devises']`
-- ============================================================================
--  {"taux_usd_cdf": 2800, "devise_defaut": "CDF"}
--  `on conflict do nothing` : relancer la migration ne REMPLACE jamais un
--  taux déjà réglé par le Super Admin.

insert into public.app_settings (key, value, updated_at)
values (
  'devises',
  jsonb_build_object('taux_usd_cdf', 2800, 'devise_defaut', 'CDF'),
  now()
)
on conflict (key) do nothing;


-- ============================================================================
--  3. HELPERS — LIBELLÉS, SYMBOLES ET TAUX EFFECTIF
-- ============================================================================

create or replace function public.devise_libelle(p_devise text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_devise, 'CDF')))
    when 'USD' then 'Dollar américain'
    when 'CDF' then 'Franc congolais'
    else coalesce(nullif(btrim(p_devise), ''), 'Franc congolais')
  end;
$$;

comment on function public.devise_libelle(text) is
  'Module 18 — Libellé lisible d''une devise (CDF → Franc congolais, USD → Dollar américain).';

create or replace function public.devise_symbole(p_devise text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_devise, 'CDF')))
    when 'USD' then '$'
    else 'CDF'
  end;
$$;

comment on function public.devise_symbole(text) is
  'Module 18 — Unité d''affichage d''une devise (CDF / $). Miroir de Devise.symbole côté Dart.';

-- Taux effectif : entreprise → plateforme → 2 800 (jamais NULL, jamais 0).
create or replace function public.taux_change_effectif(p_entreprise uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_taux_ent  numeric;
  v_taux_plat numeric;
begin
  if p_entreprise is not null then
    select e.taux_usd_cdf into v_taux_ent
      from public.entreprises e
     where e.id = p_entreprise;
  end if;

  begin
    select nullif((s.value ->> 'taux_usd_cdf')::numeric, 0) into v_taux_plat
      from public.app_settings s
     where s.key = 'devises';
  exception when others then
    v_taux_plat := null;
  end;

  return coalesce(nullif(v_taux_ent, 0), v_taux_plat, 2800);
end;
$$;

comment on function public.taux_change_effectif(uuid) is
  'Module 18 — Taux de change « 1 USD = X CDF » applicable : entreprise, sinon plateforme, sinon 2 800.';

revoke all on function public.devise_libelle(text) from public;
revoke all on function public.devise_symbole(text) from public;
revoke all on function public.taux_change_effectif(uuid) from public;
revoke all on function public.taux_change_effectif(uuid) from anon;
grant execute on function public.devise_libelle(text) to authenticated;
grant execute on function public.devise_symbole(text) to authenticated;
grant execute on function public.taux_change_effectif(uuid) to authenticated;


-- ============================================================================
--  4. `rpc_devise_etat()` — ÉTAT COMPLET POUR L'APPLICATION
-- ============================================================================
--  Renvoie la devise de l'entreprise active, le taux effectif, le taux de la
--  plateforme, et la liste des devises proposées (pour les sélecteurs).

create or replace function public.rpc_devise_etat()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user      uuid := auth.uid();
  v_espace    uuid;
  v_ent       uuid;
  v_devise    text;
  v_dev_esp   text;
  v_taux_ent  numeric;
  v_taux_plat numeric;
  v_defaut    text := 'CDF';
  v_role      text := public.mon_role();
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter votre devise.';
  end if;

  -- Espace de travail actif → entreprise du compte.
  v_espace := public.mon_proprietaire();
  v_ent := public.entreprise_de_proprietaire(v_espace);

  if v_ent is not null then
    select e.taux_usd_cdf into v_taux_ent
      from public.entreprises e
     where e.id = v_ent;

    select nullif(upper(btrim(coalesce(e.devise, ''))), '') into v_devise
      from public.entreprises e
     where e.id = v_ent;
  end if;

  -- Devise propre à l'espace actif (prioritaire).
  if v_espace is not null then
    select nullif(upper(btrim(coalesce(s.devise, ''))), '') into v_dev_esp
      from public.espaces s
     where s.id = v_espace;
    v_devise := coalesce(v_dev_esp, v_devise);
  end if;

  begin
    select nullif((s.value ->> 'taux_usd_cdf')::numeric, 0),
           coalesce(nullif(btrim(s.value ->> 'devise_defaut'), ''), 'CDF')
      into v_taux_plat, v_defaut
      from public.app_settings s
     where s.key = 'devises';
  exception when others then
    v_taux_plat := null;
    v_defaut := 'CDF';
  end;

  v_devise := coalesce(nullif(v_devise, ''), v_defaut, 'CDF');

  return jsonb_build_object(
    'ok',              true,
    'entreprise_id',   v_ent,
    'espace_id',       v_espace,
    'devise',          v_devise,
    'devise_libelle',  public.devise_libelle(v_devise),
    'symbole',         public.devise_symbole(v_devise),
    'taux_usd_cdf',    public.taux_change_effectif(v_ent),
    'taux_entreprise', v_taux_ent,
    'taux_plateforme', coalesce(v_taux_plat, 2800),
    'devise_plateforme', coalesce(v_defaut, 'CDF'),
    'peut_modifier',   v_ent is not null
                       and (v_role = 'PROPRIETAIRE' or public.est_plateforme()),
    'devises', jsonb_build_array(
      jsonb_build_object('code', 'CDF', 'libelle', 'Franc congolais', 'symbole', 'CDF'),
      jsonb_build_object('code', 'USD', 'libelle', 'Dollar américain', 'symbole', '$')
    )
  );
end;
$$;

comment on function public.rpc_devise_etat() is
  'Module 18 — Devise de travail de l''entreprise active, taux de change effectif et devises proposées.';

revoke all on function public.rpc_devise_etat() from public;
revoke all on function public.rpc_devise_etat() from anon;
grant execute on function public.rpc_devise_etat() to authenticated;


-- ============================================================================
--  5. `rpc_devise_configurer()` — CHOIX DE LA DEVISE (ENTREPRISE)
-- ============================================================================
--  Réservé au PROPRIÉTAIRE de l'entreprise (ou au Super Admin).
--  `p_taux` :
--    • > 0      → taux propre à l'entreprise (1 USD = p_taux CDF) ;
--    • = 0      → REVENIR au taux de la plateforme (remet la colonne à NULL) ;
--    • null     → ne change pas le taux (seule la devise change).
--  ⚠️ Les montants déjà enregistrés ne sont PAS convertis (voir l'entête).

create or replace function public.rpc_devise_configurer(
  p_devise        text,
  p_taux          numeric default null,
  p_entreprise_id uuid    default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_role   text := public.mon_role();
  v_ent    uuid;
  v_espace uuid;
  v_devise text;
  v_avant  text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour changer votre devise.';
  end if;

  -- Entreprise cible : celle du propriétaire, ou celle indiquée par la
  -- plateforme (Super Admin).
  if public.est_plateforme() and p_entreprise_id is not null then
    v_ent := p_entreprise_id;
  else
    v_espace := public.mon_proprietaire();
    v_ent := public.entreprise_de_proprietaire(v_espace);
  end if;

  if v_ent is null then
    raise exception 'AUCUNE_ENTREPRISE|Aucune entreprise rattachée à votre compte.';
  end if;

  if v_role <> 'PROPRIETAIRE' and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul le propriétaire du compte peut changer la devise de travail.';
  end if;

  v_devise := upper(btrim(coalesce(p_devise, '')));
  if v_devise not in ('CDF', 'USD') then
    raise exception 'DEVISE_INCONNUE|Devise inconnue : choisissez CDF (franc congolais) ou USD (dollar américain).';
  end if;

  if p_taux is not null and p_taux < 0 then
    raise exception 'TAUX_INVALIDE|Le taux de change doit être un nombre positif (1 USD = X CDF).';
  end if;

  select coalesce(nullif(upper(btrim(coalesce(e.devise, ''))), ''), 'CDF')
    into v_avant
    from public.entreprises e
   where e.id = v_ent;

  -- Devise du COMPTE (défaut hérité par les nouveaux espaces) + taux.
  update public.entreprises
     set devise = v_devise,
         taux_usd_cdf = case
                          when p_taux is null then taux_usd_cdf
                          when p_taux = 0    then null      -- taux plateforme
                          else p_taux
                        end,
         updated_at = now()
   where id = v_ent;

  -- Devise PROPRE À L'ESPACE DE TRAVAIL (le patron règle l'entreprise qu'il
  -- est en train d'utiliser : une boutique peut rester en CDF, un hôtel en
  -- USD).
  if v_espace is not null and not (public.est_plateforme() and p_entreprise_id is not null) then
    update public.espaces
       set devise = v_devise,
           updated_at = now()
     where id = v_espace;
  end if;

  -- Trace (best-effort).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'DEVISE_CONFIG', v_user,
      jsonb_build_object(
        'entreprise_id', v_ent,
        'devise_avant',  v_avant,
        'devise',        v_devise,
        'taux_demande',  p_taux,
        'taux_effectif', public.taux_change_effectif(v_ent)
      )
    );
  exception when others then null;
  end;

  return public.rpc_devise_etat();
end;
$$;

comment on function public.rpc_devise_configurer(text, numeric, uuid) is
  'Module 18 — Le propriétaire choisit la devise de travail de son entreprise (CDF/USD) et son taux de change (0 = taux de la plateforme).';

revoke all on function public.rpc_devise_configurer(text, numeric, uuid) from public;
revoke all on function public.rpc_devise_configurer(text, numeric, uuid) from anon;
grant execute on function public.rpc_devise_configurer(text, numeric, uuid) to authenticated;


-- ============================================================================
--  6. `rpc_devise_plateforme_definir()` — TAUX PAR DÉFAUT (PLATEFORME)
-- ============================================================================
--  Réservé au SUPER_ADMIN : taux appliqué à toutes les entreprises qui n'ont
--  pas défini le leur, et devise proposée par défaut aux nouvelles.

create or replace function public.rpc_devise_plateforme_definir(
  p_taux          numeric,
  p_devise_defaut text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_defaut text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour régler le taux de la plateforme.';
  end if;

  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin peut régler le taux de change de la plateforme.';
  end if;

  if p_taux is null or p_taux <= 0 then
    raise exception 'TAUX_INVALIDE|Indiquez un taux positif (1 USD = X CDF).';
  end if;

  v_defaut := upper(btrim(coalesce(p_devise_defaut, '')));
  if v_defaut is not null and v_defaut <> '' and v_defaut not in ('CDF', 'USD') then
    raise exception 'DEVISE_INCONNUE|Devise par défaut inconnue (CDF ou USD).';
  end if;

  insert into public.app_settings (key, value, updated_at)
  values (
    'devises',
    jsonb_build_object(
      'taux_usd_cdf', p_taux,
      'devise_defaut', coalesce(nullif(v_defaut, ''), 'CDF')
    ),
    now()
  )
  on conflict (key) do update
    set value = coalesce(public.app_settings.value, '{}'::jsonb)
                || jsonb_build_object('taux_usd_cdf', p_taux)
                || case
                     when nullif(v_defaut, '') is null then '{}'::jsonb
                     else jsonb_build_object('devise_defaut', v_defaut)
                   end,
        updated_at = now();

  -- Trace (best-effort).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'DEVISE_CONFIG', v_user,
      jsonb_build_object(
        'portee', 'plateforme', 'taux_usd_cdf', p_taux,
        'devise_defaut', coalesce(nullif(v_defaut, ''), 'CDF')
      )
    );
  exception when others then null;
  end;

  return public.rpc_devise_etat();
end;
$$;

comment on function public.rpc_devise_plateforme_definir(numeric, text) is
  'Module 18 — Super Admin : taux de change par défaut de la plateforme (1 USD = X CDF) et devise proposée par défaut.';

revoke all on function public.rpc_devise_plateforme_definir(numeric, text) from public;
revoke all on function public.rpc_devise_plateforme_definir(numeric, text) from anon;
grant execute on function public.rpc_devise_plateforme_definir(numeric, text) to authenticated;


-- ============================================================================
--  7. `audit_niveau()` — NIVEAUX (DEVISE = CRITIQUE)
-- ============================================================================
--  Reprise de la version la plus complète (module 16 C5) + les actions IA du
--  module 13 (rétablies) + DEVISE_CONFIG / ESPACE_TYPE.
--  ⚠️ Toute nouvelle action doit être ajoutée ICI (et dans le module qui
--  l'utilise).

create or replace function public.audit_niveau(p_action text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_action, '')))
    -- CRITIQUE : argent, droits, cycle de vie des comptes, devise.
    when 'CREATION_ENTREPRISE'        then 'CRITIQUE'
    when 'CHANGEMENT_STATUT'          then 'CRITIQUE'
    when 'REACTIVATION'               then 'CRITIQUE'
    when 'CHANGEMENT_ROLE'            then 'CRITIQUE'
    when 'PERMISSIONS_MODIFIEES'      then 'CRITIQUE'
    when 'PERMISSIONS_REINITIALISEES' then 'CRITIQUE'
    when 'PRIX_MODIFIE'               then 'CRITIQUE'
    when 'ANNULATION_VENTE'           then 'CRITIQUE'
    when 'VENTE_SUPPRIMEE'            then 'CRITIQUE'
    when 'UTILISATEUR_SUPPRIME'       then 'CRITIQUE'
    when 'ENTREPRISE_SUPPRIMEE'       then 'CRITIQUE'
    when 'AGENT_IA_CONFIG'            then 'CRITIQUE'
    when 'DEVISE_CONFIG'              then 'CRITIQUE'
    -- HAUT : opérations financières et mouvements de stock.
    when 'VENTE'                      then 'HAUT'
    when 'PAIEMENT_ENREGISTRE'        then 'HAUT'
    when 'PAIEMENT_DETTE'             then 'HAUT'
    when 'DETTE'                      then 'HAUT'
    when 'DEPENSE'                    then 'HAUT'
    when 'CLOTURE_CAISSE'             then 'HAUT'
    when 'APPROVISIONNEMENT'          then 'HAUT'
    when 'AJUSTEMENT'                 then 'HAUT'
    when 'INVENTAIRE'                 then 'HAUT'
    when 'STOCK_MODIFIE'              then 'HAUT'
    when 'ARTICLE_SUPPRIME'           then 'HAUT'
    when 'CHANGEMENT_ACTIVATION'      then 'HAUT'
    when 'IMPORT_PRODUITS'            then 'HAUT'
    when 'AGENT_IA_ACHAT'             then 'HAUT'
    -- 🏨 MODULE 16 C2 — hôtel.
    when 'CHECKOUT_SEJOUR'            then 'HAUT'
    when 'SEJOUR_ENCAISSE'            then 'HAUT'
    -- 🍽️ MODULE 16 C3 — restaurant.
    when 'COMMANDE_ENCAISSEE'         then 'HAUT'
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    when 'EVENEMENT_ENCAISSE'         then 'HAUT'
    when 'EVENEMENT_ANNULE'           then 'HAUT'
    -- 🥖 MODULE 16 C5 — boulangerie.
    when 'PRODUCTION_TERMINEE'        then 'HAUT'
    -- MOYEN : administration courante et sessions.
    when 'CONNEXION'                  then 'MOYEN'
    when 'DECONNEXION'                then 'MOYEN'
    when 'CONNEXION_ECHEC'            then 'MOYEN'
    when 'ARTICLE_CREE'               then 'MOYEN'
    when 'ARTICLE_MODIFIE'            then 'MOYEN'
    when 'CONDITIONNEMENT_AJOUTE'     then 'MOYEN'
    when 'CONDITIONNEMENT_MODIFIE'    then 'MOYEN'
    when 'CONDITIONNEMENT_SUPPRIME'   then 'MOYEN'
    when 'UTILISATEUR_CREE'           then 'MOYEN'
    when 'UTILISATEUR_MODIFIE'        then 'MOYEN'
    when 'ENTREPRISE_MODIFIEE'        then 'MOYEN'
    when 'RELANCE_DETTE'              then 'MOYEN'
    when 'AGENT_IA'                   then 'MOYEN'
    when 'AGENT_IA_ATTRIBUTION'       then 'MOYEN'
    when 'ESPACE_TYPE'                then 'MOYEN'
    -- 🏨 MODULE 16 C2 — hôtel.
    when 'CHAMBRE_ENREGISTREE'        then 'MOYEN'
    when 'CHAMBRE_MODIFIEE'           then 'MOYEN'
    when 'CHAMBRE_STATUT'             then 'MOYEN'
    when 'RESERVATION'                then 'MOYEN'
    when 'RESERVATION_ANNULEE'        then 'MOYEN'
    when 'CHECKIN_SEJOUR'             then 'MOYEN'
    -- 🍽️ MODULE 16 C3 — restaurant.
    when 'TABLE_ENREGISTREE'          then 'MOYEN'
    when 'TABLE_MODIFIEE'             then 'MOYEN'
    when 'TABLE_STATUT'               then 'MOYEN'
    when 'COMMANDE'                   then 'MOYEN'
    when 'COMMANDE_ENVOYEE'           then 'MOYEN'
    when 'COMMANDE_STATUT'            then 'MOYEN'
    when 'COMMANDE_ANNULEE'           then 'MOYEN'
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    when 'SALLE_ENREGISTREE'          then 'MOYEN'
    when 'SALLE_MODIFIEE'             then 'MOYEN'
    when 'EVENEMENT'                  then 'MOYEN'
    when 'EVENEMENT_MODIFIE'          then 'MOYEN'
    when 'EVENEMENT_STATUT'           then 'MOYEN'
    -- 🥖 MODULE 16 C5 — boulangerie.
    when 'MATIERE_ENREGISTREE'        then 'MOYEN'
    when 'MATIERE_MODIFIEE'           then 'MOYEN'
    when 'MATIERE_APPRO'              then 'MOYEN'
    when 'MATIERE_AJUSTEMENT'         then 'MOYEN'
    when 'PRODUCTION'                 then 'MOYEN'
    when 'PRODUCTION_ANNULEE'         then 'MOYEN'
    when 'RAPPORT'                    then 'INFO'
    else 'INFO'
  end;
$$;

comment on function public.audit_niveau(text) is
  'Niveau de gravité d''une action du journal d''audit (+ actions IA module 13, devises module 18).';


-- ============================================================================
--  8. VÉRIFICATIONS (à relire après exécution)
-- ============================================================================

-- 8.a Colonnes de devise (attendu : entreprises.devise = CDF par défaut,
--     entreprises.taux_usd_cdf NULL, espaces.devise NULL).
select table_name, column_name, data_type, column_default, is_nullable
  from information_schema.columns
 where table_schema = 'public'
   and ((table_name = 'entreprises' and column_name in ('devise', 'taux_usd_cdf'))
        or (table_name = 'espaces' and column_name = 'devise'))
 order by table_name, column_name;

-- 8.b Réglage plateforme (attendu : {"taux_usd_cdf": 2800, ...}).
select key, value
  from public.app_settings
 where key = 'devises';

-- 8.c Devise des dernières entreprises + devise de leurs espaces.
select e.nom,
       e.devise as devise_compte,
       e.taux_usd_cdf as taux_entreprise,
       public.taux_change_effectif(e.id) as taux_applique,
       (select count(*) from public.espaces s where s.entreprise_id = e.id and s.devise is not null)
         as espaces_avec_devise_propre
  from public.entreprises e
 order by e.created_at desc
 limit 10;

-- 8.d Niveaux d'audit des nouvelles actions (attendu : CRITIQUE, MOYEN).
select public.audit_niveau('DEVISE_CONFIG')    as devise_config,
       public.audit_niveau('ESPACE_TYPE')      as espace_type,
       public.audit_niveau('AGENT_IA_CONFIG')  as agent_ia_config;

-- 8.e (à exécuter connecté, depuis l'app ou l'API) : état complet.
-- select public.rpc_devise_etat();

-- ============================================================================
--  FIN — Module 18. Chaque entreprise travaille dans sa devise (CDF/USD) ;
--  tous les montants de l'application (prix, ventes, dépenses, caisse,
--  rapports, paiements, abonnements) s'affichent avec son symbole, et un
--  taux « 1 USD = X CDF » — réglé par la plateforme et surchargeable par le
--  patron — permet les équivalences.
-- ============================================================================
