-- ============================================================================
--  biashara_yangu — MIGRATION 0175
--  ÉQUIPE PRESSING · SCANNER QR · TARIF & REVENUS QR · REVENUS SERDIPAY ·
--  ANALYSE D'UNE ENTREPRISE (semaine / mois)
--  ---------------------------------------------------------------------------
--  Fichier : supabase/migrations/20260916000175_equipe_qr_revenus_analyse.sql
--
--  ⚠️ À EXÉCUTER APRÈS LA MIGRATION 0174 (instantanés du journal, suppression
--     sans blocage du journal). 0175 est idempotente : relançable sans effet.
--
--  CE QUE CETTE MIGRATION CORRIGE / AJOUTE
--  ---------------------------------------------------------------------------
--  P1. « insert or update on table utilisateurs violates foreign key
--       constraint utilisateurs_parent_id_fkey » à l'ajout d'un collaborateur
--       du PRESSING.
--      → `press_collaborateur_creer` écrivait `parent_id = <entreprise>`
--        alors que `parent_id` référence `utilisateurs(id)` (le PATRON).
--        La liste (`press_collaborateurs_lister`) filtrait sur la même valeur
--        fausse : l'équipe serait restée vide même après correction de la FK.
--      → `parent_id = public.mon_patron()`, `espace_actif_id` = un espace
--        RÉEL de l'entreprise, `entreprise_id` = l'entreprise du patron.
--      → nouvelle RPC `press_collaborateur_supprimer` (retirer un compte).
--
--  P2. QR code généré mais « article introuvable » au scan.
--      → la résolution passait par `produits` sous RLS : un produit d'un
--        autre espace de la MÊME entreprise (ou un produit historique dont
--        `owner_id` est encore l'UUID du patron) était invisible.
--      → nouvelle RPC `rpc_scanner_resoudre(code)` : SECURITY DEFINER, elle
--        résout `PROD:<id>` / `COND:<uuid>` dans le périmètre de l'ENTREPRISE
--        du demandeur (et de la plateforme), jamais au-delà.
--
--  P3. Prix d'un QR code + revenus QR.
--      → `qr_codes_emis` : un QR par produit (idempotent), prix unitaire
--        défini par la plateforme (150 CDF par défaut, MODIFIABLE).
--      → `rpc_qr_tarif_etat`, `rpc_qr_tarif_definir`,
--        `rpc_qr_code_emettre`.
--
--  P4. Revenus de la plateforme = UNIQUEMENT l'argent passé par SerdiPay.
--      → `rpc_admin_tableau_bord()` : total encaissé = Σ
--        `paiements_serdipay.montant` avec `statut = 'paye'` (rien d'autre
--        n'est compté : ni les ventes des boutiques, ni les promesses de
--        paiement). Les QR émis y sont présentés séparément.
--
--  P5. Rapport PAR ENTREPRISE, par semaine ou par mois.
--      → `rpc_rapport_entreprise_analyse(entreprise, debut, fin)` :
--        meilleur produit, meilleur jour, meilleur moment, panier moyen,
--        conseils de croissance et SIMULATION « si ce produit progresse de
--        X %, la boutique gagne Y CDF ».
--
--  ⚠️ AUCUNE donnée existante n'est supprimée.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


-- ============================================================================
--  1. ÉQUIPE DU PRESSING — LE PARENT EST LE PATRON (pas l'entreprise)
-- ============================================================================

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
  v_patron   uuid := public.mon_patron();
  v_espace   uuid;
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

  if not (public.pressing_role() in ('proprietaire', 'responsable')) then
    raise exception 'DROIT_REFUSE|Seul le patron ou le responsable peut créer un collaborateur.';
  end if;

  if v_ent is null or v_patron is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Aucune entreprise rattachée à ce compte.';
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

  -- L'ESPACE à activer doit EXISTER : `utilisateurs.espace_actif_id` est une
  -- clé étrangère vers `espaces(id)` (jamais l'identifiant de l'entreprise).
  select s.id into v_espace
    from public.espaces s
   where s.entreprise_id = v_ent
   order by (s.id = v_patron) desc, s.created_at asc nulls last
   limit 1;

  if v_espace is null then
    select u.espace_actif_id into v_espace
      from public.utilisateurs u
     where u.id = v_patron;
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
    -- Déjà collaborateur d'une AUTRE équipe ?
    if exists (
      select 1 from public.utilisateurs u
       where u.id = v_existant
         and u.parent_id is not null
         and u.parent_id <> v_patron
    ) then
      raise exception 'COMPTE_EXISTANT|Cette adresse e-mail appartient déjà au collaborateur d''une autre entreprise.';
    end if;

    if v_existant = v_patron then
      raise exception 'COMPTE_EXISTANT|Cette adresse est celle du propriétaire : choisissez une autre adresse.';
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
     set nom             = v_nom,
         prenom          = v_prenom,
         email           = v_email,
         telephone       = coalesce(v_tel, telephone),
         role            = 'collaborator',
         new_role        = coalesce(public.role_enum(v_new_role), new_role),
         valide          = 1,
         -- ✅ LE PATRON (utilisateurs.id) — cause de la violation de clé.
         parent_id       = v_patron,
         entreprise_id   = coalesce(
                             (select u.entreprise_id from public.utilisateurs u
                               where u.id = v_patron),
                             v_ent),
         espace_actif_id = v_espace,
         role_pressing   = v_role,
         press_actif     = true
   where id = v_user;

  begin
    insert into public.journal_audit (
      entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      null, 'PRESS_COLLABORATEUR_CREE', v_user,
      jsonb_build_object('role_pressing', v_role, 'email', v_email,
                         'boutique', v_ent, 'patron', v_patron),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'id', v_user, 'email', v_email,
                            'role', v_role);
end;
$$;

comment on function public.press_collaborateur_creer(text, text, text, text, text, text) is
  '0175 — crée un collaborateur du pressing avec le BON parent (le patron) et un espace existant. Corrige utilisateurs_parent_id_fkey.';

revoke all on function public.press_collaborateur_creer(text, text, text, text, text, text) from public, anon;
grant execute on function public.press_collaborateur_creer(text, text, text, text, text, text) to authenticated;


create or replace function public.press_collaborateurs_lister()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent    uuid := public.pressing_entreprise();
  v_patron uuid := public.mon_patron();
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
   where u.parent_id = v_patron
     and u.role_pressing is not null
     and (v_ent is null or u.entreprise_id = v_ent or u.entreprise_id is null);

  return jsonb_build_object(
    'role',  public.pressing_role(),
    'lignes', v_lignes
  );
end;
$$;

comment on function public.press_collaborateurs_lister() is
  '0175 — équipe du pressing : filtre sur le PATRON (utilisateurs.parent_id), plus sur l''entreprise (ancien bug : liste toujours vide).';

revoke all on function public.press_collaborateurs_lister() from public, anon;
grant execute on function public.press_collaborateurs_lister() to authenticated;


create or replace function public.press_collaborateur_supprimer(
  p_id           uuid,
  p_confirmation text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_patron uuid := public.mon_patron();
  v_u      public.utilisateurs;
  v_auth   boolean := false;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if not (public.pressing_role() in ('proprietaire', 'responsable')) then
    raise exception 'DROIT_REFUSE|Seul le patron ou le responsable peut retirer un collaborateur.';
  end if;

  if upper(btrim(coalesce(p_confirmation, ''))) <> 'SUPPRIMER' then
    raise exception 'CONFIRMATION_REQUISE|Tapez SUPPRIMER pour confirmer.';
  end if;

  select * into v_u from public.utilisateurs where id = p_id;
  if not found then
    raise exception 'UTILISATEUR_INCONNU|Ce collaborateur n''existe plus.';
  end if;

  if p_id = auth.uid() or p_id = v_patron then
    raise exception 'DROIT_REFUSE|Vous ne pouvez pas retirer ce compte (patron ou vous-même).';
  end if;

  if v_u.parent_id is distinct from v_patron or v_u.role_pressing is null then
    raise exception 'DROIT_REFUSE|Ce compte ne fait pas partie de votre équipe pressing.';
  end if;

  -- Les historiques du pressing gardent l'identifiant (aucune FK bloquante) :
  -- on n'efface que le COMPTE.
  begin
    delete from public.utilisateurs where id = p_id;
  exception
    when foreign_key_violation then
      raise exception 'SUPPRESSION_BLOQUEE|Le journal d''audit bloque encore ce compte : exécutez d''abord la migration 174.';
  end;

  begin
    delete from auth.users where id = p_id;
    v_auth := true;
  exception when others then
    v_auth := false;
  end;

  begin
    insert into public.journal_audit (
      entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      null, 'PRESS_COLLABORATEUR_SUPPRIME', auth.uid(),
      jsonb_build_object('collaborateur_id', p_id, 'email', v_u.email,
                         'role_pressing', v_u.role_pressing,
                         'compte_auth_supprime', v_auth),
      now()
    );
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'id', p_id,
                            'compte_auth_supprime', v_auth);
end;
$$;

comment on function public.press_collaborateur_supprimer(uuid, text) is
  '0175 — retire un collaborateur du pressing (compte Auth + profil). Patron/responsable, confirmation SUPPRIMER, jamais le patron lui-même.';

revoke all on function public.press_collaborateur_supprimer(uuid, text) from public, anon;
grant execute on function public.press_collaborateur_supprimer(uuid, text) to authenticated;


-- ============================================================================
--  2. SCANNER — RÉSOUDRE UN QR DANS LE PÉRIMÈTRE DE L'ENTREPRISE
-- ============================================================================
--  Pourquoi une RPC ? Parce que la lecture directe de `produits` est filtrée
--  par la RLS : un article d'un AUTRE ESPACE de la même entreprise (ou dont
--  `owner_id` porte encore l'UUID du patron) devenait « introuvable » alors
--  que l'étiquette était valide.
-- ============================================================================

create or replace function public.rpc_scanner_resoudre(p_code text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_code    text := upper(btrim(coalesce(p_code, '')));
  v_ent     uuid := public.mon_entreprise_id();
  v_patron  uuid := public.mon_patron();
  v_id      bigint;
  v_qr      uuid;
  v_produit public.produits%rowtype;
  v_cond    public.conditionnements%rowtype;
  v_ok      boolean;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if v_code like 'PROD:%' then
    begin
      v_id := nullif(btrim(substring(v_code from 6)), '')::bigint;
    exception when others then
      raise exception 'QR_INVALIDE|QR code illisible : identifiant d''article invalide.';
    end;

    if v_id is null then
      raise exception 'QR_INVALIDE|QR code illisible : identifiant d''article absent.';
    end if;

    select * into v_produit from public.produits p where p.id = v_id;
    if not found then
      raise exception 'PRODUIT_INTROUVABLE|Article introuvable : il a peut-être été supprimé.';
    end if;

    select (public.est_plateforme()
            or v_produit.owner_id = auth.uid()
            or v_produit.owner_id = v_patron
            or exists (select 1 from public.espaces s
                        where s.id = v_produit.owner_id
                          and s.entreprise_id = v_ent))
      into v_ok;

    if not coalesce(v_ok, false) then
      raise exception 'PRODUIT_INTROUVABLE|Article introuvable : il appartient à une autre entreprise.';
    end if;

    return jsonb_build_object(
      'ok', true, 'type', 'article',
      'produit', to_jsonb(v_produit),
      'conditionnement', null);
  end if;

  if v_code like 'COND:%' then
    begin
      v_qr := nullif(btrim(substring(v_code from 6)), '')::uuid;
    exception when others then
      raise exception 'QR_INVALIDE|QR code illisible : identifiant de conditionnement invalide.';
    end;

    if v_qr is null then
      raise exception 'QR_INVALIDE|QR code illisible : identifiant de conditionnement absent.';
    end if;

    select * into v_cond from public.conditionnements c where c.qr_code_id = v_qr;
    if not found then
      raise exception 'CONDITIONNEMENT_INTROUVABLE|Conditionnement introuvable : cette étiquette a peut-être été supprimée.';
    end if;

    select * into v_produit from public.produits p where p.id = v_cond.produit_id;
    if not found then
      raise exception 'PRODUIT_INTROUVABLE|L''article de ce conditionnement est introuvable.';
    end if;

    select (public.est_plateforme()
            or v_produit.owner_id = auth.uid()
            or v_produit.owner_id = v_patron
            or exists (select 1 from public.espaces s
                        where s.id = v_produit.owner_id
                          and s.entreprise_id = v_ent))
      into v_ok;

    if not coalesce(v_ok, false) then
      raise exception 'PRODUIT_INTROUVABLE|Article introuvable : il appartient à une autre entreprise.';
    end if;

    return jsonb_build_object(
      'ok', true, 'type', 'conditionnement',
      'produit', to_jsonb(v_produit),
      'conditionnement', to_jsonb(v_cond));
  end if;

  raise exception 'QR_INVALIDE|Ce QR code n''est pas une étiquette Biashara Yangu.';
end;
$$;

comment on function public.rpc_scanner_resoudre(text) is
  '0175 — résout PROD:<id> / COND:<uuid> dans le périmètre de l''entreprise du demandeur (ou plateforme). Remplace la lecture RLS qui rendait certains articles « introuvables ».';

revoke all on function public.rpc_scanner_resoudre(text) from public, anon;
grant execute on function public.rpc_scanner_resoudre(text) to authenticated;


-- 2.b LE CATALOGUE D'UNE ENTREPRISE (toutes ses boutiques).
--     L'écran QR de la plateforme cherchait les articles par UUID du PATRON :
--     depuis que `produits.owner_id` porte l'ESPACE, il ne trouvait plus rien
--     (ou les mauvais articles). Cette RPC renvoie TOUS les articles des
--     espaces de l'entreprise, plus les articles historiques du patron.
create or replace function public.rpc_articles_entreprise(p_entreprise_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_lignes jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if p_entreprise_id is null then
    raise exception 'ENTREPRISE_INVALIDE|Aucune entreprise choisie.';
  end if;

  if not (public.est_plateforme()
          or exists (select 1 from public.entreprises e
                      where e.id = p_entreprise_id
                        and e.owner_id in (auth.uid(), public.mon_patron()))
          or public.mon_entreprise_id() = p_entreprise_id) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette entreprise.';
  end if;

  select coalesce(jsonb_agg(to_jsonb(p) order by p.nom), '[]'::jsonb)
    into v_lignes
    from public.produits p
   where exists (select 1 from public.espaces s
                  where s.id = p.owner_id
                    and s.entreprise_id = p_entreprise_id)
      or p.owner_id in (select u.id from public.utilisateurs u
                         where u.entreprise_id = p_entreprise_id);

  return v_lignes;
end;
$$;

comment on function public.rpc_articles_entreprise(uuid) is
  '0175 — catalogue complet d''une entreprise (tous ses espaces + articles historiques du patron). Sert à l''écran QR de la plateforme.';

revoke all on function public.rpc_articles_entreprise(uuid) from public, anon;
grant execute on function public.rpc_articles_entreprise(uuid) to authenticated;


-- ============================================================================
--  3. QR CODES — TARIF DE LA PLATEFORME ET REVENUS
-- ============================================================================
-- 3.a Réglage : 150 CDF par défaut, modifiable par le Super Admin.
insert into public.app_settings (key, value, updated_at)
values ('qr_codes', '{"prix": 150, "devise": "CDF"}'::jsonb, now())
on conflict (key) do nothing;

-- 3.b Registre des QR émis. UNE ligne par produit (idempotent) : régénérer
--     une étiquette ne facture pas deux fois le même produit.
create table if not exists public.qr_codes_emis (
  id            uuid primary key default gen_random_uuid(),
  entreprise_id uuid not null,
  espace_id     uuid,
  produit_id    bigint not null,
  produit_nom   text,
  quantite      integer not null default 1,
  prix_unitaire numeric(12, 2) not null,
  devise        text not null default 'CDF',
  total         numeric(14, 2) not null,
  emis_par      uuid,
  created_at    timestamptz not null default now(),
  mis_a_jour_le timestamptz not null default now(),
  constraint qr_codes_emis_unique unique (entreprise_id, produit_id)
);

comment on table public.qr_codes_emis is
  '0175 — QR codes émis par produit (un seul par produit et par entreprise). Sert au calcul des revenus QR de la plateforme (prix unitaire réglable).';

create index if not exists qr_codes_emis_entreprise_idx
  on public.qr_codes_emis (entreprise_id, created_at desc);

alter table public.qr_codes_emis enable row level security;

drop policy if exists qr_codes_emis_lecture on public.qr_codes_emis;
create policy qr_codes_emis_lecture on public.qr_codes_emis
  for select to authenticated
  using (
    public.est_plateforme()
    or entreprise_id = public.mon_entreprise_id()
    or espace_id = public.mon_proprietaire()
  );

revoke insert, update, delete on public.qr_codes_emis
  from public, anon, authenticated;

-- 3.c Lire le tarif + les revenus QR (plateforme).
create or replace function public.rpc_qr_tarif_etat()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_prix   numeric := 150;
  v_devise text := 'CDF';
  v_val    jsonb;
  v_nb     bigint := 0;
  v_total  numeric := 0;
  v_mois   numeric := 0;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Réservé à la plateforme.';
  end if;

  select s.value into v_val from public.app_settings s where s.key = 'qr_codes';
  if v_val is not null then
    v_prix   := coalesce((v_val->>'prix')::numeric, v_prix);
    v_devise := coalesce(nullif(v_val->>'devise', ''), v_devise);
  end if;

  select count(*), coalesce(sum(q.total), 0) into v_nb, v_total
    from public.qr_codes_emis q;

  select coalesce(sum(q.total), 0) into v_mois
    from public.qr_codes_emis q
   where q.created_at >= date_trunc('month', now());

  return jsonb_build_object(
    'ok', true,
    'prix', v_prix,
    'devise', v_devise,
    'nb_qr', v_nb,
    'revenus_total', v_total,
    'revenus_mois', v_mois
  );
end;
$$;

comment on function public.rpc_qr_tarif_etat() is
  '0175 — tarif du QR (défaut 150 CDF) et revenus QR de la plateforme.';

revoke all on function public.rpc_qr_tarif_etat() from public, anon;
grant execute on function public.rpc_qr_tarif_etat() to authenticated;


create or replace function public.rpc_qr_tarif_definir(p_prix numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Seul le Super Administrateur règle le prix du QR code.';
  end if;
  if p_prix is null or p_prix <= 0 or p_prix > 100000 then
    raise exception 'MONTANT_INVALIDE|Indiquez un prix entre 1 et 100 000 CDF.';
  end if;

  insert into public.app_settings (key, value, updated_at)
  values ('qr_codes',
          jsonb_build_object('prix', round(p_prix, 2), 'devise', 'CDF'),
          now())
  on conflict (key) do update
     set value = jsonb_build_object('prix', round(p_prix, 2), 'devise', 'CDF'),
         updated_at = now();

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id,
                                      details, created_at)
    values (null, 'QR_TARIF_DEFINI', auth.uid(),
            jsonb_build_object('prix', p_prix), now());
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'prix', round(p_prix, 2));
end;
$$;

comment on function public.rpc_qr_tarif_definir(numeric) is
  '0175 — fixe le prix unitaire d''un QR code (plateforme uniquement).';

revoke all on function public.rpc_qr_tarif_definir(numeric) from public, anon;
grant execute on function public.rpc_qr_tarif_definir(numeric) to authenticated;


-- 3.d Émettre (facturer) les QR d'une liste de produits.
create or replace function public.rpc_qr_code_emettre(
  p_produit_ids bigint[],
  p_quantite    integer default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_val     jsonb;
  v_prix    numeric := 150;
  v_devise  text := 'CDF';
  v_qte     integer := greatest(1, coalesce(p_quantite, 1));
  v_ent     uuid := public.mon_entreprise_id();
  v_prod    record;
  v_nb      integer := 0;
  v_total   numeric := 0;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  if p_produit_ids is null or array_length(p_produit_ids, 1) is null then
    return jsonb_build_object('ok', true, 'prix', 150, 'nb', 0, 'total', 0);
  end if;

  select s.value into v_val from public.app_settings s where s.key = 'qr_codes';
  if v_val is not null then
    v_prix   := coalesce((v_val->>'prix')::numeric, v_prix);
    v_devise := coalesce(nullif(v_val->>'devise', ''), v_devise);
  end if;

  for v_prod in
    select p.id, p.nom, p.owner_id
      from public.produits p
     where p.id = any(p_produit_ids)
  loop
    -- Portée : plateforme, ou produit d'un espace de MON entreprise.
    if not (public.est_plateforme()
            or v_prod.owner_id = auth.uid()
            or v_prod.owner_id = public.mon_patron()
            or exists (select 1 from public.espaces s
                        where s.id = v_prod.owner_id
                          and s.entreprise_id = v_ent)) then
      continue;
    end if;

    declare
      v_ent_produit uuid;
    begin
      select s.entreprise_id into v_ent_produit
        from public.espaces s
       where s.id = v_prod.owner_id;

      v_ent_produit := coalesce(v_ent_produit, v_ent);

      insert into public.qr_codes_emis (
        entreprise_id, espace_id, produit_id, produit_nom,
        quantite, prix_unitaire, devise, total, emis_par
      ) values (
        v_ent_produit, v_prod.owner_id, v_prod.id, v_prod.nom,
        v_qte, v_prix, v_devise, v_prix,
        auth.uid()
      )
      on conflict (entreprise_id, produit_id) do update
         set quantite      = greatest(qr_codes_emis.quantite,
                                      excluded.quantite),
             produit_nom   = excluded.produit_nom,
             prix_unitaire = excluded.prix_unitaire,
             devise        = excluded.devise,
             total         = greatest(qr_codes_emis.quantite,
                                      excluded.quantite) * excluded.prix_unitaire,
             mis_a_jour_le = now();

      v_nb := v_nb + 1;
    exception when others then
      -- Un produit illisible ne doit pas annuler les autres.
      null;
    end;
  end loop;

  select coalesce(sum(q.total), 0) into v_total
    from public.qr_codes_emis q
   where q.produit_id = any(p_produit_ids);

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id,
                                      details, created_at)
    values (null, 'QR_CODES_EMIS', auth.uid(),
            jsonb_build_object('produits', v_nb, 'prix', v_prix,
                               'quantite', v_qte), now());
  exception when others then null;
  end;

  return jsonb_build_object('ok', true, 'prix', v_prix, 'devise', v_devise,
                            'nb', v_nb, 'total', v_total);
end;
$$;

comment on function public.rpc_qr_code_emettre(bigint[], integer) is
  '0175 — enregistre (et facture une seule fois par produit) les QR codes émis. Idempotent : régénérer une étiquette ne double pas la facture.';

revoke all on function public.rpc_qr_code_emettre(bigint[], integer) from public, anon;
grant execute on function public.rpc_qr_code_emettre(bigint[], integer) to authenticated;


-- ============================================================================
--  4. TABLEAU DE BORD PLATEFORME — L'ARGENT = SERDIPAY UNIQUEMENT
-- ============================================================================

create or replace function public.rpc_admin_tableau_bord()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_total      numeric := 0;
  v_mois       numeric := 0;
  v_jour       numeric := 0;
  v_nb         bigint := 0;
  v_qr_total   numeric := 0;
  v_qr_mois    numeric := 0;
  v_qr_nb      bigint := 0;
  v_qr_prix    numeric := 150;
  v_entreprises bigint := 0;
  v_comptes    bigint := 0;
  v_produits   bigint := 0;
  v_val        jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not public.est_plateforme() then
    raise exception 'DROIT_REFUSE|Tableau de bord réservé à la plateforme.';
  end if;

  -- 💰 REVENUS RÉELS : uniquement les paiements CONFIRMÉS par SerdiPay.
  --    Aucune vente de boutique, aucun encaissement manuel, aucune promesse
  --    de paiement n'entre dans ce total.
  select coalesce(sum(s.montant), 0), count(*)
    into v_total, v_nb
    from public.paiements_serdipay s
   where s.statut = 'paye';

  select coalesce(sum(s.montant), 0) into v_mois
    from public.paiements_serdipay s
   where s.statut = 'paye'
     and coalesce(s.paye_le, s.created_at) >= date_trunc('month', now());

  select coalesce(sum(s.montant), 0) into v_jour
    from public.paiements_serdipay s
   where s.statut = 'paye'
     and coalesce(s.paye_le, s.created_at) >= date_trunc('day', now());

  -- 🏷️ REVENUS QR (facturés à l'émission, prix de la plateforme).
  select s.value into v_val from public.app_settings s where s.key = 'qr_codes';
  if v_val is not null then
    v_qr_prix := coalesce((v_val->>'prix')::numeric, v_qr_prix);
  end if;

  select count(*), coalesce(sum(q.total), 0) into v_qr_nb, v_qr_total
    from public.qr_codes_emis q;

  select coalesce(sum(q.total), 0) into v_qr_mois
    from public.qr_codes_emis q
   where q.created_at >= date_trunc('month', now());

  select count(*) into v_entreprises from public.entreprises;
  select count(*) into v_comptes from public.utilisateurs;
  select count(*) into v_produits from public.produits;

  return jsonb_build_object(
    'ok', true,
    'devise', 'CDF',
    'serdipay', jsonb_build_object(
      'total', v_total, 'mois', v_mois, 'jour', v_jour, 'paiements', v_nb),
    'qr', jsonb_build_object(
      'prix', v_qr_prix, 'nb', v_qr_nb,
      'total', v_qr_total, 'mois', v_qr_mois),
    'compteurs', jsonb_build_object(
      'entreprises', v_entreprises,
      'comptes', v_comptes,
      'produits', v_produits)
  );
end;
$$;

comment on function public.rpc_admin_tableau_bord() is
  '0175 — tableau de bord plateforme : argent = SOMME des paiements SerdiPay confirmés (statut paye), plus les revenus QR. Rien d''autre n''est compté.';

revoke all on function public.rpc_admin_tableau_bord() from public, anon;
grant execute on function public.rpc_admin_tableau_bord() to authenticated;


-- ============================================================================
--  5. ANALYSE D'UNE ENTREPRISE — SEMAINE / MOIS
-- ============================================================================
--  Répond aux questions du patron : quel produit se vend le plus, quel jour,
--  à quel moment, et COMBIEN la boutique gagnerait en poussant un produit.
-- ============================================================================

create or replace function public.rpc_rapport_entreprise_analyse(
  p_entreprise_id uuid,
  p_debut         date,
  p_fin           date
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_nom       text;
  v_perim     uuid[] := array[]::uuid[];
  v_debut     date := coalesce(p_debut, current_date - 6);
  v_fin       date := coalesce(p_fin, current_date);
  v_ca        numeric := 0;
  v_ventes    bigint := 0;
  v_articles  numeric := 0;
  v_panier    numeric := 0;
  v_marge     numeric := 0;
  v_top       jsonb := '[]'::jsonb;
  v_jours     jsonb := '[]'::jsonb;
  v_moments   jsonb := '[]'::jsonb;
  v_best_prod jsonb;
  v_best_jour jsonb;
  v_best_mom  jsonb;
  v_conseils  jsonb := '[]'::jsonb;
  v_simul     jsonb := '{}'::jsonb;
  v_part      numeric := 0;
  v_jour_nom  text;
  v_mom_nom   text;
  v_objectif  numeric := 0.10;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;

  select e.nom into v_nom
    from public.entreprises e
   where e.id = p_entreprise_id;

  if v_nom is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Cette entreprise n''existe pas.';
  end if;

  if not (public.est_plateforme()
          or exists (select 1 from public.entreprises e
                      where e.id = p_entreprise_id
                        and e.owner_id in (auth.uid(), public.mon_patron()))) then
    raise exception 'DROIT_REFUSE|Vous n''avez pas accès à cette entreprise.';
  end if;

  if v_fin < v_debut then
    raise exception 'PERIODE_INVALIDE|La date de fin précède la date de début.';
  end if;

  -- Périmètre : espaces de l'entreprise + comptes rattachés (ventes
  -- historiques dont `owner_id` porte encore l'UUID du patron).
  select coalesce(array_agg(distinct x), array[]::uuid[]) into v_perim
    from (
      select s.id as x from public.espaces s where s.entreprise_id = p_entreprise_id
      union
      select u.id from public.utilisateurs u where u.entreprise_id = p_entreprise_id
      union
      select e.owner_id from public.entreprises e
       where e.id = p_entreprise_id and e.owner_id is not null
    ) t;

  create temporary table if not exists _analyse_ventes (
    produit_id bigint, nom text, quantite numeric, prix numeric,
    prix_achat numeric, local_date timestamp, tranche text
  ) on commit drop;

  delete from _analyse_ventes;

  insert into _analyse_ventes (produit_id, nom, quantite, prix, prix_achat,
                               local_date, tranche)
  select v.produit_id,
         coalesce(p.nom, 'Article supprimé'),
         coalesce(v.quantite, 0),
         coalesce(v.prix, 0),
         p.prix_achat,
         (v.date at time zone 'Africa/Lubumbashi'),
         case
           when extract(hour from (v.date at time zone 'Africa/Lubumbashi')) between 6 and 10 then 'Matin (6h–11h)'
           when extract(hour from (v.date at time zone 'Africa/Lubumbashi')) between 11 and 14 then 'Midi (11h–15h)'
           when extract(hour from (v.date at time zone 'Africa/Lubumbashi')) between 15 and 18 then 'Après-midi (15h–19h)'
           when extract(hour from (v.date at time zone 'Africa/Lubumbashi')) between 19 and 22 then 'Soir (19h–23h)'
           else 'Nuit (23h–6h)'
         end
    from public.ventes v
    left join public.produits p on p.id = v.produit_id
   where v.owner_id = any(v_perim)
     and v.date >= v_debut::timestamptz
     and v.date < (v_fin + 1)::timestamptz;

  select coalesce(sum(prix), 0), count(*), coalesce(sum(quantite), 0)
    into v_ca, v_ventes, v_articles
    from _analyse_ventes;

  select coalesce(sum(prix - coalesce(prix_achat, 0) * quantite), 0)
    into v_marge
    from _analyse_ventes;

  if v_ventes > 0 then
    v_panier := round(v_ca / v_ventes, 2);
  end if;

  -- Top produits (par chiffre d'affaires).
  select coalesce(jsonb_agg(jsonb_build_object(
           'rang', x.rang, 'nom', x.nom, 'quantite', x.qte, 'ca', x.ca,
           'part', case when v_ca > 0 then round(100 * x.ca / v_ca, 1) else 0 end
         ) order by x.rang), '[]'::jsonb)
    into v_top
    from (
      select a.nom,
             sum(a.quantite) as qte,
             sum(a.prix) as ca,
             row_number() over (order by sum(a.prix) desc, a.nom) as rang
        from _analyse_ventes a
       group by a.nom
       limit 10
    ) x;

  if jsonb_array_length(v_top) > 0 then
    v_best_prod := v_top->0;
    v_part := coalesce((v_best_prod->>'part')::numeric, 0);
  end if;

  -- Jours de la semaine (0 = dimanche côté PostgreSQL).
  select coalesce(jsonb_agg(jsonb_build_object(
           'dow', d.dow, 'jour', d.jour, 'ca', d.ca, 'ventes', d.nb
         ) order by d.dow), '[]'::jsonb)
    into v_jours
    from (
      select extract(dow from a.local_date)::int as dow,
             case extract(dow from a.local_date)::int
               when 0 then 'Dimanche' when 1 then 'Lundi' when 2 then 'Mardi'
               when 3 then 'Mercredi' when 4 then 'Jeudi' when 5 then 'Vendredi'
               else 'Samedi' end as jour,
             sum(a.prix) as ca,
             count(*) as nb
        from _analyse_ventes a
       group by 1
    ) d;

  select j into v_best_jour
    from jsonb_array_elements(v_jours) j
   order by (j->>'ca')::numeric desc
   limit 1;

  -- Moments de la journée.
  select coalesce(jsonb_agg(jsonb_build_object(
           'moment', m.tranche, 'ca', m.ca, 'ventes', m.nb
         ) order by m.ca desc), '[]'::jsonb)
    into v_moments
    from (
      select a.tranche, sum(a.prix) as ca, count(*) as nb
        from _analyse_ventes a
       group by a.tranche
    ) m;

  v_best_mom := v_moments->0;

  -- Conseils (calculés sur les données réelles, jamais inventés).
  if v_ventes = 0 then
    v_conseils := jsonb_build_array(jsonb_build_object(
      'titre', 'Aucune vente sur la période',
      'detail', 'Choisissez une autre période, ou vérifiez que les ventes sont bien enregistrées dans cette entreprise.'));
  else
    if v_best_jour is not null then
      v_jour_nom := coalesce(v_best_jour->>'jour', '');
      v_conseils := v_conseils || jsonb_build_object(
        'titre', format('Votre meilleur jour : %s', v_jour_nom),
        'detail', format('%s réalise %s CDF. Prévoyez le stock et le personnel ce jour-là, et lancez vos promotions la veille.', v_jour_nom, to_char(coalesce((v_best_jour->>'ca')::numeric, 0), 'FM999G999G999G999')));
    end if;

    if v_best_mom is not null then
      v_mom_nom := coalesce(v_best_mom->>'moment', '');
      v_conseils := v_conseils || jsonb_build_object(
        'titre', format('Votre pic horaire : %s', v_mom_nom),
        'detail', format('Ce créneau pèse %s CDF. Assurez la disponibilité des produits phares et la présence d''un vendeur supplémentaire.', to_char(coalesce((v_best_mom->>'ca')::numeric, 0), 'FM999G999G999G999')));
    end if;

    if v_best_prod is not null and v_part >= 40 then
      v_conseils := v_conseils || jsonb_build_object(
        'titre', 'Trop dépendant d''un seul produit',
        'detail', format('« %s » représente %s %% du chiffre d''affaires. Développez 2 produits complémentaires pour sécuriser les revenus.', v_best_prod->>'nom', to_char(v_part, 'FM990.0')));
    elsif v_best_prod is not null then
      v_conseils := v_conseils || jsonb_build_object(
        'titre', 'Un produit moteur à pousser',
        'detail', format('« %s » est votre meilleure vente (%s CDF). Mettez-le en avant à l''entrée et proposez-le systématiquement : c''est le levier le plus rapide.', v_best_prod->>'nom', to_char(coalesce((v_best_prod->>'ca')::numeric, 0), 'FM999G999G999G999')));
    end if;

    if v_panier > 0 then
      v_conseils := v_conseils || jsonb_build_object(
        'titre', format('Panier moyen : %s CDF', to_char(v_panier, 'FM999G999G999G999')),
        'detail', 'Proposez un article complémentaire à chaque vente (lot, accessoire, produit d''appel) : +10 % sur le panier suffit à augmenter le revenu sans nouveau client.');
    end if;

    if v_marge > 0 then
      v_conseils := v_conseils || jsonb_build_object(
        'titre', 'Marge estimée sur la période',
        'detail', format('Marge brute estimée : %s CDF (sur les produits dont le prix d''achat est renseigné). Renseignez les prix d''achat manquants pour un calcul complet.', to_char(v_marge, 'FM999G999G999G999')));
    end if;
  end if;

  -- Simulation : le produit n°1 progresse de 10 % (quantité et CA).
  if v_best_prod is not null then
    v_simul := jsonb_build_object(
      'produit', v_best_prod->>'nom',
      'ca_actuel', coalesce((v_best_prod->>'ca')::numeric, 0),
      'objectif_pct', 10,
      'ca_supplementaire', round(coalesce((v_best_prod->>'ca')::numeric, 0) * v_objectif, 2),
      'ca_projete', round(v_ca + coalesce((v_best_prod->>'ca')::numeric, 0) * v_objectif, 2),
      'message', format('Si « %s » progresse de 10 %%, la boutique gagne environ %s CDF de plus sur la période.',
                        v_best_prod->>'nom',
                        to_char(round(coalesce((v_best_prod->>'ca')::numeric, 0) * v_objectif, 2), 'FM999G999G999G999'))
    );
  end if;

  drop table if exists _analyse_ventes;

  return jsonb_build_object(
    'ok', true,
    'entreprise_id', p_entreprise_id,
    'entreprise_nom', v_nom,
    'debut', v_debut,
    'fin', v_fin,
    'devise', 'CDF',
    'totaux', jsonb_build_object(
      'ca', v_ca, 'ventes', v_ventes, 'articles', v_articles,
      'panier_moyen', v_panier, 'marge', v_marge),
    'top_produits', v_top,
    'jours', v_jours,
    'moments', v_moments,
    'meilleur_produit', v_best_prod,
    'meilleur_jour', v_best_jour,
    'meilleur_moment', v_best_mom,
    'conseils', v_conseils,
    'simulation', v_simul
  );
end;
$$;

comment on function public.rpc_rapport_entreprise_analyse(uuid, date, date) is
  '0175 — analyse commerciale d''une entreprise sur une période : meilleur produit, meilleur jour, meilleur moment, marge, conseils de croissance et simulation de revenus.';

revoke all on function public.rpc_rapport_entreprise_analyse(uuid, date, date) from public, anon;
grant execute on function public.rpc_rapport_entreprise_analyse(uuid, date, date) to authenticated;


-- ============================================================================
--  6. VÉRIFICATIONS (lecture seule)
-- ============================================================================

-- 6.a Les fonctions installées (attendu : 8 lignes).
select p.proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in (
     'press_collaborateur_creer', 'press_collaborateurs_lister',
     'press_collaborateur_supprimer', 'rpc_scanner_resoudre',
     'rpc_qr_tarif_etat', 'rpc_qr_tarif_definir', 'rpc_qr_code_emettre',
     'rpc_admin_tableau_bord', 'rpc_rapport_entreprise_analyse')
 order by 1;

-- 6.b Tarif QR (attendu : 150).
select value from public.app_settings where key = 'qr_codes';

-- 6.c Collaborateurs pressing dont le parent n'est pas un utilisateur
--     (attendu : 0 ligne après correction).
select count(*) as collaborateurs_orphelins
  from public.utilisateurs u
 where u.parent_id is not null
   and not exists (select 1 from public.utilisateurs p where p.id = u.parent_id);

-- ============================================================================
--  FIN — migration 0175.
-- ============================================================================
