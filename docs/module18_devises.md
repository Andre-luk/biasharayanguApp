# Module 18 — Devises de travail & taux de conversion

> Migration SQL : `supabase/migrations/20260916000039_module18_devises.sql`
> (à exécuter APRÈS `0038` — idempotente).
>
> Code application :
> `lib/models/devise.dart`, `lib/services/devise_service.dart`,
> `lib/utils/format_utils.dart` (devise globale + `formatMontant`),
> `lib/pages/devise_page.dart` (écrans client et plateforme).

## 1. Principe

Chaque entreprise travaille dans **sa devise** :

| Devise | Code | Unité affichée | Montants |
|---|---|---|---|
| Franc congolais | `CDF` | `CDF` | entiers (`15 000 CDF`) |
| Dollar américain | `USD` | `$` | deux décimales (`12,50 $`) |

Le choix s'applique à **tous les montants de l'entreprise** : prix d'achat et
de vente des articles, conditionnements, ventes, reçus, dépenses, caisse,
dettes, hôtel/restaurant/fêtes/boulangerie, rapports (écran, PDF, Excel),
paiements, abonnements (équivalents) et quotas IA (facturés en CDF).

### ⚠️ Règle importante

La devise est une **unité de lecture/saisie** : changer de devise **ne
convertit pas** les montants déjà enregistrés (`15 000` reste `15 000`). C'est
pourquoi l'écran :

* affiche un **avertissement explicite** dans le dialogue de changement ;
* propose un **simulateur** « 1 USD = X CDF » pour convertir avant d'agir.

## 2. Taux de conversion

```
taux effectif = taux de l'ENTREPRISE  (entreprises.taux_usd_cdf)
              ↓ si absent
                taux de la PLATEFORME (app_settings['devises'].taux_usd_cdf)
              ↓ si absent
                2 800 CDF (valeur de repli)
```

### Devise : trois niveaux (héritage)

```
1. espaces.devise            ← devise de l'entreprise UTILISÉE (recommandé,
                               ex. boutique en CDF, hôtel en USD)
2. entreprises.devise        ← devise du COMPTE (défaut hérité par les
                               nouveaux espaces) : réglée par l'admin
                               plateforme ou au premier choix du patron
3. app_settings['devises']   ← devise par défaut de la plateforme
   .devise_defaut              (Super Admin)
```

Le patron règle la devise de l'**espace qu'il est en train d'utiliser**
(« Devise & conversion ») ; l'admin plateforme peut régler la devise d'un
compte entier (**Devises & taux** → « Configurer une entreprise »), héritée
par tous ses espaces qui n'ont pas encore la leur.

* **Super Admin** : réglage du taux par défaut + devise proposée par défaut
  (écran admin → **Système → Devises & taux**) ;
* **Patron** : peut imposer son propre taux (écran **Paramètres → Devise &
  conversion**), ou revenir au taux de la plateforme (`p_taux = 0`).

RPC correspondantes :

| RPC | Rôle | Effet |
|---|---|---|
| `rpc_devise_etat()` | connecté | devise de l'espace actif (sinon du compte), taux effectif, taux plateforme, devises proposées |
| `rpc_devise_configurer(p_devise, p_taux, p_entreprise_id)` | PROPRIÉTAIRE (ou Super Admin) | choisit la devise ; `p_taux` = null (inchangé), 0 (taux plateforme), > 0 (taux propre) |
| `rpc_devise_plateforme_definir(p_taux, p_devise_defaut)` | SUPER_ADMIN | taux + devise par défaut de la plateforme |
| `taux_change_effectif(entreprise)` | outil | taux applicable |

Helpers SQL : `devise_libelle()`, `devise_symbole()` (miroirs de
`Devise.libelle` / `Devise.symbole` côté Dart).

Journal d'audit : action **`DEVISE_CONFIG`** (niveau **CRITIQUE**), à chaque
changement (entreprise ou plateforme).

## 3. Propagation dans l'application

`DeviseService` charge la devise (démarrage, connexion, bascule d'entreprise)
puis **applique l'unité à `FormatMonetaire`** : comme *tous* les écrans passent
par `formatMontant()`, la devise se propage partout automatiquement
(≈ 200 appels) — aucune régression : par défaut, l'affichage reste `CDF`.

* **Rôles de la plateforme** (admin, gestionnaire, finance) : restent en CDF
  (leurs montants sont ceux de la plateforme : abonnements, grilles).
* **Écrans client qui montrent des prix plateforme** (quotas IA) : affichés
  explicitement en CDF + équivalent.
* **Écran devise** : `/settings/devise` (entreprise) et `/admin/devises`
  (plateforme : taux par défaut + configuration d'une entreprise).
* **Déconnexion** : retour à CDF pour l'utilisateur suivant.

## 4. Où l'utilisateur accède à la fonctionnalité

| Écran | Chemin | Rôle |
|---|---|---|
| Paramètres → **Devise & conversion** | `/settings/devise` | Propriétaire (consultation : tous) |
| Admin → Système → **Devises & taux** | `/admin/devises` | Super Admin |

## 5. Vérifications après exécution (SQL Editor)

```sql
-- Colonnes ajoutées (attendu : devise = CDF par défaut, taux NULL)
select column_name, column_default, is_nullable
  from information_schema.columns
 where table_name = 'entreprises' and column_name in ('devise','taux_usd_cdf');

-- Réglage plateforme (attendu : {"taux_usd_cdf": 2800, "devise_defaut": "CDF"})
select value from public.app_settings where key = 'devises';

-- Devise des entreprises + taux appliqué
select nom, devise, taux_usd_cdf, public.taux_change_effectif(id)
  from public.entreprises order by created_at desc limit 10;

-- Niveaux d'audit
select public.audit_niveau('DEVISE_CONFIG');  -- CRITIQUE
```

## 6. Recette

| Scénario | Attendu |
|---|---|
| Entreprise en CDF (défaut) | Montants inchangés (`15 000 CDF`) |
| Passage en USD | Confirmation + avertissement ; montants affichés en `$` (`15 000,00 $`) |
| Taux propre (2 850) | `1 USD = 2 850 CDF` sur l'écran devise et dans les rapports |
| Retour au taux plateforme | Case « Utiliser le taux de la plateforme » → `p_taux = 0` |
| Compte non validé | Toujours verrouillé (module 17) — la devise reste consultable |
| Super Admin | Voit CDF partout + règle le taux plateforme et la devise d'une entreprise |

## 7. Tests

`flutter test test/devise_test.dart` (20 cas) : codes et libellés, analyse de
`rpc_devise_etat`, conversions CDF ↔ USD (garde-fous), priorité du taux
d'entreprise, formatage (entier CDF / cents USD), propagation via
`FormatMonetaire`, messages serveur. Suite complète : 607 tests.
