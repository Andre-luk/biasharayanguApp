-- ============================================================================
--  biashara_yangu — MIGRATION 0136 : L'ÉQUIPE DU PRESSING
--
--  DEMANDE
--    « Les collaborateurs du pressing doivent avoir des rôles selon le
--      pressing — comme la distribution. »
--
--  LE PROBLÈME ACTUEL
--    Un pressing réutilise les rôles génériques de la boutique : « caissier »
--    ou « magasinier ». Un patron de pressing ne dit pas à son employé « tu es
--    magasinier » : il dit « tu es à l'atelier » ou « tu es à l'accueil ».
--    Et surtout, AUCUN garde-fou ne distingue ces métiers : un caissier pouvait
--    modifier les tarifs, un agent d'atelier pouvait remettre un vêtement.
--
--  CE QUE FAIT CETTE MIGRATION (même mécanique que le module 24 distribution)
--    1. Colonne `utilisateurs.role_pressing` + `press_actif` : le métier dans
--       le pressing, DISTINCT du rôle générique (`new_role`), qui continue de
--       porter les pages autorisées.
--    2. `pressing_role()` — rôle du compte connecté dans SON pressing
--       ('proprietaire' pour le patron, sinon le métier saisi).
--    3. `pressing_exige(text[])` — refuse une action hors métier
--       (`ROLE_PRESSING_REFUSE`).
--    4. `press_collaborateurs_lister / _creer / _maj` : le patron crée lui-même
--       ses comptes (vrai compte Auth, mot de passe propre), avec le métier.
--    5. GARDE-FOUS par table (triggers) — les métiers décident vraiment :
--         • tarifs, prestations, catégories, réglages  → responsable ;
--         • dépôt (commandes, lignes)                  → accueil, responsable ;
--         • atelier (historique d'étapes)              → atelier, responsable ;
--         • argent (paiements, retraits)               → caisse, accueil,
--                                                        responsable.
--
--  ⚠️ COMPATIBILITÉ : un compte SANS `role_pressing` (créé avant cette
--     migration, ou le patron lui-même) garde exactement les droits de ses
--     pages. Les garde-fous ne bloquent donc jamais un compte existant.
--
--  ⚠️ IDEMPOTENT : peut être relancé sans effet de bord.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if to_regclass('public.pressing_commandes') is null then
    raise exception 'Module 35 absent : exécutez d''abord 20260916000120 → 20260916000123.';
  end if;
end $$;


-- ============================================================================
--  1. LE MÉTIER DANS LE PRESSING
-- ============================================================================

alter table public.utilisateurs
  add column if not exists role_pressing text;

alter table public.utilisateurs
  add column if not exists press_actif boolean not null default true;

comment on column public.utilisateurs.role_pressing is
  'Module 35 — métier dans le pressing : responsable | accueil | atelier | caisse. NULL = compte non concerné (patron, ou compte antérieur).';

comment on column public.utilisateurs.press_actif is
  'Module 35 — le collaborateur peut-il encore se connecter au pressing ?';

create index if not exists idx_utilisateurs_role_pressing
  on public.utilisateurs (parent_id, role_pressing);


-- ============================================================================
--  2. HELPERS DE RÔLE
-- ============================================================================

-- 2.a Rôle du compte connecté dans son pressing ------------------------------
create or replace function public.pressing_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
           when auth.uid() is not null
                and public.pressing_entreprise() = auth.uid()
             then 'proprietaire'
           else coalesce(
             nullif(lower(btrim((
               select u.role_pressing
                 from public.utilisateurs u
                where u.id = auth.uid()
             ))), ''),
             'aucun')
         end;
$$;

comment on function public.pressing_role() is
  'Module 35 — métier du compte connecté dans son pressing : proprietaire, responsable, accueil, atelier, caisse ou aucun.';

revoke all on function public.pressing_role() from public, anon;
grant execute on function public.pressing_role() to authenticated;


-- 2.b Contrôle d'accès par métier -------------------------------------------
--  'proprietaire' passe toujours. Un compte SANS métier (NULL / 'aucun')
--  passe aussi : ses droits restent ceux de ses pages (aucune régression).
create or replace function public.pressing_exige(p_roles text[])
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text := public.pressing_role();
begin
  if v_role in ('proprietaire', 'aucun') then
    return;
  end if;
  if p_roles is null or not (v_role = any (p_roles)) then
    raise exception
      'ROLE_PRESSING_REFUSE|Votre métier dans le pressing (%) ne permet pas cette action.',
      v_role;
  end if;
end;
$$;

comment on function public.pressing_exige(text[]) is
  'Module 35 — refuse l''action si le métier du collaborateur n''est pas dans la liste (le patron passe toujours).';

revoke all on function public.pressing_exige(text[]) from public, anon;
grant execute on function public.pressing_exige(text[]) to authenticated;


-- ============================================================================
--  3. LES GARDE-FOUS PAR TABLE
-- ============================================================================
--  Un seul trigger, qui lit le nom de la table. Volontairement limité aux
--  INSERT (et aux UPDATE des tables de catalogue) : les recalculs internes
--  touchent `pressing_commandes` / `pressing_lignes` en UPDATE, et un caissier
--  qui encaisse ne doit pas être bloqué par le garde-fou du dépôt.

create or replace function public.pressing_garde_metier()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := public.pressing_role();
  v_op   text := lower(tg_op);
  v_ok   boolean := true;
  v_qui  text;
begin
  -- Le patron, la plateforme et les comptes sans métier ne sont pas bridés.
  if v_role in ('proprietaire', 'aucun') or public.est_plateforme() then
    return new;
  end if;

  case tg_table_name
    -- 💰 LE PRIX ET LES RÉGLAGES : responsable seulement.
    when 'pressing_tarifs', 'pressing_prestations', 'pressing_categories' then
      v_ok := v_role = 'responsable';
      v_qui := 'les tarifs et le catalogue';

    when 'pressing_config' then
      -- La ligne de réglages est créée automatiquement à la première lecture
      -- (n'importe quel métier) ; seule la MODIFICATION est réservée.
      v_ok := (v_op = 'insert') or (v_role = 'responsable');
      v_qui := 'les réglages du pressing';

    -- 🧾 LE DÉPÔT : accueil (et responsable).
    when 'pressing_commandes', 'pressing_lignes' then
      v_ok := v_role in ('accueil', 'responsable');
      v_qui := 'le dépôt d''un vêtement';

    -- 🧺 L'HISTORIQUE D'ÉTAPES : deux écritures très différentes cohabitent.
    --    • « DEPOSE »  → écrit par l'ACCUEIL, au moment du dépôt ;
    --    • « REMIS »   → écrit par la CAISSE, au moment de la remise ;
    --    • les étapes intermédiaires (lavage, repassage, contrôle) → ATELIER.
    when 'pressing_ligne_etapes' then
      if upper(btrim(coalesce(new.etape_code, ''))) in ('DEPOSE', 'REMIS') then
        v_ok := v_role in ('accueil', 'caisse', 'atelier', 'responsable');
        v_qui := 'le dépôt et la remise';
      else
        v_ok := v_role in ('atelier', 'responsable');
        v_qui := 'l''atelier (traitement et contrôle)';
      end if;

    -- 💵 L'ARGENT : caisse et accueil.
    when 'pressing_paiements', 'pressing_retraits',
         'pressing_retrait_lignes' then
      v_ok := v_role in ('caisse', 'accueil', 'responsable');
      v_qui := 'l''encaissement et la remise';

    else
      v_ok := true;
  end case;

  if not v_ok then
    raise exception
      'ROLE_PRESSING_REFUSE|Votre métier dans le pressing (%) ne permet pas % . Demandez au responsable.',
      v_role, v_qui;
  end if;

  return new;
end;
$$;

comment on function public.pressing_garde_metier() is
  'Module 35 — applique le métier du collaborateur (responsable / accueil / atelier / caisse) sur les tables du pressing.';

-- Triggers (insertion seule, sauf le catalogue).
do $$
declare
  v_t text;
  v_tables text[] := array[
    'pressing_commandes', 'pressing_lignes', 'pressing_ligne_etapes',
    'pressing_paiements', 'pressing_retraits', 'pressing_retrait_lignes'
  ];
begin
  foreach v_t in array v_tables loop
    execute format('drop trigger if exists trg_press_metier on public.%I', v_t);
    execute format(
      'create trigger trg_press_metier before insert on public.%I
         for each row execute function public.pressing_garde_metier()', v_t);
  end loop;

  -- Catalogue et réglages : insertion ET modification.
  foreach v_t in array array['pressing_tarifs', 'pressing_prestations',
                             'pressing_categories', 'pressing_config'] loop
    execute format('drop trigger if exists trg_press_metier on public.%I', v_t);
    execute format(
      'create trigger trg_press_metier before insert or update on public.%I
         for each row execute function public.pressing_garde_metier()', v_t);
  end loop;
end $$;


-- ============================================================================
--  4. L'ÉQUIPE — LISTER, CRÉER, MODIFIER
-- ============================================================================

-- 4.a Lister ----------------------------------------------------------------
create or replace function public.press_collaborateurs_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent   uuid := public.pressing_entreprise();
  v_lignes jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.peut('pressing_depots', 'voir') then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de voir l''équipe du pressing.';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id',        u.id,
           'nom',       coalesce(u.nom, ''),
           'prenom',    coalesce(u.prenom, ''),
           'email',     coalesce(u.email, ''),
           'telephone', coalesce(u.telephone, ''),
           'role',      coalesce(u.role_pressing, ''),
           'actif',     coalesce(u.press_actif, true)
         ) order by coalesce(u.nom, ''), coalesce(u.prenom, '')), '[]'::jsonb)
    into v_lignes
    from public.utilisateurs u
   where u.parent_id = v_ent
     and u.role_pressing is not null;

  return jsonb_build_object(
    'role',  public.pressing_role(),
    'lignes', v_lignes
  );
end;
$$;

comment on function public.press_collaborateurs_lister() is
  'Module 35 — équipe du pressing (métier + état du compte).';

revoke all on function public.press_collaborateurs_lister() from public, anon;
grant execute on function public.press_collaborateurs_lister() to authenticated;


-- 4.b Créer un collaborateur ------------------------------------------------
--  Le métier décide des pages, et donc du rôle générique :
--    responsable → PROPRIETAIRE (tout le pressing, y compris les réglages)
--    accueil     → VENDEUR      (dépôt, retrait, caisse)
--    atelier     → MAGASINIER   (atelier, contrôle qualité)
--    caisse      → VENDEUR      (caisse, retrait)
create or replace function public.press_collaborateur_creer(
  p_nom          text,
  p_prenom       text,
  p_email        text,
  p_telephone    text,
  p_mot_de_passe text,
  p_role         text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_ent      uuid := public.pressing_entreprise();
  v_role     text := lower(btrim(coalesce(p_role, '')));
  v_email    text := lower(btrim(coalesce(p_email, '')));
  v_nom      text := nullif(btrim(coalesce(p_nom, '')), '');
  v_prenom   text := coalesce(btrim(coalesce(p_prenom, '')), '');
  v_tel      text := nullif(btrim(coalesce(p_telephone, '')), '');
  v_new_role text;
  v_user     uuid;
  v_existant uuid;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  -- Seul le patron (ou un responsable désigné) recrute.
  if not (public.pressing_role() in ('proprietaire', 'responsable')) then
    raise exception 'DROIT_REFUSE|Seul le patron ou le responsable peut créer un collaborateur.';
  end if;

  if v_role not in ('responsable', 'accueil', 'atelier', 'caisse') then
    raise exception 'ROLE_INVALIDE|Métier inconnu : choisissez responsable, accueil, atelier ou caisse.';
  end if;

  if v_nom is null then
    raise exception 'NOM_REQUIS|Indiquez le nom du collaborateur.';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'EMAIL_INVALIDE|Indiquez une adresse e-mail valide (elle sert d''identifiant de connexion).';
  end if;

  if p_mot_de_passe is null or length(p_mot_de_passe) < 8 then
    raise exception 'MOT_DE_PASSE_TROP_COURT|Le mot de passe doit comporter au moins 8 caractères.';
  end if;

  v_new_role := case v_role
                  when 'responsable' then 'PROPRIETAIRE'
                  when 'atelier'     then 'MAGASINIER'
                  else 'VENDEUR'
                end;

  select u.id into v_existant
    from public.utilisateurs u
   where lower(u.email) = v_email
   limit 1;

  if v_existant is not null then
    if exists (
      select 1 from public.utilisateurs u
       where u.id = v_existant
         and u.parent_id is not null
         and u.parent_id <> v_ent
    ) then
      raise exception 'COMPTE_EXISTANT|Cette adresse e-mail appartient déjà au collaborateur d''une autre entreprise.';
    end if;

    update auth.users
       set encrypted_password = crypt(p_mot_de_passe, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_existant;

    v_user := v_existant;
  else
    v_user := public.creer_compte_plateforme(
      v_email, p_mot_de_passe, v_nom, v_prenom, v_new_role);
  end if;

  update public.utilisateurs
     set nom           = v_nom,
         prenom        = v_prenom,
         email         = v_email,
         telephone     = coalesce(v_tel, telephone),
         role          = 'collaborator',
         new_role      = coalesce(public.role_enum(v_new_role), new_role),
         valide        = 1,
         parent_id     = v_ent,
         entreprise_id = coalesce(entreprise_id, v_ent),
         espace_actif_id = v_ent,
         role_pressing = v_role,
         press_actif   = true
   where id = v_user;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'PRESS_COLLABORATEUR_CREE', v_user,
    jsonb_build_object('role_pressing', v_role, 'email', v_email,
                       'boutique', v_ent),
    now()
  );

  return jsonb_build_object('ok', true, 'id', v_user, 'email', v_email,
                            'role', v_role);
end;
$$;

comment on function public.press_collaborateur_creer(text, text, text, text, text, text) is
  'Module 35 — crée le compte d''un collaborateur du pressing avec son métier (vrai compte Auth).';

revoke all on function public.press_collaborateur_creer(text, text, text, text, text, text) from public, anon;
grant execute on function public.press_collaborateur_creer(text, text, text, text, text, text) to authenticated;


-- 4.c Modifier un collaborateur ---------------------------------------------
create or replace function public.press_collaborateur_maj(
  p_id           uuid,
  p_nom          text,
  p_prenom       text,
  p_telephone    text,
  p_role         text,
  p_actif        boolean default true,
  p_mot_de_passe text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_ent      uuid := public.pressing_entreprise();
  v_role     text := lower(btrim(coalesce(p_role, '')));
  v_new_role text;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.pressing_role() in ('proprietaire', 'responsable')) then
    raise exception 'DROIT_REFUSE|Seul le patron ou le responsable peut modifier un collaborateur.';
  end if;

  if not exists (
    select 1 from public.utilisateurs u
     where u.id = p_id and u.parent_id = v_ent
  ) then
    raise exception 'COLLABORATEUR_INTROUVABLE|Ce collaborateur n''appartient pas à votre pressing.';
  end if;

  if v_role not in ('responsable', 'accueil', 'atelier', 'caisse') then
    raise exception 'ROLE_INVALIDE|Métier inconnu.';
  end if;

  v_new_role := case v_role
                  when 'responsable' then 'PROPRIETAIRE'
                  when 'atelier'     then 'MAGASINIER'
                  else 'VENDEUR'
                end;

  update public.utilisateurs
     set nom           = coalesce(nullif(btrim(coalesce(p_nom, '')), ''), nom),
         prenom        = coalesce(btrim(coalesce(p_prenom, '')), prenom),
         telephone     = coalesce(nullif(btrim(coalesce(p_telephone, '')), ''), telephone),
         role_pressing = v_role,
         press_actif   = coalesce(p_actif, true),
         new_role      = coalesce(public.role_enum(v_new_role), new_role),
         valide        = case when coalesce(p_actif, true) then 1 else 0 end
   where id = p_id;

  if p_mot_de_passe is not null and length(p_mot_de_passe) >= 8 then
    update auth.users
       set encrypted_password = crypt(p_mot_de_passe, gen_salt('bf')),
           updated_at = now()
     where id = p_id;
  end if;

  insert into public.journal_audit (
    id, entreprise_id, action, utilisateur_id, details, created_at
  ) values (
    gen_random_uuid(), null, 'PRESS_COLLABORATEUR_MAJ', p_id,
    jsonb_build_object('role_pressing', v_role, 'actif', p_actif,
                       'boutique', v_ent),
    now()
  );

  return jsonb_build_object('ok', true);
end;
$$;

comment on function public.press_collaborateur_maj(uuid, text, text, text, text, boolean, text) is
  'Module 35 — change le métier / l''état d''un collaborateur du pressing.';

revoke all on function public.press_collaborateur_maj(uuid, text, text, text, text, boolean, text) from public, anon;
grant execute on function public.press_collaborateur_maj(uuid, text, text, text, text, boolean, text) to authenticated;


-- ============================================================================
--  5. DIAGNOSTIC (lecture seule)
-- ============================================================================

select 'MIGRATION 0136 PRÊTE' as controle,
       (select count(*) from public.utilisateurs where role_pressing is not null)
         as collaborateurs_avec_metier;

select 'GARDE-FOU MÉTIER' as controle,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.proname = 'pressing_garde_metier' and n.nspname = 'public')
         as fonction_ok,
       (select count(*) from pg_trigger where tgname = 'trg_press_metier')
         as triggers_particuliers,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.proname = 'press_collaborateur_creer' and n.nspname = 'public')
         as rpc_creation_ok;
