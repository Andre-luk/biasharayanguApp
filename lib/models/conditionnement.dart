// lib/models/conditionnement.dart
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Conditionnement d'un article — table `public.conditionnements`.
///
/// Un conditionnement est un emballage vendable (« Farde de 12 »,
/// « Carton de 24 ») rattaché à un article de base :
///
///   • [quantiteUnitesBase] — nombre d'unités de base qu'il contient (12, 24…) ;
///   • [prixVente] — prix de vente DE L'EMBALLAGE, librement fixé : il peut
///     être différent de (prix de l'unité de base × quantité), c'est même
///     l'intérêt commercial d'un emballage ;
///   • [qrCodeId] — identifiant unique généré automatiquement par la base à la
///     création (colonne `qr_code_id`, `default gen_random_uuid()`), encodé
///     dans le QR code imprimé ;
///   • [codeBarreTexte] — code-barre du fabricant, saisi si présent.
class Conditionnement {
  final String id;
  final int produitId;
  final String libelle;
  final double quantiteUnitesBase;
  final double prixVente;
  final String qrCodeId;
  final String? codeBarreTexte;
  final DateTime? createdAt;

  const Conditionnement({
    required this.id,
    required this.produitId,
    required this.libelle,
    required this.quantiteUnitesBase,
    required this.prixVente,
    required this.qrCodeId,
    this.codeBarreTexte,
    this.createdAt,
  });

  factory Conditionnement.fromMap(Map<String, dynamic> map) {
    return Conditionnement(
      id: parseString(map['id']),
      produitId: parseInt(map['produit_id']),
      libelle: parseString(map['libelle']),
      quantiteUnitesBase: parseDouble(map['quantite_unites_base']),
      prixVente: parseDouble(map['prix_vente']),
      qrCodeId: parseString(map['qr_code_id']),
      codeBarreTexte: parseStringOrNull(map['code_barre_texte']),
      createdAt: parseDateTimeOrNull(map['created_at']),
    );
  }

  /// Champs envoyés à Supabase (l'`id` et le `qr_code_id` sont posés par la
  /// base à la création ; ils ne font pas partie du corps d'insertion).
  Map<String, dynamic> toMap() {
    return {
      'produit_id': produitId,
      'libelle': libelle,
      'quantite_unites_base': quantiteUnitesBase,
      'prix_vente': prixVente,
      'code_barre_texte': codeBarreTexte,
    };
  }

  Conditionnement copyWith({
    String? id,
    int? produitId,
    String? libelle,
    double? quantiteUnitesBase,
    double? prixVente,
    String? qrCodeId,
    String? codeBarreTexte,
    DateTime? createdAt,
  }) {
    return Conditionnement(
      id: id ?? this.id,
      produitId: produitId ?? this.produitId,
      libelle: libelle ?? this.libelle,
      quantiteUnitesBase: quantiteUnitesBase ?? this.quantiteUnitesBase,
      prixVente: prixVente ?? this.prixVente,
      qrCodeId: qrCodeId ?? this.qrCodeId,
      codeBarreTexte: codeBarreTexte ?? this.codeBarreTexte,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Quantité d'unités de base représentée par [nombreExemplaires]
  /// exemplaires de ce conditionnement (ex. 3 fardes de 12 → 36 bouteilles).
  double versUnitesBase(double nombreExemplaires) {
    return nombreExemplaires * quantiteUnitesBase;
  }

  /// Nombre d'exemplaires ENTIERS que [stockUnitesBase] permet de constituer.
  ///
  /// Exemple : 34 bouteilles en stock, farde de 12 → 2 fardes complètes.
  int exemplairesContenusDans(double stockUnitesBase) {
    if (quantiteUnitesBase <= 0 || stockUnitesBase <= 0) return 0;
    return (stockUnitesBase / quantiteUnitesBase).floor();
  }

  /// Aperçu du cahier des charges :
  /// « 1 Farde de 12 = 12 bouteilles pour 12 000 CDF ».
  String apercu({required String uniteBase}) {
    return apercuTexte(
      libelle: libelle,
      quantiteUnitesBase: quantiteUnitesBase,
      prixVente: prixVente,
      uniteBase: uniteBase,
    );
  }

  /// Aperçu calculable depuis des valeurs brutes (prévisualisation du
  /// formulaire, avant enregistrement).
  static String apercuTexte({
    required String libelle,
    required double quantiteUnitesBase,
    required double prixVente,
    required String uniteBase,
  }) {
    final String nom = libelle.trim().isEmpty ? '[libellé]' : libelle.trim();
    final String unites =
        '${_nombreTexte(quantiteUnitesBase)} ${pluriel(uniteBase, quantiteUnitesBase)}';
    return '1 $nom = $unites pour ${formatMontant(prixVente)}';
  }

  /// Pluriel simple des unités de base (« bouteille » → « bouteilles »).
  ///
  /// Les unités déjà invariables (kg, m, s…) ne sont pas modifiées.
  static String pluriel(String unite, double quantite) {
    if (quantite <= 1) return unite;
    final String u = unite.trim();
    if (u.isEmpty) return unite;
    if (u.endsWith('s') || u.endsWith('x') || u == 'kg' || u == 'm') return u;
    return '${u}s';
  }
}

/// « 12 » pour une quantité entière, « 1,5 » sinon (virgule française).
String _nombreTexte(double valeur) {
  if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
  return valeur
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}
