# 🏪 FICHE APKPURE — textes prêts à coller

> Remplis simplement les champs de la console développeur APKPure avec les
> textes ci-dessous. Les `[À COMPLÉTER]` sont les seules zones à personnaliser.

---

## Champs principaux

| Champ | Valeur |
|---|---|
| **Nom de l'application** | `Biashara Yangu` |
| **Nom du package** | `com.example.biashara_yangu` *(voir note ci-dessous)* |
| **Version** | `1.1.7` (versionCode `9`) — suivre les releases GitHub |
| **Catégorie** | Business (Affaires) |
| **Classification de contenu** | Tout public |
| **Email de contact** | `[À COMPLÉTER — ex. contact@biasharayangu.cd]` |
| **Site web (optionnel)** | `[À COMPLÉTER si tu as un site/page]` |
| **Politique de confidentialité** | disponible dans l'app : Paramètres → Politique & conditions |

> ⚠️ **Le nom du package ne pourra PLUS jamais changer** après la première
> publication (sinon = nouvelle application, sans mises à jour). Si tu veux un
> identifiant plus propre que `com.example.…` (ex. `cd.laperle.biasharayangu`),
> c'est **maintenant ou jamais** — dis-le avant de publier.

---

## Description courte (≤ 80 caractères)

```
Ventes, stock, clients et finances de votre commerce — simple et hors ligne.
```

## Description longue (à coller telle quelle)

```
Biashara Yangu est l'assistant complet du commerçant : encaissez en quelques
touches, suivez votre stock et vos dettes, et gardez la main sur vos finances —
même sans connexion internet stable.

CARACTÉRISTIQUES

• Ventes & caisse — encaissement rapide, panier multi-articles, détection des
  produits par QR code (scanner intégré), reçus et historique complets.
• Stock intelligent — entrées, sorties, ajustements, inventaires, alertes de
  rupture et conversions multi-unités (pièce, paquet, farde, carton).
• Clients & crédits — carnet de créances, encaissements des dettes, rappels.
• Finances claires — dépenses, caisse, bénéfices, rapports d'activité
  exportables.
• QR codes produits — étiquettes générées par l'administration, impression en
  planche multiple.
• Collaborateurs — chaque vendeur, caissier ou magasinier a son propre compte
  avec des droits adaptés à son rôle.
• Assistant IA — posez vos questions sur votre commerce (ventes du jour,
  stock faible, dettes…) et obtenez des réponses instantanées.
• Sécurité — journal d'audit détaillé, traçabilité des actions sensibles,
  données sauvegardées dans le cloud.
• Mode boutique — une interface pensée pour l'Afrique : en français,
  montants en CDF, fonctionne dans les conditions réelles du terrain.

QUI EST-CE POUR ?

Boutiques, pharmacies, hôtels, restauration, quincailleries… Toute activité qui
veut savoir, en temps réel : ce qui entre, ce qui sort, et ce qu'il reste.

DÉMARRAGE

Créez votre compte, indiquez le nom de votre commerce : l'équipe Biashara Yangu
vérifie et active votre espace (validation rapide). Vous pouvez ensuite tout
configurer : produits, prix, magasins, vendeurs.

Vos données restent les vôtres : consultation permanente, export possible,
et aucune suppression automatique.
```

## Mots-clés suggérés

```
gestion commerce, gestion de stock, caisse, point de vente, ventes,
inventaire, finance, Congo, RDC, CDF, franc congolais, NFC, QR code,
logiciel boutique, gratuit
```

---

## Captures d'écran à préparer (2 à 8)

APKPure demande des images au format **1080 × 1920** (portrait) idéalement.
Le plus simple : installe l'APK sur ton téléphone et prends des captures de :

1. Connexion / création de compte
2. Accueil (tableau de bord)
3. Caisse / nouvelle vente
4. Stock ou Articles
5. Rapports & exports
6. Mon abonnement (suivi d'activation)

> 💡 Évite les captures avec des données personnelles réelles (noms de
> clients, téléphones). Utilise une boutique de démonstration si besoin.

---

## Ce qu'il faut téléverser sur APKPure

| Fichier | Où le trouver |
|---|---|
| `biashara-yangu.apk` | Dernière release GitHub (**signée officiellement**) |
| `docs/icone_512.png` | Déjà prêt dans le projet (512×512) |
| Captures d'écran | À réaliser depuis le téléphone (voir ci-dessus) |
| Textes | Copier/coller depuis ce document |

---

## Pour chaque mise à jour future

1. Nouvelle version dans `pubspec.yaml` (`version: 1.1.8+10` — le `+10`,
   `+11`… doit **toujours augmenter**).
2. Build CI : `git tag v1.1.8 && git push origin v1.1.8`.
3. Télécharger l'APK fraîchement signé depuis la release GitHub.
4. Le téléverser sur APKPure via la même console développeur.

> La signature (keystore) et le nom du package doivent rester **identiques
> à vie** — voir `docs/publication_app.md` § 7 et § 8.
