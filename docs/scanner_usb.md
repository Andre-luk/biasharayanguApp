# Lire les codes-barres avec un scanner USB externe

**Concerné :** Moss Lode 650 nm classe 1, et tout lecteur laser / LED / QR
USB ou Bluetooth du même type (Honeywell, Zebra, Datalogic, Symcode…).

---

## 1. Pourquoi il n'y a rien à installer

Un lecteur de codes-barres de ce type se présente à l'ordinateur comme un
**clavier**. Il ne transmet pas une image ni un fichier : il « tape » les
caractères du code, puis appuie sur **Entrée**.

C'est le mode **HID / clavier**, actif par défaut sur la quasi-totalité des
lecteurs. Conséquence directe :

- pas de pilote à installer ;
- pas de port COM à configurer ;
- pas d'autorisation Android à accorder ;
- le lecteur fonctionne sur Windows, Linux, macOS **et** Android (câble OTG).

Biashara Yangu écoute donc simplement le clavier de la machine et reconnaît une
**rafale de frappe** : le lecteur envoie ses caractères toutes les 5 à 30 ms,
alors qu'un humain dépasse rarement 120 ms. C'est cette différence de vitesse
qui permet de distinguer un scan d'une saisie manuelle, sans rien demander au
commerçant.

---

## 2. Vérifier le réglage du lecteur (une fois)

| Réglage | Valeur attendue | Où le vérifier |
|---|---|---|
| Mode de sortie | **Clavier / HID Keyboard** | notice du lecteur (code-barres de configuration) |
| Suffixe (fin de code) | **Entrée (CR)** | idem |
| Préfixe | aucun | idem |
| Disposition clavier | QWERTY ou AZERTY | indifférent pour les codes numériques |

> Si votre lecteur est réglé en **« port série / COM virtuel »**, aucun code
> n'apparaîtra dans l'application : scannez le code-barres de configuration
> « USB HID Keyboard » fourni dans la notice (souvent la page 2 ou 3).

---

## 3. Utilisation dans la caisse

1. Ouvrir **Caisse** (ou **Nouvelle vente**).
2. Scanner l'article. Le premier caractère capté suffit : inutile de cliquer
   dans un champ.
3. Le produit est ajouté au panier et un message confirme
   (« Eau Casino — Farde de 12 ajouté au panier »).
4. Répéter pour chaque article, puis appuyer sur **Enregistrer la vente**.

### Ce que l'application sait reconnaître

| Code lu | Interprétation |
|---|---|
| `6001234567890` | code-barres **fabricant** d'un article (EAN/UPC) |
| `6001234567891` | code-barres **fabricant d'un emballage** (farde, carton) |
| `PROD:123` | étiquette **article** imprimée par Biashara Yangu |
| `COND:<uuid>` | étiquette **format de vente** (farde de 12, carton de 24…) |
| `BAL:123:1500` | étiquette de **balance** : 1,5 kg de l'article 123 |

Tout est résolu **sur le téléphone** : la caisse vend au scanner même sans
réseau. Le serveur n'est consulté qu'en dernier recours, pour un article jamais
synchronisé sur cet appareil.

### Scanner pendant que la recherche a le focus

Si le curseur est dans le champ « Rechercher un produit », le lecteur y écrit le
code. L'application le détecte : au lieu de filtrer la liste, elle **ajoute
l'article au panier** et vide le champ. Une recherche tapée à la main
(« savon », « eau casino ») continue de fonctionner normalement.

---

## 4. Enregistrer le code-barres d'un article

Un code inconnu n'est jamais inventé : l'application affiche

> « Code 6001234567890 non reconnu. Enregistrez d'abord son code-barres sur la
> fiche de l'article. »

Pour l'enregistrer : **Articles → ouvrir la fiche → Code-barres**. Le code est
ensuite recopié sur l'appareil lors de la synchronisation et reconnu
instantanément, même hors ligne.

---

## 5. Dépannage

| Symptôme | Cause probable | Solution |
|---|---|---|
| Rien ne se passe au scan | lecteur en mode port série | scanner le code « USB HID Keyboard » de la notice |
| Le code apparaît dans un champ mais rien n'est ajouté | article inconnu de la boutique | enregistrer le code-barres sur la fiche article |
| Le code est tronqué | lecteur trop lent | scanner à nouveau ; vérifier la longueur minimale (4 caractères) |
| Deux codes collés | suffixe absent | régler le suffixe sur **Entrée (CR)** |
| Fonctionne sur PC, pas sur tablette | câble simple au lieu d'OTG | utiliser un adaptateur USB‑OTG |
| Caractères bizarres (lettres à la place des chiffres) | lecteur en AZERTY matériel sur clavier QWERTY | passer la disposition clavier du système en AZERTY, ou scanner le code de configuration de la notice |

---

## 6. Ce que l'application ne fait pas (volontairement)

- Elle ne **pilote** pas le lecteur : aucun réglage n'est écrit dans le matériel.
- Elle ne demande **aucune permission** spéciale (ni caméra, ni USB) : le
  lecteur est un clavier, pas un périphérique à appairer.
- Elle ne remplace pas le **scanner caméra** (module 7) : les deux coexistent —
  la caméra pour un téléphone, le lecteur USB pour un poste de caisse.
