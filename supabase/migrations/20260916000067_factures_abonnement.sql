-- ============================================================================
--  biashara_yangu — CORRECTIF 67 : FACTURES D'ABONNEMENT TRAÇABLES
--  Migration 20260916000067_factures_abonnement.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : base de données uniquement.
--
--  CE QUE LE PATRON A DEMANDÉ
--  --------------------------
--  « un moyen de génération de la facture automatique traçable pour les
--    abonnements de clients, et celui qui génère cette facture, pour suivre
--    l'abonnement du client et lui envoyer sa facture via son numéro
--    WhatsApp. »
--
--  Et le contenu exigé, mot pour mot :
--  « la facture va démontrer le prix de l'installation + le prix de
--    l'abonnement par mois et ce que le client a payé dans le premier mois de
--    l'installation, car il y a l'avance et le client complète après 7 jours. »
--
--  POURQUOI CETTE FACTURE EST UNE PREUVE, ET PAS UN REÇU
--  -----------------------------------------------------
--  « c'est pour la véracité sur ce que le client paie et ce que l'agent
--    demande ». Une facture qui n'affiche que le dernier encaissement ne
--    prouve rien : le litige porte toujours sur le TOTAL DÛ, sur l'AVANCE
--    versée et sur ce qui RESTE. C'est donc un état de compte figé :
--
--      prix d'installation   → ce que vaut l'entrée (le 1er mois est inclus)
--      prix mensuel          → ce que coûteront les renouvellements
--      montant dû du cycle   → installation (1er cycle) ou mensuel (ensuite)
--      avance déjà versée    → ce qui a été payé AVANT ce versement
--      versement reçu        → ce que l'agent vient d'encaisser
--      total payé à ce jour  → le cumul
--      solde restant         → le complément que le client doit sous 7 jours
--
--  Chaque ligne est un INSTANTANÉ : elle est écrite au moment du fait et ne
--  bouge plus, même si l'entreprise est renommée ou ses prix corrigés plus
--  tard. C'est ce qui rend la facture opposable.
--
--  QUI GÉNÈRE QUOI (décision du patron)
--  -------------------------------------
--    • AUTOMATIQUE (origine = 'AUTO') : à CHAQUE encaissement, quel que soit
--      le rôle de celui qui encaisse — y compris l'agent de terrain. C'est
--      délibéré : la facture est la contrepartie de l'argent reçu, elle ne
--      doit jamais dépendre du bon vouloir de celui qui le reçoit.
--    • MANUELLE (origine = 'MANUEL') : Finance et Super Admin seulement,
--      pour éditer un état de compte ou une facture d'échéance.
--    • ENVOI WhatsApp : Finance, Super Admin ET agent de terrain.
--    • ANNULATION : Finance et Super Admin seulement (une facture annulée
--      n'est jamais supprimée : elle garde sa trace et son motif).
--
--  LES DEUX CHEMINS D'ENCAISSEMENT EXISTANTS SONT COUVERTS
--  -------------------------------------------------------
--  L'application encaisse par deux fonctions distinctes, qui écrivent dans
--  DEUX tables différentes (aucun doublon, les deux sont écoutées) :
--    • rpc_abonnement_enregistrer_paiement → paiements_abonnements_laperle
--      (colonnes type_paiement AVANCE / SOLDE / RENOUVELLEMENT) ;
--    • rpc_enregistrer_paiement            → paiements_abonnement
--      (pas de type_paiement).
--  Le déclencheur est posé sur les DEUX tables et lit le type de façon
--  tolérante, pour que la facture existe quel que soit l'écran utilisé.
--
--  UNE FACTURE NE DOIT JAMAIS FAIRE PERDRE UN PAIEMENT
--  ---------------------------------------------------
--  Le déclencheur est protégé : s'il échoue, l'encaissement est CONSERVÉ et
--  l'échec est journalisé. Les factures manquantes se réparent ensuite avec
--  `rpc_abonnement_factures_rattraper` (bouton « Réparer l'historique »).
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 66.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LA TABLE DES FACTURES
-- ============================================================================

create table if not exists public.factures_abonnement (
  id                    uuid primary key default gen_random_uuid(),
  -- Numéro officiel : FA-2026-000001 (voir §2).
  numero                text not null,
  entreprise_id         uuid not null
                        references public.entreprises (id) on delete cascade,

  -- ── Identité FIGÉE du client (recopiée au moment du fait : si
  --    l'entreprise change de nom demain, la facture reste celle d'hier).
  client_nom            text not null default '',
  client_telephone      text,
  devise                text not null default 'CDF',

  -- ── Nature et état
  type_facture          text not null default 'ENCAISSEMENT',
  statut                text not null default 'EMISE',
  origine               text not null default 'AUTO',

  -- ── Période couverte
  periode_debut         timestamptz,
  periode_fin           timestamptz,
  mois_couverts         integer not null default 0,

  -- ── Décomposition exigée par le patron
  montant_installation  numeric not null default 0,
  montant_mensuel       numeric not null default 0,
  montant_total         numeric not null default 0,
  montant_avance        numeric not null default 0,
  montant_regle         numeric not null default 0,
  montant_paye          numeric not null default 0,
  solde_restant         numeric not null default 0,

  -- ── Traçabilité de l'ÉMETTEUR (« celui qui génère cette facture »)
  genere_par            uuid references public.utilisateurs (id) on delete set null,
  genere_par_nom        text,
  genere_par_role       text,
  genere_le             timestamptz not null default now(),

  -- ── Traçabilité de l'ENVOI
  envoyee_le            timestamptz,
  envoyee_a             text,
  canal_envoi           text,
  nb_envois             integer not null default 0,

  -- ── Rattachement au fait déclencheur
  paiement_id           uuid,
  paiement_table        text,
  note                  text,

  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

comment on table public.factures_abonnement is
  'Correctif 67 — Factures d''abonnement traçables : instantané du prix d''installation, du prix mensuel, de l''avance versée, du versement reçu et du solde à compléter. Qui a généré, qui a envoyé, à quel numéro.';

comment on column public.factures_abonnement.montant_avance is
  'Ce que le client avait DÉJÀ versé sur le cycle en cours AVANT le versement de cette facture (l''avance de l''installation, avant le complément sous 7 jours).';

comment on column public.factures_abonnement.montant_regle is
  'Le versement encaissé au moment de l''émission de cette facture (0 pour une facture manuelle d''état de compte).';

comment on column public.factures_abonnement.solde_restant is
  'Ce qui reste à payer APRÈS ce versement : le complément que le client doit sous 7 jours.';

comment on column public.factures_abonnement.genere_par is
  'Auteur de la génération : le rôle qui a encaissé (facture AUTO) ou l''administrateur qui a édité la facture (MANUEL).';

-- Contraintes (ajoutées à part : la table peut déjà exister d'une exécution
-- précédente, et une migration doit être relançable).
do $factures_contraintes$
begin
  begin
    alter table public.factures_abonnement
      add constraint factures_abonnement_numero_unique unique (numero);
  exception when duplicate_object or invalid_table_definition then null;
  end;

  begin
    alter table public.factures_abonnement
      add constraint factures_abonnement_type_check
      check (type_facture in ('INSTALLATION', 'AVANCE', 'COMPLEMENT',
                              'RENOUVELLEMENT', 'ECHEANCE', 'MANUELLE',
                              'ENCAISSEMENT'));
  exception when duplicate_object then null;
  end;

  begin
    alter table public.factures_abonnement
      add constraint factures_abonnement_statut_check
      -- ⚠️ Pas de statut « PAYEE » : le règlement est déjà décrit par
      --    `solde_restant`. Un statut de plus ferait doublon avec le montant.
      check (statut in ('EMISE', 'ENVOYEE', 'ANNULEE'));
  exception when duplicate_object then null;
  end;

  begin
    alter table public.factures_abonnement
      add constraint factures_abonnement_origine_check
      check (origine in ('AUTO', 'MANUEL'));
  exception when duplicate_object then null;
  end;

  begin
    alter table public.factures_abonnement
      add constraint factures_abonnement_canal_check
      check (canal_envoi is null
             or canal_envoi in ('whatsapp', 'sms', 'appel', 'impression', 'aucun'));
  exception when duplicate_object then null;
  end;

  begin
    alter table public.factures_abonnement
      add constraint factures_abonnement_paiement_table_check
      check (paiement_table is null
             or paiement_table in ('paiements_abonnement',
                                   'paiements_abonnements_laperle'));
  exception when duplicate_object then null;
  end;
end $factures_contraintes$;

create index if not exists idx_factures_abonnement_entreprise
  on public.factures_abonnement (entreprise_id, genere_le desc);

create index if not exists idx_factures_abonnement_a_envoyer
  on public.factures_abonnement (statut, genere_le desc)
  where statut = 'EMISE';

-- Un encaissement ne peut produire qu'UNE facture automatique : la contrainte
-- rend le déclencheur rejouable sans jamais dupliquer une facture.
create unique index if not exists uq_factures_abonnement_paiement
  on public.factures_abonnement (paiement_table, paiement_id)
  where paiement_id is not null;


-- ============================================================================
--  2. NUMÉROTATION  FA-2026-000001
--     Compteur atomique : deux encaissements simultanés ne peuvent PAS
--     obtenir le même numéro (un « max() + 1 » le permettrait).
-- ============================================================================

create table if not exists public.compteurs_factures (
  prefixe         text primary key,
  derniere_valeur integer not null default 0,
  updated_at      timestamptz not null default now()
);

comment on table public.compteurs_factures is
  'Correctif 67 — Compteurs de numérotation (ex. FA-2026 → 000001, 000002…). Lu et incrémenté uniquement par les fonctions internes.';

create or replace function public.facture_abonnement_numero_suivant()
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prefixe text := 'FA-' || to_char(now(), 'YYYY');
  v_valeur  integer;
begin
  insert into public.compteurs_factures (prefixe, derniere_valeur, updated_at)
  values (v_prefixe, 1, now())
  on conflict (prefixe) do update
     set derniere_valeur = public.compteurs_factures.derniere_valeur + 1,
         updated_at      = now()
  returning derniere_valeur into v_valeur;

  return v_prefixe || '-' || lpad(v_valeur::text, 6, '0');
end $$;

comment on function public.facture_abonnement_numero_suivant() is
  'Correctif 67 — Numéro de facture suivant, au format FA-AAAA-000001. La séquence repart à 000001 chaque année.';


-- ============================================================================
--  3. QUI PEUT VOIR QUELLE FACTURE
--     Cette règle est utilisée DEUX fois : par la sécurité par ligne (§7) et
--     par les RPC de lecture. Une seule définition, donc aucune divergence
--     possible entre ce que la table laisse passer et ce que le RPC renvoie.
-- ============================================================================

create or replace function public.facture_abonnement_visible(p_entreprise_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    -- Le personnel de la plateforme voit tout.
    public.est_plateforme()
    -- Le client voit ses propres factures.
    or p_entreprise_id = public.mon_entreprise_id()
    -- L'agent de terrain voit les factures des comptes qu'il suit : c'est lui
    -- qui encaisse sur le terrain, il doit pouvoir remontrer la facture.
    or exists (
         select 1
           from public.entreprises e
          where e.id = p_entreprise_id
            and e.agent_id = auth.uid()
       );
$$;

comment on function public.facture_abonnement_visible(uuid) is
  'Correctif 67 — Visibilité d''une facture d''abonnement : plateforme, client propriétaire, ou agent de terrain du compte.';

revoke all on function public.facture_abonnement_visible(uuid) from public, anon;
grant execute on function public.facture_abonnement_visible(uuid) to authenticated;


-- ============================================================================
--  4. LE NUMÉRO WHATSAPP DU CLIENT
--     C'est le téléphone du PROPRIÉTAIRE (le champ existe depuis le
--     correctif 21). Repli sur le premier responsable connu du compte si le
--     propriétaire n'en a pas : mieux vaut un numéro approchant que rien.
-- ============================================================================

create or replace function public.facture_abonnement_telephone_client(p_entreprise_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    -- 1. Le propriétaire, priorité absolue.
    (select nullif(btrim(u.telephone), '')
       from public.utilisateurs u
      where u.entreprise_id = p_entreprise_id
        and u.role = 'PROPRIETAIRE'
        and nullif(btrim(coalesce(u.telephone, '')), '') is not null
      order by u.created_at
      limit 1),
    -- 2. Repli : n'importe quel responsable du compte joignable.
    (select nullif(btrim(u.telephone), '')
       from public.utilisateurs u
      where u.entreprise_id = p_entreprise_id
        and nullif(btrim(coalesce(u.telephone, '')), '') is not null
      order by case when u.role = 'GESTIONNAIRE' then 0 else 1 end,
               u.created_at
      limit 1)
  );
$$;

comment on function public.facture_abonnement_telephone_client(uuid) is
  'Correctif 67 — Numéro WhatsApp du client : téléphone du PROPRIÉTAIRE du compte, avec repli sur un autre responsable joignable. NULL = aucun numéro connu.';

revoke all on function public.facture_abonnement_telephone_client(uuid) from public, anon;
grant execute on function public.facture_abonnement_telephone_client(uuid) to authenticated;


-- ============================================================================
--  5. LE GÉNÉRATEUR
--     Une seule fonction d'écriture, appelée par le déclencheur automatique
--     ET par le RPC manuel : les deux chemins produisent donc EXACTEMENT la
--     même facture. C'est volontaire — un encaissement manuel et un
--     encaissement automatique ne doivent pas se présenter différemment.
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

comment on function public.facture_abonnement_generer_interne(uuid, uuid, text, text, numeric, numeric, numeric, integer, uuid, text, text) is
  'Correctif 67 — Écrit une facture d''abonnement (instantané complet). Appelée par le déclencheur automatique et par la génération manuelle : un seul chemin d''écriture.';

-- Fonction interne : personne ne l'appelle directement depuis l'application.
revoke all on function public.facture_abonnement_generer_interne(uuid, uuid, text, text, numeric, numeric, numeric, integer, uuid, text, text) from public, anon, authenticated;


-- ============================================================================
--  6. LA GÉNÉRATION AUTOMATIQUE
--     Un déclencheur sur CHACUNE des deux tables d'encaissement. Il lit le
--     type de paiement de façon tolérante : `paiements_abonnement` ne
--     possède pas la colonne `type_paiement`, l'autre si.
-- ============================================================================

create or replace function public.facture_abonnement_auto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type      text;
  v_id        uuid;
begin
  -- Rejouable : si la facture de ce versement existe déjà, on ne fait rien.
  -- (Le couple table + identifiant, car les deux tables sont écoutées.)
  if exists (
    select 1 from public.factures_abonnement f
     where f.paiement_id = NEW.id
       and f.paiement_table = TG_TABLE_NAME
  ) then
    return NEW;
  end if;

  -- Lecture TOLÉRANTE du type : la colonne n'existe que sur une des deux
  -- tables. `to_jsonb` évite toute référence à une colonne absente.
  v_type := nullif(btrim(coalesce(to_jsonb(NEW) ->> 'type_paiement', '')), '');

  begin
    v_id := public.facture_abonnement_generer_interne(
      p_entreprise_id  => NEW.entreprise_id,
      p_paiement_id    => NEW.id,
      p_paiement_table => TG_TABLE_NAME,
      p_type_paiement  => v_type,
      p_montant        => NEW.montant,
      p_total_apres    => NEW.total_apres,
      p_solde_apres    => NEW.solde_apres,
      p_prolongation   => nullif(coalesce(to_jsonb(NEW) ->> 'prolongation_jours', '0'), '')::integer,
      p_auteur         => coalesce(NEW.enregistre_par, auth.uid()),
      p_origine        => 'AUTO'
    );
  exception
    when others then
      -- ⚠️ RÈGLE ABSOLUE : un problème de facture ne doit JAMAIS faire
      -- échouer un encaissement. L'argent reçu est conservé, l'incident est
      -- journalisé, et la facture sera réparée par « rattraper ».
      begin
        insert into public.journal_audit (
          id, entreprise_id, action, utilisateur_id, details, created_at
        ) values (
          gen_random_uuid(), NEW.entreprise_id,
          'FACTURE_ABONNEMENT_ECHEC', coalesce(NEW.enregistre_par, auth.uid()),
          jsonb_build_object(
            'paiement_id',    NEW.id,
            'table',          TG_TABLE_NAME,
            'montant',        NEW.montant,
            'code',           SQLSTATE,
            'message',        SQLERRM,
            'correctif',      '67'
          ),
          now()
        );
      exception when others then null;
      end;

      raise warning 'Correctif 67 : facture non generee pour le paiement % (%) — %',
        NEW.id, TG_TABLE_NAME, SQLERRM;
      return NEW;
  end;

  return NEW;
end $$;

comment on function public.facture_abonnement_auto() is
  'Correctif 67 — Déclencheur : à CHAQUE encaissement, quelle que soit la table et quel que soit le rôle de l''agent, une facture traçable est écrite. Ne bloque jamais le paiement.';

drop trigger if exists trg_facture_abonnement_laperle on public.paiements_abonnements_laperle;
create trigger trg_facture_abonnement_laperle
  after insert on public.paiements_abonnements_laperle
  for each row
  execute function public.facture_abonnement_auto();

drop trigger if exists trg_facture_abonnement_simple on public.paiements_abonnement;
create trigger trg_facture_abonnement_simple
  after insert on public.paiements_abonnement
  for each row
  execute function public.facture_abonnement_auto();


-- ============================================================================
--  7. SÉCURITÉ PAR LIGNE
--     Lecture seule. AUCUNE écriture directe : seul le générateur (§5) et
--     les RPC (§8) écrivent, car eux seuls numérotent et tracent.
-- ============================================================================

alter table public.factures_abonnement enable row level security;
alter table public.compteurs_factures  enable row level security;

drop policy if exists factures_abonnement_lecture on public.factures_abonnement;
create policy factures_abonnement_lecture on public.factures_abonnement
  for select
  to authenticated
  using (public.facture_abonnement_visible(entreprise_id));

-- ⚠️ AUCUNE policy d'écriture n'est créée — volontairement. Sans policy
-- permissive d'INSERT/UPDATE/DELETE, toute écriture DIRECTE est refusée, même
-- à un Super Admin. C'est indispensable ici : une facture que l'on peut
-- réécrire après coup ne prouve plus rien.

-- `compteurs_factures` : aucune policy du tout → totalement inaccessible
-- depuis l'API. Seules les fonctions internes (security definer) y touchent.

revoke all on table public.factures_abonnement from anon;
revoke all on table public.compteurs_factures  from anon;
revoke insert, update, delete, truncate on table public.factures_abonnement from authenticated;
revoke insert, update, delete, truncate on table public.compteurs_factures  from authenticated;


-- ============================================================================
--  8. LES RPC DE L'APPLICATION
-- ============================================================================

--  ── 8.1 LISTER ────────────────────────────────────────────────────────────
create or replace function public.rpc_abonnement_factures_lister(
  p_entreprise_id   uuid default null,
  p_limite          integer default 100,
  p_inclure_annulees boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limite integer := greatest(1, least(coalesce(p_limite, 100), 500));
  v_out    jsonb;
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE|Connectez-vous pour consulter les factures.';
  end if;

  select coalesce(jsonb_agg(x.obj order by x.genere_le desc), '[]'::jsonb)
    into v_out
    from (
      select f.genere_le,
             jsonb_build_object(
               'id',                   f.id,
               'numero',               f.numero,
               'entreprise_id',        f.entreprise_id,
               'client_nom',           f.client_nom,
               'client_telephone',     f.client_telephone,
               'devise',               f.devise,
               'type_facture',         f.type_facture,
               'statut',               f.statut,
               'origine',              f.origine,
               'periode_debut',        f.periode_debut,
               'periode_fin',          f.periode_fin,
               'mois_couverts',        f.mois_couverts,
               'montant_installation', f.montant_installation,
               'montant_mensuel',      f.montant_mensuel,
               'montant_total',        f.montant_total,
               'montant_avance',       f.montant_avance,
               'montant_regle',        f.montant_regle,
               'montant_paye',         f.montant_paye,
               'solde_restant',        f.solde_restant,
               'genere_par',           f.genere_par,
               'genere_par_nom',       f.genere_par_nom,
               'genere_par_role',      f.genere_par_role,
               'genere_le',            f.genere_le,
               'envoyee_le',           f.envoyee_le,
               'envoyee_a',            f.envoyee_a,
               'canal_envoi',          f.canal_envoi,
               'nb_envois',            f.nb_envois,
               'note',                 f.note
             ) as obj
        from public.factures_abonnement f
       where public.facture_abonnement_visible(f.entreprise_id)
         and (p_entreprise_id is null or f.entreprise_id = p_entreprise_id)
         and (coalesce(p_inclure_annulees, false) or f.statut <> 'ANNULEE')
       order by f.genere_le desc
       limit v_limite
    ) x;

  return jsonb_build_object('factures', v_out, 'limite', v_limite);
end $$;

comment on function public.rpc_abonnement_factures_lister(uuid, integer, boolean) is
  'Correctif 67 — Liste les factures d''abonnement visibles par l''appelant (plateforme, client, ou agent du compte). Les factures annulees sont masquees par defaut.';

revoke all on function public.rpc_abonnement_factures_lister(uuid, integer, boolean) from public, anon;
grant execute on function public.rpc_abonnement_factures_lister(uuid, integer, boolean) to authenticated;


--  ── 8.2 CE QUI RESTE À ENVOYER ────────────────────────────────────────────
create or replace function public.rpc_abonnement_factures_a_envoyer(
  p_entreprise_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_total  integer;
  v_out    jsonb;
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE|Connectez-vous pour consulter les factures.';
  end if;

  select count(*) into v_total
    from public.factures_abonnement f
   where f.statut = 'EMISE'
     and public.facture_abonnement_visible(f.entreprise_id)
     and (p_entreprise_id is null or f.entreprise_id = p_entreprise_id);

  select coalesce(jsonb_agg(x.obj order by x.genere_le), '[]'::jsonb)
    into v_out
    from (
      select f.genere_le,
             jsonb_build_object(
               'id',               f.id,
               'numero',           f.numero,
               'entreprise_id',    f.entreprise_id,
               'client_nom',       f.client_nom,
               'client_telephone', f.client_telephone,
               'devise',           f.devise,
               'type_facture',     f.type_facture,
               'montant_regle',    f.montant_regle,
               'solde_restant',    f.solde_restant,
               'genere_le',        f.genere_le,
               'genere_par_nom',   f.genere_par_nom
             ) as obj
        from public.factures_abonnement f
       where f.statut = 'EMISE'
         and public.facture_abonnement_visible(f.entreprise_id)
         and (p_entreprise_id is null or f.entreprise_id = p_entreprise_id)
       order by f.genere_le
       limit 200
    ) x;

  return jsonb_build_object('total', coalesce(v_total, 0), 'factures', v_out);
end $$;

comment on function public.rpc_abonnement_factures_a_envoyer(uuid) is
  'Correctif 67 — Factures émises et pas encore envoyées : alimente le badge de l''écran Factures.';

revoke all on function public.rpc_abonnement_factures_a_envoyer(uuid) from public, anon;
grant execute on function public.rpc_abonnement_factures_a_envoyer(uuid) to authenticated;


--  ── 8.3 GÉNÉRER À LA MAIN (Finance / Super Admin) ─────────────────────────
create or replace function public.rpc_abonnement_facture_generer(
  p_entreprise_id uuid,
  p_type          text default 'MANUELLE',
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text := upper(btrim(coalesce(p_type, 'MANUELLE')));
  v_ent  public.entreprises;
  v_id   uuid;
  v_num  text;
begin
  -- Le libellé EXACT du rôle Finance est « FINANCE_LAPERLE » (enum
  -- role_utilisateur_enum). Le duo Finance + Super Admin est celui déjà
  -- retenu par le module 14 pour valider une activation.
  if public.mon_role() not in ('FINANCE_LAPERLE', 'SUPER_ADMIN') then
    raise exception 'ACCES_REFUSE|Seule la Finance ou le Super Admin peut editer une facture a la main. L''encaissement, lui, genere la facture automatiquement.';
  end if;

  if v_type not in ('MANUELLE', 'ECHEANCE') then
    v_type := 'MANUELLE';
  end if;

  select * into v_ent from public.entreprises where id = p_entreprise_id;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Le compte vise n''existe pas.';
  end if;

  v_id := public.facture_abonnement_generer_interne(
    p_entreprise_id  => p_entreprise_id,
    p_paiement_id    => null,
    p_paiement_table => null,
    p_type_paiement  => v_type,
    p_montant        => 0,
    p_total_apres    => coalesce(v_ent.montant_deja_paye, 0),
    p_solde_apres    => coalesce(v_ent.solde_restant, 0),
    p_prolongation   => 0,
    p_auteur         => auth.uid(),
    p_origine        => 'MANUEL',
    p_note           => p_note
  );

  select numero into v_num from public.factures_abonnement where id = v_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), p_entreprise_id,
    'FACTURE_ABONNEMENT_EMISE', auth.uid(),
    jsonb_build_object(
      'facture_id', v_id,
      'numero',     v_num,
      'type',       v_type,
      'origine',    'MANUEL',
      'correctif',  '67'
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'id', v_id, 'numero', v_num);
end $$;

comment on function public.rpc_abonnement_facture_generer(uuid, text, text) is
  'Correctif 67 — Édite manuellement une facture d''abonnement (Finance ou Super Admin). La facture automatique, elle, est produite par le déclencheur à chaque encaissement.';

revoke all on function public.rpc_abonnement_facture_generer(uuid, text, text) from public, anon;
grant execute on function public.rpc_abonnement_facture_generer(uuid, text, text) to authenticated;


--  ── 8.4 MARQUER ENVOYÉE (Finance / Super Admin / Agent) ───────────────────
create or replace function public.rpc_abonnement_facture_marquer_envoyee(
  p_facture_id uuid,
  p_telephone  text default null,
  p_canal      text default 'whatsapp'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facture public.factures_abonnement;
  v_tel     text;
  v_canal   text := lower(btrim(coalesce(p_canal, 'whatsapp')));
begin
  if auth.uid() is null then
    raise exception 'ACCES_REFUSE|Connectez-vous pour envoyer une facture.';
  end if;

  if v_canal not in ('whatsapp', 'sms', 'appel', 'impression', 'aucun') then
    raise exception 'CANAL_INVALIDE|Canal d''envoi inconnu : %. Utilisez whatsapp, sms, appel ou impression.', p_canal;
  end if;

  select * into v_facture
    from public.factures_abonnement
   where id = p_facture_id
   for update;

  if not found then
    raise exception 'FACTURE_INTROUVABLE|Cette facture n''existe pas.';
  end if;

  -- Le rôle qui envoie : plateforme ou agent du compte. Le client, lui, peut
  -- seulement CONSULTER sa facture — il ne peut pas certifier l'avoir envoyée.
  if not (public.est_plateforme()
          or exists (select 1 from public.entreprises e
                      where e.id = v_facture.entreprise_id
                        and e.agent_id = auth.uid())) then
    raise exception 'ACCES_REFUSE|Vous n''etes pas habilite a marquer cette facture comme envoyee.';
  end if;

  if v_facture.statut = 'ANNULEE' then
    raise exception 'FACTURE_ANNULEE|Cette facture a ete annulee : elle ne peut plus etre envoyee.';
  end if;

  v_tel := nullif(btrim(coalesce(p_telephone, '')), '');
  -- Repli sur le numéro du propriétaire si l'appelant n'en fournit aucun.
  v_tel := coalesce(v_tel, v_facture.client_telephone,
                    public.facture_abonnement_telephone_client(v_facture.entreprise_id));

  if v_tel is null and v_canal = 'whatsapp' then
    raise exception 'SANS_TELEPHONE|Aucun numero WhatsApp connu pour ce client. Renseignez le telephone du proprietaire, puis renvoyez la facture.';
  end if;

  update public.factures_abonnement
     set statut      = 'ENVOYEE',
         envoyee_le  = now(),
         envoyee_a   = v_tel,
         canal_envoi = v_canal,
         nb_envois   = nb_envois + 1,
         updated_at  = now()
   where id = p_facture_id
   returning * into v_facture;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_facture.entreprise_id,
    'FACTURE_ABONNEMENT_ENVOYEE', auth.uid(),
    jsonb_build_object(
      'facture_id', v_facture.id,
      'numero',     v_facture.numero,
      'canal',      v_canal,
      'telephone',  v_tel,
      'nb_envois',  v_facture.nb_envois,
      'correctif',  '67'
    ),
    now()
  );

  return jsonb_build_object(
    'ok',        true,
    'numero',    v_facture.numero,
    'canal',     v_facture.canal_envoi,
    'telephone', v_facture.envoyee_a,
    'nb_envois', v_facture.nb_envois
  );
end $$;

comment on function public.rpc_abonnement_facture_marquer_envoyee(uuid, text, text) is
  'Correctif 67 — Trace l''envoi d''une facture (qui, quand, à quel numéro, par quel canal). Finance, Super Admin ou agent de terrain du compte.';

revoke all on function public.rpc_abonnement_facture_marquer_envoyee(uuid, text, text) from public, anon;
grant execute on function public.rpc_abonnement_facture_marquer_envoyee(uuid, text, text) to authenticated;


--  ── 8.5 ANNULER (Finance / Super Admin) ───────────────────────────────────
create or replace function public.rpc_abonnement_facture_annuler(
  p_facture_id uuid,
  p_motif      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_facture public.factures_abonnement;
  v_motif   text := nullif(btrim(coalesce(p_motif, '')), '');
begin
  if public.mon_role() not in ('FINANCE_LAPERLE', 'SUPER_ADMIN') then
    raise exception 'ACCES_REFUSE|Seule la Finance ou le Super Admin peut annuler une facture.';
  end if;

  if v_motif is null then
    raise exception 'MOTIF_REQUIS|Indiquez le motif de l''annulation : il est conserve avec la facture.';
  end if;

  select * into v_facture
    from public.factures_abonnement
   where id = p_facture_id
   for update;

  if not found then
    raise exception 'FACTURE_INTROUVABLE|Cette facture n''existe pas.';
  end if;

  if v_facture.statut = 'ANNULEE' then
    raise exception 'DEJA_ANNULEE|Cette facture est deja annulee.';
  end if;

  -- Une facture qui atteste d'un versement RÉEL ne peut pas être annulée :
  -- l'argent a été reçu, la faire disparaître serait exactement le défaut que
  -- cette facture existe pour empêcher.
  if coalesce(v_facture.montant_regle, 0) > 0 then
    raise exception 'FACTURE_ATTESTE_UN_VERSEMENT|Cette facture atteste d''un versement de % % deja encaisse : elle ne peut pas etre annulee. Etablissez une facture rectificative.',
      v_facture.montant_regle, v_facture.devise;
  end if;

  -- ⚠️ On n'EFFACE jamais une facture : on la marque annulée et on garde le
  -- motif. Une facture supprimée ne prouverait plus rien.
  update public.factures_abonnement
     set statut     = 'ANNULEE',
         note       = coalesce(note || ' | ', '') || 'ANNULEE : ' || v_motif,
         updated_at = now()
   where id = p_facture_id;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), v_facture.entreprise_id,
    'FACTURE_ABONNEMENT_ANNULEE', auth.uid(),
    jsonb_build_object(
      'facture_id', v_facture.id,
      'numero',     v_facture.numero,
      'motif',      v_motif,
      'correctif',  '67'
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'numero', v_facture.numero, 'motif', v_motif);
end $$;

comment on function public.rpc_abonnement_facture_annuler(uuid, text) is
  'Correctif 67 — Annule une facture (motif obligatoire). La facture n''est jamais supprimée : la trace reste.';

revoke all on function public.rpc_abonnement_facture_annuler(uuid, text) from public, anon;
grant execute on function public.rpc_abonnement_facture_annuler(uuid, text) to authenticated;


--  ── 8.6 RÉPARER L'HISTORIQUE ──────────────────────────────────────────────
--     Les encaissements antérieurs à ce correctif n'ont évidemment pas de
--     facture. Cette fonction les rattrape, et permet aussi de réparer un
--     échec du déclencheur (§6). Le tri chronologique est essentiel : le
--     PREMIER cycle soldé doit être reconnu comme l'installation, avant que
--     les suivants ne soient lus comme des renouvellements.
create or replace function public.rpc_abonnement_factures_rattraper(
  p_entreprise_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paie     record;
  v_creees   integer := 0;
  v_ignorees integer := 0;
begin
  if not public.est_plateforme() then
    raise exception 'ACCES_REFUSE|Seule la plateforme peut reparer l''historique des factures.';
  end if;

  for v_paie in
    select p.id,
           p.entreprise_id,
           p.montant,
           p.total_apres,
           p.solde_apres,
           p.enregistre_par,
           p.created_at,
           'paiements_abonnements_laperle'::text as table_source,
           nullif(btrim(coalesce(p.type_paiement, '')), '') as type_paiement,
           coalesce(p.prolongation_jours, 0) as prolongation_jours
      from public.paiements_abonnements_laperle p
     where p_entreprise_id is null or p.entreprise_id = p_entreprise_id

    union all

    select p.id,
           p.entreprise_id,
           p.montant,
           p.total_apres,
           p.solde_apres,
           p.enregistre_par,
           p.created_at,
           'paiements_abonnement'::text,
           null::text,
           coalesce(p.prolongation_jours, 0)
      from public.paiements_abonnement p
     where p_entreprise_id is null or p.entreprise_id = p_entreprise_id

     order by created_at
  loop
    if exists (select 1 from public.factures_abonnement f
                where f.paiement_id = v_paie.id
                  and f.paiement_table = v_paie.table_source) then
      v_ignorees := v_ignorees + 1;
      continue;
    end if;

    begin
      perform public.facture_abonnement_generer_interne(
        p_entreprise_id  => v_paie.entreprise_id,
        p_paiement_id    => v_paie.id,
        p_paiement_table => v_paie.table_source,
        p_type_paiement  => v_paie.type_paiement,
        p_montant        => v_paie.montant,
        p_total_apres    => v_paie.total_apres,
        p_solde_apres    => v_paie.solde_apres,
        p_prolongation   => v_paie.prolongation_jours,
        p_auteur         => v_paie.enregistre_par,
        p_origine        => 'AUTO',
        p_note           => 'Facture reconstituee depuis l''historique (correctif 67).'
      );
      v_creees := v_creees + 1;
    exception when others then
      v_ignorees := v_ignorees + 1;
    end;
  end loop;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), p_entreprise_id,
    'FACTURES_ABONNEMENT_RATTRAPAGE', auth.uid(),
    jsonb_build_object(
      'creees',   v_creees,
      'ignorees', v_ignorees,
      'correctif', '67'
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'creees', v_creees, 'ignorees', v_ignorees);
end $$;

comment on function public.rpc_abonnement_factures_rattraper(uuid) is
  'Correctif 67 — Reconstruit les factures manquantes depuis les deux tables d''encaissement (historique antérieur, ou échec du déclencheur). Plateforme uniquement.';

revoke all on function public.rpc_abonnement_factures_rattraper(uuid) from public, anon;
grant execute on function public.rpc_abonnement_factures_rattraper(uuid) to authenticated;


-- ============================================================================
--  9. CONTRÔLE
-- ============================================================================

do $verif_factures_abonnement$
declare
  v_rls       boolean;
  v_lecture   integer;
  v_ecriture  integer;
  v_triggers  integer;
  v_fonctions integer;
begin
  select c.relrowsecurity into v_rls
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'factures_abonnement';

  if not coalesce(v_rls, false) then
    raise exception 'Correctif 67 : la securite par ligne n''est PAS activee sur factures_abonnement — ne poursuivez pas.';
  end if;

  select count(*) into v_lecture
    from pg_policies
   where schemaname = 'public'
     and tablename = 'factures_abonnement'
     and cmd = 'SELECT';

  if v_lecture < 1 then
    raise exception 'Correctif 67 : aucune policy de lecture — les factures seraient illisibles.';
  end if;

  select count(*) into v_ecriture
    from pg_policies
   where schemaname = 'public'
     and tablename = 'factures_abonnement'
     and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL');

  if v_ecriture > 0 then
    raise exception 'Correctif 67 : % policy(ies) d''ecriture directe subsistent — une facture reecrite ne prouve plus rien.', v_ecriture;
  end if;

  -- Les DEUX déclencheurs : sans eux, plus aucune facture automatique.
  select count(*) into v_triggers
    from pg_trigger t
    join pg_class c on c.oid = t.tgrelid
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public'
     and not t.tgisinternal
     and t.tgname in ('trg_facture_abonnement_laperle', 'trg_facture_abonnement_simple');

  if v_triggers < 2 then
    raise exception 'Correctif 67 : % declencheur(s) sur 2 seulement — un des deux chemins d''encaissement ne produirait pas de facture.', v_triggers;
  end if;

  select count(*) into v_fonctions
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('facture_abonnement_numero_suivant',
                       'facture_abonnement_visible',
                       'facture_abonnement_telephone_client',
                       'facture_abonnement_generer_interne',
                       'facture_abonnement_auto',
                       'rpc_abonnement_factures_lister',
                       'rpc_abonnement_factures_a_envoyer',
                       'rpc_abonnement_facture_generer',
                       'rpc_abonnement_facture_marquer_envoyee',
                       'rpc_abonnement_facture_annuler',
                       'rpc_abonnement_factures_rattraper');

  if v_fonctions < 11 then
    raise exception 'Correctif 67 : % fonctions sur 11 attendues — script incomplet.', v_fonctions;
  end if;

  raise notice 'Correctif 67 : factures d''abonnement operationnelles (numerotation, generation automatique sur les 2 chemins, tracabilite, envoi WhatsApp).';
end $verif_factures_abonnement$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
--  ⚠️ Ce rapport NE consomme AUCUN numéro de facture : il se contente de
--     calculer le prochain ATTENDU, sans toucher au compteur. Appeler la
--     fonction d'incrémentation ici brûlerait un numéro à chaque exécution.
-- ============================================================================

with prochain as (
  select 'FA-' || to_char(now(), 'YYYY') as prefixe
)
select 'Correctif 67 — factures d''abonnement'                             as chantier,
       (select count(*) from public.factures_abonnement)                   as factures_existantes,
       (select count(*) from pg_trigger t
          join pg_class c on c.oid = t.tgrelid
         where not t.tgisinternal
           and t.tgname in ('trg_facture_abonnement_laperle',
                            'trg_facture_abonnement_simple'))              as declencheurs_actifs,
       (select count(*) from pg_policies
         where schemaname = 'public' and tablename = 'factures_abonnement') as policies,
       (select count(*) from public.entreprises e
         where public.facture_abonnement_telephone_client(e.id) is not null) as clients_joignables_whatsapp,
       -- ⚠️ CONTRÔLE D'INTÉGRITÉ : toute facture dont l'addition est fausse
       --    est comptée ici. DOIT VALOIR 0. C'est ce qui rend la facture
       --    opposable — une addition fausse la disqualifierait.
       (select count(*)
          from public.factures_abonnement f
         where abs(f.montant_paye - (f.montant_avance + f.montant_regle)) > 0.001)
                                                                            as additions_incoherentes,
       (select coalesce(c.derniere_valeur, 0) from public.compteurs_factures c
         where c.prefixe = (select prefixe from prochain))                  as numeros_deja_emis_cette_annee,
       (select (select prefixe from prochain) || '-'
               || lpad((coalesce(c.derniere_valeur, 0) + 1)::text, 6, '0')
          from prochain p
          left join public.compteurs_factures c on c.prefixe = p.prefixe)   as prochain_numero_prevu;
