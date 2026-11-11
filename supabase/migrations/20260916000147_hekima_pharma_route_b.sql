-- ============================================================================
--  biashara_yangu — MIGRATION 0147 : OUVRIR « HEKIMA PHARMA »
--  (Route B : une ENTREPRISE de plus pour le même propriétaire)
--
--  DEMANDE
--    « Hekima Pharma appartient à josephissa@gmail.com, qui gère déjà
--      Urembo Market. Harold y travaille. Pas de frais d'installation,
--      7 jours d'essai, puis 12 500 FC/mois (10 000 + 2 500 collaborateur).
--      Les DEUX abonnements sont séparés, mais il n'y a qu'UN propriétaire. »
--
--  PRÉ-REQUIS
--      • 20260916000145_entreprises_owner_id.sql
--      • 20260916000146_bascule_entreprise.sql
--
--  CE QUE FAIT CE SCRIPT
--    1. Crée l'ENTREPRISE « HEKIMA PHARMA » (owner_id = josephissa) → elle
--       porte SON abonnement, indépendant de celui d'Urembo.
--    2. Crée sa boutique (espace de type `pharmacie` → module péremption).
--    3. Crée le compte de connexion d'Harold (mot de passe 12345678) et le
--       rattache à CETTE entreprise / CETTE boutique, rôle VENDEUR.
--    4. Ouvre 7 jours d'essai et met `prix_installation = 0`
--       (frais d'installation offerts pour la pharmacie).
--    5. Affiche la facture attendue : base 10 000 + 2 500 × collaborateurs
--       = 12 500 FC (le patron n'est jamais compté).
--
--  ⚠️ Ce script travaille pour le patron désigné par `v_email_patron`,
--     même exécuté depuis l'éditeur SQL (pas de session : `auth.uid()` est
--     NULL, donc on n'appelle pas les RPC qui en dépendent).
--  ⚠️ IDEMPOTENT : relançable sans doublon.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. ÉTAT DES LIEUX (avant)
-- ============================================================================

select 'PATRON' as etape,
       u.id                                                as patron_id,
       u.email,
       coalesce(u.nom, '') || ' ' || coalesce(u.prenom, '') as nom,
       coalesce(u.new_role::text, u.role)                   as role,
       u.entreprise_id                                      as entreprise_active
  from public.utilisateurs u
 where lower(u.email) = 'josephissa@gmail.com';

select 'ENTREPRISES DU PATRON' as etape,
       e.nom,
       e.statut,
       to_char(e.date_expiration, 'DD/MM/YYYY') as echeance,
       e.prix_installation,
       e.owner_id = u.id                        as bien_rattachee,
       (select count(*) from public.espaces s where s.entreprise_id = e.id)
                                                as nb_boutiques
  from public.entreprises e
  join public.utilisateurs u on lower(u.email) = 'josephissa@gmail.com'
 where e.owner_id = u.id
 order by e.created_at;


-- ============================================================================
--  2. CRÉATION
-- ============================================================================

do $$
declare
  -- ─────────────────────────── PARAMÈTRES ───────────────────────────
  v_email_patron  text    := 'josephissa@gmail.com';
  v_nom_pharmacie text    := 'HEKIMA PHARMA';
  v_email_collab  text    := 'harold@gmail.com';
  v_mdp_collab    text    := '12345678';
  v_nom_collab    text    := 'Harold';
  v_prenom_collab text    := '';
  v_role_collab   text    := 'VENDEUR';
  v_jours_essai   integer := 7;
  v_installation_offerte boolean := true;
  -- ──────────────────────────────────────────────────────────────────

  v_patron   uuid;
  v_ent      uuid;
  v_espace   uuid;
  v_uid      uuid;
  v_grille   uuid;
  v_total    numeric := 0;
begin
  select u.id into v_patron
    from public.utilisateurs u
   where lower(u.email) = lower(v_email_patron)
   limit 1;

  if v_patron is null then
    raise exception 'PROPRIETAIRE_INTROUVABLE|Aucun compte pour %.', v_email_patron;
  end if;

  -- 1) L'ENTREPRISE (idempotent : on la retrouve si elle existe déjà).
  select e.id into v_ent
    from public.entreprises e
   where e.owner_id = v_patron
     and lower(regexp_replace(e.nom, '[^[:alnum:]]', '', 'g'))
         = lower(regexp_replace(v_nom_pharmacie, '[^[:alnum:]]', '', 'g'))
   limit 1;

  if v_ent is null then
    -- Grille tarifaire du patron (celle de son entreprise la plus ancienne).
    select e.groupe_tarifaire_id into v_grille
      from public.entreprises e
     where e.owner_id = v_patron
     order by e.created_at nulls first
     limit 1;

    insert into public.entreprises (nom, owner_id)
    values (v_nom_pharmacie, v_patron)
    returning id into v_ent;

    update public.entreprises
       set statut              = 'ESSAI_7J'::public.statut_abonnement_enum,
           date_activation     = now(),
           date_expiration     = now() + make_interval(days => v_jours_essai),
           prix_installation   = case when v_installation_offerte then 0 else prix_installation end,
           groupe_tarifaire_id = coalesce(groupe_tarifaire_id, v_grille),
           updated_at          = now()
     where id = v_ent;

    raise notice 'Entreprise créée : % (id %), essai de % jours, installation offerte : %',
      v_nom_pharmacie, v_ent, v_jours_essai, v_installation_offerte;
  else
    raise notice 'Entreprise déjà présente : % (id %)', v_nom_pharmacie, v_ent;
  end if;

  -- 2) La BOUTIQUE (espace de type pharmacie).
  select s.id into v_espace
    from public.espaces s
   where s.entreprise_id = v_ent
     and lower(regexp_replace(s.nom, '[^[:alnum:]]', '', 'g'))
         = lower(regexp_replace(v_nom_pharmacie, '[^[:alnum:]]', '', 'g'))
   limit 1;

  if v_espace is null then
    insert into public.espaces (entreprise_id, nom, type, actif)
    values (v_ent, v_nom_pharmacie, 'pharmacie', true)
    returning id into v_espace;
    raise notice 'Boutique créée : % (espace %)', v_nom_pharmacie, v_espace;
  else
    raise notice 'Boutique déjà présente : % (espace %)', v_nom_pharmacie, v_espace;
  end if;

  -- 3) Le collaborateur Harold.
  select a.id into v_uid
    from auth.users a
   where lower(a.email) = lower(v_email_collab)
   limit 1;

  if v_uid is null then
    v_uid := public.creer_compte_plateforme(
      lower(v_email_collab), v_mdp_collab, v_nom_collab, v_prenom_collab, v_role_collab);
    raise notice 'Compte de connexion créé : %', v_email_collab;
  else
    update auth.users
       set encrypted_password = crypt(v_mdp_collab, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at         = now()
     where id = v_uid;
    raise notice 'Compte existant réutilisé : %', v_email_collab;
  end if;

  update public.utilisateurs
     set nom             = v_nom_collab,
         prenom          = v_prenom_collab,
         email           = lower(v_email_collab),
         role            = 'collaborator',
         new_role        = coalesce(public.role_enum(v_role_collab),
                                    public.role_enum('VENDEUR')),
         valide          = 1,
         parent_id       = v_patron,
         entreprise_id   = v_ent,        -- l'entreprise de la PHARMACIE
         espace_actif_id = v_espace      -- et sa boutique
   where id = v_uid;

  raise notice 'Collaborateur rattaché : % → %', v_email_collab, v_nom_pharmacie;

  -- 4) Montant mensuel dû (base + collaborateurs de CETTE entreprise).
  v_total := public.abonnement_prix_base(v_ent)
             + public.abonnement_supplement_collaborateurs(v_ent);

  update public.entreprises
     set montant_total_du = v_total,
         updated_at       = now()
   where id = v_ent
     and coalesce(montant_total_du, 0) is distinct from v_total;

  raise notice 'Facture mensuelle % : % FC (base % + collaborateurs %).',
    v_nom_pharmacie, v_total,
    public.abonnement_prix_base(v_ent),
    public.abonnement_supplement_collaborateurs(v_ent);
end $$;


-- ============================================================================
--  3. VÉRIFICATION
-- ============================================================================

select 'ENTREPRISE' as controle,
       e.nom,
       e.statut,
       to_char(e.date_activation, 'DD/MM/YYYY HH24:MI') as activation,
       to_char(e.date_expiration, 'DD/MM/YYYY HH24:MI') as echeance,
       e.prix_installation,
       (e.date_expiration - now())                       as temps_restant,
       (select count(*) from public.espaces s where s.entreprise_id = e.id)
                                                         as nb_boutiques
  from public.entreprises e
 where e.owner_id = (select u.id from public.utilisateurs u
                      where lower(u.email) = 'josephissa@gmail.com')
   and lower(regexp_replace(e.nom, '[^[:alnum:]]', '', 'g')) = 'hekimapharma';

select 'HAROLD' as controle,
       u.email,
       coalesce(u.nom, '') || ' ' || coalesce(u.prenom, '') as nom,
       coalesce(u.new_role::text, u.role)                   as role,
       u.valide,
       p.email                       as patron,
       e.nom                         as entreprise,
       (select s.nom from public.espaces s where s.id = u.espace_actif_id) as boutique,
       (a.id is not null)            as compte_connexion_existe
  from public.utilisateurs u
  left join public.utilisateurs p on p.id = u.parent_id
  left join public.entreprises e on e.id = u.entreprise_id
  left join auth.users a on a.id = u.id
 where lower(u.email) = 'harold@gmail.com';

-- Les DEUX factures, séparées (attendu : 12 500 chacune).
select 'FACTURES' as controle,
       e.nom as entreprise,
       e.statut,
       public.abonnement_prix_base(e.id)                 as base,
       public.abonnement_collaborateurs_actifs(e.id)     as collaborateurs_factures,
       public.abonnement_supplement_collaborateurs(e.id) as supplement,
       public.abonnement_prix_base(e.id)
         + public.abonnement_supplement_collaborateurs(e.id) as total_mensuel
  from public.entreprises e
 where e.owner_id = (select u.id from public.utilisateurs u
                      where lower(u.email) = 'josephissa@gmail.com')
 order by e.created_at;

select 'MIGRATION 0147 TERMINÉE' as controle,
       (select count(*) from public.entreprises e
         where e.owner_id = (select u.id from public.utilisateurs u
                              where lower(u.email) = 'josephissa@gmail.com'))
         as entreprises_du_patron,
       (select count(*) from public.utilisateurs u
         where lower(u.email) = 'harold@gmail.com'
           and u.parent_id is not null
           and u.espace_actif_id is not null)
         as harold_ok;
