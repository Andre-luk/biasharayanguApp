-- ============================================================================
--  biashara_yangu — PHASE 11 bis : L'AGENT PEUT PAYER POUR L'ENTREPRISE
--  ---------------------------------------------------------------------------
--  Demande du patron : « si c'est un agent qui crée le compte, il peut
--  effectuer le paiement directement pour l'entreprise ».
--
--  Le moteur de paiement (`rpc_serdipay_ouvrir`) n'acceptait que :
--    • le propriétaire du compte ;
--    • les quatre rôles plateforme (`est_plateforme()`).
--  Un AGENT DE TERRAIN était donc refusé (`ENTREPRISE_REFUSEE`).
--
--  Ici : on ajoute UNE seule possibilité — l'agent rattaché au dossier
--  (`entreprises.agent_id = auth.uid()`). Aucun autre droit n'est élargi :
--  le montant reste calculé et vérifié en base, l'agent ne peut ni réduire
--  ni augmenter ce qui est dû.
--
--  ⚠️ La fonction est reproduite à l'IDENTIQUE depuis la migration 0088,
--     seule la clause d'autorisation change.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);

create or replace function public.agent_de_entreprise(p_entreprise uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select e.agent_id = auth.uid()
      from public.entreprises e
     where e.id = p_entreprise
  ), false);
$$;

comment on function public.agent_de_entreprise(uuid) is
  'Vrai si l''agent connecté a pris en charge cette entreprise (entreprises.agent_id).';

revoke all on function public.agent_de_entreprise(uuid) from public, anon;
grant execute on function public.agent_de_entreprise(uuid) to authenticated;


create or replace function public.rpc_serdipay_ouvrir(
  p_objet         text,
  p_objet_id      uuid default null,
  p_telephone     text default null,
  p_operateur     text default null,
  p_entreprise_id uuid default null,
  p_montant       numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user     uuid := auth.uid();
  v_ent      uuid;
  v_ligne    public.entreprises%rowtype;
  v_objet    text := lower(btrim(coalesce(p_objet, 'abonnement')));
  v_montant  numeric := 0;
  v_devise   text := 'CDF';
  v_type     text := 'SOLDE';
  v_tel      text;
  v_op       text;
  v_ref      text;
  v_id       uuid;
  v_expire   timestamptz;
begin
  if v_user is null then
    raise exception 'SESSION_ABSENTE';
  end if;

  v_ent := public.mon_entreprise_id();

  if p_entreprise_id is not null then
    if p_entreprise_id = v_ent then
      v_ent := p_entreprise_id;
    elsif public.est_plateforme() then
      v_ent := p_entreprise_id;
    elsif public.agent_de_entreprise(p_entreprise_id) then
      -- PHASE 11 : l agent qui a pris en charge le dossier peut PAYER pour
      -- l entreprise (le marchand paie cash sur le terrain, l agent ouvre le
      -- paiement). Il ne gagne aucun autre droit pour autant.
      v_ent := p_entreprise_id;
    else
      raise exception 'ENTREPRISE_REFUSEE';
    end if;
  end if;

  if v_ent is null then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  select * into v_ligne from public.entreprises where id = v_ent;
  if not found then
    raise exception 'ENTREPRISE_INTROUVABLE';
  end if;

  v_devise := coalesce(nullif(btrim(v_ligne.devise), ''), 'CDF');

  v_tel := nullif(regexp_replace(coalesce(p_telephone, ''), '[^0-9]', '', 'g'), '');
  if v_tel is null or length(v_tel) < 9 or length(v_tel) > 15 then
    raise exception 'TELEPHONE_INVALIDE';
  end if;

  v_op := nullif(lower(btrim(coalesce(p_operateur, ''))), '');

  -- MONTANT : calculé ici, jamais dicté par le client.
  if v_objet = 'facture' then
    if p_objet_id is null then
      raise exception 'OBJET_REQUIS';
    end if;

    select coalesce(f.solde_restant, 0)
      into v_montant
      from public.factures_abonnement f
     where f.id = p_objet_id
       and f.entreprise_id = v_ent;

    if v_montant is null then
      raise exception 'FACTURE_INTROUVABLE';
    end if;

  elsif v_objet = 'abonnement' then

    -- ABONNEMENT ÉCHU : on ouvre d'abord le cycle suivant au prix négocié.
    -- C'est ce qui débloque le renouvellement en autonomie.
    if coalesce(v_ligne.solde_restant, 0) <= 0
       and v_ligne.date_activation is not null
       and (v_ligne.statut in ('EXPIRE', 'EN_ATTENTE_COMPLEMENT')
            or (v_ligne.date_expiration is not null
                and v_ligne.date_expiration < now())) then
      begin
        perform public.rpc_abonnement_preparer_renouvellement(v_ent);
      exception
        when others then
          -- On ne masque jamais la suite : si la préparation échoue
          -- (prix absent), le message viendra de la lecture ci-dessous.
          null;
      end;

      select * into v_ligne from public.entreprises where id = v_ent;
    end if;

    v_montant := coalesce(v_ligne.solde_restant, 0);

    -- AVANCE : le client peut payer une PARTIE du solde, jamais plus.
    if p_montant is not null and p_montant > 0 then
      if p_montant > v_montant + 0.01 then
        raise exception 'MONTANT_INCORRECT';
      end if;
      v_montant := round(p_montant, 2);
    end if;

  else
    raise exception 'OBJET_INVALIDE';
  end if;

  if v_montant <= 0 then
    raise exception 'SOLDE_NUL';
  end if;

  -- Type attendu par le moteur d'abonnement.
  v_type := case
              when coalesce(v_ligne.montant_deja_paye, 0) > 0 then 'SOLDE'
              when v_montant < coalesce(v_ligne.solde_restant, 0) - 0.01 then 'AVANCE'
              when v_ligne.date_activation is null then 'AVANCE'
              else 'RENOUVELLEMENT'
            end;

  v_ref := public.serdipay_reference();

  insert into public.paiements_serdipay (
    reference, entreprise_id, utilisateur_id, objet, objet_id,
    montant, devise, type_paiement, telephone, operateur, statut
  ) values (
    v_ref, v_ent, v_user, v_objet, p_objet_id,
    v_montant, v_devise, v_type, v_tel, v_op, 'en_attente'
  )
  returning id, expire_le into v_id, v_expire;

  begin
    insert into public.journal_audit (entreprise_id, action, utilisateur_id, details)
    values (
      v_ent, 'SERDIPAY_OUVERT', v_user,
      jsonb_build_object(
        'reference', v_ref, 'objet', v_objet, 'montant', v_montant,
        'type', v_type, 'operateur', v_op
      )
    );
  exception when others then null;
  end;

  return jsonb_build_object(
    'ok', true,
    'reference', v_ref,
    'montant', v_montant,
    'devise', v_devise,
    'type_paiement', v_type,
    'expire_le', v_expire,
    'entreprise_id', v_ent
  );
end;
$$;

comment on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid, numeric) is
  'Ouvre un paiement SerdiPay. PHASE 11 bis : le propriétaire, la plateforme ET l''agent rattaché au dossier peuvent payer pour l''entreprise.';

revoke all on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid, numeric) from public, anon;
grant execute on function public.rpc_serdipay_ouvrir(text, uuid, text, text, uuid, numeric) to authenticated;

-- ============================================================================
--  FIN — PHASE 11 bis
-- ============================================================================
