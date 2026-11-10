-- ============================================================================
--  biashara_yangu — MIGRATION 0135 : ÉCHÉANCE D'UREMBO MARKET AU 09/12/2026
--
--  DEMANDE
--    « Urembo Market, son abonnement doit finir le 09/12/2026. »
--
--  ÉTAT CONSTATÉ (avant ce script)
--    statut          : ACTIF
--    date_expiration : 2026-12-10 15:44:09+00  →  10/12/2026
--    (le moteur ajoute 30 JOURS au cycle ; il ne compte pas des mois
--     calendaires : 10/11 + 30 j = 10/12.)
--
--  CE QUE FAIT CE SCRIPT
--    1. Retrouve l'entreprise « Urembo Market » (jamais au hasard : si le nom
--       est ambigu, il s'arrête et liste les candidats).
--    2. Pose l'échéance au **09/12/2026 en fin de journée** (23:59:59 heure de
--       Lubumbashi, soit 21:59:59 UTC) : le client garde toute la journée du 9.
--    3. Écrit une ligne de journal d'audit (traçabilité de la correction).
--    4. N'ÉCRIT RIEN d'autre : ni montant, ni solde, ni statut, ni paiement.
--       Aucun encaissement n'est inventé — c'est un simple ajustement de date.
--
--  ⚠️ IDEMPOTENT : relancé, il retrouve la même valeur et ne modifie rien.
--
--  OÙ L'EXÉCUTER
--    Supabase Dashboard → SQL Editor → New query → coller → Run
--    (le tableau de contrôle est la DERNIÈRE instruction : c'est le seul
--     résultat que le SQL Editor affiche.)
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


do $$
declare
  -- ⬇⬇⬇  SEUL RÉGLAGE À CHANGER  ⬇⬇⬇
  --  Fin de journée du 09/12/2026 à Lubumbashi (UTC+2).
  --  Pour garder l'heure exacte de l'ancienne échéance (15:44), utiliser
  --  plutôt : timestamptz '2026-12-09 15:44:09+00'
  v_cible     timestamptz := timestamptz '2026-12-09 23:59:59+02';
  --  true  = applique la correction
  --  false = inspection seule (aucune écriture)
  v_appliquer boolean     := true;
  -- ⬆⬆⬆ --------------------------- ⬆⬆⬆

  v_id        uuid;
  v_nb        integer;
  v_candidats text;
  v_e         public.entreprises;
  v_avant     timestamptz;
begin
  -- ========================================================================
  --  1. RETROUVER L'ENTREPRISE (nom exact d'abord, sinon un seul « urembo »)
  -- ========================================================================
  select count(*) into v_nb
    from public.entreprises e
   where lower(btrim(e.nom)) = 'urembo market';

  if v_nb >= 1 then
    select e.id into v_id
      from public.entreprises e
     where lower(btrim(e.nom)) = 'urembo market'
     order by e.id
     limit 1;
  else
    select count(*), string_agg(e.nom, ' | ' order by e.nom)
      into v_nb, v_candidats
      from public.entreprises e
     where e.nom ilike '%urembo%';

    if v_nb = 0 then
      raise exception
        'ENTREPRISE_INTROUVABLE|Aucune entreprise ne contient « urembo » : vérifiez le nom exact dans l''admin avant de relancer.';
    end if;

    if v_nb > 1 then
      raise exception
        'PLUSIEURS_ENTREPRISES|% entreprises contiennent « urembo » (%) : renommez la bonne ou modifiez le filtre du script, aucune date n''a été touchée.',
        v_nb, coalesce(v_candidats, '?');
    end if;

    select e.id into v_id
      from public.entreprises e
     where e.nom ilike '%urembo%'
     limit 1;
  end if;

  -- ========================================================================
  --  2. LIRE LA FICHE (verrou : personne ne paie pendant la correction)
  -- ========================================================================
  select * into v_e
    from public.entreprises e
   where e.id = v_id
   for update;

  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE|Identifiant % absent de public.entreprises.', v_id;
  end if;

  v_avant := v_e.date_expiration;

  raise notice 'Urembo Market — avant : statut=%, expiration=%, solde=%',
    v_e.statut::text,
    coalesce(to_char(v_e.date_expiration, 'DD/MM/YYYY HH24:MI'), '—'),
    coalesce(v_e.solde_restant, 0);

  -- ========================================================================
  --  3. APPLIQUER L'ÉCHÉANCE DEMANDÉE
  -- ========================================================================
  if not v_appliquer then
    raise notice 'Mode inspection : la date serait portée au % (aucune écriture).',
      to_char(v_cible, 'DD/MM/YYYY HH24:MI');
  elsif v_avant is not distinct from v_cible then
    raise notice 'Déjà au % : aucune modification.', to_char(v_cible, 'DD/MM/YYYY HH24:MI');
  else
    update public.entreprises
       set date_expiration = v_cible,
           updated_at      = now()
     where id = v_id
     returning * into v_e;

    insert into public.journal_audit (
      id, entreprise_id, action, utilisateur_id, details, created_at
    ) values (
      gen_random_uuid(),
      v_id,
      'AJUSTEMENT_ECHEANCE',
      auth.uid(),
      jsonb_build_object(
        'motif',           'échéance portée au 09/12/2026 (demande du client)',
        'echeance_avant',  v_avant,
        'echeance_apres',  v_e.date_expiration,
        'statut',          v_e.statut::text,
        'montant_deja_paye', v_e.montant_deja_paye,
        'solde_restant',   v_e.solde_restant,
        'migration',       '0135'
      ),
      now()
    );

    raise notice 'Urembo Market — après : expiration=% (correction enregistrée au journal d''audit)',
      to_char(v_e.date_expiration, 'DD/MM/YYYY HH24:MI');
  end if;

  -- ========================================================================
  --  4. CONTRÔLES DE COHÉRENCE (avertissements seulement, aucune écriture)
  -- ========================================================================
  if v_cible <= now() then
    raise warning
      'La nouvelle échéance (%) est déjà passée : le compte sera considéré comme échu.',
      to_char(v_cible, 'DD/MM/YYYY HH24:MI');
  end if;

  if v_e.statut::text not in ('ACTIF', 'ESSAI_7J') then
    raise warning
      'Le statut est « % » alors que la fiche porte une échéance future : ce script ne change PAS le statut. Si le compte doit réouvrir, passez par la réactivation / la validation finance.',
      v_e.statut::text;
  end if;

  if coalesce(v_e.solde_restant, 0) > 0 then
    raise warning
      'Un solde de % est encore dû sur le cycle courant : la date posée ici ne règle PAS cet impayé.',
      v_e.solde_restant;
  end if;
end $$;


-- ============================================================================
--  CONTRÔLE (dernière instruction = le seul résultat affiché)
-- ============================================================================
select e.nom,
       e.statut::text                                as statut,
       e.montant_total_du                            as du,
       e.montant_deja_paye                           as paye,
       e.solde_restant                               as solde,
       to_char(e.date_expiration, 'DD/MM/YYYY HH24:MI') as fin_abonnement,
       greatest(0, ceil(extract(epoch from (e.date_expiration - now())) / 86400))::int
                                                     as jours_restants,
       (select to_char(max(j.created_at), 'DD/MM/YYYY HH24:MI')
          from public.journal_audit j
         where j.entreprise_id::text = e.id::text
           and j.action = 'AJUSTEMENT_ECHEANCE')     as correction_tracee_le
  from public.entreprises e
 where lower(btrim(e.nom)) = 'urembo market'
    or (not exists (select 1 from public.entreprises x
                     where lower(btrim(x.nom)) = 'urembo market')
        and e.nom ilike '%urembo%');
