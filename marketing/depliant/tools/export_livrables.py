#!/usr/bin/env python3
"""Fabrique les livrables du dépliant Biashara Yangu.

Produit, à partir de `depliant.html` :
  • le PDF imprimable A4 paysage (2 faces) ;
  • les images de chaque face (300 ppp) et des 6 volets ;
  • les images « web » (JPEG) et la page numérique responsive ;
  • une copie complète dans ~/Téléchargements/Biashara-Yangu-Depliant.

Usage :  python3 tools/export_livrables.py
"""

from __future__ import annotations

import glob
import os
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

RACINE = Path(__file__).resolve().parents[1]          # marketing/depliant
HTML = RACINE / "depliant.html"
PDF = RACINE / "depliant-biashara-yangu.pdf"
TMP = Path("/tmp/depliant_export")
DEST = Path.home() / "Téléchargements" / "Biashara-Yangu-Depliant"

# A4 paysage : 297 × 210 mm — 3 volets de 99 mm
LARGEUR_MM, HAUTEUR_MM = 297.0, 209.0
VOLET_MM = 99.0

VOLETS = [
    ("1-le-constat", 0),
    ("2-les-fonctions", 1),
    ("3-couverture", 2),
    ("4-les-metiers", 0),
    ("5-multiplateforme", 1),
    ("6-contact", 2),
]



def executer(commande: list[str], **kw) -> None:
    """Exécute une commande en s'arrêtant en cas d'erreur."""
    resultat = subprocess.run(commande, capture_output=True, text=True, **kw)
    if resultat.returncode != 0 and "written to file" not in resultat.stderr:
        print("ÉCHEC :", " ".join(commande[:3]), file=sys.stderr)
        print(resultat.stderr[-800:], file=sys.stderr)
        raise SystemExit(1)


def chrome(*arguments: str) -> None:
    executer(
        [
            "google-chrome",
            "--headless=new",
            "--no-sandbox",
            "--disable-gpu",
            "--no-pdf-header-footer",
            *arguments,
        ]
    )


def construire_pdf() -> None:
    print("2. PDF imprimable…")
    chrome(f"--print-to-pdf={PDF}", HTML.as_uri())
    pages = subprocess.run(
        ["pdfinfo", str(PDF)], capture_output=True, text=True
    ).stdout
    nb = next(
        (l.split()[-1] for l in pages.splitlines() if l.startswith("Pages:")), "?"
    )
    taille = next(
        (l.split(":", 1)[1].strip() for l in pages.splitlines() if "Page size" in l),
        "?",
    )
    print(f"   → {PDF.name} : {nb} pages, {taille}")
    if nb != "2":
        raise SystemExit("⚠️ Le PDF doit contenir exactement 2 pages.")


def rasteriser(dpi: int) -> list[Path]:
    """Convertit le PDF en PNG (une image par face)."""
    if TMP.exists():
        shutil.rmtree(TMP)
    TMP.mkdir(parents=True)
    executer(["pdftoppm", "-r", str(dpi), "-png", str(PDF), str(TMP / "face")])
    return sorted(TMP.glob("face-*.png"))


def images_faces(dpi: int = 300) -> list[Path]:
    print(f"3. Images des faces ({dpi} ppp)…")
    dossiers = RACINE / "images"
    dossiers.mkdir(exist_ok=True)
    faces = rasteriser(dpi)
    sorties = []
    for index, source in enumerate(faces, start=1):
        cible = dossiers / f"face-{index}-{'recto' if index == 1 else 'verso'}.png"
        shutil.copyfile(source, cible)
        with Image.open(cible) as im:
            print(f"   → {cible.name} : {im.width} × {im.height} px ({(im.width/(LARGEUR_MM/25.4)):.0f} ppp)")
        sorties.append(cible)
    return sorties


def images_volets(faces: list[Path]) -> None:
    """Découpe chaque face en 3 volets de 99 mm (6 volets au total)."""
    print("3. Images des volets…")
    dossier = RACINE / "images" / "volets"
    dossier.mkdir(parents=True, exist_ok=True)
    for numero_face, source in enumerate(faces, start=1):
        groupe = VOLETS[:3] if numero_face == 1 else VOLETS[3:]
        with Image.open(source) as im:
            largeur_volet_px = im.width * VOLET_MM / LARGEUR_MM
            for nom, colonne in groupe:
                gauche = int(round(largeur_volet_px * colonne))
                droite = int(round(min(gauche + largeur_volet_px, im.width)))
                cible = dossier / f"face{numero_face}-volet{nom}.png"
                im.crop((gauche, 0, droite, im.height)).save(cible)
                print(f"   → {cible.name} (colonne {colonne + 1})")


def images_web(faces: list[Path]) -> list[Path]:
    print("4. Images web (JPEG)…")
    dossier = RACINE / "images" / "web"
    dossier.mkdir(parents=True, exist_ok=True)
    sorties = []
    for index, source in enumerate(faces, start=1):
        with Image.open(source).convert("RGB") as im:
            hauteur = int(im.height * 1700 / im.width)
            cible = dossier / f"face-{index}.jpg"
            im.resize((1700, hauteur), Image.LANCZOS).save(
                cible, quality=88, optimize=True, progressive=True
            )
            print(f"   → {cible.name} ({cible.stat().st_size // 1024} Ko)")
            sorties.append(cible)
    return sorties


def page_numerique(faces_web: list[Path]) -> Path:
    """Page responsive à ouvrir sur ordinateur, tablette ou téléphone."""
    print("5. Version numérique responsive…")
    cible = RACINE / "depliant-numerique.html"
    cible.write_text(
        f"""<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Biashara Yangu — dépliant commercial</title>
<meta name="description" content="Biashara Yangu : une seule application pour vendre, encaisser et piloter votre commerce. Android, Windows, Linux et Web.">
<style>
:root{{
  --marine:#1F3864; --marine-p:#16294A; --orange:#F08A4B; --encre:#151A23;
  --gris:#5A6478; --carte:#fff; --fond:#EEF2F9;
}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{
  font-family:'Noto Sans','Segoe UI',Roboto,Arial,sans-serif;color:var(--encre);
  background:var(--fond);line-height:1.55;-webkit-font-smoothing:antialiased;
}}
header{{
  background:linear-gradient(135deg,var(--marine-p),var(--marine) 55%,#2E5AA8);
  color:#fff;padding:34px 22px 30px;
}}
.enveloppe{{max-width:1080px;margin:0 auto;display:flex;gap:18px;align-items:center;flex-wrap:wrap}}
header img{{width:74px;height:74px;border-radius:16px;background:#fff;padding:6px;object-fit:contain}}
h1{{font-size:clamp(22px,4.4vw,34px);font-weight:800;letter-spacing:-.02em}}
.slogan{{color:#C9D5EC;font-size:clamp(14px,2.4vw,18px);margin-top:4px}}
.etiquettes{{display:flex;gap:8px;flex-wrap:wrap;margin-top:14px}}
.etiquettes span{{
  background:rgba(240,138,75,.18);color:#FFD9BD;border:.5pt solid rgba(240,138,75,.45);
  padding:4px 11px;border-radius:999px;font-size:12.5px;font-weight:700;
}}
main{{max-width:1080px;margin:0 auto;padding:26px 18px 60px}}
.intro{{background:var(--carte);border-radius:16px;padding:20px 22px;box-shadow:0 10px 30px rgba(21,42,74,.08);margin-bottom:22px}}
.intro h2{{color:var(--marine);font-size:19px;margin-bottom:8px}}
.intro p{{color:#2C3444;font-size:15px}}
.faces{{display:flex;flex-direction:column;gap:26px}}
.face{{background:var(--carte);border-radius:16px;overflow:hidden;box-shadow:0 10px 30px rgba(21,42,74,.10)}}
.face figcaption{{
  display:flex;justify-content:space-between;gap:12px;align-items:baseline;
  padding:13px 18px;border-bottom:1px solid #E3E7F0;font-size:13px;color:var(--gris)
}}
.face figcaption b{{color:var(--marine);font-size:14.5px}}
.face img{{display:block;width:100%;height:auto}}
.actions{{display:flex;flex-wrap:wrap;gap:12px;margin:28px 0 6px}}
a.bouton{{
  text-decoration:none;font-weight:700;font-size:15px;border-radius:12px;padding:13px 20px;
  display:inline-flex;align-items:center;gap:9px;
}}
a.principale{{background:var(--orange);color:#231006}}
a.secondaire{{background:var(--marine);color:#fff}}
a.lien{{background:#fff;color:var(--marine);border:1px solid #D7DEF0}}
.infos{{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:16px;margin-top:26px}}
.carte{{background:var(--carte);border-radius:14px;padding:18px;box-shadow:0 8px 22px rgba(21,42,74,.07)}}
.carte h3{{color:var(--marine);font-size:14px;letter-spacing:.06em;text-transform:uppercase;margin-bottom:7px}}
.carte p{{font-size:14.5px;color:#2C3444}}
footer{{color:#4A5468;font-size:12.5px;text-align:center;padding:22px 18px 40px;line-height:1.7}}
@media print{{
  header,footer,.actions,.intro{{display:none}}
  main{{padding:0;max-width:none}} .faces{{gap:0}} .face{{box-shadow:none;border-radius:0}}
  .face figcaption{{display:none}} .face{{break-after:page;page-break-after:always}}
}}
</style>
</head>
<body>
<header>
  <div class="enveloppe">
    <img src="assets/logo-biashara.png" alt="Logo Biashara Yangu">
    <div>
      <h1>Biashara Yangu</h1>
      <div class="slogan">Une seule application pour <b>vendre</b>, <b>encaisser</b> et
        <b>piloter</b> votre commerce.</div>
      <div class="etiquettes">
        <span>Android</span><span>Windows</span><span>Linux</span><span>Web</span>
        <span>11 activités</span><span>Montants en CDF ou USD</span>
      </div>
    </div>
  </div>
</header>

<main>
  <section class="intro">
    <h2>Le cahier ne suffit plus.</h2>
    <p>Biashara Yangu réunit les ventes, les articles, le stock, la caisse, les dettes, les
      dépenses et les rapports dans une seule application, en français. Chaque activité
      (boutique, hôtel, pharmacie, restaurant, salle des fêtes, boulangerie, boucherie,
      mode…) dispose de ses propres écrans, et l’équipe de 8 rôles travaille avec des
      permissions précises et un journal d’audit.</p>
  </section>

  <div class="faces">
    <figure class="face">
      <figcaption><b>Face 1 — recto</b><span>Volet 1 : le constat · Volet 2 : les fonctions · Volet 3 : couverture</span></figcaption>
      <img src="images/web/face-1.jpg" alt="Face 1 du dépliant : constat, fonctions et couverture" loading="lazy">
    </figure>
    <figure class="face">
      <figcaption><b>Face 2 — verso</b><span>Volet 4 : les métiers · Volet 5 : multiplateforme · Volet 6 : contact</span></figcaption>
      <img src="images/web/face-2.jpg" alt="Face 2 du dépliant : activités, plateformes et contact" loading="lazy">
    </figure>
  </div>

  <div class="actions">
    <a class="bouton principale" href="https://wa.me/243974084668">Demander une démonstration</a>
    <a class="bouton secondaire" href="mailto:andrelukengu67@gmail.com?subject=Démonstration%20Biashara%20Yangu">Écrire un e-mail</a>
    <a class="bouton lien" href="Biashara-Yangu-Depliant-A4.pdf" download>Télécharger le PDF imprimable</a>
  </div>

  <section class="infos">
    <div class="carte"><h3>WhatsApp</h3><p>+243 974 084 668</p></div>
    <div class="carte"><h3>E-mail</h3><p>andrelukengu67@gmail.com<br>support@biasharayangu.cd</p></div>
    <div class="carte"><h3>Éditeur</h3><p>Biashara Tech — Lubumbashi, Haut-Katanga,<br>République démocratique du Congo</p></div>
    <div class="carte"><h3>Version présentée</h3><p>Biashara Yangu 2.1.3 — Android, Windows, Linux, Web</p></div>
  </section>
</main>

<footer>
  Biashara Yangu — version 2.1.3. Édité par <b>Biashara Tech</b>, Lubumbashi (RDC).
  Développement : Andre Lukengu. Collaborateur marketing : La Perle Corp.<br>
  © 2026 Biashara Tech — tous droits réservés.
</footer>
</body>
</html>
""",
        encoding="utf-8",
    )
    print(f"   → {cible.name}")
    return cible


LISEZ_MOI = """BIASHARA YANGU — DÉPLIANT COMMERCIAL
====================================
Dossier créé automatiquement depuis le projet (dossier « marketing/depliant »).
Aucun fichier de l'application n'a été modifié.

CONTENU
-------
1. Biashara-Yangu-Depliant-A4.pdf
   Dépliant prêt à imprimer : A4 PAYSAGE, 2 faces (recto / verso), 3 volets.
   • Format fini : 297 × 210 mm — 3 volets de 99 × 210 mm
   • Plis verticaux à 99 mm et 198 mm (repères imprimés, discrets)
   • Marges de sécurité de 9 mm : aucun texte ne traverse un pli

2. Biashara-Yangu-Depliant.html
   Le même dépliant en HTML/CSS (source du PDF) : ouvrez-le dans un
   navigateur, la barre du haut permet de MASQUER les repères de pliage
   avant impression. Dossier « assets/ » à conserver à côté du fichier.

3. Biashara-Yangu-Depliant-numerique.html
   Version numérique responsive (ordinateur, tablette, téléphone) avec les
   liens cliquables : WhatsApp, e-mail, téléchargement du PDF.

4. images/
   • face-1-recto.png / face-2-verso.png — les deux faces en 300 ppp
   • volets/ — les 6 volets séparés (utile pour les réseaux sociaux)
   • web/ — versions JPEG allégées pour le web et les e-mails

5. captures/ — captures d'écran authentiques faites sur l'application réelle
   (Linux et version Web) : accueil, chambres d'hôtel, rapports, paramètres,
   connexion, création de compte.

IMPRESSION (imprimeur ou imprimante de bureau)
----------------------------------------------
• Papier : A4, 210 g/m² couché mat (idéal) — 135 g/m² minimum
• Orientation : PAYSAGE
• Échelle : 100 % (NE PAS cocher « ajuster à la page »)
• Recto-verso : « retourner sur les BORDS COURTS » (relire au dos)
• Marges : aucune / bordure minimale
• Couleurs : activer « imprimer les graphismes d'arrière-plan »
• Fichier à fournir : Biashara-Yangu-Depliant-A4.pdf
• Repères de pliage : pour une impression sans traits, ouvrir le HTML,
  cliquer sur « Repères de pliage : on / off » puis imprimer depuis le
  navigateur.

PLIAGE (dépliant 3 volets, fermeture à droite)
----------------------------------------------
1. Poser la face 1 (recto) devant soi.
2. Plier le long du repère à 99 mm, puis à 198 mm (accordéon).
3. Le volet 3 (couverture) doit rester à l'extérieur une fois plié :
   plier d'abord le volet 1 vers l'intérieur, puis rabattre la couverture.

CONTACTS UTILISÉS DANS LE DÉPLIANT (issus du projet)
----------------------------------------------------
• WhatsApp : +243 974 084 668      • E-mail : andrelukengu67@gmail.com
• Support : support@biasharayangu.cd
• Éditeur : Biashara Tech — Lubumbashi, Haut-Katanga, RDC
• QR code du volet contact : https://wa.me/243974084668
"""


def copier_livrables(faces: list[Path], web: list[Path], numerique: Path) -> None:
    print("7. Copie dans les Téléchargements…")
    DEST.mkdir(parents=True, exist_ok=True)
    for sous_dossier in ("images", "images/volets", "images/web", "captures", "assets"):
        (DEST / sous_dossier).mkdir(parents=True, exist_ok=True)

    shutil.copyfile(PDF, DEST / "Biashara-Yangu-Depliant-A4.pdf")
    shutil.copyfile(HTML, DEST / "Biashara-Yangu-Depliant.html")
    shutil.copyfile(numerique, DEST / "Biashara-Yangu-Depliant-numerique.html")
    for source in faces:
        shutil.copyfile(source, DEST / "images" / source.name)

    for source in glob.glob(str(RACINE / "images" / "volets" / "*.png")):
        shutil.copyfile(source, DEST / "images" / "volets" / os.path.basename(source))
    for source in web:
        shutil.copyfile(source, DEST / "images" / "web" / source.name)
    for source in glob.glob(str(RACINE / "assets" / "ecrans" / "*.png")):
        shutil.copyfile(source, DEST / "captures" / os.path.basename(source))
    shutil.copyfile(RACINE / "images" / "partage-social.png", DEST / "images" / "partage-social.png")
    shutil.copytree(RACINE / "assets", DEST / "assets", dirs_exist_ok=True)

    (DEST / "LISEZ-MOI.txt").write_text(LISEZ_MOI, encoding="utf-8")
    print(f"   → {DEST}")


def apercu_contact() -> None:
    """Miniature carrée pour les réseaux sociaux (carte de visite rapide)."""
    dossier = RACINE / "images"
    with Image.open(dossier / "face-1-recto.png") as source:
        im = source.convert("RGB")
        largeur = 1200
        hauteur = int(im.height * largeur / im.width)
        im = im.resize((largeur, hauteur), Image.LANCZOS)
        image = Image.new("RGB", (1200, 630), "#16294A")
        image.paste(im, (0, (630 - hauteur) // 2))
        trait = ImageDraw.Draw(image)
        trait.rectangle((0, 0, 1200, 630), outline="#F08A4B", width=6)
        try:
            police = ImageFont.truetype(
                "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 26
            )
        except OSError:  # pragma: no cover
            police = ImageFont.load_default()
        trait.text(
            (24, 590),
            "Biashara Yangu 2.1.3  ·  WhatsApp +243 974 084 668",
            fill="#FFFFFF",
            font=police,
        )
        cible = dossier / "partage-social.png"
        image.save(cible)
        print(f"   → {cible.name}")


def main() -> None:
    construire_pdf()
    faces = images_faces()
    images_volets(faces)
    web = images_web(faces)
    numerique = page_numerique(web)
    apercu_contact()
    copier_livrables(faces, web, numerique)
    print("\nLivrables prêts.")


if __name__ == "__main__":
    main()
