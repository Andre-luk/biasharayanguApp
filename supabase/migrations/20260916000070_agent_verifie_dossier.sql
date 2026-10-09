-- ============================================================================
--  biashara_yangu — CORRECTIF 70 : L'AGENT PEUT VÉRIFIER UN DOSSIER
--  Migration 20260916000070_agent_verifie_dossier.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : base de données uniquement.
--
--  CE QUE CE FICHIER FAIT — ET CE QU'IL N'A PEUT-ÊTRE PAS EU À FAIRE
--  -----------------------------------------------------------------
--  Cette migration fige la garde de `rpc_activation_verifier` pour qu'elle
--  accepte l'AGENT_TERRAIN, ce que `lib/services/permission_service.dart`
--  annonce déjà (`verificationComptes` : voir + valider).
--
--  ⚠️ MAIS ELLE N'A PEUT-ÊTRE CORRIGÉ AUCUN DÉFAUT RÉEL, ET IL FAUT LE DIRE.
--
--  En lisant la migration 18 — où la garde est
--  `v_role not in ('GESTIONNAIRE_COMPTES', 'SUPER_ADMIN')` — j'avais conclu que
--  le serveur refusait l'agent, qui voyait donc un bouton « Vérifier » refusé
--  ensuite. Cette conclusion est DOUTEUSE : la migration 43 (section 3.c) passe
--  en revue TOUTES les fonctions contenant 'SUPER_ADMIN' et remplace
--  dynamiquement cette liste par une liste incluant AGENT_TERRAIN. Le refus
--  observé sur `rpc_activation_valider_finance` — prouvé, lui, par l'échec du
--  premier essai de ce fichier — montre que ce remplacement a bien eu lieu.
--  Il a donc très probablement élargi `rpc_activation_verifier` de la même
--  façon, dès la migration 43 : l'agent pouvait déjà vérifier.
--
--  CE FICHIER RESTE UTILE POUR AUTANT : un patch dynamique ne se voit pas. La
--  migration 18 est idempotente (`create or replace`) ; la rejouer — réflexe
--  normal en cas de doute — remettrait la garde d'origine sans que personne ne
--  s'en aperçoive avant que l'agent voie son bouton refusé. Ici, l'intention est
--  écrite noir sur blanc, dans un fichier qu'on peut relire.
--
--  ⚠️ LE RAPPORT FINAL TRANCHE. Le `select` à la fin de ce fichier affiche les
--  DEUX gardes réellement en vigueur en base. C'est la seule preuve : aucun
--  raisonnement sur les fichiers ne remplace une lecture de la base.
--
--  Le patron décrit précisément ce geste : « avant que l'agent confirme le
--  compte ou valide, il faut un code de validation ». L'agent CONFIRME donc le
--  compte — c'est cette étape-ci. Le correctif 69 lui fournit le contrôle.
--
--  CE QUI NE CHANGE PAS — ET CE QUE J'AI CRU À TORT
--  ------------------------------------------------
--  1. `rpc_activation_valider_finance` (l'ARGENT) n'est PAS modifiée ici :
--     aucune de ses lignes n'est touchée.
--
--     ⚠️ CORRECTION D'UNE ERREUR DE LECTURE. J'avais écrit que le serveur
--     réservait la validation du paiement à FINANCE_LAPERLE et SUPER_ADMIN.
--     C'est FAUX depuis la migration 43. Sa section 3.c passe en revue
--     TOUTES les fonctions contenant 'SUPER_ADMIN' et remplace
--     dynamiquement la liste ('FINANCE_LAPERLE', 'SUPER_ADMIN') par
--     ('FINANCE_LAPERLE', 'AGENT_TERRAIN', 'SUPER_ADMIN'). La validation du
--     paiement accepte donc l'agent de terrain — et c'était DÉLIBÉRÉ :
--     « il crée les entreprises, vérifie et active leurs dossiers et valide
--     les paiements reçus » (commentaire de la 43, section 3.b).
--
--     LA LEÇON : lire la migration 18 ne suffisait pas. Une `create or
--     replace` dans un vieux fichier n'est PAS la définition en vigueur si
--     une migration ultérieure re-patche la fonction par `replace()` sur
--     `pg_get_functiondef` — rien dans le fichier d'origine ne le laisse
--     voir. Le premier essai de CE fichier a échoué pour cette seule raison :
--     son contrôle annonçait une « escalade de droits » là où il n'y avait
--     qu'un choix de conception déjà installé et assumé.
--
--  2. Les correctifs 63 et 64 restent en vigueur : l'agent ne suspend, ne
--     réactive et ne supprime AUCUN compte. Cet alignement ne les concerne pas.
--  3. Aucune autre fonction n'est modifiée. La fonction est reprise À
--     L'IDENTIQUE, seule la ligne de garde change.
--
--  POURQUOI CE FICHIER RESTE UTILE, MÊME SI LA 43 AVAIT DÉJÀ ÉLARGI LA GARDE
--  -------------------------------------------------------------------------
--  Parce qu'un patch dynamique ne se voit pas. La migration 18 est
--  idempotente (`create or replace`) : la rejouer — un réflexe normal en cas
--  de doute — REMETTRAIT la garde d'origine, sans que personne ne s'en
--  aperçoive avant que l'agent voie son bouton refusé par le serveur. Ce
--  fichier-ci fige l'intention dans le texte de la migration, à un endroit
--  lisible, et il est sans effet si la 43 a déjà fait le travail.
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
--
--  ⚠️ On EXTRAIT la liste de rôles réellement écrite dans chaque garde
--  (`v_role not in (...)`), au lieu de chercher le mot « AGENT_TERRAIN »
--  n'importe où dans le corps de la fonction. Chercher le mot partout donnait
--  un FAUX POSITIF sur `rpc_activation_valider_finance` : la migration 43 y
--  avait ajouté l'agent DÉLIBÉRÉMENT, et le contrôle criait à l'escalade de
--  droits. Un contrôle qui crie au loup est pire que pas de contrôle : on
--  finit par le contourner — et le vrai problème passerait avec.
-- ============================================================================

do $verif_agent_verifie$
declare
  v_verif   text;
  v_finance text;
  v_garde   text;
begin
  select pg_get_functiondef(p.oid) into v_verif
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_verifier';

  if v_verif is null then
    raise exception 'Correctif 70 : rpc_activation_verifier introuvable.';
  end if;

  --  LE point de cette migration : l'agent de terrain peut VÉRIFIER.
  v_garde := (regexp_match(v_verif, 'v_role\s+not\s+in\s*\(([^()]*)\)'))[1];
  if v_garde is null then
    raise exception 'Correctif 70 : garde de rpc_activation_verifier illisible — verifiez la fonction a la main.';
  end if;
  if position('AGENT_TERRAIN' in v_garde) = 0 then
    raise exception 'Correctif 70 : l''agent de terrain n''est PAS autorise a verifier (garde = %). Le correctif n''a pas pris.', v_garde;
  end if;

  --  Ce qui ne doit PAS avoir bougé : la Finance et le Super Admin gardent la
  --  validation du paiement. C'est le SEUL invariant que ce fichier défend.
  select pg_get_functiondef(p.oid) into v_finance
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'rpc_activation_valider_finance';

  if v_finance is null then
    raise exception 'Correctif 70 : rpc_activation_valider_finance introuvable — l''activation ne fonctionnerait plus.';
  end if;

  v_garde := (regexp_match(v_finance, 'v_role\s+not\s+in\s*\(([^()]*)\)'))[1];
  if v_garde is null then
    raise exception 'Correctif 70 : garde de rpc_activation_valider_finance illisible.';
  end if;
  if position('FINANCE_LAPERLE' in v_garde) = 0
     or position('SUPER_ADMIN' in v_garde) = 0 then
    raise exception 'Correctif 70 : la Finance ou le Super Admin a perdu la validation du paiement (garde = %).', v_garde;
  end if;

  --  ⚠️ L'agent dans la garde du paiement n'est PAS une anomalie : c'est la
  --  migration 43, section 3.c, qui l'y a mis volontairement. On le SIGNALE,
  --  on ne le juge pas : un contrôle n'a pas à casser une décision de
  --  conception déjà installée.
  if position('AGENT_TERRAIN' in v_garde) > 0 then
    raise notice 'Correctif 70 : l''agent de terrain peut VERIFIER un dossier ET VALIDER un paiement (garde du paiement = %). Ce second droit vient de la migration 43 et n''est pas modifie ici.', v_garde;
  else
    raise notice 'Correctif 70 : l''agent de terrain peut VERIFIER un dossier ; la validation du paiement reste a %.', v_garde;
  end if;
end $verif_agent_verifie$;


-- ============================================================================
--  RAPPORT FINAL — l'état RÉEL des deux gardes, lisible d'un coup d'œil.
--  ⚠️ En ENTIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select 'Correctif 70 — agent verifie le dossier' as chantier,
       (select (regexp_match(pg_get_functiondef(p.oid),
                             'v_role\s+not\s+in\s*\(([^()]*)\)'))[1]
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'rpc_activation_verifier')
                                            as roles_qui_verifient,
       (select (regexp_match(pg_get_functiondef(p.oid),
                             'v_role\s+not\s+in\s*\(([^()]*)\)'))[1]
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public' and p.proname = 'rpc_activation_valider_finance')
                                            as roles_qui_valident_le_paiement,
       (select public.mon_role() is not null) as session_active;
