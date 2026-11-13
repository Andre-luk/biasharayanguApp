-- ============================================================================
--  0173 — UN PRESSING N'EST PAS UNE BOUTIQUE
--
--  Problème constaté le 13/11/2026 sur le compte « Pressing Test Biashara » :
--  l'accueil affichait encore la grille d'une boutique —
--      Produits · Statut du Stock · Mes ventes
--      + boutons « Nouvelle Vente » et « Scanner » + onglet « Stock »
--
--  CAUSE : la migration 0162 avait ajouté `ventes`, `produits`, `stock` et
--  `qr` au profil de modules de l'activité `pressing`, en mode « union »
--  (pour ne rien retirer aux profils existants). Ces modules n'ont rien à
--  faire dans un pressing : il REÇOIT, TRAITE et RESTITUE des vêtements
--  confiés. Son catalogue est « Prestations / Tarifs » (tables
--  `pressing_prestations`, `pressing_tarifs`), pas `produits`.
--
--  CE QUE FAIT CETTE MIGRATION
--    Retire les 4 codes du tableau `types_espaces_modules.modules` pour
--    `type = 'pressing'`. AUCUNE donnée métier n'est touchée : les tables
--    `produits`, `ventes`, `stock`, `qr_codes` restent intactes, et un
--    espace pressing qui en contiendrait encore les conserve pour l'export.
--    Seuls les ENTRÉES DE MENU et les CARTES de ces modules disparaissent.
--
--  EFFET (application ≥ 3.9.2) :
--    `rpc_mes_modules()` ne renvoie plus ventes/produits/stock/qr
--    ⇒ plus de carte « Produits », « Statut du Stock », « Mes ventes »,
--      plus de « Nouvelle Vente » / « Scanner », plus d'onglet « Stock ».
--    Restent : dépôts, atelier, retraits, caisse, clients, finance,
--      collaborateurs, rapports, assistant IA, abonnement.
--
--  ⚠️ Le module `caisse` est CONSERVÉ : c'est lui qui encaisse les dépôts,
--     les soldes et les retraits du pressing.
--  ⚠️ Idempotente : relançable sans effet supplémentaire.
-- ============================================================================

begin;

-- 1. Retrait des quatre modules « boutique » du profil pressing.
--    `jsonb_array_elements_text ... with ordinality` conserve l'ordre des
--    modules restants (l'écran Admin affiche le profil tel qu'il est stocké).
update public.types_espaces_modules t
   set modules = coalesce(
         (
           select jsonb_agg(x.code order by x.rang)
             from jsonb_array_elements_text(t.modules)
                  with ordinality as x(code, rang)
            where x.code not in ('ventes', 'produits', 'stock', 'qr')
         ),
         '[]'::jsonb
       )
 where t.type = 'pressing';

-- 2. Garde-fou : le profil pressing doit toujours exister et rester actif.
do $$
declare
  v_modules jsonb;
begin
  select m.modules into v_modules
    from public.types_espaces_modules m
   where m.type = 'pressing';

  if v_modules is null then
    raise exception 'PROFIL_PRESSING_ABSENT|Le profil de modules « pressing » est introuvable.';
  end if;

  if jsonb_array_length(v_modules) = 0 then
    raise exception 'PROFIL_PRESSING_VIDE|Le profil « pressing » est vide : migration annulée.';
  end if;
end $$;

-- 3. Verdict lisible dans le SQL Editor.
select m.type,
       m.libelle,
       m.actif,
       jsonb_array_length(m.modules) as nb_modules,
       m.modules
  from public.types_espaces_modules m
 where m.type = 'pressing';

commit;
