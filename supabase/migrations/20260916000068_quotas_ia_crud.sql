-- ============================================================================
--  biashara_yangu — CORRECTIF 68 : CRUD DES QUOTAS IA
--  Migration 20260916000068_quotas_ia_crud.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : base de données uniquement.
--
--  CE QUI MANQUAIT
--  ---------------
--  Les quotas de l'assistant IA étaient réglables, mais leur CATALOGUE ne
--  l'était pas :
--
--    1. LES PACKS étaient CODÉS EN DUR dans l'application
--       (10 / 20 / 50 / 100 quotas, prix strictement proportionnels au pack
--       de 10). Le Super Admin ne pouvait donc PAS créer un pack de 30, ni
--       faire une remise sur les gros packs. Un prix commercial qui vit dans
--       le code ne se change pas sans republier l'application.
--       → table `agent_ia_packs`, éditable, avec repli applicatif si la
--         migration n'est pas encore exécutée (règle fail-open du projet).
--
--    2. UNE ATTRIBUTION NE POUVAIT PAS ÊTRE REPRISE. Un patron qui
--       distribuait 50 quotas à un vendeur parti le lendemain n'avait aucun
--       moyen de récupérer son dû : les quotas restaient bloqués sur un
--       compte inutilisé.
--       → `rpc_agent_ia_attribution_annuler` (les quotas NON CONSOMMÉS
--         retournent au pool de l'entreprise).
--
--    3. AUCUN GESTE COMMERCIAL possible. Offrir des quotas d'essai à un
--       prospect demandait de passer par SQL.
--       → `rpc_agent_ia_offrir` (Super Admin, motif obligatoire).
--
--    4. LE PATRON NE VOYAIT PAS OÙ ÉTAIENT SES QUOTAS. `rpc_agent_ia_etat`
--       liste les collaborateurs sans leur solde : impossible de savoir qui
--       détient quoi, donc impossible de décider quoi reprendre.
--       → `rpc_agent_ia_attributions` (soldes par membre + pool).
--
--  POURQUOI `audit_niveau` EST RECRÉÉE ICI
--  ---------------------------------------
--  Le journal d'audit accepte des noms d'action LIBRES, mais les noms
--  inconnus retombent au niveau « INFO » — le moins grave. Un GESTE
--  COMMERCIAL (des quotas offerts, donc de l'argent donné) serait donc
--  journalisé au même niveau qu'un simple affichage de page : c'est
--  exactement le genre d'angle mort qu'un journal d'audit ne doit pas avoir.
--  La fonction est donc reprise À L'IDENTIQUE et complétée — jamais
--  réécrite de mémoire. ⚠️ Si une migration ultérieure l'a déjà étendue,
--  LA SIENNE EST LA RÉFÉRENCE : ne relancez pas ce fichier après elle.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 67.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE CATALOGUE DES PACKS
-- ============================================================================

create table if not exists public.agent_ia_packs (
  id         uuid primary key default gen_random_uuid(),
  --  Un pack EST une taille : deux packs de 30 quotas n'auraient aucun sens
  --  et rendraient le choix du client ambigu.
  quotas     integer not null check (quotas between 1 and 100000),
  prix       numeric not null default 0 check (prix >= 0),
  libelle    text,
  ordre      integer not null default 0,
  actif      boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.utilisateurs (id) on delete set null
);

comment on table public.agent_ia_packs is
  'Correctif 68 — Catalogue des packs de quotas IA (taille, prix, ordre). Remplace les 4 packs codés en dur dans l''application : un prix commercial doit pouvoir changer sans republier l''application.';

create unique index if not exists idx_m68_packs_quotas
  on public.agent_ia_packs (quotas);

create index if not exists idx_m68_packs_actifs
  on public.agent_ia_packs (ordre, quotas)
  where actif;

-- ── Reprise des 4 packs existants : AUCUNE invention de prix.
--    Le pack de 10 garde le prix de référence réglé dans `agent_ia_config`,
--    les autres conservent EXACTEMENT leur proportionnalité d'origine.
--    `on conflict do nothing` : une seconde exécution ne touche à rien.
insert into public.agent_ia_packs (quotas, prix, libelle, ordre)
select p.quotas, p.prix, p.libelle, p.ordre
  from (
    select 10  as quotas, coalesce(c.prix_pack_10_quotas, 1000)        as prix,
           'Pack découverte' as libelle, 10 as ordre
      from public.agent_ia_config c
    union all
    select 20, coalesce(c.prix_pack_10_quotas, 1000) * 2, 'Pack standard', 20
      from public.agent_ia_config c
    union all
    select 50, coalesce(c.prix_pack_10_quotas, 1000) * 5, 'Pack boutique', 30
      from public.agent_ia_config c
    union all
    select 100, coalesce(c.prix_pack_10_quotas, 1000) * 10, 'Pack professionnel', 40
      from public.agent_ia_config c
  ) p
on conflict (quotas) do nothing;

-- Si aucune configuration n'existe encore, on pose la grille de référence
-- (prix du pack de 10 = 1 000 CDF, comme le défaut du module 13).
insert into public.agent_ia_packs (quotas, prix, libelle, ordre)
select p.quotas, p.prix, p.libelle, p.ordre
  from (
    select 10  as quotas, 1000::numeric       as prix, 'Pack découverte' as libelle, 10 as ordre
    union all select 20,  2000::numeric, 'Pack standard', 20
    union all select 50,  5000::numeric, 'Pack boutique', 30
    union all select 100, 10000::numeric, 'Pack professionnel', 40
  ) p
 where not exists (select 1 from public.agent_ia_packs)
on conflict (quotas) do nothing;

alter table public.agent_ia_packs enable row level security;

-- La grille des offres est PUBLIQUE : un client doit pouvoir voir ce qu'il
-- achète. Aucune policy d'écriture : les modifications passent par les RPC,
-- qui vérifient le rôle et laissent une trace.
drop policy if exists agent_ia_packs_lecture on public.agent_ia_packs;
create policy agent_ia_packs_lecture on public.agent_ia_packs
  for select
  to authenticated
  using (true);

revoke all on table public.agent_ia_packs from anon;
revoke insert, update, delete, truncate on table public.agent_ia_packs from authenticated;


-- ============================================================================
--  2. LIRE LES PACKS
-- ============================================================================

create or replace function public.rpc_agent_ia_packs(
  p_tous boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_out jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les packs.';
  end if;

  -- « tous » (packs désactivés compris) réservé à la plateforme : un client
  -- n'a pas à voir une offre qu'on lui cache.
  if coalesce(p_tous, false) and not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seule la plateforme consulte les packs desactives.';
  end if;

  select coalesce(jsonb_agg(x.obj order by x.ordre, x.quotas), '[]'::jsonb)
    into v_out
    from (
      select p.ordre,
             p.quotas,
             jsonb_build_object(
               'id',              p.id,
               'quotas',          p.quotas,
               'prix',            p.prix,
               'libelle',         coalesce(nullif(btrim(p.libelle), ''),
                                          p.quotas || ' quotas'),
               'ordre',           p.ordre,
               'actif',           p.actif,
               'prix_par_quota',  case when p.quotas > 0
                                       then round(p.prix / p.quotas, 2)
                                       else 0 end
             ) as obj
        from public.agent_ia_packs p
       where coalesce(p_tous, false) or p.actif
    ) x;

  return jsonb_build_object('packs', v_out);
end $$;

comment on function public.rpc_agent_ia_packs(boolean) is
  'Correctif 68 — Catalogue des packs de quotas IA. Les packs désactivés ne sont visibles que de la plateforme.';

revoke all on function public.rpc_agent_ia_packs(boolean) from public, anon;
grant execute on function public.rpc_agent_ia_packs(boolean) to authenticated;


-- ============================================================================
--  3. ÉDITER UN PACK (Super Admin)
-- ============================================================================

create or replace function public.rpc_agent_ia_pack_enregistrer(
  p_id      uuid    default null,
  p_quotas  integer default null,
  p_prix    numeric default null,
  p_libelle text    default null,
  p_ordre   integer default null,
  p_actif   boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pack     public.agent_ia_packs;
  v_quotas   integer := p_quotas;
  v_prix     numeric := p_prix;
  v_ordre    integer := p_ordre;
  v_actif    boolean := p_actif;
  v_libelle  text    := nullif(btrim(coalesce(p_libelle, '')), '');
  v_doublon  uuid;
  v_creer    boolean := (p_id is null);
begin
  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin regle le catalogue des packs de quotas.';
  end if;

  if v_creer then
    --  À la création, la taille et le prix sont indispensables : un pack sans
    --  prix obligerait l'application à en inventer un.
    if v_quotas is null or v_quotas < 1 then
      raise exception 'PARAMETRES_INVALIDES|Indiquez le nombre de quotas du nouveau pack.';
    end if;
    if v_prix is null or v_prix < 0 then
      raise exception 'PARAMETRES_INVALIDES|Indiquez le prix du nouveau pack.';
    end if;

    --  Message CLAIR plutôt que la violation d'index brute : le Super Admin
    --  doit comprendre qu'un pack de cette taille existe déjà.
    select p.id into v_doublon
      from public.agent_ia_packs p
     where p.quotas = v_quotas;
    if v_doublon is not null then
      raise exception 'PACK_EXISTE|Un pack de % quotas existe deja : modifiez-le au lieu d''en creer un second.', v_quotas;
    end if;

    insert into public.agent_ia_packs (quotas, prix, libelle, ordre, actif, updated_by)
    values (
      v_quotas,
      v_prix,
      v_libelle,
      coalesce(v_ordre, v_quotas),
      coalesce(v_actif, true),
      auth.uid()
    )
    returning * into v_pack;
  else
    select * into v_pack
      from public.agent_ia_packs
     where id = p_id
     for update;

    if not found then
      raise exception 'PACK_INTROUVABLE|Ce pack n''existe pas.';
    end if;

    --  Changer la TAILLE d'un pack reviendrait à le remplacer : on refuse,
    --  pour ne pas laisser croire que les clients ont acheté « 30 quotas »
    --  alors qu'ils en ont reçu 20. Les prix, libellés et l'ordre se
    --  modifient librement — la taille ne bouge JAMAIS.
    if v_quotas is not null and v_quotas <> v_pack.quotas then
      raise exception 'TAILLE_VERROUILLEE|La taille d''un pack ne peut pas changer (% quotas). Creez un nouveau pack et desactivez celui-ci.', v_pack.quotas;
    end if;

    if v_prix is not null and v_prix < 0 then
      raise exception 'PARAMETRES_INVALIDES|Le prix ne peut pas etre negatif.';
    end if;

    update public.agent_ia_packs
       set prix       = coalesce(v_prix, prix),
           libelle    = coalesce(v_libelle, libelle),
           ordre      = coalesce(v_ordre, ordre),
           actif      = coalesce(v_actif, actif),
           updated_at = now(),
           updated_by = auth.uid()
     where id = p_id
     returning * into v_pack;

    --  Désactiver le DERNIER pack actif laisserait un catalogue vide : plus
    --  aucune demande d'achat ne serait possible. On refuse.
    if not v_pack.actif
       and not exists (select 1 from public.agent_ia_packs p
                        where p.actif and p.id <> v_pack.id)
    then
      raise exception 'DERNIER_PACK_ACTIF|Impossible de desactiver le dernier pack actif : le catalogue serait vide et plus aucun achat ne serait possible.';
    end if;
  end if;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), null,
    case when v_creer then 'AGENT_IA_PACK' else 'AGENT_IA_PACK_ENREGISTRE' end,
    auth.uid(),
    jsonb_build_object(
      'pack_id',  v_pack.id,
      'quotas',   v_pack.quotas,
      'prix',     v_pack.prix,
      'libelle',  v_pack.libelle,
      'actif',    v_pack.actif,
      'creation', v_creer,
      'correctif', '68'
    ),
    now()
  );

  return jsonb_build_object(
    'ok',     true,
    'id',     v_pack.id,
    'quotas', v_pack.quotas,
    'prix',   v_pack.prix,
    'actif',  v_pack.actif,
    'creation', v_creer
  );
end $$;

comment on function public.rpc_agent_ia_pack_enregistrer(uuid, integer, numeric, text, integer, boolean) is
  'Correctif 68 — Crée ou modifie un pack de quotas IA (Super Admin). La TAILLE d''un pack existant est verrouillée ; les prix et l''état sont libres.';

revoke all on function public.rpc_agent_ia_pack_enregistrer(uuid, integer, numeric, text, integer, boolean) from public, anon;
grant execute on function public.rpc_agent_ia_pack_enregistrer(uuid, integer, numeric, text, integer, boolean) to authenticated;


-- ============================================================================
--  4. SUPPRIMER UN PACK (Super Admin)
--     ⚠️ On ne supprime QUE si le pack n'a jamais servi de base à un achat
--        connu... ce qui n'est pas traçable : les achats conservent le NOMBRE
--        de quotas, pas le pack. La suppression est donc autorisée, mais le
--        dernier pack actif est protégé (§3) et l'opération est journalisée.
-- ============================================================================

create or replace function public.rpc_agent_ia_pack_supprimer(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pack public.agent_ia_packs;
begin
  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin supprime un pack de quotas.';
  end if;

  select * into v_pack
    from public.agent_ia_packs
   where id = p_id
   for update;

  if not found then
    raise exception 'PACK_INTROUVABLE|Ce pack n''existe pas.';
  end if;

  if v_pack.actif
     and not exists (select 1 from public.agent_ia_packs p
                      where p.actif and p.id <> v_pack.id)
  then
    raise exception 'DERNIER_PACK_ACTIF|Impossible de supprimer le dernier pack actif : le catalogue serait vide. Desactivez-le apres en avoir cree un autre, ou modifiez-le.';
  end if;

  delete from public.agent_ia_packs where id = p_id;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), null,
    'AGENT_IA_PACK_SUPPRIME', auth.uid(),
    jsonb_build_object(
      'pack_id', v_pack.id,
      'quotas',  v_pack.quotas,
      'prix',    v_pack.prix,
      'correctif', '68'
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'quotas', v_pack.quotas);
end $$;

comment on function public.rpc_agent_ia_pack_supprimer(uuid) is
  'Correctif 68 — Supprime un pack de quotas IA (Super Admin), sauf le dernier pack actif.';

revoke all on function public.rpc_agent_ia_pack_supprimer(uuid) from public, anon;
grant execute on function public.rpc_agent_ia_pack_supprimer(uuid) to authenticated;


-- ============================================================================
--  5. VOIR LES ATTRIBUTIONS (où sont passés les quotas ?)
--     `rpc_agent_ia_etat` liste les collaborateurs SANS leur solde : le
--     patron ne pouvait donc pas savoir qui détenait quoi, ni décider quoi
--     reprendre. Cette lecture comble ce manque sans toucher à l'existant.
-- ============================================================================

create or replace function public.rpc_agent_ia_attributions(
  p_entreprise_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_plateforme boolean;
  v_soc        uuid;
  v_pool       integer;
  v_out        jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les attributions.';
  end if;

  v_plateforme := public.est_plateforme();

  if not (v_plateforme or public.mon_role() = 'PROPRIETAIRE') then
    raise exception 'DROIT_REFUSE|Seuls le proprietaire de la boutique ou le personnel de la plateforme consultent les attributions.';
  end if;

  --  Hors plateforme, on ne regarde QUE sa propre entreprise : l'identifiant
  --  reçu est ignoré pour qu'il ne serve pas de porte d'entrée.
  v_soc := case
             when v_plateforme then coalesce(p_entreprise_id, public.mon_entreprise_id())
             else public.mon_entreprise_id()
           end;

  if v_soc is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Aucune entreprise associee a ce compte.';
  end if;

  select coalesce(q.quotas_disponibles, 0) into v_pool
    from public.agent_ia_quotas q
   where q.utilisateur_id is null
     and q.entreprise_id = v_soc;

  v_pool := coalesce(v_pool, 0);

  select coalesce(jsonb_agg(x.obj order by x.nom), '[]'::jsonb)
    into v_out
    from (
      select coalesce(nullif(btrim(u.nom), ''), u.email, 'Collaborateur') as nom,
             jsonb_build_object(
               'utilisateur_id',       q.utilisateur_id,
               'nom',                  coalesce(nullif(btrim(u.nom), ''), u.email, 'Collaborateur'),
               'role',                 public.mon_role(q.utilisateur_id),
               'quotas_disponibles',   q.quotas_disponibles,
               'quotas_utilises_total', q.quotas_utilises_total,
               'quotas_achetes_total', q.quotas_achetes_total,
               'attribue_le',          q.attribue_le,
               'attribue_par',         q.attribue_par,
               'attribue_par_nom',     coalesce(nullif(btrim(auteur.nom), ''), auteur.email)
             ) as obj
        from public.agent_ia_quotas q
        left join public.utilisateurs u
               on u.id = q.utilisateur_id
        left join public.utilisateurs auteur
               on auteur.id = q.attribue_par
       where q.utilisateur_id is not null
         and q.entreprise_id = v_soc
    ) x;

  return jsonb_build_object(
    'entreprise_id', v_soc,
    'pool_disponible', v_pool,
    'attributions', v_out
  );
end $$;

comment on function public.rpc_agent_ia_attributions(uuid) is
  'Correctif 68 — Soldes par collaborateur et pool restant : montre au proprietaire ou sont passes ses quotas avant d''en reprendre.';

revoke all on function public.rpc_agent_ia_attributions(uuid) from public, anon;
grant execute on function public.rpc_agent_ia_attributions(uuid) to authenticated;


-- ============================================================================
--  6. REPRENDRE UNE ATTRIBUTION
--     Les quotas NON CONSOMMÉS d'un membre retournent au pool de
--     l'entreprise. Les quotas DÉJÀ UTILISÉS ne sont jamais reprenables :
--     le service a été rendu, il est dû.
-- ============================================================================

create or replace function public.rpc_agent_ia_attribution_annuler(
  p_utilisateur uuid,
  p_quotas      integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_plateforme boolean;
  v_dest       public.utilisateurs;
  v_soc        uuid;
  v_solde      integer;
  v_retrait    integer;
  v_pool_after integer;
  v_ma_soc     uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour reprendre des quotas.';
  end if;

  if p_utilisateur is null then
    raise exception 'PARAMETRES_INVALIDES|Choisissez le collaborateur dont vous reprenez les quotas.';
  end if;

  v_plateforme := public.est_plateforme();

  if not (v_plateforme or public.mon_role() = 'PROPRIETAIRE') then
    raise exception 'DROIT_REFUSE|Seuls le proprietaire de la boutique ou le personnel de la plateforme reprennent des quotas.';
  end if;

  select * into v_dest from public.utilisateurs where id = p_utilisateur;
  if v_dest.id is null then
    raise exception 'UTILISATEUR_INCONNU|Ce collaborateur n''existe pas.';
  end if;

  --  Même résolution d'entreprise que l'attribution (correctif 56) : les deux
  --  opérations doivent viser EXACTEMENT le même périmètre, sinon on
  --  créditerait un pool que l'on n'a pas débité.
  select coalesce(v_dest.entreprise_id, p.entreprise_id) into v_soc
    from public.utilisateurs p
   where p.id = v_dest.parent_id;

  if v_soc is null then
    v_soc := coalesce(v_dest.entreprise_id, v_dest.parent_id);
  end if;

  if v_soc is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Impossible de determiner l''entreprise de ce collaborateur.';
  end if;

  if not v_plateforme then
    v_ma_soc := public.mon_entreprise_id();
    if v_ma_soc is not null and v_soc <> v_ma_soc then
      raise exception 'HORS_BOUTIQUE|Ce collaborateur n''appartient pas a votre entreprise.';
    end if;
  end if;

  --  Verrou sur la ligne du membre : on lit puis on écrit sans laisser une
  --  attribution concurrente se glisser entre les deux.
  select q.quotas_disponibles into v_solde
    from public.agent_ia_quotas q
   where q.utilisateur_id = p_utilisateur
   for update;

  if v_solde is null then
    raise exception 'ATTRIBUTION_INEXISTANTE|Ce collaborateur ne detient aucune attribution de quotas.';
  end if;

  if v_solde <= 0 then
    raise exception 'AUCUN_QUOTA_A_REPRENDRE|Ce collaborateur a deja consomme tous ses quotas : il n''y a rien a reprendre.';
  end if;

  --  `p_quotas` absent = tout reprendre.
  v_retrait := case
                 when p_quotas is null then v_solde
                 else p_quotas
               end;

  if v_retrait < 1 then
    raise exception 'PARAMETRES_INVALIDES|Indiquez un nombre de quotas a reprendre (1 minimum).';
  end if;

  if v_retrait > v_solde then
    raise exception 'QUOTAS_INSUFFISANTS|Ce collaborateur ne detient que % quotas non consommes.', v_solde;
  end if;

  update public.agent_ia_quotas
     set quotas_disponibles = quotas_disponibles - v_retrait,
         updated_at         = now()
   where utilisateur_id = p_utilisateur;

  --  Retour au pool de l'entreprise (créé s'il n'existe pas encore).
  insert into public.agent_ia_quotas (utilisateur_id, entreprise_id, quotas_disponibles)
  values (null, v_soc, v_retrait)
  on conflict (entreprise_id) where utilisateur_id is null
  do update set
    quotas_disponibles = public.agent_ia_quotas.quotas_disponibles + excluded.quotas_disponibles,
    updated_at         = now()
  returning quotas_disponibles into v_pool_after;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), v_soc, 'AGENT_IA_ATTRIBUTION_ANNULEE', v_user,
    jsonb_build_object(
      'destinataire',  p_utilisateur,
      'quotas_repris', v_retrait,
      'solde_membre_avant', v_solde,
      'solde_membre_apres', v_solde - v_retrait,
      'pool_apres',    v_pool_after,
      'boutique',      v_soc,
      'par_plateforme', v_plateforme,
      'correctif',     '68'
    ),
    now()
  );

  return jsonb_build_object(
    'ok',                true,
    'quotas_repris',     v_retrait,
    'solde_destinataire', v_solde - v_retrait,
    'pool_restant',      v_pool_after
  );
end $$;

comment on function public.rpc_agent_ia_attribution_annuler(uuid, integer) is
  'Correctif 68 — Reprend les quotas NON CONSOMMES d''un collaborateur et les rend au pool de l''entreprise. Les quotas deja utilises ne sont jamais reprenables.';

revoke all on function public.rpc_agent_ia_attribution_annuler(uuid, integer) from public, anon;
grant execute on function public.rpc_agent_ia_attribution_annuler(uuid, integer) to authenticated;


-- ============================================================================
--  7. GESTE COMMERCIAL — OFFRIR DES QUOTAS (Super Admin)
--     Des quotas offerts ne sont PAS des quotas achetés : `quotas_achetes_
--     total` n'est jamais touché. C'est ce qui permet au patron de voir la
--     différence entre ce qu'il a payé et ce qu'on lui a offert.
-- ============================================================================

create or replace function public.rpc_agent_ia_offrir(
  p_quotas        integer,
  p_motif         text,
  p_utilisateur   uuid default null,
  p_entreprise_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_motif  text := nullif(btrim(coalesce(p_motif, '')), '');
  v_dest   public.utilisateurs;
  v_soc    uuid;
  v_apres  integer;
begin
  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin accorde un geste commercial sur les quotas.';
  end if;

  if p_quotas is null or p_quotas < 1 or p_quotas > 10000 then
    raise exception 'PARAMETRES_INVALIDES|Indiquez un nombre de quotas a offrir (1 a 10 000).';
  end if;

  --  Un cadeau sans justification est un trou dans la caisse : le motif est
  --  OBLIGATOIRE et conservé tel quel dans le journal.
  if v_motif is null or length(v_motif) < 3 then
    raise exception 'MOTIF_REQUIS|Indiquez le motif du geste commercial : il est conserve dans le journal (3 caracteres minimum).';
  end if;

  if p_utilisateur is not null then
    select * into v_dest from public.utilisateurs where id = p_utilisateur;
    if v_dest.id is null then
      raise exception 'UTILISATEUR_INCONNU|Ce collaborateur n''existe pas.';
    end if;

    select coalesce(v_dest.entreprise_id, p.entreprise_id) into v_soc
      from public.utilisateurs p
     where p.id = v_dest.parent_id;
    v_soc := coalesce(v_soc, v_dest.entreprise_id, v_dest.parent_id);

    insert into public.agent_ia_quotas (
      utilisateur_id, entreprise_id, quotas_disponibles, attribue_par, attribue_le
    ) values (
      p_utilisateur, v_soc, p_quotas, auth.uid(), now()
    )
    on conflict (utilisateur_id)
    do update set
      quotas_disponibles = public.agent_ia_quotas.quotas_disponibles + excluded.quotas_disponibles,
      attribue_par       = excluded.attribue_par,
      attribue_le        = excluded.attribue_le,
      updated_at         = now()
    returning quotas_disponibles into v_apres;
  else
    if p_entreprise_id is null then
      raise exception 'PARAMETRES_INVALIDES|Precisez le beneficiaire : une entreprise ou un collaborateur.';
    end if;
    v_soc := p_entreprise_id;

    --  ⚠️ Aucune ligne `quotas_achetes_total` ici : c'est la marque du don.
    insert into public.agent_ia_quotas (utilisateur_id, entreprise_id, quotas_disponibles)
    values (null, v_soc, p_quotas)
    on conflict (entreprise_id) where utilisateur_id is null
    do update set
      quotas_disponibles = public.agent_ia_quotas.quotas_disponibles + excluded.quotas_disponibles,
      updated_at         = now()
    returning quotas_disponibles into v_apres;
  end if;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), v_soc, 'AGENT_IA_GESTE', auth.uid(),
    jsonb_build_object(
      'beneficiaire_utilisateur', p_utilisateur,
      'beneficiaire_entreprise',  v_soc,
      'quotas_offerts',           p_quotas,
      'solde_apres',              v_apres,
      'motif',                    v_motif,
      'correctif',                '68'
    ),
    now()
  );

  return jsonb_build_object(
    'ok',             true,
    'quotas_offerts', p_quotas,
    'solde_apres',    v_apres
  );
end $$;

comment on function public.rpc_agent_ia_offrir(integer, text, uuid, uuid) is
  'Correctif 68 — Geste commercial : offre des quotas a une entreprise ou a un collaborateur (Super Admin). Motif obligatoire ; `quotas_achetes_total` n''est jamais touche, donc un don reste distinguable d''un achat.';

revoke all on function public.rpc_agent_ia_offrir(integer, text, uuid, uuid) from public, anon;
grant execute on function public.rpc_agent_ia_offrir(integer, text, uuid, uuid) to authenticated;


-- ============================================================================
--  7 bis. LE MONTANT DEMANDÉ DOIT SUIVRE LE CATALOGUE
--
--  ⚠️ INCOHÉRENCE QUE LES PACKS AURAIENT CRÉÉE, ET QUE CE BLOC FERME.
--  `rpc_agent_ia_demander_achat` REFUSAIT toute taille hors de la liste
--  figée 10/20/50/100, et calculait le montant par proportionnalité au prix
--  du pack de 10 lu dans `agent_ia_config`.
--
--  Conséquence si on n'y touchait pas : le Super Admin aurait pu créer un
--  pack de 30 quotas à prix remisé... que personne n'aurait pu commander
--  (« PACK_INVALIDE »), et qui, s'il avait été commandé, aurait été facturé
--  au prix proportionnel — donc PAS le prix affiché. Un catalogue dont le
--  prix affiché n'est pas le prix facturé est pire que pas de catalogue.
--
--  RÈGLE : quand le catalogue existe, IL FAIT FOI. Quand il est absent
--  (migration pas encore exécutée), le comportement d'origine est conservé
--  À L'IDENTIQUE — aucune régression pendant la fenêtre de déploiement.
-- ============================================================================

create or replace function public.rpc_agent_ia_demander_achat(
  p_nombre_quotas integer,
  p_mode_paiement text default 'especes',
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user       uuid := auth.uid();
  v_plateforme boolean;
  v_owner      uuid;
  v_config     public.agent_ia_config%rowtype;
  v_mode       text := lower(btrim(coalesce(p_mode_paiement, 'especes')));
  v_catalogue  integer;
  v_prix       numeric;
  v_montant    numeric(12,2);
  v_id         uuid;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour demander des quotas.';
  end if;

  if p_nombre_quotas is null or p_nombre_quotas < 1 then
    raise exception 'PACK_INVALIDE|Choisissez un pack de quotas.';
  end if;

  if v_mode not in ('especes', 'mobile_money', 'carte', 'virement') then
    raise exception 'MODE_INVALIDE|Mode de paiement inconnu.';
  end if;

  select * into v_config from public.agent_ia_config limit 1;
  if v_config.id is null or v_config.actif is not true then
    raise exception 'ASSISTANT_INDISPONIBLE|L''assistant IA n''est pas active.';
  end if;

  -- ── Le CATALOGUE (correctif 68) décide du prix.
  select count(*) into v_catalogue
    from public.agent_ia_packs p
   where p.actif;

  if v_catalogue > 0 then
    select p.prix into v_prix
      from public.agent_ia_packs p
     where p.quotas = p_nombre_quotas
       and p.actif;

    if not found then
      --  Un pack DESACTIVE ne doit pas pouvoir etre commande : c'est tout
      --  l'interet de l'avoir retire de la grille.
      raise exception 'PACK_INVALIDE|Ce pack n''est pas propose. Choisissez-en un dans la liste.';
    end if;
  else
    --  Repli : catalogue absent (migration non executee). Grille d'origine.
    if p_nombre_quotas not in (10, 20, 50, 100) then
      raise exception 'PACK_INVALIDE|Choisissez un pack de 10, 20, 50 ou 100 quotas.';
    end if;
    v_prix := round((p_nombre_quotas::numeric / 10.0) * v_config.prix_pack_10_quotas, 2);
  end if;

  -- Montant calcule cote SERVEUR : jamais envoye par l'application.
  v_montant := round(coalesce(v_prix, 0), 2);

  v_plateforme := public.est_plateforme();
  v_owner := public.mon_proprietaire();
  if v_owner is null then
    v_owner := v_user;
  end if;

  insert into public.agent_ia_achats (
    utilisateur_id, entreprise_id, nombre_quotas, montant_cdf,
    mode_paiement, statut, statut_paiement, enregistre_par, note
  ) values (
    v_user,
    case when v_plateforme then null else v_owner end,
    p_nombre_quotas, v_montant,
    v_mode, 'demande', 'impaye', v_user, nullif(btrim(coalesce(p_note, '')), '')
  )
  returning id into v_id;

  insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
  values (
    null, 'AGENT_IA_ACHAT', v_user,
    jsonb_build_object(
      'etape',         'demande',
      'achat_id',      v_id,
      'nombre_quotas', p_nombre_quotas,
      'montant_cdf',   v_montant,
      'mode_paiement', v_mode,
      'boutique',      case when v_plateforme then null else v_owner end,
      'prix_du_catalogue', v_catalogue > 0,
      'correctif',     '68'
    )
  );

  return jsonb_build_object(
    'achat_id',        v_id,
    'statut',          'demande',
    'statut_paiement', 'impaye',
    'nombre_quotas',   p_nombre_quotas,
    'montant_cdf',     v_montant
  );
end;
$$;

comment on function public.rpc_agent_ia_demander_achat(integer, text, text) is
  'Module 13 / correctif 68 — Demande d''achat d''un pack de quotas. Le MONTANT vient du catalogue des packs (agent_ia_packs) ; repli proportionnel au pack de 10 tant que le catalogue n''est pas renseigne.';

revoke all on function public.rpc_agent_ia_demander_achat(integer, text, text) from public, anon;
grant execute on function public.rpc_agent_ia_demander_achat(integer, text, text) to authenticated;


-- ============================================================================
--  8. NIVEAUX D'AUDIT DES NOUVELLES ACTIONS
--     ⚠️ Reprise À L'IDENTIQUE de la version en vigueur + les actions des
--        correctifs 67 et 68. Aucune ligne n'est réécrite de mémoire.
-- ============================================================================

create or replace function public.audit_niveau(p_action text)
returns text
language sql
immutable
as $$
  select case upper(btrim(coalesce(p_action, '')))
    -- CRITIQUE : argent, droits, cycle de vie des comptes, devise.
    when 'CREATION_ENTREPRISE'        then 'CRITIQUE'
    when 'CHANGEMENT_STATUT'          then 'CRITIQUE'
    when 'REACTIVATION'               then 'CRITIQUE'
    when 'CHANGEMENT_ROLE'            then 'CRITIQUE'
    when 'PERMISSIONS_MODIFIEES'      then 'CRITIQUE'
    when 'PERMISSIONS_REINITIALISEES' then 'CRITIQUE'
    when 'PRIX_MODIFIE'               then 'CRITIQUE'
    when 'ANNULATION_VENTE'           then 'CRITIQUE'
    when 'VENTE_SUPPRIMEE'            then 'CRITIQUE'
    when 'UTILISATEUR_SUPPRIME'       then 'CRITIQUE'
    when 'ENTREPRISE_SUPPRIMEE'       then 'CRITIQUE'
    when 'AGENT_IA_CONFIG'            then 'CRITIQUE'
    when 'DEVISE_CONFIG'              then 'CRITIQUE'
    -- HAUT : opérations financières et mouvements de stock.
    when 'VENTE'                      then 'HAUT'
    when 'PAIEMENT_ENREGISTRE'        then 'HAUT'
    when 'PAIEMENT_DETTE'             then 'HAUT'
    when 'DETTE'                      then 'HAUT'
    when 'DEPENSE'                    then 'HAUT'
    when 'CLOTURE_CAISSE'             then 'HAUT'
    when 'APPROVISIONNEMENT'          then 'HAUT'
    when 'AJUSTEMENT'                 then 'HAUT'
    when 'INVENTAIRE'                 then 'HAUT'
    when 'STOCK_MODIFIE'              then 'HAUT'
    when 'ARTICLE_SUPPRIME'           then 'HAUT'
    when 'CHANGEMENT_ACTIVATION'      then 'HAUT'
    when 'IMPORT_PRODUITS'            then 'HAUT'
    when 'AGENT_IA_ACHAT'             then 'HAUT'
    -- 🏨 MODULE 16 C2 — hôtel.
    when 'CHECKOUT_SEJOUR'            then 'HAUT'
    when 'SEJOUR_ENCAISSE'            then 'HAUT'
    -- 🍽️ MODULE 16 C3 — restaurant.
    when 'COMMANDE_ENCAISSEE'         then 'HAUT'
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    when 'EVENEMENT_ENCAISSE'         then 'HAUT'
    when 'EVENEMENT_ANNULE'           then 'HAUT'
    -- 🥖 MODULE 16 C5 — boulangerie.
    when 'PRODUCTION_TERMINEE'        then 'HAUT'
    -- MOYEN : administration courante et sessions.
    when 'CONNEXION'                  then 'MOYEN'
    when 'DECONNEXION'                then 'MOYEN'
    when 'CONNEXION_ECHEC'            then 'MOYEN'
    when 'ARTICLE_CREE'               then 'MOYEN'
    when 'ARTICLE_MODIFIE'            then 'MOYEN'
    when 'CONDITIONNEMENT_AJOUTE'     then 'MOYEN'
    when 'CONDITIONNEMENT_MODIFIE'    then 'MOYEN'
    when 'CONDITIONNEMENT_SUPPRIME'   then 'MOYEN'
    when 'UTILISATEUR_CREE'           then 'MOYEN'
    when 'UTILISATEUR_MODIFIE'        then 'MOYEN'
    when 'ENTREPRISE_MODIFIEE'        then 'MOYEN'
    when 'RELANCE_DETTE'              then 'MOYEN'
    when 'AGENT_IA'                   then 'MOYEN'
    when 'AGENT_IA_ATTRIBUTION'       then 'MOYEN'
    when 'ESPACE_TYPE'                then 'MOYEN'
    -- 🏨 MODULE 16 C2 — hôtel.
    when 'CHAMBRE_ENREGISTREE'        then 'MOYEN'
    when 'CHAMBRE_MODIFIEE'           then 'MOYEN'
    when 'CHAMBRE_STATUT'             then 'MOYEN'
    when 'RESERVATION'                then 'MOYEN'
    when 'RESERVATION_ANNULEE'        then 'MOYEN'
    when 'CHECKIN_SEJOUR'             then 'MOYEN'
    -- 🍽️ MODULE 16 C3 — restaurant.
    when 'TABLE_ENREGISTREE'          then 'MOYEN'
    when 'TABLE_MODIFIEE'             then 'MOYEN'
    when 'TABLE_STATUT'               then 'MOYEN'
    when 'COMMANDE'                   then 'MOYEN'
    when 'COMMANDE_ENVOYEE'           then 'MOYEN'
    when 'COMMANDE_STATUT'            then 'MOYEN'
    when 'COMMANDE_ANNULEE'           then 'MOYEN'
    -- 🎉 MODULE 16 C4 — salle des fêtes.
    when 'SALLE_ENREGISTREE'          then 'MOYEN'
    when 'SALLE_MODIFIEE'             then 'MOYEN'
    when 'EVENEMENT'                  then 'MOYEN'
    when 'EVENEMENT_MODIFIE'          then 'MOYEN'
    when 'EVENEMENT_STATUT'           then 'MOYEN'
    -- 🥖 MODULE 16 C5 — boulangerie.
    when 'MATIERE_ENREGISTREE'        then 'MOYEN'
    when 'MATIERE_MODIFIEE'           then 'MOYEN'
    when 'MATIERE_APPRO'              then 'MOYEN'
    when 'MATIERE_AJUSTEMENT'         then 'MOYEN'
    when 'PRODUCTION'                 then 'MOYEN'
    when 'PRODUCTION_ANNULEE'         then 'MOYEN'
    when 'RAPPORT'                    then 'INFO'

    -- 🧾 CORRECTIF 67 — factures d'abonnement.
    --   ECHEC : une facture non produite est un TROU de traçabilité sur un
    --   encaissement réel — aussi grave qu'un document annulé.
    when 'FACTURE_ABONNEMENT_ECHEC'       then 'HAUT'
    when 'FACTURE_ABONNEMENT_EMISE'       then 'MOYEN'
    when 'FACTURE_ABONNEMENT_ENVOYEE'     then 'INFO'
    when 'FACTURE_ABONNEMENT_ANNULEE'     then 'HAUT'
    when 'FACTURES_ABONNEMENT_RATTRAPAGE' then 'MOYEN'
    -- 🪙 CORRECTIF 68 — quotas IA : catalogue des packs, reprise
    --   d'attribution, geste commercial. Un DON de quotas est de l'argent
    --   donné : il doit être aussi visible qu'un changement de permission.
    when 'AGENT_IA_PACK'                  then 'MOYEN'
    when 'AGENT_IA_PACK_ENREGISTRE'       then 'MOYEN'
    when 'AGENT_IA_PACK_SUPPRIME'         then 'HAUT'
    when 'AGENT_IA_ATTRIBUTION_ANNULEE'   then 'HAUT'
    when 'AGENT_IA_GESTE'                 then 'CRITIQUE'
    else 'INFO'
  end;
$$;


-- ============================================================================
--  9. CONTRÔLE
-- ============================================================================

do $verif_quotas_ia$
declare
  v_packs     integer;
  v_actifs    integer;
  v_rls_packs boolean;
  v_ecritures integer;
  v_fonctions integer;
  v_niveau    text;
begin
  select count(*) into v_packs from public.agent_ia_packs;
  select count(*) into v_actifs from public.agent_ia_packs where actif;

  if v_packs < 1 then
    raise exception 'Correctif 68 : le catalogue des packs est VIDE — plus aucun achat ne serait possible.';
  end if;
  if v_actifs < 1 then
    raise exception 'Correctif 68 : aucun pack ACTIF — plus aucun achat ne serait possible.';
  end if;

  select c.relrowsecurity into v_rls_packs
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'agent_ia_packs';

  if not coalesce(v_rls_packs, false) then
    raise exception 'Correctif 68 : la securite par ligne n''est PAS activee sur agent_ia_packs.';
  end if;

  select count(*) into v_ecritures
    from pg_policies
   where schemaname = 'public'
     and tablename = 'agent_ia_packs'
     and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL');

  if v_ecritures > 0 then
    raise exception 'Correctif 68 : % policy(ies) d''ecriture directe subsistent sur les packs — ils seraient modifiables sans trace.', v_ecritures;
  end if;

  select count(*) into v_fonctions
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('rpc_agent_ia_packs',
                       'rpc_agent_ia_pack_enregistrer',
                       'rpc_agent_ia_pack_supprimer',
                       'rpc_agent_ia_attributions',
                       'rpc_agent_ia_attribution_annuler',
                       'rpc_agent_ia_offrir',
                       'rpc_agent_ia_demander_achat');

  if v_fonctions < 7 then
    raise exception 'Correctif 68 : % fonctions sur 7 attendues — script incomplet.', v_fonctions;
  end if;

  --  Le geste commercial DOIT être classé CRITIQUE : c'est de l'argent donné.
  select public.audit_niveau('AGENT_IA_GESTE') into v_niveau;
  if v_niveau <> 'CRITIQUE' then
    raise exception 'Correctif 68 : AGENT_IA_GESTE est classe « % » au lieu de CRITIQUE — un don de quotas passerait inapercu dans le journal.', v_niveau;
  end if;

  raise notice 'Correctif 68 : catalogue des packs, reprise d''attribution et geste commercial operationnels.';
end $verif_quotas_ia$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select 'Correctif 68 — quotas IA'                            as chantier,
       (select count(*) from public.agent_ia_packs)           as packs_total,
       (select count(*) from public.agent_ia_packs where actif) as packs_actifs,
       (select count(*) from public.agent_ia_quotas
         where utilisateur_id is null)                        as pools_entreprise,
       (select count(*) from public.agent_ia_quotas
         where utilisateur_id is not null)                    as attributions_membres,
       (select public.audit_niveau('AGENT_IA_GESTE'))          as niveau_geste_commercial,
       (select public.audit_niveau('AGENT_IA_PACK_SUPPRIME'))  as niveau_suppression_pack,
       (select string_agg(p.quotas || ' = ' || p.prix || ' CDF', ' | '
                          order by p.ordre, p.quotas)
          from public.agent_ia_packs p where p.actif)          as grille_active;
