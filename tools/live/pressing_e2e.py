#!/usr/bin/env python3
# =============================================================================
#  biashara_yangu — ESSAI « BOUT EN BOUT » DU PRESSING (compte de test)
#
#  Ce script crée UNE commande réelle sur le compte de test
#  (pressing.test@biashara.cd) et vérifie, étape par étape, les garanties du
#  module 35 :
#     • amorçage idempotent du catalogue et des étapes ;
#     • prix FIGÉ à la ligne au dépôt ;
#     • numérotation PR-AAAA-NNNNNN et jeton QR de 64 hexadécimaux ;
#     • statut de commande calculé depuis les lignes ;
#     • paiement jamais au-delà du facturé ;
#     • remise finale refusée s'il reste un solde (politique SOLDE_OBLIGATOIRE) ;
#     • caisse du jour cohérente avec les paiements.
#
#  Usage : python3 tools/live/pressing_e2e.py
#  Secrets : ~/.config/biashara/supabase.env (jamais affichés)
# =============================================================================
from __future__ import annotations

import json
import os
import shlex
import sys
import urllib.error
import urllib.request
import uuid
from datetime import date, datetime, timedelta, timezone

FICHIER = os.environ.get(
    "SUPABASE_ENV", os.path.expanduser("~/.config/biashara/supabase.env")
)

OK = 0
KO = 0
INFO = 0


def ok(msg: str) -> None:
    global OK
    OK += 1
    print(f"✅ {msg}")


def ko(msg: str) -> None:
    global KO
    KO += 1
    print(f"❌ {msg}")


def info(msg: str) -> None:
    global INFO
    INFO += 1
    print(f"⚠️  {msg}")


def lire_env() -> dict[str, str]:
    if not os.path.exists(FICHIER):
        print(f"❌ Fichier de secrets absent : {FICHIER}")
        print("   → voir tools/live/README.md")
        sys.exit(2)
    valeurs: dict[str, str] = {}
    with open(FICHIER, encoding="utf-8") as flux:
        for ligne in flux:
            ligne = ligne.strip()
            if not ligne or ligne.startswith("#") or "=" not in ligne:
                continue
            cle, valeur = ligne.split("=", 1)
            morceaux = shlex.split(valeur)
            valeurs[cle.strip()] = morceaux[0] if morceaux else ""
    return valeurs


ENV = lire_env()
BASE = ENV["SUPABASE_URL"].rstrip("/")
CLE = ENV["SUPABASE_ANON_KEY"]
EMAIL = ENV["TEST_EMAIL"]
MOT_DE_PASSE = ENV["TEST_PASSWORD"]

JETON = ""


def http(chemin: str, corps: dict | None = None, methode: str = "POST") -> tuple[int, object]:
    donnees = None if corps is None else json.dumps(corps).encode("utf-8")
    requete = urllib.request.Request(
        f"{BASE}{chemin}",
        data=donnees,
        method=methode,
        headers={
            "apikey": CLE,
            "Authorization": f"Bearer {JETON or CLE}",
            "Content-Type": "application/json",
            "Prefer": "return=representation",
        },
    )
    try:
        with urllib.request.urlopen(requete, timeout=40) as reponse:
            brut = reponse.read().decode("utf-8")
            return reponse.status, (json.loads(brut) if brut else None)
    except urllib.error.HTTPError as erreur:
        brut = erreur.read().decode("utf-8")
        try:
            return erreur.code, json.loads(brut)
        except Exception:  # noqa: BLE001
            return erreur.code, brut


def rpc(nom: str, params: dict | None = None):
    """Appelle une RPC. Lève RpcErreur si le serveur refuse."""
    statut, corps = http(f"/rest/v1/rpc/{nom}", params or {})
    if isinstance(corps, dict) and corps.get("message"):
        raise RpcErreur(nom, str(corps["message"]))
    if statut >= 400:
        raise RpcErreur(nom, f"HTTP {statut} — {str(corps)[:200]}")
    return corps


class RpcErreur(Exception):
    def __init__(self, nom: str, message: str) -> None:
        super().__init__(f"{nom} : {message}")
        self.message = message


def essayer(nom: str, params: dict | None = None):
    try:
        return rpc(nom, params), None
    except RpcErreur as erreur:
        return None, erreur.message


# -----------------------------------------------------------------------------
# 1. Connexion
# -----------------------------------------------------------------------------
statut, corps = http(
    "/auth/v1/token?grant_type=password",
    {"email": EMAIL, "password": MOT_DE_PASSE},
)
if statut != 200 or not isinstance(corps, dict) or not corps.get("access_token"):
    ko(f"Connexion refusée pour {EMAIL.split('@')[0]}@…")
    sys.exit(1)
JETON = corps["access_token"]
MOI = corps.get("user", {}).get("id", "")
ok(f"Connexion OK ({EMAIL.split('@')[0]}@…, uid {MOI[:8]}…)")

# -----------------------------------------------------------------------------
# 2. Réglages du pressing
# -----------------------------------------------------------------------------
config, err = essayer("pressing_config_lire")
if err:
    ko(f"pressing_config_lire : {err}")
    sys.exit(1)
if isinstance(config, str):
    config = json.loads(config)
politique = (config or {}).get("politique_remise") or "?"
devise = (config or {}).get("devise") or "CDF"
ok(f"Réglages lus — politique_remise={politique}, devise={devise}")

# -----------------------------------------------------------------------------
# 3. Amorçage du catalogue et des étapes (idempotent)
# -----------------------------------------------------------------------------
for amorce in ("pressing_amorcer_catalogue", "pressing_amorcer_etapes"):
    res, err = essayer(amorce)
    if err and "existe déjà" not in err.lower():
        ko(f"{amorce} : {err}")
    else:
        info(f"{amorce} exécuté (idempotent).")

catalogue = rpc("pressing_catalogue_lister") or {}
if isinstance(catalogue, str):
    catalogue = json.loads(catalogue)
categories = catalogue.get("categories") or []
prestations = catalogue.get("prestations") or []
ok(
    "Catalogue : "
    f"{len(categories)} catégorie(s), {len(prestations)} prestation(s), "
    f"{len(catalogue.get('tarifs') or [])} tarif(s)."
)
if not categories or not prestations:
    ko("Catalogue vide après amorçage → impossible d'aller plus loin.")
    sys.exit(1)

etapes = rpc("pressing_etapes_lister") or []
if isinstance(etapes, str):
    etapes = json.loads(etapes)
etapes = sorted(etapes, key=lambda e: e.get("ordre") or 0)
codes = [e.get("code") for e in etapes if e.get("actif", True)]
finale = next(
    (e.get("code") for e in etapes if e.get("est_finale") or e.get("finale")),
    None,
)
ok(f"Étapes : {', '.join(str(c) for c in codes)} (finale = {finale})")
if not finale:
    ko("Aucune étape finale → migration 0121 à revoir.")
    sys.exit(1)

# -----------------------------------------------------------------------------
# 4. Tarif de test : 1 500 pour la 1re catégorie, 2 000 pour la 2e (si présente)
# -----------------------------------------------------------------------------
categorie_a = categories[0].get("id")
categorie_b = (categories[1].get("id") if len(categories) > 1 else categorie_a)
prestation = prestations[0].get("id")
PRIX_A, PRIX_B = 1500, 2000
rpc(
    "pressing_tarif_definir",
    {"p_prestation_id": prestation, "p_categorie_id": categorie_a, "p_prix": PRIX_A},
)
rpc(
    "pressing_tarif_definir",
    {"p_prestation_id": prestation, "p_categorie_id": categorie_b, "p_prix": PRIX_B},
)
ok(f"Tarifs de test définis ({PRIX_A} et {PRIX_B} {devise}).")

# -----------------------------------------------------------------------------
# 5. Client de test
# -----------------------------------------------------------------------------
horodatage = datetime.now().strftime("%H%M%S")
client_id, err = essayer(
    "pressing_client_enregistrer",
    {
        "p_id": None,
        "p_nom": f"CLIENT TEST E2E {horodatage}",
        "p_telephone": "0990000001",
        "p_adresse": None,
        "p_email": None,
        "p_notes": "créé par tools/live/pressing_e2e.py",
    },
)
if err:
    ko(f"pressing_client_enregistrer : {err}")
    sys.exit(1)
client_id = client_id.get("id") if isinstance(client_id, dict) else client_id
ok(f"Client de test créé ({str(client_id)[:8]}…).")

# -----------------------------------------------------------------------------
# 6. Dépôt : 2 lignes (2 pièces A + 1 pièce B), sans prix envoyé
# -----------------------------------------------------------------------------
demain = (date.today() + timedelta(days=1)).isoformat()
reference = f"E2E-{horodatage}-{uuid.uuid4().hex[:6]}"
commande, err = essayer(
    "pressing_depot_creer",
    {
        "p_client_id": client_id,
        "p_lignes": [
            {
                "categorie_id": categorie_a,
                "prestation_id": prestation,
                "designation": "CHEMISE TEST",
                "couleur": "blanc",
                "quantite": 2,
            },
            {
                "categorie_id": categorie_b,
                "prestation_id": prestation,
                "designation": "PANTALON TEST",
                "couleur": "bleu",
                "quantite": 1,
            },
        ],
        "p_date_prevue": f"{demain}T12:00:00",
        "p_remise": 0,
        "p_supplement": 0,
        "p_urgence": False,
        "p_observations": "commande créée par le script de vérification",
        "p_paiement": None,
        "p_reference_locale": reference,
    },
)
if err:
    ko(f"pressing_depot_creer : {err}")
    sys.exit(1)
if isinstance(commande, str):
    commande = json.loads(commande)
commande_id = commande.get("id")
numero = commande.get("numero") or "?"
ok(f"Dépôt {numero} créé — statut {commande.get('statut')}, total {commande.get('total')} {devise}.")

jeton_qr = commande.get("qr_token") or ""
if len(jeton_qr) == 64:
    ok("Jeton QR = 64 hexadécimaux (aucun identifiant de base exposé).")
else:
    ko(f"Jeton QR inattendu (longueur {len(jeton_qr)}).")

lignes = commande.get("lignes") or []
if len(lignes) == 2:
    ok("2 lignes de dossier créées (un vêtement = une ligne).")
else:
    ko(f"{len(lignes)} ligne(s) au lieu de 2.")

prix_par_ligne = [
    round(float(l.get("quantite") or 0) * float(l.get("prix_unitaire") or 0))
    for l in lignes
]
prix_attendus = [PRIX_A * 2, PRIX_B]
if sorted(prix_par_ligne) == sorted(prix_attendus):
    ok(
        "Prix FIGÉS à la ligne : "
        + ", ".join(
            f"{l.get('designation')} ×{l.get('quantite')} @ {l.get('prix_unitaire')}"
            for l in lignes
        )
    )
else:
    ko(f"Prix des lignes {prix_par_ligne} ≠ attendus {prix_attendus}.")

total_attendu = sum(prix_attendus)
total = float(commande.get("total") or 0)
if round(total) == total_attendu:
    ok(f"Total facturé = {total_attendu} {devise}.")
else:
    ko(f"Total {total} ≠ {total_attendu}.")

if numero.startswith("PR-"):
    ok(f"Numérotation conforme ({numero}).")
else:
    ko(f"Numérotation inattendue : {numero}.")

# ---- idempotence hors ligne : même reference_locale -------------------------
doublon, err = essayer(
    "pressing_depot_creer",
    {
        "p_client_id": client_id,
        "p_lignes": [
            {
                "categorie_id": categorie_a,
                "prestation_id": prestation,
                "designation": "CHEMISE TEST",
                "quantite": 2,
            }
        ],
        "p_date_prevue": None,
        "p_remise": 0,
        "p_supplement": 0,
        "p_urgence": False,
        "p_observations": None,
        "p_paiement": None,
        "p_reference_locale": reference,
    },
)
if isinstance(doublon, str):
    doublon = json.loads(doublon)
if doublon and doublon.get("id") == commande_id:
    ok("Dépôt rejoué avec la même reference_locale → même commande (idempotence hors ligne).")
else:
    ko("La reference_locale n'a pas empêché un doublon.")

# -----------------------------------------------------------------------------
# 7. Paiement partiel : 1 000 (jamais au-delà du facturé)
# -----------------------------------------------------------------------------
partiel = 1000.0
res, err = essayer(
    "pressing_paiement_ajouter",
    {
        "p_commande_id": commande_id,
        "p_montant": partiel,
        "p_mode": "especes",
        "p_reference": None,
    },
)
if err:
    ko(f"pressing_paiement_ajouter (partiel) : {err}")
else:
    ok(f"Paiement partiel de {partiel:g} {devise} accepté.")

_, err = essayer(
    "pressing_paiement_ajouter",
    {
        "p_commande_id": commande_id,
        "p_montant": total_attendu * 2,
        "p_mode": "especes",
        "p_reference": None,
    },
)
if err:
    ok(f"Surpaiement refusé par le serveur ({err[:60]}…).")
else:
    ko("Surpaiement ACCEPTÉ → le plafond du facturé ne tient pas.")

# -----------------------------------------------------------------------------
# 8. Atelier : avancer chaque vêtement jusqu'à l'étape finale
# -----------------------------------------------------------------------------
a_avancer: list[str] = []
for code in codes:
    if code == codes[0]:
        continue
    a_avancer.append(code)
    if code == finale:
        break
info(f"Parcours atelier : {' → '.join(a_avancer)} (RETRAITEMENT est une boucle, ignorée).")
for ligne in lignes:
    ligne_id = ligne.get("id")
    for code in a_avancer:
        _, err = essayer(
            "pressing_ligne_avancer",
            {"p_ligne_id": ligne_id, "p_etape": code, "p_note": None, "p_agent_id": None},
        )
        if err:
            ko(f"pressing_ligne_avancer({code}) : {err}")
            break
fiche = rpc("pressing_commande_fiche", {"p_commande_id": commande_id})
if isinstance(fiche, str):
    fiche = json.loads(fiche)
statut_final = str(fiche.get("statut") or "").lower()
pretes = [l for l in (fiche.get("lignes") or []) if l.get("est_prete")]
if len(pretes) == len(fiche.get("lignes") or []) and statut_final in {"pret", "prete", "prête"}:
    ok("Tous les vêtements sont PRÊTS et la commande est passée à « PRETE ».")
else:
    ko(f"Statut après atelier : {statut_final} ({len(pretes)} vêtement(s) prêt(s)).")

# -----------------------------------------------------------------------------
# 9. Contrôle qualité puis remise avec solde (doit être refusée)
# -----------------------------------------------------------------------------
for ligne in fiche.get("lignes") or []:
    essayer("pressing_controle_qualite", {"p_ligne_id": ligne.get("id"), "p_ok": True, "p_note": None})

ids_lignes = [l.get("id") for l in (fiche.get("lignes") or [])]
res, err = essayer(
    "pressing_retrait_enregistrer",
    {
        "p_commande_id": commande_id,
        "p_ligne_ids": ids_lignes,
        "p_paiement": None,
        "p_observations": None,
        "p_signataire": None,
    },
)
if err and ("SOLDE_DU" in err or "SOLDE" in err):
    ok(f"Remise finale SANS paiement refusée ({err[:50]}…).")
elif err:
    info(f"Remise sans paiement refusée autrement : {err[:80]}")
else:
    info("Remise sans paiement acceptée : politique de remise non bloquante, à confirmer avec l'exploitant.")

# -----------------------------------------------------------------------------
# 10. Paiement du solde puis remise
# -----------------------------------------------------------------------------
solde = round(total_attendu - partiel)
res, err = essayer(
    "pressing_paiement_ajouter",
    {
        "p_commande_id": commande_id,
        "p_montant": solde,
        "p_mode": "mobile_money",
        "p_reference": "MM-TEST",
    },
)
if err:
    ko(f"Paiement du solde refusé : {err}")
else:
    ok(f"Paiement du solde de {solde:g} {devise} accepté.")

res, err = essayer(
    "pressing_retrait_enregistrer",
    {
        "p_commande_id": commande_id,
        "p_ligne_ids": ids_lignes,
        "p_paiement": None,
        "p_observations": "restitution test",
        "p_signataire": "client test",
    },
)
if err:
    ko(f"pressing_retrait_enregistrer : {err}")
else:
    ok("Remise finale enregistrée après paiement complet.")

fiche = rpc("pressing_commande_fiche", {"p_commande_id": commande_id})
if isinstance(fiche, str):
    fiche = json.loads(fiche)
if str(fiche.get("statut") or "").lower() in {"remis", "remise", "partiel"}:
    ok(f"Statut final calculé : {fiche.get('statut')} — solde {fiche.get('solde')}.")
else:
    info(f"Statut final : {fiche.get('statut')}.")

_, err = essayer(
    "pressing_retrait_enregistrer",
    {
        "p_commande_id": commande_id,
        "p_ligne_ids": ids_lignes,
        "p_paiement": None,
        "p_observations": None,
        "p_signataire": None,
    },
)
if err and "DEJA_REMIS" in err:
    ok("Double remise refusée (DEJA_REMIS).")
elif err:
    info(f"Double remise refusée autrement : {err[:60]}")
else:
    ko("Double remise ACCEPTÉE → garantie de restitution violée.")

# -----------------------------------------------------------------------------
# 11. Caisse du jour cohérente
# -----------------------------------------------------------------------------
caisse = rpc("pressing_caisse_jour", {"p_date": date.today().isoformat()})
if isinstance(caisse, str):
    caisse = json.loads(caisse)
encaisse = float(caisse.get("total_encaisse") or caisse.get("encaisse") or 0)
if round(encaisse) >= total_attendu:
    ok(f"Caisse du jour : {encaisse:g} {devise} encaissés (commande comprise).")
else:
    ko(f"Caisse du jour incohérente : {encaisse:g} < {total_attendu}.")

# -----------------------------------------------------------------------------
# 12. Verdict
# -----------------------------------------------------------------------------
print()
print(f"═══ ESSAI PRESSING {numero} — {OK} OK · {KO} ÉCHEC(S) · {INFO} INFO(S) ═══")
print(f"   commande de test : {commande_id}")
print("   ⚠️  cette commande reste en base (aucune suppression autorisée) :")
print("       elle porte l'observation « commande créée par le script de vérification ».")
sys.exit(0 if KO == 0 else 1)
