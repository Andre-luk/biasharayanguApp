-- ============================================================================
--  biashara_yangu — CORRECTIF 71 : LA COLONNE `nom_complet` N'EXISTE PAS
--  Migration 20260916000071_fix_colonne_nom_utilisateur.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : correction de base uniquement.
--
--  LE DÉFAUT CORRIGÉ — ET IL ÉTAIT VISIBLE CHEZ L'UTILISATEUR
--  ----------------------------------------------------------
--  Les migrations 67, 68 et 69 lisaient le nom d'un utilisateur avec
--  `utilisateurs.nom_complet`. Cette colonne n'a jamais existé : elle
--  n'apparaît QUE dans ces trois fichiers. Le nom se lit `nom`, avec `email`
--  en secours — l'idiome déjà utilisé en production par la migration 47
--  (`coalesce(nullif(btrim(u.nom), ''), u.email)`).
--
--  Symptôme relevé dans le journal de l'application, v2.8.0 installée :
--
--    CodeValidationAgentService (le chargement des codes) :
--      PostgrestException(message: column demandeur.nom_complet does not
--      exist, code: 42703)
--
--  ⚠️ POURQUOI LE CONTRÔLE DE SYNTAXE NE POUVAIT PAS LE VOIR : PL/pgSQL ne
--  valide PAS les noms de colonnes à la création d'une fonction — seulement à
--  sa PREMIÈRE EXÉCUTION. La migration s'installe donc sans la moindre erreur,
--  et le défaut ne se révèle que chez l'utilisateur, au moment où il ouvre
--  l'écran. C'est la leçon de ce correctif : une migration « valide » n'est pas
--  une migration qui fonctionne.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--  Elle RÉINSTALLE les quatre fonctions qui référençaient la colonne
--  inexistante, avec le nom corrigé. Les fonctions sont reprises depuis leurs
--  fichiers d'origine (67, 68, 69) DÉJÀ CORRIGÉS : une seule expression change
--  dans chacune, rien d'autre.
--
--    1. `facture_abonnement_generer_interne`  (correctif 67) — nom de l'auteur
--       de la facture ;
--    2. `rpc_agent_ia_attributions`           (correctif 68) — nom du
--       collaborateur et de celui qui lui a attribué des quotas ;
--    3. `rpc_agent_codes_lister`              (correctif 69) — noms du
--       demandeur, de l'émetteur et du valideur du code ;
--    4. `rpc_agent_dossiers_sans_code`        (correctif 69) — nom de celui qui
--       a vérifié le dossier.
--
--  ⚠️ `create or replace` CONSERVE LES PRIVILÈGES : inutile de rejouer les
--  `revoke` / `grant` des migrations d'origine.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS les correctifs 67, 68 et 69.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  LES QUATRE FONCTIONS, RÉINSTALLÉES AVEC LE NOM CORRIGÉ
-- ============================================================================

create or replace function public.facture_abonnement_generer_interne(
  p_entreprise_id  uuid,
  p_paiement_id    uuid,
  p_paiement_table text,
  p_type_paiement  text,
  p_montant        numeric,
  p_total_apres    numeric,
  p_solde_apres    numeric,
  p_prolongation   integer,
  p_auteur         uuid,
  p_origine        text,
  p_note           text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent           public.entreprises;
  v_telephone     text;
  v_type          text;
  v_montant       numeric := coalesce(p_montant, 0);
  v_total_apres   numeric;
  v_solde         numeric;
  v_solde_inconnu boolean := false;
  v_du            numeric;
  v_avance        numeric;
  v_regle         numeric;
  v_paye          numeric;
  v_jours         integer := coalesce(p_prolongation, 0);
  v_mois          integer;
  v_cycles_avant  integer;
  v_nom_auteur    text;
  v_role_auteur   text;
  v_id            uuid;
  v_numero        text;
begin
  select * into v_ent
    from public.entreprises
   where id = p_entreprise_id;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Le compte vise n''existe pas.';
  end if;

  -- ── 5.a Cumuls : la ligne d'historique fait foi quand elle les porte.
  --     ⚠️ On CONSERVE le NULL quand l'information manque : sur une facture,
  --     « inconnu » et « zéro » ne veulent pas dire la même chose.
  v_total_apres   := coalesce(p_total_apres, v_ent.montant_deja_paye);
  v_solde         := coalesce(p_solde_apres, v_ent.solde_restant);
  v_solde_inconnu := (v_solde is null);

  -- ── 5.b Montant dû du cycle. Le moteur le tient dans `montant_total_du`
  --     quand il est passé par rpc_abonnement_enregistrer_paiement ; le
  --     chemin historique (rpc_enregistrer_paiement) ne le renseigne pas.
  --     On retombe alors sur une identité arithmétique toujours vraie —
  --     dû = déjà payé + reste — mais UNIQUEMENT si les deux termes sont
  --     connus : sinon on préférerait un montant faux à un montant absent.
  v_du := coalesce(
            nullif(v_ent.montant_total_du, 0),
            case
              when v_total_apres is not null and v_solde is not null
                then nullif(v_total_apres + v_solde, 0)
            end,
            nullif(v_ent.prix_installation, 0),
            nullif(v_ent.prix_abonnement_mensuel, 0),
            0
          );

  -- ── 5.b bis Le reste à payer. Déduit du dû seulement quand il était
  --     inconnu : c'est la seule reconstruction honnête possible.
  v_solde := coalesce(v_solde, greatest(v_du - coalesce(v_total_apres, 0), 0));

  -- ── 5.c L'AVANCE, le VERSEMENT et le PAYÉ.
  --     L'avance, c'est ce qui avait été versé sur ce cycle AVANT ce
  --     versement : le moteur remet le compteur du cycle à zéro à chaque
  --     nouvelle échéance, donc ce qui reste dans le cumul est bien
  --     l'acompte déjà encaissé. C'est exactement « l'avance » du patron,
  --     celle qu'il complète sous 7 jours.
  --     ⚠️ L'invariant  PAYÉ = AVANCE + VERSEMENT  est posé PAR
  --     CONSTRUCTION (et non recopié de la base), pour qu'aucune facture ne
  --     puisse afficher une addition fausse.
  v_regle  := greatest(v_montant, 0);
  v_avance := greatest(coalesce(v_total_apres, v_regle) - v_regle, 0);
  v_paye   := v_avance + v_regle;

  -- ── 5.d Nature de la facture.
  if p_origine = 'MANUEL' then
    -- État de compte : aucun versement nouveau, tout le cumul est l'avance.
    v_type   := coalesce(nullif(p_type_paiement, ''), 'MANUELLE');
    v_avance := coalesce(v_total_apres, 0);
    v_regle  := 0;
    v_paye   := v_avance;
  elsif v_solde_inconnu then
    -- Historique trop incomplet pour trancher : on le DIT au lieu d'inventer.
    v_type := 'ENCAISSEMENT';
  elsif v_solde > 0 then
    -- Cycle NON soldé : c'est l'avance de l'installation, ou son complément.
    v_type := case when v_avance > 0 then 'COMPLEMENT' else 'AVANCE' end;
  else
    -- Cycle soldé : premier cycle = installation, les suivants = mensuel.
    select count(*) into v_cycles_avant
      from (
        select id, solde_apres
          from public.paiements_abonnement
         where entreprise_id = p_entreprise_id
        union all
        select id, solde_apres
          from public.paiements_abonnements_laperle
         where entreprise_id = p_entreprise_id
      ) t
     where coalesce(t.solde_apres, 1) <= 0
       and (p_paiement_id is null or t.id <> p_paiement_id);

    v_type := case when v_cycles_avant = 0 then 'INSTALLATION'
                   else 'RENOUVELLEMENT' end;
  end if;

  -- ── 5.e Mois couverts.
  v_mois := case
              when v_jours > 0 then greatest(1, round(v_jours / 30.0)::integer)
              when v_type in ('INSTALLATION', 'RENOUVELLEMENT') then 1
              else 0
            end;

  -- ── 5.f Identité de l'émetteur (traçabilité).
  --     `mon_role(uuid)` est le RÔLE EFFECTIF (new_role prime sur l'ancien
  --     `role` hérité) : la facture doit nommer le rôle réel de l'auteur.
  select coalesce(nullif(btrim(u.nom), ''), u.email),
         public.mon_role(u.id)
    into v_nom_auteur, v_role_auteur
    from public.utilisateurs u
   where u.id = coalesce(p_auteur, auth.uid());

  -- Le rôle est un RÔLE, jamais un type de facture : un auteur inconnu
  -- (rattrapage de l'historique, script) est honnêtement nommé « SYSTEME ».
  v_nom_auteur  := coalesce(v_nom_auteur, 'Système');
  v_role_auteur := coalesce(v_role_auteur, 'SYSTEME');

  -- ── 5.g Le numéro, puis la facture.
  v_numero := public.facture_abonnement_numero_suivant();
  v_telephone := public.facture_abonnement_telephone_client(p_entreprise_id);

  insert into public.factures_abonnement (
    numero, entreprise_id,
    client_nom, client_telephone, devise,
    type_facture, statut, origine,
    periode_debut, periode_fin, mois_couverts,
    montant_installation, montant_mensuel, montant_total,
    montant_avance, montant_regle, montant_paye, solde_restant,
    genere_par, genere_par_nom, genere_par_role, genere_le,
    paiement_id, paiement_table, note
  ) values (
    v_numero, p_entreprise_id,
    coalesce(nullif(btrim(v_ent.nom), ''), 'Compte sans nom'),
    v_telephone,
    coalesce(nullif(btrim(v_ent.devise), ''), 'CDF'),
    v_type, 'EMISE', coalesce(p_origine, 'AUTO'),
    v_ent.date_activation, v_ent.date_expiration, v_mois,
    coalesce(v_ent.prix_installation, 0),
    coalesce(v_ent.prix_abonnement_mensuel, 0),
    coalesce(v_du, 0),
    v_avance, v_regle, v_paye, coalesce(v_solde, 0),
    coalesce(p_auteur, auth.uid()), v_nom_auteur, v_role_auteur, now(),
    p_paiement_id, p_paiement_table, nullif(btrim(coalesce(p_note, '')), '')
  )
  returning id into v_id;

  return v_id;
end $$;

create or replace function public.rpc_agent_ia_attributions(
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
  v_pool       integer;
  v_out        jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les attributions.';
  end if;

  v_plateforme := public.est_plateforme();

  if not (v_plateforme or public.mon_role() = 'PROPRIETAIRE') then
    raise exception 'DROIT_REFUSE|Seuls le proprietaire de la boutique ou le personnel de la plateforme consultent les attributions.';
  end if;

  --  Hors plateforme, on ne regarde QUE sa propre entreprise : l'identifiant
  --  reçu est ignoré pour qu'il ne serve pas de porte d'entrée.
  v_soc := case
             when v_plateforme then coalesce(p_entreprise_id, public.mon_entreprise_id())
             else public.mon_entreprise_id()
           end;

  if v_soc is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Aucune entreprise associee a ce compte.';
  end if;

  select coalesce(q.quotas_disponibles, 0) into v_pool
    from public.agent_ia_quotas q
   where q.utilisateur_id is null
     and q.entreprise_id = v_soc;

  v_pool := coalesce(v_pool, 0);

  select coalesce(jsonb_agg(x.obj order by x.nom), '[]'::jsonb)
    into v_out
    from (
      select coalesce(nullif(btrim(u.nom), ''), u.email, 'Collaborateur') as nom,
             jsonb_build_object(
               'utilisateur_id',       q.utilisateur_id,
               'nom',                  coalesce(nullif(btrim(u.nom), ''), u.email, 'Collaborateur'),
               'role',                 public.mon_role(q.utilisateur_id),
               'quotas_disponibles',   q.quotas_disponibles,
               'quotas_utilises_total', q.quotas_utilises_total,
               'quotas_achetes_total', q.quotas_achetes_total,
               'attribue_le',          q.attribue_le,
               'attribue_par',         q.attribue_par,
               'attribue_par_nom',     coalesce(nullif(btrim(auteur.nom), ''), auteur.email)
             ) as obj
        from public.agent_ia_quotas q
        left join public.utilisateurs u
               on u.id = q.utilisateur_id
        left join public.utilisateurs auteur
               on auteur.id = q.attribue_par
       where q.utilisateur_id is not null
         and q.entreprise_id = v_soc
    ) x;

  return jsonb_build_object(
    'entreprise_id', v_soc,
    'pool_disponible', v_pool,
    'attributions', v_out
  );
end $$;

create or replace function public.rpc_agent_codes_lister(
  p_entreprise_id uuid    default null,
  p_limite        integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plateforme boolean;
  v_finance    boolean;
  v_limite     integer := greatest(1, least(coalesce(p_limite, 100), 500));
  v_out        jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les codes.';
  end if;

  v_plateforme := public.est_plateforme();
  v_finance := public.mon_role() in ('FINANCE_LAPERLE', 'SUPER_ADMIN');

  if not (v_plateforme or public.est_agent_terrain()) then
    raise exception 'DROIT_REFUSE|Seul le personnel de la plateforme consulte les codes de validation.';
  end if;

  --  ── Balayage des demandes périmées. Sans cela, une demande jamais traitée
  --     resterait « EN_ATTENTE » pour toujours et bloquerait la suivante
  --     (index unique partiel sur les demandes ouvertes).
  update public.codes_validation_agent
     set statut = 'EXPIRE', updated_at = now()
   where statut in ('EN_ATTENTE', 'EMIS')
     and expire_le <= now();

  select coalesce(jsonb_agg(x.obj order by x.demande_le desc), '[]'::jsonb)
    into v_out
    from (
      select c.demande_le,
             jsonb_build_object(
               'id',             c.id,
               'entreprise_id',  c.entreprise_id,
               'entreprise_nom', nullif(btrim(e.nom), ''),
               'motif',          c.motif,
               'statut',         c.statut,
               'demande_par',    c.demande_par,
               'demande_par_nom', coalesce(nullif(btrim(demandeur.nom), ''), demandeur.email),
               'demande_le',     c.demande_le,
               'emis_le',        c.emis_le,
               'emis_par_nom',   coalesce(nullif(btrim(emetteur.nom), ''), emetteur.email),
               'valide_le',      c.valide_le,
               'valide_par_nom', coalesce(nullif(btrim(valide.nom), ''), valide.email),
               'expire_le',      c.expire_le,
               'minutes_restantes', case
                  when c.statut in ('EN_ATTENTE', 'EMIS')
                    then greatest(0, ceil(extract(epoch from (c.expire_le - now())) / 60))::int
                  else 0
                end,
               --  ⚠️ LE CODE N'EST RENVOYÉ QU'À LA FINANCE ET AU SUPER ADMIN.
               --     S'il apparaissait dans l'application de l'agent, il n'y
               --     aurait plus aucun échange entre la Finance et lui : le
               --     contrôle serait vidé de son sens.
               'code', case when v_finance then c.code else null end
             ) as obj
        from public.codes_validation_agent c
        left join public.entreprises e on e.id = c.entreprise_id
        left join public.utilisateurs demandeur on demandeur.id = c.demande_par
        left join public.utilisateurs emetteur  on emetteur.id  = c.emis_par
        left join public.utilisateurs valide    on valide.id    = c.valide_par
       where (p_entreprise_id is null or c.entreprise_id = p_entreprise_id)
         --  Un agent ne voit QUE ses propres demandes.
         and (v_plateforme or c.demande_par = auth.uid())
       order by c.demande_le desc
       limit v_limite
    ) x;

  return jsonb_build_object('codes', v_out, 'peut_voir_le_code', v_finance);
end $$;

create or replace function public.rpc_agent_dossiers_sans_code(
  p_limite integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := greatest(1, least(coalesce(p_limite, 100), 500));
  v_out    jsonb;
  v_total  integer;
begin
  if not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seule la plateforme consulte les dossiers a confirmer.';
  end if;

  select count(*) into v_total
    from public.entreprises e
   where e.activation_etape = 'verifie'
     and not exists (
       select 1 from public.codes_validation_agent c
        where c.entreprise_id = e.id
          and c.statut = 'UTILISE'
     );

  select coalesce(jsonb_agg(x.obj order by x.verifie_le), '[]'::jsonb)
    into v_out
    from (
      select e.verifie_le,
             jsonb_build_object(
               'entreprise_id', e.id,
               'nom',           nullif(btrim(e.nom), ''),
               'etape',         e.activation_etape,
               'statut',        e.statut::text,
               'verifie_par',   e.verifie_par,
               'verifie_par_nom', coalesce(nullif(btrim(verificateur.nom), ''), verificateur.email),
               'verifie_le',    e.verifie_le,
               --  Une demande ouverte a-t-elle au moins été faite ? Cela
               --  distingue « l'agent n'a rien demandé » de « la Finance n'a
               --  pas répondu » : deux responsabilités différentes.
               'a_demande_un_code', exists (
                 select 1 from public.codes_validation_agent c
                  where c.entreprise_id = e.id
               ),
               'demande_en_attente', exists (
                 select 1 from public.codes_validation_agent c
                  where c.entreprise_id = e.id
                    and c.statut in ('EN_ATTENTE', 'EMIS')
               )
             ) as obj
        from public.entreprises e
        left join public.utilisateurs verificateur on verificateur.id = e.verifie_par
       where e.activation_etape = 'verifie'
         and not exists (
           select 1 from public.codes_validation_agent c
            where c.entreprise_id = e.id
              and c.statut = 'UTILISE'
         )
       order by e.verifie_le
       limit v_limite
    ) x;

  return jsonb_build_object('total', coalesce(v_total, 0), 'dossiers', v_out);
end $$;


-- ============================================================================
--  2. CONTRÔLE
--
--  ⚠️ Ce contrôle vérifie DEUX choses, et la seconde est celle qui aurait
--  attrapé le défaut : que les fonctions ne mentionnent plus `nom_complet`,
--  ET que les colonnes qu'elles utilisent EXISTENT vraiment.
-- ============================================================================

do $verif_nom_utilisateur$
declare
  v_nom     text;
  v_def     text;
  v_restant text := '';
  v_manque  text := '';
begin
  --  1. Plus aucune trace de la colonne inexistante.
  foreach v_nom in array array[
    'facture_abonnement_generer_interne',
    'rpc_agent_ia_attributions',
    'rpc_agent_codes_lister',
    'rpc_agent_dossiers_sans_code'
  ] loop
    select pg_get_functiondef(p.oid) into v_def
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = v_nom;

    if v_def is null then
      raise exception 'Correctif 71 : la fonction % est introuvable — executez d''abord les correctifs 67, 68 et 69.', v_nom;
    end if;

    if position('nom_complet' in v_def) > 0 then
      v_restant := v_restant || v_nom || ' ';
    end if;
  end loop;

  if v_restant <> '' then
    raise exception 'Correctif 71 : % reference(nt) encore nom_complet — la correction n''a pas pris.', v_restant;
  end if;

  --  2. ⚠️ LE CONTRÔLE QUI MANQUAIT : les colonnes utilisées EXISTENT-elles ?
  --  C'est cette vérification, faite sur `utilisateurs`, qui aurait empêché le
  --  défaut d'arriver chez l'utilisateur.
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'utilisateurs'
       and column_name in ('nom', 'email')
     having count(*) = 2
  ) then
    raise exception 'Correctif 71 : la table utilisateurs n''a pas les colonnes nom et email — verifiez-la a la main avant d''aller plus loin.';
  end if;

  raise notice 'Correctif 71 : les 4 fonctions lisent desormais utilisateurs.nom (secours : email), et ces colonnes existent bien.';
end $verif_nom_utilisateur$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En ENTIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select 'Correctif 71 — colonne nom_complet' as chantier,
       (select count(*)
          from pg_proc p join pg_namespace n on n.oid = p.pronamespace
         where n.nspname = 'public'
           and p.proname in ('facture_abonnement_generer_interne',
                             'rpc_agent_ia_attributions',
                             'rpc_agent_codes_lister',
                             'rpc_agent_dossiers_sans_code')
           and pg_get_functiondef(p.oid) not like '%nom_complet%')
                                as fonctions_corrigees,
       (select count(*)
          from information_schema.columns
         where table_schema = 'public' and table_name = 'utilisateurs'
           and column_name in ('nom', 'email'))
                                as colonnes_nom_et_email,
       (select public.mon_role() is not null) as session_active;
