-- ============================================================================
--  biashara_yangu — MIGRATION 0167 : `owner_id` = ESPACE DE TRAVAIL PARTOUT
--
--  CONSTAT LIVE (13/11/2026, compte josephissa@gmail.com)
--    • Espace actif = HEKIMA PHARMA.
--    • Vente de test : `rpc_vente_valider` reçoit `v_owner = mon_proprietaire()`
--      (= HEKIMA)… mais la ligne `ventes` est enregistrée avec
--      `owner_id = 07a0cdf1…` = UUID de l'utilisateur = espace Urembo.
--    • Résultat : le chiffre d'affaires de la pharmacie reste à 0 et celui de
--      la boutique augmente. Les rapports sont faux, silencieusement.
--
--  CAUSE (la même que pour `produits`, corrigée en 0165/0166)
--    Des triggers LEGACY (hors migrations), présents sur plusieurs tables
--    métier, réécrivent `owner_id := auth.uid()` à l'insertion. Depuis le
--    multi-entreprises, `owner_id` doit porter l'ESPACE (`mon_proprietaire()`).
--    Les deux valeurs ne coïncident que pour l'espace par défaut.
--
--  CORRECTIF — GÉNÉRIQUE, PAS TABLE PAR TABLE
--    1. Une fonction unique `owner_espace_actif()` :
--         • rôles plateforme → ne touche à rien ;
--         • sinon → `owner_id := coalesce(mon_proprietaire(), owner_id, auth.uid())`.
--    2. Un trigger `zzz_owner_espace` posé UNIQUEMENT sur les tables qui
--       cumulent :
--         – une colonne `owner_id` ;
--         – au moins un trigger legacy dont la fonction mentionne `auth.uid()`.
--       (PostgreSQL exécute les triggers `before insert` par ordre
--        alphabétique : `zzz_…` passe donc en dernier et corrige la valeur.)
--
--  ⚠️ Aucune donnée modifiée. Idempotent. Réexécutable sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

create or replace function public.owner_espace_actif()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_espace uuid;
begin
  -- Administration plateforme : elle choisit explicitement le propriétaire.
  if public.est_plateforme() then
    return new;
  end if;

  v_espace := public.mon_proprietaire();
  new.owner_id := coalesce(v_espace, new.owner_id, auth.uid());
  return new;
end;
$$;

comment on function public.owner_espace_actif() is
  'Correctif 0167 — toute écriture métier appartient à l''ESPACE DE TRAVAIL actif (mon_proprietaire()), jamais à l''identité de l''utilisateur.';

do $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select distinct c.relname as table_name
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_proc p on p.oid = t.tgfoid
     where not t.tgisinternal
       and c.relkind = 'r'
       and c.relnamespace = 'public'::regnamespace
       and (
         pg_get_functiondef(p.oid) ilike '%auth.uid()%'
         -- Filet de sécurité : certains triggers legacy sont nommés
         -- « …owner… » sans que leur corps contienne littéralement auth.uid()
         -- (appel d'une fonction utilitaire).
         or p.proname ilike '%owner%'
       )
       and exists (
         select 1
           from information_schema.columns col
          where col.table_schema = 'public'
            and col.table_name = c.relname
            and col.column_name = 'owner_id'
       )
     order by c.relname
  loop
    execute format(
      'drop trigger if exists zzz_owner_espace on public.%I',
      r.table_name);
    execute format(
      'create trigger zzz_owner_espace before insert on public.%I '
      'for each row execute function public.owner_espace_actif()',
      r.table_name);
    n := n + 1;
  end loop;

  raise notice 'Correctif 0167 : % table(s) protégée(s).', n;
end $$;

-- Verdict (une seule ligne) : tables protégées par le trigger correctif.
select 'Correctif 0167 — owner_id corrigé sur : ' ||
       coalesce((
         select string_agg(t.tgrelid::regclass::text, ', '
                           order by t.tgrelid::regclass::text)
           from pg_trigger t
          where t.tgname = 'zzz_owner_espace'
            and not t.tgisinternal
       ), '(aucune table — vérifier les triggers legacy)') as verdict;
