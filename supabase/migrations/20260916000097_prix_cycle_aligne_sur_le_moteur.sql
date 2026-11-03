-- ============================================================================
--  biashara_yangu — CORRECTIF 97 : LE PRIX DU CYCLE SUIT LA RÈGLE DU MOTEUR
--  ---------------------------------------------------------------------------
--  CE QUE LE PATRON A VU (01/11/2026)
--    « Les Trois Frères : le nouveau cycle à encaisser est 15 000 CDF, mais
--      quand je mets 15 000, toujours le même message d'avant. »
--
--  LA CAUSE — deux règles qui ne disent pas la même chose
--    Le MOTEUR (`rpc_abonnement_enregistrer_paiement`) considère qu'un
--    abonnement est au PREMIER cycle seulement si `date_activation IS NULL` :
--        v_premier_cycle := (v_entreprise.date_activation is null);
--    Sinon il facture le MENSUEL (5 000 pour Les Trois Frères).
--
--    Mais `rpc_abonnement_prix_du_cycle` (migration 0090) testait « aucun
--    paiement enregistré » pour réclamer l'INSTALLATION. Or depuis 0091/0093
--    un compte est activé automatiquement en essai 7 jours : `date_activation`
--    est renseignée et il n'y a encore AUCUN paiement.
--    ⇒ l'écran annonçait 15 000 (installation), le moteur attendait 5 000
--      (mensuel), et le paiement de 15 000 était refusé.
--
--  LA CORRECTION — une seule règle, la même partout :
--      date_activation NULL  → PREMIER cycle payant → installation
--      date_activation remplie → RENOUVELLEMENT     → prix mensuel
--
--  ⚠️ `rpc_abonnement_enregistrer_paiement` n'est PAS touchée.
--  ⚠️ IDEMPOTENT.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

-- ============================================================================
--  1. PRIX DU PROCHAIN CYCLE — même règle que le moteur
-- ============================================================================
create or replace function public.rpc_abonnement_prix_du_cycle(
  p_entreprise uuid
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_e      public.entreprises%rowtype;
  v_grille numeric := 0;
  v_prix   numeric := 0;
begin
  select * into v_e from public.entreprises where id = p_entreprise;
  if not found then
    return 0;
  end if;

  -- 1️⃣ PREMIER CYCLE PAYANT : l'entreprise n'a JAMAIS été activée.
  --    (Même test que le moteur : `date_activation IS NULL`.)
  if v_e.date_activation is null
     and coalesce(v_e.prix_installation, 0) > 0 then
    return v_e.prix_installation;
  end if;

  select coalesce(g.montant_abonnement, 0)
    into v_grille
    from public.groupes_tarifaires g
   where g.id = v_e.groupe_tarifaire_id;

  -- 2️⃣ RENOUVELLEMENT : le MENSUEL, jamais l'installation.
  v_prix := coalesce(
    nullif(v_e.prix_abonnement_mensuel, 0),
    nullif(v_grille, 0),
    case
      when coalesce(v_e.montant_total_du, 0) > 0
       and coalesce(v_e.montant_total_du, 0) <> coalesce(v_e.prix_installation, -1)
        then v_e.montant_total_du
      else 0
    end,
    -- Dernier repli : l'installation TIENT LIEU de premier mois.
    nullif(v_e.prix_installation, 0),
    0
  );

  -- Un compte déjà activé ne doit jamais se voir réclamer l'installation.
  if v_e.date_activation is not null
     and coalesce(v_e.prix_installation, 0) > 0
     and v_prix = coalesce(v_e.prix_installation, 0) then
    select coalesce(g.montant_abonnement, 0)
      into v_prix
      from public.groupes_tarifaires g
     where g.id = v_e.groupe_tarifaire_id;
    v_prix := coalesce(nullif(v_prix, 0), v_e.prix_abonnement_mensuel, 0);
  end if;

  return coalesce(v_prix, 0);
end;
$$;

comment on function public.rpc_abonnement_prix_du_cycle(uuid) is
  'Correctif 97 — prix du prochain cycle, avec LA MÊME règle que le moteur : installation seulement si date_activation IS NULL, sinon prix mensuel.';

revoke all on function public.rpc_abonnement_prix_du_cycle(uuid) from public, anon;
grant execute on function public.rpc_abonnement_prix_du_cycle(uuid) to authenticated;


-- ============================================================================
--  2. NATURE DU PROCHAIN CYCLE — même règle
-- ============================================================================
create or replace function public.rpc_abonnement_type_cycle(
  p_entreprise uuid
)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select case
           when (select e.date_activation from public.entreprises e
                  where e.id = p_entreprise) is null
            and coalesce((select e.prix_installation from public.entreprises e
                           where e.id = p_entreprise), 0) > 0
             then 'installation'
           else 'abonnement'
         end;
$$;

comment on function public.rpc_abonnement_type_cycle(uuid) is
  'Correctif 97 — « installation » seulement si le compte n''a jamais été activé, sinon « abonnement ».';

revoke all on function public.rpc_abonnement_type_cycle(uuid) from public, anon;
grant execute on function public.rpc_abonnement_type_cycle(uuid) to authenticated;


-- ============================================================================
--  3. STATUT VIDE — l'erreur « invalid input value for enum » vue en test
-- ============================================================================
--  `AbonnementService.etatInstallation` a renvoyé :
--     invalid input value for enum statut_abonnement_enum: ""
--  Un statut vide empêche la lecture du dossier d'abonnement. On le déduit
--  des dates et du montant dû, sans jamais toucher un statut valide.
do $$
declare
  v_n integer := 0;
begin
  begin
    update public.entreprises
       set statut = case
                      when coalesce(montant_total_du, 0) > coalesce(montant_deja_paye, 0)
                        then 'EN_ATTENTE_COMPLEMENT'::public.statut_abonnement_enum
                      when date_expiration is not null and date_expiration < now()
                        then 'EXPIRE'::public.statut_abonnement_enum
                      else 'ACTIF'::public.statut_abonnement_enum
                    end,
           updated_at = now()
     where statut is null or btrim(statut::text) = '';
    get diagnostics v_n = row_count;
    raise notice 'Correctif 97 — % statut(s) vide(s) normalisé(s).', v_n;
  exception
    when others then
      raise warning 'Correctif 97 — normalisation des statuts impossible : %', sqlerrm;
  end;
end $$;

-- ============================================================================
--  4. CONTRÔLE : pour chaque entreprise, ce que l'écran annonce = ce que le
--     moteur demandera.
-- ============================================================================
select e.nom,
       e.date_activation is null                 as premier_cycle,
       e.prix_installation                       as installation,
       e.prix_abonnement_mensuel                 as mensuel,
       public.rpc_abonnement_prix_du_cycle(e.id) as prix_annonce,
       e.statut::text                            as statut
  from public.entreprises e
 order by e.nom;

-- ============================================================================
--  FIN — CORRECTIF 97
-- ============================================================================
