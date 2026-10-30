// lib/models/recipients.dart
//
// REFONTE ABONNEMENTS & DISTRIBUTION — RÉCIPIENTS, ÉCHANGES ET BONUS.
//
// Miroir des tables et RPC de la migration 0084.
//
// ⚠️ RÈGLE MÉTIER FONDAMENTALE : ne jamais confondre
//   • VENDU    → le récipient appartient au client (il ne revient pas) ;
//   • LIVRÉ    → récipient plein confié au client (il DOIT revenir) ;
//   • RÉCUPÉRÉ → vide rendu par le client ;
//   • CASSÉ / PERDU → perte sèche de l'entreprise.
// Les calculs ci-dessous sont PURS (testables sans réseau).

import 'package:biashara_yangu/utils/json_parsing.dart';

/// Les trois cas du métier, exactement comme sur le terrain.
enum ModeVenteRecipient {
  /// Le client achète l'eau ET un récipient neuf.
  nouveau('nouveau', 'Nouveau récipient'),

  /// Le client rend un vide et reçoit un plein.
  echange('echange', 'Échange (vide → plein)'),

  /// Le client utilise SON récipient : on ne facture que le remplissage.
  propre('propre', 'Récipient du client');

  const ModeVenteRecipient(this.code, this.libelle);

  final String code;
  final String libelle;

  static ModeVenteRecipient depuis(String? brut) {
    final String v = (brut ?? '').trim().toLowerCase();
    for (final ModeVenteRecipient m in ModeVenteRecipient.values) {
      if (m.code == v) return m;
    }
    return ModeVenteRecipient.propre;
  }
}

/// Résultat d'un calcul de vente avec récipient (PUR, sans réseau).
class MontantsVenteRecipient {
  const MontantsVenteRecipient({
    required this.mode,
    required this.quantite,
    required this.montantEau,
    required this.montantRecipient,
  });

  final ModeVenteRecipient mode;
  final int quantite;
  final double montantEau;
  final double montantRecipient;

  /// Ce que le client doit payer au total.
  double get total => montantEau + montantRecipient;

  /// Nombre de mouvements de récipients créés par l'opération
  /// (0 pour « récipient du client », 1 pour « nouveau », 2 pour « échange »).
  int get mouvements => switch (mode) {
        ModeVenteRecipient.nouveau => 1,
        ModeVenteRecipient.echange => 2,
        ModeVenteRecipient.propre => 0,
      };
}

/// Calculs métier des trois cas — MIROIR de `rpc_vente_recipient` (SQL).
abstract final class CalculRecipient {
  /// Montants dus selon le mode choisi.
  ///
  /// - `nouveau` : eau + récipient facturés ;
  /// - `echange` : eau seulement (le récipient est échangé, pas vendu) ;
  /// - `propre`  : eau seulement (aucun récipient facturé, aucun mouvement).
  static MontantsVenteRecipient montants({
    required ModeVenteRecipient mode,
    required double prixEau,
    required double prixRecipient,
    int quantite = 1,
  }) {
    final int q = quantite <= 0 ? 1 : quantite;
    final double eau = (prixEau < 0 ? 0.0 : prixEau) * q;
    final double rec = mode == ModeVenteRecipient.nouveau
        ? (prixRecipient < 0 ? 0.0 : prixRecipient) * q
        : 0.0;
    return MontantsVenteRecipient(
      mode: mode,
      quantite: q,
      montantEau: eau,
      montantRecipient: rec,
    );
  }

  /// Nombre de récipients restant à récupérer chez un client.
  ///
  /// `détenus = livrés − récupérés − perdus − cassés` (jamais négatif).
  static int detenus({
    required int livres,
    required int recuperes,
    int perdus = 0,
    int casses = 0,
  }) {
    final int reste = livres - recuperes - perdus - casses;
    return reste < 0 ? 0 : reste;
  }
}

/// Type de récipient configurable par l'entreprise.
class TypeRecipient {
  const TypeRecipient({
    required this.id,
    required this.libelle,
    this.contenanceLitres = 0,
    this.prixConsigne = 0,
    this.actif = true,
    this.ordre = 50,
  });

  final String id;
  final String libelle;
  final double contenanceLitres;
  final double prixConsigne;
  final bool actif;
  final int ordre;

  factory TypeRecipient.fromMap(Map<String, dynamic> m) => TypeRecipient(
        id: (m['id'] ?? '').toString(),
        libelle: parseString(m['libelle']),
        contenanceLitres: parseDouble(m['contenance_litres']),
        prixConsigne: parseDouble(m['prix_consigne']),
        actif: m['actif'] != false,
        ordre: parseInt(m['ordre'], fallback: 50),
      );
}

/// Ce qu'un client détient encore.
class SoldeRecipients {
  const SoldeRecipients({
    this.livres = 0,
    this.vendus = 0,
    this.recuperes = 0,
    this.casses = 0,
    this.perdus = 0,
    this.detenus = 0,
  });

  final int livres;
  final int vendus;
  final int recuperes;
  final int casses;
  final int perdus;

  /// Récipients appartenant à l'entreprise encore entre les mains du client.
  final int detenus;

  static const SoldeRecipients vide = SoldeRecipients();

  factory SoldeRecipients.fromMap(Map<String, dynamic>? m) {
    if (m == null) return vide;
    return SoldeRecipients(
      livres: parseInt(m['livres']),
      vendus: parseInt(m['vendus']),
      recuperes: parseInt(m['recuperes']),
      casses: parseInt(m['casses']),
      perdus: parseInt(m['perdus']),
      detenus: parseInt(m['detenus']),
    );
  }
}

/// Vue d'ensemble des récipients de l'entreprise.
class TableauBordRecipients {
  const TableauBordRecipients({
    this.livres = 0,
    this.vendus = 0,
    this.recuperes = 0,
    this.casses = 0,
    this.perdus = 0,
    this.chezClients = 0,
    this.clientsConcernes = 0,
  });

  final int livres;
  final int vendus;
  final int recuperes;
  final int casses;
  final int perdus;
  final int chezClients;
  final int clientsConcernes;

  static const TableauBordRecipients vide = TableauBordRecipients();

  /// Taux de récupération (0 → 1). 1 = tous les vides sont revenus.
  double get tauxRecuperation {
    final int sortis = livres + vendus;
    if (sortis <= 0) return 1;
    final double t = recuperes / sortis;
    return t > 1 ? 1 : t;
  }

  factory TableauBordRecipients.fromMap(Map<String, dynamic>? m) {
    if (m == null) return vide;
    return TableauBordRecipients(
      livres: parseInt(m['livres']),
      vendus: parseInt(m['vendus']),
      recuperes: parseInt(m['recuperes']),
      casses: parseInt(m['casses']),
      perdus: parseInt(m['perdus']),
      chezClients: parseInt(m['chez_clients']),
      clientsConcernes: parseInt(m['clients_concernes']),
    );
  }
}

/// Règle de bonus configurable (« 5 fardes achetées = 1 offerte »).
class RegleBonus {
  const RegleBonus({
    required this.id,
    required this.libelle,
    this.produitId,
    this.typeDeclencheur = 'farde',
    this.quantiteDeclencheur = 5,
    this.typeOffert = 'farde',
    this.quantiteOfferte = 1,
    this.actif = true,
  });

  final String id;
  final String libelle;
  final String? produitId;
  final String typeDeclencheur;
  final int quantiteDeclencheur;
  final String typeOffert;
  final int quantiteOfferte;
  final bool actif;

  factory RegleBonus.fromMap(Map<String, dynamic> m) => RegleBonus(
        id: (m['id'] ?? '').toString(),
        libelle: parseString(m['libelle']),
        produitId: m['produit_id']?.toString(),
        typeDeclencheur: parseString(m['type_declencheur'], fallback: 'farde'),
        quantiteDeclencheur: parseInt(m['quantite_declencheur'], fallback: 5),
        typeOffert: parseString(m['type_offert'], fallback: 'farde'),
        quantiteOfferte: parseInt(m['quantite_offerte'], fallback: 1),
        actif: m['actif'] != false,
      );

  /// Quantité offerte pour [achetee] unités achetées (calcul PUR).
  int bonusPour(int achetee) {
    if (!actif || quantiteDeclencheur <= 0 || achetee <= 0) return 0;
    return (achetee ~/ quantiteDeclencheur) * quantiteOfferte;
  }
}
