// lib/models/statut_abonnement.dart

/// Valeurs autorisées par le type PostgreSQL `statut_abonnement_enum`.
///
/// ⚠️ [code] est la valeur réellement stockée dans `public.entreprises.statut`.
/// Ne jamais la modifier sans modifier simultanément le type enum côté Supabase.
enum StatutAbonnement {
  essai7j('ESSAI_7J', 'Essai 7 jours'),
  actif('ACTIF', 'Actif'),
  expire('EXPIRE', 'Expiré'),
  suspendu('SUSPENDU', 'Suspendu'),
  enAttenteComplement('EN_ATTENTE_COMPLEMENT', 'Attente de complément'),

  /// Valeur de repli utilisée uniquement si la base renvoie un statut inconnu
  /// de cette version de l'application. Elle n'est **jamais** écrite en base.
  inconnu('INCONNU', 'Statut inconnu');

  const StatutAbonnement(this.code, this.libelle);

  /// Valeur stockée dans `public.entreprises.statut`.
  final String code;

  /// Libellé affiché à l'utilisateur.
  final String libelle;

  /// Statuts proposés dans les filtres de l'écran liste.
  ///
  /// [inconnu] est exclu : il ne correspond à aucune valeur en base.
  static List<StatutAbonnement> get statutsFiltrables => values
      .where((StatutAbonnement statut) => statut != StatutAbonnement.inconnu)
      .toList(growable: false);

  /// Convertit un code SQL en statut applicatif.
  static StatutAbonnement fromCode(String? code) {
    if (code == null) return StatutAbonnement.inconnu;

    for (final StatutAbonnement statut in values) {
      if (statut.code == code) return statut;
    }
    return StatutAbonnement.inconnu;
  }
}
