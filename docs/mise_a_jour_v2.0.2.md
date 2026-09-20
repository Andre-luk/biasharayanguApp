# Mise à jour v2.0.2 — notes de publication

## 🚨 Correctif définitif Linux — suppression de `window_manager`

**Symptôme** : l'application Linux se fermait brutalement (SIGSEGV) ~10 secondes
après le lancement.

**Analyse (core dump + gdb, 20/09/2026)** : le crash venait du greffon natif
`window_manager` (`libwindow_manager_plugin.so` → `gtk_widget_show`). Son
gestionnaire du signal GTK « show » s'attache à la fenêtre **dès
l'enregistrement du plugin, au démarrage** — même sans aucun appel Dart.
Impossible à contourner côté code.

**Correctif v2.0.2** : le greffon `window_manager` est **entièrement retiré**
du projet. La fenêtre est configurée nativement :

| Plateforme | Fichier | Configuration |
|---|---|---|
| Linux | `linux/runner/my_application.cc` | 1200×800, minimum 900×600, titre « Biashara Yangu » |
| Windows | `windows/runner/main.cpp` | 1200×800, titre « Biashara Yangu » |

L'icône vient du raccourci `.desktop` (Linux) et du `.ico` de l'exécutable
(Windows). Aucun changement d'interface.

> ℹ️ La v2.0.1 (premier essai de correctif) ne réglait pas le problème et a été
> retirée ; utilisez **v2.0.2**.

## 📦 Contenu cumulé (v2.0.0 → v2.0.2)

- Modules 16 C1→E : pharmacie (lots/péremption), hôtel (chambres,
  réservations, réception), restaurant (tables, commandes, cuisine),
  salle des fêtes, boulangerie, boucherie (vente au poids), variantes
  (taille/couleur/marque), **packs par modules** (Essentiel/Avancé/…)
- Notifications locales (chaque vente + rapport du soir)
- Rapports par activité + exports PDF/Excel signés (réf + empreinte)
- Imports CSV produits, journal d'audit, assistant IA (quotas)
- 🌐 **Version web** : `biashara-yangu-web.zip` (navigateur, 100 % Supabase)

## 📁 Fichiers de la release

| Fichier | Plateforme |
|---|---|
| `biashara-yangu.apk` | Android (téléphone) — signé officiellement |
| `biashara-yangu-setup.exe` | Windows — installeur |
| `biashara-yangu-windows.zip` | Windows — version portable |
| `biashara-yangu-linux.tar.gz` | Linux |
| `biashara-yangu-web.zip` | Web (navigateur) |

## 🐧 Installer sur Linux

```bash
mkdir -p ~/Applications
tar -xzf biashara-yangu-linux.tar.gz -C ~/Applications
~/Applications/biashara_yangu
```

Ou par le menu : fichier `~/.local/share/applications/biashara-yangu.desktop`
(voir `docs/publication_app.md §5`). L'application embarque SQLite
(`lib/libsqlite3.so`) — rien à installer.
