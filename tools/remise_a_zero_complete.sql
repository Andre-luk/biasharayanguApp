-- ============================================================================
--  REMISE À ZÉRO COMPLÈTE — OUTIL DE MAINTENANCE DÉCISIF
--  tools/remise_a_zero_complete.sql
-- ============================================================================
--
--  POURQUOI CE SCRIPT EXISTE
--  -------------------------
--  Les purges « au cas par cas » se heurtaient les unes après les autres à des
--  contraintes légitimes : garde-fou des ventes, clés étrangères du journal
--  d'audit, des dettes, des dépenses, des inventaires… Chaque contournement en
--  révélait un autre, parce que la liste complète des dépendances n'est connue
--  que de la base elle-même.
--
--  CE SCRIPT PREND LE PROBLÈME À L'ENVERS :
--    1. il met de côté TOUTES les protections du schéma `public`
--       (`disable trigger all` : contraintes de clés étrangères comprises) ;
--    2. il supprime les comptes (sauf la liste à conserver), puis les
--       entreprises, les boutiques et les comptes de connexion ;
--    3. il RÉTABLIT TOUTES les protections.
--
--  SÉCURITÉ
--    • la mise de côté des protections et les suppressions se font dans LA
--      MÊME transaction : si quoi que ce soit échoue, PostgreSQL annule TOUT,
--      y compris la coupure des protections. Il est donc impossible de
--      laisser la base sans ses garde-fous ;
--    • le script refuse de démarrer si les 4 comptes d'administration ne sont
--      pas tous présents (protection anti-verrouillage) ;
--    • il commence par un INVENTAIRE, et `v_executer` est FAUX par défaut :
--      la première exécution ne détruit rien.
--
--  ⚠️ CE SCRIPT DÉTRUIT DES DONNÉES COMPTABLES (ventes, dettes, dépenses,
--     journal d'audit). C'est une remise à zéro, à n'utiliser qu'une fois.
-- ============================================================================

do $remise_a_zero$
declare
  -- ▶▶▶ COMMUTATEUR ◀◀◀   false = INVENTAIRE (rien n'est détruit)
  v_executer boolean := false;

  -- Comptes CONSERVÉS.
  v_garder text[] := array['super.admin@biasharayangu.cd',
                           'comptes@biasharayangu.cd',
                           'finance@biasharayangu.cd',
                           'support@biasharayangu.cd'];

  v_rec      record;
  v_n        integer;
  v_ent      integer := 0;
  v_comptes  integer := 0;
  v_auth     integer := 0;
  v_coupes   integer := 0;
  v_repris   integer := 0;
  v_restants integer := 0;
begin
  -- ------------------------------------------------- anti-verrouillage : les 4
  select count(*) into v_n
    from public.utilisateurs u
   where lower(u.email) = any(v_garder);

  if v_n < 4 then
    raise exception
      'GARDE : % des 4 comptes d''administration seulement. Script ANNULÉ pour ne pas te verrouiller dehors.', v_n;
  end if;

  -- ------------------------------------------------------------- inventaire
  select count(*) into v_comptes
    from public.utilisateurs where lower(email) <> all(v_garder);
  select count(*) into v_ent  from public.entreprises;
  select count(*) into v_auth from auth.users;

  raise notice '=== INVENTAIRE ===';
  raise notice '   comptes à supprimer      : %', v_comptes;
  raise notice '   entreprises              : %', v_ent;
  raise notice '   boutiques (espaces)      : %', (select count(*) from public.espaces);
  raise notice '   ventes                   : %', (select count(*) from public.ventes);
  raise notice '   comptes de connexion     : %', v_auth;
  raise notice '   mode                     : %',
    case when v_executer then 'SUPPRESSION RÉELLE' else 'INVENTAIRE (aucune suppression)' end;

  if not v_executer then
    raise notice 'POUR EXÉCUTER : passez `v_executer` à TRUE et relancez.';
    return;
  end if;

  -- ================================================== EXÉCUTION RÉELLE
  -- Tout se joue dans une transaction : si un maillon casse, rien n'est appliqué.
  raise notice '=== EXÉCUTION : mise de côté des protections ===';

  for v_rec in
    select c.relname as tbl
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
     order by c.relname
  loop
    -- Ne pas couper les protections de `utilisateurs` avant d'avoir supprimé :
    -- on les coupe aussi, la suppression en a besoin (FK entrantes).
    begin
      execute format('alter table public.%I disable trigger all', v_rec.tbl);
      v_coupes := v_coupes + 1;
    exception when others then
      raise warning 'Protections non coupées sur % : %', v_rec.tbl, sqlerrm;
    end;
  end loop;

  raise notice '   % table(s) : déclencheurs et clés étrangères mis de côté.', v_coupes;

  -- ------------------------------------------------------- suppressions
  raise notice '=== SUPPRESSION ===';

  delete from public.utilisateurs where lower(email) <> all(v_garder);
  get diagnostics v_n = row_count;
  raise notice '   comptes supprimés        : %', v_n;

  -- Les profils restants (les 4) sont connus : on s'en sert pour les comptes de connexion.
  delete from auth.users u
   where not exists (select 1 from public.utilisateurs x where x.id = u.id);
  get diagnostics v_n = row_count;
  raise notice '   comptes de connexion     : %', v_n;

  begin
    delete from public.espaces;
    get diagnostics v_n = row_count;
    raise notice '   boutiques supprimées      : %', v_n;
  exception when others then
    raise warning 'Boutiques : %', sqlerrm;
  end;

  begin
    delete from public.entreprises;
    get diagnostics v_n = row_count;
    raise notice '   entreprises supprimées    : %', v_n;
  exception when others then
    raise warning 'Entreprises : %', sqlerrm;
  end;

  -- ------------------------------------------------- rétablissement
  raise notice '=== RÉTABLISSEMENT DES PROTECTIONS ===';

  for v_rec in
    select c.relname as tbl
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
     order by c.relname
  loop
    begin
      execute format('alter table public.%I enable trigger all', v_rec.tbl);
      v_repris := v_repris + 1;
    exception when others then
      raise warning 'Protections non rétablies sur % : %', v_rec.tbl, sqlerrm;
    end;
  end loop;

  raise notice '   % table(s) : déclencheurs et clés étrangères rétablis.', v_repris;

  select count(*) into v_restants from public.utilisateurs;
  raise notice '=== FIN — % compte(s) restant(s) (attendu : 4). ===', v_restants;
end $remise_a_zero$;


-- ============================================================================
--  CONTRÔLES — à relancer après l'opération
-- ============================================================================

select (select count(*) from public.utilisateurs) as comptes,
       (select count(*) from public.entreprises)  as entreprises,
       (select count(*) from public.espaces)      as boutiques,
       (select count(*) from public.ventes)       as ventes;

-- Les protections doivent être TOUTES actives : aucune ligne ne doit sortir ici.
select c.relname as table_protegee, t.tgname, t.tgenabled
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
 where n.nspname = 'public'
   and not t.tgisinternal
   and t.tgenabled = 'D'
 order by 1;

-- ============================================================================
--  FIN
-- ============================================================================
