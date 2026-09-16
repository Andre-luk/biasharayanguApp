// lib/models/etiquette_qr.dart
//
// MODULE 6 — CONTENU DES QR CODES (GESTION DES ÉTIQUETTES)
//
// ⚠️ RÈGLE ABSOLUE : un QR code ne contient JAMAIS de prix.
//
// Il encode uniquement l'IDENTITÉ de l'objet :
//
//     PROD:123                → l'article public.produits n° 123
//     COND:0b8a…-…            → le conditionnement (qr_code_id uuid)
//
// Le prix est relu dans la base de données à chaque scan : un changement de
// prix n'invalide donc jamais les étiquettes déjà imprimées.

/// Type d'objet identifié par un QR code.
enum TypeQrCode {
  article('PROD', 'Article'),
  conditionnement('COND', 'Conditionnement');

  const TypeQrCode(this.prefixe, this.libelle);

  /// Préfixe encodé dans le QR code (`PROD` / `COND`).
  final String prefixe;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Convertit un préfixe (`PROD`, `COND`) en type, `null` si inconnu.
  static TypeQrCode? depuisPrefixe(String? prefixe) {
    final String normalise = (prefixe ?? '').trim().toUpperCase();
    for (final TypeQrCode type in values) {
      if (type.prefixe == normalise) return type;
    }
    return null;
  }
}

/// Étiquette QR d'un article ou d'un conditionnement.
///
/// [code] est LA chaîne encodée dans le QR code ; les autres champs
/// ([titre], [sousTitre]…) ne servent qu'à l'affichage, aux noms de fichiers
/// et à la mise en page de la planche PDF : ils ne sont JAMAIS encodés.
class EtiquetteQr {
  /// Nature de l'objet identifié.
  final TypeQrCode type;

  /// Identifiant encodé : id de l'article (`123`) ou `qr_code_id` du
  /// conditionnement (uuid).
  final String identifiant;

  /// Article parent (toujours renseigné : l'id de l'article lui-même pour un
  /// article, l'id de son article pour un conditionnement).
  final int? articleId;

  /// Nom de l'article (affichage / impression).
  final String titre;

  /// Précision pour un conditionnement (« Farde de 12 — 12 bouteilles »).
  final String? sousTitre;

  const EtiquetteQr({
    required this.type,
    required this.identifiant,
    this.articleId,
    this.titre = '',
    this.sousTitre,
  });

  /// Chaîne encodée dans le QR code — JAMAIS le prix.
  String get code => '${type.prefixe}:$identifiant';

  /// Nom de fichier de base, sans extension : `qr_PROD_123`,
  /// `qr_COND_0b8a….png`…
  String get nomFichierBase => 'qr_${type.prefixe}_$identifiant';

  /// Libellé de tête affiché dans l'application et sur l'étiquette.
  String get libelleComplet =>
      sousTitre == null || sousTitre!.trim().isEmpty
          ? titre.trim()
          : '${titre.trim()} — ${sousTitre!.trim()}';

  /// Relit un code `PROD:123` / `COND:uuid`. `null` si le format est inconnu
  /// (destiné au futur scanner : un code étranger est simplement ignoré).
  static EtiquetteQr? decoder(String? code) {
    final String propre = (code ?? '').trim();
    if (propre.isEmpty) return null;

    final int separateur = propre.indexOf(':');
    if (separateur <= 0 || separateur == propre.length - 1) return null;

    final TypeQrCode? type =
        TypeQrCode.depuisPrefixe(propre.substring(0, separateur));
    if (type == null) return null;

    final String identifiant = propre.substring(separateur + 1).trim();
    if (identifiant.isEmpty) return null;

    return EtiquetteQr(
      type: type,
      identifiant: identifiant,
      articleId: type == TypeQrCode.article ? int.tryParse(identifiant) : null,
    );
  }
}
