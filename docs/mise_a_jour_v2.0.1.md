# Mise à jour v2.0.1 — notes de publication

## 🚨 Correctif important (Linux)

L'application Linux pouvait **se fermer brutalement (SIGSEGV)** quelques
secondes après le lancement. Cause identifiée par analyse du core dump :
le greffon `window_manager` (v0.2.5) plantait dans `gtk_widget_show` sur les
GTK récents, au moment d'afficher la fenêtre.

**Correctif** : `window_manager` n'est plus utilisé sur Linux. La fenêtre est
configurée nativement (taille 1200×800, minimum 900×600, titre
« Biashara Yangu ») et l'icône vient du raccourci du menu. Windows/macOS ne
changent pas.

## 🌐 Version web

Premier paquet navigateur publié : `biashara-yangu-web.zip`. Sur le web,
l'application fonctionne entièrement en ligne avec Supabase (pas de base
SQLite locale dans un navigateur) ; les exports PDF/Excel et les QR codes se
téléchargent via le navigateur.

## 📦 Contenu cumulé (v2.0.0 → v2.0.1)

- Modules 16 C1→E : pharmacie (lots/péremption), hôtel (chambres,
  réservations, réception), restaurant (tables, commandes, cuisine),
  salle des fêtes, boulangerie, boucherie (vente au poids), variantes
  (taille/couleur/marque), **packs par modules** (Essentiel/Avancé/…)
- Notifications locales (chaque vente + rapport du soir)
- Rapports par activité + exports PDF/Excel signés (réf + empreinte)
- Imports CSV produits, journal d'audit, assistant IA (quotas)

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

Ou via le menu : créez `~/.local/share/applications/biashara-yangu.desktop`
(voir `docs/publication_app.md §5`). L'application embarque SQLite
(`lib/libsqlite3.so`) — rien à installer.
