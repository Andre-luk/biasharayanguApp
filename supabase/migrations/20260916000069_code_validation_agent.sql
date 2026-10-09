-- ============================================================================
--  biashara_yangu — CORRECTIF 69 : CODE DE VALIDATION DE L'AGENT
--  Migration 20260916000069_code_validation_agent.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : base de données uniquement.
--
--  CE QUE LE PATRON A DEMANDÉ
--  --------------------------
--  « avant que l'agent confirme le compte ou valide, il faut un code de
--    validation que finance et super admin doivent pouvoir l'envoyer, pour la
--    traçabilité ; si ce code n'est pas envoyé dans 5 minutes, l'agent peut
--    créer, l'agent n'a pas le droit de désactiver les comptes. »
--
--  CE QUE CE DISPOSITIF EST — ET CE QU'IL N'EST PAS
--  ------------------------------------------------
--  C'est un CONTRÔLE DE TRAÇABILITÉ, pas un verrou. Le patron l'a dit : si le
--  code n'arrive pas dans les 5 minutes, l'agent CONTINUE. Bloquer la création
--  d'un compte parce qu'un comptable est au téléphone serait absurde sur le
--  terrain ; mais on doit pouvoir savoir, après coup, QUI a ouvert ce compte
--  et AVEC QUELLE AUTORISATION.
--
--  Trois conséquences de conception, volontaires :
--
--  1. LE CODE N'EST JAMAIS JOURNALISÉ. L'écrire dans `journal_audit` — même
--     « pour la traçabilité » — le rendrait lisible par toute personne ayant
--     accès au journal, donc inutile. Le journal retient QUI, QUAND, et le
--     RÉSULTAT ; jamais la valeur.
--
--  2. LE CODE N'EST VISIBLE QUE DE LA FINANCE ET DU SUPER ADMIN. C'est eux qui
--     le TRANSMETTENT à l'agent (téléphone, WhatsApp…). S'il s'affichait dans
--     l'application de l'agent, il n'y aurait plus aucun échange : l'agent
--     lirait lui-même le code et le contrôle disparaîtrait.
--
--  3. DEUX FENÊTRES DE 5 MINUTES, DISTINCTES :
--       • la DEMANDE est valable 5 minutes — c'est le délai laissé à la
--         Finance pour répondre (« si ce code n'est pas envoyé dans 5
--         minutes, l'agent peut créer ») ;
--       • le CODE émis est valable 5 minutes à son tour — un code qui
--         traînerait une journée sur un téléphone ne serait plus un contrôle.
--
--  LES FENÊTRES EXPIRÉES SONT CONSTATÉES À LA LECTURE
--  --------------------------------------------------
--  Aucun planificateur (pg_cron) n'est requis : la demande est marquée EXPIRE
--  au moment où quelqu'un la consulte. Un test de contrôle vérifie que le
--  balayage fonctionne.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
--  ⚠️ À EXÉCUTER APRÈS le correctif 68.
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE DÉLAI, EN UN SEUL ENDROIT — ET DÉFINI EN PREMIER
--     ⚠️ AVANT la table : le défaut de `expire_le` l'appelle. Une fonction
--     ne peut pas être utilisée dans un défaut de colonne avant d'exister.
--     La règle des 5 minutes du patron ne doit pas être recopiée dans cinq
--     fonctions : le jour où elle change, on ne saurait plus lesquelles.
-- ============================================================================

create or replace function public.delai_code_agent_minutes()
returns integer
language sql
immutable
as $$
  select 5;
$$;

comment on function public.delai_code_agent_minutes() is
  'Correctif 69 — Durée de validité (en minutes) d''une demande de code ET d''un code émis. Décision du patron : 5 minutes.';

grant execute on function public.delai_code_agent_minutes() to authenticated;


-- ============================================================================
--  2. LA TABLE DES CODES
-- ============================================================================

create table if not exists public.codes_validation_agent (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null
                references public.entreprises (id) on delete cascade,

  --  Ce que l'agent veut faire, en clair (« création du compte »,
  --  « vérification du dossier »…). Un code sans objet ne se contrôle pas.
  motif         text,

  --  La DEMANDE : qui, quand.
  demande_par   uuid references public.utilisateurs (id) on delete set null,
  demande_le    timestamptz not null default now(),

  --  Le CODE, posé par la FINANCE. NULL tant qu'il n'a pas été émis.
  code          text,
  emis_par      uuid references public.utilisateurs (id) on delete set null,
  emis_le       timestamptz,

  --  Fin de validité : celle de la DEMANDE tant qu'aucun code n'est émis,
  --  puis celle du CODE une fois émis.
  --  ⚠️ Le défaut appelle la fonction de délai au lieu de recopier « 5 » :
  --     la règle du patron doit vivre à UN SEUL endroit.
  expire_le     timestamptz not null
                default now() + make_interval(mins => public.delai_code_agent_minutes()),

  --  L'UTILISATION : qui s'en est servi.
  valide_par    uuid references public.utilisateurs (id) on delete set null,
  valide_le     timestamptz,

  statut        text not null default 'EN_ATTENTE',
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table public.codes_validation_agent is
  'Correctif 69 — Code de validation exigé avant qu''un agent confirme ou valide un compte. Trace qui a demandé, qui a émis, qui s''en est servi. Le code lui-même n''est JAMAIS journalisé.';

comment on column public.codes_validation_agent.code is
  'Code à 6 chiffres, généré par le serveur et visible UNIQUEMENT de la Finance et du Super Admin — ce sont eux qui le transmettent à l''agent. S''il était visible de l''agent, le contrôle n''existerait plus.';

comment on column public.codes_validation_agent.expire_le is
  'Valable 5 minutes : celle de la DEMANDE tant qu''aucun code n''est émis, puis celle du CODE émis.';

do $m69_contraintes$
begin
  begin
    alter table public.codes_validation_agent
      add constraint codes_validation_agent_statut_check
      check (statut in ('EN_ATTENTE', 'EMIS', 'UTILISE', 'EXPIRE', 'REVOQUE'));
  exception when duplicate_object then null;
  end;
end $m69_contraintes$;

create index if not exists idx_m69_codes_entreprise
  on public.codes_validation_agent (entreprise_id, demande_le desc);

--  UNE SEULE DEMANDE OUVERTE PAR COMPTE : sans cela, un agent pressé
--  empilerait les demandes et la Finance ne saurait plus laquelle traiter.
create unique index if not exists idx_m69_code_ouvert
  on public.codes_validation_agent (entreprise_id)
  where statut in ('EN_ATTENTE', 'EMIS');


-- ============================================================================
--  3. DEMANDER UN CODE
-- ============================================================================

create or replace function public.rpc_agent_code_demander(
  p_entreprise_id uuid,
  p_motif         text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_motif    text := nullif(btrim(coalesce(p_motif, '')), '');
  v_ouverte  public.codes_validation_agent;
  v_id       uuid;
  v_expire   timestamptz;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour demander un code.';
  end if;

  --  Toute la chaîne d'activation peut demander : l'agent de terrain, le
  --  gestionnaire des comptes, et la plateforme. Le client, non : c'est lui
  --  qui est contrôlé.
  if not (public.est_plateforme() or public.est_agent_terrain()) then
    raise exception 'DROIT_REFUSE|Seul le personnel de la plateforme demande un code de validation.';
  end if;

  if p_entreprise_id is null then
    raise exception 'PARAMETRES_INVALIDES|Precisez le compte concerne.';
  end if;

  if not exists (select 1 from public.entreprises e where e.id = p_entreprise_id) then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe pas.';
  end if;

  --  Une demande est-elle déjà ouverte ? On la REND au lieu d'en empiler une
  --  seconde (l'index unique partiel le refuserait de toute facon, mais avec
  --  un message incomprehensible).
  select * into v_ouverte
    from public.codes_validation_agent c
   where c.entreprise_id = p_entreprise_id
     and c.statut in ('EN_ATTENTE', 'EMIS')
   for update;

  if found then
    --  Ouverte mais périmée : on l'expire et on en ouvre une neuve.
    if v_ouverte.expire_le <= now() then
      update public.codes_validation_agent
         set statut = 'EXPIRE', updated_at = now()
       where id = v_ouverte.id;
    else
      return jsonb_build_object(
        'ok',          true,
        'demande_id',  v_ouverte.id,
        'statut',      v_ouverte.statut,
        'expire_le',   v_ouverte.expire_le,
        'deja_ouverte', true,
        'code_emis',   v_ouverte.code is not null
      );
    end if;
  end if;

  v_expire := now() + make_interval(mins => public.delai_code_agent_minutes());

  insert into public.codes_validation_agent (
    entreprise_id, motif, demande_par, demande_le, expire_le
  ) values (
    p_entreprise_id, v_motif, v_user, now(), v_expire
  )
  returning id into v_id;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), p_entreprise_id, 'AGENT_CODE_DEMANDE', v_user,
    jsonb_build_object(
      'demande_id', v_id,
      'motif',      v_motif,
      'expire_le',  v_expire,
      'correctif',  '69'
    ),
    now()
  );

  return jsonb_build_object(
    'ok',         true,
    'demande_id', v_id,
    'statut',     'EN_ATTENTE',
    'expire_le',  v_expire,
    'deja_ouverte', false,
    'code_emis',  false
  );
end $$;

comment on function public.rpc_agent_code_demander(uuid, text) is
  'Correctif 69 — L''agent demande un code de validation pour un compte. Une seule demande ouverte par compte ; elle vaut 5 minutes.';

revoke all on function public.rpc_agent_code_demander(uuid, text) from public, anon;
grant execute on function public.rpc_agent_code_demander(uuid, text) to authenticated;


-- ============================================================================
--  4. ÉMETTRE LE CODE (Finance / Super Admin)
-- ============================================================================

create or replace function public.rpc_agent_code_emettre(p_demande_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_demande public.codes_validation_agent;
  v_code    text;
  v_expire  timestamptz;
begin
  --  DEUX RÔLES SEULEMENT : « finance et super admin doivent pouvoir
  --  l'envoyer ». Personne d'autre — surtout pas l'agent, qui est contrôlé.
  if public.mon_role() not in ('FINANCE_LAPERLE', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seule la Finance ou le Super Admin emet un code de validation.';
  end if;

  select * into v_demande
    from public.codes_validation_agent
   where id = p_demande_id
   for update;

  if not found then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande de code n''existe pas.';
  end if;

  if v_demande.statut = 'UTILISE' then
    raise exception 'CODE_DEJA_UTILISE|Ce code a deja ete utilise.';
  end if;
  if v_demande.statut = 'REVOQUE' then
    raise exception 'DEMANDE_REVOQUEE|Cette demande a ete revoquee.';
  end if;

  --  Un code à 6 chiffres, entre 100 000 et 999 999 : pas de zéro de tête,
  --  qui se perd à l'oral comme à l'écrit.
  v_code := lpad((floor(random() * 900000) + 100000)::int::text, 6, '0');
  v_expire := now() + make_interval(mins => public.delai_code_agent_minutes());

  update public.codes_validation_agent
     set code      = v_code,
         emis_par  = auth.uid(),
         emis_le   = now(),
         expire_le = v_expire,
         statut    = 'EMIS',
         updated_at = now()
   where id = p_demande_id;

  --  ⚠️ LE CODE N'EST PAS DANS LE JOURNAL. L'y écrire le rendrait lisible par
  --  quiconque consulte le journal : le contrôle n'existerait plus.
  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), v_demande.entreprise_id, 'AGENT_CODE_EMIS', auth.uid(),
    jsonb_build_object(
      'demande_id', v_demande.id,
      'emis_par_role', public.mon_role(),
      'expire_le',  v_expire,
      'renouvellement', v_demande.code is not null,
      'correctif',  '69'
    ),
    now()
  );

  --  Le code est renvoyé À LA FINANCE UNIQUEMENT (garde ci-dessus) : c'est
  --  elle qui le transmet à l'agent.
  return jsonb_build_object(
    'ok',        true,
    'demande_id', v_demande.id,
    'code',      v_code,
    'expire_le', v_expire
  );
end $$;

comment on function public.rpc_agent_code_emettre(uuid) is
  'Correctif 69 — La Finance ou le Super Admin emet un code a 6 chiffres valable 5 minutes. Le code n''est jamais journalise et n''est renvoye qu''a ces deux roles.';

revoke all on function public.rpc_agent_code_emettre(uuid) from public, anon;
grant execute on function public.rpc_agent_code_emettre(uuid) to authenticated;


-- ============================================================================
--  5. SAISIR LE CODE (l'agent)
-- ============================================================================

create or replace function public.rpc_agent_code_valider(
  p_demande_id uuid,
  p_code       text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_demande public.codes_validation_agent;
  v_saisi   text := btrim(coalesce(p_code, ''));
  v_raison  text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour saisir le code.';
  end if;

  if not (public.est_plateforme() or public.est_agent_terrain()) then
    raise exception 'DROIT_REFUSE|Seul le personnel de la plateforme saisit un code de validation.';
  end if;

  if v_saisi = '' then
    raise exception 'CODE_REQUIS|Saisissez le code communique par la Finance.';
  end if;

  select * into v_demande
    from public.codes_validation_agent
   where id = p_demande_id
   for update;

  if not found then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande de code n''existe pas.';
  end if;

  --  ── Pourquoi ça ne marche pas. Le message distingue les cas : « le code
  --     est faux » et « le code a expiré » demandent deux réactions
  --     différentes de l'agent.
  if v_demande.statut = 'UTILISE' then
    v_raison := 'DEJA_UTILISE';
  elsif v_demande.statut = 'REVOQUE' then
    v_raison := 'REVOQUE';
  elsif v_demande.statut = 'EXPIRE' or v_demande.expire_le <= now() then
    v_raison := 'EXPIRE';
  elsif v_demande.code is null then
    v_raison := 'AUCUN_CODE_EMIS';
  elsif v_demande.code <> v_saisi then
    v_raison := 'CODE_INCORRECT';
  end if;

  if v_raison is not null then
    --  Marquer la demande expirée au passage : la prochaine demande de
    --  l'agent repartira proprement au lieu de buter sur la clé unique.
    if v_raison = 'EXPIRE' then
      update public.codes_validation_agent
         set statut = 'EXPIRE', updated_at = now()
       where id = p_demande_id and statut <> 'EXPIRE';
    end if;

    --  ⚠️ On journalise l'ÉCHEC et sa raison, JAMAIS le code saisi : le
    --  journal ne doit pas devenir un moyen de retrouver un code.
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (
      gen_random_uuid(), v_demande.entreprise_id, 'AGENT_CODE_ECHEC', auth.uid(),
      jsonb_build_object(
        'demande_id', v_demande.id,
        'raison',     v_raison,
        'correctif',  '69'
      ),
      now()
    );

    raise exception 'CODE_REFUSE|Code refuse (%). %', v_raison,
      case v_raison
        when 'CODE_INCORRECT'  then 'Verifiez les 6 chiffres communiques par la Finance.'
        when 'EXPIRE'          then 'Ce code a expire. Demandez-en un nouveau.'
        when 'DEJA_UTILISE'    then 'Ce code a deja servi.'
        when 'AUCUN_CODE_EMIS' then 'La Finance n''a pas encore emis de code pour ce compte.'
        else 'Cette demande a ete revoquee par la Finance.'
      end;
  end if;

  update public.codes_validation_agent
     set statut     = 'UTILISE',
         valide_par = auth.uid(),
         valide_le  = now(),
         updated_at = now()
   where id = p_demande_id;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), v_demande.entreprise_id, 'AGENT_CODE_VALIDE', auth.uid(),
    jsonb_build_object(
      'demande_id', v_demande.id,
      'motif',      v_demande.motif,
      'emis_par',   v_demande.emis_par,
      'delai_secondes', greatest(
        0, floor(extract(epoch from (now() - v_demande.emis_le)))::int),
      'correctif',  '69'
    ),
    now()
  );

  return jsonb_build_object(
    'ok',           true,
    'demande_id',   v_demande.id,
    'entreprise_id', v_demande.entreprise_id,
    'valide_le',    now(),
    'motif',        v_demande.motif
  );
end $$;

comment on function public.rpc_agent_code_valider(uuid, text) is
  'Correctif 69 — L''agent saisit le code communique par la Finance. Distingue code faux, expire, deja utilise et jamais emis. Le code saisi n''est jamais journalise.';

revoke all on function public.rpc_agent_code_valider(uuid, text) from public, anon;
grant execute on function public.rpc_agent_code_valider(uuid, text) to authenticated;


-- ============================================================================
--  6. RÉVOQUER UNE DEMANDE (Finance / Super Admin)
-- ============================================================================

create or replace function public.rpc_agent_code_revoquer(
  p_demande_id uuid,
  p_motif      text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_demande public.codes_validation_agent;
  v_motif   text := nullif(btrim(coalesce(p_motif, '')), '');
begin
  if public.mon_role() not in ('FINANCE_LAPERLE', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seule la Finance ou le Super Admin revoque une demande de code.';
  end if;

  select * into v_demande
    from public.codes_validation_agent
   where id = p_demande_id
   for update;

  if not found then
    raise exception 'DEMANDE_INTROUVABLE|Cette demande de code n''existe pas.';
  end if;

  if v_demande.statut in ('UTILISE', 'REVOQUE') then
    raise exception 'DEMANDE_CLOSE|Cette demande est deja close (%).', v_demande.statut;
  end if;

  update public.codes_validation_agent
     set statut     = 'REVOQUE',
         note       = coalesce(note || ' | ', '') || 'REVOQUEE : '
                      || coalesce(v_motif, 'sans motif'),
         updated_at = now()
   where id = p_demande_id;

  insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
  values (
    gen_random_uuid(), v_demande.entreprise_id, 'AGENT_CODE_REVOQUE', auth.uid(),
    jsonb_build_object(
      'demande_id', v_demande.id,
      'motif',      v_motif,
      'correctif',  '69'
    ),
    now()
  );

  return jsonb_build_object('ok', true, 'demande_id', v_demande.id);
end $$;

comment on function public.rpc_agent_code_revoquer(uuid, text) is
  'Correctif 69 — La Finance ou le Super Admin revoque une demande de code (elle ne sera plus utilisable).';

revoke all on function public.rpc_agent_code_revoquer(uuid, text) from public, anon;
grant execute on function public.rpc_agent_code_revoquer(uuid, text) to authenticated;


-- ============================================================================
--  7. LIRE L'ÉTAT DES CODES
--     ⚠️ Fonction VOLONTAIREMENT volatile : elle constate À LA LECTURE les
--        demandes périmées, ce qui évite d'avoir besoin d'un planificateur.
-- ============================================================================

create or replace function public.rpc_agent_codes_lister(
  p_entreprise_id uuid    default null,
  p_limite        integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plateforme boolean;
  v_finance    boolean;
  v_limite     integer := greatest(1, least(coalesce(p_limite, 100), 500));
  v_out        jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter les codes.';
  end if;

  v_plateforme := public.est_plateforme();
  v_finance := public.mon_role() in ('FINANCE_LAPERLE', 'SUPER_ADMIN');

  if not (v_plateforme or public.est_agent_terrain()) then
    raise exception 'DROIT_REFUSE|Seul le personnel de la plateforme consulte les codes de validation.';
  end if;

  --  ── Balayage des demandes périmées. Sans cela, une demande jamais traitée
  --     resterait « EN_ATTENTE » pour toujours et bloquerait la suivante
  --     (index unique partiel sur les demandes ouvertes).
  update public.codes_validation_agent
     set statut = 'EXPIRE', updated_at = now()
   where statut in ('EN_ATTENTE', 'EMIS')
     and expire_le <= now();

  select coalesce(jsonb_agg(x.obj order by x.demande_le desc), '[]'::jsonb)
    into v_out
    from (
      select c.demande_le,
             jsonb_build_object(
               'id',             c.id,
               'entreprise_id',  c.entreprise_id,
               'entreprise_nom', nullif(btrim(e.nom), ''),
               'motif',          c.motif,
               'statut',         c.statut,
               'demande_par',    c.demande_par,
               'demande_par_nom', nullif(btrim(demandeur.nom_complet), ''),
               'demande_le',     c.demande_le,
               'emis_le',        c.emis_le,
               'emis_par_nom',   nullif(btrim(emetteur.nom_complet), ''),
               'valide_le',      c.valide_le,
               'valide_par_nom', nullif(btrim(valide.nom_complet), ''),
               'expire_le',      c.expire_le,
               'minutes_restantes', case
                  when c.statut in ('EN_ATTENTE', 'EMIS')
                    then greatest(0, ceil(extract(epoch from (c.expire_le - now())) / 60))::int
                  else 0
                end,
               --  ⚠️ LE CODE N'EST RENVOYÉ QU'À LA FINANCE ET AU SUPER ADMIN.
               --     S'il apparaissait dans l'application de l'agent, il n'y
               --     aurait plus aucun échange entre la Finance et lui : le
               --     contrôle serait vidé de son sens.
               'code', case when v_finance then c.code else null end
             ) as obj
        from public.codes_validation_agent c
        left join public.entreprises e on e.id = c.entreprise_id
        left join public.utilisateurs demandeur on demandeur.id = c.demande_par
        left join public.utilisateurs emetteur  on emetteur.id  = c.emis_par
        left join public.utilisateurs valide    on valide.id    = c.valide_par
       where (p_entreprise_id is null or c.entreprise_id = p_entreprise_id)
         --  Un agent ne voit QUE ses propres demandes.
         and (v_plateforme or c.demande_par = auth.uid())
       order by c.demande_le desc
       limit v_limite
    ) x;

  return jsonb_build_object('codes', v_out, 'peut_voir_le_code', v_finance);
end $$;

comment on function public.rpc_agent_codes_lister(uuid, integer) is
  'Correctif 69 — Etat des demandes de code. Le code lui-meme n''est renvoye qu''a la Finance et au Super Admin ; un agent ne voit que ses propres demandes.';

revoke all on function public.rpc_agent_codes_lister(uuid, integer) from public, anon;
grant execute on function public.rpc_agent_codes_lister(uuid, integer) to authenticated;


-- ============================================================================
--  8. CE QUE LA FINANCE DOIT CONFIRMER
--     « si ce code n'est pas envoyé dans 5 minutes, l'agent peut créer » —
--     mais alors LA FINANCE DOIT CONFIRMER ENSUITE. Voici exactement cette
--     liste : les dossiers vérifiés SANS code validé.
-- ============================================================================

create or replace function public.rpc_agent_dossiers_sans_code(
  p_limite integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_limite integer := greatest(1, least(coalesce(p_limite, 100), 500));
  v_out    jsonb;
  v_total  integer;
begin
  if not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seule la plateforme consulte les dossiers a confirmer.';
  end if;

  select count(*) into v_total
    from public.entreprises e
   where e.activation_etape = 'verifie'
     and not exists (
       select 1 from public.codes_validation_agent c
        where c.entreprise_id = e.id
          and c.statut = 'UTILISE'
     );

  select coalesce(jsonb_agg(x.obj order by x.verifie_le), '[]'::jsonb)
    into v_out
    from (
      select e.verifie_le,
             jsonb_build_object(
               'entreprise_id', e.id,
               'nom',           nullif(btrim(e.nom), ''),
               'etape',         e.activation_etape,
               'statut',        e.statut::text,
               'verifie_par',   e.verifie_par,
               'verifie_par_nom', nullif(btrim(verificateur.nom_complet), ''),
               'verifie_le',    e.verifie_le,
               --  Une demande ouverte a-t-elle au moins été faite ? Cela
               --  distingue « l'agent n'a rien demandé » de « la Finance n'a
               --  pas répondu » : deux responsabilités différentes.
               'a_demande_un_code', exists (
                 select 1 from public.codes_validation_agent c
                  where c.entreprise_id = e.id
               ),
               'demande_en_attente', exists (
                 select 1 from public.codes_validation_agent c
                  where c.entreprise_id = e.id
                    and c.statut in ('EN_ATTENTE', 'EMIS')
               )
             ) as obj
        from public.entreprises e
        left join public.utilisateurs verificateur on verificateur.id = e.verifie_par
       where e.activation_etape = 'verifie'
         and not exists (
           select 1 from public.codes_validation_agent c
            where c.entreprise_id = e.id
              and c.statut = 'UTILISE'
         )
       order by e.verifie_le
       limit v_limite
    ) x;

  return jsonb_build_object('total', coalesce(v_total, 0), 'dossiers', v_out);
end $$;

comment on function public.rpc_agent_dossiers_sans_code(integer) is
  'Correctif 69 — Dossiers verifies SANS code valide : ce sont eux que la Finance doit confirmer apres coup. Distingue « aucune demande faite » de « Finance n''a pas repondu ».';

revoke all on function public.rpc_agent_dossiers_sans_code(integer) from public, anon;
grant execute on function public.rpc_agent_dossiers_sans_code(integer) to authenticated;


-- ============================================================================
--  9. SÉCURITÉ PAR LIGNE
-- ============================================================================

alter table public.codes_validation_agent enable row level security;

--  Lecture : la plateforme, et l'auteur de la demande (l'agent voit la sienne).
drop policy if exists codes_validation_agent_lecture on public.codes_validation_agent;
create policy codes_validation_agent_lecture on public.codes_validation_agent
  for select
  to authenticated
  using (public.est_plateforme() or demande_par = auth.uid());

--  ⚠️ AUCUNE policy d'écriture : les seules écritures passent par les RPC,
--  qui vérifient le rôle et journalisent. Un code réécrit après coup ne
--  prouverait plus rien.

revoke all on table public.codes_validation_agent from anon;
revoke insert, update, delete, truncate on table public.codes_validation_agent from authenticated;


-- ============================================================================
--  10. NIVEAUX D'AUDIT DES NOUVELLES ACTIONS
--     ⚠️ Reprise À L'IDENTIQUE de la version en vigueur + les actions du
--        correctif 69. Aucune ligne n'est réécrite de mémoire.
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
    -- 🔐 CORRECTIF 69 — code de validation de l'agent.
    --   EMIS : c'est un CONTRÔLE sur la création de comptes, pas une
    --   formalité — la Finance autorise quelqu'un à ouvrir un compte.
    --   VALIDE : trace de qui s'en est servi.
    --   ECHEC : un code refusé ou expiré est le signal le plus intéressant du
    --   dispositif : soit une erreur, soit une tentative. Il ne doit JAMAIS
    --   se noyer dans le journal.
    when 'AGENT_CODE_DEMANDE'   then 'MOYEN'
    when 'AGENT_CODE_EMIS'      then 'HAUT'
    when 'AGENT_CODE_VALIDE'    then 'HAUT'
    when 'AGENT_CODE_ECHEC'     then 'HAUT'
    when 'AGENT_CODE_REVOQUE'   then 'HAUT'
    else 'INFO'
  end;
$$;


-- ============================================================================
--  11. CONTRÔLE
-- ============================================================================

do $verif_code_agent$
declare
  v_rls       boolean;
  v_ecritures integer;
  v_fonctions integer;
  v_delai     integer;
  v_niveau    text;
begin
  select c.relrowsecurity into v_rls
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relname = 'codes_validation_agent';

  if not coalesce(v_rls, false) then
    raise exception 'Correctif 69 : la securite par ligne n''est PAS activee sur codes_validation_agent.';
  end if;

  select count(*) into v_ecritures
    from pg_policies
   where schemaname = 'public'
     and tablename = 'codes_validation_agent'
     and cmd in ('INSERT', 'UPDATE', 'DELETE', 'ALL');

  if v_ecritures > 0 then
    raise exception 'Correctif 69 : % policy(ies) d''ecriture directe — un code reecrit ne prouverait plus rien.', v_ecritures;
  end if;

  select count(*) into v_fonctions
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('rpc_agent_code_demander',
                       'rpc_agent_code_emettre',
                       'rpc_agent_code_valider',
                       'rpc_agent_code_revoquer',
                       'rpc_agent_codes_lister',
                       'rpc_agent_dossiers_sans_code',
                       'delai_code_agent_minutes');

  if v_fonctions < 7 then
    raise exception 'Correctif 69 : % fonctions sur 7 attendues — script incomplet.', v_fonctions;
  end if;

  --  La règle des 5 minutes est une décision du patron : on la vérifie.
  select public.delai_code_agent_minutes() into v_delai;
  if v_delai <> 5 then
    raise exception 'Correctif 69 : le delai vaut % minutes au lieu de 5.', v_delai;
  end if;

  --  Un échec de code est le signal le plus utile du dispositif : il ne doit
  --  pas se noyer dans le journal.
  select public.audit_niveau('AGENT_CODE_ECHEC') into v_niveau;
  if v_niveau <> 'HAUT' then
    raise exception 'Correctif 69 : AGENT_CODE_ECHEC est classe « % » au lieu de HAUT.', v_niveau;
  end if;

  raise notice 'Correctif 69 : code de validation de l''agent operationnel (demande, emission, saisie, revocation, dossiers a confirmer).';
end $verif_code_agent$;


-- ============================================================================
--  RAPPORT FINAL
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select 'Correctif 69 — code de validation agent'        as chantier,
       public.delai_code_agent_minutes()                 as delai_minutes,
       (select count(*) from public.codes_validation_agent)                     as demandes_total,
       (select count(*) from public.codes_validation_agent where statut = 'EN_ATTENTE') as en_attente,
       (select count(*) from public.codes_validation_agent where statut = 'EMIS')       as codes_valides_emis,
       (select count(*) from public.codes_validation_agent where statut = 'UTILISE')    as codes_utilises,
       (select count(*) from public.codes_validation_agent where statut = 'EXPIRE')     as expirees,
       (select count(*) from public.entreprises e
         where e.activation_etape = 'verifie'
           and not exists (select 1 from public.codes_validation_agent c
                            where c.entreprise_id = e.id and c.statut = 'UTILISE'))
                                                                        as dossiers_a_confirmer,
       public.audit_niveau('AGENT_CODE_ECHEC')           as niveau_echec,
       public.audit_niveau('AGENT_CODE_EMIS')            as niveau_emission;
