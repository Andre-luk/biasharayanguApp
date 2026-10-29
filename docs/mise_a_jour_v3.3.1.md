# Mise à jour v3.3.1 — correctif de compatibilité Linux

**Version** : 3.3.1 (build 38) — voir `lib/config/app_version.dart`.
**Aucune migration SQL** : la 3.3.1 ne contient que du code.

> Cette version reprend **tout** le contenu de la 3.3.0 (distribution terrain,
> mode simple, pesée, scanner « encaisser maintenant ») et corrige un défaut
> de la compilation Linux.

---

## Le problème

Sur l'ordinateur d'essai, la version Linux 3.3.0 refusait de démarrer :

```
./biashara_yangu: CPU ISA level is lower than required
```

Cause : le lanceur compilé par GitHub exigeait le jeu d'instructions
**x86-64-v3 (AVX2)**. Le processeur concerné (Intel Celeron N4020) s'arrête à
x86-64-v2 : il possède SSE4.2 et POPCNT, mais pas AVX2.

Preuve, sur le binaire livré :

```
readelf -n biashara_yangu
  → x86 ISA needed: x86-64-baseline, x86-64-v2, x86-64-v3   (v3.3.0)
  → x86 ISA needed: x86-64-baseline                          (v3.2.0, correcte)
```

Le défaut ne venait pas du code Flutter (la bibliothèque `libflutter_linux_gtk.so`
et le code Dart `libapp.so` étaient bien en base x86-64) mais de la chaîne
d'outils de l'image de compilation, qui a changé entre deux publications.

## Ce qui est corrigé

1. **`linux/CMakeLists.txt`** impose la base `x86-64` au code natif du lanceur :

   ```cmake
   if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|amd64|AMD64")
     add_compile_options(-march=x86-64 -mtune=generic)
   endif()
   ```

   Le binaire démarre désormais sur tout processeur 64 bits, y compris les
   Celeron, Pentium récents et machines virtuelles.

2. **Image de compilation épinglée** : le job Linux utilise `ubuntu-24.04` au
   lieu de `ubuntu-latest` — l'image ne peut plus changer sous nos pieds (la
   version de la bibliothèque C requise reste ainsi connue et stable).

3. **Garde-fou dans la CI** : un contrôle `readelf` échoue AVANT la publication
   si le binaire exige `x86-64-v2`/`v3`. Un paquet inutilisable ne peut plus
   être publié.

## Ce qu'il faut faire

- **Android / Windows** : rien de particulier, réinstaller si vous le souhaitez.
- **Linux** : remplacer le dossier de l'application par le nouveau
  `biashara-yangu-linux.tar.gz` (les données utilisateur restent dans
  `~/Documents/biashara_yangu.db`, donc rien n'est perdu).
- **Base de données** : exécuter les migrations de la 3.3.0 si ce n'est pas
  déjà fait (0079, 0080, 0081).

---

**Validation avant publication** : `flutter analyze` 0 erreur ;
`flutter test` 977/977 ; binaire Linux vérifié `x86-64-baseline`.
