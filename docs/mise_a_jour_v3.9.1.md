# Mise à jour v3.9.1 — partage du PDF et ouverture sur ordinateur

**Version** : 3.9.1 (55)
**Date** : 12 novembre 2026

---

## 1. Windows / Linux : « ce fichier ne contient pas d'application associée… »

### Ce qui se passait

Après une vente, l'application utilisait `Printing.sharePdf` — la fonction de
partage de la bibliothèque d'impression. Elle ne se comporte pas du tout de la
même façon selon la machine :

| Plateforme | Ce que fait `sharePdf` |
|---|---|
| Android / iOS | Ouvre la feuille de partage du système **avec le PDF joint** |
| Linux | Écrit `/tmp/facture-….pdf` puis lance `xdg-open` |
| Windows | Écrit le fichier puis lance le programme associé |

Sur un ordinateur dont l'association PDF est cassée (par exemple un
`xreader.desktop` déclaré par défaut alors que le lecteur n'est pas installé),
`xdg-open` échoue et le système affiche :

> ce fichier ne contient pas d'application associée pour effectuer cette
> action. installez une application ou, si c'est déjà fait, créer une
> association sur la page paramètres dans l'application par défaut

Le fichier restait de plus dans `/tmp`, donc perdu au redémarrage.

### Ce qui a changé

Un seul point d'entrée, `lib/utils/partage_pdf.dart` :

- **Ordinateur** : le PDF est enregistré dans
  `Téléchargements/Biashara Yangu/Factures/` (nom propre, fichier durable),
  puis ouvert avec `gio open`, sinon `xdg-open`, sinon un lecteur connu
  (`evince`, `okular`, `xreader`, `firefox`). Si aucun ne répond, le **dossier**
  s'ouvre et le chemin exact est affiché dans l'application.
- **Mobile** : feuille de partage du système avec le fichier joint (inchangé,
  c'est le comportement correct).
- **Web** : téléchargement par le navigateur.

Aucun écran n'appelle plus `Printing.sharePdf` directement : factures de vente,
factures de distribution, avoirs, reçus de pressing, bordereaux d'atelier,
rapports, rapports de sorties, étiquettes QR, factures d'abonnement et rapports
de collaborateurs passent tous par ce même chemin.

---

## 2. WhatsApp : le FICHIER, plus le texte

### Ce qui se passait

Le bouton « ENVOYER SUR WHATSAPP » ouvrait `https://wa.me/<numéro>?text=…`.
Un lien `wa.me` ne peut transporter **que du texte** : le client recevait un
message qui annonçait une facture… sans facture.

### Ce qui a changé

- **Mobile** : le PDF est joint via la feuille de partage ; l'utilisateur
  choisit WhatsApp puis le contact. Le message d'accompagnement est pré-rempli
  (nom du client, numéro de facture, montant).
- **Ordinateur** : WhatsApp Desktop n'accepte pas de pièce jointe par lien. Le
  PDF est donc enregistré, puis la conversation du client s'ouvre avec le
  message **et le chemin exact du fichier** à joindre.
- Aucun risque de double envoi : on n'ouvre plus `wa.me` après la feuille de
  partage.

---

## 3. Rappel — correctif du mode rapide (v3.9.0 → v3.9.1)

Le filtre du mode rapide ne gardait que cinq identifiants de boutique
(`products`, `distribution-pro`, `tournees`, `consignes`, `ma-tournee`) :

- aucun métier (pressing, hôtel, restaurant) → grille d'accueil **vide** ;
- `products` n'existe pas (la carte s'appelle `produits`) → même une boutique
  simple perdait sa carte Produits.

Corrigé par `CarteAccueil.pourModeRapide()` avec `idsEssentiels` / `idsMetier`,
plus cinq tests de non-régression.

---

## Pourquoi ces correctifs ne peuvent pas passer par Supabase

Les migrations SQL corrigent les **données** (profils, modules, abonnements).
Ces deux points-ci sont dans le **code de l'application** : il faut installer la
version 3.9.1 (APK Android, paquet Linux, version web) pour les recevoir.
