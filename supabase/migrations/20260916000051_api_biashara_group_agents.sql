-- ============================================================================
--  MODULE 21 quinquies — API « Biashara Group » (suivi des agents terrain)
--  Migration 20260916000051_api_biashara_group_agents.sql
-- ============================================================================
--
--  À exécuter APRÈS les migrations 47, 48, 49 et 50. IDEMPOTENTE.
--
--  À QUOI ÇA SERT
--  --------------
--  La plateforme d'administration de Biashara Group (biasharagroup.com/admin)
--  doit suivre ses agents terrain : activité, dossiers, boutiques, QR codes,
--  encaissements, journal complet — et pouvoir désactiver un compte.
--
--  Ces lectures passent par l'Edge Function `admin-agents` (voir
--  `supabase/functions/admin-agents/index.ts`), qui détient la clé
--  `service_role` et vérifie un jeton de service Biashara Group.
--
--  ⚠️ POURQUOI DES RPC « bg_ » SÉPARÉES
--  -----------------------------------
--  Une Edge Function appelée avec la clé `service_role` n'a PAS de session
--  utilisateur : `auth.uid()` est NULL et `mon_role()` vaut NULL. Les RPC
--  « rpc_agent_* » (qui exigent un rôle plateforme) la REFUSERAIENT donc.
--
--  D'où ces fonctions dédiées :
--    • aucune vérification de rôle interne (le contrôle se fait dans l'Edge
--      Function, qui possède le jeton) ;
--    • `execute` RÉVOQUÉ pour `public`, `anon` et `authenticated`, ACCORDÉ
--      uniquement à `service_role`. Elles sont donc INACCESSIBLES depuis
--      l'application Flutter : seul le serveur (Edge Function) peut les appeler.
--
--  Ce qui est exposé reste STRICTEMENT l'activité de l'agent : jamais les
--  ventes, le stock, les dépenses ou les clients des commerçants.
-- ============================================================================


-- ============================================================================
--  1. CALCUL DE LA FICHE — FACTORISÉ ET RÉUTILISABLE
-- ============================================================================
--  Le corps du calcul est extrait dans une fonction interne SANS contrôle
--  d'accès. Elle est appelée :
--    • par `rpc_agent_fiche` (contrôles de rôle : agent = la sienne,
--      personnel plateforme = tout agent) ;
--    • par `rpc_bg_agent_fiche` (service_role, pour Biashara Group).
--  Une seule source de vérité : les compteurs ne peuvent pas diverger.

create or replace function public.bg_agent_fiche_calcul(p_agent_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_agent    uuid := p_agent_id;
  v_prof     public.utilisateurs;
  v_nb_users integer := 0;
  v_nb_ent   integer := 0;
  v_nb_esp   integer := 0;
  v_nb_prod  integer := 0;
  v_nb_cond  integer := 0;
  v_nb_pub   integer := 0;
  v_nb_act   integer := 0;
  v_nb_att   integer := 0;
  v_encaisse numeric := 0;
  v_solde    numeric := 0;
  v_ent      jsonb := '[]'::jsonb;
  v_users    jsonb := '[]'::jsonb;
  v_journal  jsonb := '[]'::jsonb;
begin
  if v_agent is null then
    return jsonb_build_object('ok', false, 'erreur', 'AGENT_ID_MANQUANT');
  end if;

  select * into v_prof from public.utilisateurs u where u.id = v_agent;

  select count(*) into v_nb_users
    from public.utilisateurs u where u.agent_id = v_agent;

  select count(*),
         count(*) filter (where e.activation_etape = 'actif'),
         count(*) filter (where e.activation_etape in ('en_attente_verification', 'verifie')),
         coalesce(sum(coalesce(e.solde_restant, 0)), 0)
    into v_nb_ent, v_nb_act, v_nb_att, v_solde
    from public.entreprises e where e.agent_id = v_agent;

  select count(*) into v_nb_esp
    from public.espaces s
    join public.entreprises e on e.id = s.entreprise_id
   where e.agent_id = v_agent;

  select count(*) into v_nb_prod
    from public.produits p
   where p.owner_id in (
     select u.id from public.utilisateurs u
      join public.entreprises e on e.id = u.entreprise_id
     where e.agent_id = v_agent);

  select count(*) into v_nb_cond
    from public.conditionnements c
   where c.produit_id in (
     select p.id from public.produits p
      where p.owner_id in (
        select u.id from public.utilisateurs u
         join public.entreprises e on e.id = u.entreprise_id
        where e.agent_id = v_agent));

  select count(*) into v_nb_pub
    from public.produits_publications pb
   where pb.publie
     and pb.espace_id in (
       select s.id from public.espaces s
        join public.entreprises e on e.id = s.entreprise_id
       where e.agent_id = v_agent);

  -- Revenus : ce que SES abonnements ont généré (paiements validés en finance).
  begin
    select coalesce(sum(a.montant), 0) into v_encaisse
      from public.activations_entreprise a
     where a.etape = 'paiement_finance'
       and a.montant is not null
       and a.entreprise_id in (
         select e.id from public.entreprises e where e.agent_id = v_agent);
  exception when others then v_encaisse := 0;
  end;

  select coalesce(jsonb_agg(jsonb_build_object(
           'entreprise_id', e.id,
           'nom', e.nom,
           'statut', e.statut::text,
           'activation_etape', coalesce(e.activation_etape, 'actif'),
           'solde_restant', coalesce(e.solde_restant, 0),
           'montant_total_du', e.montant_total_du,
           'montant_deja_paye', e.montant_deja_paye,
           'date_expiration', e.date_expiration,
           'created_at', e.created_at
         ) order by e.created_at desc), '[]'::jsonb)
    into v_ent
    from public.entreprises e where e.agent_id = v_agent;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', u.id,
           'nom', u.nom,
           'email', u.email,
           'telephone', to_jsonb(u) ->> 'telephone',
           'role', coalesce(u.new_role::text, u.role),
           'created_at', u.created_at
         ) order by u.created_at desc), '[]'::jsonb)
    into v_users
    from public.utilisateurs u where u.agent_id = v_agent;

  begin
    select coalesce(jsonb_agg(jsonb_build_object(
             'action', j.action,
             'created_at', j.created_at,
             'niveau', j.niveau,
             'details', j.details
           ) order by j.created_at desc), '[]'::jsonb)
      into v_journal
      from (
        select a.action, a.created_at, to_jsonb(a) ->> 'niveau' as niveau, a.details
          from public.journal_audit a
         where a.utilisateur_id = v_agent
         order by a.created_at desc
         limit 20
      ) j;
  exception when others then v_journal := '[]'::jsonb;
  end;

  return jsonb_build_object(
    'ok', true,
    'agent_id', v_agent,
    'nom', coalesce(v_prof.nom, ''),
    'email', coalesce(v_prof.email, ''),
    'telephone', to_jsonb(v_prof) ->> 'telephone',
    'valide', coalesce(v_prof.valide, 0),
    'role', coalesce(v_prof.new_role::text, v_prof.role),
    'nb_utilisateurs', v_nb_users,
    'nb_entreprises', v_nb_ent,
    'nb_boutiques', v_nb_esp,
    'nb_abonnements_actifs', v_nb_act,
    'nb_en_attente', v_nb_att,
    'nb_produits', v_nb_prod,
    'nb_conditionnements', v_nb_cond,
    'nb_qr_codes', v_nb_prod + v_nb_cond,
    'nb_produits_publies', v_nb_pub,
    'montant_encaisse', v_encaisse,
    'solde_du', v_solde,
    'entreprises', v_ent,
    'utilisateurs', v_users,
    'journal', v_journal
  );
end;
$$;

comment on function public.bg_agent_fiche_calcul(uuid) is
  'Module 21 quinquies — Calcul de la fiche d''un agent terrain (aucun contrôle d''accès : usage interne / service_role). Source unique appelée par rpc_agent_fiche et rpc_bg_agent_fiche.';

revoke all on function public.bg_agent_fiche_calcul(uuid) from public, anon, authenticated;
grant execute on function public.bg_agent_fiche_calcul(uuid) to service_role;


-- ============================================================================
--  2. `rpc_agent_fiche` DEVIENT UN SIMPLE CONTRÔLE + DÉLÉGATION
-- ============================================================================
--  Comportement inchangé pour l'application : un agent ne lit que la sienne,
--  le personnel plateforme lit celle de n'importe quel agent.

create or replace function public.rpc_agent_fiche(p_agent_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_moi   uuid := auth.uid();
  v_agent uuid := coalesce(p_agent_id, auth.uid());
begin
  if v_moi is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not public.est_plateforme() and not public.est_agent_terrain() then
    raise exception 'DROIT_REFUSE|Réservé au personnel plateforme ou à un agent terrain.';
  end if;

  if public.est_agent_terrain() and v_agent <> v_moi then
    raise exception 'DROIT_REFUSE|Un agent ne consulte que sa propre fiche.';
  end if;

  return public.bg_agent_fiche_calcul(v_agent);
end;
$$;

comment on function public.rpc_agent_fiche(uuid) is
  'Module 21 ter — Fiche d''activité d''un agent terrain. Un agent ne voit que la sienne ; la plateforme voit celle de tout agent.';

revoke all on function public.rpc_agent_fiche(uuid) from public, anon;
grant execute on function public.rpc_agent_fiche(uuid) to authenticated;


-- ============================================================================
--  3. API BIASHARA GROUP — RÉSERVÉE AU service_role
-- ============================================================================

--  3.a Fiche complète d'un agent (pour Biashara Group).
create or replace function public.rpc_bg_agent_fiche(p_agent_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select public.bg_agent_fiche_calcul(p_agent_id);
$$;

comment on function public.rpc_bg_agent_fiche(uuid) is
  'Module 21 quinquies — Fiche d''un agent terrain pour la plateforme Biashara Group (service_role uniquement).';

revoke all on function public.rpc_bg_agent_fiche(uuid) from public, anon, authenticated;
grant execute on function public.rpc_bg_agent_fiche(uuid) to service_role;


--  3.b Liste des agents terrain + compteurs.
create or replace function public.rpc_bg_agents_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return coalesce((
    select jsonb_agg(s.t order by s.created_at desc)
      from (
        select jsonb_build_object(
                 'agent_id', u.id,
                 'nom', u.nom,
                 'email', u.email,
                 'telephone', to_jsonb(u) ->> 'telephone',
                 'valide', coalesce(u.valide, 0),
                 'created_at', u.created_at,
                 'nb_entreprises', (
                   select count(*) from public.entreprises e where e.agent_id = u.id),
                 'nb_boutiques', (
                   select count(*) from public.espaces s2
                     join public.entreprises e2 on e2.id = s2.entreprise_id
                    where e2.agent_id = u.id),
                 'nb_abonnements_actifs', (
                   select count(*) from public.entreprises e3
                    where e3.agent_id = u.id and e3.activation_etape = 'actif'),
                 'montant_encaisse', (
                   select coalesce(sum(a.montant), 0)
                     from public.activations_entreprise a
                    where a.etape = 'paiement_finance'
                      and a.montant is not null
                      and a.entreprise_id in (
                        select e4.id from public.entreprises e4 where e4.agent_id = u.id))
               ) as t,
               u.created_at
          from public.utilisateurs u
         where coalesce(u.new_role::text, u.role) = 'AGENT_TERRAIN'
      ) s
  ), '[]'::jsonb);
end;
$$;

comment on function public.rpc_bg_agents_lister() is
  'Module 21 quinquies — Liste des comptes AGENT_TERRAIN avec compteurs (service_role uniquement, pour Biashara Group).';

revoke all on function public.rpc_bg_agents_lister() from public, anon, authenticated;
grant execute on function public.rpc_bg_agents_lister() to service_role;


--  3.c JOURNAL UNIFIÉ — « tout ce qu'il fait dans Biashara Yangu »
--      Réunit le journal d'audit (connexions, vérifications, montants,
--      vitrines, rapports, IA…) ET les étapes du workflow d'activation
--      (paiements encaissés), avec le nom de l'entreprise concernée.
create or replace function public.rpc_bg_agent_journal_lister(
  p_agent_id uuid,
  p_limite   integer default 100,
  p_decalage integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limite   integer := least(greatest(coalesce(p_limite, 100), 1), 500);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_total    integer := 0;
  v_liste    jsonb := '[]'::jsonb;
begin
  select count(*) into v_total
    from public.journal_audit a
   where a.utilisateur_id = p_agent_id;

  select coalesce(jsonb_agg(s.t order by s.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select jsonb_build_object(
               'source', 'yangu_journal',
               'action', a.action,
               'niveau', to_jsonb(a) ->> 'niveau',
               'entreprise_id', a.entreprise_id,
               'entreprise', (select e.nom from public.entreprises e where e.id = a.entreprise_id),
               'details', a.details,
               'created_at', a.created_at
             ) as t,
             a.created_at
        from public.journal_audit a
       where a.utilisateur_id = p_agent_id

      union all

      select jsonb_build_object(
               'source', 'yangu_activation',
               'action', 'ACTIVATION_' || upper(h.etape),
               'niveau', 'MOYEN',
               'entreprise_id', h.entreprise_id,
               'entreprise', (select e.nom from public.entreprises e where e.id = h.entreprise_id),
               'details', jsonb_build_object(
                            'montant', h.montant,
                            'mode_paiement', h.mode_paiement,
                            'reference', h.reference_transaction,
                            'acteur_role', h.acteur_role,
                            'note', h.note),
               'created_at', h.created_at
             ) as t,
             h.created_at
        from public.activations_entreprise h
       where h.acteur_id = p_agent_id

       order by created_at desc
       limit v_limite offset v_decalage
    ) s;

  return jsonb_build_object('ok', true, 'total', v_total, 'journal', v_liste);
end;
$$;

comment on function public.rpc_bg_agent_journal_lister(uuid, integer, integer) is
  'Module 21 quinquies — Journal unifié d''un agent terrain (audit + étapes d''activation) pour Biashara Group (service_role uniquement).';

revoke all on function public.rpc_bg_agent_journal_lister(uuid, integer, integer) from public, anon, authenticated;
grant execute on function public.rpc_bg_agent_journal_lister(uuid, integer, integer) to service_role;


--  3.d DÉSACTIVER UN COMPTE AGENT (jamais de suppression).
create or replace function public.rpc_bg_agent_desactiver(
  p_agent_id uuid,
  p_motif    text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role  text;
  v_email text;
  v_motif text := nullif(btrim(coalesce(p_motif, '')), '');
begin
  select coalesce(u.new_role::text, u.role), u.email
    into v_role, v_email
    from public.utilisateurs u
   where u.id = p_agent_id;

  if v_role is null then
    raise exception 'UTILISATEUR_INCONNU|Ce compte n''existe plus.';
  end if;

  if v_role <> 'AGENT_TERRAIN' then
    raise exception 'ROLE_INVALIDE|Ce compte n''est pas un agent terrain (%).', v_role;
  end if;

  if v_motif is null or length(v_motif) < 3 then
    raise exception 'MOTIF_REQUIS|Indiquez le motif de la désactivation (3 caractères minimum).';
  end if;

  update public.utilisateurs
     set valide = 0
   where id = p_agent_id;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'AGENT_TERRAIN_DESACTIVE', p_agent_id,
      jsonb_build_object('email', v_email, 'motif', v_motif, 'par', 'BIASHARA_GROUP')
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'agent_id', p_agent_id, 'valide', 0, 'motif', v_motif);
end;
$$;

comment on function public.rpc_bg_agent_desactiver(uuid, text) is
  'Module 21 quinquies — Désactive (valide = 0) le compte d''un agent terrain, avec motif obligatoire et trace au journal. Aucune suppression de données. service_role uniquement.';

revoke all on function public.rpc_bg_agent_desactiver(uuid, text) from public, anon, authenticated;
grant execute on function public.rpc_bg_agent_desactiver(uuid, text) to service_role;


-- ============================================================================
--  4. CRÉER UN COMPTE AGENT DEPUIS BIASHARA GROUP
-- ============================================================================
--  `rpc_admin_creer_agent_terrain` exige un rôle plateforme : un appel
--  service_role (sans session) serait refusé. On réutilise donc le même
--  constructeur (`creer_compte_plateforme`) derrière une porte service_role.

create or replace function public.rpc_bg_agent_creer(
  p_email    text,
  p_password text,
  p_nom      text,
  p_prenom   text,
  p_note     text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_id     uuid;
  v_existe integer := 0;
begin
  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE|Adresse e-mail invalide.';
  end if;

  if p_password is null or length(p_password) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT|Le mot de passe doit comporter au moins 8 caractères.';
  end if;

  select count(*) into v_existe
    from public.utilisateurs u where lower(u.email) = v_email;

  v_id := public.creer_compte_plateforme(
            v_email, p_password,
            coalesce(nullif(btrim(p_nom), ''), 'Agent'),
            coalesce(nullif(btrim(p_prenom), ''), 'terrain'),
            'AGENT_TERRAIN');

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'AGENT_TERRAIN_CREE', v_id,
      jsonb_build_object(
        'email', v_email,
        'compte_existant', (v_existe > 0),
        'par', 'BIASHARA_GROUP',
        'note', nullif(btrim(coalesce(p_note, '')), '')
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'agent_id', v_id,
    'email', v_email,
    'role', 'AGENT_TERRAIN',
    'compte_reutilise', (v_existe > 0)
  );
end;
$$;

comment on function public.rpc_bg_agent_creer(text, text, text, text, text) is
  'Module 21 quinquies — Crée (ou réaligne) un compte AGENT_TERRAIN pour Biashara Group : compte Auth + profil + journal. service_role uniquement.';

revoke all on function public.rpc_bg_agent_creer(text, text, text, text, text) from public, anon, authenticated;
grant execute on function public.rpc_bg_agent_creer(text, text, text, text, text) to service_role;


-- ============================================================================
--  5. VÉRIFICATION — RUN SÉPARÉ
-- ============================================================================
--  -- 1. Les fonctions sont bien réservées au service_role (aucune ligne pour
--  --    anon/authenticated) :
--  -- select proname, proacl from pg_proc p
--  --   join pg_namespace n on n.oid = p.pronamespace
--  --  where n.nspname='public' and p.proname like 'rpc_bg_%';
--  --
--  -- 2. Le calcul répond (à lancer en tant que service_role, donc via l'Edge
--  --    Function ou le SQL Editor) :
--  -- select public.rpc_bg_agents_lister();
--  -- select public.rpc_bg_agent_fiche('83162486-0478-4314-bb8e-9bdee71cc516');
--  -- select public.rpc_bg_agent_journal_lister('83162486-0478-4314-bb8e-9bdee71cc516', 50, 0);
-- ============================================================================
--  FIN — module 21 quinquies.
-- ============================================================================
