#!/usr/bin/env python3
"""
Génère les icônes du site web (favicon, PWA, Apple, écran de démarrage)
à partir du logo officiel de l'application.

Source : assets/Biashara_app_off-.png (emblème + texte « BIASHARA YANGU MOBILE »).
On isole l'EMBLÈME (le cercle avec le caddie et le téléphone) : un favicon
de 32 px ne peut pas afficher du texte, et un texte illisible fait amateur.

Usage :
    python3 tools/generer_icones_web.py
"""
from __future__ import annotations

import os
from PIL import Image

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(RACINE, "assets", "Biashara_app_off-.png")
WEB = os.path.join(RACINE, "web")

BLANC = (255, 255, 255, 255)


def embleme() -> Image.Image:
    """Découpe l'emblème (partie haute) et le recadre au carré."""
    im = Image.open(SOURCE).convert("RGBA")
    largeur, hauteur = im.size
    # Le texte occupe le bas de l'image : on ne garde que la partie haute.
    im = im.crop((0, 0, largeur, int(hauteur * 0.80)))
    # Recadrage sur le contenu réel (le pourtour est blanc).
    boite = im.convert("RGB").point(lambda v: 255 if v < 245 else 0).getbbox()
    if boite:
        im = im.crop(boite)
    # Mise au carré sans déformer.
    cote = max(im.size)
    carre = Image.new("RGBA", (cote, cote), (0, 0, 0, 0))
    carre.paste(im, ((cote - im.width) // 2, (cote - im.height) // 2), im)
    return carre


def sur_fond(im: Image.Image, taille: int, marge: float) -> Image.Image:
    """Place l'emblème sur un carré blanc avec une marge relative."""
    interieur = int(taille * (1 - 2 * marge))
    redim = im.copy()
    redim.thumbnail((interieur, interieur), Image.LANCZOS)
    fond = Image.new("RGBA", (taille, taille), BLANC)
    fond.paste(
        redim,
        ((taille - redim.width) // 2, (taille - redim.height) // 2),
        redim,
    )
    return fond


def ecrire(im: Image.Image, chemin: str) -> None:
    os.makedirs(os.path.dirname(chemin), exist_ok=True)
    im.save(chemin, optimize=True)
    print(f"  ✅ {os.path.relpath(chemin, RACINE)} — {im.size[0]}×{im.size[1]}")


def main() -> None:
    base = embleme()
    print("Icônes web depuis", os.path.relpath(SOURCE, RACINE))

    # Favicon : petit, mais avec un peu d'air pour rester lisible.
    ecrire(sur_fond(base, 64, 0.04), os.path.join(WEB, "favicon.png"))

    # Icônes PWA « classiques » (bord blanc fin).
    for taille in (192, 512):
        ecrire(sur_fond(base, taille, 0.04),
               os.path.join(WEB, "icons", f"Icon-{taille}.png"))

    # Icônes « maskable » : zone de sécurité de 20 % (Android rogne les bords).
    for taille in (192, 512):
        ecrire(sur_fond(base, taille, 0.14),
               os.path.join(WEB, "icons", f"Icon-maskable-{taille}.png"))

    # iOS : l'icône d'écran d'accueil.
    ecrire(sur_fond(base, 180, 0.04), os.path.join(WEB, "apple-touch-icon.png"))

    # Écran de démarrage Flutter (splash) : même emblème, 4 densités.
    for densite in (1, 2, 3, 4):
        ecrire(sur_fond(base, 125 * densite, 0.10),
               os.path.join(WEB, "splash", "img", f"light-{densite}x.png"))
        ecrire(sur_fond(base, 125 * densite, 0.10),
               os.path.join(WEB, "splash", "img", f"dark-{densite}x.png"))

    print("Terminé.")


if __name__ == "__main__":
    main()
