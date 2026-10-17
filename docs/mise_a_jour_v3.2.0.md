# Mise à jour v3.2.0 — La caisse qui répond au doigt, et un marché qui se remplit seul

**Version :** 3.2.0 (build 36)
**Migrations SQL :** `20260916000078`
**Tests :** 929/929 ✅

---

## En une phrase

**Ajouter un article au panier est instantané (et une seule fois), « Enregistrer
vente » fonctionne, le tableau de bord se met à jour tout seul — et le marché
Biashara affiche les articles sans qu'on ait rien à publier.**

---

## Les quatre corrections

### 1. Ajouter un article : immédiat, et une seule fois

Avant, le bouton « Ajouter » **attendait une réponse du serveur**
(l'article, ses emballages) avant d'inscrire la ligne. D'où :

- un temps d'attente à chaque appui ;
- des appuis répétés (« le produit ne s'ajoute pas une seule fois ») ;
- sur une connexion lente, l'impression que rien ne se passe.

Désormais la ligne entre dans le panier **tout de suite**, avec les données du
téléphone. Les emballages éventuels (farde, carton, sachet…) sont ensuite
proposés par un message discret avec un bouton **« Choisir »** — sans jamais
retarder la vente ni dépendre du réseau.

### 2. « Enregistrer vente » : plus de « Produit ID introuvable »

L'écran de caisse enregistre la vente dans le fichier du téléphone. Il
recevait le **numéro de la base** (503…) alors que la copie locale connaît le
sien (83…) : d'où *« Erreur lors de l'enregistrement de la vente : Produit ID
503 introuvable »*, et l'obligation de passer par le panier.

Les deux numéros voyagent maintenant **ensemble** : le numéro de la base pour
le serveur, le numéro local pour le stock du téléphone. « Enregistrer vente »
et le panier aboutissent au même résultat.

### 3. Le tableau de bord se rafraîchit instantanément

Il gardait les anciens totaux jusqu'à ce qu'on quitte l'application. Un canal
unique annonce désormais **chaque écriture** :

| Action | Effet |
|---|---|
| Vente encaissée (panier) | totaux, ventes du jour, stock faible recalculés |
| Vente enregistrée (caisse) | idem, immédiatement |
| Article créé / modifié / supprimé | compteurs et stock à jour |

Aucun geste à faire : ni quitter l'écran, ni tirer vers le bas.

### 4. Le marché se remplit tout seul 🌍

Trois verrous empêchaient un article d'apparaître — tous fermés par défaut :

| Verrou | Avant | Maintenant |
|---|---|---|
| Vitrine « visible publiquement » | faux par défaut | **vrai** par défaut |
| Coordonnées GPS de la boutique | obligatoires | **plus** obligatoires (classée sans distance) |
| Publication de chaque article | à faire **à la main** | **automatique** |

**Côté boutique**, le formulaire d'article l'annonce désormais clairement :
*« Enregistrer suffit : cet article est immédiatement visible dans le marché
Biashara. Aucune publication à préparer. »*

Un article **volontairement retiré** du marché n'est jamais republié tout seul ;
une boutique en attente, rejetée ou suspendue reste invisible.

---

## Migration de cette version

| # | Fichier | Ce qu'elle fait |
|---|---|---|
| 78 | `20260916000078_marketplace_automatique.sql` | Vitrine visible par défaut · vue publique sans GPS obligatoire · publication automatique de chaque article (déclencheur + reprise des articles existants) |

**Idempotente** : relançable sans effet de bord. Elle se termine par un rapport
(articles en base, articles publiés, boutiques visibles).

> ⚠️ Rappel : les migrations **74**, **76** et **77** doivent également être
> exécutées si ce n'est pas déjà fait.

---

## Compatibilité

- Aucune donnée existante n'est supprimée ni renommée.
- Les ventes déjà enregistrées ne changent pas.
- Une boutique peut toujours **quitter** le marché : il suffit de décocher sa
  visibilité (Paramètres → Ma vitrine) ou de retirer un article.
