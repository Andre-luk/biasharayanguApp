# Sorties de stock, dettes encaissées et paiements SerdiPay

**Migrations concernées :** `20260916000132`, `20260916000133`, `20260916000134`
**Version :** non publiée (à intégrer à la prochaine release)

---

## 1. Sorties de stock spéciales (migration 0132)

### Le problème

Une marchandise ne quittait le stock **que par une vente**. Or un stock diminue
aussi quand :

| Cas | Exemple |
|---|---|
| Consommation du propriétaire | « j'ai consommé un sucré de ma boutique » |
| Article offert / échantillon | un « goffre » donné à un client |
| Perte ou vol | disparition constatée à l'inventaire |
| Casse | bouteilles tombées |
| Péremption | produit expiré retiré de la vente |
| Retour fournisseur | marchandise renvoyée |
| Usage interne | ingrédients utilisés pour une fabrication |

Dans **tous** ces cas : le stock baisse, **aucun argent n'entre en caisse**.

### Ce qui a été ajouté

- **Table `public.sorties_stock`** : article, quantité, **motif obligatoire**,
  note, valeur unitaire figée, date, auteur.
- **Trigger `trg_sorties_stock_appliquer`** : retire la quantité du stock.
  ⚠️ Aucune ligne de `caisse` n'est écrite : ce n'est pas une vente.
- **`rpc_stock_sortie(...)`** : enregistre une sortie, refuse un stock
  insuffisant (`STOCK_INSUFFISANT`), valorise la perte, journalise
  `SORTIE_STOCK`.
- **`rpc_stock_sorties_liste(...)`** : historique filtrable (période, article,
  motif) avec totaux et **détail par motif**.
- **Écran « Sorties de stock »** : `/main/stock/sorties`
  - accès par l'icône 📤 de l'écran Stock, ou par le menu de chaque article ;
  - filtres : aujourd'hui / 7 jours / ce mois / période libre, et par motif ;
  - bandeau « Aucun encaissement : ces articles ne sont pas vendus ».
- **Rapport imprimable** (`RapportSortiesPdfService`) : en-tête de
  l'établissement, période, détail par motif, détail des sorties, valeur totale
  et mention explicite « sortie sans vente ».

### Ce que le commerçant voit

- Le stock diminue réellement (le même stock que la caisse utilise).
- Le chiffre d'affaires **ne bouge pas**.
- Un document justificatif imprimable existe pour chaque période.

---

## 2. La vente à crédit n'est plus un encaissement (migration 0133)

### Le problème (argent réel)

`rpc_vente_valider` écrivait une ligne dans `public.caisse` **pour toutes les
ventes**, y compris celles à crédit, et n'écrivait **rien** dans `public.dettes`.

Conséquences :

1. la **caisse était gonflée** du montant de chaque vente impayée ;
2. la **dette du client n'existait pas** côté serveur : l'écran « Dettes
   clients » restait vide — donc « il n'y a pas d'option pour régulariser ».

### Ce qui a été ajouté

- **Trigger `trg_caisse_vente_credit`** (BEFORE INSERT sur `caisse`) :
  - vente à crédit → la ligne de caisse **n'est pas créée** et la **dette du
    client est enregistrée** (une seule fois par vente, clé `vente_uuid`) ;
  - vente normale → comportement inchangé.
- **Rattrapage** : les dettes manquantes des ventes déjà encaissées à tort sont
  créées, puis **les lignes de caisse fantômes sont supprimées** — uniquement
  lorsque `montant_recu` est nul ou 0.
- **Application** : la caisse n'écrit plus de dette locale (elle n'était lue par
  aucun écran actif). La dette vient du serveur et apparaît donc immédiatement
  dans « Dettes clients ».
- **Écran Caisse** : nouveau bouton **« Encaisser une dette »**
  (à côté de « Décaissement »), qui ouvre les dettes clients. Le règlement
  passe par `rpc_dette_paiement` → table `paiements_dette` → **comptée dans le
  solde de caisse**.

### Parcours de régularisation

1. Le client prend une dette à la caisse (vente à crédit) → stock sorti,
   caisse **inchangée**, dette créée.
2. Le client revient payer → « Dettes clients » → **Encaisser** → montant,
   mode → `rpc_dette_paiement`.
3. L'argent **entre dans la caisse** (journal : « Règlement — nom du client »).

---

## 3. Abonnement et installation : SerdiPay uniquement (migration 0134)

### Règle appliquée

> Les abonnements et les frais d'installation se paient **uniquement par Mobile
> Money via SerdiPay**, quel que soit le rôle : super administrateur, finance
> ou agent. Aucun encaissement en espèces.

### Modifications

- **Base** — `paiement_mm_exige_serdipay` ne se limite plus au Mobile Money :
  **tout** paiement d'abonnement sans transaction SerdiPay réelle en attente
  (même entreprise, même montant, référence fournisseur présente) est refusé.
  Seul le chemin SerdiPay lui-même (`mode_paiement` = « SerdiPay »,
  « SerdiPay · OM »…) passe.
- **Finance → Activations** : plus aucune validation en espèces ; le bouton
  ouvre SerdiPay (le montant total dû est toujours enregistré avant).
- **Paiement d'abonnement (commerçant)** : idem, SerdiPay uniquement.
- **Création d'entreprise** : le récapitulatif propose désormais
  **« Payer par Mobile Money »** — le client règle depuis son téléphone juste
  après la création du compte.

### « Mois d'abonnement + 7 jours inclus »

Le moteur (`rpc_abonnement_enregistrer_paiement`, migration 0115) part de
l'**échéance future** quand elle existe :

```
date_expiration = (échéance actuelle si future, sinon maintenant) + durée du cycle
```

Un compte en **essai de 7 jours** qui paie ses frais d'installation
(10 000 CDF, premier mois inclus) ressort donc **ACTIF pour 7 + 30 = 37 jours**.
Aucun jour d'essai n'est perdu : c'est vérifié en fin de migration 0134.

---

## 4. Ordre d'exécution

1. `20260916000132_sorties_stock_speciales.sql`
2. `20260916000133_vente_credit_sans_encaissement.sql`
3. `20260916000134_serdipay_obligatoire_abonnement.sql`

Chaque script est **idempotent** et se termine par des contrôles en lecture
seule (nombre de dettes, lignes de caisse restantes, trigger présent).

---

## 5. Après les migrations — à vérifier

```sql
-- 1. Plus aucune ligne de caisse « crédit »
select count(*) as lignes_credit
  from public.caisse
 where lower(btrim(coalesce(mode_paiement, 'especes'))) in ('credit', 'dette');

-- 2. Les dettes des ventes à crédit existent
select d.id, c.nom as client, d.montant_total, d.montant_paye, d.statut
  from public.dettes d
  join public.clients c on c.id = d.client_id
 order by d.date_creation desc
 limit 20;

-- 3. Le garde-fou SerdiPay est en place
select tgname from pg_trigger where tgname = 'trg_paiement_mm_serdipay';
```
