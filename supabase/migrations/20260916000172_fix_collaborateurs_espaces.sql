-- ============================================================================
--  biashara_yangu — MIGRATION 0172 : RÉPARATION DES COLLABORATEURS + VERDICT
--
--  CONSTATS LIVE (13/11/2026)
--    • 5 collaborateurs ont une entreprise mais AUCUN espace actif :
--        tshimanga Junior, Guelord, Dan, Benoît, Marlene.
--      Depuis 0170, leur portée de repli est sûre, mais autant fixer la
--      donnée : ils doivent avoir une boutique active.
--    • 2 collaborateurs n'ont AUCUNE entreprise (Urembo, joseph Issa) et
--      leur patron « La Perle » (56c414cf…) n'a lui-même aucune entreprise.
--      ⇒ non réparables sans créer une entreprise. Laissés en l'état.
--    • 6 patrons orphelins (km hôtel, Jambo mr, Patron Diag, Jean-Luc,
--      Hôtel KZ, Anaclet) n'ont AUCUNE entreprise : leurs 25 lignes
--      historiques (produits, ventes, clients, dépenses, dettes,
--      inventaires, caisse) ne peuvent pas être réattribuées.
--      ⇒ AUCUNE donnée supprimée ni déplacée : elles restent invisibles et
--        sont listées dans le verdict pour décision ultérieure.
--
--  ⚠️ Idempotent. Ne touche ni aux ventes, ni aux produits, ni à la caisse.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- Compte des corrections à effectuer (pour le verdict).
create temp table if not exists _fix_espaces as
select count(*)::integer as n
  from public.utilisateurs u
 where u.parent_id is not null
   and u.entreprise_id is not null
   and u.espace_actif_id is null
   and exists (
     select 1 from public.espaces s
      where s.entreprise_id = u.entreprise_id
        and s.actif
   );

-- ---------------------------------------------------------------------------
-- 1. UN ESPACE ACTIF POUR CHAQUE COLLABORATEUR QUI EN A UN
-- ---------------------------------------------------------------------------
--  Choix déterministe : première boutique active de SON entreprise.

update public.utilisateurs u
   set espace_actif_id = (
         select s.id
           from public.espaces s
          where s.entreprise_id = u.entreprise_id
            and s.actif
          order by s.created_at nulls last, s.nom
          limit 1)
 where u.parent_id is not null
   and u.entreprise_id is not null
   and u.espace_actif_id is null
   and exists (
     select 1 from public.espaces s
      where s.entreprise_id = u.entreprise_id
        and s.actif
   );

-- ---------------------------------------------------------------------------
-- 2. RATTAILLEMENT MULTI-ENTREPRISES (sécurité, phase 1 déjà faite)
-- ---------------------------------------------------------------------------

insert into public.collaborateurs_entreprises (
  utilisateur_id, entreprise_id, role, actif
)
select u.id,
       u.entreprise_id,
       coalesce(u.new_role, public.role_enum('VENDEUR')),
       coalesce(u.valide, 1) = 1
  from public.utilisateurs u
 where u.entreprise_id is not null
on conflict (utilisateur_id, entreprise_id) do nothing;

-- ---------------------------------------------------------------------------
-- 3. VERDICT
-- ---------------------------------------------------------------------------

select 'Correctif 0172 — espaces actifs corrigés : ' ||
       (select n from _fix_espaces) ||
       ' | collaborateurs encore sans espace : ' ||
       (select count(*) from public.utilisateurs u
         where u.parent_id is not null
           and u.entreprise_id is not null
           and u.espace_actif_id is null) ||
       ' | sans entreprise (non réparables) : ' ||
       (select count(*) from public.utilisateurs u
         where u.parent_id is not null and u.entreprise_id is null) ||
       ' || DONNÉES ORPHELINES (patrons sans entreprise, non réattribuables) : ' ||
       'produits=' || (select count(*) from public.produits p
                         left join public.espaces s on s.id = p.owner_id
                        where s.id is null) ||
       ' ventes=' || (select count(*) from public.ventes v
                        left join public.espaces s on s.id = v.owner_id
                       where s.id is null) ||
       ' clients=' || (select count(*) from public.clients c
                         left join public.espaces s on s.id = c.owner_id
                        where s.id is null) ||
       ' depenses=' || (select count(*) from public.depenses d
                          left join public.espaces s on s.id = d.owner_id
                         where s.id is null) ||
       ' dettes=' || (select count(*) from public.dettes x
                        left join public.espaces s on s.id = x.owner_id
                       where s.id is null) ||
       ' inventaires=' || (select count(*) from public.inventaires_quotidiens i
                             left join public.espaces s on s.id = i.owner_id
                            where s.id is null) ||
       ' caisse=' || (select count(*) from public.caisse ca
                        left join public.espaces s on s.id = ca.owner_id
                       where s.id is null) as verdict;

drop table if exists _fix_espaces;
