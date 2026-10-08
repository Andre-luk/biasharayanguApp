-- ============================================================================
--  biashara_yangu — CORRECTIF 65 : LES FONCTIONNALITÉS SUIVENT L'ABONNEMENT
--  Migration 20260916000065_fonctionnalites_par_abonnement.sql
-- ============================================================================
--
--  ⛔ AUCUNE COMPILATION, AUCUNE PUBLICATION : préparation de base uniquement.
--
--  LE PRINCIPE
--  -----------
--  Jusqu'ici, les fonctionnalités visibles dépendaient UNIQUEMENT de
--  l'activité de l'espace (boutique, pharmacie, hôtel…). Un compte à
--  20 000 CDF/mois voyait exactement la même chose qu'un compte à
--  5 000 CDF/mois.
--
--  Désormais :  FONCTIONNALITÉS = ACTIVITÉ  ∩  NIVEAU D'ABONNEMENT
--
--     • l'ACTIVITÉ décide de ce qui a du SENS (une pharmacie gère des lots,
--       un hôtel des chambres) — mécanisme existant, inchangé ;
--     • le NIVEAU d'abonnement décide de ce qui est PAYÉ.
--  Un hôtel « Essentiel » ne voit pas les mêmes écrans qu'un hôtel
--  « Premium » ; et une pharmacie « Pro » ne voit jamais des chambres.
--
--  LA RÈGLE D'OR EST PRÉSERVÉE : FAIL-OPEN
--  ---------------------------------------
--  Aucun module trouvé, session absente, réseau coupé → **tout reste
--  visible**. C'est la règle déjà appliquée par `ReglesActivite.actif()` et
--  `ModulesService` : elle garantit qu'aucun correctif de base ne peut
--  masquer un écran à un commerçant qui paie. Cette migration ne la change
--  pas — elle fournit seulement une liste à croiser.
--
--  CE QUE FAIT CETTE MIGRATION
--  ---------------------------
--    1. crée le CATALOGUE DES NIVEAUX (`niveaux_abonnement`) : code, libellé,
--       ordre, prix mensuel CONSEILLÉ et liste des fonctionnalités ;
--    2. amorce trois niveaux de départ, à modifier librement dans
--       l'application (l'amorçage n'écrase JAMAIS un niveau déjà modifié) ;
--    3. rattache un niveau à la grille tarifaire (`groupes_tarifaires.niveau`)
--       et à chaque entreprise (`entreprises.niveau_abonnement`) ;
--    4. ajoute des FONCTIONNALITÉS NÉGOCIÉES par entreprise
--       (`entreprises.modules_abonnement`) : le prix est négocié, les
--       fonctionnalités peuvent l'être aussi ;
--    5. fournit les RPC du CRUD et la RPC que lit l'application.
--
--  ORDRE DE RÉSOLUTION (du plus précis au plus général)
--  ----------------------------------------------------
--    1. fonctionnalités NÉGOCIÉES de l'entreprise ;
--    2. fonctionnalités du NIVEAU de l'entreprise (ou celui de son pack) ;
--    3. fonctionnalités du PACK tarifaire affecté ;
--    4. sinon NULL → l'application applique le FAIL-OPEN.
--
--  ⚠️ `["*"]` DANS LA LISTE = TOUTES LES FONCTIONNALITÉS de l'activité.
--     C'est le niveau le plus élevé, et il restera correct même quand de
--     nouvelles fonctionnalités seront ajoutées à l'application.
--
--  IDEMPOTENTE : relançable sans effet de bord.
--  OÙ : Supabase → SQL Editor → coller → Run
-- ============================================================================


select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. LE CATALOGUE DES NIVEAUX
-- ============================================================================

create table if not exists public.niveaux_abonnement (
  code                   text primary key,
  libelle                text not null,
  ordre                  integer not null default 0,
  prix_mensuel_conseille numeric,
  modules                jsonb not null default '[]'::jsonb,
  description            text,
  actif                  boolean not null default true,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

comment on table public.niveaux_abonnement is
  'Correctif 65 — Catalogue des NIVEAUX d''abonnement. Chaque niveau porte la liste des fonctionnalités (modules) qu''il ouvre. Le prix conseillé est INDICATIF : le prix réel est négocié entreprise par entreprise.';

comment on column public.niveaux_abonnement.modules is
  'Liste des codes de fonctionnalités ouvertes par ce niveau. ["*"] = toutes les fonctionnalités de l''activité.';

comment on column public.niveaux_abonnement.prix_mensuel_conseille is
  'Prix mensuel proposé (l''abonnement démarre à 5 000 CDF). Sert de valeur par défaut à la saisie, jamais de facturation : le moteur d''abonnement ne lit jamais cette colonne.';

create index if not exists idx_niveaux_abonnement_ordre
  on public.niveaux_abonnement (actif, ordre);


-- ============================================================================
--  2. RATTACHEMENT : GRILLE TARIFAIRE ET ENTREPRISE
-- ============================================================================

alter table public.groupes_tarifaires
  add column if not exists niveau       text,
  add column if not exists niveau_ordre integer default 0;

alter table public.entreprises
  add column if not exists niveau_abonnement   text,
  add column if not exists modules_abonnement  jsonb;

comment on column public.entreprises.niveau_abonnement is
  'Niveau d''abonnement NÉGOCIÉ pour cette entreprise. NULL = celui de son pack tarifaire. Correctif 65.';

comment on column public.entreprises.modules_abonnement is
  'Fonctionnalités NÉGOCIÉES pour cette entreprise (liste de codes, ["*"] pour tout). NULL ou vide = suivre le niveau puis le pack. Correctif 65.';


-- ============================================================================
--  3. AMORÇAGE DES TROIS NIVEAUX DE DÉPART
-- ============================================================================
--  `on conflict do nothing` : relancer la migration NE REMPLACE JAMAIS un
--  niveau que vous avez modifié. Vos réglages sont donc toujours conservés.

insert into public.niveaux_abonnement
  (code, libelle, ordre, prix_mensuel_conseille, modules, description)
values
  ('ESSENTIEL', 'Essentiel', 1, 5000,
   '["ventes","produits","stock","caisse","clients","rapports"]'::jsonb,
   'Le socle : vendre, tenir le stock, suivre la caisse et les rapports.'),

  ('PRO', 'Pro', 2, 10000,
   '["ventes","produits","stock","qr","caisse","clients","finance","employes","rapports","assistant_ia"]'::jsonb,
   'Ajoute la gestion financière, les employés, les étiquettes QR et l''assistant IA.'),

  ('PREMIUM', 'Premium', 3, 20000,
   '["*"]'::jsonb,
   'Toutes les fonctionnalités de l''activité, sans restriction.')
on conflict (code) do nothing;


-- ============================================================================
--  4. LA RÉSOLUTION : QUELS MODULES POUR CETTE ENTREPRISE ?
-- ============================================================================

create or replace function public.abonnement_modules_entreprise(
  p_entreprise_id uuid
)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    --  1. les fonctionnalités NÉGOCIÉES pour cette entreprise ;
    case when jsonb_typeof(e.modules_abonnement) = 'array'
         then nullif(e.modules_abonnement, '[]'::jsonb) end,
    --  2. celles du NIVEAU de l'entreprise — ou, à défaut, du niveau de son
    --     pack tarifaire ;
    (select case when jsonb_typeof(n.modules) = 'array'
                 then nullif(n.modules, '[]'::jsonb) end
       from public.niveaux_abonnement n
      where n.actif
        and n.code = coalesce(
              nullif(e.niveau_abonnement, ''),
              (select g.niveau
                 from public.groupes_tarifaires g
                where g.id = e.groupe_tarifaire_id)
            )
      limit 1),
    --  3. celles du PACK tarifaire affecté — uniquement si c'est bien une
    --     LISTE : un objet jsonb n'a pas de longueur et serait inutilisable.
    --     (On ne devine pas : on retombe alors sur le fail-open.)
    (select case when jsonb_typeof(g.modules) = 'array'
                 then nullif(g.modules, '[]'::jsonb) end
       from public.groupes_tarifaires g
      where g.id = e.groupe_tarifaire_id),
    --  4. sinon NULL : l'application applique sa règle FAIL-OPEN.
    null
  )
  from public.entreprises e
  where e.id = p_entreprise_id;
$$;

comment on function public.abonnement_modules_entreprise(uuid) is
  'Correctif 65 — Fonctionnalités ouvertes à une entreprise : négociées, sinon celles de son NIVEAU, sinon celles de son pack, sinon NULL (fail-open côté application).';

revoke all on function public.abonnement_modules_entreprise(uuid) from public, anon;
grant execute on function public.abonnement_modules_entreprise(uuid) to authenticated;


-- ============================================================================
--  5. LA RPC QUE LIT L'APPLICATION
-- ============================================================================

create or replace function public.rpc_abonnement_modules()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_soc  uuid;
begin
  --  Hors session : rien n'est renvoyé, l'application reste en fail-open.
  if v_user is null then
    return null;
  end if;

  --  Le personnel de la plateforme n'est jamais restreint par un abonnement :
  --  il doit pouvoir diagnostiquer n'importe quel compte.
  if public.est_plateforme() then
    return null;
  end if;

  v_soc := public.mon_entreprise_id();
  if v_soc is null then
    return null;
  end if;

  return public.abonnement_modules_entreprise(v_soc);
end;
$$;

comment on function public.rpc_abonnement_modules() is
  'Correctif 65 — Fonctionnalités de l''abonnement de la session courante. NULL = aucune restriction (fail-open).';

revoke all on function public.rpc_abonnement_modules() from public, anon;
grant execute on function public.rpc_abonnement_modules() to authenticated;


-- ============================================================================
--  6. CRUD — LE CATALOGUE DES NIVEAUX (Super Admin)
-- ============================================================================

create or replace function public.rpc_abonnement_niveau_enregistrer(
  p_code        text,
  p_libelle     text,
  p_ordre       integer default 0,
  p_prix        numeric default null,
  p_modules     jsonb   default null,
  p_description text    default null,
  p_actif       boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code  text := upper(regexp_replace(btrim(coalesce(p_code, '')), '[^A-Za-z0-9_]', '_', 'g'));
  v_label text := nullif(btrim(coalesce(p_libelle, '')), '');
  v_mods  jsonb := coalesce(p_modules, '[]'::jsonb);
  v_niveau public.niveaux_abonnement;
begin
  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin définit les niveaux d''abonnement.';
  end if;

  if v_code = '' then
    raise exception 'PARAMETRES_INVALIDES|Indiquez un code de niveau (lettres, chiffres, souligné).';
  end if;

  if v_label is null then
    raise exception 'PARAMETRES_INVALIDES|Indiquez le nom affiché du niveau.';
  end if;

  if jsonb_typeof(v_mods) <> 'array' then
    raise exception 'PARAMETRES_INVALIDES|La liste des fonctionnalités doit être une liste.';
  end if;

  if p_prix is not null and p_prix < 0 then
    raise exception 'PARAMETRES_INVALIDES|Le prix conseillé ne peut pas être négatif.';
  end if;

  insert into public.niveaux_abonnement
    (code, libelle, ordre, prix_mensuel_conseille, modules, description, actif, updated_at)
  values
    (v_code, v_label, coalesce(p_ordre, 0), p_prix, v_mods,
     nullif(btrim(coalesce(p_description, '')), ''), coalesce(p_actif, true), now())
  on conflict (code) do update set
    libelle                = excluded.libelle,
    ordre                  = excluded.ordre,
    prix_mensuel_conseille = excluded.prix_mensuel_conseille,
    modules                = excluded.modules,
    description            = excluded.description,
    actif                  = excluded.actif,
    updated_at             = now()
  returning * into v_niveau;

  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (
      gen_random_uuid(), null, 'NIVEAU_ABONNEMENT_ENREGISTRE', auth.uid(),
      jsonb_build_object(
        'code',          v_niveau.code,
        'libelle',       v_niveau.libelle,
        'ordre',         v_niveau.ordre,
        'prix_conseille', v_niveau.prix_mensuel_conseille,
        'nb_fonctions',  jsonb_array_length(v_niveau.modules),
        'modules',       v_niveau.modules,
        'actif',         v_niveau.actif,
        'correctif',     '65'
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'code', v_niveau.code,
    'libelle', v_niveau.libelle,
    'nb_fonctions', jsonb_array_length(v_niveau.modules)
  );
end;
$$;

comment on function public.rpc_abonnement_niveau_enregistrer(text, text, integer, numeric, jsonb, text, boolean) is
  'Correctif 65 — Crée ou met à jour un niveau d''abonnement et ses fonctionnalités (Super Admin).';

revoke all on function public.rpc_abonnement_niveau_enregistrer(text, text, integer, numeric, jsonb, text, boolean) from public, anon;
grant execute on function public.rpc_abonnement_niveau_enregistrer(text, text, integer, numeric, jsonb, text, boolean) to authenticated;


create or replace function public.rpc_abonnement_niveau_supprimer(
  p_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_nb   integer;
begin
  if not public.est_super_admin() then
    raise exception 'DROIT_REFUSE|Seul le Super Admin supprime un niveau d''abonnement.';
  end if;

  if v_code = '' then
    raise exception 'PARAMETRES_INVALIDES|Précisez le niveau à supprimer.';
  end if;

  select count(*) into v_nb
    from public.entreprises
   where niveau_abonnement = v_code;

  if v_nb > 0 then
    raise exception 'NIVEAU_UTILISE|% entreprise(s) utilisent ce niveau. Affectez-leur un autre niveau avant de le supprimer.', v_nb;
  end if;

  select count(*) into v_nb
    from public.groupes_tarifaires
   where niveau = v_code;

  if v_nb > 0 then
    raise exception 'NIVEAU_UTILISE|% pack(s) tarifaire(s) portent ce niveau. Retirez-le d''abord de ces packs.', v_nb;
  end if;

  delete from public.niveaux_abonnement where code = v_code;

  if not found then
    raise exception 'NIVEAU_INTROUVABLE|Ce niveau n''existe pas.';
  end if;

  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (
      gen_random_uuid(), null, 'NIVEAU_ABONNEMENT_SUPPRIME', auth.uid(),
      jsonb_build_object('code', v_code, 'correctif', '65'),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'code', v_code);
end;
$$;

comment on function public.rpc_abonnement_niveau_supprimer(text) is
  'Correctif 65 — Supprime un niveau d''abonnement, refusé s''il est encore utilisé par une entreprise ou un pack.';

revoke all on function public.rpc_abonnement_niveau_supprimer(text) from public, anon;
grant execute on function public.rpc_abonnement_niveau_supprimer(text) to authenticated;


-- ============================================================================
--  7. CRUD — LE NIVEAU NÉGOCIÉ D'UNE ENTREPRISE (Finance / Super Admin)
-- ============================================================================

create or replace function public.rpc_abonnement_definir_niveau_entreprise(
  p_entreprise_id uuid,
  p_niveau        text default null,
  p_modules       jsonb default null,
  p_note          text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role     text := public.mon_role();
  v_e        public.entreprises;
  v_niveau   text := nullif(upper(btrim(coalesce(p_niveau, ''))), '');
  v_mods     jsonb := p_modules;
  v_note     text := nullif(btrim(coalesce(p_note, '')), '');
  v_avant_n  text;
  v_avant_m  jsonb;
begin
  if v_role not in ('FINANCE_LAPERLE', 'GESTIONNAIRE_COMPTES', 'SUPER_ADMIN') then
    raise exception 'DROIT_REFUSE|Seuls la finance, le gestionnaire des comptes ou le Super Admin définissent le niveau d''un abonnement.';
  end if;

  if v_niveau is null and v_mods is null then
    raise exception 'PARAMETRES_VIDES|Indiquez au moins un niveau ou une liste de fonctionnalités.';
  end if;

  if v_niveau is not null and not exists (
    select 1 from public.niveaux_abonnement where code = v_niveau
  ) then
    raise exception 'NIVEAU_INTROUVABLE|Le niveau « % » n''existe pas.', v_niveau;
  end if;

  if v_mods is not null and jsonb_typeof(v_mods) <> 'array' then
    raise exception 'PARAMETRES_INVALIDES|La liste des fonctionnalités doit être une liste.';
  end if;

  select * into v_e from public.entreprises
   where id = p_entreprise_id for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Ce compte n''existe plus.';
  end if;

  v_avant_n := v_e.niveau_abonnement;
  v_avant_m := v_e.modules_abonnement;

  update public.entreprises
     set niveau_abonnement  = coalesce(v_niveau, v_e.niveau_abonnement),
         --  Une liste VIDE remet l'entreprise sur son niveau : c'est la façon
         --  d'annuler une négociation particulière.
         modules_abonnement = case
                                when v_mods is null then v_e.modules_abonnement
                                when jsonb_array_length(v_mods) = 0 then null
                                else v_mods
                              end,
         updated_at         = now()
   where id = p_entreprise_id
   returning * into v_e;

  begin
    insert into public.journal_audit (id, entreprise_id, action, utilisateur_id, details, created_at)
    values (
      gen_random_uuid(), p_entreprise_id, 'NIVEAU_ABONNEMENT_FIXE', auth.uid(),
      jsonb_build_object(
        'niveau_avant',  v_avant_n,
        'niveau_apres',  v_e.niveau_abonnement,
        'modules_avant', v_avant_m,
        'modules_apres', v_e.modules_abonnement,
        'note',          v_note,
        'correctif',     '65'
      ),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', p_entreprise_id,
    'niveau', v_e.niveau_abonnement,
    'modules', v_e.modules_abonnement,
    'modules_effectifs', public.abonnement_modules_entreprise(p_entreprise_id)
  );
end;
$$;

comment on function public.rpc_abonnement_definir_niveau_entreprise(uuid, text, jsonb, text) is
  'Correctif 65 — Fixe le niveau d''abonnement et/ou les fonctionnalités NÉGOCIÉES d''une entreprise. Liste vide = revenir au niveau.';

revoke all on function public.rpc_abonnement_definir_niveau_entreprise(uuid, text, jsonb, text) from public, anon;
grant execute on function public.rpc_abonnement_definir_niveau_entreprise(uuid, text, jsonb, text) to authenticated;


-- ============================================================================
--  8. CONTRÔLE
-- ============================================================================

do $verif_niveaux$
declare
  v_nb_niveaux integer;
  v_nb_rpc     integer;
begin
  select count(*) into v_nb_niveaux from public.niveaux_abonnement;

  if v_nb_niveaux < 3 then
    raise exception 'Correctif 65 : % niveau(x) au lieu des 3 amorces.', v_nb_niveaux;
  end if;

  if not exists (select 1 from public.niveaux_abonnement where code = 'ESSENTIEL' and actif) then
    raise exception 'Correctif 65 : le niveau d''entree ESSENTIEL est absent.';
  end if;

  select count(*) into v_nb_rpc
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public'
     and p.proname in ('rpc_abonnement_modules',
                       'abonnement_modules_entreprise',
                       'rpc_abonnement_niveau_enregistrer',
                       'rpc_abonnement_niveau_supprimer',
                       'rpc_abonnement_definir_niveau_entreprise');

  if v_nb_rpc <> 5 then
    raise exception 'Correctif 65 : % RPC(s) sur 5 presente(s).', v_nb_rpc;
  end if;

  raise notice 'Correctif 65 : fonctionnalites par abonnement en place.';
end $verif_niveaux$;


-- ============================================================================
--  RAPPORT FINAL — les niveaux, et ce que voit chaque entreprise
--  ⚠️ En DERNIER : le SQL Editor n'affiche que le résultat de la dernière
--     instruction du script.
-- ============================================================================

select '1. NIVEAU' as bloc,
       n.code as reference,
       n.libelle || ' (' || n.ordre || ')' as libelle,
       coalesce(n.prix_mensuel_conseille, 0) as prix_conseille,
       (case when jsonb_typeof(n.modules) = 'array'
             then jsonb_array_length(n.modules) else 0 end) as nb_fonctions,
       case when n.actif then 'actif' else 'inactif' end as etat
  from public.niveaux_abonnement n

union all

select '2. ENTREPRISE',
       coalesce(e.niveau_abonnement, '— (pack)') as reference,
       e.nom as libelle,
       coalesce(e.prix_abonnement_mensuel, 0) as prix_conseille,
       coalesce(jsonb_array_length(public.abonnement_modules_entreprise(e.id)), 0) as nb_fonctions,
       case
         when e.modules_abonnement is not null then 'fonctionnalites NEGOCIEES'
         when e.niveau_abonnement is not null then 'niveau propre'
         when e.groupe_tarifaire_id is not null then 'niveau du pack'
         else '⚠️ AUCUN niveau — fail-open (tout visible)'
       end as etat
  from public.entreprises e

 order by 1, 3;


-- ============================================================================
--  NOTE — CE QUI RESTE CÔTÉ APPLICATION (prochain lot)
--  ------------------------------------------------------------------------
--    • `ModulesService` : croiser les fonctionnalités de l'abonnement
--      (`rpc_abonnement_modules()`) avec celles de l'ACTIVITÉ. La règle
--      fail-open ne change pas : liste vide ou NULL → tout reste visible.
--    • `["*"]` = tout autoriser (aucun croisement à faire).
--    • Écran d'administration des NIVEAUX (CRUD complet, modules à cocher)
--      réservé au Super Admin.
--    • Sur la fiche d'une entreprise : afficher le niveau et permettre à la
--      Finance de le changer + d'ajuster les fonctionnalités.
--
--  POUR VÉRIFIER OU CORRIGER À LA MAIN :
--
--    --  voir les fonctionnalités d'une entreprise
--    select public.abonnement_modules_entreprise('<uuid-entreprise>'::uuid);
--
--    --  lui donner le niveau PRO
--    select public.rpc_abonnement_definir_niveau_entreprise(
--             '<uuid-entreprise>'::uuid, 'PRO');
--
--    --  lui négocier un jeu sur mesure (remplace le niveau)
--    select public.rpc_abonnement_definir_niveau_entreprise(
--             '<uuid-entreprise>'::uuid, null,
--             '["ventes","produits","stock","caisse","rapports","assistant_ia"]'::jsonb);
-- ============================================================================
