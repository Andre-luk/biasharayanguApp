-- ============================================================================
--  biashara_yangu — MIGRATION 0166 : `produits.owner_id` DÉSIGNE UN ESPACE
--
--  CONSTAT LIVE (13/11/2026)
--    `insert into produits (owner_id = <espace HEKIMA>)` échoue :
--
--      insert or update on table "produits" violates foreign key
--      constraint "fk_produit_owner"
--
--    La contrainte d'origine pointe vers `public.utilisateurs` : elle exige
--    un UUID d'UTILISATEUR. Depuis le multi-entreprises, `owner_id` porte
--    l'ESPACE de travail (`mon_proprietaire()`), qui n'est un UUID
--    d'utilisateur que pour l'espace par défaut — d'où le trigger legacy
--    `owner_id := auth.uid()` et le symptôme « article enregistré dans la
--    pharmacie, liste vide ».
--
--  CORRECTIF
--    1. Supprime la contrainte `fk_produit_owner` (référence utilisateurs).
--    2. La remplace par `fk_produit_owner_espace` → `public.espaces(id)`.
--       `NOT VALID` : elle s'applique à TOUTES les nouvelles lignes sans
--       exiger la réécriture des lignes historiques (aucune donnée touchée).
--
--  ⚠️ Idempotent. Aucune donnée supprimée ni modifiée.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  -- 1. Ancienne contrainte : owner_id → utilisateurs.
  if exists (
    select 1 from pg_constraint
     where conrelid = 'public.produits'::regclass
       and conname = 'fk_produit_owner'
  ) then
    alter table public.produits drop constraint fk_produit_owner;
  end if;

  -- 2. Nouvelle contrainte : owner_id → espaces (même sémantique que
  --    mon_proprietaire()).
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.produits'::regclass
       and conname = 'fk_produit_owner_espace'
  ) then
    alter table public.produits
      add constraint fk_produit_owner_espace
      foreign key (owner_id) references public.espaces(id)
      not valid;
  end if;
end $$;

comment on constraint fk_produit_owner_espace on public.produits is
  'Correctif 0166 — owner_id désigne l''ESPACE de travail (public.espaces), pas un utilisateur. NOT VALID : les lignes historiques sont conservées.';

-- Verdict (une seule ligne).
select 'Correctif 0166 — produits.owner_id : ' ||
       coalesce((
         select string_agg(c.conname || ' → ' || pg_get_constraintdef(c.oid), ' | '
                           order by c.conname)
           from pg_constraint c
          where c.conrelid = 'public.produits'::regclass
            and c.contype = 'f'
            and pg_get_constraintdef(c.oid) ilike '%owner_id%'
       ), '(aucune contrainte FK sur owner_id)') as verdict;
