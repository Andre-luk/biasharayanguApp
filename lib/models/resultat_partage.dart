// lib/models/resultat_partage.dart
//
// 📤 RÉSULTAT D'UN PARTAGE DE PDF — modèle partagé par toutes les plateformes.
//
// Un seul vocabulaire pour toute l'application : « le fichier est-il parti ? »,
// « où est-il enregistré ? ». Les écrans n'ont pas à savoir si l'on est sur
// Android, Linux ou le web.

/// Comment le PDF a été remis à l'utilisateur.
enum ModePartage {
  /// La feuille de partage du système s'est ouverte AVEC le fichier joint
  /// (l'utilisateur choisit WhatsApp, e-mail, Drive…).
  feuilleDePartage,

  /// Navigateur : le fichier a été téléchargé.
  telecharge,

  /// Bureau : le fichier est enregistré sur le disque et a été ouvert (ou son
  /// dossier l'a été).
  enregistre,

  /// Rien n'a pu être fait (erreur de génération, permissions…).
  echec,
}

/// Ce qui s'est réellement passé lors d'un partage.
class ResultatPartage {
  const ResultatPartage({
    required this.mode,
    required this.message,
    this.chemin,
    this.fichierJoint = false,
  });

  const ResultatPartage.echec(this.message)
      : mode = ModePartage.echec,
        chemin = null,
        fichierJoint = false;

  final ModePartage mode;

  /// Phrase prête à afficher, en français, sans jargon technique.
  final String message;

  /// Chemin complet du fichier écrit (bureau et navigateur), sinon `null`.
  final String? chemin;

  /// `true` seulement si le PDF lui-même a été joint (pas un simple texte).
  final bool fichierJoint;

  bool get ok => mode != ModePartage.echec;

  @override
  String toString() => 'ResultatPartage($mode, $message, $chemin)';
}
