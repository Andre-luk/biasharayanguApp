// lib/models/niveau_abonnement.dart
//
// 🧩 CORRECTIF 65 — UN NIVEAU D'ABONNEMENT.
//
// Un niveau porte la LISTE DES FONCTIONNALITÉS qu'il ouvre, plus un prix
// mensuel CONSEILLÉ (indicatif : le prix réel est négocié entreprise par
// entreprise — le moteur d'abonnement ne lit jamais ce champ).
//
// Table `public.niveaux_abonnement` (correctif 65).

import 'package:biashara_yangu/models/fonctionnalites.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Un niveau du catalogue (`ESSENTIEL`, `PRO`, `PREMIUM`…).
class NiveauAbonnement {
  const NiveauAbonnement({
    required this.code,
    required this.libelle,
    this.ordre = 0,
    this.prixMensuelConseille,
    this.fonctionnalites = const <String>{},
    this.description,
    this.actif = true,
    this.updatedAt,
  });

  /// Code technique (« ESSENTIEL »). Identifiant unique du niveau.
  final String code;

  /// Nom affiché (« Essentiel »).
  final String libelle;

  /// Ordre d'affichage (croissant).
  final int ordre;

  /// Prix mensuel conseillé, en CDF. `null` = non renseigné.
  final double? prixMensuelConseille;

  /// Fonctionnalités ouvertes (codes). Peut contenir le joker `*`.
  final Set<String> fonctionnalites;

  final String? description;
  final bool actif;
  final DateTime? updatedAt;

  /// Le niveau ouvre-t-il TOUT (joker) ?
  bool get toutesLesFonctionnalites =>
      fonctionnalites.contains(Fonctionnalites.joker);

  /// Nombre de fonctionnalités ouvertes (le joker compte pour tout).
  int get nbFonctionnalites => Fonctionnalites.compte(fonctionnalites);

  /// Fonctionnalités affichables, triées dans l'ordre du catalogue.
  List<String> get fonctionnalitesTriees {
    final List<String> connues = Fonctionnalites.codes
        .where(fonctionnalites.contains)
        .toList(growable: false);

    //  Les codes inconnus de l'application (ajoutés côté base) sont conservés
    //  en fin de liste : on ne perd jamais silencieusement une fonctionnalité.
    final List<String> inconnues =
        fonctionnalites.where((String c) => !Fonctionnalites.codeConnu(c)).toList()
          ..sort();

    return <String>[...connues, ...inconnues];
  }

  /// Un niveau de travail vide (formulaire de création).
  static const NiveauAbonnement vide = NiveauAbonnement(
    code: '',
    libelle: '',
  );

  factory NiveauAbonnement.fromMap(Map<String, dynamic> map) {
    return NiveauAbonnement(
      code: parseString(map['code']),
      libelle: parseString(map['libelle']),
      ordre: parseInt(map['ordre']),
      prixMensuelConseille: parseDoubleOrNull(map['prix_mensuel_conseille']),
      fonctionnalites: _codes(map['modules']),
      description: parseStringOrNull(map['description']),
      actif: map['actif'] == null ? true : map['actif'] == true,
      updatedAt: parseDateTimeOrNull(map['updated_at']),
    );
  }

  /// Paramètres de la RPC d'enregistrement.
  ///
  /// Les noms sont imposés par la signature SQL — ne pas les « améliorer »
  /// sans changer la fonction côté base.
  Map<String, dynamic> versRpc() {
    return <String, dynamic>{
      'p_code': code,
      'p_libelle': libelle,
      'p_ordre': ordre,
      'p_prix': prixMensuelConseille,
      'p_modules': fonctionnalites.toList(growable: false)..sort(),
      'p_description': description,
      'p_actif': actif,
    };
  }

  NiveauAbonnement copyWith({
    String? code,
    String? libelle,
    int? ordre,
    double? prixMensuelConseille,
    Set<String>? fonctionnalites,
    String? description,
    bool? actif,
    DateTime? updatedAt,
  }) {
    return NiveauAbonnement(
      code: code ?? this.code,
      libelle: libelle ?? this.libelle,
      ordre: ordre ?? this.ordre,
      prixMensuelConseille: prixMensuelConseille ?? this.prixMensuelConseille,
      fonctionnalites: fonctionnalites ?? this.fonctionnalites,
      description: description ?? this.description,
      actif: actif ?? this.actif,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Liste de codes depuis un tableau jsonb.
  ///
  /// Toute forme inattendue donne un ensemble VIDE — et un ensemble vide
  /// signifie « aucune restriction » côté application (règle fail-open).
  static Set<String> _codes(dynamic valeur) {
    if (valeur is! List) return const <String>{};

    return valeur
        .map((dynamic element) => element.toString().trim())
        .where((String code) => code.isNotEmpty)
        .toSet();
  }
}
