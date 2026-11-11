# Comptes collaborateurs « Bonjour utilisateur » — correctif base de données

**Concerne** : `rachel@biashara.com` et `abi@biashara.com` (collaboratrices de
**Portes Ouvertes**).

**Script à exécuter** :
`supabase/migrations/20260916000141_fix_collaborateurs_portes_ouvertes.sql`
(précédé de `20260916000142_collaborateurs_entreprise_coherente.sql`)

---

## 0. Ordre d'exécution

| Ordre | Script | Rôle |
|---|---|---|
| 1 | `0142_collaborateurs_entreprise_coherente.sql` | sécurise le déclencheur hérité + réaligne les entreprises |
| 2 | `0141_fix_collaborateurs_portes_ouvertes.sql` | crée / rattache les fiches de Rachel et Abi |
| 3 | `0140_collaborateurs_sans_code.sql` | fonctions de création depuis **Mon Équipe** |

> Un script lancé deux fois ne casse rien : ils sont tous idempotents.

---

## 1. Ce que voit l'utilisatrice

- l'accueil écrit « **Bonjour utilisateur** » au lieu de son nom ;
- la boutique **Portes Ouvertes** n'apparaît plus : l'application ouvre un
  espace vide (stock, caisse) comme si le compte était propriétaire.

> ⚠️ **Cas constaté le 11/11** : les deux comptes se connectent mais n'ont
> **aucune fiche** dans `public.utilisateurs`. Ils n'apparaissent donc dans
> aucune liste construite à partir des fiches (équipe, collaborateurs…) et
> l'application n'a ni nom, ni rôle, ni entreprise à lire — d'où « Bonjour
> utilisateur » et un accueil réduit à « Suivi commercial ». La réparation
> **crée** la fiche au lieu de la corriger.

## 2. Pourquoi (dans le code, pas une hypothèse)

### a) « Bonjour utilisateur »

À l'ouverture de l'accueil, `home_page.dart` lit la fiche du compte dans
`public.utilisateurs` :

| Ce que lit l'application | Colonne | Si la valeur manque |
|---|---|---|
| le nom affiché | `nom` | « Bonjour utilisateur » |
| « suis-je un collaborateur ? » | `parent_id` | le compte est pris pour un **propriétaire** ⇒ boutique vide |
| la boutique du patron | nom du compte parent | rien ne s'affiche |
| les droits | `new_role` | droits minimaux ou vides |

### b) « Suivi commercial » au lieu de « Nouvelle vente » + « Scanner »

Ce n'est **pas** un module de distribution : c'est le **libellé de repli** du
second raccourci de l'accueil (`home_page.dart`, ligne 892). Le code dit :

```dart
if (permissions.peut(caisse, creer))      → « Nouvelle vente »
permissions.peutVoir(scanner)
    ? « Scanner »
    : « Suivi commercial »   // ← repli quand le droit scanner N'EXISTE PAS
```

Autrement dit :

- **« Nouvelle vente » absente** = droit `caisse / créer` non accordé ;
- **« Suivi commercial »** = droit `scanner` non accordé.

Les deux disparaissent en même temps quand le **rôle lu par l'application**
(valeur de `new_role`, sinon de `role`) n'est pas reconnu : la matrice de
droits renvoie alors « aucune permission » pour ce compte.

Un `VENDEUR` (ou `PROPRIETAIRE`) possède `caisse/créer` **et** `scanner` :
c'est exactement le rôle d'une collaboratrice de boutique. D'où la réparation
qui **écrit** le rôle au lieu de le conserver.

Donc : la fiche existe, mais `parent_id` (parfois `nom`) et/ou le rôle n'ont
pas été renseignés. **Aucune correction d'application n'est nécessaire** : tout
se règle en base.

## 3. Ce que fait le script

1. **Affiche l'état actuel** des deux comptes (bloc « AVANT », construit à
   partir de `auth.users`, donc visible même sans fiche), **tous les patrons**
   avec leur entreprise et leur nombre de collaborateurs, et une **recherche
   « portes »** tolérante (espaces, tirets, casse ignorés).
2. **Crée la fonction** `public.reparer_collaborateur(email, boutique, patron, role)` :
   - retrouve le propriétaire dans cet ordre : e-mail du patron passé en
     paramètre → **indice `parentId` des métadonnées du compte** (l'ancien
     code boutique) → nom de l'entreprise → nom de l'espace → nom du patron ;
     la comparaison ignore espaces, tirets, apostrophes et casse
     (« Portes Ouvertes » = « portes-ouvertes » = « PORTESOUVERTES ») ;
   - complète `nom`, `prenom`, `telephone` (fiche existante → métadonnées du
     compte de connexion → partie locale de l'e-mail, avec majuscule) ;
   - écrit `parent_id` = propriétaire, `entreprise_id` = entreprise du
     propriétaire, `espace_actif_id` = espace par défaut (seulement s'il
     existe), `role = 'collaborator'`, **`new_role` = rôle demandé
     (`VENDEUR` par défaut — valeurs acceptées : `PROPRIETAIRE`, `VENDEUR`,
     `MAGASINIER`, `COMPTABLE_ENTREPRISE`)**, `valide = 1` ;
   - trace l'opération dans `journal_audit` (`COLLABORATEUR_RATTACHE`).
3. **Répare les deux comptes** (chacun séparément : un échec n'empêche pas
   l'autre).
4. **Ré-affiche les fiches** (bloc « APRÈS ») et le compteur
   `comptes_rattaches_sur_2` — il doit valoir **2**.

## 4. Exécution

Supabase → **SQL Editor** → coller le fichier → **Run**.

Puis, sur le téléphone des collaboratrices : se déconnecter et se reconnecter
(ou fermer/rouvrir l'application) pour que la fiche serveur remplace la fiche
locale.

## 5. Si le propriétaire n'est pas retrouvé

Le script affiche un avertissement `ÉCHEC … PROPRIETAIRE_INTROUVABLE` et la
requête « CANDIDATS PROPRIÉTAIRE » reste vide. Il suffit alors de désigner le
patron à la main :

```sql
select public.reparer_collaborateur('rachel@biashara.com', null, 'EMAIL-DU-PATRON');
select public.reparer_collaborateur('abi@biashara.com',    null, 'EMAIL-DU-PATRON');
```

Pour donner un autre rôle (magasinier, comptable, responsable) :

```sql
select public.reparer_collaborateur('rachel@biashara.com', 'Portes Ouvertes', null, 'MAGASINIER');
```

La fonction est réutilisable pour **tout** compte dans le même cas (ancien
collaborateur, compte créé hors application…).

## 6. Ce que le script ne fait pas

- il ne change **aucun mot de passe** ;
- il ne touche **ni à l'abonnement ni aux montants** ;
- il n'efface aucune donnée métier (ventes, stock, caisse).

---

## 7. Suite indispensable : `0142` (entreprise de chaque collaborateur)

`supabase/migrations/20260916000142_collaborateurs_entreprise_coherente.sql`

Plusieurs fonctions de création de comptes écrivaient
`entreprise_id = <identifiant du PATRON>` au lieu de
`entreprise_id = <entreprise DU PATRON>`. Les écrans qui lisent `parent_id`
continuaient de fonctionner — d'où l'impression que tout allait bien — mais
ceux qui filtrent par `entreprise_id` (espaces de la boutique, abonnement,
rapports, distribution, marketplace) ne voyaient plus ces comptes.

Le script :

1. **compte** les comptes mal rattachés ;
2. **corrige l'existant** : chaque collaborateur reprend l'entreprise de son
   patron ;
3. installe la **règle automatique** `trg_utilisateurs_rattacher_entreprise` :
   dès qu'un compte a un `parent_id`, son `entreprise_id` est celui de son
   patron — quel que soit le module qui crée le compte (Mon Équipe, Pressing,
   Distribution, plateforme) ;
4. **vérifie** : `collaborateurs_mal_rattaches` doit valoir **0** et
   `regle_active` = `true`.

> ⚠️ La règle ne remplace **jamais** une entreprise volontairement différente :
> elle ne réaligne que les valeurs vides ou égales à l'identifiant du patron.

### Déclencheur hérité `trg_utilisateurs_maj_collaborateurs`

Le script commence par sécuriser un **ancien déclencheur présent dans la base**
(créé hors migrations) dont le corps comparait un `uuid` à une chaîne vide :

```sql
v_entreprise := coalesce(
  nullif(new.entreprise_id::text, '')::uuid,
  nullif(new.parent_id, '')::uuid   -- ERROR 22P02: invalid input syntax for type uuid: ""
);
```

Toute mise à jour d'une fiche sans entreprise échouait donc (y compris la
réparation). Le script :

1. sauvegarde la définition des déclencheurs concernés ;
2. les supprime ;
3. remplace le corps par une version **NULL-SAFE**, à intention identique
   (entreprise du patron + espace par défaut, jamais une entreprise
   volontairement différente) ;
4. recrée les déclencheurs à l'identique ;
5. **liste** tous les déclencheurs restants sur `public.utilisateurs` — si un
   autre présentait la même faute, il apparaîtrait dans ce résultat.
