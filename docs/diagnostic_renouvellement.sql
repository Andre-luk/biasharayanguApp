-- ============================================================================
--  BIASHARA YANGU — DIAGNOSTIC « RENOUVELLEMENT » (chargement du dossier)
--  Fichier : docs/diagnostic_renouvellement.sql
--  ---------------------------------------------------------------------------
--  À exécuter dans l'éditeur SQL de Supabase — LECTURE SEULE.
--
--  Il appelle, une par une, les fonctions utilisées quand on ouvre le dossier
--  d'un client pour le renouveler, et dit LAQUELLE échoue et POURQUOI.
--  (Aucune de ces deux fonctions n'écrit quoi que ce soit.)
--
--  Remplace « urembo » par le début du nom du client si besoin.
-- ============================================================================

do $$
declare
  v_id   uuid;
  v_nom  text;
  v_txt  text;
  v_num  numeric;
  v_echec integer := 0;
begin
  select e.id, e.nom into v_id, v_nom
    from public.entreprises e
   where e.nom ilike '%urembo%'
   order by e.nom
   limit 1;

  if v_id is null then
    raise notice 'Aucune entreprise ne correspond à « urembo ». Modifiez le filtre.';
    return;
  end if;

  raise notice 'Dossier testé : % (%)', v_nom, v_id;

  -- 1️⃣ Nature du prochain cycle
  begin
    v_txt := public.rpc_abonnement_type_cycle(v_id);
    raise notice '✅ rpc_abonnement_type_cycle → %', v_txt;
  exception when others then
    v_echec := v_echec + 1;
    raise notice '❌ rpc_abonnement_type_cycle [%] %', sqlstate, sqlerrm;
  end;

  -- 2️⃣ Prix du prochain cycle
  begin
    v_num := public.rpc_abonnement_prix_du_cycle(v_id);
    raise notice '✅ rpc_abonnement_prix_du_cycle → %', v_num;
  exception when others then
    v_echec := v_echec + 1;
    raise notice '❌ rpc_abonnement_prix_du_cycle [%] %', sqlstate, sqlerrm;
  end;

  if v_echec = 0 then
    raise notice 'Bilan : les deux fonctions répondent. Le blocage vient d''ailleurs (voir la 3ᵉ requête).';
  else
    raise notice 'Bilan : % fonction(s) en échec — c''est la cause du message « Impossible de charger le dossier ».', v_echec;
  end if;
end $$;


-- ---------------------------------------------------------------------------
--  3. Les types réels : LA cause la plus fréquente
-- ---------------------------------------------------------------------------
select table_name, column_name, data_type
  from information_schema.columns
 where table_schema = 'public'
   and table_name in ('paiements_abonnements_laperle', 'agent_ia_achats',
                      'paiements_serdipay', 'entreprises')
   and column_name in ('entreprise_id', 'id')
 order by table_name, column_name;

-- Attendu après le correctif 45 : `uuid` partout.
-- Si `paiements_abonnements_laperle.entreprise_id` reste en `text`, c'est que
-- des valeurs n'étaient pas des uuid : le message d'avertissement du script
-- 0125 donne alors le nombre de lignes concernées.


-- ---------------------------------------------------------------------------
--  4. Le dossier du client, tel que le voit le moteur
-- ---------------------------------------------------------------------------
select e.nom,
       e.statut::text                 as statut,
       e.activation_etape,
       e.date_activation,
       e.date_expiration,
       e.montant_total_du,
       e.montant_deja_paye,
       e.solde_restant,
       e.prix_installation,
       e.prix_abonnement_mensuel,
       e.groupe_tarifaire_id,
       (select count(*)
          from public.paiements_abonnements_laperle p
         where p.entreprise_id::text = e.id::text) as versements_enregistres
  from public.entreprises e
 where e.nom ilike '%urembo%';
