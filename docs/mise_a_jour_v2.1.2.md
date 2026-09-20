# Mise à jour v2.1.2 — Biashara Yangu

**Date :** 20 septembre 2026
**Fichiers :** `biashara-yangu.apk` (Android) • `biashara-yangu-linux.tar.gz`
(Linux) • `biashara-yangu-windows.zip` + `biashara-yangu-setup.exe` (Windows) •
`biashara-yangu-web.zip` (navigateur)
**Où télécharger :** dépôt GitHub → onglet **Releases** → *Biashara Yangu
v2.1.2*.
**Type :** correctifs d'affichage. Aucune migration SQL à exécuter.

---

## 🆕 Ce qui change

### 1. 🧩 Chaque activité ne voit QUE ses écrans

Après la v2.1.1, il restait des entrées d'autres métiers dans une activité
donnée. Tout a été repris :

| Écran / bouton | Activité(s) où il apparaît maintenant |
|---|---|
| **Ajouter un produit**, **Catégories**, **Importer des articles** | activités avec *Articles & catalogue* (boutique, pharmacie, mode, boucherie, restaurant, salon…) |
| **Nouvelle Vente**, **Scanner**, **Suivi commercial** | activités avec *Ventes & panier* |
| **Caisse** (raccourci d'accueil) | activités sans vente au comptoir (hôtel, salon) |
| Onglet **Stock** | activités avec *Stock* ou *Articles* |
| Onglet **Rapports** | activités avec *Rapports* |
| **Assistant IA** + **Quotas IA** | activités avec *Assistant IA* |
| Rapports **Ventes / Stock / Caisse / Dépenses / Finance / Expirations** | seulement si l'activité a le module correspondant |
| Menu **Gestion commerciale** → Dépenses, Dettes, Clients, Inventaires, Rapports | chaque carte suit son module |

> ⚠️ Précision importante : **les étiquettes QR ne donnent plus accès au
> catalogue d'articles**. Un hôtel dont le profil contient « QR codes &
> étiquettes » ne verra donc plus « Ajouter un produit » ni « Catégories ».
> C'était la cause du bouton qui restait affiché.
>
> ℹ️ Rappel : ces règles **masquent** des entrées, elles ne bloquent aucun
> écran et ne modifient pas vos droits (rôles).

### 2. 🤖 Assistant IA — la fonction serveur doit être publiée

Si l'assistant répond « *l'assistant n'est pas encore déployé* », ce n'est pas
un problème de l'application : la **fonction Edge `agent-ia` n'est pas publiée**
sur le projet Supabase. Vérifié le 20/09/2026 : le serveur répond
`Requested function was not found`. **Voir le fichier ci-joint :
`docs/deployer_function_ia.md`** (deux méthodes, dont un script qui fait tout).

### 3. 🖥️ Rappels de la v2.1.1 (inclus)

* contenu centré et borné (980 px) + **3 colonnes** sur ordinateur ;
* fenêtre d'ouverture **adaptée à votre écran** (plus de barre de navigation
  coupée sur un portable 1 366 × 768) ;
* monnaie : la devise de travail (module 18) — la migration
  `20260916000039_module18_devises.sql` est **déjà exécutée** ✅.

---

## 🔧 Comment mettre à jour

1. GitHub → **Releases** → *Biashara Yangu v2.1.2* → télécharger le fichier de
   votre appareil :
   * **Android** : `biashara-yangu.apk` (autoriser l'installation) ;
   * **Linux** : `biashara-yangu-linux.tar.gz` → remplacer le contenu du
     dossier d'installation (vos données restent dans `~/Documents/`) ;
   * **Windows** : `biashara-yangu-setup.exe` (ou `biashara-yangu-windows.zip`).
2. Rien d'autre à faire : aucune migration SQL pour cette version.
