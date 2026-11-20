# Correctif 175 — Équipe, QR codes, revenus SerdiPay, analyse des ventes

**Date** : 20 novembre 2026
**Migration** : `supabase/migrations/20260916000175_equipe_qr_revenus_analyse.sql`
**Prérequis** : **exécuter d'abord la migration 174**
(`20260916000174_creation_unifiee_suppressions.sql`).

---

## 1. Ce que le client a signalé (7 points)

| # | Signalement | Cause réelle trouvée |
|---|---|---|
| 1 | « Les formulaires doivent être dynamiques quand on veut écrire quelque chose » | Le clavier recouvrait le champ en cours de saisie (voir §8) |
| 2 | « La suppression d'utilisateur n'est pas trouvable » | Le bouton était en bas d'une feuille d'actions, en gris discret |
| 3 | « Enlever le mode de démarrage rapide du setup » | Un choix technique (rapide/complet) était proposé au patron |
| 4 | « Ajouter un collaborateur d'équipe échoue : `utilisateurs_parent_id_fkey` » | `parent_id` recevait l'**UUID de l'entreprise** au lieu de celui du **patron** |
| 5 | « L'argent de la plateforme doit être UNIQUEMENT celui passé par SerdiPay » | Le tableau de bord lisait la base **SQLite locale** de l'appareil |
| 6 | « Le QR généré par produit n'est pas reconnu au scan » + prix défini par la plateforme | Le scanner lisait `produits.owner_id = <utilisateur>` alors que `owner_id` = **espace** ; la RLS masquait les articles des autres espaces |
| 7 | « Rapport téléchargeable par entreprise (semaine / mois) avec conseils » | Fonctionnalité inexistante |

---

## 2. Migration 175 — objets créés / corrigés

### 2.1 Équipe du pressing (point 4)

* `press_collaborateur_creer(...)` — le collaborateur est rattaché au
  **patron** (`utilisateurs.parent_id = mon_patron()`), `entreprise_id` repris
  du patron, `espace_actif_id` = un **espace réel** de l'entreprise (jamais
  l'UUID de l'entreprise, qui n'existe pas dans `espaces`).
* `press_collaborateurs_lister()` — filtre sur `parent_id = mon_patron()`
  (et non sur l'entreprise : les comptes historiques portaient des
  `parent_id` erronés).
* `press_collaborateur_supprimer(uuid, text)` — retire un collaborateur avec
  confirmation écrite, sans jamais toucher au patron.
* Côté Dart : `PressingService.supprimerCollaborateur`,
  `PressingEquipePage._retirer` (icône rouge + dialogue « SUPPRIMER »).

### 2.2 Scanner et QR codes (point 6)

* `rpc_scanner_resoudre(p_code text)` — résout `PROD:<id>` et `COND:<uuid>`
  avec la BONNE portée : plateforme, propriétaire, patron, ou tout espace de
  l'entreprise du demandeur.
* `rpc_articles_entreprise(p_entreprise uuid)` — liste les articles d'une
  entreprise (toutes boutiques), pour la génération des QR par la plateforme.
* Prix du QR défini par la plateforme : `app_settings['qr_codes']`
  (`prix_unitaire` = **150 CDF** par défaut, `devise`), réglable par
  `rpc_qr_tarif_definir`, lisible par `rpc_qr_tarif_etat`.
* Table `qr_codes_emis` (une ligne par **entreprise + produit** émises) et
  `rpc_qr_code_emettre(bigint[], integer)` : facture l'émission, idempotent
  (un même produit n'est jamais refacturé).
* Côté Dart : `ScannerService` appelle d'abord le serveur, valide le
  **format localement** (`PROD:` numérique, `COND:` UUID) puis retombe sur
  l'ancienne lecture si la RPC n'est pas installée.

### 2.3 Revenus SerdiPay (point 5)

* `rpc_admin_tableau_bord()` renvoie :
  * `serdipay.total` / `.mois` / `.jour` / `.paiements` → **uniquement** les
    lignes `paiements_serdipay` au statut **`paye`** ;
  * `qr.total` / `qr.nb` → revenus des QR codes facturés à l'émission ;
  * `compteurs.entreprises` / `.comptes` / `.produits`.
* Côté Dart, `admin_home_page.dart` n'utilise plus `DBHelper` : les cartes
  affichent « Revenus SerdiPay (confirmés) », « ce mois », « aujourd'hui »,
  « Paiements confirmés », « Revenus QR codes émis », compteurs — avec la
  mention explicite que **seuls les paiements confirmés par SerdiPay sont
  comptés**.

### 2.4 Rapport d'analyse téléchargeable (point 7)

* `rpc_rapport_entreprise_analyse(p_entreprise_id uuid, p_debut date,
  p_fin date)` renvoie :
  * `totaux` : CA, ventes, articles, panier moyen, marge estimée ;
  * `top_produits` (10 premiers, avec part du CA) ;
  * `jours` et `moments` (Matin / Midi / Après-midi / Soir / Nuit) ;
  * `meilleur_produit`, `meilleur_jour`, `meilleur_moment` ;
  * `conseils` : textes calculés sur les ventes réelles (meilleur jour, pic
    horaire, dépendance à un produit, panier moyen, marge) ;
  * `simulation` : « si « X » progresse de 10 %, la boutique gagne ~Y CDF ».
* Côté Dart :
  * `lib/models/analyse_entreprise.dart` — modèle tolérant (int/num/String) ;
  * `lib/services/analyse_entreprise_service.dart` — `charger()`,
    `construirePDF()` (polices standard, aucun accès réseau),
    `exporterPDF()` (navigateur sur le web, « Téléchargements/Biashara
    Yangu/Rapports » ailleurs), périodes `periodeSemaine()` (7 jours) et
    `periodeMois()` (30 jours) ;
  * `entreprise_detail_page.dart` — carte « Analyse des ventes » avec deux
    boutons **Semaine** / **Mois** et un résumé à l'écran.

---

## 3. Fichiers Dart touchés

| Fichier | Nature |
|---|---|
| `lib/pages/admin_home_page.dart` | Cartes SerdiPay + QR (plus de SQLite locale) |
| `lib/pages/entreprise_detail_page.dart` | Carte « Analyse des ventes » (semaine / mois) |
| `lib/pages/pressing/pressing_equipe_page.dart` | Retrait d'un collaborateur |
| `lib/pages/admin_users_page.dart` | « Supprimer l'utilisateur » en tête, en rouge |
| `lib/pages/setup_page.dart` | Choix « mode de démarrage rapide » supprimé |
| `lib/pages/qr_codes_page.dart` | Prix du QR affiché / modifiable + facturation |
| `lib/services/scanner_service.dart` | Résolution serveur + contrôle de format |
| `lib/services/qr_code_service.dart` | Tarif, émission facturée |
| `lib/services/article_service.dart` | `getArticlesPourEntreprise` (RPC) |
| `lib/services/pressing_service.dart` | `supprimerCollaborateur` |
| `lib/models/analyse_entreprise.dart` | **nouveau** |
| `lib/services/analyse_entreprise_service.dart` | **nouveau** |
| `lib/widgets/clavier_champ_visible.dart` | **nouveau** — champ actif visible au-dessus du clavier |
| `lib/main.dart` | Branchement du garde clavier autour de toute l'application |

---

## 4. Ordre d'exécution (Supabase → SQL Editor)

1. `20260916000174_creation_unifiee_suppressions.sql`
2. `20260916000175_equipe_qr_revenus_analyse.sql`

Les deux sont **idempotentes** (relançables sans effet de bord) et ne
suppriment aucune donnée.

---

## 5. Vérifications SQL (lecture seule, incluses en fin de 175)

```sql
select p.proname from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public'
   and p.proname in ('press_collaborateur_creer','press_collaborateurs_lister',
                     'press_collaborateur_supprimer','rpc_scanner_resoudre',
                     'rpc_articles_entreprise','rpc_qr_tarif_etat',
                     'rpc_qr_tarif_definir','rpc_qr_code_emettre',
                     'rpc_admin_tableau_bord','rpc_rapport_entreprise_analyse')
 order by 1;                                    -- attendu : 10 lignes

select * from public.app_settings where cle = 'qr_codes';   -- prix 150 CDF
```

---

## 6. Procédures de test (à faire dans l'ordre)

1. **Équipe du pressing** — Pressing → Équipe → « Ajouter un collaborateur ».
   *Attendu* : succès (plus de `utilisateurs_parent_id_fkey`), le
   collaborateur apparaît dans la liste avec son rôle. Puis icône rouge →
   « SUPPRIMER » → il disparaît.
2. **Suppression d'utilisateur** — Super Admin → Utilisateurs → fiche d'un
   compte → la ligne rouge « Supprimer l'utilisateur » est **la première**.
   Confirmer en tapant le nom (ou SUPPRIMER) → le compte, ses entreprises et
   ses paiements sont supprimés, une sauvegarde JSON est créée.
3. **Setup** — Créer une entreprise : plus aucun choix « mode de démarrage »,
   les modules de l'activité sont tous installés.
4. **QR codes** — Plateforme → QR codes : le prix (150 CDF par défaut)
   s'affiche et se modifie. Générer les QR d'un produit puis **scanner
   l'étiquette imprimée** depuis la caisse de la boutique : l'article est
   reconnu (plus de « introuvable »).
5. **Tableau de bord** — Super Admin → Accueil : « Revenus SerdiPay
   (confirmés) » ne compte que les paiements `paye`. Un paiement en attente ne
   change pas le total.
6. **Rapport d'analyse** — Super Admin → Entreprises → fiche → « Analyse des
   ventes » → **Semaine** puis **Mois** : le PDF est téléchargé et contient
   meilleur produit, meilleur jour, meilleur moment, conseils et la
   projection « +10 % ».

---

## 7. Retour arrière

Aucune donnée n'est supprimée : pour revenir en arrière, on peut
`drop function` les nouvelles fonctions et `drop table public.qr_codes_emis`
(les QR déjà imprimés restent lisibles par l'ancienne lecture directe).

```sql
drop function if exists public.rpc_rapport_entreprise_analyse(uuid, date, date);
drop function if exists public.rpc_admin_tableau_bord();
drop function if exists public.rpc_qr_code_emettre(bigint[], integer);
drop function if exists public.rpc_qr_tarif_definir(integer, text);
drop function if exists public.rpc_qr_tarif_etat();
drop function if exists public.rpc_articles_entreprise(uuid);
drop function if exists public.rpc_scanner_resoudre(text);
drop table if exists public.qr_codes_emis;
```

---

## 8. Point 1 — « les formulaires doivent être dynamiques quand on veut écrire »

Réponse du client (20/11) : **le champ en cours de saisie doit rester visible
quand le clavier s'ouvre** (saisie « à l'aveugle » dans les formulaires longs).

Correctif appliqué, **une seule fois pour toute l'application** :

* nouveau widget `lib/widgets/clavier_champ_visible.dart` — à chaque changement
  de champ actif, il appelle `Scrollable.ensureVisible` (marge de 12 % en
  haut), **deux fois** : dès la fin de la frame de mise au point, puis 320 ms
  plus tard, une fois le clavier réellement mesuré ;
* posé dans `main.dart`, dans le `builder` du `MaterialApp.router`, autour de
  toute l'application (donc aussi les dialogues et les feuilles du bas) ;
* aucun comportement modifié si le champ est déjà visible ou s'il n'y a pas de
  zone défilante.

À vérifier sur mobile / web mobile : formulaire article (10+ champs),
dépense, client, collaborateur pressing, fiche entreprise.

