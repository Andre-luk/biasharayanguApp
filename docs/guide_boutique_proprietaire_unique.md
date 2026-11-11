# Boutique gérée par son seul propriétaire — parcours et création

**Public** : un commerçant qui travaille **seul** (pas de vendeur, pas de
magasinier). Objectif : qu'il puisse gérer sa boutique de bout en bout, et
savoir exactement quoi faire le premier jour.

---

## 1. Ce qui existe déjà (aucun développement nécessaire)

Le profil d'activité **« Boutique »** (`types_espaces_modules`, migration
`0027`) contient déjà les 10 modules utiles :

```
ventes · produits · stock · qr · caisse · clients · finance
employes · rapports · assistant_ia
```

Un propriétaire seul utilise les 9 premiers. Le module **`employes`** ne le
gêne pas : dès qu'il est retiré du profil, l'application **masque d'elle-même**
tout ce qui touche à l'équipe — c'est le test `ModuleCode.employes` de
`home_page.dart` (l. 1215) :

- plus de bouton « Collaborateurs » sur l'accueil ;
- plus d'entrée « Mes vendeurs » dans les paramètres ;
- l'écran **Mon Équipe** reste accessible par lien direct, mais les droits du
  propriétaire restent inchangés.

Son rôle est `PROPRIETAIRE` : il a **tous** les droits (vente, caisse,
articles, stock, clients, finance, rapports, assistant IA).

---

## 2. Le parcours de création, étape par étape (ce qu'il fait dans l'app)

### Étape 1 — Créer le compte et la boutique
Écran **Inscription** :

| Champ | Valeur |
|---|---|
| Nom | son nom (affiché à l'accueil : « Bonjour … ») |
| E-mail + mot de passe | identifiants de connexion |
| Nom de la boutique | ce qui s'imprime sur les factures |
| Type d'activité | **Boutique** |
| Mode de démarrage | **Rapide** → essai de 7 jours **actif immédiatement** |

Ce que fait le serveur (`rpc_entreprise_creer_simple`) : crée l'**entreprise**
(elle porte l'abonnement), l'**espace** de vente par défaut, et rattache le
compte comme propriétaire. Aucun collaborateur n'est nécessaire.

### Étape 2 — Renseigner sa boutique
**Paramètres → Ma boutique** : nom, adresse, téléphone, devise de travail
(CDF/USD), logo. Ces informations apparaissent sur les reçus et factures.

### Étape 3 — Créer ses articles
**Articles** : catégories puis fiches articles (nom, **prix de vente**,
**coût d'achat**, seuil d'alerte de stock). Le coût d'achat est ce qui permet
à **Finance** de calculer un vrai bénéfice (pas seulement le chiffre
d'affaires).

### Étape 4 — Entrer le stock de départ
**Stock → Approvisionnement** : la quantité réellement en rayon, avec le prix
d'achat. Sans cette entrée, la caisse refuse de vendre au-delà du stock (ou
passe en négatif selon le réglage) et les alertes de rupture sont fausses.

### Étape 5 — Ouvrir la caisse
**Caisse → Fond de caisse** : montant présent au démarrage de la journée.
C'est ce qui permet, le soir, de rapprocher espèces comptées et espèces
attendues.

### Étape 6 — Vendre
**Nouvelle vente** (ou **Scanner** pour un article étiqueté). Une vente
crédit crée automatiquement une **dette** client et **n'entre pas en caisse**
(migration `0133`) : c'est la règle qui évite de compter deux fois l'argent.

### Étape 7 — Clients et dettes
**Clients** : fiche, historique, dettes. Quand un client vient régulariser,
**Caisse → Encaisser une dette** fait entrer l'argent dans la caisse au bon
moment.

### Étape 8 — Dépenses et bénéfice
**Finance → Dépenses** (loyer, transport, salaires…) : c'est ce qui transforme
le chiffre d'affaires en résultat.

### Étape 9 — Contrôler et imprimer
- **Rapports** : ventes, marges, meilleurs articles.
- **Stock → Sorties spéciales** (perte, casse, consommation du patron,
  péremption) : le stock baisse **sans** création d'argent, avec un rapport
  imprimable pour justifier l'inventaire (migration `0132`).
- **Clôture de caisse** en fin de journée.

---

## 3. Créer un type d'activité dédié « Boutique (propriétaire seul) »

Utile si tu veux que ce profil soit proposé **directement à l'inscription**,
sans les écrans d'équipe.

### 3.1 Ajouter le profil

```sql
insert into public.types_espaces_modules (type, libelle, modules)
values (
  'boutique_solo',
  'Boutique (propriétaire seul)',
  '["ventes","produits","stock","qr","caisse","clients","finance",
    "rapports","assistant_ia"]'::jsonb
)
on conflict (type) do nothing;
```

> Aucune mise à jour de l'application n'est nécessaire : l'écran d'inscription
> lit `rpc_types_espaces_publics`, qui interroge cette table. Le nouveau type
> apparaît **immédiatement** dans la liste déroulante.
>
> La contrainte `check` figée sur `espaces.type` a été supprimée par la
> migration `0027` : un type inconnu est accepté (repli « autre » puis
> « boutique » côté modules).

### 3.2 Basculer une boutique existante

```sql
-- 1) Vérifier l'entreprise visée
select e.id, e.nom, s.id as espace_id, s.type
  from public.entreprises e
  join public.espaces s on s.entreprise_id = e.id
 where e.nom ilike '%nom de la boutique%';

-- 2) Appliquer le profil « propriétaire seul »
update public.espaces
   set type = 'boutique_solo', updated_at = now()
 where entreprise_id = (select id from public.entreprises
                         where nom ilike '%nom de la boutique%');
```

Effets immédiats, sans reconnexion forcée (le profil est relu au prochain
démarrage ou changement d'espace) :

- l'équipe disparaît de l'accueil et des paramètres ;
- tous les autres écrans restent identiques ;
- les **droits** du propriétaire ne changent pas (seul l'affichage suit
  l'activité).

### 3.3 Revenir en arrière

```sql
update public.espaces set type = 'boutique', updated_at = now()
 where entreprise_id = (select id from public.entreprises
                         where nom ilike '%nom de la boutique%');
```

---

## 4. Ce qu'il faut retenir

| Question | Réponse |
|---|---|
| Faut-il un développement pour un patron seul ? | **Non** : le profil « Boutique » suffit. |
| Peut-il embaucher plus tard ? | Oui : **Mon Équipe → Nouveau collaborateur** (migration `0140`), sans code d'invitation. |
| Que se passe-t-il s'il ne crée aucun collaborateur ? | Rien : aucun écran ne l'exige, aucune donnée n'est bloquée. |
| Peut-il tout faire seul ? | Oui : vente, caisse, stock, clients, dépenses, rapports, assistant IA. |
| Un seul appareil suffit-il ? | Oui, et les données se synchronisent dès qu'il se connecte sur un autre appareil. |

---

## 5. Pièges à éviter au démarrage

1. **Vendre avant d'avoir entré le stock** → quantités négatives et alertes
   fausses. Faire l'approvisionnement de départ d'abord.
2. **Oublier le coût d'achat** sur les articles → la marge affichée est
   fausse (elle utilise 0 par défaut).
3. **Confondre vente à crédit et encaissement** : une vente à crédit ne
   remplit pas la caisse ; c'est le règlement de la dette qui le fait.
4. **Ne pas ouvrir la caisse** (fond de caisse) → la clôture ne peut pas
   rapprocher les espèces.
5. **Changer de type d'activité sans prévenir** : le profil masque des écrans,
   mais ne supprime jamais de données. Le retour à « boutique » les réaffiche.
