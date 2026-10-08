-- ============================================================================
--  BIASHARA YANGU — RÉPARATION DE L'ABONNEMENT D'UN COMPTE
--  Fichier : tools/reparer_abonnement_compte.sql
-- ============================================================================
--
--  À QUOI ÇA SERT
--  --------------
--  Le bug du complément de paiement (correctif 53) a écrasé l'acompte de
--  certains abonnements : `montant_deja_paye` est reparti d'un montant trop bas
--  et le compte reste bloqué « en attente de complément » alors que le client a
--  TOUT payé.
--
--  Ce script :
--     1. retrouve l'entreprise du compte indiqué ;
--     2. AFFICHE son état et l'historique de ses versements ;
--     3. reconstitue le cumulé réellement versé à partir de l'historique ;
--     4. remet `montant_deja_paye` au bon niveau ;
--     5. CONCLUT l'abonnement (statut ACTIF + période) si tout est réglé.
--
--  Il est IDEMPOTENT : le relancer ne cumule rien (le montant est recalculé, il
--  n'est jamais ajouté). Il n'ABAISSE jamais un montant déjà enregistré.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--
--  COMMENT CHANGER DE COMPTE
--    Modifiez la seule ligne `v_email` ci-dessous.
--
--  ⚠️ À exécuter APRÈS le correctif 53 (20260916000053…), sinon le bug
--     refera la même chose au prochain paiement.
-- ============================================================================

do $$
declare
  -- ⬇⬇⬇  SEUL RÉGLAGE À CHANGER  ⬇⬇⬇
  v_email      text    := 'biasharagroup@gmail.com';
  -- true  = répare réellement
  -- false = inspection seule (affiche ce qui serait fait, n'écrit rien)
  v_appliquer  boolean := true;
  -- ⬆⬆⬆ --------------------------- ⬆⬆⬆

  v_user       public.utilisateurs;
  v_entreprise uuid;
  v_e          public.entreprises;
  v_cumul_hist numeric := 0;   -- cumulé le plus élevé qu'impliquent les versements
  v_anomalie   numeric := 0;   -- versement dont le cumulé a CHUTÉ (signature du bug)
  v_anomalie_le timestamptz;
  v_cible      numeric := 0;   -- montant_deja_paye à rétablir
  v_avant_paye numeric := 0;
  v_avant_solde numeric := 0;
  v_nb_vers    integer := 0;
  v_duree      integer := 30;
  v_statut_avant text;
  v_activer    boolean := false;
begin
  -- ========================================================================
  -- 1. RETROUVER LE COMPTE
  -- ========================================================================
  select * into v_user
    from public.utilisateurs u
   where lower(btrim(u.email)) = lower(btrim(v_email))
   limit 1;

  if v_user.id is null then
    raise exception 'COMPTE_INTROUVABLE|Aucun utilisateur avec l''adresse « % ».', v_email;
  end if;

  -- L'entreprise du compte, ou celle de son « patron » (mêmes règles que
  -- public.mon_entreprise_id(), qui gère les comptes rattachés).
  select coalesce(u.entreprise_id, p.entreprise_id)
    into v_entreprise
    from public.utilisateurs u
    left join public.utilisateurs p on p.id = u.parent_id
   where u.id = v_user.id;

  if v_entreprise is null then
    raise exception 'ENTREPRISE_INTROUVABLE|Le compte « % » n''est rattaché à aucune entreprise.', v_email;
  end if;

  select * into v_e from public.entreprises where id = v_entreprise;
  if v_e.id is null then
    raise exception 'ENTREPRISE_INTROUVABLE|L''entreprise rattachée n''existe plus.';
  end if;

  v_avant_paye  := coalesce(v_e.montant_deja_paye, 0);
  v_avant_solde := coalesce(v_e.solde_restant, 0);
  v_statut_avant := v_e.statut::text;

  raise notice '── COMPTE ────────────────────────────────────────────';
  raise notice '   e-mail        : %', v_user.email;
  raise notice '   entreprise    : % (%)', v_e.nom, v_e.id;
  raise notice '   montant dû    : %', coalesce(v_e.montant_total_du, 0);
  raise notice '   deja paye     : %', v_avant_paye;
  raise notice '   solde restant : %', v_avant_solde;
  raise notice '   statut        : %', v_statut_avant;
  raise notice '   etape         : %', coalesce(v_e.activation_etape, '-');

  -- ========================================================================
  -- 2. RECONSTITUER LE CUMULÉ RÉEL À PARTIR DE L'HISTORIQUE
  -- ========================================================================
  --  `total_apres` est le cumulé APRÈS le versement : dans un cycle correct il
  --  ne peut que CROÎTRE. Le bug du complément l'a fait CHUTER (l'acompte est
  --  reparti de zéro). On reconstitue donc, pour chaque versement, le cumulé
  --  qu'il AURAIT dû produire — cumulé précédent + versement — et on retient le
  --  plus élevé. C'est la preuve chiffrée du montant réellement payé.

  select coalesce(count(*), 0) into v_nb_vers
    from public.paiements_abonnements_laperle h
   where h.entreprise_id = v_entreprise;

  select coalesce(max(t.precedent + t.montant), 0)
    into v_cumul_hist
    from (
      select h.montant,
             lag(h.total_apres) over (order by h.created_at) as precedent
        from public.paiements_abonnements_laperle h
       where h.entreprise_id = v_entreprise
    ) t
   where t.precedent is not null;

  select coalesce(max(t.total_apres - t.precedent), 0)
    into v_anomalie
    from (
      select h.total_apres,
             lag(h.total_apres) over (order by h.created_at) as precedent
        from public.paiements_abonnements_laperle h
       where h.entreprise_id = v_entreprise
    ) t
   where t.precedent is not null
     and t.total_apres < t.precedent;

  select max(h.created_at) into v_anomalie_le
    from (
      select h.created_at, h.total_apres,
             lag(h.total_apres) over (order by h.created_at) as precedent
        from public.paiements_abonnements_laperle h
       where h.entreprise_id = v_entreprise
    ) h
   where h.precedent is not null
     and h.total_apres < h.precedent;

  raise notice '── HISTORIQUE ─────────────────────────────────────────';
  raise notice '   versements enregistres : %', v_nb_vers;
  raise notice '   cumule implique par l''historique : %', v_cumul_hist;
  if v_anomalie > 0 then
    raise notice '   ⚠️ BUG DETECTE le % : le cumule a chute de %',
                 to_char(v_anomalie_le, 'DD/MM/YYYY HH24:MI'), v_anomalie;
  else
    raise notice '   aucun cumule en baisse : pas de trace du bug sur ce dossier';
  end if;

  -- ========================================================================
  -- 3. CALCULER LE MONTANT À RÉTABLIR
  -- ========================================================================
  --  On ne retient que ce qui AUGMENTE, et jamais au-delà du montant dû.
  if coalesce(v_e.montant_total_du, 0) > 0 then
    v_cible := least(v_cumul_hist, v_e.montant_total_du);
  else
    v_cible := v_cumul_hist;
  end if;

  if v_cible <= v_avant_paye then
    raise notice '── AUCUNE CORRECTION NECESSAIRE ──────────────────────';
    raise notice '   le montant enregistre (%) est deja au niveau du cumule historique (%).',
                 v_avant_paye, v_cible;
    -- Rien à réparer : le dossier n'a pas subi le bug. On continue quand même
    -- vers la conclusion si l'abonnement est soldé mais non actif.
  else
    raise notice '── CORRECTION ────────────────────────────────────────';
    raise notice '   deja paye : %  ->  %', v_avant_paye, v_cible;
  end if;

  -- ========================================================================
  -- 4. APPLIQUER LA CORRECTION
  -- ========================================================================
  if v_appliquer and v_cible > v_avant_paye then
    -- `solde_restant` est une colonne GÉNÉRÉE (total − payé) : elle suit seule.
    update public.entreprises
       set montant_deja_paye = v_cible,
           updated_at        = now()
     where id = v_entreprise
    returning * into v_e;

    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details, created_at)
    values (
      v_entreprise, 'ABONNEMENT_PAIEMENT_REPARE', null,
      jsonb_build_object(
        'motif', 'correctif 53 — reconstitution du cumule apres effacement de l acompte',
        'compte', v_email,
        'montant_deja_paye_avant', v_avant_paye,
        'montant_deja_paye_apres', v_cible,
        'cumule_historique', v_cumul_hist,
        'anomalie_detectee', v_anomalie > 0,
        'anomalie_le', v_anomalie_le
      ),
      now()
    );
  elsif not v_appliquer and v_cible > v_avant_paye then
    raise notice '   (inspection seule : v_appliquer = false -> aucune ecriture)';
  end if;

  -- ========================================================================
  -- 5. CONCLURE L'ABONNEMENT SI LE COMPTE EST INTÉGRALEMENT RÉGLÉ
  -- ========================================================================
  -- Le montant local ne doit JAMAIS descendre sous ce qui est deja enregistre,
  -- sinon le solde calcule ci-dessous serait faussement optimiste.
  v_e.montant_deja_paye := greatest(v_avant_paye, v_cible);
  v_e.solde_restant := greatest(coalesce(v_e.montant_total_du, 0) - v_e.montant_deja_paye, 0);

  if coalesce(v_e.solde_restant, 0) <= 0
     and coalesce(v_e.montant_total_du, 0) > 0
     and v_statut_avant <> 'SUSPENDU'          -- une suspension reste humaine
     and v_statut_avant <> 'ACTIF'             -- deja actif : rien a faire
  then
    v_activer := true;

    select coalesce(nullif(g.duree_abonnement_jours, 0), 30)
      into v_duree
      from public.groupes_tarifaires g
     where g.id = v_e.groupe_tarifaire_id;
    v_duree := coalesce(v_duree, 30);

    if v_appliquer then
      update public.entreprises
         set statut           = 'ACTIF'::public.statut_abonnement_enum,
             activation_etape = case
                                  when activation_etape in ('verifie', 'restreint')
                                    then 'actif'
                                  else activation_etape
                                end,
             date_activation  = coalesce(date_activation, now()),
             -- On prolonge à partir de la date future s'il y en a une, sinon
             -- de maintenant : le client ne perd aucun jour deja paye.
             date_expiration  = greatest(
                                  coalesce(date_expiration, now()), now()
                                ) + make_interval(days => v_duree),
             valide_le_finance = coalesce(valide_le_finance, now()),
             updated_at       = now()
       where id = v_entreprise
      returning * into v_e;

      insert into public.journal_audit (entreprise_id, action, utilisateur_id, details, created_at)
      values (
        v_entreprise, 'ABONNEMENT_CONCLU_REPARATION', null,
        jsonb_build_object(
          'compte', v_email,
          'solde_restant', 0,
          'statut', 'ACTIF',
          'date_expiration', v_e.date_expiration,
          'jours', v_duree,
          'motif', 'correctif 53 — abonnement integrement regle'
        ),
        now()
      );

      raise notice '── ABONNEMENT CONCLU ─────────────────────────────────';
      raise notice '   statut : ACTIF | expiration : % | +% jours',
                   to_char(v_e.date_expiration, 'DD/MM/YYYY'), v_duree;
    else
      raise notice '   (inspection seule : conclusion NON appliquee)';
    end if;
  else
    raise notice '── CONCLUSIONS ───────────────────────────────────────';
    raise notice '   solde restant : % | statut : %',
                 coalesce(v_e.solde_restant, 0), v_e.statut::text;
    if v_statut_avant = 'SUSPENDU' then
      raise notice '   ⚠️ compte SUSPENDU : la reactivation reste une decision humaine.';
    elsif coalesce(v_e.solde_restant, 0) > 0 then
      raise notice '   il reste un solde a encaisser : abonnement non conclu.';
    end if;
  end if;
end $$;


-- ============================================================================
--  CONTRÔLE FINAL — à lancer juste après (ne modifie rien)
-- ============================================================================
--  C'est ce tableau qui confirme le résultat.

select u.email                        as compte,
       e.nom                          as entreprise,
       e.montant_total_du             as montant_du,
       e.montant_deja_paye            as deja_paye,
       e.solde_restant                as solde_restant,
       e.statut::text                 as statut,
       e.activation_etape             as etape,
       e.date_activation              as activation,
       e.date_expiration              as expiration,
       (e.date_expiration - now())    as jours_restants
  from public.utilisateurs u
  left join public.utilisateurs p on p.id = u.parent_id
  join public.entreprises e on e.id = coalesce(u.entreprise_id, p.entreprise_id)
 where lower(btrim(u.email)) = lower(btrim('biasharagroup@gmail.com'));


-- ============================================================================
--  HISTORIQUE DES VERSEMENTS — pour comprendre ce qui s'est passé
-- ============================================================================

select h.created_at                  as "date",
       h.montant                     as verse,
       h.type_paiement               as "type",
       h.total_apres                 as cumule_apres,
       lag(h.total_apres) over (order by h.created_at) as cumule_precedent,
       case when h.total_apres < lag(h.total_apres) over (order by h.created_at)
            then '⛔ cumule en baisse = bug du complement'
            else '' end              as observation
  from public.paiements_abonnements_laperle h
  join public.entreprises e on e.id = h.entreprise_id
  join public.utilisateurs u on u.email = 'biasharagroup@gmail.com'
  left join public.utilisateurs p on p.id = u.parent_id
 where e.id = coalesce(u.entreprise_id, p.entreprise_id)
 order by h.created_at desc;

-- ============================================================================
--  FIN
-- ============================================================================
