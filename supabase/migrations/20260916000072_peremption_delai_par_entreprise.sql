-- ============================================================================
--  biashara_yangu — CORRECTIF 72 : LE DÉLAI D'ALERTE DE PÉREMPTION
--  Migration 20260916000072_peremption_delai_par_entreprise.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : base de données uniquement.
--
--  CE QUI MANQUAIT
--  ---------------
--  Le module 16 (C1, pharmacie) alerte sur les produits « bientôt périmés »
--  à partir d'un délai FIXE de 30 jours, écrit en dur dans l'application
--  (`StatutExpiration.depuis(..., joursProches: 30)` et
--  `ArticleService.compterExpirations(jours: 30)`).
--
--  Or ce délai n'est pas le même pour tout le monde : une pharmacie veut être
--  prévenue 90 jours à l'avance, une épicerie se contente de 7 jours. Un
--  délai imposé est soit trop court — on découvre la péremption trop tard —,
--  soit trop long — l'alerte devient permanente et on cesse de la lire.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--    1. une colonne `entreprises.alerte_peremption_jours` (défaut 30 jours,
--       bornée de 1 à 365) : CHAQUE BOUTIQUE règle le sien ;
--    2. `rpc_peremption_config()`   — lire le délai en vigueur ;
--    3. `rpc_peremption_definir_delai(p_jours)` — le modifier, avec
--       journalisation ;
--    4. le niveau d'audit de l'action `PEREMPTION_DELAI`.
--
--  ⚠️ POURQUOI SUR `entreprises` ET NON DANS `app_settings` : cette dernière
--  est GLOBALE (une clé, une valeur, aucune notion de boutique). Y écrire un
--  délai l'aurait imposé à tout le monde — exactement le défaut qu'on corrige.
--
--  LE DÉFAUT (30 JOURS) EST CONSERVÉ : une boutique qui ne règle rien garde
--  exactement le comportement d'avant. Aucune alerte ne change de camp
--  silencieusement.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 29 (module pharmacie).
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA COLONNE — LE DÉLAI PROPRE À CHAQUE BOUTIQUE
-- ============================================================================

alter table public.entreprises
  add column if not exists alerte_peremption_jours integer not null default 30;

--  Bornes : en dessous de 1 jour il n'y a plus d'anticipation ; au-delà d'un
--  an, une épicerie aurait en alerte permanente une marchandise qu'elle ne
--  vendra jamais. On refuse les deux.
do $peremption_contrainte$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'entreprises_alerte_peremption_plage'
       and conrelid = 'public.entreprises'::regclass
  ) then
    alter table public.entreprises
      add constraint entreprises_alerte_peremption_plage
      check (alerte_peremption_jours between 1 and 365);
    raise notice 'Correctif 72 : contrainte de plage ajoutee (1 a 365 jours).';
  end if;
end $peremption_contrainte$;

comment on column public.entreprises.alerte_peremption_jours is
  'Correctif 72 — Nombre de jours AVANT la date de peremption a partir duquel un produit est signale « expire bientot ». Regle par la boutique (defaut 30). N''a aucun effet sur le blocage de vente des produits deja expires.';


-- ============================================================================
--  2. LIRE LE DÉLAI EN VIGUEUR
-- ============================================================================
--  Renvoie le délai, la boutique concernée, et si l'appelant peut le
--  modifier — l'écran n'a donc pas à deviner s'il doit afficher un bouton.

create or replace function public.rpc_peremption_config(
  p_entreprise_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plateforme boolean;
  v_soc        uuid;
  v_delai      integer;
  v_modifiable boolean;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter le delai d''alerte de peremption.';
  end if;

  v_plateforme := public.est_plateforme();

  --  ⚠️ Hors plateforme, l'identifiant reçu est IGNORÉ : sans cela, n'importe
  --  quel commerçant pourrait lire le réglage d'une autre boutique en
  --  passant son identifiant. (Même règle que le correctif 68.)
  v_soc := case
             when v_plateforme then coalesce(p_entreprise_id, public.mon_entreprise_id())
             else public.mon_entreprise_id()
           end;

  if v_soc is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Aucune entreprise associee a ce compte.';
  end if;

  select e.alerte_peremption_jours into v_delai
    from public.entreprises e
   where e.id = v_soc;

  if v_delai is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe plus.';
  end if;

  v_modifiable := v_plateforme
                  or public.peut('articles', 'modifier')
                  or public.mon_role() = 'PROPRIETAIRE';

  return jsonb_build_object(
    'entreprise_id', v_soc,
    'delai_jours',   v_delai,
    'modifiable',    v_modifiable,
    'defaut_jours',  30
  );
end $$;

comment on function public.rpc_peremption_config(uuid) is
  'Correctif 72 — Lit le delai d''alerte de peremption de la boutique (toutes les 30 minutes). Hors plateforme, l''identifiant recu est ignore.';

revoke all on function public.rpc_peremption_config(uuid) from public, anon;
grant execute on function public.rpc_peremption_config(uuid) to authenticated;


-- ============================================================================
--  3. RÉGLER LE DÉLAI
-- ============================================================================

create or replace function public.rpc_peremption_definir_delai(
  p_jours          integer,
  p_entreprise_id  uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_plateforme boolean;
  v_soc        uuid;
  v_avant      integer;
  v_apres      integer := p_jours;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour regler le delai d''alerte de peremption.';
  end if;

  v_plateforme := public.est_plateforme();

  if not (v_plateforme
          or public.peut('articles', 'modifier')
          or public.mon_role() = 'PROPRIETAIRE') then
    raise exception 'DROIT_REFUSE|Votre role ne permet pas de regler le delai d''alerte de peremption.';
  end if;

  if v_apres is null then
    raise exception 'DELAI_INVALIDE|Indiquez un nombre de jours.';
  end if;

  if v_apres < 1 or v_apres > 365 then
    raise exception 'DELAI_INVALIDE|Le delai doit etre compris entre 1 et 365 jours (recu : %).', v_apres;
  end if;

  v_soc := case
             when v_plateforme then coalesce(p_entreprise_id, public.mon_entreprise_id())
             else public.mon_entreprise_id()
           end;

  if v_soc is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Aucune entreprise associee a ce compte.';
  end if;

  select e.alerte_peremption_jours into v_avant
    from public.entreprises e
   where e.id = v_soc
   for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe plus.';
  end if;

  update public.entreprises
     set alerte_peremption_jours = v_apres,
         updated_at              = now()
   where id = v_soc;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_soc, 'PEREMPTION_DELAI', v_user,
    jsonb_build_object(
      'avant_jours', v_avant,
      'apres_jours', v_apres,
      'par_role',    public.mon_role(),
      'correctif',   '72'
    ),
    now()
  );

  return jsonb_build_object(
    'entreprise_id', v_soc,
    'avant_jours',   v_avant,
    'delai_jours',   v_apres,
    'modifie',       v_avant is distinct from v_apres
  );
end $$;

comment on function public.rpc_peremption_definir_delai(integer, uuid) is
  'Correctif 72 — Regle le nombre de jours avant peremption a partir duquel un produit est signale. Journalise PEREMPTION_DELAI.';

revoke all on function public.rpc_peremption_definir_delai(integer, uuid) from public, anon;
grant execute on function public.rpc_peremption_definir_delai(integer, uuid) to authenticated;


-- ============================================================================
--  4. NIVEAUX D'AUDIT DE LA NOUVELLE ACTION
-- ============================================================================
--  ⚠️ `audit_niveau` retombe sur 'INFO' pour toute action qu'elle ne connait
--  pas — le niveau LE PLUS FAIBLE. Sans cette section, un changement de delai
--  d'alerte serait journalise au meme niveau qu'un affichage de page :
--  personne ne le verrait jamais.
--
--  La fonction est reprise A L'IDENTIQUE depuis la migration qui la definit
--  aujourd'hui, et SEULE la nouvelle action y est inseree. Le script qui la
--  produit REFUSE d'ecrire si la forme attendue du bloc a change — il ne
--  devine rien.
-- ============================================================================

create or replace function public.audit_niveau(p_action text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_action, '')))
    -- CRITIQUE : argent, droits, cycle de vie des comptes, devise.
    when 'CREATION_ENTREPRISE'        then 'CRITIQUE'
    when 'CHANGEMENT_STATUT'          then 'CRITIQUE'
    when 'REACTIVATION'               then 'CRITIQUE'
    when 'CHANGEMENT_ROLE'            then 'CRITIQUE'
    when 'PERMISSIONS_MODIFIEES'      then 'CRITIQUE'
    when 'PERMISSIONS_REINITIALISEES' then 'CRITIQUE'
    when 'PRIX_MODIFIE'               then 'CRITIQUE'
    when 'ANNULATION_VENTE'           then 'CRITIQUE'
    when 'VENTE_SUPPRIMEE'            then 'CRITIQUE'
    when 'UTILISATEUR_SUPPRIME'       then 'CRITIQUE'
    when 'ENTREPRISE_SUPPRIMEE'       then 'CRITIQUE'
    when 'AGENT_IA_CONFIG'            then 'CRITIQUE'
    when 'DEVISE_CONFIG'              then 'CRITIQUE'
    -- HAUT : opérations financières et mouvements de stock.
    when 'VENTE'                      then 'HAUT'
    when 'PAIEMENT_ENREGISTRE'        then 'HAUT'
    when 'PAIEMENT_DETTE'             then 'HAUT'
    when 'DETTE'                      then 'HAUT'
    when 'DEPENSE'                    then 'HAUT'
    when 'CLOTURE_CAISSE'             then 'HAUT'
    when 'APPROVISIONNEMENT'          then 'HAUT'
    when 'AJUSTEMENT'                 then 'HAUT'
    when 'INVENTAIRE'                 then 'HAUT'
    when 'STOCK_MODIFIE'              then 'HAUT'
    when 'ARTICLE_SUPPRIME'           then 'HAUT'
    when 'CHANGEMENT_ACTIVATION'      then 'HAUT'
    when 'IMPORT_PRODUITS'            then 'HAUT'
    when 'AGENT_IA_ACHAT'             then 'HAUT'
    -- 🏨 MODULE 16 C2 — hôtel.
    when 'CHECKOUT_SEJOUR'            then 'HAUT'
    when 'SEJOUR_ENCAISSE'            then 'HAUT'
    -- 🍽️ MODULE 16 C3 — restaurant.
    when 'COMMANDE_ENCAISSEE'         then 'HAUT'
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    when 'EVENEMENT_ENCAISSE'         then 'HAUT'
    when 'EVENEMENT_ANNULE'           then 'HAUT'
    -- 🥖 MODULE 16 C5 — boulangerie.
    when 'PRODUCTION_TERMINEE'        then 'HAUT'
    -- MOYEN : administration courante et sessions.
    when 'CONNEXION'                  then 'MOYEN'
    when 'DECONNEXION'                then 'MOYEN'
    when 'CONNEXION_ECHEC'            then 'MOYEN'
    when 'ARTICLE_CREE'               then 'MOYEN'
    when 'ARTICLE_MODIFIE'            then 'MOYEN'
    when 'CONDITIONNEMENT_AJOUTE'     then 'MOYEN'
    when 'CONDITIONNEMENT_MODIFIE'    then 'MOYEN'
    when 'CONDITIONNEMENT_SUPPRIME'   then 'MOYEN'
    when 'UTILISATEUR_CREE'           then 'MOYEN'
    when 'UTILISATEUR_MODIFIE'        then 'MOYEN'
    when 'ENTREPRISE_MODIFIEE'        then 'MOYEN'
    when 'RELANCE_DETTE'              then 'MOYEN'
    when 'AGENT_IA'                   then 'MOYEN'
    when 'AGENT_IA_ATTRIBUTION'       then 'MOYEN'
    when 'ESPACE_TYPE'                then 'MOYEN'
    -- 🏨 MODULE 16 C2 — hôtel.
    when 'CHAMBRE_ENREGISTREE'        then 'MOYEN'
    when 'CHAMBRE_MODIFIEE'           then 'MOYEN'
    when 'CHAMBRE_STATUT'             then 'MOYEN'
    when 'RESERVATION'                then 'MOYEN'
    when 'RESERVATION_ANNULEE'        then 'MOYEN'
    when 'CHECKIN_SEJOUR'             then 'MOYEN'
    -- 🍽️ MODULE 16 C3 — restaurant.
    when 'TABLE_ENREGISTREE'          then 'MOYEN'
    when 'TABLE_MODIFIEE'             then 'MOYEN'
    when 'TABLE_STATUT'               then 'MOYEN'
    when 'COMMANDE'                   then 'MOYEN'
    when 'COMMANDE_ENVOYEE'           then 'MOYEN'
    when 'COMMANDE_STATUT'            then 'MOYEN'
    when 'COMMANDE_ANNULEE'           then 'MOYEN'
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    when 'SALLE_ENREGISTREE'          then 'MOYEN'
    when 'SALLE_MODIFIEE'             then 'MOYEN'
    when 'EVENEMENT'                  then 'MOYEN'
    when 'EVENEMENT_MODIFIE'          then 'MOYEN'
    when 'EVENEMENT_STATUT'           then 'MOYEN'
    -- 🥖 MODULE 16 C5 — boulangerie.
    when 'MATIERE_ENREGISTREE'        then 'MOYEN'
    when 'MATIERE_MODIFIEE'           then 'MOYEN'
    when 'MATIERE_APPRO'              then 'MOYEN'
    when 'MATIERE_AJUSTEMENT'         then 'MOYEN'
    when 'PRODUCTION'                 then 'MOYEN'
    when 'PRODUCTION_ANNULEE'         then 'MOYEN'
    when 'RAPPORT'                    then 'INFO'

    -- 🧾 CORRECTIF 67 — factures d'abonnement.
    --   ECHEC : une facture non produite est un TROU de traçabilité sur un
    --   encaissement réel — aussi grave qu'un document annulé.
    when 'FACTURE_ABONNEMENT_ECHEC'       then 'HAUT'
    when 'FACTURE_ABONNEMENT_EMISE'       then 'MOYEN'
    when 'FACTURE_ABONNEMENT_ENVOYEE'     then 'INFO'
    when 'FACTURE_ABONNEMENT_ANNULEE'     then 'HAUT'
    when 'FACTURES_ABONNEMENT_RATTRAPAGE' then 'MOYEN'
    -- 🪙 CORRECTIF 68 — quotas IA : catalogue des packs, reprise
    --   d'attribution, geste commercial. Un DON de quotas est de l'argent
    --   donné : il doit être aussi visible qu'un changement de permission.
    when 'AGENT_IA_PACK'                  then 'MOYEN'
    when 'AGENT_IA_PACK_ENREGISTRE'       then 'MOYEN'
    when 'AGENT_IA_PACK_SUPPRIME'         then 'HAUT'
    when 'AGENT_IA_ATTRIBUTION_ANNULEE'   then 'HAUT'
    when 'AGENT_IA_GESTE'                 then 'CRITIQUE'
    -- 🔐 CORRECTIF 69 — code de validation de l'agent.
    --   EMIS : c'est un CONTRÔLE sur la création de comptes, pas une
    --   formalité — la Finance autorise quelqu'un à ouvrir un compte.
    --   VALIDE : trace de qui s'en est servi.
    --   ECHEC : un code refusé ou expiré est le signal le plus intéressant du
    --   dispositif : soit une erreur, soit une tentative. Il ne doit JAMAIS
    --   se noyer dans le journal.
    when 'AGENT_CODE_DEMANDE'   then 'MOYEN'
    when 'AGENT_CODE_EMIS'      then 'HAUT'
    when 'AGENT_CODE_VALIDE'    then 'HAUT'
    when 'AGENT_CODE_ECHEC'     then 'HAUT'
    when 'AGENT_CODE_REVOQUE'   then 'HAUT'
    -- 🧮 CORRECTIF 72 — délai d'alerte de péremption, réglé par la boutique.
    --   MOYEN et non BAS : ce réglage décide QUAND on prévient qu'une
    --   marchandise va périmer. Le rallonger trop fait crier l'alerte en
    --   permanence (on cesse de la lire) ; le raccourcir trop fait découvrir
    --   la péremption après coup. C'est donc un réglage qui a des
    --   conséquences sur la marchandise, même s'il ne touche pas à l'argent.
    when 'PEREMPTION_DELAI'     then 'MOYEN'
    else 'INFO'
  end;
$$;


-- ============================================================================
--  5. CONTROLE
-- ============================================================================

do $verif_peremption$
declare
  v_type text;
  v_defaut text;
  v_borne boolean;
  v_fonctions integer;
begin
  --  ⚠️ On vérifie d'abord que la COLONNE EXISTE VRAIMENT. C'est ce contrôle
  --  qui manquait au correctif précédent, où une colonne inventée
  --  (`nom_complet`) s'était installée sans erreur — PL/pgSQL ne valide pas
  --  les noms de colonnes à la création d'une fonction, seulement au premier
  --  appel.
  select c.data_type, pg_get_expr(d.adbin, d.adrelid)
    into v_type, v_defaut
    from information_schema.columns c
    join pg_attribute a on a.attrelid = 'public.entreprises'::regclass
                       and a.attname = c.column_name
    join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where c.table_schema = 'public'
     and c.table_name = 'entreprises'
     and c.column_name = 'alerte_peremption_jours';

  if v_type is null then
    raise exception 'Correctif 72 : la colonne entreprises.alerte_peremption_jours n''existe pas — la migration n''a pas pris.';
  end if;

  if v_type <> 'integer' then
    raise exception 'Correctif 72 : la colonne alerte_peremption_jours est de type % au lieu de integer.', v_type;
  end if;

  if v_defaut not like '%30%' then
    raise exception 'Correctif 72 : le defaut de la colonne devrait etre 30, il vaut % .', v_defaut;
  end if;

  select exists (
    select 1 from pg_constraint
     where conname = 'entreprises_alerte_peremption_plage'
       and conrelid = 'public.entreprises'::regclass
  ) into v_borne;

  if not v_borne then
    raise exception 'Correctif 72 : la contrainte de plage (1 a 365 jours) est absente.';
  end if;

  --  Les deux fonctions doivent exister ET lire la bonne colonne.
  select count(*) into v_fonctions
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('rpc_peremption_config', 'rpc_peremption_definir_delai')
     and pg_get_functiondef(p.oid) like '%alerte_peremption_jours%';

  if v_fonctions <> 2 then
    raise exception 'Correctif 72 : % fonction(s) sur 2 lisent alerte_peremption_jours — la migration est incomplete.', v_fonctions;
  end if;

  raise notice 'Correctif 72 : delai de peremption par boutique installe (colonne, bornes 1-365, defaut 30, 2 fonctions).';
end $verif_peremption$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En ENTIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select 'Correctif 72 — delai de peremption par boutique' as chantier,
       (select count(*) from information_schema.columns
         where table_schema = 'public' and table_name = 'entreprises'
           and column_name = 'alerte_peremption_jours')
                                                     as colonne_presente,
       (select count(*) from pg_proc p
          join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('rpc_peremption_config',
                             'rpc_peremption_definir_delai'))
                                                     as fonctions_creees,
       (select count(*) from public.entreprises
         where alerte_peremption_jours = 30)         as boutiques_au_defaut,
       (select count(*) from public.entreprises)      as boutiques_total,
       (select public.mon_role() is not null)         as session_active;
