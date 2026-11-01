# Biashara Yangu — v3.4.1 (build 43)

**Date :** 1er novembre 2026
**Type :** version de correctifs (aucune fonctionnalité retirée)
**Migrations SQL :** `0095`, `0096` — s'ajoutent aux `0091` → `0094`.

---

## Ce que cette version corrige

Les six incohérences relevées en Super Administrateur, une par une.

### 1. « Le montant dépasse le solde restant » alors qu'on paie ce qui est dû

Cas : entreprise **EXPIRÉE**, « montant total dû 15 000 », encaissement
**15 000** → refus.

**Cause** : pour un abonnement échu, le moteur ouvre un **nouveau cycle** au
prix mensuel **actuel**. Depuis l'arrivée du barème, ce prix n'est plus
15 000 mais 10 000 : l'écran proposait donc plus que le dû réel, et la base
refusait — à juste titre.

**Corrigé** : l'écran demande à la base le prix du **prochain** cycle et
l'affiche sous le libellé « **Nouveau cycle à encaisser** ». Un abonnement
échu est facturé au prix actuel, jamais au montant du cycle précédent. Le
message d'erreur, s'il survient encore, dit maintenant quoi encaisser.

### 2. Le type d'activité ne changeait rien

Trois causes, toutes corrigées :

- le profil d'activité « **Distribution (production & tournées)** » pouvait
  être inactif, donc invisible dans le sélecteur ;
- choisir cette activité ne renseignait pas le **type** de l'entreprise :
  l'accueil continuait d'afficher Tournées, Ma tournée, Consignes clients,
  Récipients & bonus… **même dans une boutique** ;
- changer le type dans « Gestion du compte » ne touchait pas le profil de
  modules de l'entreprise : l'environnement ne suivait pas.

**Désormais** : choisir « Distribution » (à la création comme dans la fiche)
→ l'entreprise devient une distribution, son espace passe sur le profil
production + tournées, et les écrans de distribution apparaissent. Passer en
« Boutique » les masque. Un espace spécialisé (pharmacie, hôtel, restaurant)
n'est jamais écrasé.

La fiche entreprise affiche une carte **« Type d'activité »** qui dit en clair
ce qui est activé ou masqué — ce n'était vérifiable nulle part auparavant.

### 3. Impossible de supprimer une entreprise

Message : « le journal d'audit est inaltérable : delete est interdit sur
public.journal_audit ».

Le nettoyage passait par toutes les tables, dont le journal d'audit, protégé
en écriture seule. La suppression s'arrêtait dès la première ligne.

**Corrigé** : le journal de l'entreprise est traité à part (protection levée
le temps de l'opération, puis remise immédiatement), et les autres
suppressions sont tolérantes : une table récalcitrante est signalée au lieu
d'annuler tout le nettoyage.

### 4. Inscription : pas d'activité, et l'ancienne entreprise restait affichée

- Le sélecteur d'activité n'apparaissait qu'en **mode complet**. Il est
  maintenant proposé **dans les deux modes** (simple et complet).
- Après la création, l'application continuait d'afficher l'entreprise
  précédente (« biasharagroup ») jusqu'à ce qu'on quitte et se reconnecte.
  **L'entreprise créée devient active immédiatement** : espaces, modules,
  type d'activité et abonnement sont rechargés sur place.

### 5. Quotas IA payables en Mobile Money — **étape suivante**

Aujourd'hui la demande de quotas passe encore par l'administration. La
bascule vers un paiement direct suppose son propre cycle (packs → paiement
SerdiPay → confirmation par le webhook → crédit des quotas). C'est un lot
dédié, volontairement séparé pour ne pas toucher à l'argent « à moitié ».

---

## À faire après l'installation

1. Exécuter dans le SQL Editor, dans cet ordre :
   - `0095_suppression_entreprise_audit.sql`
   - `0096_type_activite_pilote_les_modules.sql`
   (les `0091` → `0094` sont déjà passées)
2. Vérifier avec `docs/verification_migrations.sql` puis
   `docs/verification_donnees.sql` : tout doit être `OK`.
3. **Définir le type d'activité** de votre société d'eau : fiche entreprise →
   carte « Type d'activité » → **Distribution**. Elle passera alors sur le
   profil production + tournées et paiera le barème distribution
   (50 000 / 20 000 au lieu de 30 000 / 10 000).
4. Redéployer l'Edge Function `serdipay` si ce n'est pas déjà fait.

> ⚠️ La migration `0096` **déduit** le type des entreprises existantes :
> celles qui n'ont pas d'espace « distribution » deviennent des boutiques —
> c'est voulu (les écrans de distribution ne doivent pas apparaître dans une
> boutique). Corrigez au cas par cas depuis la fiche entreprise.

---

## Technique

- `flutter analyze` : 0 erreur · **1122 tests** verts dont
  `paiement_abonnement_coherence_test.dart` (6).
- Migrations `0095` (5/5) et `0096` (11/11) validées SyntaxTree.
