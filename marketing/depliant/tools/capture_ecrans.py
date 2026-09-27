#!/usr/bin/env python3
"""Capture d'écrans authentiques de Biashara Yangu (bureau Linux, X11).

Outil de fabrication du support commercial : clique dans la fenêtre de
l'application via XTEST puis capture la fenêtre au format PNG.

⚠️ Ce script ne modifie RIEN dans l'application ni dans ses données : il se
contente de naviguer entre les écrans déjà consultables par l'utilisateur
connecté (aucune création/enregistrement).

Usage :
    python3 capture_ecrans.py            # séquence complète
    python3 capture_ecrans.py --aide     # rappel des coordonnées
"""

from __future__ import annotations

import glob
import os
import subprocess
import sys
import time

from PIL import Image
from Xlib import X, display
from Xlib.ext import xtest

# ── Géométrie de la fenêtre de l'application (cliente, absolue) ──────────────
FENETRE = "Biashara Yangu"
SORTIE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "ecrans")

_display = display.Display()
_root = _display.screen().root


def _id_fenetre() -> int:
    sortie = subprocess.run(
        ["wmctrl", "-l"], capture_output=True, text=True, check=True
    ).stdout
    for ligne in sortie.splitlines():
        if FENETRE in ligne:
            return int(ligne.split()[0], 16)
    raise SystemExit(f"Fenêtre « {FENETRE} » introuvable — lancez l'application d'abord.")


def geometrie() -> tuple[int, int, int, int]:
    """(x, y, largeur, hauteur) absolus de la zone cliente."""
    infos = subprocess.run(
        ["xwininfo", "-id", hex(_id_fenetre())],
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    valeurs = {}
    for ligne in infos.splitlines():
        if ":" in ligne:
            cle, _, val = ligne.strip().partition(":")
            valeurs[cle.strip()] = val.strip()
    return (
        int(valeurs["Absolute upper-left X"]),
        int(valeurs["Absolute upper-left Y"]),
        int(valeurs["Width"]),
        int(valeurs["Height"]),
    )


def _hauteur_decoration() -> int:
    """Hauteur de la barre de titre : les captures `gnome-screenshot -w`
    incluent le cadre, la zone cliente non. Mesurée sur la dernière capture
    disponible (auto-calibrage), sinon 32 px (thème GTK par défaut)."""
    _, _, _, lh = geometrie()
    captures = glob.glob(os.path.join(os.path.abspath(SORTIE), "*.png"))
    if captures:
        with Image.open(max(captures, key=os.path.getmtime)) as im:
            decor = im.size[1] - lh
        if 0 <= decor <= 80:
            return decor
    return 32


def _origine_image() -> tuple[int, int]:
    """Origine absolue du coin supérieur gauche de l'IMAGE capturée, pour que
    les coordonnées passées à [cliquer] soient celles lues dans la capture."""
    ox, oy, _, _ = geometrie()
    return ox, oy - _hauteur_decoration()


def cliquer(x: int, y: int, pause: float = 1.6) -> None:
    """Clic gauche aux coordonnées RELATIVES À L'IMAGE de la fenêtre."""
    activer()
    ox, oy = _origine_image()
    cible_x, cible_y = ox + x, oy + y
    # Petit déplacement progressif : Flutter n'enregistre le clic qu'après
    # avoir reçu l'entrée du pointeur dans le widget.
    for etape in range(1, 4):
        _root.warp_pointer(
            ox + x * etape // 3 + 1, oy + y * etape // 3 + 1
        )
        _display.sync()
        time.sleep(0.05)
    _root.warp_pointer(cible_x, cible_y)
    _display.sync()
    time.sleep(0.35)
    xtest.fake_input(_display, X.MotionNotify, x=cible_x, y=cible_y)
    _display.sync()
    time.sleep(0.15)
    xtest.fake_input(_display, X.ButtonPress, 1)
    _display.sync()
    time.sleep(0.12)
    xtest.fake_input(_display, X.ButtonRelease, 1)
    _display.sync()
    time.sleep(pause)


def activer() -> None:
    """Donne le focus à la fenêtre (sinon le 1er clic ne sert qu'à focaliser)."""
    subprocess.run(["wmctrl", "-i", "-a", hex(_id_fenetre())], check=True)
    time.sleep(0.4)


def capture(nom: str) -> str:
    """Capture la fenêtre active (image = cadre + zone cliente)."""
    os.makedirs(SORTIE, exist_ok=True)
    chemin = os.path.abspath(os.path.join(SORTIE, f"{nom}.png"))
    activer()
    time.sleep(0.8)
    subprocess.run(["gnome-screenshot", "-w", "-f", chemin], check=True)
    print(f"  ✓ {os.path.relpath(chemin)}")
    return chemin


def redimensionner(largeur: int, hauteur: int) -> None:
    """Redimensionne la fenêtre (permet d'obtenir la mise en page compacte)."""
    ox, oy, _, _ = geometrie()
    subprocess.run(
        ["wmctrl", "-i", "-r", hex(_id_fenetre()), "-e", f"0,{ox},{oy},{largeur},{hauteur}"],
        check=True,
    )
    time.sleep(2.5)


def sequence_bureau() -> None:
    """Écrans grand écran destinés aux mockups « ordinateur »."""
    print("Captures bureau (1200 × 696) :")
    redimensionner(1200, 696)
    time.sleep(2.0)
    cliquer(200, 692)  # onglet « Accueil »
    capture("linux-accueil")
    cliquer(272, 510)  # 1re carte de statistiques de l'activité
    capture("linux-module-1")
    cliquer(60, 60)  # retour (flèche de l'AppBar)
    cliquer(600, 380)  # action rapide principale (Caisse / Nouvelle vente)
    capture("linux-caisse")
    cliquer(60, 60)  # retour
    cliquer(595, 692)  # onglet « Rapports »
    capture("linux-rapports")
    cliquer(1000, 692)  # onglet « Paramètres »
    capture("linux-parametres")
    cliquer(200, 692)  # retour à l'accueil
    time.sleep(1.5)


def sequence_mobile() -> None:
    """Même application, fenêtre étroite = mise en page « téléphone »."""
    print("Captures mise en page compacte (420 × 820) :")
    redimensionner(420, 820)
    time.sleep(2.5)
    capture("mobile-accueil")


def main() -> None:
    if "--aide" in sys.argv:
        print(__doc__)
        print("Fenêtre :", geometrie())
        return
    sequence_bureau()
    sequence_mobile()
    print("Terminé.")


if __name__ == "__main__":
    main()
