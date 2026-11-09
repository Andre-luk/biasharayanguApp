-- ============================================================================
--  biashara_yangu — MODULE 34 : RETOUR DE MARCHANDISE SUR UN AVOIR
--  ---------------------------------------------------------------------------
--  CE QUE LE PROPRIÉTAIRE DEMANDE
--    « Quand je fais un avoir pour un retour, la marchandise revient en
--      boutique : il faut la remettre en stock — et je ne connais pas
--      toujours le prix d'achat. »
--
--  CE QUE CE SCRIPT AJOUTE
--    `avoir_retour_stock(p_note_id, p_lignes)` :
--      p_lignes = [{"produit_id": 12, "quantite": 3, "prix_achat": 800}, …]
--      • "quantite" est exprimée en UNITÉS DE BASE (jamais en fardes) ;
--      • "prix_achat" est FACULTATIF (0 si inconnu) ;
--      • le stock remonte par la fonction officielle d'approvisionnement,
--        donc avec le même contrôle de droits et la même traçabilité ;
--      • l'opération est liée à l'avoir (référence) et journalisée.
--
--  ⚠️ RÈGLES
--    • On ne peut réintégrer du stock QUE sur un avoir ÉMIS (pas annulé).
--    • Un même avoir ne peut pas servir deux fois pour le même article :
--      `retour_stock_le` est posé sur l'avoir.
--    • Réservé au propriétaire (ou à la plateforme).
--    • IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

alter table public.notes_credit
  add column if not exists retour_stock_le timestamptz;

comment on column public.notes_credit.retour_stock_le is
  'Module 34 — date à laquelle la marchandise de cet avoir a été remise en stock (NULL = pas encore).';


create or replace function public.avoir_retour_stock(
  p_note_id uuid,
  p_lignes  jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user   uuid := auth.uid();
  v_note   public.notes_credit%rowtype;
  v_ligne  jsonb;
  v_prod   bigint;
  v_qte    numeric;
  v_prix   numeric;
  v_n      integer := 0;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select * into v_note from public.notes_credit where id = p_note_id for update;
  if not found then
    raise exception 'AVOIR_INTROUVABLE|Cet avoir n''existe pas.';
  end if;

  if not (v_user = v_note.entreprise_id
          or v_user = public.mon_proprietaire()
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire peut remettre en stock.';
  end if;

  if v_note.statut <> 'EMIS' then
    raise exception 'AVOIR_ANNULE|Cet avoir est annulé : aucun retour possible.';
  end if;

  if v_note.retour_stock_le is not null then
    raise exception 'RETOUR_DEJA_FAIT|La marchandise de cet avoir a déjà été remise en stock le %.',
      to_char(v_note.retour_stock_le, 'DD/MM/YYYY');
  end if;

  if p_lignes is null
     or jsonb_typeof(p_lignes) <> 'array'
     or jsonb_array_length(p_lignes) = 0 then
    raise exception 'LIGNE_INVALIDE|Indiquez au moins un article à remettre en stock.';
  end if;

  for v_ligne in select * from jsonb_array_elements(p_lignes)
  loop
    v_prod := nullif(v_ligne->>'produit_id', '')::bigint;
    v_qte  := coalesce((v_ligne->>'quantite')::numeric, 0);
    -- 💰 Prix d'achat FACULTATIF : 0 si le commerçant ne le connaît pas.
    v_prix := coalesce(nullif(v_ligne->>'prix_achat', '')::numeric, 0);

    if v_prod is null then
      raise exception 'LIGNE_INVALIDE|Une ligne de retour n''a pas d''article.';
    end if;
    if v_qte <= 0 then
      raise exception 'LIGNE_INVALIDE|Quantité de retour invalide pour l''article %.', v_prod;
    end if;
    if v_prix < 0 then
      raise exception 'PRIX_INVALIDE|Le prix d''achat ne peut pas être négatif.';
    end if;

    -- Le stock remonte par la fonction officielle : mêmes droits, même
    -- traçabilité, même mouvement d'approvisionnement.
    perform public.rpc_stock_approvisionner(
      p_produit_id        => v_prod,
      p_quantite          => v_qte,
      p_prix_achat_unitaire => v_prix,
      p_fournisseur       => 'Retour avoir ' || v_note.numero,
      p_date_approvisionnement => now()
    );

    v_n := v_n + 1;
  end loop;

  update public.notes_credit
     set retour_stock_le = now()
   where id = p_note_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_note.entreprise_id, 'AVOIR_RETOUR_STOCK', v_user,
    jsonb_build_object(
      'avoir', v_note.numero,
      'lignes', p_lignes,
      'nb_lignes', v_n
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'avoir', v_note.numero,
    'nb_lignes', v_n
  );
end;
$$;

comment on function public.avoir_retour_stock(uuid, jsonb) is
  'Module 34 — remet en stock la marchandise rendue d''un avoir (prix d''achat facultatif), une seule fois par avoir.';

revoke all on function public.avoir_retour_stock(uuid, jsonb) from public, anon;
grant execute on function public.avoir_retour_stock(uuid, jsonb) to authenticated;


-- ============================================================================
--  2. LA LISTE DES AVOIRS INDIQUE SI LA MARCHANDISE EST REVENUE
--     (sans quoi l'écran ne peut pas savoir quelles avoirs sont encore
--      « à remettre en stock ».)
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
               'retour_stock_le', n.retour_stock_le,
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
--  VÉRIFICATION
-- ============================================================================

select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('avoir_retour_stock', 'note_credit_lister')
 order by p.proname;
