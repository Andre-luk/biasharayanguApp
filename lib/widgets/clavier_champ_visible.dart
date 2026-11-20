// lib/widgets/clavier_champ_visible.dart
//
// ⌨️ CORRECTIF 175 — « LE CHAMP OÙ J'ÉCRIS DOIT RESTER VISIBLE QUAND LE
// CLAVIER S'OUVRE ».
//
// POURQUOI CE FICHIER
// -------------------
// Flutter ne fait défiler un `TextField` vers le haut que dans certains cas
// (champ déjà dans la zone visible, `ScrollView` reconnu, clavier mesuré à
// temps). Dans la pratique, sur un formulaire long, le clavier recouvre le
// champ en cours de saisie : l'utilisateur tape « à l'aveugle » et croit que
// le formulaire est figé.
//
// Plutôt que de corriger écran par écran (il y a plus de 40 formulaires), ce
// widget est posé UNE SEULE FOIS autour de toute l'application : à chaque
// changement de champ actif, il demande au `Scrollable` le plus proche de
// rendre ce champ visible, avec une petite marge en haut.
//
// ⚠️ Aucun comportement existant n'est modifié : si le champ est déjà visible,
// `Scrollable.ensureVisible` ne bouge rien ; s'il n'y a pas de zone
// défilante, l'appel est sans effet.

import 'package:flutter/material.dart';

/// Garde le champ actif visible au-dessus du clavier.
class ClavierChampVisible extends StatefulWidget {
  const ClavierChampVisible({super.key, required this.child});

  final Widget child;

  @override
  State<ClavierChampVisible> createState() => _ClavierChampVisibleState();
}

class _ClavierChampVisibleState extends State<ClavierChampVisible> {
  /// Dernier champ pris en charge (évite de rejouer le défilement en boucle).
  FocusNode? _dernierChamp;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_surChangementDeChamp);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_surChangementDeChamp);
    super.dispose();
  }

  void _surChangementDeChamp() {
    final FocusNode? champ = FocusManager.instance.primaryFocus;
    if (champ == null || identical(champ, _dernierChamp)) return;
    _dernierChamp = champ;

    // Le clavier met quelques centaines de millisecondes à s'afficher : la
    // première passe a lieu dès la fin de la frame de mise au point, la
    // seconde une fois la zone visible réellement réduite par le clavier.
    _rendreVisible(champ);
    Future<void>.delayed(
      const Duration(milliseconds: 320),
      () => _rendreVisible(champ),
    );
  }

  void _rendreVisible(FocusNode champ) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final BuildContext? cible = champ.context;
      if (cible == null || !cible.mounted) return;
      Scrollable.ensureVisible(
        cible,
        // 12 % de la hauteur depuis le haut : le champ reste lisible, avec
        // ses suggestions et le libellé au-dessus.
        alignment: 0.12,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
