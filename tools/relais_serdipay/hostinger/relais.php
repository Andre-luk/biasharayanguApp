<?php
/**
 * ============================================================================
 *  BIASHARA YANGU — RELAIS À IP FIXE POUR SERDIPAY (hébergement mutualisé)
 *  ---------------------------------------------------------------------------
 *  À déposer sur un hébergement Hostinger (ou tout hébergement PHP 8+ avec
 *  cURL et HTTPS), par exemple dans le dossier d'un sous-domaine :
 *
 *      /home/uXXX/domains/serdipay.mondomaine.cd/public_html/
 *          relais.php
 *          .htaccess
 *
 *  Rôle : SerdiPay n'appelle QUE l'IP publique de cet hébergement (elle est
 *  fixe), et ce script transmet la requête à l'Edge Function Supabase.
 *  Le corps BRUT est transmis tel quel : la signature HMAC reste valable.
 *
 *  Deux chemins, et RIEN d'autre :
 *    /functions/v1/serdipay/*  → Supabase   (webhook entrant, signé)
 *    /api/*                    → api.serdipay.com (appels sortants, jeton requis)
 *  Tout le reste répond 404 : ce n'est PAS un proxy ouvert.
 *
 *  ⚠️ Ne jamais élargir ces chemins, ni retirer la vérification du jeton.
 * ============================================================================
 */

declare(strict_types=1);

// --- Cibles autorisées (jamais variables) -----------------------------------
const HOTE_SUPABASE   = 'pqzcliibocndiyqbyddr.supabase.co';
const HOTE_SERDIPAY   = 'api.serdipay.com';

// --- Jeton des appels SORTANTS ----------------------------------------------
// À remplacer par une longue chaîne aléatoire, et à déclarer à l'identique
// dans les secrets Supabase : SERDIPAY_RELAIS_TOKEN.
const JETON_RELAIS    = 'CHANGEZ-CE-JETON-PAR-UNE-VALEUR-ALEATOIRE';

const DELAI_SECONDES  = 30;

/** En-têtes jamais transmis à la cible. */
const ENTETES_IGNORES = ['host', 'content-length', 'connection', 'accept-encoding'];

/** Réponse JSON minimale puis sortie. */
function repondre(int $code, string $corps, string $type = 'application/json'): void
{
    http_response_code($code);
    header('Content-Type: ' . $type);
    header('Cache-Control: no-store');
    echo $corps;
    exit;
}

$methode = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$chemin  = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$requete = $_SERVER['QUERY_STRING'] ?? '';

// --- 1. Choix de la cible ---------------------------------------------------
$cible = null;

if (strpos($chemin, '/functions/v1/serdipay/') === 0) {
    // Webhook entrant : SerdiPay signe chaque appel, aucun jeton local n'est
    // nécessaire — le refus viendra de Supabase (401/503) si le secret manque.
    $cible = 'https://' . HOTE_SUPABASE . $chemin;
} elseif (strpos($chemin, '/api/') === 0) {
    // Appels sortants : réservés à notre passerelle.
    $jeton = $_SERVER['HTTP_X_RELAIS_TOKEN'] ?? '';
    if (!hash_equals(JETON_RELAIS, (string) $jeton)) {
        repondre(401, '{"ok":false,"erreur":"jeton de relais absent ou invalide"}');
    }
    $cible = 'https://' . HOTE_SERDIPAY . substr($chemin, 4); // retire « /api »
} else {
    repondre(404, '{"ok":false,"erreur":"chemin non autorise"}');
}

if ($requete !== '') {
    $cible .= '?' . $requete;
}

// --- 2. Préparation de la transmission --------------------------------------
$corps = file_get_contents('php://input');
if ($corps === false) {
    $corps = '';
}

$entetes = [];
foreach (getallheaders() as $nom => $valeur) {
    if (in_array(strtolower($nom), ENTETES_IGNORES, true)) {
        continue;
    }
    $entetes[] = $nom . ': ' . $valeur;
}

// --- 3. Appel de la cible ---------------------------------------------------
$curl = curl_init($cible);
curl_setopt_array($curl, [
    CURLOPT_RETURNTRANSFER => true,
    CURLOPT_HEADER         => false,
    CURLOPT_FOLLOWLOCATION => false,   // une redirection casserait la signature
    CURLOPT_CUSTOMREQUEST  => $methode,
    CURLOPT_HTTPHEADER     => $entetes,
    CURLOPT_TIMEOUT        => DELAI_SECONDES,
    CURLOPT_CONNECTTIMEOUT => 10,
    CURLOPT_SSL_VERIFYPEER => true,
    CURLOPT_SSL_VERIFYHOST => 2,
]);

if ($methode !== 'GET' && $methode !== 'HEAD') {
    curl_setopt($curl, CURLOPT_POSTFIELDS, $corps);
}

$reponse = curl_exec($curl);
$code    = (int) curl_getinfo($curl, CURLINFO_HTTP_CODE);
$type    = (string) (curl_getinfo($curl, CURLINFO_CONTENT_TYPE) ?: 'application/json');
$erreur  = curl_error($curl);
curl_close($curl);

// --- 4. Restitution ---------------------------------------------------------
if ($reponse === false || $code === 0) {
    error_log('relais serdipay : echec curl ' . $erreur);
    repondre(502, '{"ok":false,"erreur":"relais indisponible"}');
}

repondre($code, (string) $reponse, $type);
