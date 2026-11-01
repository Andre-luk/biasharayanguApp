-- ============================================================================
--  biashara_yangu — CORRECTIF 96 : LE TYPE D'ACTIVITÉ PILOTE VRAIMENT LES MENUS
--  ---------------------------------------------------------------------------
--  PROBLÈMES SIGNALÉS PAR LE PATRON (31/10/2026)
--    • « Dans l'activité je ne trouve rien qui lie l'environnement module de
--       distribution : il faut qu'il y ait une activité spécifique. »
--    • « Le type d'entreprise ne joue pas son rôle même s'il est activé. »
--    • « Je vois Tournées, Ma tournée, Consignes clients, Récipients & bonus
--       dans une boutique — ce sont des points de distribution. »
--
--  POURQUOI
--    1. Le profil de modules « distribution » (créé en 0089) n'était pas
--       forcément `actif` → il n'apparaissait pas dans le sélecteur
--       d'activité de la création d'entreprise.
--    2. Choisir « Distribution » comme activité ne renseignait PAS
--       `entreprises.type_activite` : l'accueil continuait donc d'afficher
--       toutes les cartes (type NULL = fail-open).
--    3. Changer le type dans « Gestion du compte » ne touchait pas le profil
--       de modules de l'espace : l'environnement ne suivait pas.
--
--  CE QUE FAIT CETTE MIGRATION
--    1. Active le profil d'espace « distribution ».
--    2. Un déclencheur ALIGNE `entreprises.type_activite` sur le type de
--       l'espace créé ('distribution' → distribution, sinon boutique).
--    3. Rattrapage des entreprises existantes dont le type est vide.
--    4. `rpc_entreprise_definir_type_activite` (v2) aligne aussi les ESPACES :
--       passer en distribution bascule l'espace sur le profil de modules
--       « distribution » (production + tournées) ; revenir en boutique le
--       ramène sur « boutique ». Un espace spécialisé (pharmacie, hôtel…)
--       n'est JAMAIS écrasé.
--
--  ⚠️ IDEMPOTENT. Peut être relancé sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- ============================================================================
--  1. LE PROFIL D'ESPACE « DISTRIBUTION » DOIT ÊTRE PROPOSÉ
-- ============================================================================
do $$
begin
  if to_regclass('public.types_espaces_modules') is null then
    raise warning 'types_espaces_modules absente : migration 0089 non exécutée ?';
    return;
  end if;

  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'types_espaces_modules'
       and column_name = 'actif'
  ) then
    -- Sans ce `actif = true`, le profil n'apparaît pas dans le sélecteur
    -- d'activité de la création d'entreprise.
    update public.types_espaces_modules
       set actif = true
     where type = 'distribution'
       and actif is distinct from true;
  end if;

  if not exists (select 1 from public.types_espaces_modules where type = 'distribution') then
    insert into public.types_espaces_modules (type, libelle, modules)
    values (
      'distribution',
      'Distribution (production & tournées)',
      '["ventes","produits","stock","qr","caisse","clients","finance","employes",
        "rapports","assistant_ia","distribution","production"]'::jsonb
    )
    on conflict (type) do nothing;
  end if;
end $$;


-- ============================================================================
--  2. À LA CRÉATION D'UN ESPACE, LE TYPE DE L'ENTREPRISE SUIT
-- ============================================================================
--  Choix d'activité « Distribution (production & tournées) » → l'entreprise
--  devient une DISTRIBUTION ; toute autre activité → une BOUTIQUE.
--  Un type déjà renseigné explicitement n'est JAMAIS écrasé.

create or replace function public.espace_aligne_type_activite()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type      text;
  v_activite  text;
begin
  if new.entreprise_id is null then
    return new;
  end if;

  v_type := lower(btrim(coalesce(new.type, '')));
  if v_type = '' then
    return new;
  end if;

  select e.type_activite into v_activite
    from public.entreprises e
   where e.id = new.entreprise_id;

  -- Type déjà choisi (par le client, l'agent ou l'admin) : on respecte.
  if v_activite is not null and btrim(v_activite) <> '' then
    return new;
  end if;

  update public.entreprises
     set type_activite = case when v_type = 'distribution' then 'distribution'
                              else 'boutique' end,
         updated_at    = now()
   where id = new.entreprise_id;

  return new;
end;
$$;

comment on function public.espace_aligne_type_activite() is
  'Correctif 96 — déduit entreprises.type_activite du type du premier espace créé (distribution sinon boutique), sans jamais écraser un choix explicite.';

drop trigger if exists trg_espace_aligne_type_activite on public.espaces;
create trigger trg_espace_aligne_type_activite
  after insert on public.espaces
  for each row
  execute function public.espace_aligne_type_activite();


-- ============================================================================
--  3. RATTRAPAGE DES ENTREPRISES EXISTANTES (type vide)
-- ============================================================================
do $$
declare
  v_distribuees integer := 0;
  v_boutiques   integer := 0;
begin
  -- Une entreprise qui possède un espace « distribution » est une distribution.
  update public.entreprises e
     set type_activite = 'distribution',
         updated_at    = now()
   where (e.type_activite is null or btrim(e.type_activite) = '')
     and exists (
       select 1 from public.espaces s
        where s.entreprise_id = e.id
          and lower(coalesce(s.type, '')) = 'distribution'
     );
  get diagnostics v_distribuees = row_count;

  -- Toutes les autres deviennent des boutiques (leurs cartes de distribution
  -- ne doivent pas apparaître : c'est exactement le défaut signalé).
  update public.entreprises e
     set type_activite = 'boutique',
         updated_at    = now()
   where e.type_activite is null or btrim(e.type_activite) = '';
  get diagnostics v_boutiques = row_count;

  raise notice
    'Correctif 96 — type d''activité déduit : % distribution(s), % boutique(s).',
    v_distribuees, v_boutiques;
end $$;


-- ============================================================================
--  4. CHANGER LE TYPE ALIGNE AUSSI LE PROFIL DE MODULES DE L'ESPACE
-- ============================================================================

create or replace function public.rpc_entreprise_definir_type_activite(
  p_entreprise_id uuid,
  p_type          text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type    text;
  v_espaces integer := 0;
begin
  v_type := nullif(btrim(lower(coalesce(p_type, ''))), '');

  if v_type is not null and v_type not in ('boutique', 'distribution') then
    raise exception 'TYPE_ACTIVITE_INVALIDE|Type d''activité inconnu : %', p_type;
  end if;

  if not (
    public.est_plateforme()
    or p_entreprise_id = public.mon_entreprise_id()
  ) then
    raise exception 'DROIT_REFUSE|Vous ne pouvez pas modifier cette entreprise.';
  end if;

  update public.entreprises
     set type_activite = v_type,
         updated_at    = now()
   where id = p_entreprise_id;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Entreprise introuvable.';
  end if;

  -- ------------------------------------------------------------------------
  -- ALIGNEMENT DU PROFIL DE MODULES
  --   distribution → l'espace bascule sur le profil « distribution »
  --                  (production + tournées) ;
  --   boutique     → retour au profil « boutique ».
  --   ⚠️ Un espace SPÉCIALISÉ (pharmacie, hôtel, restaurant…) n'est jamais
  --      écrasé : on ne touche qu'aux profils génériques.
  -- ------------------------------------------------------------------------
  if v_type = 'distribution'
     and exists (select 1 from public.types_espaces_modules where type = 'distribution') then
    update public.espaces
       set type = 'distribution'
     where entreprise_id = p_entreprise_id
       and lower(coalesce(type, '')) in ('boutique', 'distribution');
    get diagnostics v_espaces = row_count;

  elsif v_type = 'boutique'
        and exists (select 1 from public.types_espaces_modules where type = 'boutique') then
    update public.espaces
       set type = 'boutique'
     where entreprise_id = p_entreprise_id
       and lower(coalesce(type, '')) = 'distribution';
    get diagnostics v_espaces = row_count;
  end if;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      p_entreprise_id, 'TYPE_ACTIVITE', auth.uid(),
      jsonb_build_object('type', v_type, 'espaces_aligne', v_espaces)
    );
  exception when others then
    null;
  end;

  return v_type;
end;
$$;

comment on function public.rpc_entreprise_definir_type_activite(uuid, text) is
  'Correctif 96 — définit boutique/distribution ET aligne le profil de modules de l''espace (production + tournées en distribution).';

revoke all on function public.rpc_entreprise_definir_type_activite(uuid, text) from public, anon;
grant execute on function public.rpc_entreprise_definir_type_activite(uuid, text) to authenticated;

-- ============================================================================
--  FIN — CORRECTIF 96
-- ============================================================================
