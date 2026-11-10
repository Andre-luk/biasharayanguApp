-- ============================================================================
--  biashara_yangu — MIGRATION 0133 : LA VENTE À CRÉDIT N'EST PAS UN ENCAISSEMENT
--
--  LE PROBLÈME (argent réel)
--    `rpc_vente_valider` insère une ligne dans `public.caisse` POUR TOUTES les
--    ventes, y compris celles à crédit (`p_mode_paiement = 'credit'`). Et il
--    n'insère RIEN dans `public.dettes`.
--
--    Conséquence exacte, constatée sur les données :
--      1. la CAISSE est gonflée du montant de chaque vente impayée — le
--         commerçant croit avoir de l'argent qu'il n'a pas encore reçu ;
--      2. la DETTE du client n'existe pas côté serveur : l'écran « Dettes
--         clients » reste vide, donc « il n'y a pas d'option pour régulariser ».
--
--  CE QUE FAIT CETTE MIGRATION
--    1. Un trigger BEFORE INSERT sur `public.caisse` :
--         • vente à crédit → la ligne de caisse n'est PAS créée (aucun argent
--           n'entre) et une DETTE est enregistrée pour le client ;
--         • vente normale   → comportement inchangé (la ligne est créée).
--       Le trigger est idempotent : une seule dette par vente (`vente_uuid`).
--    2. RATTRAPAGE des ventes à crédit déjà encaissées à tort :
--         • la dette manquante est créée ;
--         • la ligne de caisse fantôme est supprimée — UNIQUEMENT si aucune
--           espèce n'a été reçue (`montant_recu` nul ou 0).
--    3. Contrôle final : combien de dettes ont été créées, combien de lignes
--       fantômes ont été retirées, et quel est le solde de caisse corrigé.
--
--  ⚠️ Après cette migration, encaisser une dette passe par
--     `rpc_dette_paiement` : c'est LUI qui fait entrer l'argent en caisse
--     (`paiements_dette` est compté par `rpc_caisse_resume`).
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  ⚠️ IDEMPOTENT : peut être relancé sans dupliquer de dette ni détruire de
--     vente normale.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- Contrôle préalable.
do $$
begin
  if to_regclass('public.caisse') is null then
    raise exception 'Table public.caisse introuvable : exécutez les modules 8 et 10.';
  end if;
  if to_regclass('public.dettes') is null then
    raise exception 'Table public.dettes introuvable : exécutez le module 10 (finance).';
  end if;
end $$;


-- ============================================================================
--  1. TRIGGER — UNE VENTE À CRÉDIT N'ENTRE PAS EN CAISSE
-- ============================================================================
--  ⚠️ Un trigger BEFORE INSERT qui renvoie NULL ANNULE l'insertion : c'est
--     volontaire et c'est tout l'objet de cette migration. `rpc_vente_valider`
--     n'utilise pas la ligne de caisse (pas de `returning`, aucune lecture
--     après l'insertion) : la vente reste donc valide, avec son numéro et ses
--     lignes, mais sans encaissement.

create or replace function public.caisse_vente_credit_sans_encaissement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_mode text := lower(btrim(coalesce(new.mode_paiement, 'especes')));
begin
  -- Seules les ventes à crédit sont concernées.
  if v_mode not in ('credit', 'dette') then
    return new;
  end if;

  -- Une vente à crédit DOIT avoir un client : sans client, il n'y a personne
  -- à qui réclamer l'argent. On laisse alors la ligne de caisse telle quelle
  -- (comportement historique) plutôt que de perdre la vente.
  if new.client_id is null then
    return new;
  end if;

  -- La dette est créée UNE SEULE FOIS par vente (clé : `vente_uuid`).
  if new.vente_uuid is not null and coalesce(new.montant_total, 0) > 0 then
    if not exists (
      select 1
        from public.dettes d
       where d.vente_uuid = new.vente_uuid
         and d.owner_id = new.owner_id
    ) then
      insert into public.dettes (
        owner_id, client_id, vente_id, vente_uuid, montant_total,
        montant_paye, statut, date_creation, date_echeance, is_synced
      ) values (
        new.owner_id, new.client_id, null, new.vente_uuid, new.montant_total,
        0, 'non_paye', coalesce(new.date, now()), null, 1
      );

      insert into public.journal_audit (
        id, entreprise_id, action, utilisateur_id, details, created_at
      ) values (
        gen_random_uuid(), null, 'DETTE_CREEE_VENTE_CREDIT', new.seller_id,
        jsonb_build_object(
          'vente_uuid',    new.vente_uuid,
          'numero_vente',  new.numero_vente,
          'client_id',     new.client_id,
          'montant_total', new.montant_total,
          'boutique',      new.owner_id,
          'origine',       'vente_a_credit'
        ),
        now()
      );
    end if;
  end if;

  -- ⛔ Rien n'est encaissé : la ligne de caisse n'existe pas.
  return null;
end;
$$;

comment on function public.caisse_vente_credit_sans_encaissement() is
  'Empêche une vente à crédit d''entrer en caisse et crée la dette du client (une seule fois par vente).';

drop trigger if exists trg_caisse_vente_credit on public.caisse;
create trigger trg_caisse_vente_credit
  before insert on public.caisse
  for each row execute function public.caisse_vente_credit_sans_encaissement();


-- ============================================================================
--  2. RATTRAPAGE — DETTES MANQUANTES, PUIS LIGNES DE CAISSE FANTÔMES
-- ============================================================================

-- 2.a Créer la dette des ventes à crédit déjà enregistrées sans dette -------
do $$
declare
  v_creees integer := 0;
begin
  insert into public.dettes (
    owner_id, client_id, vente_id, vente_uuid, montant_total,
    montant_paye, statut, date_creation, date_echeance, is_synced
  )
  select c.owner_id, c.client_id, null, c.vente_uuid, c.montant_total,
         0, 'non_paye', coalesce(c.date, now()), null, 1
    from public.caisse c
   where lower(btrim(coalesce(c.mode_paiement, 'especes'))) in ('credit', 'dette')
     and coalesce(c.montant_recu, 0) <= 0
     and c.client_id is not null
     and c.vente_uuid is not null
     and coalesce(c.montant_total, 0) > 0
     and not exists (
       select 1 from public.dettes d where d.vente_uuid = c.vente_uuid
     );

  get diagnostics v_creees = row_count;
  raise notice 'Rattrapage : % dette(s) reconstituée(s) pour des ventes à crédit.', v_creees;
end $$;

-- 2.b Retirer les lignes de caisse fantômes de ces ventes -------------------
--     ⚠️ Seulement celles où AUCUNE espèce n'a été reçue : une vente à crédit
--        partiellement payée en espèces reste dans la caisse pour la part reçue.
do $$
declare
  v_supprimees integer := 0;
begin
  delete from public.caisse c
   where lower(btrim(coalesce(c.mode_paiement, 'especes'))) in ('credit', 'dette')
     and coalesce(c.montant_recu, 0) <= 0;

  get diagnostics v_supprimees = row_count;
  raise notice 'Rattrapage : % ligne(s) de caisse fantôme(s) retirée(s).', v_supprimees;
end $$;


-- ============================================================================
--  3. DIAGNOSTIC (lecture seule)
-- ============================================================================

select 'MIGRATION 0133 PRÊTE' as controle,
       (select count(*) from public.dettes) as dettes_totales,
       (select count(*) from public.dettes where statut <> 'paye') as dettes_a_encaisser,
       (select coalesce(sum(montant_total - coalesce(montant_paye, 0)), 0)
          from public.dettes where statut <> 'paye') as restant_du;

select 'LIGNES DE CAISSE' as controle,
       (select count(*) from public.caisse
         where lower(btrim(coalesce(mode_paiement, 'especes'))) in ('credit', 'dette'))
         as lignes_credit_restantes,
       (select count(*) from public.caisse) as lignes_caisse,
       (select coalesce(sum(montant_total), 0) from public.caisse) as total_caisse;

select 'SA VÉRIFICATION' as controle,
       exists (select 1 from pg_trigger where tgname = 'trg_caisse_vente_credit') as trigger_ok,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.proname = 'caisse_vente_credit_sans_encaissement'
                  and n.nspname = 'public') as fonction_ok;
