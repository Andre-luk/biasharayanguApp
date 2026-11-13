// lib/utils/ecoute_contexte_entreprise.dart
//
// 🧩 CONTEXTE MULTI-ENTREPRISES — « QUAND JE CHANGE D'ENTREPRISE,
//    L'ÉCRAN QUE JE REGARDE CHANGE AUSSI ».
//
// POURQUOI CE FICHIER
//   Les écrans principaux vivent dans un `StatefulShellRoute.indexedStack` :
//   ils ne sont donc créés QU'UNE FOIS et jamais détruits. Sans écoute
//   explicite, un écran de liste (articles, stock, clients, caisse…) continue
//   d'afficher les données de l'entreprise précédente après une bascule,
//   alors que le menu, lui, affiche déjà la nouvelle. C'est exactement le
//   symptôme « je crée un article dans la pharmacie et la liste montre la
//   boutique ».
//
// CE QUE FAIT CE MIXIN
//   Il observe [EspaceService.etat] et appelle [onChangementEntreprise]
//   UNIQUEMENT quand la portée de travail ([ScopeDonnees.espaceActif])
//   change réellement — y compris le premier passage `null → identifiant`
//   quand l'écran s'est chargé avant la réponse du serveur. Chaque écran
//   décide quoi recharger : c'est le seul point à brancher.
//
// UTILISATION
//   class _MaPageState extends State<MaPage>
//       with EcouteContexteEntreprise<MaPage> {
//     @override
//     void onChangementEntreprise(String? espaceId) => _charger();
//   }
//
// ⚠️ La valeur suivie est celle de [ScopeDonnees] (l'espace de TRAVAIL, la
//    même que celle utilisée pour lire/écrire `owner_id`), et non le simple
//    identifiant choisi dans le menu : les deux peuvent différer quand le
//    serveur retombe sur l'UUID du patron.

import 'package:flutter/widgets.dart';

import 'package:biashara_yangu/services/espace_service.dart';
import 'package:biashara_yangu/services/scope_donnees.dart';

mixin EcouteContexteEntreprise<T extends StatefulWidget> on State<T> {
  String? _dernierEspaceConnu;
  bool _ecouteActive = false;

  /// Entreprise de travail au moment du dernier appel (diagnostic / tests).
  String? get espaceSuivi => _dernierEspaceConnu;

  @override
  void initState() {
    super.initState();
    _dernierEspaceConnu = ScopeDonnees.espaceActif;
    _ecouteActive = true;
    EspaceService.instance.etat.addListener(_surEspace);
  }

  @override
  void dispose() {
    if (_ecouteActive) {
      EspaceService.instance.etat.removeListener(_surEspace);
      _ecouteActive = false;
    }
    super.dispose();
  }

  void _surEspace() {
    if (!mounted) return;

    final String? courant = ScopeDonnees.espaceActif;
    if (courant == _dernierEspaceConnu) return;

    // ⚠️ Un passage `null → identifiant` est aussi un changement : l'écran a
    // pu se charger AVANT que la liste des entreprises ne réponde (démarrage
    // à froid), donc avec la portée de secours. Le relire une fois est moins
    // coûteux qu'afficher les données de la mauvaise entreprise.
    _dernierEspaceConnu = courant;
    onChangementEntreprise(courant);
  }

  /// Appelé quand l'entreprise active change réellement.
  ///
  /// [espaceId] est l'identifiant de travail (`null` seulement si la session
  /// a été réinitialisée : déconnexion).
  void onChangementEntreprise(String? espaceId);
}
