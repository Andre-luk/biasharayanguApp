#!/usr/bin/env python3
# tools/guide_vers_pdf.py
#
# 📄 Convertit un guide Markdown (docs/*.md) en PDF lisible et imprimable.
#
# Outils utilisés : `python3 -m markdown` (extensions tables + toc) puis
# Google Chrome en mode « headless » (--print-to-pdf). Aucun accès réseau.
#
# Usage :
#   python3 tools/guide_vers_pdf.py docs/guide_module_pharmacie_complet.md
#   → docs/guide_module_pharmacie_complet.html + .pdf

import os
import subprocess
import sys
import tempfile

import markdown

CSS = """
@page { size: A4; margin: 16mm 14mm 18mm 14mm; }
body {
  font-family: "DejaVu Sans", "Liberation Sans", Arial, sans-serif;
  font-size: 10.5pt; line-height: 1.45; color: #111;
}
h1 { font-size: 20pt; color: #065f46; border-bottom: 2px solid #065f46;
     padding-bottom: 4px; margin-top: 0; }
h2 { font-size: 14pt; color: #065f46; margin-top: 18px;
     border-bottom: 1px solid #d1d5db; padding-bottom: 2px; }
h3 { font-size: 11.5pt; color: #111827; margin-top: 14px; }
p, li { font-size: 10.5pt; }
ul, ol { margin: 4px 0 8px 18px; padding: 0; }
table { border-collapse: collapse; width: 100%; margin: 8px 0 12px; }
th { background: #065f46; color: #fff; font-size: 9.5pt;
     text-align: left; padding: 5px 6px; border: 1px solid #065f46; }
td { font-size: 9.5pt; padding: 4px 6px; border: 1px solid #cbd5e1;
     vertical-align: top; }
tr:nth-child(even) td { background: #f3f4f6; }
code, pre { font-family: "DejaVu Sans Mono", monospace; font-size: 9pt; }
pre { background: #f8fafc; border: 1px solid #cbd5e1; border-radius: 4px;
      padding: 8px; white-space: pre-wrap; page-break-inside: avoid; }
blockquote { margin: 8px 0; padding: 6px 10px; background: #fef9c3;
             border-left: 4px solid #ca8a04; font-size: 10pt; }
hr { border: none; border-top: 1px solid #e5e7eb; margin: 14px 0; }
h2, h3 { page-break-after: avoid; }
table, pre, blockquote { page-break-inside: avoid; }
"""

HTML = """<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<title>{titre}</title><style>{css}</style></head>
<body>{corps}</body></html>
"""


def convertir(md_path: str) -> tuple[str, str]:
    with open(md_path, encoding='utf-8') as f:
        texte = f.read()

    corps = markdown.markdown(
        texte,
        extensions=['tables', 'fenced_code', 'toc', 'sane_lists'],
    )

    titre = os.path.splitext(os.path.basename(md_path))[0]
    html_path = os.path.splitext(md_path)[0] + '.html'
    pdf_path = os.path.splitext(md_path)[0] + '.pdf'

    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(HTML.format(titre=titre, css=CSS, corps=corps))

    with tempfile.TemporaryDirectory() as profil:
        commande = [
            'google-chrome', '--headless=new', '--disable-gpu',
            '--no-sandbox', '--no-pdf-header-footer',
            f'--user-data-dir={profil}',
            f'--print-to-pdf={pdf_path}',
            'file://' + os.path.abspath(html_path),
        ]
        subprocess.run(commande, check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)

    return html_path, pdf_path


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage : python3 tools/guide_vers_pdf.py <fichier.md>')
        raise SystemExit(2)
    html, pdf = convertir(sys.argv[1])
    print('HTML :', html)
    print('PDF  :', pdf, f'({os.path.getsize(pdf) // 1024} Ko)')
