-- ============================================================================
--  biashara_yangu — PHASE 9 : MODE SIMPLE — INSTALLATION OPTIONNELLE,
--                            ABONNEMENT OBLIGATOIRE
--  ---------------------------------------------------------------------------
--  RÈGLE MÉTIER demandée par le patron :
--
--    « Le client peut payer OU NE PAS payer l'installation, mais il est
--      OBLIGÉ de payer un abonnement. »
--
--  Traduction technique :
--    • l'installation est OPTIONNELLE : si `prix_installation` vaut 0 (ou
--      NULL), elle n'est jamais réclamée — le compte passe directement au
--      mensuel ;
--    • si elle est définie (> 0), elle est réclamée UNE SEULE FOIS, au
--      premier cycle PAYANT ;
--    • l'abonnement mensuel, lui, est OBLIGATOIRE : sans lui, l'accès reste
--      en lecture seule (statut EXPIRE / EN_ATTENTE_COMPLEMENT).
--
--  LE PROBLÈME QUE ÇA RÉSOUT
--  -------------------------
--  Le mode simple (`rpc_entreprise_creer_simple`, migration 0081) pose
--  `date_activation = now()` dès l'inscription pour activer l'essai de 7 jours.
--  Le moteur en conclut « compte déjà activé » (correctif 60) et facture donc
--  le MENSUEL dès la fin de l'essai : l'installation n'était JAMAIS demandée,
--  même lorsqu'un prix avait été négocié.
--
--  LA CORRECTION (sans toucher au moteur)
--  --------------------------------------
--  1. `rpc_abonnement_prix_du_cycle` : si AUCUN versement n'a jamais été
--     enregistré et qu'une installation est définie, le prochain cycle est
--     L'INSTALLATION. Sinon, le mensuel (règle inchangée).
--  2. `rpc_abonnement_preparer_renouvellement` : quand il ouvre le cycle, il
--     pose le statut `EN_ATTENTE_COMPLEMENT`. C'est ce qui FIGE le montant :
--     le moteur ne rouvre pas un cycle (il ne le fait que sur `EXPIRE` ou
--     solde nul) et crédite donc exactement ce qui a été préparé.
--
--  ⚠️ Aucune écriture de vente, aucun changement du moteur.
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if not exists (
    select 1 from information_schema.tables
     where table_schema = 'public' and table_name = 'paiements_abonnements_laperle'
  ) then
    raise exception 'Module 3 absent : exécutez 20260916000003_module3_abonnement.sql.';
  end if;
end $$;


-- ============================================================================
--  1. PRIX DU PROCHAIN CYCLE — L'INSTALLATION D'ABORD, SI ELLE EXISTE
-- ============================================================================

create or replace function public.rpc_abonnement_prix_du_cycle(
  p_entreprise uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_e         public.entreprises%rowtype;
  v_grille    numeric := 0;
  v_paiements integer := 0;
  v_prix      numeric := 0;
begin
  select * into v_e from public.entreprises where id = p_entreprise;
  if not found then
    return 0;
  end if;

  -- Combien de versements ont déjà été enregistrés sur ce dossier ?
  -- (0 = le client n'a encore JAMAIS payé : c'est le premier cycle payant.)
  select count(*) into v_paiements
    from public.paiements_abonnements_laperle p
   where p.entreprise_id = p_entreprise;

  -- 1️⃣ PREMIER CYCLE PAYANT et installation définie → c'est elle qu'on
  --    réclame (elle comprend le premier mois). Installation à 0/NULL =
  --    offerte : on ne réclame rien et on passe au mensuel.
  if v_paiements = 0 and coalesce(v_e.prix_installation, 0) > 0 then
    return v_e.prix_installation;
  end if;

  select coalesce(g.montant_abonnement, 0)
    into v_grille
    from public.groupes_tarifaires g
   where g.id = v_e.groupe_tarifaire_id;

  -- 2️⃣ Renouvellement : le MENSUEL, jamais l'installation.
  v_prix := coalesce(
    nullif(v_e.prix_abonnement_mensuel, 0),
    nullif(v_grille, 0),
    case
      when coalesce(v_e.montant_total_du, 0) > 0
       and coalesce(v_e.montant_total_du, 0) <> coalesce(v_e.prix_installation, -1)
        then v_e.montant_total_du
      else 0
    end,
    0
  );

  return coalesce(v_prix, 0);
end;
$$;

comment on function public.rpc_abonnement_prix_du_cycle(uuid) is
  'Prix du prochain cycle : installation au premier cycle payant (si elle est définie), puis prix mensuel négocié, sinon grille. Jamais l''installation deux fois.';


-- Petit utilitaire : le prochain cycle est-il l'installation ?
create or replace function public.rpc_abonnement_type_cycle(
  p_entreprise uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
           when (select count(*) from public.paiements_abonnements_laperle p
                  where p.entreprise_id = p_entreprise) = 0
            and coalesce((select e.prix_installation from public.entreprises e
                           where e.id = p_entreprise), 0) > 0
             then 'installation'
           else 'abonnement'
         end;
$$;

comment on function public.rpc_abonnement_type_cycle(uuid) is
  'Nature du prochain cycle : « installation » (premier cycle payant, si définie) ou « abonnement ».';

revoke all on function public.rpc_abonnement_type_cycle(uuid) from public, anon;
grant execute on function public.rpc_abonnement_type_cycle(uuid) to authenticated;


-- ============================================================================
--  2. PRÉPARATION DU CYCLE : LE MONTANT EST FIGÉ
-- ============================================================================

create or replace function public.rpc_abonnement_preparer_renouvellement(
  p_entreprise uuid default null
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
  v_e      public.entreprises%rowtype;
  v_prix   numeric := 0;
  v_type   text := 'abonnement';
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

  -- Portée STRICTE : l'entreprise de l'appelant (ou un membre de sa société),
  -- jamais celle d'un tiers. La plateforme garde son droit d'intervention.
  if not (v_user = v_e.id
          or v_id = coalesce(v_owner, v_e.id)
          or v_user = v_owner
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à ce dossier.';
  end if;

  v_type := public.rpc_abonnement_type_cycle(v_id);

  -- L'abonnement court encore : on n'ouvre rien, on ne facture rien.
  if not (v_e.statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
          or (v_e.date_expiration is not null and v_e.date_expiration < now())) then
    return jsonb_build_object(
      'ok', true,
      'entreprise_id', v_id,
      'cycle_ouvert', false,
      'motif', 'CYCLE_EN_COURS',
      'type_cycle', v_type,
      'solde_restant', coalesce(v_e.solde_restant, 0),
      'prix_mensuel', public.rpc_abonnement_prix_du_cycle(v_id),
      'devise', coalesce(v_e.devise, 'CDF')
    );
  end if;

  -- Un cycle est déjà ouvert avec un solde : le client paie, on ne touche
  -- surtout pas au montant (double facturation impossible).
  if coalesce(v_e.solde_restant, 0) > 0.001 then
    return jsonb_build_object(
      'ok', true,
      'entreprise_id', v_id,
      'cycle_ouvert', true,
      'motif', 'DEJA_OUVERT',
      'type_cycle', v_type,
      'solde_restant', coalesce(v_e.solde_restant, 0),
      'prix_mensuel', public.rpc_abonnement_prix_du_cycle(v_id),
      'devise', coalesce(v_e.devise, 'CDF')
    );
  end if;

  v_prix := public.rpc_abonnement_prix_du_cycle(v_id);
  if v_prix <= 0 then
    raise exception 'PRIX_ABSENT|Aucun abonnement n''est défini pour ce compte : contactez la plateforme.';
  end if;

  -- Nouveau cycle. `statut = EN_ATTENTE_COMPLEMENT` FIGE le montant :
  -- le moteur ne rouvre un cycle que sur `EXPIRE` ou solde nul ; il créditera
  -- donc exactement ce montant-là (installation ou mensuel).
  -- `solde_restant` est GÉNÉRÉ (total − payé) : jamais écrit ici.
  update public.entreprises
     set montant_total_du  = v_prix,
         montant_deja_paye = 0,
         statut            = 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum,
         updated_at        = now()
   where id = v_id;

  begin
    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(), v_id, 'CYCLE_RENOUVELLEMENT_OUVERT', v_user,
      jsonb_build_object(
        'montant', v_prix, 'type_cycle', v_type,
        'statut_avant', v_e.statut, 'expiration', v_e.date_expiration
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', v_id,
    'cycle_ouvert', true,
    'motif', 'CYCLE_OUVERT',
    'type_cycle', v_type,
    'solde_restant', v_prix,
    'prix_mensuel', v_prix,
    'devise', coalesce(v_e.devise, 'CDF')
  );
end;
$$;

comment on function public.rpc_abonnement_preparer_renouvellement(uuid) is
  'Ouvre le cycle suivant (installation au premier cycle payant, puis mensuel) et FIGE le montant en passant le dossier en EN_ATTENTE_COMPLEMENT.';


-- ============================================================================
--  3. CONTRÔLE — le prix renvoyé est-il cohérent ?
-- ============================================================================

do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where p.proname = 'rpc_abonnement_prix_du_cycle' and n.nspname = 'public';

  if position('prix_installation' in v_def) = 0 then
    raise warning 'rpc_abonnement_prix_du_cycle ne mentionne pas l''installation : vérifiez la règle du premier cycle.';
  end if;
end $$;

-- ============================================================================
--  FIN — PHASE 9
-- ============================================================================
