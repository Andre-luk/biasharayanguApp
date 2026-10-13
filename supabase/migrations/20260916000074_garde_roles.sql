-- ============================================================================
--  biashara_yangu — CORRECTIF 74 : LE GARDE-FOU DES RÔLES
--  Migration 20260916000074_garde_roles.sql
-- ============================================================================
--
--  ⛔ AUCUNE PUBLICATION. Correction de base uniquement.
--
--  LA FAILLE (lue sur les règles RLS en production, pas supposée)
--  --------------------------------------------------------------
--  Sur `public.utilisateurs`, les règles PERMISSIVES disent :
--    • « L'utilisateur gère son propre profil »  → ALL, auth.uid() = id ;
--    • « L'utilisateur crée son propre profil »  → INSERT, auth.uid() = id ;
--    • « Les admins gèrent tout »                → ALL, is_admin() ;
--  et il n'existe AUCUNE règle RESTRICTIVE sur INSERT ni sur UPDATE.
--
--  Trois conséquences, toutes vérifiées par lecture des règles :
--    1. n'importe quel compte connecté peut réécrire SON `role`/`new_role` :
--         update public.utilisateurs set new_role = 'SUPER_ADMIN'
--          where id = auth.uid();
--    2. le rôle hérité « admin » vaut SUPER_ADMIN (`role_herite('admin')`) ;
--    3. le déclencheur d'inscription recopie le rôle envoyé par le CLIENT
--       dans les métadonnées : une inscription faite avec
--       `{"role": "admin"}` fabrique un Super Administrateur.
--  Le point 3 est exactement ce qui a été observé dans l'application : depuis
--  l'écran « Ajouter un utilisateur », un agent créait un administrateur.
--
--  CE QUE CE FICHIER FAIT — TROIS RÈGLES, DANS CET ORDRE
--  -----------------------------------------------------
--   R0  On ne garde QUE les changements de rôle. Une mise à jour qui laisse le
--       rôle identique (nom, téléphone, avatar, `valide`…) passe sans être
--       inspectée : aucune régression, aucun faux positif, et les opérations
--       d'entretien restent possibles.
--   R1  Un rôle de la PLATEFORME ne s'obtient JAMAIS par défaut : il faut
--       être déjà de la plateforme, ou poser explicitement le drapeau
--       d'autorisation (voir la note de maintenance). ⇒ ferme à la fois
--       l'auto-promotion ET le rôle glissé dans les métadonnées d'inscription,
--       quel que soit le chemin emprunté (application, API, inscription).
--   R2  Sur une écriture DIRECTE du client (rôle PostgreSQL `authenticated` =
--       l'application et toute requête PostgREST avec un jeton) : on ne donne
--       jamais plus de droits que les siens.
--
--  POURQUOI R2 NE COUVRE PAS LES FONCTIONS `security definer`
--  ----------------------------------------------------------
--  Dans une fonction `security definer`, `current_user` vaut le propriétaire
--  de la fonction, pas `authenticated`. Les chaînes légitimes du serveur
--  (création de compte, `rpc_entreprise_creer`, activation…) ne sont donc
--  jamais concernées — elles ne peuvent pas se casser.
--
--  CE QUI N'EST PAS TOUCHÉ
--  -----------------------
--   • les 4 comptes de la plateforme déjà créés : aucune écriture sur eux ;
--   • la re-exécution de la migration 7 (comptes plateforme) : elle met à jour
--     des rôles IDENTIQUES → R0 la laisse passer ;
--   • la création du compte d'un agent terrain ou d'un propriétaire
--     (`rpc_admin_creer_agent_terrain`, `rpc_admin_entreprise_creer`) ;
--   • l'activation, l'encaissement, la double validation.
--
--  ⚠️ À exécuter dans Supabase → SQL Editor → coller → Run.
--  IDEMPOTENTE : relançable sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA TABLE DES NIVEAUX — miroir exact de `RoleUtilisateur.niveau` (Dart)
-- ============================================================================
--  Fonction PURE : aucun accès à la base, aucune écriture.

create or replace function public.niveau_role(p_role text)
returns integer
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_role, '')))
           when 'SUPER_ADMIN'          then 100
           when 'GESTIONNAIRE_COMPTES' then  90
           when 'FINANCE_LAPERLE'      then  80
           when 'SUPPORT'              then  70
           when 'AGENT_TERRAIN'        then  60
           when 'PROPRIETAIRE'         then  50
           when 'COMPTABLE_ENTREPRISE' then  40
           when 'MAGASINIER'           then  30
           when 'VENDEUR'              then  20
           else 0
         end;
$$;

comment on function public.niveau_role(text) is
  'Correctif 74 — niveau de privilège d''un rôle (plus grand = plus de droits). Miroir de RoleUtilisateur.niveau côté application.';

grant execute on function public.niveau_role(text) to authenticated;


-- ============================================================================
--  2. LE GARDE-FOU
-- ============================================================================
--  Déclenché AVANT CHAQUE écriture sur `utilisateurs`. Il ne modifie jamais la
--  ligne : il l'accepte ou il refuse, avec un message que l'application sait
--  déjà afficher (le texte après le « | »).

create or replace function public.garder_role_utilisateur()
returns trigger
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_cible  text;
  v_ancien text;
  v_acteur text;
begin
  --  Rôle VISÉ : la colonne officielle `new_role` d'abord, sinon la conversion
  --  de la colonne héritée `role` — c'est là que « admin » devient SUPER_ADMIN.
  v_cible := coalesce(
    nullif(upper(btrim(coalesce(new.new_role::text, ''))), ''),
    public.role_herite(new.role),
    'INCONNU');

  -- ------------------------------------------------------------------- R0
  -- Aucun changement de rôle : on ne garde rien. C'est ce qui laisse passer
  -- toutes les mises à jour d'information, y compris l'entretien en SQL.
  if tg_op = 'UPDATE' then
    v_ancien := coalesce(
      nullif(upper(btrim(coalesce(old.new_role::text, ''))), ''),
      public.role_herite(old.role),
      'INCONNU');

    if v_cible is not distinct from v_ancien then
      return new;
    end if;
  end if;

  v_acteur := public.mon_role();

  -- ------------------------------------------------------------------- R1
  -- Rôle de la plateforme : jamais par défaut, quel que soit le chemin.
  --  • L'AGENT TERRAIN reste attribuable par tout compte de la plateforme :
  --    c'est le travail du Gestionnaire des comptes (module 21 ter).
  --  • Les QUATRE rôles d'administration n'obéissent qu'à un Super
  --    Administrateur — la règle est la même dans l'application
  --    (`RoleUtilisateur.attribuablesPar`).
  if v_cible = 'AGENT_TERRAIN' then
    if not (public.est_plateforme()
            or current_setting('biashara.role_plateforme', true) = '1') then
      raise exception 'DROIT_REFUSE|Le role % est reserve a la plateforme La Perle.', v_cible;
    end if;
  elsif v_cible in ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES',
                    'FINANCE_LAPERLE', 'SUPPORT') then
    if not (v_acteur = 'SUPER_ADMIN'
            or current_setting('biashara.role_plateforme', true) = '1') then
      raise exception 'DROIT_REFUSE|Seul un Super Administrateur attribue le role %.', v_cible;
    end if;
  end if;

  -- ------------------------------------------------------------------- R2
  -- Écriture DIRECTE du client : jamais plus de droits que les siens.
  --  • `v_acteur = 'INCONNU'` : le compte n'a pas encore de fiche — c'est le
  --    cas de l'inscription qui crée sa propre ligne. R1 a déjà écarté les
  --    rôles de la plateforme ; on ne bloque pas une inscription normale.
  --  • les fonctions `security definer` ne passent jamais ici.
  if current_user = 'authenticated' and v_acteur <> 'INCONNU' then
    if public.niveau_role(v_cible) > public.niveau_role(v_acteur) then
      raise exception 'DROIT_REFUSE|Vous ne pouvez pas attribuer le role % (votre role : %).',
        v_cible, v_acteur;
    end if;
  end if;

  return new;
end;
$$;

comment on function public.garder_role_utilisateur() is
  'Correctif 74 — Refuse une attribution de rôle non autorisée sur `utilisateurs` : rôle de la plateforme sans habilitation (R1), ou rôle supérieur au sien sur une écriture directe du client (R2). Laisse passer toute écriture qui ne change pas le rôle (R0).';

drop trigger if exists trg_garde_role_utilisateurs on public.utilisateurs;
create trigger trg_garde_role_utilisateurs
  before insert or update on public.utilisateurs
  for each row
  execute function public.garder_role_utilisateur();


-- ============================================================================
--  3. CONTRÔLE
-- ============================================================================

do $verif_74$
declare
  v_trg     integer;
  v_def     text;
  v_niveaux integer;
  v_plat    integer;
begin
  --  3.a Le déclencheur est bien en place, et non désactivé.
  select count(*) into v_trg
    from pg_trigger
   where tgname = 'trg_garde_role_utilisateurs'
     and not tgisinternal
     and tgenabled <> 'D';

  if v_trg <> 1 then
    raise exception 'Correctif 74 : le declencheur n''est pas actif.';
  end if;

  --  3.b La fonction contient bien les deux règles.
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'garder_role_utilisateur';

  if position('niveau_role' in v_def) = 0
     or position('role_plateforme' in v_def) = 0 then
    raise exception 'Correctif 74 : le garde-fou est incomplet.';
  end if;

  --  3.c La table des niveaux est correcte (miroir du Dart).
  select count(*) into v_niveaux
    from (select 1) x
   where public.niveau_role('SUPER_ADMIN') = 100
     and public.niveau_role('GESTIONNAIRE_COMPTES') = 90
     and public.niveau_role('AGENT_TERRAIN') = 60
     and public.niveau_role('PROPRIETAIRE') = 50
     and public.niveau_role('VENDEUR') = 20
     and public.niveau_role('INCONNU') = 0;

  if v_niveaux <> 1 then
    raise exception 'Correctif 74 : la table des niveaux est incorrecte.';
  end if;

  --  ⚠️ On SIGNALE les comptes de la plateforme, on ne bloque pas : ce sont
  --     les comptes légitimes, ils n'ont pas à être touchés.
  select count(*) into v_plat
    from public.utilisateurs
   where coalesce(nullif(upper(btrim(coalesce(new_role::text, ''))), ''),
                  public.role_herite(role)) in
         ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE', 'SUPPORT');

  raise notice 'Correctif 74 pret : garde-fou actif, % compte(s) de plateforme.';
end $verif_74$;


-- ============================================================================
--  RAPPORT FINAL
-- ============================================================================
--  ⚠️ En DERNIER : le SQL Editor n'affiche que la dernière instruction.

select 'CORRECTIF 74 — ACTIF' as resultat,
       (select count(*) from pg_trigger
         where tgname = 'trg_garde_role_utilisateurs' and not tgisinternal) as declencheur,
       (select count(*) from public.utilisateurs u
         where coalesce(nullif(upper(btrim(coalesce(u.new_role::text, ''))), ''),
                        public.role_herite(u.role))
               in ('SUPER_ADMIN', 'GESTIONNAIRE_COMPTES', 'FINANCE_LAPERLE', 'SUPPORT')) as comptes_plateforme,
       (select count(*) from public.utilisateurs u
         where coalesce(nullif(upper(btrim(coalesce(u.new_role::text, ''))), ''),
                        public.role_herite(u.role)) = 'AGENT_TERRAIN') as agents_terrain,
       (select count(*) from public.utilisateurs u
         where coalesce(nullif(upper(btrim(coalesce(u.new_role::text, ''))), ''),
                        public.role_herite(u.role)) = 'SUPER_ADMIN') as super_admins;


-- ============================================================================
--  NOTE DE MAINTENANCE — à lire une fois, à garder sous la main
-- ============================================================================
--
--  1) CRÉER OU RÉALIGNER UN COMPTE DE LA PLATEFORME (Super Admin, Gestionnaire
--     des comptes, Finance, Assistance) depuis le SQL Editor : posez d'abord
--     le drapeau, DANS LA MÊME EXÉCUTION (un « Run » = une transaction) :
--
--         select set_config('biashara.role_plateforme', '1', true);
--         select public.creer_compte_plateforme(
--                  'nouveau@biasharayangu.cd', 'MotDePasse!2026',
--                  'Nom', 'Prenom', 'FINANCE_LAPERLE');
--
--     Le drapeau est LOCAL À LA TRANSACTION : il ne peut pas être posé depuis
--     l'application, ni depuis une inscription. C'est tout l'intérêt.
--
--  2) TOUT LE RESTE PASSE SANS RIEN FAIRE : changer un nom, un téléphone, un
--     mot de passe, activer/désactiver un compte, créer un propriétaire ou un
--     agent terrain depuis l'application.
--
--  3) SI UN MESSAGE « DROIT_REFUSE » APPARAÎT : il nomme le rôle refusé et le
--     rôle de celui qui a tenté. C'est le garde-fou qui fait son travail —
--     l'attribution était soit non autorisée, soit une élévation.
-- ============================================================================
