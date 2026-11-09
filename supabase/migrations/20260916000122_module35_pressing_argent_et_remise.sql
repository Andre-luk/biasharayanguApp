-- ============================================================================
--  biashara_yangu — MODULE 35 : PRESSING & BLANCHISSERIE
--  ÉTAPE 3/4 — L'ARGENT ET LA REMISE DES VÊTEMENTS
--  ---------------------------------------------------------------------------
--  CE QUE CE SCRIPT AJOUTE
--    1. pressing_retraits        → une opération de remise (qui, quand, quoi)
--    2. pressing_retrait_lignes  → les vêtements précisément remis
--    3. Les RPC :
--         pressing_paiement_ajouter / pressing_paiement_annuler
--         pressing_retrait_enregistrer   (remise partielle ou totale)
--         pressing_retraits_lister
--         pressing_tableau_bord          (les indicateurs du dashboard)
--         pressing_commandes_en_retard
--
--  RÈGLES QUI FONT FOI (et qui protègent l'argent du commerçant)
--    • Un vêtement ne peut être remis QUE s'il est à l'étape finale (PRÊT)
--      et n'a pas déjà été remis → la double remise est impossible.
--    • Chaque remise est une OPÉRATION DISTINCTE : un dossier de 10
--      vêtements peut être remis en 3 fois, l'historique garde les 3.
--    • Le STATUT de la commande se déduit des lignes : partiellement remise
--      tant qu'il en reste.
--    • Si le pressing exige le solde (politique SOLDE_OBLIGATOIRE), la
--      DERNIÈRE remise est refusée tant qu'il reste de l'argent dû.
--    • Un encaissement ne se supprime JAMAIS : il s'annule (trace + motif).
--    • « Facturé » n'est jamais présenté comme « encaissé » : le tableau de
--      bord renvoie les deux séparément.
--
--  ⚠️ IDEMPOTENT — peut être rejoué. Aucune table existante modifiée.
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase (après 0120 et 0121).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LES REMISES
-- ============================================================================

create table if not exists public.pressing_retraits (
  id               uuid primary key default gen_random_uuid(),
  entreprise_id    uuid not null,
  commande_id      uuid not null
    references public.pressing_commandes (id) on delete cascade,
  -- Ce qui a été encaissé À CETTE REMISE (le cas échéant).
  montant_encaisse numeric(14, 2) not null default 0,
  mode_paiement    text,
  reference        text,
  observations     text,
  -- Preuve de réception : nom saisi par le client (ou mention « retiré par
  -- un tiers »). Aucune signature électronique n'est inventée.
  signataire       text,
  agent_id         uuid,
  created_at       timestamptz not null default now()
);

create index if not exists idx_pressing_retraits_commande
  on public.pressing_retraits (commande_id, created_at desc);

comment on table public.pressing_retraits is
  'Module 35 — opération de remise : une ligne par passage du client (remise partielle ou totale), avec l''agent et le montant encaissé à cette occasion.';


create table if not exists public.pressing_retrait_lignes (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null,
  retrait_id    uuid not null
    references public.pressing_retraits (id) on delete cascade,
  ligne_id      uuid not null
    references public.pressing_lignes (id) on delete cascade,
  quantite      numeric(10, 2) not null default 1 check (quantite > 0),
  created_at    timestamptz not null default now()
);

create index if not exists idx_pressing_retrait_lignes_retrait
  on public.pressing_retrait_lignes (retrait_id);

-- ⛔ Un vêtement ne peut apparaître qu'UNE fois dans l'ensemble des remises.
create unique index if not exists idx_pressing_retrait_lignes_unique
  on public.pressing_retrait_lignes (ligne_id);

comment on table public.pressing_retrait_lignes is
  'Module 35 — vêtements effectivement remis lors d''une opération (unicité : un vêtement ne se remet qu''une fois).';


alter table public.pressing_retraits        enable row level security;
alter table public.pressing_retrait_lignes  enable row level security;

drop policy if exists pressing_retraits_lecture on public.pressing_retraits;
create policy pressing_retraits_lecture on public.pressing_retraits
  for select to authenticated
  using (entreprise_id = public.pressing_entreprise() or public.est_plateforme());

drop policy if exists pressing_retrait_lignes_lecture on public.pressing_retrait_lignes;
create policy pressing_retrait_lignes_lecture on public.pressing_retrait_lignes
  for select to authenticated
  using (entreprise_id = public.pressing_entreprise() or public.est_plateforme());

revoke insert, update, delete on public.pressing_retraits       from authenticated, anon;
revoke insert, update, delete on public.pressing_retrait_lignes from authenticated, anon;


-- ============================================================================
--  2. OUTIL INTERNE — RECALCUL DE CE QUI A ÉTÉ ENCAISSÉ
-- ============================================================================

create or replace function public.pressing_recalc_paye(p_commande_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paye numeric;
begin
  select coalesce(sum(montant), 0) into v_paye
    from public.pressing_paiements
   where commande_id = p_commande_id and annule_le is null;

  update public.pressing_commandes
     set montant_paye = v_paye, updated_at = now()
   where id = p_commande_id;

  return v_paye;
end;
$$;

comment on function public.pressing_recalc_paye(uuid) is
  'Module 35 — recalcule le montant encaissé d''une commande à partir des encaissements non annulés.';

revoke all on function public.pressing_recalc_paye(uuid) from public, anon;
grant execute on function public.pressing_recalc_paye(uuid) to authenticated;


-- ============================================================================
--  3. RPC — ENCAISSER UN VERSEMENT
-- ============================================================================

create or replace function public.pressing_paiement_ajouter(
  p_commande_id uuid,
  p_montant     numeric,
  p_mode        text default 'especes',
  p_reference   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_cmd  public.pressing_commandes%rowtype;
  v_id   uuid;
  v_paye numeric;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_depots', 'creer')
          or public.peut('caisse', 'creer')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''encaisser un paiement.';
  end if;
  if p_montant is null or p_montant <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant doit être supérieur à zéro.';
  end if;

  select * into v_cmd
    from public.pressing_commandes
   where id = p_commande_id and entreprise_id = v_ent
   for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Cette commande n''existe pas.';
  end if;
  if v_cmd.statut = 'ANNULEE' then
    raise exception 'COMMANDE_ANNULEE|Cette commande est annulée : aucun encaissement possible.';
  end if;

  v_paye := public.pressing_recalc_paye(v_cmd.id);

  if v_paye + p_montant > v_cmd.total then
    raise exception 'MONTANT_INVALIDE|Le total encaissé dépasserait le montant facturé (% restant).',
      greatest(v_cmd.total - v_paye, 0);
  end if;

  insert into public.pressing_paiements (
    entreprise_id, commande_id, montant, mode, reference, agent_id
  ) values (
    v_ent, v_cmd.id, round(p_montant, 2),
    coalesce(nullif(btrim(coalesce(p_mode, '')), ''), 'especes'),
    nullif(btrim(coalesce(p_reference, '')), ''),
    auth.uid()
  )
  returning id into v_id;

  v_paye := public.pressing_recalc_paye(v_cmd.id);

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_ent, 'PRESSING_PAIEMENT', auth.uid(),
    jsonb_build_object('commande', v_cmd.numero, 'montant', p_montant,
                       'mode', p_mode, 'encaisse_total', v_paye),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'montant_paye', v_paye,
    'solde', greatest(v_cmd.total - v_paye, 0)
  );
end;
$$;

comment on function public.pressing_paiement_ajouter(uuid, numeric, text, text) is
  'Module 35 — enregistre un versement sur une commande (jamais au-delà du montant facturé).';

revoke all on function public.pressing_paiement_ajouter(uuid, numeric, text, text)
  from public, anon;
grant execute on function public.pressing_paiement_ajouter(uuid, numeric, text, text)
  to authenticated;


create or replace function public.pressing_paiement_annuler(
  p_paiement_id uuid,
  p_motif       text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid := public.pressing_entreprise();
  v_p   public.pressing_paiements%rowtype;
  v_num text;
  v_paye numeric;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  -- Argent : réservé au propriétaire (ou à la plateforme).
  if not (public.peut('finance', 'valider') or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut annuler un encaissement.';
  end if;
  if btrim(coalesce(p_motif, '')) = '' then
    raise exception 'MOTIF_VIDE|Indiquez le motif de l''annulation.';
  end if;

  select * into v_p
    from public.pressing_paiements
   where id = p_paiement_id and entreprise_id = v_ent
   for update;

  if not found then
    raise exception 'INTROUVABLE|Cet encaissement n''existe pas.';
  end if;
  if v_p.annule_le is not null then
    return jsonb_build_object('ok', true, 'deja', true);
  end if;

  update public.pressing_paiements
     set annule_le = now(),
         annule_par = auth.uid(),
         motif_annulation = btrim(p_motif)
   where id = v_p.id;

  v_paye := public.pressing_recalc_paye(v_p.commande_id);

  select numero into v_num
    from public.pressing_commandes where id = v_p.commande_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_ent, 'PRESSING_PAIEMENT_ANNULE', auth.uid(),
    jsonb_build_object('commande', v_num, 'montant', v_p.montant,
                       'motif', btrim(p_motif), 'encaisse_total', v_paye),
    now()
  );

  return jsonb_build_object('ok', true, 'montant_paye', v_paye);
end;
$$;

comment on function public.pressing_paiement_annuler(uuid, text) is
  'Module 35 — annule un encaissement (jamais de suppression) avec motif et trace d''audit.';

revoke all on function public.pressing_paiement_annuler(uuid, text) from public, anon;
grant execute on function public.pressing_paiement_annuler(uuid, text) to authenticated;


-- ============================================================================
--  4. RPC — REMISE DES VÊTEMENTS (partielle ou totale)
-- ============================================================================

create or replace function public.pressing_retrait_enregistrer(
  p_commande_id  uuid,
  p_ligne_ids    uuid[],
  p_paiement     jsonb default null,
  p_observations text default null,
  p_signataire   text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent      uuid := public.pressing_entreprise();
  v_cmd      public.pressing_commandes%rowtype;
  v_cfg      public.pressing_config%rowtype;
  v_id       uuid;
  v_lid      uuid;
  v_ligne    public.pressing_lignes%rowtype;
  v_ids      uuid[] := coalesce(p_ligne_ids, '{}');
  v_n        integer := 0;
  v_finale   boolean;
  v_paie     numeric := 0;
  v_mode     text;
  v_ref      text;
  v_paye     numeric;
  v_restants integer;
  v_statut   text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_retraits', 'creer')
          or public.peut('pressing_retraits', 'valider')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de remettre des vêtements.';
  end if;
  if array_length(v_ids, 1) is null then
    raise exception 'LIGNE_INVALIDE|Sélectionnez au moins un vêtement à remettre.';
  end if;

  select * into v_cmd
    from public.pressing_commandes
   where id = p_commande_id and entreprise_id = v_ent
   for update;

  if not found then
    raise exception 'COMMANDE_INTROUVABLE|Cette commande n''existe pas.';
  end if;
  if v_cmd.statut = 'ANNULEE' then
    raise exception 'COMMANDE_ANNULEE|Cette commande est annulée : aucune remise possible.';
  end if;

  select * into v_cfg from public.pressing_config where entreprise_id = v_ent;

  -- --- 4.1 Le paiement éventuel encaissé à cette remise --------------------
  if p_paiement is not null and jsonb_typeof(p_paiement) = 'object' then
    v_paie := coalesce(nullif(p_paiement->>'montant', '')::numeric, 0);
    v_mode := coalesce(nullif(btrim(coalesce(p_paiement->>'mode', '')), ''), 'especes');
    v_ref  := nullif(btrim(coalesce(p_paiement->>'reference', '')), '');

    if v_paie < 0 then
      raise exception 'MONTANT_INVALIDE|Montant encaissé invalide.';
    end if;
  end if;

  -- --- 4.2 Vérification de CHAQUE vêtement ---------------------------------
  foreach v_lid in array v_ids loop
    select * into v_ligne
      from public.pressing_lignes
     where id = v_lid and commande_id = v_cmd.id and entreprise_id = v_ent
     for update;

    if not found then
      raise exception 'LIGNE_INVALIDE|Un vêtement sélectionné n''appartient pas à cette commande.';
    end if;

    if v_ligne.remis_le is not null then
      raise exception 'DEJA_REMIS|Le vêtement n° % a déjà été remis au client.',
        v_ligne.position;
    end if;

    select e.est_finale into v_finale
      from public.pressing_etapes e
     where e.entreprise_id = v_ent and e.code = v_ligne.etape_code and e.actif;

    if not coalesce(v_finale, v_ligne.etape_code = 'PRET') then
      raise exception 'VETEMENT_NON_PRET|Le vêtement n° % n''est pas encore prêt (%).',
        v_ligne.position, v_ligne.etape_code;
    end if;

    v_n := v_n + 1;
  end loop;

  -- --- 4.3 L'opération de remise -------------------------------------------
  insert into public.pressing_retraits (
    entreprise_id, commande_id, montant_encaisse, mode_paiement, reference,
    observations, signataire, agent_id
  ) values (
    v_ent, v_cmd.id, coalesce(v_paie, 0),
    case when coalesce(v_paie, 0) > 0 then v_mode else null end,
    v_ref,
    nullif(btrim(coalesce(p_observations, '')), ''),
    nullif(btrim(coalesce(p_signataire, '')), ''),
    auth.uid()
  )
  returning id into v_id;

  foreach v_lid in array v_ids loop
    -- On relit la ligne : sa position et son étape servent à l'historique.
    select * into v_ligne
      from public.pressing_lignes
     where id = v_lid and commande_id = v_cmd.id and entreprise_id = v_ent;

    insert into public.pressing_retrait_lignes (
      entreprise_id, retrait_id, ligne_id, quantite
    ) values (
      v_ent, v_id, v_lid, coalesce(v_ligne.quantite, 1)
    );

    update public.pressing_lignes
       set remis_le = now(), remis_par = auth.uid(), updated_at = now()
     where id = v_lid;

    insert into public.pressing_ligne_etapes (
      entreprise_id, commande_id, ligne_id, etape_code, etape_avant,
      agent_id, note
    ) values (
      v_ent, v_cmd.id, v_lid, 'REMIS', v_ligne.etape_code,
      auth.uid(), 'Remis au client'
    );
  end loop;

  -- --- 4.4 Encaissement éventuel -------------------------------------------
  if coalesce(v_paie, 0) > 0 then
    insert into public.pressing_paiements (
      entreprise_id, commande_id, montant, mode, reference, agent_id
    ) values (
      v_ent, v_cmd.id, round(v_paie, 2), v_mode, v_ref, auth.uid()
    );
  end if;

  v_paye := public.pressing_recalc_paye(v_cmd.id);

  if v_paye > v_cmd.total then
    raise exception 'MONTANT_INVALIDE|Le total encaissé dépasse le montant facturé.';
  end if;

  -- --- 4.5 Politique de remise ---------------------------------------------
  select count(*) into v_restants
    from public.pressing_lignes
   where commande_id = v_cmd.id and remis_le is null;

  if v_restants = 0
     and coalesce(v_cfg.politique_remise, 'SOLDE_OBLIGATOIRE') = 'SOLDE_OBLIGATOIRE'
     and v_cmd.total - v_paye > 0 then
    raise exception 'SOLDE_DU|Il reste % à payer : le pressing exige le solde avant la remise finale.',
      (v_cmd.total - v_paye);
  end if;

  v_statut := public.pressing_recalc_statut(v_cmd.id);

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_ent, 'PRESSING_RETRAIT', auth.uid(),
    jsonb_build_object(
      'commande', v_cmd.numero,
      'retrait_id', v_id,
      'nb_vetements', v_n,
      'montant_encaisse', coalesce(v_paie, 0),
      'mode', v_mode,
      'statut', v_statut
    ),
    now()
  );

  return public.pressing_commande_fiche(v_cmd.id)
         || jsonb_build_object('retrait_id', v_id,
                               'nb_remis', v_n,
                               'montant_encaisse', coalesce(v_paie, 0));
end;
$$;

comment on function public.pressing_retrait_enregistrer(uuid, uuid[], jsonb, text, text) is
  'Module 35 — remise partielle ou totale des vêtements prêts, avec encaissement éventuel, preuve de réception et refus de double remise.';

revoke all on function public.pressing_retrait_enregistrer(uuid, uuid[], jsonb, text, text)
  from public, anon;
grant execute on function public.pressing_retrait_enregistrer(uuid, uuid[], jsonb, text, text)
  to authenticated;


create or replace function public.pressing_retraits_lister(p_commande_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'created_at', r.created_at,
           'montant_encaisse', r.montant_encaisse,
           'mode_paiement', r.mode_paiement,
           'reference', r.reference,
           'observations', r.observations,
           'signataire', r.signataire,
           'agent_id', r.agent_id,
           'lignes', (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'ligne_id', rl.ligne_id,
                      'position', l.position,
                      'designation', coalesce(l.designation, l.categorie_nom)
                    ) order by l.position), '[]'::jsonb)
               from public.pressing_retrait_lignes rl
               join public.pressing_lignes l on l.id = rl.ligne_id
              where rl.retrait_id = r.id
           )
         ) order by r.created_at), '[]'::jsonb)
    into v_rows
    from public.pressing_retraits r
   where r.commande_id = p_commande_id and r.entreprise_id = v_ent;

  return v_rows;
end;
$$;

comment on function public.pressing_retraits_lister(uuid) is
  'Module 35 — historique des remises d''une commande (chaque passage du client).';

revoke all on function public.pressing_retraits_lister(uuid) from public, anon;
grant execute on function public.pressing_retraits_lister(uuid) to authenticated;


-- ============================================================================
--  5. RPC — TABLEAU DE BORD DU PRESSING
-- ============================================================================

create or replace function public.pressing_tableau_bord(
  p_debut date default null,
  p_fin   date default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent      uuid := public.pressing_entreprise();
  v_debut    date := coalesce(p_debut, current_date);
  v_fin      date := coalesce(p_fin, current_date);
  v_aujourdhui integer;
  v_en_cours integer;
  v_vetements integer;
  v_prets    integer;
  v_partiels integer;
  v_remises  integer;
  v_retard   integer;
  v_non_recup integer;
  v_facture  numeric;
  v_encaisse numeric;
  v_du       numeric;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select count(*) into v_aujourdhui
    from public.pressing_commandes
   where entreprise_id = v_ent and date_depot::date = current_date
     and statut <> 'ANNULEE';

  select count(*) into v_en_cours
    from public.pressing_commandes
   where entreprise_id = v_ent
     and statut in ('EN_TRAITEMENT', 'PRETE', 'PARTIELLEMENT_REMISE');

  select count(*) into v_vetements
    from public.pressing_lignes l
    join public.pressing_commandes c on c.id = l.commande_id
   where l.entreprise_id = v_ent and l.remis_le is null
     and c.statut <> 'ANNULEE';

  select count(*) into v_prets
    from public.pressing_lignes l
    join public.pressing_commandes c on c.id = l.commande_id
    left join public.pressing_etapes e
           on e.entreprise_id = l.entreprise_id and e.code = l.etape_code
   where l.entreprise_id = v_ent and l.remis_le is null
     and c.statut <> 'ANNULEE'
     and coalesce(e.est_finale, l.etape_code = 'PRET');

  select count(*) into v_partiels
    from public.pressing_commandes
   where entreprise_id = v_ent and statut = 'PARTIELLEMENT_REMISE';

  select count(*) into v_remises
    from public.pressing_commandes
   where entreprise_id = v_ent and statut = 'REMISE'
     and date_depot::date between v_debut and v_fin;

  select count(*) into v_retard
    from public.pressing_commandes
   where entreprise_id = v_ent
     and statut not in ('REMISE', 'ANNULEE')
     and date_prevue is not null and date_prevue < now();

  -- Prêtes depuis plus de 7 jours et jamais récupérées.
  select count(distinct c.id) into v_non_recup
    from public.pressing_commandes c
    join public.pressing_lignes l on l.commande_id = c.id
   where c.entreprise_id = v_ent
     and c.statut in ('PRETE', 'PARTIELLEMENT_REMISE')
     and l.remis_le is null
     and c.date_prevue is not null
     and c.date_prevue < now() - interval '7 days';

  -- 💰 Facturé ≠ encaissé : deux chiffres distincts, jamais confondus.
  select coalesce(sum(total), 0) into v_facture
    from public.pressing_commandes
   where entreprise_id = v_ent and statut <> 'ANNULEE'
     and date_depot::date between v_debut and v_fin;

  select coalesce(sum(montant), 0) into v_encaisse
    from public.pressing_paiements
   where entreprise_id = v_ent and annule_le is null
     and encaisse_le::date between v_debut and v_fin;

  select coalesce(sum(greatest(total - montant_paye, 0)), 0) into v_du
    from public.pressing_commandes
   where entreprise_id = v_ent and statut <> 'ANNULEE';

  return jsonb_build_object(
    'debut', v_debut,
    'fin', v_fin,
    'commandes_aujourdhui', v_aujourdhui,
    'commandes_en_cours', v_en_cours,
    'vetements_en_traitement', v_vetements,
    'vetements_prets', v_prets,
    'commandes_partielles', v_partiels,
    'commandes_remises', v_remises,
    'commandes_en_retard', v_retard,
    'commandes_non_recuperees', v_non_recup,
    'montant_facture', v_facture,
    'montant_encaisse', v_encaisse,
    'montant_du', v_du
  );
end;
$$;

comment on function public.pressing_tableau_bord(date, date) is
  'Module 35 — indicateurs du pressing (commandes, vêtements, retards, facturé / encaissé / dû) sur une période.';

revoke all on function public.pressing_tableau_bord(date, date) from public, anon;
grant execute on function public.pressing_tableau_bord(date, date) to authenticated;


-- ============================================================================
--  6. RPC — COMMANDES EN RETARD / NON RÉCUPÉRÉES
-- ============================================================================

create or replace function public.pressing_commandes_en_retard(
  p_jours  integer default 0,
  p_limite integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id,
           'numero', c.numero,
           'client_nom', c.client_nom,
           'client_telephone', c.client_telephone,
           'statut', c.statut,
           'date_depot', c.date_depot,
           'date_prevue', c.date_prevue,
           'jours_retard', greatest(
              extract(day from (now() - c.date_prevue))::integer, 0),
           'solde', greatest(c.total - c.montant_paye, 0),
           'vetements_non_remis', (
             select count(*) from public.pressing_lignes l
              where l.commande_id = c.id and l.remis_le is null)
         ) order by c.date_prevue), '[]'::jsonb)
    into v_rows
    from public.pressing_commandes c
   where c.entreprise_id = v_ent
     and c.statut not in ('REMISE', 'ANNULEE')
     and c.date_prevue is not null
     and c.date_prevue < now() - (greatest(coalesce(p_jours, 0), 0) || ' days')::interval
   limit greatest(coalesce(p_limite, 100), 1);

  return v_rows;
end;
$$;

comment on function public.pressing_commandes_en_retard(integer, integer) is
  'Module 35 — commandes dont la date de récupération est dépassée (filtre en jours).';

revoke all on function public.pressing_commandes_en_retard(integer, integer)
  from public, anon;
grant execute on function public.pressing_commandes_en_retard(integer, integer)
  to authenticated;


-- ============================================================================
--  VÉRIFICATIONS
-- ============================================================================

-- V1. Tables de l'étape 3 (attendu : 2).
select count(*) as tables_etape3
  from information_schema.tables
 where table_schema = 'public'
   and table_name in ('pressing_retraits', 'pressing_retrait_lignes');

-- V2. Un vêtement ne peut être remis qu'une fois (attendu : 1 index unique).
select count(*) as index_unicite_remise
  from pg_indexes
 where schemaname = 'public'
   and indexname = 'idx_pressing_retrait_lignes_unique';

-- V3. Les RPC de l'étape 3 présentes.
select proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and proname in ('pressing_paiement_ajouter', 'pressing_paiement_annuler',
                   'pressing_retrait_enregistrer', 'pressing_retraits_lister',
                   'pressing_tableau_bord', 'pressing_commandes_en_retard',
                   'pressing_recalc_paye')
 order by proname;
