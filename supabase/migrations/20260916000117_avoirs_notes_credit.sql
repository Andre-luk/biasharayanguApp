-- ============================================================================
--  biashara_yangu — MODULE 32 : AVOIR / NOTE DE CRÉDIT
--  ---------------------------------------------------------------------------
--  CE QUE LE PROPRIÉTAIRE DEMANDE
--    « Quand une facture est déjà émise et qu'il faut rendre de l'argent au
--      client (retour, erreur de prix, article défectueux), je dois produire
--      un AVOIR — sans annuler la vente d'origine. »
--
--  PRINCIPE COMPTABLE (important)
--    Une vente validée n'est JAMAIS supprimée ni modifiée. On émet un
--    document séparé, numéroté `AV-AAAAMMJJ-NNNN`, qui vient en déduction.
--    Une vente + ses avoirs doivent rester lisibles dans le temps.
--
--  CE QUE CE SCRIPT AJOUTE
--    1. `notes_credit` — l'avoir : montant, motif, type, auteur, statut.
--    2. `note_credit_creer(...)` — vérifie les plafonds puis numérote.
--    3. `note_credit_lister(...)` / `note_credit_annuler(...)`.
--
--  ⚠️ RÈGLES
--    • Le montant total des avoirs d'une vente ne peut JAMAIS dépasser le
--      montant de cette vente (contrôle sous verrou).
--    • Un avoir ne modifie AUCUN stock : le retour de marchandise se traite
--      par une entrée de stock séparée (approvisionnement).
--    • Annulation douce : une ligne d'avoir n'est jamais supprimée, seulement
--      marquée ANNULE (avec son motif et son auteur).
--    • Réservé au propriétaire (ou à la plateforme) : c'est de l'argent.
--    • IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA TABLE DES AVOIRS
-- ============================================================================

create table if not exists public.notes_credit (
  id             uuid primary key default gen_random_uuid(),
  entreprise_id  uuid not null,
  numero         text not null,
  -- Vente d'origine (facultative : on peut créditer sans référence).
  vente_id       uuid,
  facture_numero text,
  client_id      uuid,
  client_nom     text,
  client_telephone text,
  montant        numeric(14, 2) not null check (montant > 0),
  devise         text not null default 'CDF',
  -- AVOIR = somme à valoir ; REMBOURSEMENT = argent rendu au client.
  type_avoir     text not null default 'AVOIR',
  mode_remboursement text,
  motif          text,
  statut         text not null default 'EMIS',
  cree_par       uuid,
  created_at     timestamptz not null default now(),
  annule_le      timestamptz,
  annule_par     uuid,
  motif_annulation text
);

do $$
begin
  alter table public.notes_credit
    add constraint chk_notes_credit_type
    check (type_avoir in ('AVOIR', 'REMBOURSEMENT')) not valid;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter table public.notes_credit
    add constraint chk_notes_credit_statut
    check (statut in ('EMIS', 'ANNULE')) not valid;
exception when duplicate_object then null;
end $$;

create unique index if not exists idx_notes_credit_numero
  on public.notes_credit (entreprise_id, numero);

create index if not exists idx_notes_credit_entreprise
  on public.notes_credit (entreprise_id, created_at desc);

create index if not exists idx_notes_credit_vente
  on public.notes_credit (vente_id)
  where vente_id is not null;

comment on table public.notes_credit is
  'Module 32 — avoirs (notes de crédit). Un avoir ne supprime jamais la vente d''origine : il vient en déduction.';

alter table public.notes_credit enable row level security;

drop policy if exists notes_credit_lecture on public.notes_credit;
create policy notes_credit_lecture on public.notes_credit
  for select
  using (
    entreprise_id = auth.uid()
    or public.est_plateforme()
  );


-- ============================================================================
--  2. NUMÉROTATION  « AV-AAAAMMJJ-NNNN »
-- ============================================================================

create or replace function public.note_credit_prochain_numero(p_entreprise uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_jour  text := to_char(current_date, 'YYYYMMDD');
  v_n     integer;
begin
  select count(*) + 1
    into v_n
    from public.notes_credit
   where entreprise_id = p_entreprise
     and created_at::date = current_date;

  return 'AV-' || v_jour || '-' || lpad(v_n::text, 4, '0');
end;
$$;

comment on function public.note_credit_prochain_numero(uuid) is
  'Module 32 — numéro d''avoir du jour (AV-AAAAMMJJ-NNNN), par boutique.';


-- ============================================================================
--  3. CRÉER UN AVOIR
-- ============================================================================

create or replace function public.note_credit_creer(
  p_montant        numeric,
  p_motif          text default null,
  p_type           text default 'AVOIR',
  p_vente_id       uuid default null,
  p_facture_numero text default null,
  p_client_id      uuid default null,
  p_client_nom     text default null,
  p_client_tel     text default null,
  p_mode           text default null,
  p_entreprise     uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_owner  uuid;
  v_id     uuid;
  v_type   text := upper(coalesce(nullif(btrim(p_type), ''), 'AVOIR'));
  v_vente  public.ventes%rowtype;
  v_deja   numeric := 0;
  v_total  numeric := 0;
  v_numero text;
  v_note   public.notes_credit%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_owner := public.mon_proprietaire();
  v_id := coalesce(p_entreprise, public.mon_entreprise_id(), v_owner, v_user);

  -- 💰 C'est de l'argent : seul le patron (ou la plateforme) émet un avoir.
  if not (v_user = v_owner or v_user = v_id or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut émettre un avoir.';
  end if;

  if coalesce(p_montant, 0) <= 0 then
    raise exception 'MONTANT_INVALIDE|Le montant de l''avoir doit être supérieur à zéro.';
  end if;

  if v_type not in ('AVOIR', 'REMBOURSEMENT') then
    raise exception 'TYPE_INVALIDE|Type d''avoir inconnu : utilisez AVOIR ou REMBOURSEMENT.';
  end if;

  -- 🔒 PLAFOND : les avoirs d'une vente ne peuvent pas dépasser la vente.
  if p_vente_id is not null then
    select * into v_vente
      from public.ventes
     where id = p_vente_id
       for update;

    if not found then
      raise exception 'VENTE_INTROUVABLE|La vente d''origine n''existe pas.';
    end if;

    if v_vente.owner_id is distinct from v_id and not public.est_plateforme() then
      raise exception 'DROIT_REFUSE|Cette vente n''appartient pas à votre boutique.';
    end if;

    select coalesce(sum(montant), 0)
      into v_deja
      from public.notes_credit
     where vente_id = p_vente_id
       and statut = 'EMIS';

    v_total := coalesce(v_vente.prix, 0)
             + coalesce((
                 select sum(v2.prix)
                   from public.ventes v2
                  where v2.vente_uuid = v_vente.vente_uuid
               ), 0);

    -- Le contrôle porte sur la ligne de vente concernée : on ne peut pas
    -- rembourser plus que ce qui a été encaissé.
    if v_deja + p_montant > coalesce(v_vente.prix, 0) + 0.01 then
      raise exception 'AVOIR_SUPERIEUR|Le total des avoirs dépasse le montant de la vente (% restant).',
        round(coalesce(v_vente.prix, 0) - v_deja, 2);
    end if;
  end if;

  v_numero := public.note_credit_prochain_numero(v_id);

  insert into public.notes_credit (
    entreprise_id, numero, vente_id, facture_numero,
    client_id, client_nom, client_telephone,
    montant, devise, type_avoir, mode_remboursement, motif,
    statut, cree_par
  ) values (
    v_id, v_numero, p_vente_id, nullif(btrim(coalesce(p_facture_numero,'')),''),
    p_client_id, nullif(btrim(coalesce(p_client_nom,'')),''),
    nullif(btrim(coalesce(p_client_tel,'')),''),
    round(p_montant, 2),
    coalesce((select e.devise from public.entreprises e where e.id = v_id), 'CDF'),
    v_type,
    nullif(btrim(coalesce(p_mode,'')),''),
    nullif(btrim(coalesce(p_motif,'')),''),
    'EMIS', v_user
  )
  returning * into v_note;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_id, 'AVOIR_EMIS', v_user,
    jsonb_build_object(
      'numero', v_note.numero,
      'montant', v_note.montant,
      'type', v_note.type_avoir,
      'vente_id', p_vente_id,
      'motif', v_note.motif
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_note.id,
    'numero', v_note.numero,
    'montant', v_note.montant,
    'devise', v_note.devise,
    'type', v_note.type_avoir,
    'statut', v_note.statut,
    'created_at', v_note.created_at
  );
end;
$$;

comment on function public.note_credit_creer(numeric, text, text, uuid, text, uuid, text, text, text, uuid) is
  'Module 32 — émet un avoir : plafonné au montant de la vente d''origine, numéroté AV-AAAAMMJJ-NNNN, journalisé. Ne modifie ni la vente ni le stock.';

revoke all on function public.note_credit_creer(numeric, text, text, uuid, text, uuid, text, text, text, uuid)
  from public, anon;
grant execute on function public.note_credit_creer(numeric, text, text, uuid, text, text, uuid, text, text, text, uuid)
  to authenticated;


-- ============================================================================
--  4. LISTER
-- ============================================================================

create or replace function public.note_credit_lister(
  p_debut     date default null,
  p_fin       date default null,
  p_recherche text default null,
  p_limite    integer default 100
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_id    uuid;
  v_like  text;
  v_rows  jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  v_id := coalesce(public.mon_entreprise_id(), public.mon_proprietaire(), v_user);
  v_like := nullif(btrim(coalesce(p_recherche, '')), '');

  select coalesce(jsonb_agg(x order by x->>'date' desc), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
               'id', n.id,
               'numero', n.numero,
               'vente_id', n.vente_id,
               'facture_numero', n.facture_numero,
               'client_nom', n.client_nom,
               'client_telephone', n.client_telephone,
               'montant', n.montant,
               'devise', n.devise,
               'type', n.type_avoir,
               'mode_remboursement', n.mode_remboursement,
               'motif', n.motif,
               'statut', n.statut,
               'annule_le', n.annule_le,
               'motif_annulation', n.motif_annulation,
               'date', n.created_at,
               'auteur', (select nullif(btrim(concat_ws(' ', u.prenom, u.nom)), '')
                            from public.utilisateurs u where u.id = n.cree_par)
             ) as x
        from public.notes_credit n
       where (n.entreprise_id = v_id or public.est_plateforme())
         and (p_debut is null or n.created_at::date >= p_debut)
         and (p_fin is null or n.created_at::date <= p_fin)
         and (v_like is null
              or coalesce(n.numero, '') ilike '%' || v_like || '%'
              or coalesce(n.facture_numero, '') ilike '%' || v_like || '%'
              or coalesce(n.client_nom, '') ilike '%' || v_like || '%'
              or coalesce(n.motif, '') ilike '%' || v_like || '%')
       order by n.created_at desc
       limit greatest(coalesce(p_limite, 100), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.note_credit_lister(date, date, text, integer) is
  'Module 32 — liste des avoirs de la boutique (période, recherche libre).';

revoke all on function public.note_credit_lister(date, date, text, integer)
  from public, anon;
grant execute on function public.note_credit_lister(date, date, text, integer)
  to authenticated;


-- ============================================================================
--  5. ANNULER (jamais supprimer)
-- ============================================================================

create or replace function public.note_credit_annuler(
  p_id    uuid,
  p_motif text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_note public.notes_credit%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select * into v_note from public.notes_credit where id = p_id for update;
  if not found then
    raise exception 'AVOIR_INTROUVABLE|Cet avoir n''existe pas.';
  end if;

  if not (v_user = v_note.entreprise_id
          or v_user = public.mon_proprietaire()
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut annuler un avoir.';
  end if;

  if v_note.statut = 'ANNULE' then
    return jsonb_build_object(
      'ok', true, 'id', v_note.id, 'statut', 'ANNULE',
      'deja_annule', true
    );
  end if;

  update public.notes_credit
     set statut = 'ANNULE',
         annule_le = now(),
         annule_par = v_user,
         motif_annulation = nullif(btrim(coalesce(p_motif, '')), '')
   where id = p_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_note.entreprise_id, 'AVOIR_ANNULE', v_user,
    jsonb_build_object(
      'numero', v_note.numero,
      'montant', v_note.montant,
      'motif', nullif(btrim(coalesce(p_motif, '')), '')
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'id', p_id, 'statut', 'ANNULE');
end;
$$;

comment on function public.note_credit_annuler(uuid, text) is
  'Module 32 — annule un avoir sans le supprimer (traçabilité conservée).';

revoke all on function public.note_credit_annuler(uuid, text) from public, anon;
grant execute on function public.note_credit_annuler(uuid, text) to authenticated;


-- ============================================================================
--  6. VÉRIFICATION
-- ============================================================================

select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('note_credit_creer',
                     'note_credit_lister',
                     'note_credit_annuler',
                     'note_credit_prochain_numero')
 order by p.proname;
