# 📦 Publier & installer l'application (APK, Linux, Windows)

> MODULE 12 — Comment obtenir les trois paquets **sans rien compiler sur ta
> machine** : GitHub compile sur ses serveurs et te donne les fichiers prêts à
> installer. Ce document dit **où** les récupérer et **comment** les installer.

---

## 1. Le principe (pourquoi tu n'as rien à compiler)

Le dépôt contient deux automatismes GitHub Actions :

| Workflow | Quand | Ce qu'il produit |
|---|---|---|
| `build-apk.yml` (existant) | à chaque `push` sur `main` | APK **debug** de test |
| `build-release.yml` (Module 12) | sur **tag `v*`** ou manuellement | APK **release** + Linux + Windows |

La compilation se fait sur les serveurs de GitHub (gratuit pour un dépôt
public), pas sur ton ordinateur.

---

## 2. OÙ RÉCUPÉRER LES FICHIERS

### Méthode A — Page « Releases » (recommandée, fichiers permanents)

1. Va sur **`https://github.com/Andre-luk/biasharayanguApp/releases`**.
2. Ouvre la dernière release (« Biashara Yangu … »).
3. Télécharge :
   - 📱 **`biashara-yangu.apk`** → téléphone Android ;
   - 🐧 **`biashara-yangu-linux.tar.gz`** → ordinateur Linux ;
   - 🪟 **`biashara-yangu-windows.zip`** → ordinateur Windows.

### Méthode B — Onglet « Actions » (conservé 30 jours)

1. **`https://github.com/Andre-luk/biasharayanguApp/actions`**.
2. Clique sur le dernier « Publier l'application (APK + Linux + Windows) » vert.
3. Section **Artifacts** → télécharge le paquet voulu.

---

## 3. COMMENT LANCER UNE PUBLICATION

### Publication automatique (tag de version)

```bash
git tag v1.0.1
git push origin v1.0.1
```

→ GitHub compile les trois paquets et crée la release `v1.0.1`.

> Avant : incrémente la version dans `pubspec.yaml`
> (`version: 1.0.1+2` — le `+2` est le numéro de build Android).

### Publication manuelle (bouton)

GitHub → **Actions** → « Publier l'application (APK + Linux + Windows) » →
**Run workflow** (le champ tag peut rester vide : un nom de test est généré).

À chaque publication, la porte de qualité est obligatoire : **analyse
statique + tous les tests** — si c'est rouge, rien n'est publié.

---

## 4. INSTALLER SUR LE TÉLÉPHONE (APK)

1. Transfère `biashara-yangu.apk` sur le téléphone (WhatsApp, Bluetooth, USB…).
2. Ouvre le fichier → Android demande d'autoriser « Installer des applications
   inconnues » pour l'application qui ouvre le fichier → accepter.
3. ⚠️ **Si une version de l'application est déjà installée** :
   - si l'APK a été signé avec **la même clé**, la mise à jour s'installe
     par-dessus ;
   - sinon (cas d'un APK de test signé « debug »), **désinstalle l'ancienne
     version d'abord** — Android refuse d'écraser une signature différente.

---

## 5. INSTALLER SUR LINUX

```bash
# 1. Extraire
tar -xzf biashara-yangu-linux.tar.gz -C biashara-yangu

# 2. (droits d'exécution — déjà présents normalement)
chmod +x biashara-yangu/biashara_yangu

# 3. Lancer
./biashara-yangu/biashara_yangu
```

⚠️ Prérequis : bibliothèques GTK3 (presque toujours présentes sur les
distributions de bureau récentes). Si erreur de bibliothèque :

```bash
sudo apt install libgtk-3-0 liblzma5        # Debian / Ubuntu
sudo dnf install gtk3 xz-libs               # Fedora
```

---

## 6. INSTALLER SUR WINDOWS

1. Clic droit sur `biashara-yangu-windows.zip` → **Extraire tout…**
   (ne pas lancer depuis l'archive).
2. Ouvrir le dossier extrait → double-cliquer **`biashara_yangu.exe`**.
3. Windows SmartScreen peut afficher « Windows a protégé votre PC » :
   **Informations complémentaires → Exécuter quand même** (l'exécutable n'est
   pas signé numériquement — voir §8 si tu veux corriger ça plus tard).

> 💡 Tout le dossier doit rester ensemble (`data/`, DLL…) : ne déplace pas
> seulement le `.exe`.

---

## 7. SIGNATURE OFFICIELLE ANDROID (obligatoire pour APKPure)

Par défaut en CI, l'APK release est **signé avec une clé debug générée
aléatoirement** : parfait pour tester, mais **inutilisable pour APKPure** —
sans clé fixe, chaque nouvelle version porterait une signature différente et
les mises à jour ne pourraient **jamais** s'installer par-dessus l'ancienne.

### A. Créer le keystore (UNE SEULE FOIS, à conserver à vie)

```bash
# Choisis un mot de passe de 6 caractères minimum — note-le dans un endroit sûr.
keytool -genkeypair -v \
  -keystore ~/Documents/keystores/biashara-upload.jks \
  -alias biashara \
  -keyalg RSA -keysize 2048 -validity 10950 \
  -dname "CN=Biashara Yangu, O=La Perle, L=Kinshasa, C=CD"
```

> ⚠️ **Ce fichier + son mot de passe = la vie de l'application.**
> Perdre ce keystore = impossible de publier des mises à jour d'une app déjà
> installée (APKPure, téléphones…). Sauvegarde-le comme la base de données
> (voir `docs/backup_restore_supabase.md`) : par exemple dans Supabase Storage
> **privé** + une copie hors ligne (clé USB).

### B. En local (pour tes builds manuels)

Copier `android/key.properties.example` → `android/key.properties` :

```properties
storePassword=TON_MOT_DE_PASSE
keyPassword=TON_MOT_DE_PASSE
keyAlias=biashara
storeFile=/home/andre/Documents/keystores/biashara-upload.jks
```

### C. En CI (GitHub) — déjà intégré au workflow ✅

Les deux étapes de signature sont **déjà en place** dans
`.github/workflows/build-release.yml` : elles s'activent automatiquement dès
que ces 4 secrets existent
(**Settings → Secrets and variables → Actions** → *New repository secret*) :

| Secret | Valeur |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 biashara-upload.jks` (coller la sortie) |
| `ANDROID_STORE_PASSWORD` | le mot de passe du keystore |
| `ANDROID_KEY_PASSWORD` | le mot de passe de la clé (souvent le même) |
| `ANDROID_KEY_ALIAS` | `biashara` |

Tant qu'ils sont absents : repli automatique sur la clé debug (le build ne
casse jamais). Une fois présents : chaque release GitHub est signée avec ta
clé officielle.

### D. Vérifier la signature d'un APK

```bash
keytool -printcert -jarfile biashara-yangu.apk
# → doit afficher « Propriétaire : CN=Biashara Yangu… », pas « Android Debug »
```

---

## 8. PUBLIER SUR APKPURE (et recevoir les mises à jour)

### A. Première publication

1. **Compte développeur** : créer un compte sur le portail développeur
   d'APKPure (bouton *Developer / Submit app* sur `apkpure.com`).
2. **Téléverser l'APK `biashara-yangu.apk`** de la dernière release GitHub
   — **signé officiellement** (section 7) et avec un `versionCode` **9 ou
   plus** (`pubspec.yaml → version: 1.1.7+9`).
3. **Remplir la fiche** : textes prêts dans `docs/apkpure_fiche.md`
   (nom, descriptions, email, catégorie), icône 512×512
   (`docs/icone_512.png`) et captures d'écran du téléphone.
4. Attendre la validation d'APKPure (quelques jours ouvrés).

### B. Chaque mise à jour (le rituel)

1. Côté projet : monter la version dans `pubspec.yaml`
   (`version: 1.1.8+10` — **le numéro après `+` doit toujours augmenter**),
   puis :
   ```bash
   git add -A && git commit -m "…" && git push
   git tag -a v1.1.8 -m "Biashara Yangu v1.1.8" && git push origin v1.1.8
   ```
2. La CI construit et publie la release GitHub (~30 min) — l'APK est signé
   avec la clé officielle (même signature que la 1ʳᵉ publication).
3. Télécharger `biashara-yangu.apk` depuis la release GitHub et le
   **téléverser sur APKPure** (même console développeur) : la mise à jour est
   proposée aux utilisateurs (~quelques heures après validation).

> ✅ Les utilisateurs retrouvent automatiquement les nouvelles versions :
> APKPure notifie/mets à jour les apps installées depuis son store, ET
> l'application affiche elle-même la version installée (Paramètres → À propos).

### C. Règles d'or pour ne jamais bloquer les mises à jour

| Règle | Pourquoi |
|---|---|
| **Même keystore à vie** | Android refuse une mise à jour signée différemment. |
| **`versionCode` strictement croissant** (`+9`, `+10`, `+11`…) | Android refuse d'installer par-dessus une version égale ou inférieure. |
| **Ne jamais changer `applicationId`** après la 1ʳᵉ publication | Sinon c'est une NOUVELLE application (l'ancienne ne se met pas à jour). |
| **Conserver le keystore + mots de passe** | Sans lui, plus aucune mise à jour possible. |

---

## 9. EN CAS DE PROBLÈME

| Symptôme | Cause probable | Solution |
|---|---|---|
| Le workflow est rouge | erreur d'analyse ou test | ouvrir le run → lire l'étape rouge → corriger puis relancer |
| Pas d'onglet « Releases » | le workflow n'a jamais été lancé | lancer par tag (`git push origin v1.0.1`) |
| « App non installée » sur Android | signature différente | désinstaller l'ancienne version puis réessayer |
| L'app Linux ne démarre pas | bibliothèque manquante | installer GTK3 / xz (voir §5) |
| Windows refuse l'exe | SmartScreen (pas de signature) | « Exécuter quand même » ; à terme, signer l'exe (certificat payant) |
| L'APK est « debug » au lieu de « release » | c'est `build-apk.yml` (le workflow de test) | utiliser le workflow « Publier l'application » (`build-release.yml`) |
| Linux : `Failed to load dynamic library 'libsqlite3.so'` | version ≤ 1.1.3 : SQLite n'était pas embarquée | ✅ corrigé en **v1.1.4** (SQLite voyage avec l'app). En attendant : `sudo apt install libsqlite3-dev`, ou sans sudo : `ln -sf /lib/x86_64-linux-gnu/libsqlite3.so.0 lib/libsqlite3.so` puis `LD_LIBRARY_PATH="$PWD/lib" ./biashara_yangu` |
