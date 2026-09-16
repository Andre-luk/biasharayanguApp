// lib/models/mouvement_article.dart

/// Origine d'un mouvement de stock affiché dans l'historique d'un article.
enum SourceMouvement {
  approvisionnement('Approvisionnement'),
  ajustement('Ajustement'),
  vente('Vente');

  const SourceMouvement(this.libelle);

  /// Libellé affiché à l'utilisateur.
  final String libelle;
}

/// Mouvement de stock d'un article (entrée ou sortie).
///
/// L'historique est une vue en LECTURE SEULE construite à partir des trois
/// tables de mouvements existantes :
///
///   • `public.approvisionnements` — entrées (achats fournisseurs) ;
///   • `public.ajustements`        — entrées / sorties (corrections, pertes…) ;
///   • `public.ventes`             — sorties (ventes au comptoir).
///
/// Module 5 ne crée AUCUN mouvement : modifier le stock depuis la fiche
/// article met à jour `produits.quantite` directement, pour ne pas déclencher
/// deux fois les triggers de stock du serveur.
class MouvementArticle {
  final String id;
  final SourceMouvement source;

  /// Quantité signée, en unités de base : positive = entrée, négative = sortie.
  final double quantite;

  /// Motif libre (raison d'un ajustement, mode de paiement d'une vente…).
  final String? motif;

  /// Date du mouvement (peut être absente sur d'anciennes lignes).
  final DateTime? date;

  const MouvementArticle({
    required this.id,
    required this.source,
    required this.quantite,
    this.motif,
    this.date,
  });

  bool get estEntree => quantite > 0;

  bool get estSortie => quantite < 0;

  /// Tri commun à l'historique : du plus récent au plus ancien, les lignes
  /// sans date en dernier.
  static List<MouvementArticle> recentsDAbord(List<MouvementArticle> mouvements) {
    final List<MouvementArticle> copie = List<MouvementArticle>.of(mouvements);
    copie.sort((MouvementArticle a, MouvementArticle b) {
      if (a.date == null && b.date == null) return 0;
      if (a.date == null) return 1;
      if (b.date == null) return -1;
      return b.date!.compareTo(a.date!);
    });
    return copie;
  }
}
