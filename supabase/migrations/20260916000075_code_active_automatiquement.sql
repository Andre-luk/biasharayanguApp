-- ============================================================================
--  biashara_yangu — CORRECTIF 75 : LE CODE DE LA FINANCE ACTIVE LE COMPTE
--  Migration 20260916000075_code_active_automatiquement.sql
-- ============================================================================
--
--  ⛔ AUCUNE PUBLICATION. Correction de base uniquement.
--
--  CE QUI SE PASSAIT
--  -----------------
--  La chaîne d'ouverture d'un compte demandait QUATRE gestes, dont deux
--  redondants du point de vue du terrain :
--
--    1. l'agent de terrain VÉRIFIE le dossier        → `activation_etape = 'verifie'`
--    2. l'agent DEMANDE un code de validation        → `rpc_agent_code_demander`
--    3. la Finance ÉMET le code et le lui dicte      → `rpc_agent_code_emettre`
--    4. l'agent SAISIT le code reçu                  → `rpc_agent_code_valider`
--    5. …puis un dernier geste restait à faire pour que le compte soit
--       réellement opérationnel (`rpc_activation_valider_finance`).
--
--  Conséquence sur le terrain : l'agent croyait avoir terminé (« j'ai activé,
--  j'attends le code »), le client attendait, et le compte restait bloqué en
--  `verifie`. Personne ne comprenait pourquoi l'application répondait encore
--  « en attente de validation ».
--
--  CE QUE CE FICHIER FAIT
--  ----------------------
--  Dès que la Finance ÉMET le code, le compte est ACTIVÉ AUTOMATIQUEMENT :
--
--    • `activation_etape = 'actif'`  → le verrou serveur du module 17 tombe ;
--    • statut `ESSAI_7J` et échéance à +7 jours (durée d'essai de la grille
--      si elle en définit une autre) → l'application ouvre pour de bon,
--      SANS qu'un centime ait été encaissé : c'est la règle voulue des
--      7 jours avant tout paiement ;
--    • `valide_par_finance` / `valide_le_finance` renseignés : la
--      responsabilité de l'ouverture est tracée, comme avant ;
--    • une étape `paiement_finance` est ajoutée au dossier, avec la mention
--      « activation automatique — code émis », pour que la fiche raconte
--      exactement ce qui s'est passé.
--
--  Le code lui-même reste un CONTRÔLE : il est toujours dicté par la Finance à
--  l'agent, et l'agent le saisit toujours (correctif 69). Ce qui change, c'est
--  que ce geste n'est plus un préalable à l'ouverture : l'ouverture a lieu au
--  moment de l'émission.
--
--  CE QUI N'EST PAS TOUCHÉ
--  -----------------------
--   • l'ENCAISSEMENT : enregistrer une avance, un solde ou un renouvellement
--     reste un geste distinct (`rpc_abonnement_enregistrer_paiement`,
--     `rpc_activation_valider_finance`). Le compte s'ouvre en essai, puis le
--     paiement prolonge — il ne sert plus à débloquer ;
--   • les gardes : seule la Finance ou le Super Admin peut émettre le code ;
--   • `rpc_agent_code_valider` et le contrôle à 5 minutes : inchangés.
--
--  ⚠️ À exécuter dans Supabase → SQL Editor → coller → Run.
--  IDEMPOTENTE : relançable sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. L'ACTIVATION AUTOMATIQUE (une fonction, réutilisable et vérifiable)
-- ============================================================================
--  Elle ne fait rien si le compte est déjà ouvert : relancer une émission de
--  code ne prolonge jamais un abonnement.

create or replace function public.activer_apres_code(p_entreprise_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_e     public.entreprises;
  v_essai integer := 7;
  v_avant text;
begin
  select * into v_e
    from public.entreprises
   where id = p_entreprise_id
   for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  v_avant := v_e.activation_etape;

  --  Déjà ouvert : on ne touche à RIEN (ni dates, ni montants).
  if v_avant = 'actif' then
    return jsonb_build_object(
      'ok', true, 'deja_actif', true,
      'activation_etape', v_avant,
      'date_expiration', v_e.date_expiration);
  end if;

  --  Une restriction est une décision : le code ne la lève pas.
  if v_avant = 'restreint' then
    return jsonb_build_object(
      'ok', false, 'motif', 'COMPTE_RESTREINT',
      'activation_etape', v_avant,
      'message', 'Ce compte est restreint : reglez le solde avant de l''ouvrir.');
  end if;

  --  Durée d'essai : celle du pack de l'entreprise, sinon 7 jours.
  if v_e.groupe_tarifaire_id is not null then
    select coalesce(nullif(g.duree_essai_jours, 0), 7)
      into v_essai
      from public.groupes_tarifaires g
     where g.id = v_e.groupe_tarifaire_id;
    v_essai := coalesce(v_essai, 7);
  end if;

  --  Les dates ne sont posées QUE si l'abonnement n'a pas déjà couru :
  --  un compte vérifié dont l'essai est en cours ne repart pas de zéro.
  if v_e.date_activation is null or v_e.date_expiration is null
     or v_e.date_expiration <= now() then
    update public.entreprises
       set activation_etape       = 'actif',
           statut                 = 'ESSAI_7J'::public.statut_abonnement_enum,
           date_activation        = coalesce(v_e.date_activation, now()),
           date_expiration        = now() + make_interval(days => v_essai),
           montant_total_du       = coalesce(v_e.prix_installation,
                                             v_e.montant_total_du),
           valide_par_finance     = auth.uid(),
           valide_le_finance      = now(),
           updated_at             = now()
     where id = p_entreprise_id
     returning * into v_e;
  else
    update public.entreprises
       set activation_etape   = 'actif',
           valide_par_finance = auth.uid(),
           valide_le_finance  = now(),
           updated_at         = now()
     where id = p_entreprise_id
     returning * into v_e;
  end if;

  insert into public.activations_entreprise (
    entreprise_id, etape, acteur_id, acteur_role, note
  ) values (
    p_entreprise_id, 'paiement_finance', auth.uid(), public.mon_role(),
    'Activation automatique — code de validation émis par la Finance'
  );

  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (
      gen_random_uuid(), p_entreprise_id, 'ACTIVATION_FINANCE', auth.uid(),
      jsonb_build_object(
        'etape_avant', v_avant,
        'etape_apres', 'actif',
        'mode',        'automatique_par_code',
        'essai_jours', v_essai,
        'date_expiration', v_e.date_expiration,
        'correctif',   '75'
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true, 'deja_actif', false,
    'activation_etape', 'actif',
    'statut', v_e.statut,
    'essai_jours', v_essai,
    'date_expiration', v_e.date_expiration);
end $$;

comment on function public.activer_apres_code(uuid) is
  'Correctif 75 — Ouvre un compte dès que la Finance a émis le code de validation : étape actif, essai de 7 jours (ou la durée du pack), responsabilité tracée. Ne touche à rien si le compte est déjà ouvert, et ne lève pas une restriction.';

revoke all on function public.activer_apres_code(uuid) from public, anon, authenticated;


-- ============================================================================
--  2. L'ÉMISSION DU CODE ACTIVE LE COMPTE
-- ============================================================================
--  ⚠️ LA SIGNATURE CHANGE (un paramètre `p_activer` avec valeur par défaut).
--  L'ancienne fonction est DONC SUPPRIMÉE : sans cela, deux versions
--  cohabiteraient et PostgREST refuserait l'appel (« surcharge ambiguë »).
--  L'application continue d'appeler la fonction avec le seul `p_demande_id` :
--  la valeur par défaut s'applique, rien à changer côté application.

drop function if exists public.rpc_agent_code_emettre(uuid);

create or replace function public.rpc_agent_code_emettre(
  p_demande_id uuid,
  p_activer    boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_demande    public.codes_validation_agent;
  v_code       text;
  v_expire     timestamptz;
  v_activation jsonb := null;
begin
  --  DEUX RÔLES SEULEMENT : « finance et super admin doivent pouvoir
  --  l'envoyer ». Personne d'autre — surtout pas l'agent, qui est contrôlé.
  if public.mon_role() not in ('FINANCE_LAPERLE', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seule la Finance ou le Super Admin emet un code de validation.';
  end if;

  select * into v_demande
    from public.codes_validation_agent
   where id = p_demande_id
   for update;

  if not found then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande de code n''existe pas.';
  end if;

  if v_demande.statut = 'UTILISE' then
    raise exception 'CODE_DEJA_UTILISE|Ce code a deja ete utilise.';
  end if;
  if v_demande.statut = 'REVOQUE' then
    raise exception 'DEMANDE_REVOQUEE|Cette demande a ete revoquee.';
  end if;

  --  Un code à 6 chiffres, entre 100 000 et 999 999 : pas de zéro de tête,
  --  qui se perd à l'oral comme à l'écrit.
  v_code := lpad((floor(random() * 900000) + 100000)::int::text, 6, '0');
  v_expire := now() + make_interval(mins => public.delai_code_agent_minutes());

  update public.codes_validation_agent
     set code      = v_code,
         emis_par  = auth.uid(),
         emis_le   = now(),
         expire_le = v_expire,
         statut    = 'EMIS',
         updated_at = now()
   where id = p_demande_id;

  --  ⚠️ LE CODE N'EST PAS DANS LE JOURNAL. L'y écrire le rendrait lisible par
  --  quiconque consulte le journal : le contrôle n'existerait plus.
  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), v_demande.entreprise_id, 'AGENT_CODE_EMIS', auth.uid(),
    jsonb_build_object(
      'demande_id', v_demande.id,
      'emis_par_role', public.mon_role(),
      'expire_le',  v_expire,
      'renouvellement', v_demande.code is not null,
      'activation_automatique', coalesce(p_activer, true),
      'correctif',  '69/75'
    ),
    now()
  );

  --  🆕 CORRECTIF 75 — LE GESTE DE LA FINANCE SUFFIT : le compte s'ouvre.
  --  L'émission du code ne peut plus échouer à cause de l'activation : si le
  --  compte est déjà ouvert, la fonction ne fait rien, et si l'activation
  --  rencontre un cas imprévu, le code est DÉJÀ émis et valable — on renvoie
  --  l'information au lieu de tout annuler.
  if coalesce(p_activer, true) then
    begin
      v_activation := public.activer_apres_code(v_demande.entreprise_id);
    exception when others then
      v_activation := jsonb_build_object(
        'ok', false, 'motif', 'ACTIVATION_IMPOSSIBLE',
        'message', sqlerrm);
    end;
  end if;

  --  Le code est renvoyé À LA FINANCE UNIQUEMENT (garde ci-dessus) : c'est
  --  elle qui le transmet à l'agent.
  return jsonb_build_object(
    'ok',         true,
    'demande_id', v_demande.id,
    'code',       v_code,
    'expire_le',  v_expire,
    'activation', v_activation
  );
end $$;

comment on function public.rpc_agent_code_emettre(uuid, boolean) is
  'Correctif 69/75 — La Finance ou le Super Admin emet un code a 6 chiffres valable 5 minutes, et le compte est ACTIVÉ automatiquement dans la foulée (essai de 7 jours). Le code n''est jamais journalise et n''est renvoye qu''a ces deux roles. `p_activer := false` pour un code sans activation.';

revoke all on function public.rpc_agent_code_emettre(uuid, boolean) from public, anon;
grant execute on function public.rpc_agent_code_emettre(uuid, boolean) to authenticated;


-- ============================================================================
--  3. CONTRÔLE
-- ============================================================================

do $verif_75$
declare
  v_fonc     integer;
  v_ancienne integer;
  v_nb       integer;
begin
  select count(*) into v_fonc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('activer_apres_code', 'rpc_agent_code_emettre');

  if v_fonc <> 2 then
    raise exception 'Correctif 75 : % fonction(s) sur 2 présente(s).', v_fonc;
  end if;

  --  L'ancienne signature NE DOIT PLUS EXISTER : deux versions en base
  --  rendraient l'appel ambigu côté PostgREST.
  select count(*) into v_ancienne
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_agent_code_emettre'
     and p.pronargs = 1;

  if v_ancienne <> 0 then
    raise exception 'Correctif 75 : l''ancienne signature (uuid) est encore presente.';
  end if;

  select count(*) into v_nb
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname = 'rpc_agent_code_emettre'
     and p.pronargs = 2
     and (pg_get_functiondef(p.oid) like '%activer_apres_code%');

  if v_nb <> 1 then
    raise exception 'Correctif 75 : l''emission du code n''appelle pas l''activation.';
  end if;

  raise notice 'Correctif 75 pret : emettre un code ouvre le compte.';
end $verif_75$;


-- ============================================================================
--  RAPPORT FINAL — ce qui attend, et ce qui ouvre
-- ============================================================================
--  ⚠️ En DERNIER : le SQL Editor n'affiche que la dernière instruction.

select 'CORRECTIF 75 — ACTIF' as resultat,
       (select count(*) from public.entreprises
         where activation_etape = 'verifie')            as dossiers_verifies_en_attente,
       (select count(*) from public.entreprises
         where activation_etape = 'actif')              as comptes_actifs,
       (select count(*) from public.codes_validation_agent
         where statut = 'EN_ATTENTE')                   as demandes_de_code_ouvertes,
       (select count(*) from public.codes_validation_agent
         where statut = 'EMIS')                         as codes_emis_en_cours;
