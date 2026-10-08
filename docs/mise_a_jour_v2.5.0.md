# Mise à jour v2.5.0 — Biashara Yangu

> **Date :** 8 octobre 2026
> **Type :** version de fonctionnalités (le prix d'abonnement démarre à 5 000 CDF)

---

## 🔴 À FAIRE AVANT D'INSTALLER CETTE VERSION

Certaines corrections sont **côté base de données**. Exécutez-les dans
**Supabase → SQL Editor**, dans cet ordre — les scripts sont idempotents,
donc les relancer ne casse rien :

```
57  pools de quotas hérités
58  attribution des quotas par le Super Admin
59  code-barres des produits          ← OBLIGATOIRE (nouvelle colonne)
60  deux prix d'abonnement
61  ne plus refacturer l'installation
62  premier renouvellement débloqué
63  sécurité des droits d'écriture    ← IMPORTANT (voir ci-dessous)
64  l'agent corrige, mais ne suspend pas
65  fonctionnalités selon l'abonnement
```

⚠️ **Le 59 est obligatoire** : sans la colonne `produits.code_barre`,
l'enregistrement d'un produit avec un code-barres échouerait.

---

## 🔒 SÉCURITÉ — deux corrections importantes

### Une faille critique fermée

La fonction qui **efface toute la plateforme** (comptes + entreprises)
n'exigeait que la phrase de confirmation, **sans aucun contrôle de rôle** — et
elle était ouverte à tout compte connecté. N'importe quel compte (agent,
vendeur, commerçant) connaissant la phrase pouvait déclencher l'effacement
général. Elle est maintenant **réservée au Super Admin**.

### Les droits de l'agent de terrain

- ❌ il ne peut plus **suspendre ni réactiver** un compte ;
- ❌ il ne peut plus **activer ni désactiver** un compte utilisateur ;
- ❌ il ne peut plus **supprimer** une entreprise ou un compte ;
- ✅ il peut toujours **corriger les informations** d'un dossier (nom, ville,
  activité, téléphone) ;
- ✅ son parcours complet est intact : créer, vérifier, valider un paiement.

La base refuse désormais ces écritures, même si l'interface les proposait
encore.

---

## 🏷️ Lecteur de codes-barres — partout

Chaque produit peut porter **son** code-barres fabricant (EAN-13, EAN-8,
UPC-A/E, Code 128, Code 39/93, ITF-14, Codabar, DataMatrix) — **et** les
étiquettes QR déjà imprimées par l'application continuent de fonctionner.

**Une douchette USB ou Bluetooth fonctionne sans configuration** : elle « tape »
le code comme un clavier.

Le scan est disponible dans **cinq écrans** :

| Écran | Ce que fait le scan |
|---|---|
| Création / modification d'un produit | remplit le champ code-barres |
| Vente / caisse | ajoute l'article au panier |
| Entrée de stock | sélectionne le produit reçu |
| Liste et recherche | filtre la liste sur le produit scanné |
| Inventaire | isole la ligne à compter et rappelle le stock théorique |

Un même code-barres ne peut pas être enregistré deux fois chez le même patron :
l'application l'explique en français au lieu d'afficher une erreur technique.

## 🔔 Alerte de stock

Quand un article **passe sous son seuil**, une notification arrive
**immédiatement** — et **une seule fois par franchissement** : revendre un
article déjà en alerte ne noie pas le commerçant sous les notifications.

---

## 💰 Abonnement : deux prix distincts

Le problème corrigé : l'entreprise ne portait qu'**un seul** montant, qui
servait à la fois de « frais d'installation + premier mois » et de prix de
renouvellement. Un client ayant payé 30 000 CDF d'installation se voyait donc
réclamer **30 000 CDF à nouveau**, alors que seul le mois suivant était dû.

Désormais, chaque entreprise porte **ses deux prix** :

- **prix d'installation** — le premier mois est inclus dans ce montant ;
- **prix mensuel** — appliqué à partir du renouvellement.

Le prix est **négocié entreprise par entreprise** et **modifiable**. Et le
moteur **ne peut plus refacturer une installation** : s'il ne connaît pas le
prix mensuel, il retient le montant encaissé — et refuse explicitement toute
somme égale au prix d'installation.

---

## 🧩 Les fonctionnalités suivent l'abonnement

$$\text{fonctionnalités} = \text{activité} \;\cap\; \text{niveau d'abonnement}$$

- **L'activité** décide de ce qui a du sens (une pharmacie gère des lots, un
  hôtel des chambres).
- **Le niveau** décide de ce qui est payé.

Trois niveaux sont installés et **librement modifiables** :

| Niveau | Prix mensuel conseillé | Inclus |
|---|---|---|
| **Essentiel** | 5 000 CDF | ventes, produits, stock, caisse, clients, rapports |
| **Pro** | 10 000 CDF | + QR, finance, employés, assistant IA |
| **Premium** | 20 000 CDF | toutes les fonctionnalités de l'activité |

> **Aucune fonctionnalité n'est masquée tant qu'un niveau n'est pas affecté à
> l'entreprise.** Cette version ne peut donc rien retirer à personne : le
> filtre reste inactif jusqu'à ce qu'un niveau soit attribué.

---

## 🧾 Traçabilité

- Le paiement d'un abonnement note désormais le **cycle** concerné
  (installation ou renouvellement), le montant dû et les prix retenus.
- Toute affectation de niveau ou de prix est **journalisée**.

---

## 🛠️ Sous le capot

- 749 tests automatisés au vert.
- Base : correctifs 57 → 65 (migrations idempotentes).
- Outil d'audit livré : `tools/audit_abonnement_complet.sql` — **lecture
  seule**, il croise statuts, montants, dates, prix, niveaux et rattachements,
  et signale les incohérences.

## 📌 Reste pour la prochaine version

- Les **écrans d'administration** des niveaux d'abonnement (créer, renommer,
  cocher les fonctionnalités) et l'affectation d'un niveau depuis la fiche
  d'une entreprise. **En attendant, l'affectation se fait en SQL :**

```sql
select public.rpc_abonnement_definir_niveau_entreprise(
  (select id from public.entreprises where nom ilike '%Biashara%'), 'PRO');
```

- Le CRUD des quotas IA (packs, tarifs, annulation d'une attribution, gestes
  commerciaux).
- Le **code de validation** des actions de l'agent terrain (5 minutes,
  traçabilité, régularisation par la Finance).
