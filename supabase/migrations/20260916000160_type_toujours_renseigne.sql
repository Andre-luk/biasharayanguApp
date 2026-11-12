-- ============================================================================
--  biashara_yangu — MIGRATION 0160 : LE TYPE EST TOUJOURS RENSEIGNÉ
--  (création app, création Super Admin, changement de type : une seule règle)
--
--  QUESTIONS POSÉES (12/11/2026)
--    • Pourquoi les entreprises créées par le Super Admin ont un type, et
--      celles créées depuis l'écran d'inscription (« setup ») n'en ont pas ?
--    • Pourquoi l'écran admin « Type d'activité » ne propose que boutique et
--      distribution ?
--    • Comment changer un type « non renseigné » et le voir s'appliquer ?
--
--  RÉPONSES
--    1. Le type affiché par l'administration est `entreprises.type_activite`,
--       limité par contrainte à `boutique` / `distribution` (migration 0083).
--       Les écrans d'inscription écrivent bien `espaces.type` (le MÉTIER :
--       pharmacie, pressing, hôtel…), mais PERSONNE n'écrit
--       `entreprises.type_activite` → « Non renseigné » côté admin.
--    2. C'est voulu : ce sont deux réglages différents.
--         • `espaces.type`        = MÉTIER → profil de modules
--                                   (`lots_expiration`, `chambres`, `press_*`…)
--         • `entreprises.type_activite` = AXE COMMERCIAL
--                                   (`boutique` ou `distribution`)
--       L'erreur était de croire qu'ils devaient être saisis séparément.
--
--  CE QUE FAIT CE SCRIPT (idempotent, aucune donnée supprimée)
--    1. Un TRIGGER sur `espaces` recalcule `entreprises.type_activite`
--       automatiquement : distribution s'il existe un espace de distribution,
--       sinon boutique. Plus jamais de « non renseigné », quel que soit le
--       chemin de création (inscription, Super Admin, RPC).
--    2. Rattrapage sur toutes les entreprises existantes (même règle).
--    3. `rpc_entreprise_metier_definir(entreprise, type)` : LE changement de
--       type complet — métier de tous les espaces + axe commercial, avec
--       trace. Ouvert à la plateforme ET au propriétaire de l'entreprise.
--    4. Verdict en UNE ligne : chaque entreprise, son axe, ses espaces.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE MÉTIER D'UN ESPACE PILOTE L'AXE COMMERCIAL DE SON ENTREPRISE
-- ============================================================================
--  Une entreprise qui possède au moins un espace de distribution est une
--  entreprise de distribution ; sinon c'est une boutique. `type_activite`
--  reste donc TOUJOURS l'une des deux valeurs autorisées par la contrainte
--  de la migration 0083.

create or replace function public.sync_entreprise_type_activite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ent uuid;
  v_axe text;
begin
  v_ent := coalesce(new.entreprise_id, old.entreprise_id);
  if v_ent is null then
    return coalesce(new, old);
  end if;

  select case
           when exists (select 1 from public.espaces s
                         where s.entreprise_id = v_ent
                           and lower(btrim(coalesce(s.type, ''))) = 'distribution')
             then 'distribution'
           else 'boutique'
         end
    into v_axe;

  update public.entreprises
     set type_activite = v_axe
   where id = v_ent
     and type_activite is distinct from v_axe;

  return coalesce(new, old);
end;
$$;

comment on function public.sync_entreprise_type_activite() is
  '0160 — l''axe commercial (boutique/distribution) est déduit du MÉTIER des espaces : plus jamais de type non renseigné.';

drop trigger if exists trg_espaces_type_activite on public.espaces;
create trigger trg_espaces_type_activite
  after insert or update of type on public.espaces
  for each row execute function public.sync_entreprise_type_activite();


-- ============================================================================
--  2. RATTRAPAGE DES ENTREPRISES EXISTANTES
-- ============================================================================

update public.entreprises e
   set type_activite = sub.axe
  from (
    select s.entreprise_id,
           case when exists (
                      select 1 from public.espaces s2
                       where s2.entreprise_id = s.entreprise_id
                         and lower(btrim(coalesce(s2.type, ''))) = 'distribution')
                then 'distribution'
                else 'boutique'
           end as axe
      from public.espaces s
     group by s.entreprise_id
  ) sub
 where e.id = sub.entreprise_id
   and e.type_activite is distinct from sub.axe;


-- ============================================================================
--  3. CHANGER LE TYPE D'UNE ENTREPRISE — MÉTIER + AXE COMMERCIAL
-- ============================================================================

create or replace function public.rpc_entreprise_metier_definir(
  p_entreprise_id uuid,
  p_type          text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_type     text := lower(btrim(coalesce(p_type, '')));
  v_libelle  text;
  v_ent      public.entreprises%rowtype;
  v_patron   uuid;
  v_maj      int := 0;
  v_axe      text;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour changer le type.';
  end if;

  if p_entreprise_id is null then
    raise exception 'ENTREPRISE_INVALIDE|Aucune entreprise choisie.';
  end if;

  select * into v_ent from public.entreprises where id = p_entreprise_id;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  -- Droit : la plateforme, ou le propriétaire de CETTE entreprise.
  v_patron := public.mon_patron();
  if not (public.est_plateforme() or v_ent.owner_id = v_user or v_ent.owner_id = v_patron) then
    raise exception 'DROIT_REFUSE|Seul le propriétaire de cette entreprise (ou la plateforme) peut changer son type.';
  end if;

  -- Le type doit exister dans le référentiel (jamais de valeur inventée).
  select t.libelle into v_libelle
    from public.types_espaces_modules t
   where t.type = v_type
     and t.actif;

  if v_libelle is null then
    raise exception 'TYPE_INVALIDE|Type d''activité inconnu : choisissez une activité de la liste.';
  end if;

  -- 1. Le MÉTIER de tous les espaces de l'entreprise (pilote les modules).
  update public.espaces
     set type = v_type
   where entreprise_id = p_entreprise_id
     and coalesce(btrim(type), '') <> v_type;
  get diagnostics v_maj = row_count;

  -- 2. L'AXE COMMERCIAL (déjà posé par le trigger, on le garantit ici aussi).
  v_axe := case when v_type = 'distribution' then 'distribution' else 'boutique' end;
  update public.entreprises
     set type_activite = v_axe
   where id = p_entreprise_id
     and type_activite is distinct from v_axe;

  -- 3. Trace (best-effort).
  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      p_entreprise_id, 'TYPE_ACTIVITE_DEFINI', v_user,
      jsonb_build_object(
        'type', v_type, 'libelle', v_libelle,
        'axe_commercial', v_axe, 'espaces_modifies', v_maj));
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok',               true,
    'entreprise_id',    p_entreprise_id,
    'type',             v_type,
    'libelle',          v_libelle,
    'axe_commercial',   v_axe,
    'espaces_modifies', v_maj
  );
end;
$$;

comment on function public.rpc_entreprise_metier_definir(uuid, text) is
  '0160 — change le MÉTIER de tous les espaces d''une entreprise (modules) et met à jour son axe commercial. Plateforme ou propriétaire.';

revoke all on function public.rpc_entreprise_metier_definir(uuid, text) from public, anon;
grant execute on function public.rpc_entreprise_metier_definir(uuid, text) to authenticated;


-- ============================================================================
--  4. VERDICT — UNE SEULE LIGNE
-- ============================================================================

select jsonb_pretty(
  jsonb_build_object(
    'entreprises', (
      select coalesce(
               jsonb_agg(
                 jsonb_build_object(
                   'entreprise',     e.nom,
                   'axe_commercial', e.type_activite,
                   'metiers', (
                     select coalesce(jsonb_agg(distinct s.type), '[]'::jsonb)
                       from public.espaces s
                      where s.entreprise_id = e.id)
                 ) order by e.created_at),
               '[]'::jsonb)
        from public.entreprises e),
    'types_disponibles', (
      select coalesce(jsonb_agg(t.type order by t.type), '[]'::jsonb)
        from public.types_espaces_modules t
       where t.actif),
    'a_faire',
      'Dans l''application : Super Admin → entreprise → « Changer le type » '
      'liste maintenant TOUTES les activités. Se déconnecter/reconnecter '
      'ensuite pour recharger les modules.'
  )
) as verdict;
