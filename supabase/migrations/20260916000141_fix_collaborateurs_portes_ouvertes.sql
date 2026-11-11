-- ============================================================================
--  biashara_yangu — MIGRATION 0141 : COMPTES COLLABORATEURS SANS BOUTIQUE
--
--  SIGNALEMENT
--    « rachel@biashara.com et abi@biashara.com sont des collaboratrices de
--      Portes Ouvertes. Quand elles se connectent, l'application écrit
--      "Bonjour utilisateur" et elles ne voient plus la boutique liée. »
--
--  POURQUOI ÇA ARRIVE (lecture du code, pas supposition)
--    À l'ouverture de l'accueil, l'application lit la FICHE du compte dans
--    `public.utilisateurs` :
--      • le prénom affiché vient de `nom` → vide ⇒ « Bonjour utilisateur » ;
--      • le lien avec l'entreprise vient de `parent_id` :
--          - `parent_id` renseigné ⇒ « collaborateur », la boutique du patron
--            s'affiche ;
--          - `parent_id` vide       ⇒ l'application croit que le compte est
--            PROPRIÉTAIRE de sa propre boutique : elle ouvre donc un espace
--            vide (stock, caisse) et perd la boutique « Portes Ouvertes ».
--    Autrement dit : la fiche existe, mais son rattachement (et parfois son
--    nom) manque. Rien à corriger dans l'application : tout se répare ici.
--
--  CE QUE FAIT CE SCRIPT
--    1. Il AFFICHE l'état actuel des deux comptes (avant).
--    2. Il crée `public.reparer_collaborateur(...)`, utilisable pour
--       n'importe quel autre compte dans le même cas.
--    3. Il répare les deux comptes : nom, prénom, téléphone, parent_id,
--       entreprise, espace actif, rôle collaborateur, compte validé.
--    4. Il ré-affiche les fiches (après) pour vérification.
--
--  ⚠️ IDEMPOTENT : on peut le relancer sans risque.
--  ⚠️ Aucun mot de passe, aucune donnée d'abonnement n'est touchée.
-- ============================================================================

select set_config('search_path', 'public, auth, extensions', true);


-- ============================================================================
--  1. ÉTAT ACTUEL (à lire dans le résultat du SQL Editor)
-- ============================================================================
--  ⚠️ La base de départ est `auth.users` : un compte peut se connecter SANS
--     avoir de fiche dans `public.utilisateurs`. C'est exactement le cas qui
--     produit « Bonjour utilisateur » + aucun droit : le compte n'apparaît
--     dans aucune liste construite à partir des fiches.

select 'AVANT' as moment,
       a.email,
       (u.id is not null)                              as fiche_existe,
       u.id                                            as fiche_id,
       coalesce(nullif(btrim(u.nom), ''), '(vide)')     as nom,
       coalesce(nullif(btrim(u.prenom), ''), '(vide)')  as prenom,
       coalesce(nullif(btrim(u.telephone), ''), '(vide)') as telephone,
       u.role                                      as role_herite,
       u.new_role::text                            as role_effectif,
       u.parent_id,
       u.entreprise_id,
       u.espace_actif_id,
       u.valide,
       coalesce(a.raw_user_meta_data->>'parentId',
                a.raw_user_meta_data->>'parent_id') as patron_dans_metadonnees,
       a.raw_user_meta_data,
       (select e.nom from public.entreprises e
         where e.id = u.entreprise_id)             as entreprise_liee
  from auth.users a
  left join public.utilisateurs u on u.id = a.id
 where lower(a.email) in ('rachel@biashara.com', 'abi@biashara.com')
 order by a.email;

-- Si ce résultat est VIDE (aucune ligne), c'est que les comptes de connexion
-- n'existent pas sous ces adresses exactes : vérifier l'orthographe ci-dessus.

-- Tous les propriétaires, avec l'entreprise et le nombre de collaborateurs.
-- C'est ici que se trouve « Portes Ouvertes » : la ligne donne l'e-mail du
-- patron à utiliser si le rattachement automatique ne le retrouve pas.
select 'TOUS LES PATRONS' as alerte,
       e.nom            as entreprise,
       s.nom            as espace,
       u.email          as proprietaire_email,
       u.nom            as proprietaire_nom,
       coalesce(u.new_role::text, u.role) as role,
       (select count(*) from public.utilisateurs c
         where c.parent_id = u.id) as nb_collaborateurs
  from public.utilisateurs u
  left join public.entreprises e on e.id = u.entreprise_id
  left join public.espaces s
         on s.entreprise_id = e.id
        and s.id = u.id
 where u.parent_id is null
   and coalesce(u.role, '') <> 'super_admin'
   and upper(coalesce(u.new_role::text, u.role, '')) not in
       ('SUPER_ADMIN', 'GESTIONNAIRE', 'FINANCE', 'SUPPORT')
 order by e.nom nulls last, u.nom;

-- Recherche ciblée : « portes » n'importe où (espacement, tiret, casse
-- indifférents), dans l'entreprise, l'espace ou le nom du patron.
select 'RECHERCHE PORTES' as alerte,
       e.nom as entreprise,
       s.nom as espace,
       u.email as proprietaire_email,
       u.nom as proprietaire_nom,
       u.id as proprietaire_id
  from public.utilisateurs u
  left join public.entreprises e on e.id = u.entreprise_id
  left join public.espaces s
         on s.entreprise_id = e.id
        and s.id = u.id
 where lower(regexp_replace(coalesce(e.nom, ''), '[^[:alnum:]]', '', 'g')) like '%portes%'
    or lower(regexp_replace(coalesce(s.nom, ''), '[^[:alnum:]]', '', 'g')) like '%portes%'
    or lower(regexp_replace(coalesce(u.nom, ''), '[^[:alnum:]]', '', 'g')) like '%portes%'
 order by e.nom nulls last;


-- ============================================================================
--  2. LA FONCTION DE RÉPARATION (réutilisable)
-- ============================================================================
--    p_email       : le compte à rattacher (obligatoire)
--    p_boutique    : nom de l'entreprise, pour retrouver le propriétaire
--                    (« Portes Ouvertes »)
--    p_proprietaire: e-mail du patron, si on préfère le désigner à la main
--                    (prioritaire sur p_boutique)
--    p_role        : rôle à donner (VENDEUR par défaut). Il est ÉCRIT, même si
--                    la fiche portait déjà une valeur : c'est ce qui rend au
--                    compte ses droits (Nouvelle vente + Scanner).

create or replace function public.reparer_collaborateur(
  p_email        text,
  p_boutique      text default null,
  p_proprietaire text default null,
  p_role         text default 'VENDEUR'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_uid    uuid;
  v_meta   jsonb := '{}'::jsonb;
  v_owner  uuid;
  v_ent    uuid;
  v_nom    text;
  v_prenom text;
  v_tel    text;
  v_role   text;
  v_role_enum public.role_utilisateur_enum;
  v_meta_nom    text;
  v_meta_prenom text;
  v_meta_tel    text;
  v_espace uuid;
  v_hint   text;
  v_boutique_norm text;
begin
  if v_email = '' then
    raise exception 'EMAIL_REQUIS|Indiquez l''adresse e-mail du collaborateur.';
  end if;

  -- 1) Le compte de connexion doit exister.
  select a.id, coalesce(a.raw_user_meta_data, '{}'::jsonb)
    into v_uid, v_meta
    from auth.users a
   where lower(a.email) = v_email
   limit 1;

  if v_uid is null then
    raise exception 'COMPTE_INTROUVABLE|Aucun compte de connexion pour %.', v_email;
  end if;

  -- 2) Retrouver le propriétaire.
  --    L'e-mail du patron n'est utilisé que s'il EN A L'AIR : recopier un
  --    modèle (« PATRON@.... ») ne doit pas bloquer la recherche automatique.
  if p_proprietaire is not null
     and btrim(p_proprietaire) <> ''
     and position('@' in p_proprietaire) > 1
     and position('.' in split_part(p_proprietaire, '@', 2)) > 1 then
    select u.id into v_owner
      from public.utilisateurs u
     where lower(u.email) = lower(btrim(p_proprietaire))
     limit 1;
    -- S'il n'existe pas, on continue : le nom de la boutique peut suffire.
  end if;

  -- 2 bis) INDICE DANS LE COMPTE DE CONNEXION.
  --  L'ancienne inscription par code boutique envoyait l'identifiant du patron
  --  dans les métadonnées du compte (`parentId`). Même si la fiche n'a jamais
  --  été créée, cet indice est encore là : on s'en sert en premier.
  if v_owner is null then
    v_hint := coalesce(
      nullif(btrim(coalesce(v_meta->>'parentId', '')), ''),
      nullif(btrim(coalesce(v_meta->>'parent_id', '')), ''),
      nullif(btrim(coalesce(v_meta->>'patron_id', '')), '')
    );
    if v_hint is not null then
      begin
        select u.id into v_owner
          from public.utilisateurs u
         where u.id = v_hint::uuid
           and u.parent_id is null
         limit 1;
      exception when others then
        v_owner := null;   -- l'indice n'était pas un identifiant valide
      end;
    end if;
  end if;

  if v_owner is null and p_boutique is not null and btrim(p_boutique) <> '' then
    -- Comparaison TOLÉRANTE : on ignore espaces, tirets, apostrophes et casse
    -- (« Portes Ouvertes » = « portes-ouvertes » = « PORTESOUVERTES »).
    v_boutique_norm := lower(regexp_replace(btrim(p_boutique), '[^[:alnum:]]', '', 'g'));

    -- Par le nom de l'ENTREPRISE.
    select e.id into v_ent
      from public.entreprises e
     where lower(regexp_replace(coalesce(e.nom, ''), '[^[:alnum:]]', '', 'g'))
           like '%' || v_boutique_norm || '%'
     order by e.created_at nulls last
     limit 1;

    -- Par le nom de l'ESPACE (la boutique), si l'entreprise ne porte pas ce nom.
    if v_ent is null then
      select s.entreprise_id into v_ent
        from public.espaces s
       where lower(regexp_replace(coalesce(s.nom, ''), '[^[:alnum:]]', '', 'g'))
             like '%' || v_boutique_norm || '%'
       order by s.created_at nulls last
       limit 1;
    end if;

    -- Par le NOM DU PATRON (dernier repli, ex. compte nommé « Portes Ouvertes »).
    if v_ent is null then
      select u.id into v_owner
        from public.utilisateurs u
       where u.parent_id is null
         and lower(regexp_replace(coalesce(u.nom, ''), '[^[:alnum:]]', '', 'g'))
             like '%' || v_boutique_norm || '%'
       order by u.created_at nulls last
       limit 1;
    end if;

    if v_owner is null and v_ent is not null then
      select u.id into v_owner
        from public.utilisateurs u
       where u.entreprise_id = v_ent
         and (u.parent_id is null
              or upper(coalesce(u.new_role::text, public.role_herite(u.role)))
                 = 'PROPRIETAIRE')
       order by (u.parent_id is null) desc,
                (upper(coalesce(u.new_role::text, public.role_herite(u.role)))
                 = 'PROPRIETAIRE') desc,
                u.created_at nulls last
       limit 1;
    end if;
  end if;

  -- Dernier recours : le compte se souvient peut-être déjà de son entreprise.
  if v_owner is null then
    select u.id into v_owner
      from public.utilisateurs u
     where u.entreprise_id = (select f.entreprise_id from public.utilisateurs f
                               where f.id = v_uid)
       and (u.parent_id is null
            or upper(coalesce(u.new_role::text, public.role_herite(u.role)))
               = 'PROPRIETAIRE')
     order by (u.parent_id is null) desc
     limit 1;
  end if;

  if v_owner is null then
    raise exception 'PROPRIETAIRE_INTROUVABLE|Impossible de retrouver le propriétaire de « % ». Relancez avec le paramètre p_proprietaire (l''e-mail du patron).',
      coalesce(p_boutique, 'la boutique');
  end if;

  -- Le propriétaire ne peut pas être lui-même un collaborateur.
  if v_owner = v_uid then
    return jsonb_build_object(
      'ok', true, 'deja_proprietaire', true, 'email', v_email);
  end if;

  -- 3) Identité : on garde ce qui existe, on complète avec les métadonnées
  --    du compte de connexion, puis avec l'adresse e-mail.
  --    (Aucune variable « %rowtype » : une fiche absente ne doit pas faire
  --     échouer la lecture.)
  select nullif(btrim(coalesce(u.nom, '')), ''),
         nullif(btrim(coalesce(u.prenom, '')), ''),
         nullif(btrim(coalesce(u.telephone, '')), '')
    into v_nom, v_prenom, v_tel
    from public.utilisateurs u
   where u.id = v_uid;

  v_meta_nom := coalesce(
    nullif(btrim(coalesce(v_meta->>'nom', '')), ''),
    nullif(btrim(coalesce(v_meta->>'name', '')), ''),
    nullif(btrim(coalesce(v_meta->>'full_name', '')), '')
  );
  v_meta_prenom := nullif(btrim(coalesce(v_meta->>'prenom', '')), '');
  v_meta_tel := coalesce(
    nullif(btrim(coalesce(v_meta->>'telephone', '')), ''),
    nullif(btrim(coalesce(v_meta->>'phone', '')), '')
  );

  v_nom := coalesce(
    v_nom,
    v_meta_nom,
    nullif(btrim(split_part(v_email, '@', 1)), '')
  );
  v_prenom := coalesce(v_prenom, v_meta_prenom, '');
  v_tel := coalesce(v_tel, v_meta_tel);

  -- « rachel » → « Rachel » : un prénom lisible plutôt qu'une minuscule.
  if length(v_nom) > 0 then
    v_nom := upper(left(v_nom, 1)) || substr(v_nom, 2);
  end if;

  -- 4) Le ROLE est ÉCRIT (pas « conservé ») : un rôle illisible côté
  --    application (valeur inconnue) laisse le compte SANS droits — d'où un
  --    accueil réduit à « Suivi commercial » au lieu de « Nouvelle vente »
  --    et « Scanner ». On repart donc d'un rôle connu du Module 4.
  v_role := coalesce(upper(nullif(btrim(coalesce(p_role, '')), '')), 'VENDEUR');
  if v_role not in ('PROPRIETAIRE', 'VENDEUR', 'MAGASINIER', 'COMPTABLE_ENTREPRISE') then
    v_role := 'VENDEUR';
  end if;
  v_role_enum := public.role_enum(v_role);

  -- L'espace par défaut porte l'UUID du patron : on ne le renseigne que si cet
  -- espace existe réellement (sinon la clé étrangère refuserait l'écriture).
  v_espace := case
                when exists (select 1 from public.espaces s where s.id = v_owner)
                then v_owner
                else null
              end;

  -- 4) La fiche est créée si elle manque, puis rattachée à l'entreprise.
  insert into public.utilisateurs (id, email, nom, prenom, telephone,
                                   role, new_role, valide,
                                   parent_id, entreprise_id, espace_actif_id)
  values (v_uid, v_email, v_nom, v_prenom, v_tel,
          'collaborator', v_role_enum, 1,
          v_owner,
          (select u.entreprise_id from public.utilisateurs u where u.id = v_owner),
          v_espace)
  on conflict (id) do update
     set email           = v_email,
         nom             = v_nom,
         prenom          = v_prenom,
         telephone       = coalesce(v_tel, utilisateurs.telephone),
         role            = 'collaborator',
         new_role        = excluded.new_role,
         valide          = 1,
         parent_id       = v_owner,
         entreprise_id   = excluded.entreprise_id,
         espace_actif_id = excluded.espace_actif_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'COLLABORATEUR_RATTACHE', v_uid,
    jsonb_build_object('proprietaire', v_owner, 'email', v_email,
                       'boutique', p_boutique, 'role', v_role),
    now()
  );

  return jsonb_build_object(
    'ok',        true,
    'email',     v_email,
    'id',        v_uid,
    'nom',       v_nom,
    'prenom',    v_prenom,
    'parent_id', v_owner,
    'role',      v_role
  );
end;
$$;

comment on function public.reparer_collaborateur(text, text, text, text) is
  'Rattache un compte collaborateur à l''entreprise de son propriétaire (nom, parent_id, entreprise, rôle). Réparable compte par compte, sans toucher au mot de passe.';

revoke all on function public.reparer_collaborateur(text, text, text, text) from public, anon;
grant execute on function public.reparer_collaborateur(text, text, text, text) to authenticated;


-- ============================================================================
--  3. RÉPARATION DES DEUX COMPTES
-- ============================================================================
--    Chaque compte est traité séparément : si l'un échoue (propriétaire
--    introuvable), l'autre est quand même réparé et l'erreur est affichée.

do $$
declare
  v_emails text[] := array['rachel@biashara.com', 'abi@biashara.com'];
  v_mail   text;
  v_res    jsonb;
begin
  foreach v_mail in array v_emails loop
    begin
      v_res := public.reparer_collaborateur(v_mail, 'Portes Ouvertes', null, 'VENDEUR');
      raise notice 'OK % → %', v_mail, v_res::text;
    exception when others then
      raise warning 'ÉCHEC % → %', v_mail, sqlerrm;
    end;
  end loop;
end $$;


-- ============================================================================
--  4. VÉRIFICATION (après)
-- ============================================================================

select 'APRÈS' as moment,
       u.email,
       u.nom,
       u.prenom,
       ('Bonjour ' || btrim(coalesce(u.prenom, '') || ' ' || coalesce(u.nom, '')))
                                                as salutation_attendue,
       u.role                                  as role_herite,
       u.new_role::text                        as role_effectif,
       case upper(coalesce(u.new_role::text, ''))
         when 'VENDEUR'   then 'Nouvelle vente + Scanner'
         when 'PROPRIETAIRE' then 'Nouvelle vente + Scanner'
         else 'Selon le rôle choisi'
       end                                     as actions_attendues,
       u.parent_id,
       p.nom                                   as patron,
       u.entreprise_id,
       e.nom                                   as entreprise,
       u.espace_actif_id,
       u.valide
  from public.utilisateurs u
  left join public.utilisateurs p on p.id = u.parent_id
  left join public.entreprises e on e.id = u.entreprise_id
 where lower(u.email) in ('rachel@biashara.com', 'abi@biashara.com')
 order by u.email;

select 'MIGRATION 0141 TERMINÉE' as controle,
       (select count(*) from public.utilisateurs u
         where lower(u.email) in ('rachel@biashara.com', 'abi@biashara.com')
           and u.parent_id is not null
           and nullif(btrim(u.nom), '') is not null) as comptes_rattaches_sur_2;
