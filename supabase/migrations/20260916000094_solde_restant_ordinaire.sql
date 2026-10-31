-- ============================================================================
--  biashara_yangu — PHASE 11 quater : `solde_restant` N'EST PAS GÉNÉRÉE
--  ---------------------------------------------------------------------------
--  POURQUOI CETTE MIGRATION
--  ------------------------
--  Votre base déclare `public.entreprises.solde_restant` comme **colonne
--  générée** (« Column solde_restant is a generated column », erreur 428C9).
--
--  Or TOUT le moteur d'abonnement écrit cette colonne lui-même, en calculant
--  la valeur :
--      montant_total_du, montant_deja_paye, solde_restant = total - payé
--  (module 1, module 3 `rpc_abonnement_enregistrer_paiement`, module 4…).
--
--  Conséquence : chaque encaissement d'abonnement échouerait avec la même
--  erreur 428C9 — pas seulement le rattrapage.
--
--  CETTE MIGRATION
--  ---------------
--  Supprime l'EXPRESSION de génération : la colonne redevient une colonne
--  ordinaire, **avec ses valeurs actuelles conservées**. Le moteur retrouve
--  le comportement prévu par toutes les migrations, et rien d'autre ne change.
--
--  Elle ne fait RIEN si la colonne est déjà ordinaire (idempotente).
--
--  ⚠️ Si vous préférez garder la colonne générée, NE LANCEZ PAS ce fichier :
--     il faudra alors réécrire le moteur d'abonnement (module 3 et suivants)
--     pour qu'il n'écrive plus jamais `solde_restant`. Dites-le-moi, je le
--     ferai — mais c'est un chantier plus lourd qu'une simple colonne.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

do $$
declare
  v_generee boolean := false;
  v_avant   numeric;
  v_apres   numeric;
begin
  select coalesce(bool_or(is_generated = 'ALWAYS'), false)
    into v_generee
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'entreprises'
     and column_name = 'solde_restant';

  if not v_generee then
    raise notice
      'solde_restant est déjà une colonne ordinaire : rien à faire.';
    return;
  end if;

  -- Témoin avant : on vérifie que les valeurs sont conservées.
  select coalesce(sum(coalesce(solde_restant, 0)), 0) into v_avant
    from public.entreprises;

  -- La colonne cesse d'être calculée ; ses valeurs restent en place.
  execute 'alter table public.entreprises alter column solde_restant drop expression';

  select coalesce(sum(coalesce(solde_restant, 0)), 0) into v_apres
    from public.entreprises;

  raise notice
    'solde_restant est redevenue une colonne ordinaire. '
    'Somme des soldes conservée : % → %.', v_avant, v_apres;

  if v_avant <> v_apres then
    raise warning
      'Les valeurs ont changé (% → %) : vérifiez les soldes avant de facturer.',
      v_avant, v_apres;
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- CONTRÔLE — les autres colonnes calculées sont-elles bien respectées ?
-- ----------------------------------------------------------------------------
-- Affiche toutes les colonnes générées de `entreprises` : le code applicatif
-- ne doit jamais les écrire.
select column_name                          as colonne,
       is_generated                         as generee,
       coalesce(generation_expression, '')   as expression
  from information_schema.columns
 where table_schema = 'public'
   and table_name = 'entreprises'
   and is_generated = 'ALWAYS'
 order by column_name;

-- ============================================================================
--  FIN — PHASE 11 quater
-- ============================================================================
