// lib/utils/uuid_utils.dart
//
// ⚠️ UNE CHAÎNE VIDE N'EST PAS UN UUID.
//
// Symptôme corrigé côté application : « La valeur transmise n'est pas valide
// pour la base de données (invalid input syntax for type uuid) ».
//
// Cause : les listes déroulantes renvoient `''` (ou parfois `'null'`,
// `'undefined'`) quand rien n'est choisi. Envoyée telle quelle à une colonne
// ou à un paramètre de type `uuid`, PostgreSQL refuse la valeur (code 22P02)
// et toute l'opération est annulée — sans que l'utilisateur puisse comprendre
// quel champ posait problème.
//
// Règle unique de l'application : **un identifiant absent est `null`**, jamais
// une chaîne vide. Ce fichier est la seule implémentation de cette règle.
//
// ⚠️ Le serveur applique la même tolérance (`public.uuid_ou_null(text)` dans
// la migration 174) : une ancienne version de l'application installée sur un
// téléphone continue donc de fonctionner.

/// Motif strict d'un UUID canonique (8-4-4-4-12, hexadécimal).
final RegExp _motifUuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// Valeurs textuelles qui signifient « pas de valeur ».
const Set<String> _videsTextuels = <String>{
  '',
  'null',
  'undefined',
  'none',
  'nil',
};

/// En plus des valeurs ci-dessus, `0` est parfois utilisé comme faux
/// identifiant par d'anciens écrans (l'id 0 n'existe jamais côté serveur).
const Set<String> _fauxIdentifiants = <String>{'0', '-1'};

class UuidValide {
  const UuidValide._();

  /// Vrai si [valeur] est un UUID canonique.
  static bool estValide(Object? valeur) {
    if (valeur == null) return false;
    return _motifUuid.hasMatch(valeur.toString().trim());
  }

  /// Renvoie l'UUID normalisé (minuscules) ou `null`.
  ///
  /// À utiliser pour TOUT champ de type `uuid` : entreprise, propriétaire,
  /// ville, activité, grille tarifaire, espace, client, conditionnement…
  static String? ouNull(Object? valeur) {
    if (valeur == null) return null;
    final String texte = valeur.toString().trim();
    if (texte.isEmpty) return null;
    final String bas = texte.toLowerCase();
    if (_videsTextuels.contains(bas) || _fauxIdentifiants.contains(bas)) {
      return null;
    }
    if (!_motifUuid.hasMatch(texte)) return null;
    return bas;
  }

  /// Renvoie l'UUID si valide, sinon lève une erreur métier lisible.
  ///
  /// Utilisé là où l'identifiant est OBLIGATOIRE (suppression d'une
  /// entreprise, ouverture d'une fiche…) : mieux vaut un message clair qu'une
  /// erreur PostgreSQL brute.
  static String requis(Object? valeur, {String champ = 'identifiant'}) {
    final String? propre = ouNull(valeur);
    if (propre == null) {
      throw FormatException('Le $champ transmis est invalide.');
    }
    return propre;
  }

  /// Pour les champs TEXTE qui ressemblent à des identifiants sans en être
  /// (codes de module, type de boutique) : chaîne nettoyée ou `null`.
  ///
  /// ⚠️ Ne jamais l'utiliser pour une colonne `uuid` : un code de module
  /// (« boutique », « pharmacie »…) n'est pas un UUID.
  static String? texteOuNull(Object? valeur) {
    if (valeur == null) return null;
    final String texte = valeur.toString().trim();
    if (texte.isEmpty) return null;
    if (_videsTextuels.contains(texte.toLowerCase())) return null;
    return texte;
  }
}

/// Traduit une erreur de base de données en message utilisateur en français.
///
/// Le détail technique reste dans les journaux (`debugPrint`) ; l'écran ne
/// montre jamais « invalid input syntax for type uuid ».
String messageErreurBaseDeDonnees(
  Object erreur, {
  String repli = 'Une erreur est survenue. Vérifiez les informations saisies '
      'puis réessayez.',
}) {
  final String brut = erreur.toString();
  final String bas = brut.toLowerCase();

  if (bas.contains('22p02') ||
      bas.contains('invalid input syntax for type uuid')) {
    return 'Une information interne est incomplète ou invalide '
        '(identifiant manquant). Vérifiez les champs liés à l\'entreprise, '
        'à l\'activité et au propriétaire, puis réessayez.';
  }
  if (bas.contains('23505') || bas.contains('duplicate key')) {
    return 'Cet enregistrement existe déjà (doublon).';
  }
  if (bas.contains('23503') || bas.contains('foreign key')) {
    return 'Cette opération est bloquée : des données liées existent encore. '
        'Prévenez le support technique si le problème persiste.';
  }
  if (bas.contains('42501') || bas.contains('permission denied')) {
    return 'Vous n\'avez pas les droits nécessaires pour cette opération.';
  }
  if (bas.contains('pgrst202') ||
      bas.contains('could not find the function') ||
      bas.contains('schema cache')) {
    return 'Cette fonction n\'est pas encore installée en base. '
        'Exécutez la dernière migration puis réessayez.';
  }
  return repli;
}
