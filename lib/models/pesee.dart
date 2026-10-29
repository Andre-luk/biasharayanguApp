// lib/models/pesee.dart
//
// ⚖️ MODULE 23 — CALCULS DE PESÉE (PURS, TESTABLES).
//
// Une seule règle, partagée par l'écran de pesée ET la fiche du scanner :
//   • le poids est saisi tel que la balance l'affiche (« 1,250 » ou « 1.250 ») ;
//   • le total = poids × prix unitaire (prix AU KILO du produit) ;
//   • un poids nul ou négatif n'est jamais valide.

class PeseeCalculs {
  PeseeCalculs._();

  /// Nombre maximal de décimales conservées (une balance affiche souvent 3 g).
  static const int decimales = 3;

  /// Convertit « 1,250 », « 1.250 » ou « 1 250 » en `1.25`.
  /// Renvoie `null` si la saisie n'est pas un nombre strictement positif.
  static double? analyser(String texte) {
    final String propre =
        texte.trim().replaceAll(' ', '').replaceAll(',', '.');
    if (propre.isEmpty) return null;
    final double? valeur = double.tryParse(propre);
    if (valeur == null || valeur <= 0) return null;
    return arrondir(valeur);
  }

  /// Arrondit au millième (précision usuelle d'une balance de commerce).
  static double arrondir(double poids) {
    final double facteur = 1000.0;
    return (poids * facteur).roundToDouble() / facteur;
  }

  /// Montant à payer pour [poids] × [prixUnitaire].
  ///
  /// Le prix ne vient JAMAIS de la saisie du vendeur : c'est celui de
  /// l'article relu en base.
  static double total({
    required double poids,
    required double prixUnitaire,
  }) {
    if (poids <= 0 || prixUnitaire <= 0) return 0;
    // La monnaie se compte au centième (CDF/USD).
    return double.parse((poids * prixUnitaire).toStringAsFixed(2));
  }

  /// Texte d'affichage : « 1 » / « 1,25 » / « 0,333 ».
  static String texte(double poids) {
    final String brut = arrondir(poids).toStringAsFixed(decimales);
    final String sansZeros = brut
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
    return sansZeros.replaceAll('.', ',');
  }

  /// ⚖️ FORMAT D'ÉTIQUETTE DE BALANCE : `BAL:<produit_id>:<grammes>`.
  ///
  /// Exemple : `BAL:503:1250` = produit 503, **1,25 kg**. Les balances de
  /// comptoir qui impriment le poids peuvent être configurées sur ce format ;
  /// le code-barres contient alors le produit ET la pesée, et le vendeur n'a
  /// plus rien à taper.
  ///
  /// Renvoie `null` si le code n'est pas un code de balance.
  static ({int produitId, double poids})? decoderCodeBalance(String code) {
    final RegExp format = RegExp(
      r'^(?:BAL|PESEE):(\d+):(\d+(?:[.,]\d+)?)$',
      caseSensitive: false,
    );
    final RegExpMatch? m = format.firstMatch(code.trim());
    if (m == null) return null;

    final int? produitId = int.tryParse(m.group(1)!);
    final double? grammes =
        double.tryParse(m.group(2)!.replaceAll(',', '.'));
    if (produitId == null || produitId <= 0 || grammes == null || grammes <= 0) {
      return null;
    }
    return (produitId: produitId, poids: arrondir(grammes / 1000));
  }
}
