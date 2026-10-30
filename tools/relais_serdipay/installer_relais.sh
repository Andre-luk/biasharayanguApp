#!/usr/bin/env bash
# ============================================================================
#  BIASHARA YANGU — RELAIS À IP FIXE POUR SERDIPAY
#  ---------------------------------------------------------------------------
#  À exécuter SUR UN VPS UBUNTU 22.04 / 24.04 FRAIS (en root ou via sudo).
#
#  Rôle du relais :
#    1. ENTRANT  — SerdiPay appelle https://<hote>/functions/v1/serdipay/webhook
#       → Caddy termine le TLS et transmet la requête TELLE QUELLE (corps brut
#       préservé : indispensable au calcul de la signature HMAC) à l'Edge
#       Function Supabase. Le relais n'expose QUE ce chemin.
#    2. SORTANT (option --sortant) — les appels de la passerelle vers l'API
#       SerdiPay passent par https://<hote>/api/… : ils sortent donc avec
#       l'IP fixe du VPS. Il suffit alors de régler
#       SERDIPAY_BASE_URL = https://<hote>/api
#
#  Le nom d'hôte : si vous n'avez PAS de domaine, le script utilise
#  `<ip>.nip.io` — un nom public qui résout automatiquement vers l'IP du VPS.
#  Caddy obtient alors un vrai certificat Let's Encrypt : SerdiPay a une URL
#  HTTPS valide ET une IP fixe. Aucun achat de domaine n'est nécessaire.
#
#  Usage :
#     sudo bash installer_relais.sh                 # entrant seul
#     sudo bash installer_relais.sh mon.domaine.cd  # avec votre domaine
#     sudo bash installer_relais.sh --sortant       # entrant + sortant
#     sudo bash installer_relais.sh mon.domaine.cd --sortant
#
#  ⚠️ Ouvrez les ports 80 et 443 dans le PARE-FEU DU FOURNISSEUR (security
#     group / réseau cloud) : sans cela, Let's Encrypt ne valide pas le
#     certificat et SerdiPay reçoit une erreur TLS.
# ============================================================================
set -euo pipefail

DOMAINE=""
SORTANT="non"
for arg in "$@"; do
  case "$arg" in
    --sortant) SORTANT="oui" ;;
    -*) echo "Option inconnue : $arg" >&2; exit 2 ;;
    *)  DOMAINE="$arg" ;;
  esac
done

if [[ "$(id -u)" -ne 0 ]]; then
  echo "❌ Lancez ce script avec sudo." >&2
  exit 1
fi

# --- 1. IP publique du VPS --------------------------------------------------
IP_PUBLIQUE="$(curl -4 -s --max-time 15 https://api.ipify.org || true)"
if [[ -z "$IP_PUBLIQUE" ]]; then
  echo "❌ Impossible de déterminer l'IP publique (pas d'accès Internet ?)." >&2
  exit 1
fi
HOTE="${DOMAINE:-${IP_PUBLIQUE}.nip.io}"

echo "┌──────────────────────────────────────────────────────────────"
echo "│ IP fixe du relais : $IP_PUBLIQUE"
echo "│ Nom d'hôte        : $HOTE"
echo "│ Mode sortant      : $SORTANT"
echo "└──────────────────────────────────────────────────────────────"
echo

# --- 2. Paquets -------------------------------------------------------------
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates debian-keyring debian-archive-keyring \
  apt-transport-https gnupg ufw >/dev/null

if ! command -v caddy >/dev/null 2>&1; then
  echo "→ Installation de Caddy…"
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
    | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
    > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy >/dev/null
fi

# --- 3. Configuration Caddy -------------------------------------------------
echo "→ Configuration du relais…"
cat > /etc/caddy/Caddyfile <<CADDY
# ============================================================================
#  Relais à IP fixe — Biashara Yangu <-> SerdiPay
#  Généré par tools/relais_serdipay/installer_relais.sh
#  Ne JAMAIS élargir les chemins exposés : ce relais ne doit servir qu'à
#  SerdiPay, pas de proxy général vers Supabase.
# ============================================================================
${HOTE} {
	# Pas de compression : elle réécrirait le corps et casserait le HMAC.
	encode text/plain

	# ---- ENTRANT : webhooks SerdiPay -> Edge Function Supabase ----
	@serdipay path /functions/v1/serdipay/*
	handle @serdipay {
		reverse_proxy https://pqzcliibocndiyqbyddr.supabase.co {
			# Supabase route sur le Host : il DOIT rester celui du projet.
			header_up Host pqzcliibocndiyqbyddr.supabase.co
			header_up X-Forwarded-For {remote_host}
			transport http {
				dial_timeout 5s
				response_header_timeout 20s
			}
		}
	}
$( [[ "$SORTANT" == "oui" ]] && cat <<'SORTANT'
	# ---- SORTANT : la passerelle appelle l'API SerdiPay par ici ----
	# SERDIPAY_BASE_URL = https://<hote>/api
	handle /api/* {
		uri strip_prefix /api
		reverse_proxy https://public-apis.services.serdipay.com {
			header_up Host public-apis.services.serdipay.com
			transport http {
				dial_timeout 10s
				response_header_timeout 60s
			}
		}
	}
SORTANT
)

	handle {
		respond "Not found" 404
	}

	# Journaux SANS corps de requête (aucune donnée de paiement sur disque).
	log {
		output file /var/log/caddy/serdipay-access.log {
			roll_size 20mb
			roll_keep 5
		}
	}
}
CADDY

mkdir -p /var/log/caddy
chown -R caddy:caddy /var/log/caddy 2>/dev/null || true
caddy validate --config /etc/caddy/Caddyfile >/dev/null
systemctl restart caddy
systemctl enable caddy >/dev/null 2>&1 || true

# --- 4. Pare-feu ------------------------------------------------------------
echo "→ Pare-feu (SSH, HTTP, HTTPS)…"
ufw allow 22/tcp   >/dev/null
ufw allow 80/tcp   >/dev/null
ufw allow 443/tcp  >/dev/null
yes | ufw enable   >/dev/null 2>&1 || true

# --- 5. Vérification --------------------------------------------------------
echo "→ Vérification (le certificat peut demander 20 à 60 s)…"
URL_WEBHOOK="https://${HOTE}/functions/v1/serdipay/webhook"
OK="non"
for i in $(seq 1 12); do
  REP="$(curl -s --max-time 20 "$URL_WEBHOOK" || true)"
  if [[ "$REP" == *'"webhook"'* ]]; then OK="oui"; break; fi
  sleep 10
done

echo
echo "════════════════════════════════════════════════════════════════"
echo " À ENVOYER À SERDIPAY"
echo "════════════════════════════════════════════════════════════════"
echo " IP serveur (fixe) : $IP_PUBLIQUE"
echo " URL de callback   : $URL_WEBHOOK"
echo " Méthode           : POST, JSON"
echo " Signature         : HMAC-SHA256 du corps brut"
if [[ "$SORTANT" == "oui" ]]; then
  echo " Nos appels sortants partent de la MÊME IP et utilisent :"
  echo "   https://${HOTE}/api  (équivalent de https://public-apis.services.serdipay.com)"
fi
echo "════════════════════════════════════════════════════════════════"
if [[ "$OK" == "oui" ]]; then
  echo " ✅ Relais opérationnel — le webhook répond : $REP"
else
  echo " ⚠️  Le webhook n'a pas encore répondu correctement."
  echo "     Vérifiez que les ports 80/443 sont ouverts chez le fournisseur,"
  echo "     puis : curl -s $URL_WEBHOOK"
fi
echo
echo " Étape suivante côté Supabase (Edge Functions → Secrets) :"
echo "   SERDIPAY_WEBHOOK_SECRET = <le secret fourni par SerdiPay>"
[[ "$SORTANT" == "oui" ]] && echo "   SERDIPAY_BASE_URL       = https://${HOTE}/api"
