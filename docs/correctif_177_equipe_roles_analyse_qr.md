# Correctif 177 — Équipe, rôles métier, analyse tous métiers, QR par boutique

**Date** : 20 novembre 2026
**Migration** : `supabase/migrations/20260916000177_equipe_roles_analyse_qr.sql`
**Prérequis** : **0174 → 0175 → 0176** exécutées (dans cet ordre)

---

## 1. Les 5 signalements

| # | Signalement | Cause réelle |
|---|---|---|
| 1 | « Un collaborateur créé dans le pressing n'est pas dans son espace : il n'y a que la caisse » | 3 causes cumulées : liste et modification de l'équipe filtrées sur `mon_proprietaire()` (un **espace**) au lieu de `mon_patron()` (l'**utilisateur**) ; espace par défaut = celui de la **première** entreprise du patron ; `role_pressing` jamais renseigné par la création générique |
| 2 | « Analyse de vente : impossible de produire le rapport pour le moment » (pressing) | Le rapport ne lisait que la table `ventes`. Un pressing vend des **prestations** (`pressing_lignes`) : `ventes` est vide. Le rapport utilisait aussi une **table temporaire** (refusée sur certains rôles) |
| 3 | « Le rapport doit être pour tous les produits, par meilleure vente » | La requête était limitée aux **10 premiers** produits |
| 4 | « Le module PDF de pharmacie doit être sur mon ordinateur » | Aucun guide pharmacie complet en PDF local |
| 5 | « Le QR code doit compter tout ce qui a déjà été produit par chaque boutique » | Les compteurs ne regardaient que les émissions facturées depuis 0175 |

---

## 2. Ce que fait la migration 0177

### 2.1 Équipe — le bon espace, le bon rôle

| Objet | Correction |
|---|---|
| `rpc_collaborateurs_lister()` | Filtre sur `mon_patron()` → la liste n'est plus vide pour un patron multi-entreprises ; expose `espace_id` et `role_pressing` |
| `rpc_collaborateur_maj(...)` | Même portée ; déduit `role_pressing` du rôle d'entreprise s'il manque (VENDEUR → caisse, MAGASINIER → atelier, PROPRIÉTAIRE → responsable) |
| `rpc_collaborateur_supprimer(...)` | Même portée (corrige la portée « espace » de 0176) |
| `espace_collaborateur_valide(...)` | Nouvel ordre : espace demandé → **espace actif du patron** → **premier espace actif de SON entreprise** → compatibilité historique. Plus jamais l'espace d'une autre entreprise |
| `rpc_collaborateur_creer(...)` | Entreprise de pressing sans boutique précisée → **espace pressing** ; `role_pressing` + `press_actif` renseignés |
| `press_collaborateur_creer(...)` | Choisit explicitement l'espace de type `pressing` (jamais l'entreprise, qui n'est pas un espace) |
| `entreprise_est_pressing(uuid)` | Nouveau helper |

> 🧹 La migration commence par **supprimer les surcharges historiques** de
> `rpc_collaborateur_creer` / `rpc_collaborateur_maj` (versions sans
> `p_espace_id`, laissées par 0140) : deux fonctions du même nom peuvent
> provoquer `PGRST203` (« function is not unique ») ou faire appeler
> l'ancienne version, qui n'a pas la correction de portée.

### 2.2 Réparation des comptes existants

Deux `UPDATE` ciblés, **sans toucher aux données métier** :

1. comptes de pressing dont l'espace n'est pas un espace pressing → espace pressing de leur entreprise ;
2. tout collaborateur dont `espace_actif_id` n'appartient pas à son entreprise → premier espace actif de son entreprise.

Les vérifications en fin de migration doivent renvoyer **0 ligne** pour les deux contrôles.

### 2.3 Analyse des ventes — tous métiers, tous produits

* Nouvelle fonction `analyse_lignes_ventes(entreprise, debut, fin)` :
  * **boutique** : `ventes` + `produits` (avec prix d'achat pour la marge) ;
  * **pressing** : `pressing_lignes` + `pressing_commandes` (hors commandes annulées) ;
  * **sans table temporaire** (fonction `stable`, lue dans un CTE).
* `rpc_rapport_entreprise_analyse(...)` réécrite :
  * lit `analyse_lignes_ventes` (les deux sources) ;
  * **tous les produits**, classés par chiffre d'affaires décroissant (plus de `limit 10`) ;
  * nouveaux champs `nb_produits` et `sources` (`boutique` / `pressing`) ;
  * mêmes conseils et même simulation « +10 % ».

**Erreur 42804 trouvée en production** : `ventes.quantite` (et selon le
schéma `ventes.prix`) est `real`, mais `analyse_lignes_ventes` déclare ses
colonnes `quantite/prix` comme `numeric`. Le corps SQL doit caster ces colonnes
explicitement (`coalesce(v.quantite, 0)::numeric`, idem `prix` et `prix_achat`)
ou Postgres lève « returned type real does not match expected type numeric in
column 4 ». Le correctif est dans la migration 0177 ; **réexécuter 0177** après
avoir remplacé l'ancienne version.

### 2.5 Droits métier pressing — le rôle global ne donne plus les écrans boutique

Le rôle général `VENDEUR` donne par défaut `ventes`, `scanner`, `panier` et
`caisse`. Ce rôle était nécessaire pour les anciennes routes d'entreprise,
mais il ne décrit pas le métier réel du collaborateur pressing. L'application
charge maintenant `pressing_role()` à l'entrée, puis `PermissionService`
applique une **liste blanche** à l'activité pressing, même si un ancien cache
de modules contient encore `ventes` ou `pesee` :

| Métier pressing | Pages métier visibles |
|---|---|
| Responsable / propriétaire | Dépôts, atelier, retraits, équipe, réglages, finance, rapports |
| Accueil | Dépôts, retraits (et actions associées au dépôt) |
| Atelier | Atelier seulement |
| Caisse | Retraits et caisse pressing |
| Métier absent | Accueil minimal ; le responsable doit attribuer un métier |

Tous les métiers pressing sont explicitement privés de `ventes`, `scanner`,
`panier`, `pesee`, `caisse` boutique, `stock`, `articles`, `clients` boutique,
`production` et `distribution`. Les routes directes `/main/new-sale`,
`/main/ventes`, `/main/panier`, `/main/pesee`, `/scanner`, `/main/caisse` et
`/main/commercial` sont aussi refusées. La caisse pressing reste accessible par
`/main/pressing/caisse` selon le métier.

Une sécurité serveur complète le filtre UI : `trg_ventes_interdire_pressing`
bloque tout `INSERT` dans `ventes` dont le `owner_id` appartient à un pressing,
y compris les appels RPC directs. Le métier pressing seul peut toujours créer
des dépôts/prestations via les RPC du module 35.

Le message de tentative de vente est traduit en français : « La vente boutique
est désactivée pour un pressing. Enregistrez le vêtement comme dépôt dans le
module Pressing. »

Migration 0177 répare aussi les collaborateurs anciens sans `role_pressing` :
`VENDEUR` → `accueil` (le rôle le plus étroit pour un comptoir),
`MAGASINIER` → `atelier`, `PROPRIETAIRE` → `responsable`. La vérification SQL
11.c attend donc 0 compte de pressing sans métier.

### 2.6 Tests des permissions pressing

`test/pressing_permissions_test.dart` vérifie maintenant :

* tous les métiers pressing sont refusés sur ventes, scanner, panier, caisse
   boutique, stock et articles ;
* `/main/new-sale`, `/scanner`, `/main/pesee`, `/main/caisse` sont refusés ;
* accueil, atelier, caisse et responsable conservent leurs routes pressing ;
* hors pressing, un vendeur garde ses permissions de boutique habituelles.
* `test/vente_article_serveur_test.dart` vérifie le message de la garde serveur.

### 2.4 QR codes — ce qui existe, ce qui est facturé, par boutique

* `rpc_qr_tarif_etat()` renvoie en plus `codes_existants` = **1 QR par article + 1 QR par emballage** de la boutique.
* `rpc_admin_tableau_bord()` renvoie `qr.emis`, `qr.existants` et `qr_par_entreprise` (nom, codes existants, facturés, revenus) — un QR déjà produit par une boutique apparaît donc **même s'il n'a pas été facturé**.

---

## 3. Fichiers touchés

| Fichier | Nature |
|---|---|
| `supabase/migrations/20260916000177_equipe_roles_analyse_qr.sql` | **nouveau** (validé 50/50) |
| `lib/models/analyse_entreprise.dart` | `nbProduits`, `sources`, `libelleOrigines` |
| `lib/services/analyse_entreprise_service.dart` | Périodes **sans décalage d'heure**, PDF « tous les produits », message d'erreur avec la cause serveur |
| `lib/pages/entreprise_detail_page.dart` | Carte analyse : produits classés + origine |
| `lib/services/qr_code_service.dart` | `QrTarif.codesExistants` |
| `lib/pages/qr_codes_page.dart` | Affiche les codes existants + retire une méthode morte |
| `lib/pages/admin_home_page.dart` | Carte QR : facturés / existants |
| `lib/services/permission_service.dart` | Portée pressing + refus central des écrans boutique pour les collaborateurs pressing |
| `lib/services/pressing_service.dart` | Code brut du métier pressing pour la matrice centrale |
| `lib/pages/scaffold_with_nav_bar.dart` | Charge le métier pressing avec la session |
| `lib/pages/home_page.dart` | Actions dédiées par métier ; aucun raccourci vente/scanner/pesée dans le pressing |
| `test/pressing_permissions_test.dart` | Tests des rôles et des routes directes |
| `test/analyse_entreprise_test.dart` | **nouveau** — 10 tests (parsing, périodes, PDF) |
| `docs/guide_module_pharmacie_complet.md` + `.html` + `.pdf` | Guide pharmacie complet **et PDF sur l'ordinateur** |
| `tools/guide_vers_pdf.py` | **nouveau** — Markdown → HTML → PDF (Chrome headless) |

---

## 4. Procédures de test

1. **Collaborateur pressing** — Pressing → Équipe → ajouter un collaborateur
   (rôle *Accueil*), puis se connecter avec son e-mail :
   *attendu* : il arrive sur l'espace **pressing** et voit Dépôts, Retraits
   (et Caisse), pas seulement la caisse.
2. **Mon Équipe (patron multi-entreprises)** — Paramètres → Mes vendeurs :
   *attendu* : la liste affiche enfin les collaborateurs ; modification et
   suppression fonctionnent.
3. **Analyse pressing** — Super Admin → Entreprises → fiche du pressing →
   Analyse des ventes → **Semaine** :
   *attendu* : le PDF se télécharge, avec le CA des **prestations**, et la
   mention « N ligne(s) pressing ».
4. **Tous les produits** — même test sur une boutique ayant plus de 10
   articles vendus : *attendu* : la liste contient **tous** les produits, du
   meilleur au moins vendu.
5. **QR par boutique** — Plateforme → QR codes, puis Tableau de bord :
   *attendu* : « codes existants dans la boutique : N » et « N facturé(s) ».
6. **Guide pharmacie** — ouvrir `docs/guide_module_pharmacie_complet.pdf`
   (copie dans `~/Documents/Guides/`).

---

## 5. Retour arrière

```sql
drop function if exists public.analyse_lignes_ventes(uuid, date, date);
drop function if exists public.entreprise_est_pressing(uuid);
```

Les autres fonctions (`rpc_*`) sont des `create or replace` : relancer les
migrations 0143/0157/0176 en cas de doute. Aucune donnée n'a été supprimée,
seuls des champs `espace_actif_id` / `role_pressing` ont été complétés.
