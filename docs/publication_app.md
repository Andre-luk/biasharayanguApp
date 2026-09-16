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

## 7. SIGNATURE OFFICIELLE ANDROID (pour plus tard)

Par défaut en CI, l'APK release est **signé avec la clé debug** : parfait pour
tester, mais il ne pourra pas remplacer une installation déjà distribuée avec
une autre signature.

Pour signer officiellement :

```bash
# 1. Créer un keystore (une seule fois — CONSERVE-LE précieusement !)
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias upload
```

2. En local : copier `android/key.properties.example` → `android/key.properties`
   et renseigner les valeurs (le fichier est ignoré par git).
3. En CI : créer les secrets GitHub
   (**Settings → Secrets and variables → Actions**) :
   `ANDROID_KEYSTORE_BASE64` (le `.jks` en base64 : `base64 -w0 upload-keystore.jks`),
   `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`,
   puis décommenter le bloc correspondant dans `.github/workflows/build-release.yml`.

> ⚠️ **Perdre ce keystore = impossible de mettre à jour l'application** sur les
> téléphones où elle est déjà installée. Sauvegarde-le comme la base de
> données elle-même (voir `docs/backup_restore_supabase.md`).

---

## 8. EN CAS DE PROBLÈME

| Symptôme | Cause probable | Solution |
|---|---|---|
| Le workflow est rouge | erreur d'analyse ou test | ouvrir le run → lire l'étape rouge → corriger puis relancer |
| Pas d'onglet « Releases » | le workflow n'a jamais été lancé | lancer par tag (`git push origin v1.0.1`) |
| « App non installée » sur Android | signature différente | désinstaller l'ancienne version puis réessayer |
| L'app Linux ne démarre pas | bibliothèque manquante | installer GTK3 / xz (voir §5) |
| Windows refuse l'exe | SmartScreen (pas de signature) | « Exécuter quand même » ; à terme, signer l'exe (certificat payant) |
| L'APK est « debug » au lieu de « release » | c'est `build-apk.yml` (le workflow de test) | utiliser le workflow « Publier l'application » (`build-release.yml`) |
