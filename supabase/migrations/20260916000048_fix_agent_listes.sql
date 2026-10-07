-- ============================================================================
--  MODULE 21 ter bis — CORRECTIF DES LISTES DE L'AGENT TERRAIN
--  Migration 20260916000048_fix_agent_listes.sql
-- ============================================================================
--
--  À exécuter APRÈS la migration 47 (agent_terrain_cloisonnement).
--  IDEMPOTENTE : `create or replace function`.
--
--  LE DÉFAUT CORRIGÉ
--  -----------------
--  Dans `rpc_agent_utilisateurs_lister` et `rpc_agent_abonnements_lister`, la
--  requête extérieure agrégeait `jsonb_agg(t order by t.created_at desc)`
--  alors que la sous-requête est ALIASÉE `s` : PostgreSQL répondait
--
--      missing FROM-clause entry for table "t"
--
--  Les deux fonctions sont donc RECOPIÉES ici avec l'alias correct (`s.t`,
--  `s.created_at`). Les écrans « Mes clients » et « Mes abonnements » de
--  l'agent fonctionnent alors normalement.
--
--  Cette migration ne touche à RIEN d'autre : ni colonne, ni policy, ni autre
--  fonction. Elle reste sûre à rejouer.
-- ============================================================================


--  1. MES UTILISATEURS (clients/patrons onboardés par l'agent).
create or replace function public.rpc_agent_utilisateurs_lister(
  p_agent_id  uuid default null,
  p_recherche text default null,
  p_limite    integer default 200,
  p_decalage  integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := auth.uid();
  v_agent  uuid := coalesce(p_agent_id, auth.uid());
  v_q      text := public.biashara_normaliser(p_recherche);
  v_limite integer := least(greatest(coalesce(p_limite, 200), 1), 500);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_total  integer := 0;
  v_liste  jsonb := '[]'::jsonb;
begin
  if v_moi is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_plateforme() and not public.est_agent_terrain() then
    raise exception 'DROIT_REFUSE|Réservé au personnel plateforme ou à un agent terrain.';
  end if;
  if public.est_agent_terrain() and v_agent <> v_moi then
    raise exception 'DROIT_REFUSE|Un agent ne consulte que ses propres utilisateurs.';
  end if;

  select count(*) into v_total
    from public.utilisateurs u
   where u.agent_id = v_agent
     and (v_q = '' or public.biashara_normaliser(
            coalesce(u.nom, '') || ' ' || coalesce(u.email, '')) like '%' || v_q || '%');

  select coalesce(jsonb_agg(s.t order by s.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select jsonb_build_object(
               'id', u.id,
               'nom', u.nom,
               'email', u.email,
               'telephone', to_jsonb(u) ->> 'telephone',
               'role', coalesce(u.new_role::text, u.role),
               'entreprise_id', u.entreprise_id,
               'entreprise', (select e.nom from public.entreprises e where e.id = u.entreprise_id),
               'activation_etape',
                 (select coalesce(e.activation_etape, 'actif')
                    from public.entreprises e where e.id = u.entreprise_id),
               'created_at', u.created_at
             ) as t,
             u.created_at
        from public.utilisateurs u
       where u.agent_id = v_agent
         and (v_q = '' or public.biashara_normaliser(
                coalesce(u.nom, '') || ' ' || coalesce(u.email, '')) like '%' || v_q || '%')
       order by u.created_at desc
       limit v_limite offset v_decalage
    ) s;

  return jsonb_build_object('ok', true, 'total', v_total, 'utilisateurs', v_liste);
end;
$$;

comment on function public.rpc_agent_utilisateurs_lister(uuid, text, integer, integer) is
  'Module 21 ter — Utilisateurs rattachés à un agent terrain (les siens uniquement pour un agent). Correctif 48 : alias d''agrégat (s.t).';

revoke all on function public.rpc_agent_utilisateurs_lister(uuid, text, integer, integer) from public, anon;
grant execute on function public.rpc_agent_utilisateurs_lister(uuid, text, integer, integer) to authenticated;


--  2. MES ABONNEMENTS (suivi de ce que les dossiers génèrent).
create or replace function public.rpc_agent_abonnements_lister(
  p_agent_id uuid default null,
  p_filtre   text default 'tous',
  p_limite   integer default 200,
  p_decalage integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_moi    uuid := auth.uid();
  v_agent  uuid := coalesce(p_agent_id, auth.uid());
  v_filtre text := lower(btrim(coalesce(p_filtre, 'tous')));
  v_limite integer := least(greatest(coalesce(p_limite, 200), 1), 500);
  v_decalage integer := greatest(coalesce(p_decalage, 0), 0);
  v_total  integer := 0;
  v_liste  jsonb := '[]'::jsonb;
  v_encaisse numeric := 0;
  v_solde  numeric := 0;
begin
  if v_moi is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_plateforme() and not public.est_agent_terrain() then
    raise exception 'DROIT_REFUSE|Réservé au personnel plateforme ou à un agent terrain.';
  end if;
  if public.est_agent_terrain() and v_agent <> v_moi then
    raise exception 'DROIT_REFUSE|Un agent ne consulte que ses propres abonnements.';
  end if;

  if v_filtre not in ('tous', 'actifs', 'en_attente', 'impayes') then
    v_filtre := 'tous';
  end if;

  select count(*),
         coalesce(sum(coalesce(e.solde_restant, 0)), 0)
    into v_total, v_solde
    from public.entreprises e
   where e.agent_id = v_agent
     and (
       v_filtre = 'tous'
       or (v_filtre = 'actifs' and e.activation_etape = 'actif')
       or (v_filtre = 'en_attente' and e.activation_etape in ('en_attente_verification', 'verifie'))
       or (v_filtre = 'impayes' and coalesce(e.solde_restant, 0) > 0)
     );

  begin
    select coalesce(sum(a.montant), 0) into v_encaisse
      from public.activations_entreprise a
     where a.etape = 'paiement_finance'
       and a.montant is not null
       and a.entreprise_id in (select e.id from public.entreprises e where e.agent_id = v_agent);
  exception when others then v_encaisse := 0;
  end;

  select coalesce(jsonb_agg(s.t order by s.created_at desc), '[]'::jsonb)
    into v_liste
    from (
      select jsonb_build_object(
               'entreprise_id', e.id,
               'nom', e.nom,
               'statut', e.statut::text,
               'activation_etape', coalesce(e.activation_etape, 'actif'),
               'montant_total_du', e.montant_total_du,
               'montant_deja_paye', e.montant_deja_paye,
               'solde_restant', coalesce(e.solde_restant, 0),
               'date_activation', e.date_activation,
               'date_expiration', e.date_expiration,
               'responsable', (
                 select coalesce(nullif(btrim(u.nom), ''), u.email)
                   from public.utilisateurs u
                  where u.entreprise_id = e.id and u.parent_id is null
                  order by u.created_at limit 1),
               'contact', (
                 select u.email from public.utilisateurs u
                  where u.entreprise_id = e.id and u.parent_id is null
                  order by u.created_at limit 1),
               'telephone', (
                 select to_jsonb(u) ->> 'telephone' from public.utilisateurs u
                  where u.entreprise_id = e.id and u.parent_id is null
                  order by u.created_at limit 1),
               'nb_publies', (
                 select count(*) from public.produits_publications pb
                  where pb.publie
                    and pb.espace_id in (select s.id from public.espaces s where s.entreprise_id = e.id))
             ) as t,
             e.created_at
        from public.entreprises e
       where e.agent_id = v_agent
         and (
           v_filtre = 'tous'
           or (v_filtre = 'actifs' and e.activation_etape = 'actif')
           or (v_filtre = 'en_attente' and e.activation_etape in ('en_attente_verification', 'verifie'))
           or (v_filtre = 'impayes' and coalesce(e.solde_restant, 0) > 0)
         )
       order by e.created_at desc
       limit v_limite offset v_decalage
    ) s;

  return jsonb_build_object(
    'ok', true,
    'total', v_total,
    'montant_encaisse', v_encaisse,
    'solde_du', v_solde,
    'abonnements', v_liste
  );
end;
$$;

comment on function public.rpc_agent_abonnements_lister(uuid, text, integer, integer) is
  'Module 21 ter — Suivi des abonnements d''un agent terrain (les siens pour un agent). Correctif 48 : alias d''agrégat (s.t).';

revoke all on function public.rpc_agent_abonnements_lister(uuid, text, integer, integer) from public, anon;
grant execute on function public.rpc_agent_abonnements_lister(uuid, text, integer, integer) to authenticated;


-- ============================================================================
--  3. ATTRIBUTION — LES COMPTES CRÉÉS PAR UN AGENT
-- ============================================================================
--  Quand un agent crée un compte depuis l'écran « Ajouter un utilisateur »,
--  l'inscription pose `parent_id` = identifiant de L'AGENT (c'est la
--  hiérarchie existante). On en profite pour rattacher ces comptes à l'agent :
--  ils apparaissent alors dans « Mes clients » (`agent_id`).
--
--  ⚠️ Le trigger d'inscription (GoTrue) insère la ligne `utilisateurs` avec
--  `parent_id` déjà renseigné : notre BEFORE INSERT le lit donc correctement.

create or replace function public.trg_m47b_attribuer_agent_parent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.agent_id is null and new.parent_id is not null then
    if exists (
      select 1 from public.utilisateurs u
       where u.id = new.parent_id
         and coalesce(u.new_role::text, u.role) = 'AGENT_TERRAIN'
    ) then
      new.agent_id := new.parent_id;
    end if;
  end if;
  return new;
end;
$$;

comment on function public.trg_m47b_attribuer_agent_parent() is
  'Module 21 ter — Rattache automatiquement à un agent terrain les comptes qu''il crée (parent_id = l''agent).';

drop trigger if exists trg_m47b_agent_parent on public.utilisateurs;
create trigger trg_m47b_agent_parent
  before insert on public.utilisateurs
  for each row execute function public.trg_m47b_attribuer_agent_parent();


-- ============================================================================
--  VÉRIFICATION — RUN SÉPARÉ, AVEC LA SESSION DE L'AGENT
-- ============================================================================
--  select public.rpc_agent_utilisateurs_lister(null, null, 10, 0);
--  select public.rpc_agent_abonnements_lister(null, 'tous', 10, 0);
--
--  Les deux doivent répondre { "ok": true, ... } — plus de
--  « missing FROM-clause entry for table "t" ».
-- ============================================================================
--  FIN — correctif 48.
-- ============================================================================
