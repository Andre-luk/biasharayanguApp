-- ============================================================================
--  biashara_yangu — CORRECTIF 45 : la cause de fond du « uuid = text »
--  (chargement d'un dossier d'abonnement + paiement Mobile Money)
--  ---------------------------------------------------------------------------
--  CE QUI SE PASSE
--    Deux tables HISTORIQUES de ce projet ont été créées AVANT la migration
--    vers les identifiants `uuid` :
--        • public.paiements_abonnements_laperle
--        • public.agent_ia_achats
--    Leur colonne `entreprise_id` peut y être de type TEXTE.
--
--    Or tout le moteur d'abonnement compare cette colonne à des `uuid` :
--        where p.entreprise_id = p_entreprise      -- texte = uuid
--    PostgreSQL refuse alors la comparaison et renvoie :
--        operator does not exist: uuid = text
--
--    C'est ce qui casse :
--        • le CHARGEMENT du dossier (rpc_abonnement_prix_du_cycle,
--          rpc_abonnement_type_cycle) → « Impossible de charger votre dossier » ;
--        • le PAIEMENT Mobile Money (garde-fous) ;
--        • potentiellement l'historique et les rapports.
--
--  CE QUE FAIT CE SCRIPT
--    1. Il CONVERTIT la colonne en `uuid` — mais SEULEMENT si :
--         • elle est encore en texte ;
--         • TOUTES ses valeurs sont des uuid valides (aucune perte possible).
--       Sinon il ne touche à rien et affiche un avertissement explicite.
--    2. Il fait de même pour `agent_ia_achats.entreprise_id`.
--    3. Il (re)vérifie les garde-fous Mobile Money du correctif 44.
--
--  ⚠️ AUCUNE DONNÉE PERDUE : la conversion texte → uuid est sans perte quand
--     les valeurs sont déjà des uuid (c'est le cas : elles ont été écrites par
--     l'application à partir d'identifiants uuid).
--  ⚠️ IDEMPOTENT : si la colonne est déjà en uuid, le script ne fait rien.
--  📌 OÙ L'EXÉCUTER : éditeur SQL de Supabase, APRÈS le correctif 44 (0124).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. ÉTAT DES LIEUX (avant)
-- ============================================================================

select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('paiements_abonnements_laperle', 'agent_ia_achats',
                      'paiements_serdipay')
   and column_name = 'entreprise_id'
 order by table_name;


-- ============================================================================
--  2. CONVERSION DE `paiements_abonnements_laperle.entreprise_id`
-- ============================================================================

do $$
declare
  v_type  text;
  v_total bigint;
  v_bad   bigint;
begin
  select data_type into v_type
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'paiements_abonnements_laperle'
     and column_name = 'entreprise_id';

  if v_type is null then
    raise notice 'CORRECTIF 45 — table paiements_abonnements_laperle absente : rien à faire.';
    return;
  end if;

  if v_type = 'uuid' then
    raise notice 'CORRECTIF 45 — paiements_abonnements_laperle.entreprise_id est déjà en uuid : rien à faire.';
    return;
  end if;

  -- Combien de valeurs ne sont PAS des uuid valides ?
  select count(*),
         count(*) filter (
           where entreprise_id is not null
             and btrim(entreprise_id) <> ''
             and btrim(entreprise_id) !~
                 '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
         )
    into v_total, v_bad
    from public.paiements_abonnements_laperle;

  if coalesce(v_bad, 0) > 0 then
    raise warning
      'CORRECTIF 45 — % ligne(s) sur % contiennent un identifiant non-uuid : conversion NON effectuée (rien n''a été modifié). Les correctifs 44 (comparaisons en texte) suffisent à faire fonctionner l''application.',
      v_bad, v_total;
    return;
  end if;

  -- Conversion sûre : les garde-fous 44 comparent déjà en texte, ils ne
  -- seront pas perturbés.
  alter table public.paiements_abonnements_laperle
    alter column entreprise_id type uuid
    using nullif(btrim(entreprise_id), '')::uuid;

  raise notice
    'CORRECTIF 45 — paiements_abonnements_laperle.entreprise_id converti en uuid (% lignes vérifiées).',
    v_total;
exception
  when others then
    raise warning
      'CORRECTIF 45 — conversion impossible (% : %). La colonne reste en texte ; les correctifs 44 continuent de neutraliser le problème.',
      sqlstate, sqlerrm;
end $$;


-- ============================================================================
--  3. CONVERSION DE `agent_ia_achats.entreprise_id` (achats de quotas IA)
-- ============================================================================

do $$
declare
  v_type  text;
  v_total bigint;
  v_bad   bigint;
begin
  select data_type into v_type
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'agent_ia_achats'
     and column_name = 'entreprise_id';

  if v_type is null or v_type = 'uuid' then
    return;
  end if;

  select count(*),
         count(*) filter (
           where entreprise_id is not null
             and btrim(entreprise_id) <> ''
             and btrim(entreprise_id) !~
                 '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
         )
    into v_total, v_bad
    from public.agent_ia_achats;

  if coalesce(v_bad, 0) > 0 then
    raise warning
      'CORRECTIF 45 — agent_ia_achats : % valeur(s) non-uuid : conversion NON effectuée.',
      v_bad;
    return;
  end if;

  alter table public.agent_ia_achats
    alter column entreprise_id type uuid
    using nullif(btrim(entreprise_id), '')::uuid;

  raise notice
    'CORRECTIF 45 — agent_ia_achats.entreprise_id converti en uuid (% lignes).',
    v_total;
exception
  when others then
    raise warning
      'CORRECTIF 45 — agent_ia_achats : conversion impossible (% : %).',
      sqlstate, sqlerrm;
end $$;


-- ============================================================================
--  4. LES GARDE-FOUS MOBILE MONEY RESTENT TOLÉRANTS (correctif 44)
-- ============================================================================
--    Même après conversion, on garde la comparaison en texte : elle fonctionne
--    quel que soit l'état de la base (utile si une restauration remet du texte).

create or replace function public.paiement_mm_exige_serdipay()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.mode_paiement_mobile_money(new.mode_paiement) then
    return new;
  end if;

  if new.entreprise_id is null then
    raise exception 'MOBILE_MONEY_SERDIPAY|Aucune entreprise rattachée à ce paiement : le paiement Mobile Money doit passer par SerdiPay.';
  end if;

  if not exists (
    select 1
      from public.paiements_serdipay ps
     where ps.entreprise_id::text = new.entreprise_id::text
       and ps.statut = 'en_attente'
       and ps.provider_reference is not null
       and abs(ps.montant - new.montant) < 0.01
  ) then
    raise exception 'MOBILE_MONEY_SERDIPAY|Les paiements Mobile Money passent OBLIGATOIREMENT par SerdiPay : aucun encaissement Mobile Money manuel n''est accepté. Utilisez « Payer par Mobile Money ».';
  end if;

  return new;
end;
$$;

revoke all on function public.paiement_mm_exige_serdipay()
  from public, anon, authenticated;


-- ============================================================================
--  5. CONTRÔLE APRÈS (doit afficher uuid partout)
-- ============================================================================

select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('paiements_abonnements_laperle', 'agent_ia_achats',
                      'paiements_serdipay')
   and column_name = 'entreprise_id'
 order by table_name;
