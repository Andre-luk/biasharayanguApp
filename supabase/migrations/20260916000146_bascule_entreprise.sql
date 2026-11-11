-- ============================================================================
--  biashara_yangu — MIGRATION 0146 : ROUTE B — BASCULER ENTRE ENTREPRISES
--
--  CE QUE FAIT CE SCRIPT
--    1. `rpc_espaces_lister()` : liste TOUTES les boutiques du patron, même
--       quand elles appartiennent à des entreprises différentes (Urembo
--       Market et Hekima Pharma apparaissent dans le même sélecteur).
--    2. `rpc_espace_basculer(p_espace_id)` : bascule d'un seul geste
--       l'ENTREPRISE et la BOUTIQUE (`utilisateurs.entreprise_id` +
--       `utilisateurs.espace_actif_id`). C'est ce qui fait suivre l'abonnement,
--       les modules, la devise et les données.
--    3. `rpc_espace_creer(...)` : ouvre une NOUVELLE ENTREPRISE (donc un
--       nouvel abonnement) avec sa première boutique, en essai de 7 jours et
--       SANS frais d'installation, puis bascule le patron dessus.
--
--  RÈGLES
--    • un patron ne voit et ne bascule que vers SES entreprises
--      (`entreprises.owner_id = mon_patron()`) ;
--    • un collaborateur ne peut pas basculer hors de son entreprise ;
--    • le quota du pack devient « nombre d'ENTREPRISES du patron »
--      (`groupes_tarifaires.max_espaces`) ;
--    • chaque entreprise garde son abonnement : deux boutiques = deux
--      échéances, deux montants.
--
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LISTER LES BOUTIQUES DU PATRON (toutes entreprises confondues)
-- ============================================================================

create or replace function public.rpc_espaces_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_patron  uuid;
  v_role    text := public.mon_role();
  v_max     integer := 1;
  v_nb_ent  integer := 0;
  v_actif   uuid;
  v_liste   jsonb := '[]'::jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour voir vos entreprises.';
  end if;

  v_patron := public.mon_patron();
  if v_patron is null then
    return jsonb_build_object(
      'espaces', '[]'::jsonb, 'actif_id', null, 'max_espaces', 1,
      'role', v_role, 'peut_creer', false, 'raison', 'aucune_entreprise');
  end if;

  -- Quota : nombre d'ENTREPRISES autorisées par le pack (le plus large des
  -- grilles utilisées par le patron).
  select greatest(coalesce(max(g.max_espaces), 1), 1) into v_max
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.owner_id = v_patron;

  select count(*) into v_nb_ent
    from public.entreprises e
   where e.owner_id = v_patron;

  -- Boutiques des entreprises du patron (une entreprise sans espace ne
  -- disparaît pas de son propre sélecteur).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',            s.id,
           'nom',           s.nom,
           'type',          s.type,
           'actif',         s.actif,
           'est_actif',     s.id = u_actif.espace_actif_id,
           'entreprise_id',   e.id,
           'entreprise_nom',  e.nom,
           'etat_abonnement', e.statut::text,
           'date_expiration', e.date_expiration,
           'created_at',    s.created_at
         ) order by e.created_at nulls first, s.created_at, s.nom), '[]'::jsonb)
    into v_liste
    from public.entreprises e
    join public.espaces s on s.entreprise_id = e.id
    cross join (select u2.espace_actif_id from public.utilisateurs u2
                 where u2.id = v_user) u_actif
   where e.owner_id = v_patron;

  -- Espace actif effectif (repli : celui du patron, puis le premier).
  select u.espace_actif_id into v_actif
    from public.utilisateurs u
   where u.id = v_user
     and u.espace_actif_id is not null
     and exists (select 1 from public.espaces s
                  where s.id = u.espace_actif_id and s.actif);

  if v_actif is null then
    v_actif := public.mon_proprietaire();
  end if;

  return jsonb_build_object(
    'espaces',     v_liste,
    'actif_id',    v_actif,
    'max_espaces', v_max,
    'nb_entreprises', v_nb_ent,
    'role',        v_role,
    'peut_creer',  (v_role = 'PROPRIETAIRE' and v_nb_ent < v_max),
    'raison',      case
                     when v_role <> 'PROPRIETAIRE' then 'role'
                     when v_nb_ent >= v_max then 'quota'
                     else null
                   end
  );
end;
$$;

comment on function public.rpc_espaces_lister() is
  'Route B (0146) — boutiques de TOUTES les entreprises du patron, avec l''entreprise et l''état de son abonnement.';


-- ============================================================================
--  2. BASCULER ENTREPRISE + BOUTIQUE D'UN SEUL GESTE
-- ============================================================================

create or replace function public.rpc_espace_basculer(
  p_espace_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_patron uuid;
  v_espace public.espaces%rowtype;
  v_ent    public.entreprises%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour changer d''entreprise.';
  end if;

  if p_espace_id is null then
    raise exception 'ESPACE_INVALIDE|Aucune boutique choisie.';
  end if;

  select * into v_espace from public.espaces where id = p_espace_id;
  if not found then
    raise exception 'ESPACE_INTROUVABLE|Cette boutique n''existe pas.';
  end if;

  select * into v_ent from public.entreprises where id = v_espace.entreprise_id;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Entreprise de cette boutique introuvable.';
  end if;

  v_patron := public.mon_patron();

  -- Droit de bascule :
  --   • la plateforme : tout ;
  --   • le PATRON : uniquement vers une entreprise qui lui appartient ;
  --   • un COLLABORATEUR : uniquement une boutique de SON entreprise
  --     (jamais dans l'autre affaire du patron).
  if not public.est_plateforme() then
    if v_user = v_patron then
      if v_ent.owner_id is distinct from v_patron then
        raise exception 'DROIT_REFUSE|Cette entreprise n''appartient pas à votre compte.';
      end if;
    else
      if v_espace.entreprise_id is distinct from
         (select u.entreprise_id from public.utilisateurs u where u.id = v_user) then
        raise exception 'DROIT_REFUSE|Cette boutique ne dépend pas de votre entreprise.';
      end if;
    end if;
  end if;

  update public.utilisateurs
     set espace_actif_id = p_espace_id,
         entreprise_id   = v_espace.entreprise_id
   where id = v_user;

  -- Trace (best-effort).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (null, 'BASCULE_ENTREPRISE', v_user,
            jsonb_build_object('entreprise_id', v_espace.entreprise_id,
                               'entreprise', v_ent.nom,
                               'espace_id', p_espace_id,
                               'boutique', v_espace.nom));
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok',              true,
    'espace_id',       p_espace_id,
    'nom',             v_espace.nom,
    'entreprise_id',   v_espace.entreprise_id,
    'entreprise_nom',  v_ent.nom,
    'etat_abonnement', v_ent.statut::text,
    'date_expiration', v_ent.date_expiration
  );
end;
$$;

comment on function public.rpc_espace_basculer(uuid) is
  'Route B (0146) — bascule l''entreprise ET la boutique de travail (abonnement, modules, devise et données suivent).';


-- ============================================================================
--  3. OUVRIR UNE NOUVELLE ENTREPRISE (donc un nouvel abonnement)
-- ============================================================================
--    • essai de 7 jours, frais d'installation offerts ;
--    • la boutique de départ porte le nom demandé et le type choisi ;
--    • le patron bascule immédiatement dessus.

create or replace function public.rpc_espace_creer(
  p_nom                      text,
  p_type                     text default 'boutique',
  p_ville_id                 uuid default null,
  p_jours_essai              integer default 7,
  p_frais_installation_offert boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_patron  uuid;
  v_role    text := public.mon_role();
  v_nom     text;
  v_type    text;
  v_max     integer := 1;
  v_nb      integer := 0;
  v_new_ent uuid;
  v_new_esp uuid;
  v_grille  uuid;
  v_essai   integer := greatest(coalesce(p_jours_essai, 7), 0);
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer une entreprise.';
  end if;

  if v_role <> 'PROPRIETAIRE' then
    raise exception 'DROIT_REFUSE|Seul le propriétaire du compte peut créer une entreprise.';
  end if;

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null or length(v_nom) < 2 then
    raise exception 'NOM_REQUIS|Donnez un nom à votre entreprise (2 caractères minimum).';
  end if;

  v_patron := public.mon_patron();

  -- Type validé par le référentiel (repli « autre » puis « boutique »).
  v_type := lower(btrim(coalesce(p_type, 'boutique')));
  if not exists (select 1 from public.types_espaces_modules t
                  where t.type = v_type and t.actif) then
    v_type := 'autre';
    if not exists (select 1 from public.types_espaces_modules t
                    where t.type = v_type and t.actif) then
      v_type := 'boutique';
    end if;
  end if;

  -- Quota : nombre d'ENTREPRISES du patron.
  select greatest(coalesce(max(g.max_espaces), 1), 1) into v_max
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.owner_id = v_patron;

  select count(*) into v_nb from public.entreprises e where e.owner_id = v_patron;

  if v_nb >= v_max then
    raise exception 'QUOTA_ENTREPRISES|Votre pack autorise % entreprise(s) au maximum. Passez au pack avancé pour en ajouter.',
      v_max;
  end if;

  -- Grille tarifaire du patron (celle de son entreprise la plus ancienne).
  select e.groupe_tarifaire_id into v_grille
    from public.entreprises e
   where e.owner_id = v_patron
   order by e.created_at nulls first
   limit 1;

  -- 1) L'ENTREPRISE (elle porte l'abonnement).
  insert into public.entreprises (nom, owner_id)
  values (v_nom, v_patron)
  returning id into v_new_ent;

  update public.entreprises
     set statut            = 'ESSAI_7J'::public.statut_abonnement_enum,
         date_activation   = now(),
         date_expiration   = now() + make_interval(days => v_essai),
         prix_installation = case when p_frais_installation_offert then 0
                                  else prix_installation end,
         groupe_tarifaire_id = coalesce(groupe_tarifaire_id, v_grille),
         updated_at        = now()
   where id = v_new_ent;

  -- 2) La BOUTIQUE de départ (identifiant libre : l'UUID du patron est déjà
  --    pris par la première entreprise).
  insert into public.espaces (entreprise_id, nom, type, ville_id, actif)
  values (v_new_ent, v_nom, v_type, p_ville_id, true)
  returning id into v_new_esp;

  -- 3) Basculer le patron sur sa nouvelle entreprise.
  update public.utilisateurs
     set entreprise_id   = v_new_ent,
         espace_actif_id = v_new_esp,
         new_role        = coalesce(new_role, public.role_enum('PROPRIETAIRE'))
   where id = v_user;

  -- 4) Le montant dû de la nouvelle entreprise (base + ses collaborateurs).
  update public.entreprises
     set montant_total_du = public.abonnement_prix_base(v_new_ent)
                            + public.abonnement_supplement_collaborateurs(v_new_ent)
   where id = v_new_ent;

  -- Trace.
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (null, 'CREATION_ENTREPRISE', v_user,
            jsonb_build_object('entreprise_id', v_new_ent, 'nom', v_nom,
                               'type', v_type, 'espace_id', v_new_esp,
                               'essai_jours', v_essai,
                               'installation_offerte', p_frais_installation_offert));
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok',                    true,
    'entreprise_id',         v_new_ent,
    'espace_id',             v_new_esp,
    'nom',                   v_nom,
    'type',                  v_type,
    'essai_jours',           v_essai,
    'installation_offerte',  p_frais_installation_offert,
    'montant_mensuel',       public.abonnement_prix_base(v_new_ent)
                             + public.abonnement_supplement_collaborateurs(v_new_ent),
    'date_expiration',       (select date_expiration from public.entreprises where id = v_new_ent)
  );
end;
$$;

comment on function public.rpc_espace_creer(text, text, uuid, integer, boolean) is
  'Route B (0146) — ouvre une NOUVELLE ENTREPRISE (abonnement distinct) avec sa première boutique, en essai et sans frais d''installation, puis bascule le patron dessus.';


-- ============================================================================
--  4. DROITS
-- ============================================================================

revoke all on function public.rpc_espaces_lister() from public, anon;
grant execute on function public.rpc_espaces_lister() to authenticated;

revoke all on function public.rpc_espace_basculer(uuid) from public, anon;
grant execute on function public.rpc_espace_basculer(uuid) to authenticated;

revoke all on function public.rpc_espace_creer(text, text, uuid, integer, boolean) from public, anon;
grant execute on function public.rpc_espace_creer(text, text, uuid, integer, boolean) to authenticated;


-- ============================================================================
--  5. CONTRÔLE
-- ============================================================================

select 'ROUTE B PRÊTE' as controle,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname = 'mon_patron')
         as helper_patron_ok,
       exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'entreprises'
                  and column_name = 'owner_id')
         as owner_id_ok,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where n.nspname = 'public' and p.proname = 'rpc_espace_creer'
                  and pg_get_function_identity_arguments(p.oid) like '%integer%')
         as creation_avec_essai_ok;

-- Patrons à plusieurs entreprises, avec la facture de chacune.
select p.nom as patron,
       p.email,
       e.nom as entreprise,
       e.statut,
       to_char(e.date_expiration, 'DD/MM/YYYY') as echeance,
       public.abonnement_prix_base(e.id)
         + public.abonnement_supplement_collaborateurs(e.id) as montant_mensuel
  from public.entreprises e
  join public.utilisateurs p on p.id = e.owner_id
 where e.owner_id in (
         select owner_id from public.entreprises
          where owner_id is not null
          group by owner_id having count(*) > 1)
 order by p.nom, e.nom;
