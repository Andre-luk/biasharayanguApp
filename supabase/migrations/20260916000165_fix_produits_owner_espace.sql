-- ============================================================================
--  biashara_yangu — MIGRATION 0165 : LA BONNE ENTREPRISE POUR `produits`
--
--  BUG CONFIRMÉ EN DIRECT (13/11/2026, compte josephissa@gmail.com)
--    • Le patron possède Urembo Market (boutique) et HEKIMA PHARMA
--      (pharmacie). L'espace actif est HEKIMA.
--    • Il crée un médicament : l'application envoie `owner_id = HEKIMA`,
--      mais la ligne est enregistrée avec `owner_id = 07a0cdf1…`, qui est
--      l'UUID de l'UTILISATEUR — et cet UUID est aussi celui de l'espace par
--      défaut (Urembo Market).
--    • Conséquence : l'article n'apparaît PAS dans HEKIMA (la liste filtre
--      sur l'espace actif) et `rpc_lot_recevoir` répond `HORS_BOUTIQUE`.
--      C'est exactement le symptôme « l'article s'enregistre mais la liste
--      est vide ».
--
--  CAUSE
--    Un trigger LEGACY (hors migrations) réécrit `produits.owner_id` avec
--    `auth.uid()` à CHAQUE insertion. Depuis le multi-entreprises, `owner_id`
--    doit porter l'ESPACE DE TRAVAIL (`mon_proprietaire()`), pas l'identité
--    de l'utilisateur. Les deux coïncident pour le compte mono-boutique,
--    d'où l'absence de symptôme historique — mais divergent dès la 2ᵉ
--    entreprise.
--
--  CORRECTIF (additif, sans toucher au trigger inconnu)
--    Un trigger `before insert` nommé pour s'exécuter APRÈS les triggers
--    existants (ordre alphabétique des noms en PostgreSQL) réaffecte
--    `owner_id` à l'espace de travail actif.
--      • rôles plateforme (est_plateforme) : intacts — ils insèrent pour le
--        compte qu'ils administrent ;
--      • collaborateur : `mon_proprietaire()` le ramène dans SON entreprise ;
--      • patron : l'espace qu'il a sélectionné dans l'application.
--
--  ⚠️ Ne modifie aucune donnée existante. Idempotent.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

create or replace function public.produits_owner_espace_actif()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_espace uuid;
begin
  -- Administration plateforme : elle choisit explicitement le propriétaire
  -- (production d'étiquettes, import…). On ne réécrit jamais son choix.
  if public.est_plateforme() then
    return new;
  end if;

  v_espace := public.mon_proprietaire();

  -- Repli : aucun espace actif lisible (session incomplète) → on garde la
  -- valeur fournie, puis l'identité de l'utilisateur, comme avant.
  new.owner_id := coalesce(v_espace, new.owner_id, auth.uid());

  return new;
end;
$$;

comment on function public.produits_owner_espace_actif() is
  'Correctif 0165 — un article créé depuis l''application appartient à l''ESPACE DE TRAVAIL actif (mon_proprietaire()), jamais à l''identité de l''utilisateur.';

-- Le nom commence par `zzz_` : PostgreSQL exécute les triggers `before insert`
-- dans l'ordre alphabétique de leur nom, donc APRÈS un éventuel trigger
-- legacy nommé `trg_…`.
drop trigger if exists zzz_produits_owner_espace on public.produits;
create trigger zzz_produits_owner_espace
  before insert on public.produits
  for each row
  execute function public.produits_owner_espace_actif();

-- Verdict : ordre réel des triggers `before insert` sur `produits`
-- (l'éditeur SQL n'affiche que le dernier résultat).
select 'Correctif 0165 — triggers before insert sur produits : ' ||
       coalesce((
         select string_agg(t.tgname, ' → ' order by t.tgname)
           from pg_trigger t
          where t.tgrelid = 'public.produits'::regclass
            and not t.tgisinternal
            and (t.tgtype & 2) = 2   -- 2 = BEFORE
       ), '(aucun)') ||
       ' | notre trigger : ' ||
       case
         when exists (
           select 1 from pg_trigger t
            where t.tgrelid = 'public.produits'::regclass
              and t.tgname = 'zzz_produits_owner_espace'
         ) then 'INSTALLÉ (doit être le dernier de la liste)'
         else 'ABSENT — relisez l''erreur ci-dessus'
       end as verdict;
