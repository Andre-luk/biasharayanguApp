-- ============================================================================
--  DIAGNOSTIC — contraintes de clé étrangère portant sur `owner_id`
--
--  POURQUOI
--    Le multi-entreprises utilise `owner_id` pour désigner l'ESPACE de
--    travail (UUID d'une ligne de `public.espaces`). Or le schéma d'origine
--    semble avoir défini `owner_id` comme référençant `public.utilisateurs`
--    (l'utilisateur). C'est ce qui provoque :
--      • le trigger legacy `owner_id := auth.uid()` sur `produits` ;
--      • l'erreur `fk_produit_owner` dès qu'on écrit pour une 2ᵉ entreprise.
--
--  À EXÉCUTER DANS LE SQL EDITOR — lecture seule. Copier UNIQUEMENT le
--  dernier résultat (une ligne de texte, aucun secret).
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- 1) Toutes les FK dont la définition mentionne owner_id.
with fks as (
  select conrelid::regclass::text          as table_concernee,
         conname                            as contrainte,
         pg_get_constraintdef(oid)          as definition
    from pg_constraint
   where contype = 'f'
     and pg_get_constraintdef(oid) ilike '%owner_id%'
)
select 'FK owner_id — ' ||
       coalesce(
         (select string_agg(
                   table_concernee || ' : ' || contrainte || ' → ' || definition,
                   ' || '
                   order by table_concernee, contrainte)
            from fks),
         '(aucune)') as verdict;
