# Mise à jour v3.8.0 — Sorties de stock, dettes encaissées, SerdiPay obligatoire

**Date :** 10 novembre 2026
**Thème :** la marchandise et l'argent disent enfin la vérité — ce qui sort
sans être vendu est justifié, ce qui est vendu à crédit n'est plus compté
comme encaissé, et aucun abonnement ne se paie plus en espèces.

---

## 1. Les sorties de stock qui n'étaient pas des ventes

### Le problème

Une marchandise ne pouvait quitter le stock **que par une vente**. Or un stock
diminue aussi quand :

| Cas | Exemple concret |
|---|---|
| Consommation du propriétaire | « j'ai consommé un sucré de ma boutique » |
| Article offert / échantillon | un « goffre » donné à un client |
| Perte ou vol | article disparu, constaté à l'inventaire |
| Casse | bouteilles tombées |
| Péremption | produit expiré retiré de la vente |
| Retour fournisseur | marchandise renvoyée |
| Usage interne | ingrédients utilisés pour une fabrication |

La seule solution était un « ajustement d'inventaire » : il corrige la
quantité, mais **ne dit pas pourquoi**, ne valorise pas la perte et ne fournit
aucun document justificatif.

### Ce qui change

- **Nouvelle option « Sortie de stock »** : icône 📤 de l'écran Stock, et menu
  de chaque article.
- **Motif obligatoire** (liste fermée) + une précision libre.
- **Le stock diminue réellement**, la **caisse ne bouge pas** : ce n'est pas
  une vente, il n'y a rien à encaisser.
- **La perte est valorisée** au prix d'achat figé au moment de la sortie (le
  coût d'hier ne change pas si le prix monte demain).
- **Rapport imprimable** : période, détail par motif, détail ligne par ligne,
  valeur totale, et la mention explicite « sortie sans vente ». C'est la pièce
  qui justifie l'inventaire devant un associé, un contrôleur ou un comptable.
- Un stock qui passe sous son seuil à cause d'une casse **alerte** désormais
  comme après une vente.

---

## 2. La vente à crédit n'est plus comptée comme de l'argent reçu

### Le problème (argent réel)

Chaque vente à crédit créait **une ligne de caisse** — comme si le client avait
payé — et **aucune dette**. Deux conséquences graves :

1. le solde de caisse était **gonflé** du montant de toutes les ventes impayées ;
2. l'écran « Dettes clients » restait **vide** : la dette n'existait nulle part.
   C'est exactement le « il n'y a pas d'option pour régulariser ».

### Ce qui change

- Une vente à crédit **n'entre plus en caisse** et **crée la dette du client**
  automatiquement (une seule fois par vente).
- **Réparation des données existantes** : les dettes manquantes des ventes
  déjà enregistrées sont reconstituées, puis les lignes de caisse fantômes sont
  retirées — **uniquement** celles où aucune espèce n'avait été reçue.
- **Nouveau bouton « Encaisser une dette »** dans la Caisse, à côté de
  « Décaissement ». Le client revient ? On encaisse, et **l'argent entre dans
  la caisse** (visible au journal : « Règlement — nom du client »).

---

## 3. Abonnement et installation : SerdiPay uniquement

### La règle

> Les abonnements et les frais d'installation se paient **uniquement par
> Mobile Money via SerdiPay** — super administrateur, finance ou agent. Aucun
> encaissement en espèces.

### Ce qui change

- **Écran Finance → Activations** : plus de « mode de paiement » à choisir, le
  bouton ouvre directement SerdiPay. Le montant total dû reste enregistré avant
  le paiement.
- **Paiement d'abonnement** (commerçant, agent) : même règle.
- **Création d'entreprise** : le récapitulatif propose **« Payer par Mobile
  Money »** — le client règle depuis son téléphone juste après la création du
  compte.
- **Côté base** : tout paiement d'abonnement sans transaction SerdiPay réelle
  en attente (même entreprise, même montant, référence fournisseur présente)
  est **refusé**. Impossible de contourner en saisissant « espèces ».

### « Mois d'abonnement + 7 jours inclus »

Les frais d'installation **comprennent le premier mois**. Le moteur part de
l'échéance future quand elle existe : un compte en **essai de 7 jours** qui
paie ses 10 000 CDF ressort donc **ACTIF pour 7 + 30 = 37 jours**. Aucun jour
d'essai n'est perdu — un contrôle automatique le vérifie à chaque exécution de
la migration.

---

## 4. Migrations à exécuter (dans cet ordre)

1. `20260916000132_sorties_stock_speciales.sql`
2. `20260916000133_vente_credit_sans_encaissement.sql`
3. `20260916000134_serdipay_obligatoire_abonnement.sql`
4. *(correctif client)* `20260916000135_urembo_echeance_09_12_2026.sql` —
   pose l'échéance d'Urembo Market au **09/12/2026** en fin de journée, sans
   toucher aux montants ni aux paiements.

Chaque script est **idempotent** et se termine par des contrôles en lecture
seule.

---

## 5. Ce qui n'est pas encore activé

- **Module 35 (Pressing)** : le code est présent mais reste **volontairement
  inactif** (aucune boutique ne l'utilise). Il sera activé quand le module sera
  terminé.
- Aucune autre modification des écrans du quotidien : le reste de
  l'application fonctionne comme avant.

---

## 6. Vérifications rapides après mise à jour

```sql
-- Aucune ligne de caisse « crédit » ne doit subsister
select count(*) as lignes_credit
  from public.caisse
 where lower(btrim(coalesce(mode_paiement, 'especes'))) in ('credit', 'dette');

-- Les dettes des ventes à crédit existent et sont encaissables
select d.id, c.nom, d.montant_total, d.montant_paye, d.statut
  from public.dettes d
  join public.clients c on c.id = d.client_id
 order by d.date_creation desc
 limit 20;

-- Les deux garde-fous sont en place
select tgname from pg_trigger
 where tgname in ('trg_caisse_vente_credit', 'trg_paiement_mm_serdipay',
                  'trg_sorties_stock_appliquer');
```
