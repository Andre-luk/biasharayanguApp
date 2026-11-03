-- =============================================================================
-- MODULE 24 — COMPLÉMENTS DE LA DISTRIBUTION
-- =============================================================================
-- Ce script complète la migration `20260916000100_module24_distribution_gestion.sql`
-- (déjà exécutée) avec deux briques réclamées par le cahier des charges :
--
--   1. `dist_reception_intrants_refuser` : la DOUBLE CONFIRMATION d'une
--      réception n'a de sens que si le gérant peut aussi REFUSER une
--      réception erronée — avec un motif obligatoire (tracé au journal).
--      (La table `dist_receptions` acceptait déjà le statut `refusee`,
--      aucun RPC ne l'écrivait.)
--
--   2. `dist_journal_lister` : vue de TRAÇABILITÉ centrale — qui a fait
--      quoi, quand, sur quelle entité (table `dist_journal` alimentée par
--      `dist_journaliser`). Aucune donnée n'est modifiable par ce biais.
--
-- Idempotent : `create or replace`, rien n'est supprimé, aucune donnée
-- existante n'est touchée.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Refus d'une réception d'intrants (gérant/propriétaire)
-- -----------------------------------------------------------------------------
create or replace function public.dist_reception_intrants_refuser(
  p_reception uuid,
  p_motif     text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid := public.dist_owner_requis();
  v_rec   record;
  v_motif text := btrim(coalesce(p_motif, ''));
begin
  perform public.dist_exige(array['gerant', 'proprietaire']);

  if length(v_motif) < 3 then
    raise exception 'MOTIF_REQUIS|Indiquez pourquoi cette réception est refusée (3 caractères minimum).';
  end if;

  select * into v_rec
    from public.dist_receptions
   where id = p_reception and owner_id = v_owner
   for update;

  if v_rec.id is null then
    raise exception 'RECEPTION_INTROUVABLE|Cette réception n''existe pas.';
  end if;

  if v_rec.statut <> 'attente_gerant' then
    raise exception 'STATUT_INVALIDE|Cette réception a déjà été traitée.';
  end if;

  -- Aucun stock n'est touché : la réception n'a jamais été validée.
  update public.dist_receptions
     set statut       = 'refusee',
         confirme_par = auth.uid(),
         confirme_le  = now(),
         motif        = v_motif
   where id = p_reception;

  perform public.dist_journaliser(
    v_owner, 'RECEPTION_INTRANTS_REFUSEE', 'dist_receptions', p_reception,
    jsonb_build_object('numero', v_rec.numero, 'motif', v_motif));

  return jsonb_build_object('ok', true, 'statut', 'refusee');
end;
$$;

comment on function public.dist_reception_intrants_refuser(uuid, text) is
  'Module 24 — refus motivé d''une réception d''intrants en attente du gérant.';

-- -----------------------------------------------------------------------------
-- 2. Journal de traçabilité (lecture seule, tous les membres de la distribution)
-- -----------------------------------------------------------------------------
create or replace function public.dist_journal_lister(
  p_action text default null,
  p_limite integer default 150
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner  uuid := public.dist_owner_requis();
  v_role   text := public.dist_role();
  v_filtre text := nullif(btrim(coalesce(p_action, '')), '');
  v_limite integer := least(greatest(coalesce(p_limite, 150), 1), 500);
  v_items  jsonb;
begin
  if v_role = 'aucun' then
    raise exception 'ACCES_REFUSE|Vous n''êtes pas membre de cette distribution.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',         j.id,
           'action',     j.action,
           'entite',     j.entite,
           'entite_id',  j.entite_id,
           'details',    j.details,
           'auteur',     nullif(btrim(coalesce(u.prenom, '') || ' ' ||
                                      coalesce(u.nom, '')), ''),
           'role',       u.role_distribution,
           'created_at', j.created_at
         ) order by j.created_at desc), '[]'::jsonb)
    into v_items
    from (
      select j0.*
        from public.dist_journal j0
       where j0.owner_id = v_owner
         and (v_filtre is null or j0.action = v_filtre)
       order by j0.created_at desc
       limit v_limite
    ) j
    left join public.utilisateurs u on u.id = j.auteur_id;

  return jsonb_build_object('ok', true, 'items', v_items);
end;
$$;

comment on function public.dist_journal_lister(text, integer) is
  'Module 24 — journal de traçabilité de la distribution (lecture seule).';

-- -----------------------------------------------------------------------------
-- 3. Privilèges
-- -----------------------------------------------------------------------------
revoke all on function public.dist_reception_intrants_refuser(uuid, text)
  from public, anon;
grant execute on function public.dist_reception_intrants_refuser(uuid, text)
  to authenticated;

revoke all on function public.dist_journal_lister(text, integer)
  from public, anon;
grant execute on function public.dist_journal_lister(text, integer)
  to authenticated;

-- =============================================================================
-- FIN — Module 24, compléments
-- =============================================================================
