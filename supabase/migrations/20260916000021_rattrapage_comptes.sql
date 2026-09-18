-- ============================================================================
--  biashara_yangu — CORRECTIF 21 : RATTRAPAGE DES COMPTES SANS ENTREPRISE
--  (+ téléphone du responsable, + `rpc_entreprise_creer` v5)
--
--  ⚠️ À EXÉCUTER **APRÈS** `20260916000020_fix_enum_statuts.sql`
--     (l'enum doit être validé dans une transaction déjà close).
--
--  CE QUE FAIT CE FICHIER
--  ─────────────────────────────────────────────────────────────────────────
--  1. Ajoute la colonne `utilisateurs.telephone` (contact du responsable,
--     visible ensuite dans l'administration).
--  2. Reprend `rpc_entreprise_creer` (v5) :
--        • accepte le téléphone du responsable (`p_telephone`) ;
--        • NORMALISE le rôle : une inscription autonome SANS code boutique
--          est un PATRON. Le trigger d'inscription peut l'avoir mal traduit
--          (constaté : PROPRIETAIRE → VENDEUR) — le serveur corrige.
--  3. RATTRAPE les comptes bloqués par le bug d'enum : tout patron sans
--     entreprise reçoit son entreprise « EN ATTENTE DE VÉRIFICATION », son
--     espace de travail et son dossier d'activation — exactement comme au
--     moment de l'inscription.
--  4. Affiche des vérifications (à relire après exécution).
--
--  OÙ : Supabase → SQL Editor → coller → Run
--  IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
-- ============================================================================


-- ============================================================================
--  1. TÉLÉPHONE DU RESPONSABLE
-- ============================================================================

alter table public.utilisateurs
  add column if not exists telephone text;

comment on column public.utilisateurs.telephone is
  'Correctif 21 — Téléphone du responsable (contact de l''entreprise, affiché dans l''administration).';


-- ============================================================================
--  2. CONTRÔLE — L'ENUM EST-IL COMPLET ? (fait par le fichier 20)
-- ============================================================================
--  Doit lister : ESSAI_7J, ACTIF, SUSPENDU, EN_ATTENTE_COMPLEMENT, EXPIRE.

select unnest(enum_range(null::public.statut_abonnement_enum)) as statuts_disponibles;


-- ============================================================================
--  3. `rpc_entreprise_creer` v5 — TÉLÉPHONE + NORMALISATION DU RÔLE PATRON
-- ============================================================================
--  ⚠️ La version précédente n'existe qu'en un seul exemplaire : on la
--  supprime d'abord pour éviter une surcharge ambiguë côté PostgREST.

drop function if exists public.rpc_entreprise_creer(text);

create or replace function public.rpc_entreprise_creer(
  p_nom       text default null,
  p_telephone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user  uuid := auth.uid();
  v_exist uuid;
  v_nomu  text;
  v_nom   text;
  v_new   uuid;
  v_tel   text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour créer votre entreprise.';
  end if;

  -- Déjà rattaché ? On ne duplique pas.
  select u.entreprise_id into v_exist
    from public.utilisateurs u
   where u.id = v_user;

  if v_exist is not null then
    return jsonb_build_object('ok', true, 'deja', true, 'entreprise_id', v_exist);
  end if;

  select coalesce(nullif(btrim(u.nom), ''), u.email) into v_nomu
    from public.utilisateurs u
   where u.id = v_user;

  v_nom := nullif(btrim(coalesce(p_nom, '')), '');
  if v_nom is null then
    v_nom := 'Boutique ' || coalesce(v_nomu, 'nouvelle');
  end if;

  v_tel := nullif(btrim(coalesce(p_telephone, '')), '');

  insert into public.entreprises (nom)
  values (v_nom)
  returning id into v_new;

  -- Module 15 — espace par défaut (identifiant = UUID du patron).
  insert into public.espaces (id, entreprise_id, nom, type, actif)
  values (v_user, v_new, v_nom, 'boutique', true)
  on conflict (id) do nothing;

  -- Rattachement + téléphone + normalisation du rôle du PATRON.
  -- (Inscription sans code = patron ; on répare la traduction du trigger.)
  update public.utilisateurs
     set entreprise_id   = v_new,
         espace_actif_id = v_user,
         telephone       = coalesce(v_tel, telephone),
         new_role        = case when parent_id is null
                                then coalesce(public.role_enum('PROPRIETAIRE'), new_role)
                                else new_role end,
         role            = case when parent_id is null
                                then 'PROPRIETAIRE'
                                else role end
   where id = v_user;

  -- 🛡️ MODULE 14 — double validation obligatoire : le compte n'est PAS
  -- opérationnel tant que le gestionnaire puis la finance n'ont pas validé.
  -- `EN_ATTENTE_COMPLEMENT` = lecture seule (moteur Module 3).
  update public.entreprises
     set activation_etape = 'en_attente_verification',
         statut = 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum,
         updated_at = now()
   where id = v_new;

  insert into public.activations_entreprise (
    entreprise_id, etape, acteur_id, acteur_role, note
  ) values (
    v_new, 'soumission', v_user, public.mon_role(), 'Création du compte'
  );

  -- Trace (best-effort : ne doit jamais faire échouer la création).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      null, 'CREATION_ENTREPRISE', v_user,
      jsonb_build_object(
        'entreprise_id', v_new, 'nom', v_nom,
        'activation_etape', 'en_attente_verification',
        'telephone', v_tel
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'deja', false,
                            'entreprise_id', v_new, 'nom', v_nom,
                            'activation_etape', 'en_attente_verification');
end;
$$;

comment on function public.rpc_entreprise_creer(text, text) is
  'Module 14/15 + correctif 21 — Crée l''entreprise (EN ATTENTE DE VÉRIFICATION), son espace, rattache le patron (rôle normalisé) et enregistre son téléphone.';

revoke all on function public.rpc_entreprise_creer(text, text) from public;
revoke all on function public.rpc_entreprise_creer(text, text) from anon;
grant execute on function public.rpc_entreprise_creer(text, text) to authenticated;


-- ============================================================================
--  4. RATTRAPAGE — PATRONS SANS ENTREPRISE (inscriptions bloquées par l'enum)
-- ============================================================================
--  Pour chaque patron orphelin : entreprise + espace + dossier d'activation,
--  et rôle normalisé en PROPRIETAIRE. C'est EXACTEMENT ce que fait
--  `rpc_entreprise_creer` — mais sans avoir besoin de sa session.

do $$
declare
  r     record;
  v_nom text;
  v_new uuid;
begin
  for r in
    select u.id,
           coalesce(nullif(btrim(u.nom), ''),
                    nullif(btrim(u.email), ''),
                    'Nouveau patron') as nomu
      from public.utilisateurs u
     where u.entreprise_id is null
       and u.parent_id is null
       and coalesce(u.new_role::text, '') in ('PROPRIETAIRE', 'VENDEUR')
  loop
    v_nom := 'Boutique ' || r.nomu;

    insert into public.entreprises (nom, statut, activation_etape)
    values (v_nom,
            'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum,
            'en_attente_verification')
    returning id into v_new;

    insert into public.espaces (id, entreprise_id, nom, type, actif)
    values (r.id, v_new, v_nom, 'boutique', true)
    on conflict (id) do nothing;

    update public.utilisateurs
       set entreprise_id   = v_new,
           espace_actif_id = r.id,
           new_role        = coalesce(public.role_enum('PROPRIETAIRE'), new_role),
           role            = 'PROPRIETAIRE'
     where id = r.id;

    insert into public.activations_entreprise (
      entreprise_id, etape, acteur_id, acteur_role, note
    ) values (
      v_new, 'soumission', r.id, 'PROPRIETAIRE',
      'Rattrapage correctif 21 (inscription bloquée par l''enum)'
    );

    -- Trace (best-effort).
    begin
      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
      values (
        null, 'CREATION_ENTREPRISE', r.id,
        jsonb_build_object('entreprise_id', v_new, 'nom', v_nom,
                           'rattrapage', true)
      );
    exception when others then null;
    end;
  end loop;
end $$;


-- ============================================================================
--  5. VÉRIFICATIONS (à relire après exécution)
-- ============================================================================

-- 5.a Patrons encore sans entreprise → doit renvoyer 0 ligne.
select u.email, u.new_role
  from public.utilisateurs u
 where u.entreprise_id is null
   and u.parent_id is null
   and coalesce(u.new_role::text, '') in ('PROPRIETAIRE', 'VENDEUR');

-- 5.b Les nouvelles entreprises arrivent bien dans l'administration
--     (statut EN ATTENTE DE VÉRIFICATION).
select e.nom, e.statut, e.activation_etape, e.created_at
  from public.entreprises e
 order by e.created_at desc
 limit 10;

-- 5.c Dossiers en attente de vérification (Gestionnaire des comptes).
select a.etape, a.note, a.created_at, e.nom as entreprise
  from public.activations_entreprise a
  join public.entreprises e on e.id = a.entreprise_id
 order by a.created_at desc
 limit 10;
