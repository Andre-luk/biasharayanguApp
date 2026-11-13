-- ============================================================================
--  DIAGNOSTIC — qui bloque les ALTER TABLE ? (lecture seule)
--
--  Utiliser si un script de migration répond :
--    « canceling statement due to lock timeout »
--    ou « deadlock detected ».
--
--  À exécuter dans le SQL Editor. Le dernier résultat est une seule ligne.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

with s as (
  select pid,
         usename,
         state,
         wait_event_type,
         wait_event,
         now() - xact_start as duree_transaction,
         left(regexp_replace(coalesce(query, ''), '\s+', ' ', 'g'), 120) as requete
    from pg_stat_activity
   where datname = current_database()
     and pid <> pg_backend_pid()
     and state is not null
)
select 'Sessions — ' ||
       coalesce((
         select string_agg(
                  'pid ' || pid || ' [' || state || '] ' ||
                  coalesce(round(extract(epoch from duree_transaction))::text || 's', '-') ||
                  ' : ' || requete,
                  ' || ' order by pid)
           from s
       ), '(aucune autre session)') as verdict;

-- ⚠️ Si une session « idle in transaction » bloque depuis longtemps, elle peut
--    être terminée — OPÉRATION DESTRUCTRICE, à faire seulement si vous êtes
--    certain qu'aucune écriture n'est en cours. Décommentez et exécutez :
--
-- select pg_terminate_backend(pid)
--   from pg_stat_activity
--  where datname = current_database()
--    and pid <> pg_backend_pid()
--    and state in ('idle in transaction', 'idle in transaction (aborted)');
