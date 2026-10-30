// lib/models/type_activite.dart
//
// REFONTE ABONNEMENTS & DISTRIBUTION — TYPE D'ACTIVITÉ DE L'ENTREPRISE.
//
// Une entreprise Biashara Yangu exploite :
//   • une BOUTIQUE (commerce de détail : produits, stock, ventes, caisse,
//     clients, dettes, dépenses, collaborateurs, rapports) ;
//   • ou une ENTREPRISE DE DISTRIBUTION (agents, tournées, consignes,
//     récipients, bonus, retours, rapports de distribution).
//
// Le type est stocké dans `public.entreprises.type_activite`
// (migration 0083) et exposé par `rpc_entreprise_type_activite()`.
//
// ⚠️ RÈGLE D'OR (zéro régression) : `null` = NON RENSEIGNÉ. Dans ce cas
// l'application conserve le comportement historique : toutes les entrées
// restent visibles. Le filtrage n'intervient que si le type est connu.
//
// Miroir de la contrainte SQL `entreprises_type_activite_check`.

/// Type d'activité d'une entreprise.
enum TypeActivite {
  /// Commerce de détail « classique ».
  boutique('boutique', 'Boutique'),

  /// Entreprise de distribution (agents, tournées, récipients).
  distribution('distribution', 'Distribution');

  const TypeActivite(this.code, this.libelle);

  /// Valeur stockée en base.
  final String code;

  /// Libellé affichable.
  final String libelle;

  /// Convertit une valeur base (ou libre) en type connu.
  /// Renvoie `null` pour toute valeur inconnue ou vide → fail-open.
  static TypeActivite? depuis(String? brut) {
    final String v = (brut ?? '').trim().toLowerCase();
    if (v.isEmpty) return null;
    for (final TypeActivite t in TypeActivite.values) {
      if (t.code == v) return t;
    }
    // Tolérance : « distribution », « distributeur », « distributeurs ».
    if (v.startsWith('distribut')) return TypeActivite.distribution;
    if (v.startsWith('boutique') || v == 'commerce' || v == 'magasin') {
      return TypeActivite.boutique;
    }
    return null;
  }
}

/// Raccourcis purs (testables sans réseau) : « faut-il masquer cette entrée ? ».
///
/// Les deux fonctions sont volontairement **fail-open** : un type inconnu
/// (`null`) ne masque jamais rien.
abstract final class ReglesTypeActivite {
  /// Vrai si l'entreprise est connue comme BOUTIQUE.
  static bool estBoutique(TypeActivite? type) => type == TypeActivite.boutique;

  /// Vrai si l'entreprise est connue comme DISTRIBUTION.
  static bool estDistribution(TypeActivite? type) =>
      type == TypeActivite.distribution;

  /// Une entrée réservée à [requis] doit-elle être masquée ?
  ///
  /// [requis] `null` → jamais masquée (entrée commune).
  static bool masque(TypeActivite? connu, TypeActivite? requis) {
    if (requis == null) return false; // entrée commune
    if (connu == null) return false; // type non renseigné → fail-open
    return connu != requis;
  }
}
