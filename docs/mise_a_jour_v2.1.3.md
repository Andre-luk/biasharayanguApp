# Mise à jour v2.1.3 — Biashara Yangu

**Date :** 20 septembre 2026
**Fichiers :** `biashara-yangu.apk` (Android) • `biashara-yangu-linux.tar.gz`
(Linux) • `biashara-yangu-windows.zip` + `biashara-yangu-setup.exe` (Windows) •
`biashara-yangu-web.zip` (navigateur)
**Où télécharger :** dépôt GitHub → onglet **Releases** → *Biashara Yangu
v2.1.3*.
**Type :** correctifs d'affichage et de messages. **Aucune migration SQL.**

---

## 🆕 Ce qui change

### 1. 🧩 Le profil de l'activité est LA référence (fin de l'audit)

Chaque catégorie n'affiche plus que ses propres écrans — vérifié catégorie par
catégorie sur les profils réels :

| Entrée | Module(s) exigé(s) |
|---|---|
| Nouvelle Vente · Scanner · Suivi commercial · rapports de ventes | `ventes` |
| Ajouter un produit · Catégories · Importer des articles | `produits` |
| **Onglet Stock** · rapports de stock | **`stock`** *(nouveau : le module est désormais le seul juge)* |
| Onglet Rapports | `rapports` |
| Assistant IA · Quotas IA | `assistant_ia` |
| Caisse · dettes · rapports de caisse | `caisse` |
| Dépenses · Finance · rapports de dépenses | `finance` |
| Clients · Collaborateurs | `clients` · `employes` |
| Cartes du menu « Gestion commerciale » | chacune son module |

> Conséquence nette : le profil **Hôtel** n'affiche ni Nouvelle Vente, ni
> Scanner, ni Stock, ni Ajouter un produit, ni Catégories (un raccourci
> **Caisse** à la place) ; un profil qui gère des articles **sans** module de
> stock (ex. Salon de coiffure) ne voit plus l'onglet Stock.

### 2. 🤖 Message clair si l'assistant IA n'est pas prêt

Le message d'erreur indique désormais **quoi faire** :
- fonction non publiée → marche à suivre de déploiement ;
- secret manquant → où le définir (`Project Settings → Edge Functions → Secrets`).

### 3. 🖥️ Rappels des v2.1.1 / v2.1.2 (inclus)

* contenu centré, borné à 980 px, grille à 3 colonnes sur ordinateur ;
* fenêtre d'ouverture adaptée à l'écran (plus de barre de navigation coupée) ;
* devises CDF/USD (module 18) — migration déjà exécutée ✅.

---

## 🔧 Comment mettre à jour

1. GitHub → **Releases** → *Biashara Yangu v2.1.3* → télécharger le fichier de
   votre appareil :
   * **Android** : `biashara-yangu.apk` (autoriser l'installation) ;
   * **Linux** : `biashara-yangu-linux.tar.gz` (vos données restent dans
     `~/Documents/`) ;
   * **Windows** : `biashara-yangu-setup.exe`.
2. Aucune migration SQL, aucune action serveur pour cette version.
