#!/usr/bin/env python3
# ============================================================================
#  BIASHARA YANGU — lecture d'un code-barres avec la caméra de l'ordinateur
#  Dossier : tools/lire_code_barre.py
#  ---------------------------------------------------------------------------
#  POURQUOI CET OUTIL EXISTE
#  -------------------------
#  L'application ne peut PAS lire de code-barres avec une caméra sur
#  ordinateur : le plugin `mobile_scanner` (pubspec.yaml) ne déclare que
#  `android`, `ios`, `macos` et `web`. Il n'existe aucune version Linux ni
#  Windows — vérifiable dans ~/.pub-cache/.../mobile_scanner-*/pubspec.yaml, et
#  dans le paquet Linux publié, où aucun fichier `mobile_scanner*.so`
#  n'apparaît.
#
#  Sur ordinateur, la lecture par caméra passe donc par cet outil, qui :
#    1. prend une photo avec la caméra du poste (`streamer`) ;
#    2. y cherche les codes-barres (`zxing-cpp`) ;
#    3. affiche les numéros trouvés et leur format.
#
#  Le numéro obtenu sert ensuite à créer l'article dans l'application (ou à
#  retrouver un article existant). L'outil NE MODIFIE RIEN : il lit.
#
#  INSTALLATION (environnement isolé, rien n'est installé dans le système)
#  ----------------------------------------------------------------------
#    python3 -m venv /tmp/barcode-venv
#    /tmp/barcode-venv/bin/pip install zxing-cpp
#
#  UTILISATION
#  -----------
#    /tmp/barcode-venv/bin/python tools/lire_code_barre.py
#    /tmp/barcode-venv/bin/python tools/lire_code_barre.py --essais 10
#    /tmp/barcode-venv/bin/python tools/lire_code_barre.py --device /dev/video1
#
#  ⚠️ La personne qui tient le code-barres doit le présenter BIEN À PLAT, à
#  15-25 cm, dans une lumière correcte. L'outil essaie plusieurs fois : c'est
#  en répétant qu'on obtient une lecture nette.
# ============================================================================

import argparse
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def capturer(device: str, sortie: Path, largeur: int, hauteur: int) -> bool:
    """Une photo de la caméra. `streamer` est le seul outil vraiment répandu.

    ⚠️ L'EXTENSION DOIT ÊTRE `.jpeg`. `streamer` en déduit le format de
    sortie : avec `.jpg`, il échoue sur
    « neither audio nor video format specified/found » et ne produit AUCUNE
    image — un message qui parle de l'audio et de la vidéo, alors que le
    problème est le suffixe du fichier. Constaté en testant.
    """
    if shutil.which("streamer") is None:
        print("❌ `streamer` introuvable. Installez-le (paquet `streamer`) ou "
              "adaptez cette fonction à votre webcam.", file=sys.stderr)
        return False

    resultat = subprocess.run(
        ["streamer", "-c", device, "-t", "1",
         "-s", f"{largeur}x{hauteur}", "-o", str(sortie)],
        capture_output=True, text=True, timeout=30,
    )
    return resultat.returncode == 0 and sortie.exists() and sortie.stat().st_size > 0


def decoder(chemin: Path) -> list[tuple[str, str]]:
    """Les codes-barres de l'image : (texte, format)."""
    import zxingcpp
    from PIL import Image

    image = Image.open(chemin)
    trouves = zxingcpp.read_barcodes(image)
    return [(r.text, str(r.format)) for r in trouves if r.text]


def main() -> int:
    analyseur = argparse.ArgumentParser(
        description="Lit un code-barres avec la caméra de l'ordinateur.")
    analyseur.add_argument("--device", default="/dev/video0",
                           help="périphérique caméra (défaut : /dev/video0)")
    analyseur.add_argument("--essais", type=int, default=8,
                           help="nombre de photos à essayer (défaut : 8)")
    analyseur.add_argument("--pause", type=float, default=1.2,
                           help="secondes entre deux photos (défaut : 1.2)")
    analyseur.add_argument("--largeur", type=int, default=1280)
    analyseur.add_argument("--hauteur", type=int, default=720)
    analyseur.add_argument("--garder", metavar="DOSSIER",
                           help="conserver les photos dans ce dossier")
    arguments = analyseur.parse_args()

    dossier = Path(arguments.garder) if arguments.garder else None
    if dossier:
        dossier.mkdir(parents=True, exist_ok=True)

    print(f"📷 Caméra {arguments.device} — {arguments.essais} tentative(s).")
    print("   Présentez le code-barres bien à plat, à 15-25 cm, en pleine "
          "lumière.\n")

    with tempfile.TemporaryDirectory() as temporaire:
        for tentative in range(1, arguments.essais + 1):
            photo = Path(temporaire) / f"prise-{tentative}.jpeg"

            if not capturer(arguments.device, photo, arguments.largeur,
                            arguments.hauteur):
                print(f"  tentative {tentative} : la caméra n'a rien donné")
                continue

            if dossier:
                shutil.copy(photo, dossier / photo.name)

            try:
                codes = decoder(photo)
            except Exception as erreur:                      # noqa: BLE001
                print(f"❌ Décodage impossible : {erreur}", file=sys.stderr)
                return 2

            if codes:
                print("✅ CODE-BARRES LU :\n")
                for texte, format_ in codes:
                    print(f"   numéro : {texte}")
                    print(f"   format : {format_}")
                    print(f"   photo  : {photo if not dossier else dossier / photo.name}")
                print()
                return 0

            print(f"  tentative {tentative} : rien de lisible "
                  "(rapprochez, aplatissez, éclairez)")

            if tentative < arguments.essais:
                time.sleep(arguments.pause)

    print("\n❌ Aucun code-barres lu après "
          f"{arguments.essais} tentative(s).")
    print("   Conseils : aplatir le code, éviter les reflets, éclairer "
          "franchement, remplir au moins la moitié de l'image.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
