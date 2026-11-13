# Correctif — plus de téléchargement automatique de la facture (Windows)

Date : 14/11/2026 · Aucune migration SQL · Concerne toutes les plateformes,
Windows en premier.

## 1. Le problème signalé

Après chaque vente, l'application générait la facture PDF **toute seule** :

1. elle l'écrivait dans « Téléchargements/Biashara Yangu/Factures » ;
2. puis elle **ouvrait** le fichier (`cmd /c start`, `open`, `xdg-open`).

Sous Windows — et sur tout poste sans lecteur PDF associé — cela déclenchait :

> « Ce fichier ne contient pas l'application associée pour effectuer cette
> action. Installez une application ou, si c'est déjà fait, créez une
> association sur la page Paramètres des applications par défaut. »

L'utilisateur devait fermer ce message **après chaque vente**, et la facture
lui échappait.

## 2. Ce qui a été changé

| Fichier | Avant | Après |
|---|---|---|
| `lib/pages/vente_confirmation_page.dart` | `initState()` → `_proposerFactureAutomatiquement()` → PDF écrit **et ouvert** | plus rien d'automatique ; bouton **« FACTURE — PDF / WHATSAPP »** |
| `lib/pages/new_sale_page.dart` | après la vente : `telecharger(facture)` puis feuille d'actions | feuille d'actions directement, sans écriture de fichier |
| `lib/utils/partage_pdf_native.dart` | ordinateur : enregistre **puis ouvre** (avec repli sur des lecteurs connus puis le dossier) | ordinateur : **enregistre seulement**, n'ouvre plus jamais tout seul |
| `lib/widgets/actions_facture.dart` | libellé « TÉLÉCHARGER / PARTAGER LE PDF », paramètre `telechargeeAutomatiquement` | « **TÉLÉCHARGER LA FACTURE (PDF)** » + « **ENVOYER SUR WHATSAPP** » + « IMPRIMER » + « **OUVRIR LE DOSSIER** » (dossier, jamais le fichier) |

Le téléchargement et le partage WhatsApp restent donc **disponibles et
complets**, mais **à la demande**.

## 3. Comportement par plateforme

| Plateforme | « TÉLÉCHARGER LA FACTURE (PDF) » | « ENVOYER SUR WHATSAPP » |
|---|---|---|
| Android / iOS | feuille de partage système avec le **PDF joint** (WhatsApp y figure) | même feuille de partage, message du client pré-rempli → l'agent choisit WhatsApp et le contact, le fichier part réellement |
| Windows / Linux / macOS | fichier enregistré dans `Téléchargements/Biashara Yangu/Factures` **sans être ouvert** ; le chemin s'affiche, bouton « ouvrir le dossier » | fichier enregistré, puis `wa.me` s'ouvre avec le message + le chemin du PDF à joindre (WhatsApp Desktop n'accepte pas de pièce jointe par lien) |
| Web | téléchargement par le navigateur | ouverture de `wa.me` avec le message ; le PDF reste dans les téléchargements du navigateur |

> Pourquoi ne pas ouvrir le PDF nous-mêmes ? Parce qu'un poste sans lecteur
> PDF associé ne peut pas l'ouvrir : c'est exactement l'origine du message
> Windows. Ouvrir le **dossier** est toujours possible et ne dépend d'aucune
> association de fichiers.

## 4. Ce qui n'a pas changé

- la facture A4 elle-même (en-tête établissement, lignes, réglages de prix,
  cadeaux, statut payé/crédit/partiel) ;
- la numérotation `VTE-AAAAMJJ-NNNN` ;
- l'impression (`Printing.layoutPdf`) ;
- l'envoi WhatsApp du **fichier** sur mobile, et le lien `wa.me` sur ordinateur.

## 5. Vérification

1. Caisse → valider une vente : **aucun fichier ne s'ouvre**, aucune fenêtre
   Windows ; la feuille « Facture » s'affiche.
2. « TÉLÉCHARGER LA FACTURE (PDF) » → message « PDF enregistré dans
   « Téléchargements/Biashara Yangu/Factures » : … ».
3. « OUVRIR LE DOSSIER » → l'explorateur s'ouvre sur le fichier (aucun message
   d'application associée).
4. « ENVOYER SUR WHATSAPP » → saisie du numéro, puis WhatsApp s'ouvre avec le
   message et le chemin du PDF à joindre.
5. Écran « Vente enregistrée » → bouton « FACTURE — PDF / WHATSAPP » ouvre la
   même feuille.

Les autres documents (avoir, reçu de pressing, rapports, QR) profitent du même
correctif : eux non plus ne sont plus ouverts automatiquement.
