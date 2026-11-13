-- ============================================================================
--  biashara_yangu — MIGRATION 0168 : `entreprises.owner_id` RESTE LE PATRON
--
--  POURQUOI
--    0167 a posé `zzz_owner_espace` sur toutes les tables qui ont un
--    `owner_id` ET un trigger legacy `auth.uid()`. La liste retournée
--    comprenait `entreprises` :
--
--      Correctif 0167 — owner_id corrigé sur :
--        entreprises, produits, produits_lots, ventes
--
--    Or `entreprises.owner_id` (route B, migration 0145) désigne le
--    PROPRIÉTAIRE PERSONNE PHYSIQUE (un utilisateur), pas un espace.
--    Sans ce correctif, la prochaine création d'entreprise enregistrerait
--    `owner_id = mon_proprietaire()` (un UUID d'espace) et casserait la
--    relation « un patron, plusieurs entreprises ».
--
--  CORRECTIF
--    La fonction `owner_espace_actif()` devient consciente de la table :
--      • `entreprises`  → `owner_id := mon_patron()` (UUID utilisateur) ;
--      • toutes les autres tables métier → `mon_proprietaire()` (espace).
--
--  ⚠️ Aucune donnée modifiée. Idempotent.
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

  -- `entreprises.owner_id` = le PATRON (personne physique), pas l'espace.
  -- (route B : un propriétaire, plusieurs entreprises, chacune son abonnement)
  if tg_table_name = 'entreprises' then
    new.owner_id := coalesce(public.mon_patron(), new.owner_id, auth.uid());
    return new;
  end if;

  v_espace := public.mon_proprietaire();
  new.owner_id := coalesce(v_espace, new.owner_id, auth.uid());
  return new;
end;
$$;

comment on function public.owner_espace_actif() is
  'Correctifs 0167/0168 — owner_id = ESPACE de travail pour les tables métier ; pour `entreprises`, owner_id = le PATRON (mon_patron()).';

-- Verdict : rappelle la règle et liste les tables protégées.
select 'Correctif 0168 — entreprises.owner_id = mon_patron() ; tables métier : ' ||
       coalesce((
         select string_agg(t.tgrelid::regclass::text, ', '
                           order by t.tgrelid::regclass::text)
           from pg_trigger t
          where t.tgname = 'zzz_owner_espace'
            and not t.tgisinternal
       ), '(aucune)') as verdict;
