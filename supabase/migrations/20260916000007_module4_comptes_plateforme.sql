-- ============================================================================
--  biashara_yangu — MODULE 4 : COMPTES DE LA PLATEFORME (LA PERLE)
--
--  Crée les QUATRE comptes qui administrent la plateforme :
--
--    super.admin@biasharayangu.cd   SUPER_ADMIN           Accès total
--    comptes@biasharayangu.cd       GESTIONNAIRE_COMPTES  Comptes & référentiels
--    finance@biasharayangu.cd       FINANCE_LAPERLE       Abonnements & paiements
--    support@biasharayangu.cd       SUPPORT               Assistance
--
--  ⚠️ LES MOTS DE PASSE SONT ÉCRITS DANS CE FICHIER
--     Ils sont volontairement explicites pour une première mise en service.
--     Changez-les dès la première connexion, écran « Paramètres → Changer le
--     mot de passe » (ou la commande SQL en fin de script).
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  PRÉ-REQUIS
--    20260916000005_module4_permissions_enum.sql ET
--    20260916000006_module4_permissions.sql déjà exécutés.
--
--  IDEMPOTENT : relancer le script ne duplique rien et RÉINITIALISE les mots
--  de passe à leur valeur d'origine (sauf si vous utilisez le bloc « mot de
--  passe inchangé », section 5).
-- ============================================================================


-- `crypt()` et `gen_salt()` viennent de pgcrypto (schéma `extensions` sur
-- Supabase). Le search_path local couvre les deux emplacements possibles.
select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable : pgcrypto est-il disponible ?
do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'crypt'
      and n.nspname in ('public', 'extensions')
  ) then
    raise exception
      'pgcrypto est absent : activez-le dans Database → Extensions → pgcrypto.';
  end if;
end $$;


-- ============================================================================
--  1. FONCTION DE CRÉATION D'UN COMPTE DE PLATEFORME
-- ============================================================================
--  `security definer` : la fonction écrit dans le schéma `auth`, réservé au
--  propriétaire de la base. Elle est révoquée à tout le monde : seul le SQL
--  Editor (rôle postgres) peut la lancer.
--
--  Un compte de plateforme :
--    - n'est rattaché à AUCUNE entreprise (`entreprise_id` null) ;
--    - n'a AUCUN parent (`parent_id` null) ;
--    - porte son rôle dans `utilisateurs.new_role` ;
--    - conserve `utilisateurs.role = 'admin'` pour l'ancien code qui teste
--      encore cette colonne (la nouvelle matrice lit `new_role`).

create or replace function public.creer_compte_plateforme(
  p_email    text,
  p_password text,
  p_nom      text,
  p_prenom   text,
  p_role     text
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_email       text := lower(btrim(p_email));
  v_role_code   text := upper(btrim(p_role));
  v_role_enum   public.role_utilisateur_enum;
  v_user_id     uuid;
  v_identite_id uuid;
  v_provider_id_genere boolean := false;
begin
  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE : %', p_email;
  end if;

  if p_password is null or length(p_password) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT : %', v_email;
  end if;

  v_role_enum := public.role_enum(v_role_code);
  if v_role_enum is null then
    raise exception 'ROLE_INCONNU : % (exécuter le script d''enum Module 4)', p_role;
  end if;

  -- ------------------------------------------------ compte Auth (GoTrue)
  select u.id into v_user_id
    from auth.users u
   where lower(u.email) = v_email
   limit 1;

  if v_user_id is null then
    v_user_id := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      v_email,
      crypt(p_password, gen_salt('bf')),
      now(), now(), now(),
      jsonb_build_object('provider', 'email', 'providers', array['email']),
      jsonb_build_object('nom', p_nom, 'prenom', p_prenom, 'role', v_role_code),
      '', '', '', ''
    );
  else
    -- Compte déjà présent : on réaligne le mot de passe et la confirmation.
    update auth.users
       set encrypted_password = crypt(p_password, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at         = now(),
           raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
                                || jsonb_build_object('role', v_role_code)
     where id = v_user_id;
  end if;

  -- ------------------------------------------- identité (facultatif)
  -- Certaines versions de GoTrue gèrent `provider_id` en colonne générée :
  -- on ne l'alimente que si c'est une colonne ordinaire, et l'échec éventuel
  -- n'empêche jamais la connexion par mot de passe.
  begin
    if exists (
      select 1 from information_schema.columns
       where table_schema = 'auth' and table_name = 'identities'
         and column_name = 'provider_id' and is_generated = 'NEVER'
    ) then
      v_provider_id_genere := false;
    else
      v_provider_id_genere := true;
    end if;

    select i.id into v_identite_id
      from auth.identities i
     where i.user_id = v_user_id and i.provider = 'email'
     limit 1;

    if v_identite_id is null then
      if v_provider_id_genere then
        execute format(
          'insert into auth.identities (id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
           values (%L, %L, %L::jsonb, %L, now(), now(), now())',
          gen_random_uuid(), v_user_id,
          jsonb_build_object('sub', v_user_id::text, 'email', v_email)::text,
          'email'
        );
      else
        execute format(
          'insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
           values (%L, %L, %L::jsonb, %L, %L, now(), now(), now())',
          gen_random_uuid(), v_user_id,
          jsonb_build_object('sub', v_user_id::text, 'email', v_email)::text,
          'email', v_user_id::text
        );
      end if;
    end if;
  exception
    when others then
      raise notice 'Identité non créée pour % (sans impact sur la connexion) : %',
        v_email, sqlerrm;
  end;

  -- ------------------------------------- profil applicatif `utilisateurs`
  insert into public.utilisateurs (
    id, nom, prenom, email, role, new_role, valide, entreprise_id, parent_id, created_at
  ) values (
    v_user_id, p_nom, p_prenom, v_email, 'admin', v_role_enum, 1, null, null, now()
  )
  on conflict (id) do update
     set email         = excluded.email,
         nom           = coalesce(nullif(excluded.nom, ''), public.utilisateurs.nom),
         prenom        = coalesce(nullif(excluded.prenom, ''), public.utilisateurs.prenom),
         role          = 'admin',
         new_role      = excluded.new_role,
         valide        = 1,
         entreprise_id = null,
         parent_id     = null;

  raise notice 'Compte prêt : % → %', v_email, v_role_code;
  return v_user_id;
end;
$$;

revoke all on function public.creer_compte_plateforme(text, text, text, text, text)
  from public, anon, authenticated;


-- ============================================================================
--  2. CRÉATION DES QUATRE COMPTES
-- ============================================================================
--  ▶▶▶ CE SONT LES IDENTIFIANTS À COMMUNIQUER ◀◀◀
--
--  ┌──────────────────────────────┬─────────────────────────┬──────────────────────────┐
--  │ Email                        │ Mot de passe            │ Rôle                     │
--  ├──────────────────────────────┼─────────────────────────┼──────────────────────────┤
--  │ super.admin@biasharayangu.cd │ LaPerle!Super2026       │ SUPER_ADMIN              │
--  │ comptes@biasharayangu.cd     │ LaPerle!Comptes2026     │ GESTIONNAIRE_COMPTES     │
--  │ finance@biasharayangu.cd     │ LaPerle!Finance2026     │ FINANCE_LAPERLE          │
--  │ support@biasharayangu.cd     │ LaPerle!Support2026     │ SUPPORT                  │
--  └──────────────────────────────┴─────────────────────────┴──────────────────────────┘

select public.creer_compte_plateforme(
  'super.admin@biasharayangu.cd', 'LaPerle!Super2026',
  'La Perle', 'Super Administrateur', 'SUPER_ADMIN'
);

select public.creer_compte_plateforme(
  'comptes@biasharayangu.cd', 'LaPerle!Comptes2026',
  'La Perle', 'Gestion des comptes', 'GESTIONNAIRE_COMPTES'
);

select public.creer_compte_plateforme(
  'finance@biasharayangu.cd', 'LaPerle!Finance2026',
  'La Perle', 'Finance', 'FINANCE_LAPERLE'
);

select public.creer_compte_plateforme(
  'support@biasharayangu.cd', 'LaPerle!Support2026',
  'La Perle', 'Assistance', 'SUPPORT'
);


-- ============================================================================
--  3. (OPTIONNEL) COMPTES D'ENTREPRISE DE DÉMONSTRATION
-- ============================================================================
--  Décommentez si vous voulez aussi un propriétaire, un vendeur, un
--  magasinier et un comptable pour tester les permissions de l'espace
--  boutique. ⚠️ Ces comptes de démonstration n'ont pas d'entreprise : le
--  rattachement se fait depuis « Administration → Utilisateurs ».

-- select public.creer_compte_plateforme(
--   'patron@demo.cd', 'Demo!Patron2026', 'Démo', 'Patron', 'PROPRIETAIRE');
-- select public.creer_compte_plateforme(
--   'vendeur@demo.cd', 'Demo!Vendeur2026', 'Démo', 'Vendeur', 'VENDEUR');
-- select public.creer_compte_plateforme(
--   'magasinier@demo.cd', 'Demo!Magasin2026', 'Démo', 'Magasinier', 'MAGASINIER');
-- select public.creer_compte_plateforme(
--   'comptable@demo.cd', 'Demo!Comptable2026', 'Démo', 'Comptable', 'COMPTABLE_ENTREPRISE');


-- ============================================================================
--  4. VÉRIFICATION
-- ============================================================================

select
  u.email,
  coalesce(u.new_role::text, '(non converti)') as role_module4,
  u.role                                      as ancien_role,
  u.entreprise_id,
  u.parent_id,
  u.valide,
  (a.email_confirmed_at is not null)          as email_confirme,
  (a.encrypted_password is not null)          as mot_de_passe_defini
from public.utilisateurs u
left join auth.users a on a.id = u.id
where u.email in ('super.admin@biasharayangu.cd', 'comptes@biasharayangu.cd',
                  'finance@biasharayangu.cd', 'support@biasharayangu.cd')
order by u.email;

-- Contrôle des droits accordés (doit renvoyer true/false en colonnes).
select
  public.a_permission('SUPER_ADMIN', 'paiements', 'creer')          as super_admin_paie,
  public.a_permission('GESTIONNAIRE_COMPTES', 'entreprises', 'creer') as gestionnaire_cree,
  public.a_permission('GESTIONNAIRE_COMPTES', 'finance', 'voir')    as gestionnaire_finance,
  public.a_permission('FINANCE_LAPERLE', 'paiements', 'creer')      as finance_paie,
  public.a_permission('SUPPORT', 'assistance', 'modifier')          as support_assistance,
  public.a_permission('SUPPORT', 'parametres', 'modifier')          as support_parametres;


-- ============================================================================
--  5. CHANGER UN MOT DE PASSE (à faire après la première connexion)
-- ============================================================================

-- update auth.users
--    set encrypted_password = crypt('NOUVEAU_MOT_DE_PASSE', gen_salt('bf')),
--        updated_at         = now()
--  where email = 'super.admin@biasharayangu.cd';


-- ============================================================================
--  6. SUPPRIMER UN COMPTE DE PLATEFORME
-- ============================================================================
--  Suppression complète (Auth + profil). À manier avec précaution : le
--  SUPER_ADMIN est le seul rôle autorisé à modifier les permissions.

-- delete from auth.users      where email = 'support@biasharayangu.cd';
-- delete from public.utilisateurs where email = 'support@biasharayangu.cd';
