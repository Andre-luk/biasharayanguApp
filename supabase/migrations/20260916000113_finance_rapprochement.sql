-- ============================================================================
--  biashara_yangu — MODULE 27 (suite) : TABLEAU DE BORD FINANCIER ET
--  RAPPROCHEMENT DES PAIEMENTS MOBILE MONEY
--  ---------------------------------------------------------------------------
--  CE QUE LE PROPRIÉTAIRE DEMANDE
--    « Un tableau de bord Finance / Super Admin : ce qui a été facturé, ce qui
--      a été réellement encaissé, ce qui reste dû — et pouvoir pointer chaque
--      transaction Mobile Money par rapport au relevé du prestataire. »
--
--  CE QUE CE SCRIPT AJOUTE
--    1. `finance_abonnements_entreprises(...)` : la situation financière
--       entreprise par entreprise (facturé, encaissé, dû, collaborateurs,
--       dernier paiement). C'est le dossier complet demandé.
--    2. `finance_serdipay_rapprocher(...)` : marque (ou dé-marque) une
--       transaction comme rapprochée du relevé SerdiPay. Écrit `rapproche_le`
--       et `rapproche_par`, et journalise l'opération.
--
--  ⚠️ RÈGLES RESPECTÉES
--    • Aucune valeur inventée : un champ inconnu vaut `null`.
--    • Aucune écriture financière cachée : le rapprochement ne modifie AUCUN
--      montant ni statut d'abonnement, il ne fait que tracer un contrôle.
--    • Accès réservé plateforme / Finance (mêmes droits que la migration 111).
--    • IDEMPOTENT : ré-exécutable sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. SITUATION FINANCIÈRE, ENTREPRISE PAR ENTREPRISE
-- ============================================================================

create or replace function public.finance_abonnements_entreprises(
  p_recherche text default null,
  p_statut    text default null,
  p_limite    integer default 200
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_like text;
  v_rows jsonb;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.est_plateforme()
          or public.peut('finance', 'voir')
          or public.peut('abonnements', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter les finances de la plateforme.';
  end if;

  v_like := nullif(btrim(coalesce(p_recherche, '')), '');

  select coalesce(jsonb_agg(x order by x->>'nom'), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
               'entreprise_id', e.id,
               'nom', e.nom,
               'statut', e.statut,
               'devise', coalesce(e.devise, 'CDF'),
               'echeance', e.date_expiration,
               'jours_restants', case
                 when e.date_expiration is null then null
                 else greatest(
                   ceil(extract(epoch from (e.date_expiration - now())) / 86400),
                   0
                 )::int
               end,
               'montant_facture', round(coalesce(e.montant_total_du, 0), 2),
               'montant_encaisse', round(coalesce(e.montant_deja_paye, 0), 2),
               'solde_du', round(greatest(
                 coalesce(e.montant_total_du, 0)
                 - coalesce(e.montant_deja_paye, 0), 0), 2),
               'supplement_collaborateurs',
                 round(coalesce(e.supplement_collaborateurs, 0), 2),
               'collaborateurs', (
                 select count(distinct u.id) from public.utilisateurs u
                  where u.id <> e.id
                    and coalesce(u.valide, 1) <> 0
                    and lower(coalesce(u.role, '')) not in (
                      'admin', 'super_admin', 'plateforme')
                    and (u.entreprise_id = e.id
                         or u.parent_id = e.id::text)
               ),
               'dernier_paiement', (
                 select p.created_at
                   from public.paiements_abonnements_laperle p
                  where p.entreprise_id = e.id
                  order by p.created_at desc
                  limit 1
               ),
               'total_paiements', (
                 select count(*) from public.paiements_abonnements_laperle p
                  where p.entreprise_id = e.id
               ),
               'serdipay_en_attente', (
                 select count(*) from public.paiements_serdipay s
                  where s.entreprise_id = e.id
                    and s.statut = 'en_attente'
               )
             ) as x
        from public.entreprises e
       where (v_like is null or e.nom ilike '%' || v_like || '%')
         and (nullif(btrim(coalesce(p_statut, '')), '') is null
              or e.statut = p_statut)
       order by e.nom
       limit greatest(coalesce(p_limite, 200), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.finance_abonnements_entreprises(text, text, integer) is
  'Module 27 — dossier financier par entreprise : facturé, encaissé, dû, suppléments collaborateurs, dernier paiement, transactions Mobile Money en attente.';

revoke all on function public.finance_abonnements_entreprises(text, text, integer)
  from public, anon;
grant execute on function public.finance_abonnements_entreprises(text, text, integer)
  to authenticated;


-- ============================================================================
--  2. RAPPROCHEMENT AVEC LE RELEVÉ SERDIPAY
-- ============================================================================
--  `p_rapproche = true`  → la transaction est pointée (elle apparaît sur le
--                          relevé du prestataire).
--  `p_rapproche = false` → on annule le pointage (erreur de saisie).
--
--  Aucun montant, aucun statut, aucun abonnement n'est modifié.

create or replace function public.finance_serdipay_rapprocher(
  p_id        uuid,
  p_rapproche boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_s    public.paiements_serdipay%rowtype;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.est_plateforme()
          or public.peut('finance', 'modifier')
          or public.peut('finance', 'voir')) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de rapprocher les paiements.';
  end if;

  select * into v_s from public.paiements_serdipay where id = p_id;
  if not found then
    raise exception 'TRANSACTION_INTROUVABLE|Cette transaction n''existe pas.';
  end if;

  if coalesce(p_rapproche, true) then
    update public.paiements_serdipay
       set rapproche_le  = coalesce(rapproche_le, now()),
           rapproche_par = coalesce(rapproche_par, v_user)
     where id = p_id;
  else
    update public.paiements_serdipay
       set rapproche_le = null,
           rapproche_par = null
     where id = p_id;
  end if;

  select * into v_s from public.paiements_serdipay where id = p_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_s.entreprise_id,
    case when coalesce(p_rapproche, true)
         then 'SERDIPAY_RAPPROCHE' else 'SERDIPAY_RAPPROCHE_ANNULE' end,
    v_user,
    jsonb_build_object(
      'paiement_serdipay', v_s.id,
      'reference', v_s.reference,
      'reference_fournisseur', v_s.provider_reference,
      'montant', v_s.montant,
      'statut', v_s.statut
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'id', v_s.id,
    'rapproche', v_s.rapproche_le is not null,
    'rapproche_le', v_s.rapproche_le
  );
end;
$$;

comment on function public.finance_serdipay_rapprocher(uuid, boolean) is
  'Module 27 — pointe ou dé-pointe une transaction Mobile Money par rapport au relevé du prestataire. Ne modifie aucun montant.';

revoke all on function public.finance_serdipay_rapprocher(uuid, boolean)
  from public, anon;
grant execute on function public.finance_serdipay_rapprocher(uuid, boolean)
  to authenticated;


-- ============================================================================
--  3. VÉRIFICATION
-- ============================================================================

select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('finance_abonnements_entreprises',
                     'finance_serdipay_rapprocher')
 order by p.proname;
