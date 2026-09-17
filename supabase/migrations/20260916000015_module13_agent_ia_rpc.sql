-- ============================================================================
--  biashara_yangu — MODULE 13 : ASSISTANT IA (DEEPSEEK) — ÉTAPE 2 (SQL)
--
--  Petite migration COMPAGNON de l'Edge Function `agent-ia`.
--
--  POURQUOI CE FICHIER ?
--    L'Edge Function débite les quotas APRÈS chaque réponse (montant calculé
--    au caractère). Un « lire puis écrire » depuis TypeScript laisserait une
--    fenêtre de concurrence (deux messages simultanés pourraient dépasser le
--    solde). Ce débit ATOMIQUE en une seule instruction SQL est donc fait ici.
--
--  QUI PEUT L'EXÉCUTER ?
--    UNIQUEMENT le rôle `service_role` (l'Edge Function). Aucune session
--    utilisateur ne peut débiter un solde : les RPC destinées à l'application
--    (attribution par le patron, achat de packs…) viendront aux étapes
--    suivantes avec leurs propres contrôles.
--
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer ni détruire de données.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable : les tables de l'Étape 1.
do $$
declare
  v_table text;
begin
  foreach v_table in array array['agent_ia_quotas', 'agent_ia_config'] loop
    if not exists (
      select 1 from information_schema.tables
       where table_schema = 'public' and table_name = v_table
    ) then
      raise exception
        'Table public.% absente : exécutez d''abord 20260916000014_module13_agent_ia.sql.', v_table;
    end if;
  end loop;
end $$;


-- ============================================================================
--  1. `rpc_agent_ia_debiter` — DÉBIT ATOMIQUE D'UN SOLDE UTILISATEUR
-- ============================================================================
--  • une seule instruction UPDATE conditionnelle (`quotas_disponibles >= n`) :
--    jamais de solde négatif, même en cas d'appels simultanés ;
--  • incrémente `quotas_utilises_total` (statistiques) ;
--  • renvoie { ok, solde, erreur? } — l'Edge Function n'a qu'à relire `solde`.

create or replace function public.rpc_agent_ia_debiter(
  p_utilisateur uuid,
  p_quotas      integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_solde integer;
begin
  if p_utilisateur is null then
    raise exception 'DEBIT_INVALIDE|Utilisateur absent pour le débit.';
  end if;

  if p_quotas is null or p_quotas < 1 or p_quotas > 10000 then
    raise exception 'DEBIT_INVALIDE|Nombre de quotas invalide (1 à 10 000).';
  end if;

  update public.agent_ia_quotas q
     set quotas_disponibles    = q.quotas_disponibles - p_quotas,
         quotas_utilises_total = q.quotas_utilises_total + p_quotas,
         updated_at            = now()
   where q.utilisateur_id = p_utilisateur
     and q.quotas_disponibles >= p_quotas
  returning q.quotas_disponibles into v_solde;

  if not found then
    -- Ligne absente OU solde insuffisant : on renvoie le solde réel (0 si
    -- aucune ligne) pour que l'application propose d'acheter un pack.
    select q.quotas_disponibles
      into v_solde
      from public.agent_ia_quotas q
     where q.utilisateur_id = p_utilisateur;

    return jsonb_build_object(
      'ok',      false,
      'solde',   coalesce(v_solde, 0),
      'erreur',  'QUOTAS_INSUFFISANTS'
    );
  end if;

  return jsonb_build_object(
    'ok',      true,
    'solde',   v_solde,
    'debite',  p_quotas
  );
end;
$$;

comment on function public.rpc_agent_ia_debiter(uuid, integer) is
  'Module 13 — Débit atomique des quotas IA d''un utilisateur (service_role uniquement) ; renvoie { ok, solde }.';


-- ============================================================================
--  2. DROITS — SERVICE_ROLE UNIQUEMENT
-- ============================================================================
--  Une session utilisateur ne doit JAMAIS pouvoir se créditer ou se débiter :
--  le solde est mis à jour par l'Edge Function (débit) et, plus tard, par les
--  RPC d'achat/attribution (crédit).

revoke all on function public.rpc_agent_ia_debiter(uuid, integer) from public;
revoke all on function public.rpc_agent_ia_debiter(uuid, integer) from anon;
revoke all on function public.rpc_agent_ia_debiter(uuid, integer) from authenticated;
grant execute on function public.rpc_agent_ia_debiter(uuid, integer) to service_role;


-- ============================================================================
--  3. VÉRIFICATIONS
-- ============================================================================

-- 3.a La fonction existe avec la bonne signature
select p.proname, pg_get_function_arguments(p.oid) as arguments
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'rpc_agent_ia_debiter';

-- 3.b Droits : `service_role` uniquement (authenticated = f)
select proname,
       has_function_privilege('authenticated', p.oid, 'execute') as authenticated_peut,
       has_function_privilege('service_role',  p.oid, 'execute') as service_role_peut
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname = 'rpc_agent_ia_debiter';
