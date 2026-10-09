# Mise à jour v2.7.0 — Quotas IA : catalogue, reprise et gestes commerciaux

**Version :** 2.7.0 (build 30)
**Migration SQL :** `20260916000068_quotas_ia_crud.sql` *(à exécuter après le correctif 67)*
**Tests :** 805/805 ✅

---

## En une phrase

**Vous voyez enfin où sont passés vos quotas — et vous pouvez récupérer ceux
qu'un collaborateur n'a pas utilisés.**

---

## Ce qui change pour vous

### 🔍 Où sont passés mes quotas ?

L'écran des quotas affiche désormais, en plus de votre pool :

- ce que détient **chaque collaborateur** (disponible / consommé) ;
- **qui** lui a attribué ces quotas ;
- le total encore chez les membres, et le total déjà consommé.

Avant, la liste des membres n'affichait aucun solde : impossible de savoir qui
détenait quoi, donc impossible de décider quoi reprendre.

### ↩️ Reprendre une attribution

Un vendeur quitte la boutique avec 40 quotas non utilisés ? Vous les
**reprenez** : ils reviennent immédiatement dans le pool de l'entreprise.

**Ce qui n'est jamais reprenable :** les quotas **déjà consommés**. Le travail de
l'assistant a été rendu, il est dû. L'écran le dit explicitement.

### 🪙 (Plateforme) Un catalogue de packs enfin modifiable

Les packs étaient **figés dans l'application** : 10 / 20 / 50 / 100 quotas, à
prix strictement proportionnels. Impossible de créer un pack de 30, ni de faire
une remise sur les gros packs.

Désormais, l'Expert peut **créer, modifier, désactiver ou supprimer** un pack
(taille, prix, nom commercial, ordre d'affichage).

**Le client paie exactement le prix du pack affiché** — c'était le point
critique : la demande d'achat calcule le montant côté serveur, et elle suit
maintenant le catalogue.

> ⚠️ La **taille** d'un pack est définitive. Pour passer de 10 à 30 quotas,
> créez un nouveau pack puis désactivez l'ancien : les clients ont déjà acheté
> l'ancien, on ne le transforme pas en douce.

### 🎁 (Plateforme) Geste commercial

Offrez des quotas à une boutique — essai, geste après un incident,
accompagnement du lancement — depuis la **fiche du client**.

- Le **motif est obligatoire** : un cadeau sans justification est une sortie
  d'argent que personne ne peut expliquer six mois plus tard.
- Les quotas offerts **ne comptent jamais comme achetés** : vous distinguez donc
  toujours ce que vous avez payé de ce qui vous a été offert.
- L'opération est inscrite au **journal d'audit** avec son motif.

---

## Bon à savoir

- **Une offre désactivée ne peut plus être commandée** — c'est exactement
  l'intérêt de la retirer de la grille.
- **Le dernier pack actif est protégé** : impossible de désactiver ou supprimer
  le seul pack restant, sinon plus aucun achat ne serait possible.
- **Les achats déjà effectués ne sont jamais touchés** par un changement de
  catalogue — seul le prix des achats **à venir** change.
- **Le journal d'audit classe les gestes commerciaux en CRITIQUE** : un don de
  quotas est de l'argent donné, il doit être aussi visible qu'un changement de
  droits.

---

## Notes techniques (pour la fiche store)

**Base de données — correctif 68** (`20260916000068_quotas_ia_crud.sql`) :

- table `agent_ia_packs` (taille, prix, libellé, ordre, actif) — lecture seule,
  écritures par RPC uniquement ; **reprise des 4 packs existants sans inventer
  de prix** (le pack de 10 garde le prix de référence de la configuration) ;
- `rpc_agent_ia_packs` / `_pack_enregistrer` / `_pack_supprimer` (Super Admin) ;
- `rpc_agent_ia_attributions` (soldes par membre) et
  `rpc_agent_ia_attribution_annuler` (reprise, verrou `FOR UPDATE`) ;
- `rpc_agent_ia_offrir` (geste commercial, motif obligatoire) ;
- **`rpc_agent_ia_demander_achat` corrigée** : elle REFUSAIT toute taille hors
  de la liste figée 10/20/50/100 et calculait le montant par proportionnalité.
  Le catalogue aurait donc été décoratif — un pack de 30 aurait été refusé, et
  facturé au mauvais prix s'il avait pu passer ;
- **`audit_niveau` reprise à l'identique** depuis la migration 39 puis
  complétée (les correctifs 67 et 68), par un script qui **assure** la forme du
  bloc avant de l'insérer. Les actions inconnues retombent au niveau `INFO` :
  sans ce patch, un don de quotas aurait été journalisé au même niveau qu'un
  affichage de page.

**Application** : `models/agent_ia.dart` (`PackQuotas` étendu +
`AttributionQuota` + `AttributionsQuotas`), `services/agent_service.dart`
(5 méthodes + 1 lecture), `pages/agent_ia_config_page.dart` (CRUD des packs),
`pages/achat_quotas_page.dart` (attributions + reprise),
`pages/entreprise_detail_page.dart` (geste commercial).

**Repli assumé** : tant que la migration n'est pas exécutée, l'application
retombe sur la grille locale et **le signale à l'écran** — sans quoi un
administrateur croirait que ses modifications ont été enregistrées.
