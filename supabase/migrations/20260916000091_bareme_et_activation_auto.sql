-- ============================================================================
--  biashara_yangu — PHASE 11 : BARÈME AUTOMATIQUE, ACTIVATION SANS
--                            ADMINISTRATION, AVANCE INTELLIGENTE
--  ---------------------------------------------------------------------------
--  RÈGLES DEMANDÉES PAR LE PATRON
--  -------------------------------
--   1. À la création, le compte s'active TOUT SEUL avec 7 jours d'essai —
--      que ce soit le client, un agent ou l'administrateur qui le crée.
--      Plus de double validation, plus de code d'activation.
--   2. Les prix viennent d'un BARÈME par défaut, modifiable par négociation :
--        • boutique mode simple   : 10 000 installation / 5 000 par mois
--        • boutique (complet)     : 30 000 installation / 10 000 par mois
--                                   (« dans 30 000 tout est inclus »)
--        • distribution           : 50 000 installation / 20 000 par mois
--                                   (installation jusqu'à 100 000 négociable)
--   3. L'AVANCE est intelligente : 5 000 sur 30 000 → le système dit combien
--      de jours cela représente, avant même de payer.
--
--  ⚠️ LE MOTEUR (`rpc_abonnement_enregistrer_paiement`) N'EST PAS TOUCHÉ :
--     il active déjà le compte dès que le cycle est soldé.
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'entreprises'
  ) then
    raise exception 'Table entreprises absente : exécutez les modules 1 à 5.';
  end if;
end $$;


-- ============================================================================
--  1. BARÈME PAR DÉFAUT
-- ============================================================================

create table if not exists public.bareme_abonnement (
  profil            text primary key,
  libelle           text not null,
  prix_installation numeric(12,2) not null default 0,
  prix_mensuel      numeric(12,2) not null default 0,
  installation_max  numeric(12,2),
  actif             boolean not null default true,
  updated_at        timestamptz not null default now()
);

comment on table public.bareme_abonnement is
  'Prix par défaut d''un abonnement, par profil. Les prix NÉGOCIÉS de l''entreprise (prix_installation / prix_abonnement_mensuel) restent prioritaires.';

insert into public.bareme_abonnement
  (profil, libelle, prix_installation, prix_mensuel, installation_max)
values
  ('boutique_simple',   'Boutique — mode simple (création autonome)',  10000,  5000, null),
  ('boutique_complete', 'Boutique — mode complet',                     30000, 10000, null),
  ('distribution',      'Distribution (eau, PGC, tournées)',           50000, 20000, 100000)
on conflict (profil) do nothing;

alter table public.bareme_abonnement enable row level security;

drop policy if exists m91_bareme_lecture on public.bareme_abonnement;
create policy m91_bareme_lecture on public.bareme_abonnement
  for select to authenticated using (true);

revoke insert, update, delete on public.bareme_abonnement from authenticated, anon;

create or replace function public.rpc_bareme_abonnement()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'profil', b.profil,
           'libelle', b.libelle,
           'prix_installation', b.prix_installation,
           'prix_mensuel', b.prix_mensuel,
           'installation_max', b.installation_max
         ) order by b.prix_installation), '[]'::jsonb)
    from public.bareme_abonnement b
   where b.actif;
$$;

comment on function public.rpc_bareme_abonnement() is
  'Barème des abonnements (installation + mensuel) par profil.';

revoke all on function public.rpc_bareme_abonnement() from public, anon;
grant execute on function public.rpc_bareme_abonnement() to authenticated;


-- ============================================================================
--  2. APPLICATION AUTOMATIQUE DU BARÈME + ACTIVATION À LA CRÉATION
-- ============================================================================
--  Un trigger AVANT écriture (pas après) : pas de récursion, et il voit
--  exactement ce que la fonction de création s'apprête à enregistrer.

create or replace function public.abonnement_politique_automatique()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profil text;
  v_b      public.bareme_abonnement%rowtype;
begin
  -- Quel profil de prix ? Le type d'activité décide ; à défaut, boutique.
  v_profil := case
                when lower(btrim(coalesce(new.type_activite, ''))) = 'distribution'
                  then 'distribution'
                else 'boutique_complete'
              end;

  select * into v_b from public.bareme_abonnement where profil = v_profil;

  -- 1) PRIX : on ne remplit QUE ce qui est vide. Un prix négocié reste roi.
  if new.prix_installation is null and v_b.prix_installation is not null then
    new.prix_installation := v_b.prix_installation;
  end if;
  if new.prix_abonnement_mensuel is null and v_b.prix_mensuel is not null then
    new.prix_abonnement_mensuel := v_b.prix_mensuel;
  end if;

  -- 2) ACTIVATION AUTOMATIQUE : le dossier « en attente de vérification »
  --    devient immédiatement un compte ACTIF en essai de 7 jours.
  if new.activation_etape = 'en_attente_verification' then
    new.activation_etape := 'actif';
    new.statut           := 'ESSAI_7J'::public.statut_abonnement_enum;
    new.date_activation  := coalesce(new.date_activation, now());
    new.date_expiration  := coalesce(new.date_expiration, now() + interval '7 days');
    new.montant_total_du := coalesce(new.montant_total_du, 0);
    new.montant_deja_paye := coalesce(new.montant_deja_paye, 0);
  end if;

  return new;
end;
$$;

comment on function public.abonnement_politique_automatique() is
  'Prix du barème si non négociés, et activation immédiate en essai 7 jours (plus de validation administrative).';

drop trigger if exists trg_abonnement_politique on public.entreprises;
create trigger trg_abonnement_politique
  before insert or update on public.entreprises
  for each row execute function public.abonnement_politique_automatique();


-- ============================================================================
--  3. AVANCE INTELLIGENTE : COMBIEN DE JOURS POUR CE MONTANT ?
-- ============================================================================
--  Calcul PUR, sans écriture : l'écran de paiement peut l'afficher en direct
--  (« 5 000 sur 30 000 ≈ 5 jours ») AVANT que le client valide.

create or replace function public.rpc_abonnement_simulation_avance(
  p_entreprise uuid default null,
  p_montant    numeric default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user    uuid := auth.uid();
  v_id      uuid;
  v_e       public.entreprises%rowtype;
  v_cycle   numeric := 0;
  v_reste   numeric := 0;
  v_prix_j  numeric := 0;
  v_jours   integer := 0;
  v_complet boolean := false;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_id := coalesce(p_entreprise, public.mon_entreprise_id(), v_user);
  select * into v_e from public.entreprises where id = v_id;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe pas.';
  end if;

  v_cycle := public.rpc_abonnement_prix_du_cycle(v_id);
  v_reste := greatest(coalesce(v_e.solde_restant, 0), 0);

  -- Prix d'une journée = PRIX DU CYCLE / 30 (et non pas le reste à payer) :
  -- 30 000 le mois ⇒ 1 000 par jour ⇒ 5 000 = 5 jours, même si le client a
  -- déjà versé une partie.
  if v_reste <= 0 then
    v_reste := greatest(v_cycle, 0);
  end if;

  v_prix_j := case
                when v_cycle > 0 then round(v_cycle / 30.0, 2)
                when v_reste > 0 then round(v_reste / 30.0, 2)
                else 0
              end;

  v_jours := case
               when v_prix_j > 0 and p_montant is not null and p_montant > 0
                 then floor(p_montant / v_prix_j)::integer
               else 0
             end;
  if v_jours > 30 then v_jours := 30; end if;

  v_complet := p_montant is not null and p_montant + 0.01 >= v_reste;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', v_id,
    'devise', coalesce(v_e.devise, 'CDF'),
    'montant_saisi', coalesce(p_montant, 0),
    'reste_a_payer', v_reste,
    'prix_cycle', v_cycle,
    'prix_jour', v_prix_j,
    'jours_obtenus', case when v_complet then 30 else v_jours end,
    'cycle_complet', v_complet,
    'type_cycle', public.rpc_abonnement_type_cycle(v_id),
    'date_fin_estimee', case
      when v_complet then now() + interval '30 days'
      when v_jours > 0 then now() + make_interval(days => v_jours)
      else now()
    end
  );
end;
$$;

comment on function public.rpc_abonnement_simulation_avance(uuid, numeric) is
  'Combien de jours d''abonnement un montant donné achète : prix du cycle / 30, plafonné au mois complet.';

revoke all on function public.rpc_abonnement_simulation_avance(uuid, numeric) from public, anon;
grant execute on function public.rpc_abonnement_simulation_avance(uuid, numeric) to authenticated;


-- ============================================================================
--  4. CRÉATION AUTONOME (MODE SIMPLE) : BARÈME « SIMPLE »
-- ============================================================================
--  Le trigger ci-dessus applique le barème « boutique complète » (30 000 /
--  10 000). Un client qui crée son compte SEUL doit tomber sur le barème
--  « simple » (10 000 / 5 000) : on l'applique ici, uniquement s'il n'a rien
--  négocié (création neuve). Une entreprise de distribution garde son barème.

create or replace function public.rpc_entreprise_creer_simple(
  p_nom       text default null,
  p_telephone text default null,
  p_type      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_res   jsonb;
  v_id    uuid;
  v_deja  boolean;
  v_type  text := coalesce(nullif(btrim(coalesce(p_type, '')), ''), 'boutique');
  v_fin   timestamptz := now() + interval '7 days';
  v_b     public.bareme_abonnement%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  v_res := public.rpc_entreprise_creer(p_nom, p_telephone, v_type);

  v_id := nullif(v_res->>'entreprise_id', '')::uuid;
  v_deja := coalesce((v_res->>'deja')::boolean, false);

  if v_id is null then
    raise exception 'CREATION_IMPOSSIBLE|L''entreprise n''a pas pu être créée.';
  end if;

  if v_deja then
    return v_res || jsonb_build_object('mode', 'simple', 'essai', false);
  end if;

  -- Prix du profil « simple » (jamais pour une distribution).
  if lower(v_type) <> 'distribution' then
    select * into v_b from public.bareme_abonnement
     where profil = 'boutique_simple' and actif;
  end if;

  update public.entreprises
     set activation_etape = 'actif',
         statut = 'ESSAI_7J'::public.statut_abonnement_enum,
         date_activation = now(),
         date_expiration = v_fin,
         montant_total_du = 0,
         montant_deja_paye = 0,
         prix_installation = coalesce(v_b.prix_installation, prix_installation),
         prix_abonnement_mensuel = coalesce(v_b.prix_mensuel, prix_abonnement_mensuel),
         updated_at = now()
   where id = v_id;

  begin
    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role, note
    ) values (
      v_id, 'paiement_finance', v_user, public.mon_role(),
      'Activation AUTOMATIQUE — mode simple (essai 7 jours)'
    );
  exception when others then null;
  end;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'ACTIVATION_AUTO_ESSAI', v_user,
      jsonb_build_object(
        'entreprise_id', v_id, 'mode', 'simple', 'essai_jours', 7,
        'date_expiration', v_fin,
        'prix_installation', v_b.prix_installation,
        'prix_mensuel', v_b.prix_mensuel,
        'type', v_type
      )
    );
  exception when others then null;
  end;

  return v_res || jsonb_build_object(
    'mode', 'simple',
    'essai', true,
    'essai_jours', 7,
    'date_expiration', v_fin,
    'activation_etape', 'actif',
    'prix_installation', v_b.prix_installation,
    'prix_abonnement_mensuel', v_b.prix_mensuel
  );
end;
$$;

comment on function public.rpc_entreprise_creer_simple(text, text, text) is
  'Mode simple : crée l''entreprise, applique le barème simple (ou distribution) et ACTIVE immédiatement 7 jours d''essai — sans validation administrative.';

revoke all on function public.rpc_entreprise_creer_simple(text, text, text) from public, anon;
grant execute on function public.rpc_entreprise_creer_simple(text, text, text) to authenticated;


-- ============================================================================
--  5. CONTRÔLE — le barème est-il en place ?
-- ============================================================================

do $$
declare
  v_n integer;
begin
  select count(*) into v_n from public.bareme_abonnement where actif;
  if v_n < 3 then
    raise warning 'Barème incomplet : % profil(s) actif(s) au lieu de 3.', v_n;
  end if;
end $$;

-- ============================================================================
--  FIN — PHASE 11
-- ============================================================================
