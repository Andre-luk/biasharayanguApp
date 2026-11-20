-- ============================================================================
--  biashara_yangu — CORRECTIF 176 : SUPPRESSION D'UN COLLABORATEUR
--
--  PROBLÈME CONSTATÉ (audit du 20/11/2026)
--  ---------------------------------------
--  L'écran « Mon Équipe » (Paramètres → Mes vendeurs) appelle depuis toujours
--  une RPC nommée `delete_collaborateur`… qui n'existe dans AUCUNE migration.
--  Résultat : le bouton « Supprimer » échoue systématiquement
--  (« Could not find the function public.delete_collaborateur »), avant même
--  d'atteindre la base. La création et la modification d'un collaborateur
--  fonctionnaient (rpc_collaborateur_creer / _maj, migration 0140), pas la
--  suppression.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--   1. `rpc_collaborateur_supprimer(p_id, p_confirmation)` — la vraie route :
--      • propriétaire de l'entreprise (ou plateforme) uniquement ;
--      • confirmation écrite « SUPPRIMER » exigée ;
--      • jamais son propre compte, jamais le propriétaire ;
--      • le collaborateur doit appartenir à l'équipe du demandeur ;
--      • supprime le profil (`public.utilisateurs`) puis le compte Auth ;
--      • journalise `COLLABORATEUR_SUPPRIME`.
--   2. `delete_collaborateur(target_user_id)` — ALIAS historique : il garde
--      l'application DÉJÀ INSTALLÉE fonctionnelle (aucune mise à jour requise
--      sur les téléphones), tout en appliquant exactement les mêmes gardes.
--
--  ⚠️ AUCUNE donnée métier n'est supprimée : ventes, caisse, stock, lots et
--     historiques gardent leurs lignes (les liens vers l'auteur sont mis à
--     NULL par les clés étrangères `on delete set null`). Seuls le profil et
--     le compte de connexion disparaissent.
--
--  ⚠️ Si le journal d'audit bloque encore la suppression (clé étrangère
--     historique), le message renvoie vers la migration 174, qui a retiré
--     cette contrainte.
--
--  IDEMPOTENT : peut être relancé sans effet de bord.
--  PRÉREQUIS : migration 174 exécutée (journal d'audit sans FK).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA VRAIE FONCTION DE SUPPRESSION
-- ============================================================================

create or replace function public.rpc_collaborateur_supprimer(
  p_id           uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_cible public.utilisateurs%rowtype;
  v_auth  boolean := false;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if p_id is null then
    raise exception 'COLLABORATEUR_INTROUVABLE|Aucun collaborateur choisi.';
  end if;

  -- Le propriétaire de l'entreprise (ou la plateforme) décide.
  v_owner := coalesce(public.mon_proprietaire(), v_user);
  if not (v_user = v_owner or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut supprimer un collaborateur.';
  end if;

  if upper(btrim(coalesce(p_confirmation, ''))) <> 'SUPPRIMER' then
    raise exception 'CONFIRMATION_REQUISE|Tapez SUPPRIMER pour confirmer la suppression.';
  end if;

  select * into v_cible from public.utilisateurs where id = p_id;
  if not found then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''existe plus.';
  end if;

  if p_id = v_user then
    raise exception 'ACTION_INTERDITE|Vous ne pouvez pas supprimer votre propre compte par cet écran.';
  end if;

  if p_id = v_owner then
    raise exception 'DROIT_REFUSE|Le propriétaire de l''entreprise ne peut pas être supprimé ici.';
  end if;

  if v_cible.parent_id is distinct from v_owner and not public.est_plateforme() then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''appartient pas à votre entreprise.';
  end if;

  -- Détache les liens qui pourraient bloquer la suppression (aucune donnée
  -- métier n'est perdue : on met seulement l'auteur à NULL).
  begin
    update public.utilisateurs
       set parent_id = null
     where parent_id = p_id;
  exception when others then null;
  end;

  begin
    update public.agent_ia_config
       set updated_by = null
     where updated_by = p_id;
  exception when others then null;
  end;

  begin
    delete from public.utilisateurs where id = p_id;
  exception
    when foreign_key_violation then
      raise exception
        'SUPPRESSION_BLOQUEE|Un historique bloque encore ce compte : exécutez d''abord la migration 174 (journal d''audit sans clé étrangère), puis réessayez.';
  end;

  -- Le compte de connexion (Auth). S'il résiste, le profil est déjà supprimé :
  -- le collaborateur ne peut plus rien voir, on le signale dans le retour.
  begin
    delete from auth.users where id = p_id;
    v_auth := true;
  exception when others then
    v_auth := false;
  end;

  begin
    insert into public.journal_audit (
      entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      null, 'COLLABORATEUR_SUPPRIME', v_user,
      jsonb_build_object(
        'collaborateur_id', p_id,
        'email', v_cible.email,
        'nom', v_cible.nom,
        'role', v_cible.new_role::text,
        'compte_auth_supprime', v_auth,
        'boutique', v_owner
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'id', p_id,
    'compte_auth_supprime', v_auth
  );
end;
$$;

comment on function public.rpc_collaborateur_supprimer(uuid, text) is
  '0176 — supprime un collaborateur (profil + compte Auth) : propriétaire uniquement, confirmation SUPPRIMER, jamais soi-même ni le propriétaire. Aucune donnée métier n''est effacée.';

revoke all on function public.rpc_collaborateur_supprimer(uuid, text)
  from public, anon;
grant execute on function public.rpc_collaborateur_supprimer(uuid, text)
  to authenticated;


-- ============================================================================
--  2. ALIAS HISTORIQUE — `delete_collaborateur(target_user_id)`
-- ============================================================================
--  Nom réellement appelé par l'application déjà installée. Il délègue à la
--  fonction ci-dessus (mêmes gardes, mêmes effets), et CONSERVE son nom
--  d'origine pour ne casser aucun client.
--
--  ⚠️ CORRECTIF DU 20/11 (erreur 42P13) : un `delete_collaborateur(uuid)`
--  EXISTE déjà dans la base, avec un AUTRE type de retour (créé hors dépôt).
--  `create or replace` refuse ce changement :
--      « cannot change return type of existing function
--        HINT: Use DROP FUNCTION delete_collaborateur(uuid) first. »
--  On supprime donc d'abord TOUTES les versions existantes de ce nom, puis on
--  recrée la nôtre (les droits sont réappliqués juste après).

do $$
declare
  v_signature text;
begin
  for v_signature in
    select format('public.%I(%s)',
                  p.proname,
                  pg_get_function_identity_arguments(p.oid))
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'delete_collaborateur'
  loop
    raise notice '0176 — suppression de l''ancienne fonction %', v_signature;
    execute 'drop function if exists ' || v_signature;
  end loop;
end $$;

create or replace function public.delete_collaborateur(target_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  -- Confirmation implicite : cet appel provient d'un écran qui a DÉJÀ demandé
  -- confirmation. Toutes les autres gardes (propriétaire, soi-même, équipe)
  -- restent appliquées par la fonction appelée.
  return public.rpc_collaborateur_supprimer(target_user_id, 'SUPPRIMER');
end;
$$;

comment on function public.delete_collaborateur(uuid) is
  '0176 — alias historique de rpc_collaborateur_supprimer (compatibilité des applications déjà installées).';

revoke all on function public.delete_collaborateur(uuid) from public, anon;
grant execute on function public.delete_collaborateur(uuid) to authenticated;


-- ============================================================================
--  3. VÉRIFICATIONS (lecture seule)
-- ============================================================================

-- 3.a Les deux fonctions existent (attendu : 2 lignes).
select p.proname,
       pg_get_function_identity_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('rpc_collaborateur_supprimer', 'delete_collaborateur')
 order by 1;

-- 3.b Le journal d'audit n'a plus de clé étrangère vers `utilisateurs`
--     (attendu : 0 ligne ; si une ligne sort, exécuter la migration 174).
select c.conname
  from pg_constraint c
  join pg_class r on r.oid = c.conrelid
  join pg_namespace n on n.oid = r.relnamespace
 where n.nspname = 'public'
   and r.relname = 'journal_audit'
   and c.contype = 'f';

-- 3.c Collaborateurs rattachés au propriétaire connecté (contrôle visuel).
select u.id, u.nom, u.email, u.new_role::text as role, u.valide
  from public.utilisateurs u
 where u.parent_id = public.mon_proprietaire()
 order by coalesce(u.nom, '');
