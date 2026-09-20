# Mise à jour v2.1.1 — Biashara Yangu

**Date :** 20 septembre 2026
**Fichiers :** `biashara-yangu.apk` (Android) • `biashara-yangu-linux.tar.gz`
(Linux) • `biashara-yangu-windows.zip` + `biashara-yangu-setup.exe` (Windows) •
`biashara-yangu-web.zip` (navigateur)
**Où télécharger :** dépôt GitHub → onglet **Releases** → *Biashara Yangu
v2.1.1*.
**Type :** correctifs d'affichage (aucune migration à exécuter).

---

## 🆕 Ce qui change

### 1. 🏨 Une activité ne voit plus les boutons d'une autre

C'est le correctif principal de cette version.

| Activité | Avant | Maintenant |
|---|---|---|
| **Hôtel** | « Nouvelle Vente » + « Scanner » + onglet « Stock » | **aucun** de ces boutons — à la place un raccourci **« Caisse »**, ses cartes *Chambres / Réservations / Arrivées / Départs* |
| **Boutique / Dépôt / Pharmacie / Mode / Boucherie / Boulangerie** | inchangé | inchangé (Nouvelle vente, Scanner, Stock, Ajouter un produit) |
| **Restaurant** | inchangé | inchangé |
| **Salon de coiffure** | Nouvelle vente + Scanner | raccourci **« Caisse »** (pas de vente au comptoir) |

Concrètement, sur l'accueil **et** dans la barre du bas, chaque entrée suit
désormais les **modules de l'activité** choisie pour l'entreprise :

* **« Nouvelle Vente »** n'apparaît que si l'activité vend au comptoir **et**
  que votre rôle y a droit ;
* **« Scanner »** suit l'activité de vente (un hôtel n'a pas d'articles à
  scanner) ;
* le bouton **« Ajouter un produit »** n'apparaît que si l'activité gère un
  catalogue d'articles ;
* l'onglet **« Stock »** disparaît des activités sans stock ni articles ;
* les activités sans vente au comptoir gardent un accès direct à leur
  **Caisse** (encaissement des séjours, des prestations).

> ℹ️ Rien n'est bloqué : ces entrées suivent l'activité (masquage), les écrans
> restent joignables et vos droits (rôles) n'ont pas changé.

### 2. 🖥️ Interface à la bonne taille sur ordinateur

L'application est dessinée pour un **téléphone** : sur un ordinateur, les
cartes et les boutons s'étiraient sur toute la largeur de la fenêtre et
paraissaient démesurés.

* Le contenu est désormais **centré** et sa largeur est **bornée** (980 px) :
  plus d'éléments étirés d'un bord à l'autre.
* La grille de statistiques passe à **3 colonnes** sur ordinateur (au lieu de
  2) : les cartes gardent une taille raisonnable.
* La **fenêtre d'ouverture** est ajustée à votre écran : sur un portable
  1 366 × 768, la fenêtre était plus haute que la dalle et la barre de
  navigation du bas passait sous l'écran. Elle occupe maintenant au plus 94 %
  de la largeur et 92 % de la hauteur de l'écran (minimum 900 × 600).

> 📱 Sur téléphone, rien ne change : les marges et la grille à 2 colonnes sont
> conservées à l'identique.

---

## 🔧 Comment mettre à jour

1. GitHub → **Releases** → *Biashara Yangu v2.1.1* → télécharger le fichier de
   votre appareil :
   * **Android** : `biashara-yangu.apk` (autoriser l'installation) ;
   * **Linux** : `biashara-yangu-linux.tar.gz` → remplacer le contenu du
     dossier d'installation (vos données restent dans `~/Documents/`) ;
   * **Windows** : `biashara-yangu-setup.exe` (ou `biashara-yangu-windows.zip`).
2. Aucune migration SQL n'est nécessaire pour cette version.

---

## 📌 Rappel — module 18 (devises) de la v2.1.0

Si ce n'est pas déjà fait, exécutez **une fois** dans Supabase → *SQL Editor* →
*Run* :

```
supabase/migrations/20260916000039_module18_devises.sql
```

Sans elle, l'écran **« Devise & conversion »** affiche « module non installé »
(le reste de l'application fonctionne).
