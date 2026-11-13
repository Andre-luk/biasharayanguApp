-- ============================================================================
--  biashara_yangu — MIGRATION 0169 : LES FK `owner_id` → ESPACES (GÉNÉRAL)
--
--  CONSTAT LIVE (13/11/2026)
--    2ᵉ vente dans HEKIMA (espace actif) :
--      insert or update on table "ventes" violates foreign key constraint
--      "fk_vente_owner"
--
--    Même cause que pour `produits` (0166) : la contrainte d'origine exige un
--    UUID d'UTILISATEUR, alors que `owner_id` porte désormais l'ESPACE.
--    Tant qu'elle existe, AUCUNE vente ne peut être enregistrée dans une
--    deuxième entreprise — le blocage est silencieux côté application.
--
--  CORRECTIF GÉNÉRAL
--    Pour TOUTES les tables publiques dont une FK `(owner_id)` référence
--    `public.utilisateurs` :
--      1. suppression de la contrainte ;
--      2. ajout de `<ancien_nom>_espace` → `public.espaces(id)`
--         (`NOT VALID` : les lignes historiques restent intactes, les
--         nouvelles écritures sont contrôlées).
--
--    ⛔ EXCEPTION VOLONTAIRE : `public.entreprises`.
--       `entreprises.owner_id` désigne le PATRON (personne physique) et doit
--       continuer à référencer `utilisateurs`. (Route B : un propriétaire,
--       plusieurs entreprises.)
--
--  ⚠️ Aucune donnée supprimée ni modifiée. Idempotent.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- ⚠️ Un ALTER TABLE prend un verrou exclusif : si l'application est en train
--    d'écrire (ou garde une transaction ouverte), PostgreSQL peut refuser
--    d'attendre indûment. On échoue proprement au bout de 15 s plutôt que de
--    provoquer un deadlock ; il suffit alors de relancer (script idempotent).
set local lock_timeout = '15s';

do $$
declare
  r           record;
  v_nouveau   text;
  n           integer := 0;
begin
  for r in
    select conrelid::regclass as table_concernee,
           conname,
           conrelid
      from pg_constraint
     where contype = 'f'
       and conrelid <> 'public.entreprises'::regclass
       and pg_get_constraintdef(oid) ~* 'foreign key \(owner_id\) references (public\.)?utilisateurs'
     order by conrelid::regclass::text, conname
  loop
    -- 1. Retirer l'ancienne contrainte (utilisateurs).
    execute format(
      'alter table %s drop constraint %I',
      r.table_concernee, r.conname);

    -- 2. Poser la contrainte « espace » (si elle n'existe pas déjà).
    v_nouveau := left(r.conname, 50) || '_espace';
    if not exists (
      select 1 from pg_constraint
       where conrelid = r.conrelid
         and conname = v_nouveau
    ) then
      execute format(
        'alter table %s add constraint %I foreign key (owner_id) '
        'references public.espaces(id) not valid',
        r.table_concernee, v_nouveau);
    end if;

    n := n + 1;
  end loop;

  raise notice 'Correctif 0169 : % contrainte(s) owner_id convertie(s).', n;
end $$;

-- Verdict : liste des contraintes owner_id restantes (doit pointer vers
-- espaces, sauf entreprises → utilisateurs).
select 'Correctif 0169 — FK owner_id : ' ||
       coalesce((
         select string_agg(
                  c.conrelid::regclass::text || ' : ' ||
                  pg_get_constraintdef(c.oid),
                  ' || '
                  order by c.conrelid::regclass::text)
           from pg_constraint c
          where c.contype = 'f'
            and pg_get_constraintdef(c.oid) ilike '%owner_id%'
       ), '(aucune)') as verdict;
