# Mise à jour v2.9.0 — Créer un compte complet, et des rôles verrouillés

**Version :** 2.9.0 (build 33)
**Migrations SQL :** `20260916000072` → `20260916000075`
*(à exécuter dans l'ordre ; le programme SQL fait partie de l'installation)*
**Tests :** 891/891 ✅

---

## En une phrase

**Créer une entreprise crée désormais aussi le compte de son propriétaire, la
validation par code ouvre le compte toute seule — et plus personne ne peut
s'attribuer un rôle qu'il n'a pas.**

---

## Les quatre nouveautés de cette version

### 1. Créer une entreprise **avec** son propriétaire

Avant, la plateforme créait une **entreprise vide** : le patron devait
s'inscrire lui-même ensuite, et rien ne reliait officiellement les deux. Un
seul écran fait maintenant les trois choses dans l'ordre du travail :

1. **l'entreprise** — nom, ville, activité, environnement ;
2. **le pack** — grille tarifaire, **prix d'installation** (il comprend le
   premier mois), **prix mensuel**, durée d'essai ;
3. **le propriétaire** — nom, e-mail, téléphone, mot de passe : son compte est
   créé dans la foulée et rattaché à l'entreprise.

Tout part en **une seule opération serveur** : si une seule validation échoue,
**rien** n'est créé — jamais d'entreprise sans patron. Et l'on sait désormais
**qui** a créé le compte (agent de terrain, gestionnaire des comptes, Super
Administrateur) : le suivi des apporteurs existe.

### 2. La fiche unique — abonnement, installation, suivi, avance

Abonnement, prix d'installation, prix mensuel, suivi du dossier (étape, dates,
jours restants, qui a vérifié et validé) et **toute l'avance encaissée** sont
rassemblés sur **un seul écran**, alimenté par un seul appel. Le **propriétaire**
**et le créateur** du compte y figurent, avec un bouton pour ajuster les deux
prix d'un compte existant.

### 3. Le code de la Finance ouvre le compte automatiquement

C'était le maillon manquant : l'agent activait, attendait le code… et le compte
restait bloqué en « en attente de validation », sans que personne ne comprenne
pourquoi. Désormais, **dès que la Finance émet le code, le compte est ouvert** :
statut « Essai », **échéance à +7 jours**, responsable de l'ouverture tracé. Le
paiement (avance, solde, renouvellement) reste un geste distinct, qui prolonge.

### 4. Rôles verrouillés — plus d'administrateur par surprise

L'écran « Ajouter un utilisateur » proposait « Administrateur » à tout le monde,
y compris à un agent — or « Administrateur » **était** le Super Administrateur.
Trois protections sont maintenant en place :

- la liste des rôles proposés **dépend de celui qui crée** : on ne donne jamais
  plus de droits que les siens, et un rôle de la plateforme n'est attribuable
  que par un Super Administrateur ;
- **personne ne peut modifier son propre rôle** ;
- le **serveur refuse** de son côté toute attribution non autorisée, quel que
  soit le chemin — y compris un rôle glissé dans une inscription. C'est ce
  refus, et non l'écran, qui fait foi.

### Et aussi

- **Assistant IA** : un bouton de retour au tableau de bord. Ouvert depuis la
  carte d'accueil, l'assistant remplaçait tout l'écran et il n'existait aucun
  moyen d'en sortir.
- **Alerte de péremption réglable par entreprise** (détail ci-dessous).

---

## Le problème que ça règle

Jusqu'ici, l'application prévenait « quand il reste 30 jours ou moins ». C'est un
compromis, et il ne convient à personne :

- une **pharmacie** qui vend des sirops à longue conservation veut être prévenue
  **60 ou 90 jours** avant, pour avoir le temps d'écouler le lot ;
- une **boutique** qui vend du lait, du yaourt ou du pain rassis doit être
  prévenue **3 à 7 jours** avant, sinon l'alerte arrive quand le produit est déjà
  invendable ;
- un **dépôt de boissons** vit sur des mois, pas sur des semaines.

Trois métiers, un seul chiffre : forcément mauvais pour deux d'entre eux. Le
délai est désormais un **réglage d'entreprise**.

---

## Ce qui change pour vous

### ⚙️ Régler le délai

**Paramètres → Alerte de péremption.**

- choix rapides : **7 / 15 / 30 / 60 / 90 jours** ;
- ou **valeur libre**, de **1 à 365 jours** ;
- valeur par défaut : **30 jours** (rien ne change si vous ne touchez à rien).

Le réglage est **par entreprise** : si vous gérez une pharmacie et une
alimentation avec le même compte, chacune garde son propre délai.

> 💡 **Conseil de départ.** Du plus périssable au plus stable :
> pain / produits frais : **3 à 7 j** · yaourts, lait, charcuterie : **7 à 15 j**
> · pharmacie courante : **30 j** · produits à longue conservation : **60 à 90 j**.

### 🏷️ Un seul seuil, partout

Changer le délai modifie **les cinq affichages d'un coup** :

| Où | Ce que vous voyez |
|---|---|
| Fiche / carte article | Le **badge** de péremption (rouge si expiré, orange si dans le délai) |
| Accueil, carte **Expirations** | Le **compteur** de produits à surveiller |
| **Notifications** | Le nombre d'alertes de péremption |
| Écran **Expirations** | Les **filtres** et le **tri par urgence** |
| Formulaire article | Le **bandeau** d'avertissement pendant la saisie |

Aucun risque d'incohérence : ces écrans ne recalculent plus chacun dans leur
coin, ils lisent tous le délai en vigueur.

### 🎯 Le seuil compte le jour même

Avec un délai de 30 jours, un produit qui expire **exactement dans 30 jours est
déjà signalé**. C'est volontaire : un seuil qui exclut son propre jour fait
perdre une journée entière — précisément celle où il faut agir.

### 🛑 Ce que le délai ne change pas

Le **blocage de vente** reste fondé sur la **date réelle**, pas sur le délai
d'alerte. Un produit signalé « bientôt périmé » **reste vendable** jusqu'à sa
vraie date d'expiration — on vous prévient, on ne vous empêche pas de travailler.

---

## À faire de votre côté

**Exécutez les migrations, dans cet ordre** (Supabase → SQL Editor → *Run*).
Elles sont **toutes idempotentes** : les relancer n'a aucun effet de bord.

| Migration | Ce qu'elle apporte |
|---|---|
| `20260916000072` | Le délai d'alerte de péremption réglable par entreprise |
| `20260916000073` | Le lien propriétaire / créateur + la fiche unique |
| `20260916000074` | Le garde-fou des rôles (⚠️ sécurise les comptes : à exécuter) |
| `20260916000075` | L'émission du code par la Finance ouvre le compte |

La 72 ajoute :

- la colonne `entreprises.alerte_peremption_jours` (`integer`, non nulle,
  **30** par défaut) — vos données existantes ne bougent pas ;
- la contrainte `entreprises_alerte_peremption_plage` (**1 à 365**) : une
  valeur aberrante est refusée par la base, pas seulement par l'écran ;
- `rpc_peremption_config(uuid)` : lire le délai en vigueur ;
- `rpc_peremption_definir_delai(integer, uuid)` : le régler (réservé au
  **propriétaire** de l'entreprise) ;
- une entrée `PEREMPTION_DELAI` de niveau **MOYEN** dans le journal d'audit :
  chaque changement de délai est **tracé, avec qui l'a fait et quand**.

Les 73, 74 et 75 ont déjà été exécutées et vérifiées sur la base de
production.

> ⚠️ **Sans ces migrations**, l'application reste utilisable : elle retombe
> proprement sur ses valeurs par défaut au lieu de tomber en panne. Mais les
> nouveaux écrans (création complète, fiche) et le réglage du délai ne seront
> pas disponibles.

**Aucune réinstallation n'est nécessaire** si vous avez déjà la 2.8.0.

---

## Sous le capot (pour le technique)

- `lib/services/peremption_service.dart` — lecture/écriture du délai, mise en
  cache, et traduction des erreurs serveur en messages lisibles (base non
  migrée, droits insuffisants, valeur hors bornes). Un message d'erreur n'est
  jamais présenté comme une panne.
- `lib/models/statut_expiration.dart` — `statutExpirationSelon(jours)` et
  `estUrgentSelon(jours)` remplacent le seuil constant.
- `lib/services/notification_service.dart` — le compteur lisait `<= 30` **en
  dur** : il utilise désormais le délai de l'entreprise.
- `test/peremption_test.dart` — 21 tests : délai par entreprise, seuil inclusif,
  statuts, tri par urgence, messages d'erreur, cache.

### Deux bogues trouvés en écrivant cette version

1. **Fragilité aux changements d'heure.** Le test du seuil inclusif a révélé que
   `DateTime(y, m, j).add(Duration(days: n))` traverse une transition horaire et
   retombe sur **J-1 ou J+1**. Le calcul de statut se fait désormais sur des
   dates **UTC**, et l'aide de test utilise la normalisation du quantième
   (`DateTime(y, m, j + n)`). Un test qui échoue peut donc désigner le test
   lui-même : il faut corriger le bon des deux.
2. **Six erreurs de compilation masquées.** Un `dart analyze lib | tail -10`
   affichait 183 avertissements et cachait **6 erreurs** derrière eux (le total
   était en réalité à 189). La ligne rouge du projet — **183 problèmes,
   0 erreur** — se vérifie donc sur le **total comparé à la référence**, jamais
   sur la fin de la sortie.
