-- ============================================================================
--  biashara_yangu — MIGRATION 0137 : LA CAISSE DU PRESSING (JOURNÉE)
--
--  POURQUOI
--    Un pressing encaisse de l'argent tous les jours : acompte au dépôt,
--    solde à la remise. Jusqu'ici ces montants n'étaient visibles que sous
--    forme de total (« encaissé ») sur le tableau de bord : impossible de
--    savoir COMBIEN est entré en espèces, combien en Mobile Money, ni de
--    justifier la caisse en fin de journée.
--
--  CE QUE FAIT CETTE MIGRATION
--    `pressing_caisse_jour(p_date)` renvoie, pour une journée :
--      • l'encaissement réel (paiements NON annulés) et son détail PAR MODE ;
--      • les annulations du jour (montant + nombre) — un encaissement annulé
--        n'est jamais effacé ;
--      • l'activité : nombre de dépôts et montant facturé du jour, nombre de
--        remises (retraits) ;
--      • la liste détaillée des encaissements (n°, client, montant, mode,
--        heure, agent, état) — c'est la source du rapport imprimable ;
--      • le reste dû GLOBAL du pressing (toutes périodes).
--
--  ⚠️ SOURCE UNIQUE DE L'ARGENT : `pressing_paiements`. La colonne
--     `montant_encaisse` de `pressing_retraits` n'est qu'une trace de la
--     remise : la compter aussi doublerait la caisse.
--
--  Codes : SESSION_ABSENTE | ACCES_REFUSE | DROIT_REFUSE | DATE_INVALIDE
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
begin
  if to_regclass('public.pressing_paiements') is null then
    raise exception 'Module 35 absent : exécutez d''abord les migrations 0120 → 0123.';
  end if;
end $$;


create or replace function public.pressing_caisse_jour(
  p_date date default current_date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent     uuid := public.pressing_entreprise();
  v_jour    date := coalesce(p_date, current_date);
  v_d0      timestamptz;
  v_d1      timestamptz;
  v_encaisse numeric := 0;
  v_nb      integer := 0;
  v_annule  numeric := 0;
  v_nb_ann  integer := 0;
  v_par_mode jsonb := '{}'::jsonb;
  v_lignes  jsonb := '[]'::jsonb;
  v_depots  integer := 0;
  v_facture numeric := 0;
  v_remises integer := 0;
  v_du      numeric := 0;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous pour consulter la caisse du pressing.';
  end if;

  if v_ent is null then
    raise exception 'ACCES_REFUSE|Aucune entreprise rattachée à ce compte.';
  end if;

  if not (public.peut('caisse', 'voir')
          or public.peut('pressing_depots', 'voir')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas de consulter la caisse du pressing.';
  end if;

  if v_jour > current_date + 1 then
    raise exception 'DATE_INVALIDE|La date demandée ne peut pas être dans un futur lointain.';
  end if;

  v_d0 := v_jour::timestamptz;
  v_d1 := (v_jour + 1)::timestamptz;

  -- 1. Encaissements réels du jour -----------------------------------------
  select coalesce(sum(p.montant) filter (where p.annule_le is null), 0),
         count(*) filter (where p.annule_le is null),
         coalesce(sum(p.montant) filter (where p.annule_le is not null), 0),
         count(*) filter (where p.annule_le is not null)
    into v_encaisse, v_nb, v_annule, v_nb_ann
    from public.pressing_paiements p
   where p.entreprise_id = v_ent
     and p.encaisse_le >= v_d0 and p.encaisse_le < v_d1;

  -- 2. Détail par mode de paiement (encaissements NON annulés) -------------
  select coalesce(jsonb_object_agg(mode, jsonb_build_object(
           'montant', montant,
           'nb',      nb
         )), '{}'::jsonb)
    into v_par_mode
    from (
      select lower(btrim(coalesce(p.mode, 'especes'))) as mode,
             round(sum(p.montant), 2) as montant,
             count(*) as nb
        from public.pressing_paiements p
       where p.entreprise_id = v_ent
         and p.encaisse_le >= v_d0 and p.encaisse_le < v_d1
         and p.annule_le is null
       group by 1
    ) g;

  -- 3. Liste détaillée (rapport imprimable) --------------------------------
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',        p.id,
           'numero',    c.numero,
           'client',    coalesce(c.client_nom, ''),
           'montant',   p.montant,
           'mode',      lower(btrim(coalesce(p.mode, 'especes'))),
           'reference', p.reference,
           'encaisse_le', p.encaisse_le,
           'annule',    p.annule_le is not null,
           'motif_annulation', p.motif_annulation,
           'agent',     coalesce(nullif(btrim(
                          coalesce(u.prenom, '') || ' ' || coalesce(u.nom, '')
                        ), ''), '')
         ) order by p.encaisse_le desc), '[]'::jsonb)
    into v_lignes
    from public.pressing_paiements p
    join public.pressing_commandes c on c.id = p.commande_id
    left join public.utilisateurs u on u.id = p.agent_id
   where p.entreprise_id = v_ent
     and p.encaisse_le >= v_d0 and p.encaisse_le < v_d1;

  -- 4. Activité du jour -----------------------------------------------------
  select count(*), coalesce(sum(c.total), 0)
    into v_depots, v_facture
    from public.pressing_commandes c
   where c.entreprise_id = v_ent
     and c.date_depot >= v_d0 and c.date_depot < v_d1
     and c.annule_le is null;

  select count(*)
    into v_remises
    from public.pressing_retraits r
   where r.entreprise_id = v_ent
     and r.created_at >= v_d0 and r.created_at < v_d1;

  -- 5. Reste dû GLOBAL (toutes périodes, commandes non annulées) -----------
  select coalesce(sum(greatest(c.total - coalesce(c.montant_paye, 0), 0)), 0)
    into v_du
    from public.pressing_commandes c
   where c.entreprise_id = v_ent
     and c.annule_le is null;

  return jsonb_build_object(
    'date',          v_jour,
    'encaisse',      round(v_encaisse, 2),
    'nb_paiements',  v_nb,
    'annule',        round(v_annule, 2),
    'nb_annules',    v_nb_ann,
    'par_mode',      v_par_mode,
    'paiements',     v_lignes,
    'depots',        v_depots,
    'montant_facture', round(v_facture, 2),
    'remises',       v_remises,
    'reste_du',      round(v_du, 2)
  );
end;
$$;

comment on function public.pressing_caisse_jour(date) is
  'Module 35 — caisse d''une journée de pressing : encaissements par mode, annulations, dépôts, remises, reste dû global et détail imprimable.';

revoke all on function public.pressing_caisse_jour(date) from public, anon;
grant execute on function public.pressing_caisse_jour(date) to authenticated;


-- ============================================================================
--  CONTRÔLE
-- ============================================================================

select 'MIGRATION 0137 PRÊTE' as controle,
       exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                where p.proname = 'pressing_caisse_jour' and n.nspname = 'public')
         as fonction_ok,
       (select count(*) from public.pressing_paiements) as paiements_enregistres;
