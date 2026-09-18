-- ============================================================================
--  biashara_yangu — MODULE 15 : PACK AVANCÉ MULTI-ENTREPRISES
--
--  OBJECTIF
--  ─────────────────────────────────────────────────────────────────────────
--  Un même compte client (patron) peut gérer PLUSIEURS entreprises :
--  boutique + hôtel + pharmacie… et basculer de l'une à l'autre :
--
--    • le SÉLECTEUR d'entreprise change l'espace de travail actif ;
--    • toutes les données (ventes, stock, clients, finances, IA…) sont
--      cloisonnées par ESPACE — rien ne se mélange ;
--    • chaque espace a son propre nom et son type (boutique, hôtel…).
--
--  FILET DE SÉCURITÉ (architecture)
--  ─────────────────────────────────────────────────────────────────────────
--  Aujourd'hui, `mon_proprietaire()` = UUID du patron, et c'est CETTE valeur
--  qui estampille toutes les tables métier. Pour ne RIEN réécrire :
--
--    1. chaque entreprise existante reçoit un « espace par défaut » dont
--       l'identifiant EST l'UUID du patron (les données existantes restent
--       donc valides telles quelles) ;
--    2. `mon_proprietaire()` est redéfini : il renvoie l'ESPACE ACTIF de
--       l'utilisateur s'il est valide, SINON le repli historique exact
--       (coalesce(parent_id, id)) — comportement inchangé si aucun
--       basculement n'a eu lieu.
--
--  PACK AVANCÉ
--  ─────────────────────────────────────────────────────────────────────────
--  Le nombre d'entreprises autorisées vient de la grille tarifaire :
--  `groupes_tarifaires.max_espaces` (1 par défaut = mono-entreprise).
--  Créez un groupe « Pack Avancé » avec max_espaces = 3 (ou plus) dans
--  l'écran « Groupes tarifaires », puis affectez-le aux clients concernés.
--
--  OÙ L'EXÉCUTER : Supabase → SQL Editor → coller → Run
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. GRILLES TARIFAIRES — DROIT AU MULTI-ENTREPRISES
-- ============================================================================

alter table public.groupes_tarifaires
  add column if not exists max_espaces integer not null default 1;

do $$
begin
  alter table public.groupes_tarifaires
    drop constraint if exists chk_groupes_tarifaires_max_espaces;
  alter table public.groupes_tarifaires
    add constraint chk_groupes_tarifaires_max_espaces
    check (max_espaces between 1 and 20);
end $$;

comment on column public.groupes_tarifaires.max_espaces is
  'Module 15 — Nombre d''entreprises autorisées par ce pack (1 = mono-entreprise, 3 = pack avancé…).';


-- ============================================================================
--  2. TABLE `espaces` — LES ENTREPRISES DU COMPTE
-- ============================================================================

create table if not exists public.espaces (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null
    references public.entreprises(id) on delete cascade,
  nom           text not null,
  type          text not null default 'boutique'
    check (type in ('boutique', 'hotel', 'pharmacie', 'restaurant', 'depot', 'autre')),
  ville_id      uuid references public.villes(id),
  actif         boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.espaces is
  'Module 15 — Entreprises (points de vente) d''un compte client : boutique, hôtel, pharmacie… Les données métier sont cloisonnées par espace (l''espace par défaut porte l''UUID du patron pour la compatibilité).';

create index if not exists idx_espaces_entreprise
  on public.espaces (entreprise_id, created_at);

alter table public.espaces enable row level security;

drop policy if exists m15_espaces_lecture on public.espaces;
create policy m15_espaces_lecture on public.espaces
  for select to authenticated
  using (
    public.est_plateforme()
    or entreprise_id = (
      select u.entreprise_id from public.utilisateurs u where u.id = auth.uid()
    )
  );

revoke all on public.espaces from public;
revoke all on public.espaces from anon;
revoke insert, update, delete, truncate on public.espaces from authenticated;
grant select on public.espaces to authenticated;


-- ============================================================================
--  3. UTILISATEURS — ESPACE DE TRAVAIL ACTIF
-- ============================================================================

alter table public.utilisateurs
  add column if not exists espace_actif_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'utilisateurs_espace_actif_id_fkey'
  ) then
    alter table public.utilisateurs
      add constraint utilisateurs_espace_actif_id_fkey
      foreign key (espace_actif_id) references public.espaces(id) on delete set null;
  end if;
end $$;

create index if not exists idx_utilisateurs_espace_actif
  on public.utilisateurs (espace_actif_id);

comment on column public.utilisateurs.espace_actif_id is
  'Module 15 — Entreprise (espace) actuellement sélectionnée : toutes les données affichées et créées appartiennent à cet espace.';


-- ============================================================================
--  4. BACKFILL — ESPACE PAR DÉFAUT DE CHAQUE ENTREPRISE EXISTANTE
-- ============================================================================
--  L'identifiant de l'espace par défaut = UUID du patron : c'est déjà la
--  valeur stockée dans toutes les tables métier → AUCUNE donnée à réécrire.

insert into public.espaces (id, entreprise_id, nom, type, actif)
select u.id, e.id,
       coalesce(nullif(btrim(e.nom), ''), 'Boutique principale'),
       'boutique', true
  from public.entreprises e
  join lateral (
    select us.id
      from public.utilisateurs us
     where us.entreprise_id = e.id and us.parent_id is null
     order by us.created_at
     limit 1
  ) u on true
 where not exists (select 1 from public.espaces s where s.id = u.id)
   and exists (select 1 from public.utilisateurs us2 where us2.id = u.id);

-- Espace actif par défaut de chaque utilisateur (patron : lui-même ;
-- collaborateur : son patron).
update public.utilisateurs u
   set espace_actif_id = coalesce(u.parent_id, u.id)
 where u.espace_actif_id is null
   and exists (
     select 1 from public.espaces s where s.id = coalesce(u.parent_id, u.id)
   );


-- ============================================================================
--  5. `mon_proprietaire()` — LE CŒUR DU CLOISONNEMENT
-- ============================================================================
--  Renvoie l'espace de travail actif s'il est encore valide (même entreprise,
--  actif), sinon le repli historique exact — ainsi le comportement est
--  STRICTEMENT identique à avant pour ceux qui n'utilisent pas le sélecteur.

create or replace function public.mon_proprietaire()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- 1. L'espace actif choisi (module 15), s'il est valide.
    (select u.espace_actif_id
       from public.utilisateurs u
      where u.id = auth.uid()
        and u.espace_actif_id is not null
        and exists (
          select 1 from public.espaces s
           where s.id = u.espace_actif_id
             and s.actif
             and s.entreprise_id = u.entreprise_id
        )),
    -- 2. Repli historique : l'UUID du patron (inchangé).
    (select coalesce(u.parent_id, u.id)
       from public.utilisateurs u
      where u.id = auth.uid())
  );
$$;

comment on function public.mon_proprietaire() is
  'Module 15 — Espace de travail actif de l''utilisateur (entreprise sélectionnée), sinon repli historique sur l''UUID du patron.';


-- ============================================================================
--  6. `rpc_entreprise_creer` v4 — CRÉE AUSSI L'ESPACE PAR DÉFAUT
-- ============================================================================

create or replace function public.rpc_entreprise_creer(
  p_nom text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_exist uuid;
  v_nomu  text;
  v_nom   text;
  v_new   uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  -- Déjà rattaché ? On ne duplique pas.
  select u.entreprise_id into v_exist
    from public.utilisateurs u
   where u.id = v_user;

  if v_exist is not null then
    return jsonb_build_object('ok', true, 'deja', true, 'entreprise_id', v_exist);
  end if;

  select coalesce(nullif(btrim(u.nom), ''), u.email) into v_nomu
    from public.utilisateurs u
   where u.id = v_user;

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null then
    v_nom := 'Boutique ' || coalesce(v_nomu, 'nouvelle');
  end if;

  insert into public.entreprises (nom)
  values (v_nom)
  returning id into v_new;

  -- Module 15 — espace par défaut (identifiant = UUID du patron).
  insert into public.espaces (id, entreprise_id, nom, type, actif)
  values (v_user, v_new, v_nom, 'boutique', true)
  on conflict (id) do nothing;

  update public.utilisateurs
     set entreprise_id    = v_new,
         espace_actif_id  = v_user
   where id = v_user;

  -- 🛡️ MODULE 14 — double validation obligatoire : le compte n'est PAS
  -- opérationnel tant que le gestionnaire puis la finance n'ont pas validé.
  -- `EN_ATTENTE_COMPLEMENT` = lecture seule (moteur Module 3).
  update public.entreprises
     set activation_etape = 'en_attente_verification',
         statut = 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum,
         updated_at = now()
   where id = v_new;

  insert into public.activations_entreprise (
    entreprise_id, etape, acteur_id, acteur_role, note
  ) values (
    v_new, 'soumission', v_user, public.mon_role(), 'Création du compte'
  );

  -- Trace (best-effort : ne doit jamais faire échouer la création).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'CREATION_ENTREPRISE', v_user,
      jsonb_build_object(
        'entreprise_id', v_new, 'nom', v_nom,
        'activation_etape', 'en_attente_verification'
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'deja', false,
                            'entreprise_id', v_new, 'nom', v_nom,
                            'activation_etape', 'en_attente_verification');
end;
$$;

comment on function public.rpc_entreprise_creer(text) is
  'Module 14/15 — Crée l''entreprise (EN ATTENTE DE VÉRIFICATION) + son espace de travail par défaut.';

revoke all on function public.rpc_entreprise_creer(text) from public;
revoke all on function public.rpc_entreprise_creer(text) from anon;
grant execute on function public.rpc_entreprise_creer(text) to authenticated;


-- ============================================================================
--  7. RPC DU MODULE 15
-- ============================================================================

-- 7.a LISTER LES ENTREPRISES DU COMPTE (sélecteur + écran « Mes entreprises »)
create or replace function public.rpc_espaces_lister()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_role  text := public.mon_role();
  v_ent   uuid;
  v_max   integer := 1;
  v_nb    integer := 0;
  v_actif uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour voir vos entreprises.';
  end if;

  select u.entreprise_id into v_ent
    from public.utilisateurs u
   where u.id = v_user;

  if v_ent is null then
    return jsonb_build_object(
      'espaces', '[]'::jsonb,
      'actif_id', null,
      'max_espaces', 1,
      'role', v_role,
      'peut_creer', false,
      'raison', 'aucune_entreprise'
    );
  end if;

  -- Droit au multi-entreprises (pack avancé de la grille tarifaire).
  select coalesce(g.max_espaces, 1) into v_max
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.id = v_ent;
  v_max := coalesce(v_max, 1);

  select count(*) into v_nb
    from public.espaces s
   where s.entreprise_id = v_ent;

  -- Espace actif effectif (gère automatiquement les replis).
  v_actif := public.mon_proprietaire();

  return jsonb_build_object(
    'espaces', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', s.id,
               'nom', s.nom,
               'type', s.type,
               'actif', s.actif,
               'est_actif', s.id = v_actif,
               'created_at', s.created_at
             ) order by s.created_at, s.nom)
        from public.espaces s
       where s.entreprise_id = v_ent
    ), '[]'::jsonb),
    'actif_id', v_actif,
    'max_espaces', v_max,
    'role', v_role,
    'peut_creer', (v_role = 'PROPRIETAIRE' and v_nb < v_max),
    'raison', case
                when v_role <> 'PROPRIETAIRE' then 'role'
                when v_nb >= v_max then 'quota'
                else null
              end
  );
end;
$$;

comment on function public.rpc_espaces_lister() is
  'Module 15 — Entreprises du compte (nom, type, espace actif) + droit de création selon le pack.';

revoke all on function public.rpc_espaces_lister() from public;
revoke all on function public.rpc_espaces_lister() from anon;
grant execute on function public.rpc_espaces_lister() to authenticated;


-- 7.b BASCULER VERS UNE AUTRE ENTREPRISE (sélecteur)
create or replace function public.rpc_espace_basculer(
  p_espace_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_ent  uuid;
  v_nom  text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour changer d''entreprise.';
  end if;

  select u.entreprise_id into v_ent
    from public.utilisateurs u
   where u.id = v_user;

  if v_ent is null then
    raise exception 'AUCUNE_ENTREPRISE|Votre compte n''est rattaché à aucune entreprise.';
  end if;

  select s.nom into v_nom
    from public.espaces s
   where s.id = p_espace_id
     and s.entreprise_id = v_ent
     and s.actif;

  if v_nom is null then
    raise exception 'ESPACE_INTROUVABLE|Cette entreprise n''existe pas ou n''est plus active.';
  end if;

  update public.utilisateurs
     set espace_actif_id = p_espace_id
   where id = v_user;

  -- Trace (best-effort).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'ESPACE_BASCULE', v_user,
      jsonb_build_object('espace_id', p_espace_id, 'nom', v_nom)
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'espace_id', p_espace_id, 'nom', v_nom);
end;
$$;

comment on function public.rpc_espace_basculer(uuid) is
  'Module 15 — Change l''entreprise active : toutes les données suivent le nouvel espace.';

revoke all on function public.rpc_espace_basculer(uuid) from public;
revoke all on function public.rpc_espace_basculer(uuid) from anon;
grant execute on function public.rpc_espace_basculer(uuid) to authenticated;


-- 7.c CRÉER UNE ENTREPRISE SUPPLÉMENTAIRE (pack avancé, PROPRIÉTAIRE)
create or replace function public.rpc_espace_creer(
  p_nom      text,
  p_type     text default 'boutique',
  p_ville_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_role text := public.mon_role();
  v_ent  uuid;
  v_max  integer := 1;
  v_nb   integer := 0;
  v_nom  text;
  v_type text;
  v_new  uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer une entreprise.';
  end if;

  if v_role <> 'PROPRIETAIRE' then
    raise exception 'DROIT_REFUSE|Seul le propriétaire du compte peut créer une entreprise supplémentaire.';
  end if;

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null or length(v_nom) < 2 then
    raise exception 'NOM_REQUIS|Donnez un nom à votre entreprise (2 caractères minimum).';
  end if;

  v_type := lower(btrim(coalesce(p_type, 'boutique')));
  if v_type not in ('boutique', 'hotel', 'pharmacie', 'restaurant', 'depot', 'autre') then
    v_type := 'autre';
  end if;

  select u.entreprise_id into v_ent
    from public.utilisateurs u
   where u.id = v_user;

  if v_ent is null then
    raise exception 'AUCUNE_ENTREPRISE|Créez d''abord votre entreprise principale.';
  end if;

  -- Pack : nombre d'entreprises autorisées par la grille tarifaire.
  select coalesce(g.max_espaces, 1) into v_max
    from public.entreprises e
    left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
   where e.id = v_ent;
  v_max := coalesce(v_max, 1);

  select count(*) into v_nb
    from public.espaces s
   where s.entreprise_id = v_ent;

  if v_nb >= v_max then
    raise exception 'QUOTA_ESPACES|Votre pack autorise % entreprise(s) au maximum. Passez au pack multi-entreprises pour en ajouter.', v_max;
  end if;

  insert into public.espaces (entreprise_id, nom, type, ville_id)
  values (v_ent, v_nom, v_type, p_ville_id)
  returning id into v_new;

  -- Trace (best-effort).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'ESPACE_CREE', v_user,
      jsonb_build_object('espace_id', v_new, 'nom', v_nom, 'type', v_type)
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true, 'espace_id', v_new, 'nom', v_nom, 'type', v_type,
    'nb_espaces', v_nb + 1, 'max_espaces', v_max
  );
end;
$$;

comment on function public.rpc_espace_creer(text, text, uuid) is
  'Module 15 — Crée une entreprise supplémentaire (pack multi-entreprises, propriétaire uniquement).';

revoke all on function public.rpc_espace_creer(text, text, uuid) from public;
revoke all on function public.rpc_espace_creer(text, text, uuid) from anon;
grant execute on function public.rpc_espace_creer(text, text, uuid) to authenticated;


-- ============================================================================
--  8. VÉRIFICATIONS
-- ============================================================================

-- 8.a Espaces créés (une ligne par entreprise, l'espace par défaut = patron).
select s.nom as entreprise, s.type, s.actif,
       (select count(*) from public.espaces s2 where s2.entreprise_id = s.entreprise_id) as nb_espaces,
       (select g.max_espaces from public.entreprises e
          left join public.groupes_tarifaires g on g.id = e.groupe_tarifaire_id
         where e.id = s.entreprise_id) as max_espaces
  from public.espaces s
 order by s.created_at
 limit 20;

-- 8.b Utilisateurs sans espace actif (ne devrait rien renvoyer).
select u.email, u.entreprise_id
  from public.utilisateurs u
 where u.entreprise_id is not null
   and u.espace_actif_id is null;

-- 8.c Compatibilité : à ce stade, mon_proprietaire() doit renvoyer
--     exactement l'UUID du patron pour chaque utilisateur (repli).
select u.email,
       public.mon_proprietaire() as espace_actif,
       coalesce(u.parent_id, u.id) as attendu
  from public.utilisateurs u
 where u.entreprise_id is not null
 order by u.created_at desc
 limit 10;
