-- ============================================================================
--  biashara_yangu — CORRECTIF 70 : L'AGENT PEUT VÉRIFIER UN DOSSIER
--  Migration 20260916000070_agent_verifie_dossier.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : base de données uniquement.
--
--  LE DÉFAUT CORRIGÉ
--  -----------------
--  `rpc_activation_verifier` n'autorisait que GESTIONNAIRE_COMPTES et
--  SUPER_ADMIN. Or `lib/services/permission_service.dart` donne à
--  l'AGENT_TERRAIN la page `verificationComptes` (voir + valider).
--
--  Conséquence : l'agent voyait le dossier, voyait le bouton « Vérifier », et
--  se faisait refuser par le serveur. Un écran qui propose une action pour la
--  refuser ensuite est pire qu'un écran qui ne la propose pas : l'agent croit
--  à une panne, recommence, et perd la confiance dans l'outil.
--
--  Le patron décrit précisément ce geste : « avant que l'agent confirme le
--  compte ou valide, il faut un code de validation ». L'agent CONFIRME donc le
--  compte — c'est cette étape-ci. Le correctif 69 lui fournit le contrôle.
--
--  CE QUI NE CHANGE PAS — ET C'EST DÉLIBÉRÉ
--  ----------------------------------------
--  1. `rpc_activation_valider_finance` (l'ARGENT) reste réservée à
--     FINANCE_LAPERLE et SUPER_ADMIN. La séparation des responsabilités posée
--     par le module 14 — le gestionnaire vérifie, la FINANCE active — n'est
--     PAS touchée : l'agent ne valide pas un paiement.
--  2. Les correctifs 63 et 64 restent en vigueur : l'agent ne suspend, ne
--     réactive et ne supprime AUCUN compte. Cet alignement ne les concerne pas.
--  3. Aucune autre fonction n'est modifiée. La fonction est reprise À
--     L'IDENTIQUE, seule la ligne de garde change.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 69.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA FONCTION, REPRISE À L'IDENTIQUE — UNE SEULE LIGNE CHANGE
--     `create or replace` conserve les privilèges : inutile de rejouer les
--     `revoke` / `grant` de la migration 14.
-- ============================================================================

create or replace function public.rpc_activation_verifier(
  p_entreprise_id uuid,
  p_approuver     boolean,
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := public.mon_role();
  v_e    public.entreprises;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
begin
  -- 🔒 SÉPARATION DES RESPONSABILITÉS : le gestionnaire vérifie, il
  -- n'active JAMAIS (seule la finance valide l'activation finale).
  --  ⚠️ CORRECTIF 70 — l'AGENT DE TERRAIN est ajouté.
  --  L'application lui donne DÉJÀ cet écran (`verificationComptes`
  --  voir+valider) : sans cette ligne, son bouton « Vérifier »
  --  était visible puis refusé par le serveur — le pire des cas,
  --  parce qu'il fait croire à une panne.
  --  Il VÉRIFIE (aucun argent en jeu) ; il n'ACTIVE pas : la
  --  validation du paiement reste à la Finance (migration 14).
  if v_role not in ('GESTIONNAIRE_COMPTES', 'SUPER_ADMIN', 'AGENT_TERRAIN') then
    raise exception 'DROIT_REFUSE|Seul le gestionnaire des comptes vérifie un dossier.';
  end if;

  select * into v_e
    from public.entreprises
   where id = p_entreprise_id
   for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  if v_e.activation_etape not in ('en_attente_verification', 'rejete') then
    raise exception 'ETAPE_INVALIDE|Ce dossier n''est pas en attente de vérification.';
  end if;

  if coalesce(p_approuver, false) then
    update public.entreprises
       set activation_etape = 'verifie',
           verifie_par      = auth.uid(),
           verifie_le       = now(),
           updated_at       = now()
     where id = p_entreprise_id
     returning * into v_e;

    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role, note
    ) values (
      p_entreprise_id, 'verification', auth.uid(), v_role, v_note
    );

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'ACTIVATION_VERIFIEE', auth.uid(),
        jsonb_build_object('entreprise_id', p_entreprise_id, 'boutique', v_e.nom, 'note', v_note)
      );
    exception when others then null;
    end;
  else
    if v_note is null or length(v_note) < 3 then
      raise exception 'NOTE_REQUISE|Précisez le motif du rejet (3 caractères minimum).';
    end if;

    update public.entreprises
       set activation_etape = 'rejete',
           updated_at       = now()
     where id = p_entreprise_id
     returning * into v_e;

    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role, note
    ) values (
      p_entreprise_id, 'rejet_verification', auth.uid(), v_role, v_note
    );

    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'ACTIVATION_REJETEE', auth.uid(),
        jsonb_build_object('entreprise_id', p_entreprise_id, 'boutique', v_e.nom, 'motif', v_note)
      );
    exception when others then null;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'etape', v_e.activation_etape,
    'approuve', coalesce(p_approuver, false)
  );
end;
$$;

-- ============================================================================
--  2. CONTRÔLE
-- ============================================================================

do $verif_agent_verifie$
declare
  v_source text;
  v_finance text;
begin
  select pg_get_functiondef(p.oid) into v_source
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_verifier';

  if v_source is null then
    raise exception 'Correctif 70 : rpc_activation_verifier introuvable.';
  end if;

  if v_source not like '%AGENT_TERRAIN%' then
    raise exception 'Correctif 70 : l''agent de terrain n''est PAS autorise a verifier — le correctif n''a pas pris.';
  end if;

  --  ⚠️ On vérifie AUSSI ce qui ne devait PAS changer : si l'agent se
  --  retrouvait un jour dans la validation du paiement, ce serait une
  --  escalation de droits silencieuse. Le contrôle l'interdit ici.
  select pg_get_functiondef(p.oid) into v_finance
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_valider_finance';

  if v_finance is not null and v_finance like '%AGENT_TERRAIN%' then
    raise exception 'Correctif 70 : l''agent de terrain apparait dans la validation des paiements — ce ne doit PAS arriver, la separation des responsabilites est volee.';
  end if;

  raise notice 'Correctif 70 : l''agent de terrain peut verifier un dossier ; la validation du paiement reste a la Finance.';
end $verif_agent_verifie$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En ENTIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select 'Correctif 70 — agent verifie le dossier' as chantier,
       (select pg_get_functiondef(p.oid) like '%AGENT_TERRAIN%'
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'rpc_activation_verifier')
                                                  as agent_autorise_a_verifier,
       (select pg_get_functiondef(p.oid) like '%AGENT_TERRAIN%'
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'rpc_activation_valider_finance')
                                                  as agent_dans_la_finance,
       (select public.mon_role() is not null)     as session_active;
