# Mise à jour v1.6.0 — notes prêtes pour Uptodown / APKPure 📝

> **Quand l'utiliser** : dès que la fiche Uptodown sera approuvée (ou pour APKPure).
> L'APK signé se télécharge dans la release GitHub : `Releases → v1.6.0 → biashara-yangu.apk`.
> Rituel complet : voir `docs/publication_app.md` §8.
> ℹ️ Cette note **cumule** toutes les nouveautés depuis la v1.3.0 (notifications) : si la
> version publiée sur le store est antérieure, une seule mise à jour suffit.

---

## Fiche technique

| Champ | Valeur |
|---|---|
| Version | **1.6.0** (versionCode 15) |
| Nouveautés | voir textes ci-dessous |
| APK | `biashara-yangu.apk` — signé officiellement |

---

## Nouveautés de la version (texte FR — copier-coller)

```
💊 NOUVEAU — Mode Pharmacie (lots & péremption)
• Fiche article enrichie : numéro de lot + date d'expiration.
• Écran « Expirations » : produits expirés et proches de la péremption, triés par urgence.
• Alerte dans le rapport de fin de journée (« 💊 Expirations : X expirés • Y bientôt »).
• Nouveau rapport « Expirations » (export PDF/Excel) pour les pharmacies.
• Sécurité : la vente d'un produit expiré est bloquée (option configurable).

🧩 NOUVEAU — Application multi-activités
• Le tableau de bord s'adapte à votre activité : un hôtel, un restaurant ou une
  pharmacie ne voit que les cartes utiles à son métier.
• L'administrateur peut créer de nouveaux « Types d'activités » (ex. salon de coiffure)
  et choisir leurs modules en 2 minutes.

🔔 Rappels des nouveautés précédentes
• Une notification à chaque vente encaissée.
• Rapport de fin de journée automatique (heure configurable dans Paramètres).

📊 Rapports
• Rapports fiabilisés (ventes, dépenses, caisse, produits les plus vendus).
• Renommés « Rapports de l'entreprise » — adaptés à toutes les activités.

🛡️ Corrections importantes
• Création de compte fiabilisée ; activation des abonnements opérationnelle.
• Ventes de plusieurs articles corrigées.
```

---

## Étapes (rappel rapide — publication de la mise à jour)

1. Console Uptodown (ou APKPure) → **Ajouter une nouvelle version** / *Upload update*
2. Fichier : `biashara-yangu.apk` (release GitHub v1.6.0) — même signature officielle → accepté en mise à jour
3. Notes de version : coller le texte ci-dessus
4. Ne PAS cocher « Disable downloading older versions » (déjà accepté) — ne rien changer d'autre
5. Valider → la vérification par leur équipe peut prendre quelques heures

> ℹ️ Les abonnements/achats in-app restent les mêmes ; aucun changement de politique de confidentialité (même URL : https://andre-luk.github.io/biasharayangu-legal/).
