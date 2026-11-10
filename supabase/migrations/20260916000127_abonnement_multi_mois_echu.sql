-- ============================================================================
--  BIASHARA YANGU — MIGRATION 127
--  PAYER PLUSIEURS MOIS QUAND L'ABONNEMENT EST DÉJÀ ÉCHU
--  ---------------------------------------------------------------------------
--  BUG REEL (10/11/2026)
--    `abonnement_ouvrir_avance_multi(id, 3)` écrivait bien 30 000 à payer
--    (10 000 × 3) mais laissait le dossier en statut `EXPIRE`. Or le moteur
--    (`rpc_abonnement_enregistrer_paiement`) RECALCULE le total d'un cycle
--    dès que le statut est `EXPIRE` :

--      if v_solde <= 0 or v_statut_avant = 'EXPIRE' then
--        v_total := prix_abonnement_mensuel;   -- 10 000
--        v_solde := v_total;
--      end if;
--      if p_montant > v_solde + 0.001 then raise 'MONTANT_SUPERIEUR';

--    Résultat : un client échu qui paie 3 mois envoyer 30 000 chez SerdiPay,
--    l'argent est encaissé, puis le crédit est REFUSÉ (MONTANT_SUPERIEUR) et
--    la transaction reste `en_attente`.
--
--  CORRECTION
--    Quand le dossier est échu, la fonction le place en
--    `EN_ATTENTE_COMPLEMENT` — exactement ce que fait déjà
--    `rpc_abonnement_preparer_renouvellement` pour UN cycle. Le moteur ne
--    recalcule alors plus rien : il crédite le montant figé et prolonge de
--    « durée × mois » jours (ici 30 × 3 = 90).
--
--    ⚠️ Un dossier SUSPENDU n'est jamais réactivé par cette fonction : la
--       suspension reste une décision de modération.
--
--  Aucun changement de signature, aucun écran à republier.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


create or replace function public.abonnement_ouvrir_avance_multi(
  p_entreprise uuid default null,
  p_mois       integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_owner uuid;
  v_id    uuid;
  v_e     public.entreprises%rowtype;
  v_mois  integer := greatest(1, least(coalesce(p_mois, 1), 12));
  v_base  numeric := 0;
  v_supp  numeric := 0;
  v_cycle numeric := 0;
  v_total numeric := 0;
  v_solde numeric := 0;
  v_echu  boolean := false;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour payer votre abonnement.';
  end if;

  v_owner := public.mon_proprietaire();
  v_id := coalesce(p_entreprise, public.mon_entreprise_id(), v_owner, v_user);

  select * into v_e from public.entreprises where id = v_id for update;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  if not (v_user = v_e.id
          or v_user = v_owner
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
  end if;

  v_solde := coalesce(v_e.solde_restant, 0);

  -- Un montant est déjà réclamé : on n'ouvre rien, on laisse payer celui-là.
  if v_solde > 0.009 then
    return jsonb_build_object(
      'ok', true,
      'ouvert', false,
      'motif', 'DEJA_DU',
      'mois', greatest(coalesce(v_e.cycles_prepayes, 1), 1),
      'montant', v_solde,
      'echeance', v_e.date_expiration,
      'devise', coalesce(v_e.devise, 'CDF')
    );
  end if;

  v_cycle := public.rpc_abonnement_prix_du_cycle(v_id);
  if v_cycle is null or v_cycle <= 0 then
    raise exception 'PRIX_ABSENT|Aucun prix d''abonnement n''est défini pour ce compte : contactez la plateforme.';
  end if;

  v_base  := public.abonnement_prix_base(v_id);
  v_supp  := public.abonnement_supplement_collaborateurs(v_id);
  -- 🔧 Le supplément collaborateurs fait partie du cycle (2 500 par
  --    collaborateur actif) : il est inclus dans le montant réclamé, sinon le
  --    moteur attend plus que ce que le client a payé.
  v_total := round((v_cycle + v_supp) * v_mois, 2);

  -- 🔧 CORRECTIF 127 : le dossier est-il échu ? Si oui, le moteur recalcule
  -- un seul cycle et refuserait le paiement multiple. On fige donc l'état
  -- « cycle ouvert, en attente de règlement » — le strict équivalent de
  -- `rpc_abonnement_preparer_renouvellement`, mais pour N cycles.
  -- Une suspension n'est JAMAIS levée ici.
  v_echu := v_e.statut <> 'SUSPENDU'
            and (
              v_e.statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
              or (v_e.date_expiration is not null and v_e.date_expiration < now())
            );

  update public.entreprises
     set montant_total_du          = v_total,
         montant_deja_paye         = 0,
         supplement_collaborateurs = round(v_supp * v_mois, 2),
         cycles_prepayes           = v_mois,
         statut                    = case
                                       when v_echu
                                         then 'EN_ATTENTE_COMPLEMENT'
                                              ::public.statut_abonnement_enum
                                       else statut
                                     end,
         updated_at                = now()
   where id = v_id;

  begin
    perform public.abonnement_photographier_periode(v_id, v_base * v_mois);
  exception when others then null;
  end;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_id, 'ABONNEMENT_AVANCE_MULTI_OUVERTE', v_user,
    jsonb_build_object(
      'mois', v_mois,
      'prix_cycle', v_cycle,
      'base', v_base,
      'supplement_collaborateurs', v_supp,
      'montant', v_total,
      'echeance_actuelle', v_e.date_expiration,
      'statut', v_e.statut,
      'statut_pose', case when v_echu then 'EN_ATTENTE_COMPLEMENT' else v_e.statut::text end
    ),
    now()
  );

  return jsonb_build_object(
    'ok', true,
    'ouvert', true,
    'motif', 'CYCLE_ANTICIPE',
    'mois', v_mois,
    'montant', v_total,
    'prix_cycle', v_cycle,
    'base', v_base,
    'supplement_collaborateurs', v_supp,
    'statut_avant', v_e.statut::text,
    'statut_apres', case when v_echu then 'EN_ATTENTE_COMPLEMENT' else v_e.statut::text end,
    'echeance', v_e.date_expiration,
    'jours_restants', case
      when v_e.date_expiration is null then null
      else greatest(ceil(extract(epoch from (v_e.date_expiration - now())) / 86400), 0)::int
    end,
    'devise', coalesce(v_e.devise, 'CDF')
  );
end;
$$;

comment on function public.abonnement_ouvrir_avance_multi(uuid, integer) is
  'Module 30 / correctifs 127-128 — ouvre N cycles à encaisser '
  '((prix du cycle + supplément collaborateurs) × mois). Passe un dossier échu '
  'en EN_ATTENTE_COMPLEMENT pour que le moteur crédite le montant figé et '
  'prolonge de durée × N jours. Ne lève jamais une suspension.';

revoke all on function public.abonnement_ouvrir_avance_multi(uuid, integer)
  from public, anon;
grant execute on function public.abonnement_ouvrir_avance_multi(uuid, integer)
  to authenticated;


-- ============================================================================
--  CONTRÔLE
-- ============================================================================

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'abonnement_ouvrir_avance_multi'
     and pg_get_function_identity_arguments(p.oid) = 'p_entreprise uuid, p_mois integer';

  if v_def is null then
    raise exception 'abonnement_ouvrir_avance_multi(uuid, integer) introuvable après la migration.';
  end if;

  if position('EN_ATTENTE_COMPLEMENT' in v_def) = 0 then
    raise exception 'Migration 127 incomplète : le statut échu n''est pas géré.';
  end if;

  raise notice 'Migration 127 OK : payer plusieurs mois fonctionne aussi sur un abonnement échu.';
end $$;
