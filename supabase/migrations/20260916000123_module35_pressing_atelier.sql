-- ============================================================================
--  biashara_yangu — MODULE 35 : PRESSING & BLANCHISSERIE
--  ÉTAPE 5 — L'ATELIER (file de travail des agents)
--  ---------------------------------------------------------------------------
--  CE QUE CE SCRIPT AJOUTE
--    `pressing_atelier_lister(p_etape, p_miennes, p_limite)` : la FILE DE
--    TRAVAIL du pressing — un vêtement par ligne, avec son dossier, son
--    client, sa date promise et son étape actuelle.
--
--  POURQUOI UNE RPC DÉDIÉE
--    Le tableau de bord raisonne en DOSSIERS ; l'atelier raisonne en
--    VÊTEMENTS. Un agent doit voir « 12 chemises en repassage » et non
--    « 4 commandes ». Les deux lectures sont différentes et honnêtes.
--
--  ⚠️ Règles
--    • Aucun vêtement déjà remis ni d'un dossier annulé n'apparaît.
--    • `p_miennes = true` limite la vue aux vêtements affectés à l'agent
--      connecté (vue personnelle de travail).
--    • Lecture seule : les changements d'étape passent par les RPC de
--      vérification (`pressing_ligne_avancer`, `pressing_controle_qualite`).
--
--  ⚠️ IDEMPOTENT — peut être rejoué. Aucune table existante modifiée.
-- ============================================================================

select set_config('search_path', 'public, extensions', true);


create or replace function public.pressing_atelier_lister(
  p_etape   text default null,
  p_miennes boolean default false,
  p_limite  integer default 500
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_ent  uuid := public.pressing_entreprise();
  v_rows jsonb;
begin
  if auth.uid() is null then
    raise exception 'SESSION_ABSENTE|Connectez-vous.';
  end if;
  if not (public.peut('pressing_atelier', 'voir')
          or public.peut('pressing_depots', 'voir')
          or public.est_plateforme()) then
    raise exception 'DROIT_REFUSE|Votre rôle ne permet pas d''ouvrir l''atelier.';
  end if;

  select coalesce(jsonb_agg(x order by x->>'date_prevue' nulls last,
                                     x->>'date_depot'), '[]'::jsonb)
    into v_rows
    from (
      select jsonb_build_object(
               'ligne_id', l.id,
               'commande_id', c.id,
               'numero', c.numero,
               'client_nom', c.client_nom,
               'client_telephone', c.client_telephone,
               'position', l.position,
               'designation', coalesce(nullif(btrim(l.designation), ''),
                                       l.categorie_nom, 'Vêtement'),
               'categorie_nom', l.categorie_nom,
               'prestation_nom', l.prestation_nom,
               'marque', l.marque,
               'couleur', l.couleur,
               'taille', l.taille,
               'defauts', l.defauts,
               'etat_depot', l.etat_depot,
               'etape_code', l.etape_code,
               'etape_libelle', coalesce(e.libelle, l.etape_code),
               'est_prete', coalesce(e.est_finale, l.etape_code = 'PRET'),
               'agent_id', l.agent_id,
               'debut_traitement', l.debut_traitement,
               'fin_traitement', l.fin_traitement,
               'controle_ok', l.controle_ok,
               'controle_note', l.controle_note,
               'urgence', c.urgence,
               'date_depot', c.date_depot,
               'date_prevue', c.date_prevue,
               'en_retard', (c.date_prevue is not null and c.date_prevue < now())
             ) as x,
             c.date_prevue,
             c.date_depot
        from public.pressing_lignes l
        join public.pressing_commandes c on c.id = l.commande_id
        left join public.pressing_etapes e
               on e.entreprise_id = l.entreprise_id and e.code = l.etape_code
       where l.entreprise_id = v_ent
         and l.remis_le is null
         and c.statut <> 'ANNULEE'
         and (p_etape is null or btrim(p_etape) = ''
              or l.etape_code = upper(btrim(p_etape)))
         and (coalesce(p_miennes, false) = false or l.agent_id = auth.uid())
       order by c.date_prevue nulls last, c.date_depot
       limit greatest(coalesce(p_limite, 500), 1)
    ) s;

  return v_rows;
end;
$$;

comment on function public.pressing_atelier_lister(text, boolean, integer) is
  'Module 35 — file de travail de l''atelier : chaque vêtement non remis avec son dossier, son étape et son agent.';

revoke all on function public.pressing_atelier_lister(text, boolean, integer)
  from public, anon;
grant execute on function public.pressing_atelier_lister(text, boolean, integer)
  to authenticated;


-- ============================================================================
--  VÉRIFICATIONS
-- ============================================================================

select proname
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and proname = 'pressing_atelier_lister';
