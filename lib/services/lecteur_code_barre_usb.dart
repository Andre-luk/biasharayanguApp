// lib/services/lecteur_code_barre_usb.dart
//
// 🔌 MODULE 28 — LECTEUR DE CODES-BARRES USB / BLUETOOTH EXTERNE.
//
// POURQUOI CE FICHIER
//   Un lecteur laser USB (Moss Lode 650 nm classe 1, Honeywell, Zebra…) se
//   présente à l'ordinateur comme un **CLAVIER**. Il n'y a donc AUCUN pilote à
//   installer : le lecteur « tape » le code puis appuie sur Entrée.
//
//   Mais l'application ne doit pas confondre :
//     • une personne qui tape au clavier (lentement, quelques touches) ;
//     • un lecteur qui « tape » un code (très vite, puis Entrée).
//
//   Ce module fait exactement cela : il mesure la RAPIDITÉ de la frappe.
//   Un lecteur envoie ses caractères à ~5–30 ms d'intervalle ; un humain
//   dépasse rarement 120 ms. Un code lu par le lecteur est donc reconnu en
//   quelques millisecondes, sans demander au commerçant de configurer quoi
//   que ce soit.
//
// ⚠️ PRÉ-REQUIS CÔTÉ LECTEUR (réglage d'usine dans 95 % des cas)
//   • mode « clavier / HID » (et non « port série / COM ») ;
//   • suffixe = Entrée (CR) — c'est le réglage par défaut ;
//   • clavier du système en QWERTY **ou** en AZERTY : les codes-barres ne
//     contiennent que des chiffres, identiques sur les deux dispositions.
//
// L'utilisateur peut donc brancher le lecteur et scanner immédiatement.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reconnaît une rafale de frappe comme un scan de lecteur externe.
///
/// Classe pure (aucune dépendance Flutter) : testable sans interface.
class TamponScannerUsb {
  TamponScannerUsb({
    this.intervalleMax = const Duration(milliseconds: 90),
    this.dureeMax = const Duration(seconds: 3),
    this.longueurMin = 4,
  });

  /// Délai maximal entre deux caractères d'un même code.
  final Duration intervalleMax;

  /// Durée maximale de la saisie complète d'un code.
  final Duration dureeMax;

  /// En dessous de cette longueur, on ne considère pas qu'il s'agit d'un code
  /// (évite de prendre « 12 » tapé à la main pour un article).
  final int longueurMin;

  final StringBuffer _tampon = StringBuffer();
  DateTime? _debut;
  DateTime? _dernier;

  /// Contenu actuellement tamponné (utile pour l'affichage de débogage).
  String get contenu => _tampon.toString();

  bool get vide => _tampon.isEmpty;

  void reinitialiser() {
    _tampon.clear();
    _debut = null;
    _dernier = null;
  }

  /// Ajoute un caractère. Renvoie le code COMPLET si ce caractère termine un
  /// scan reconnu (touche Entrée / Tab), sinon `null`.
  ///
  /// Une frappe trop lente ou trop longue remet le tampon à zéro : on ne veut
  /// jamais interpréter une saisie humaine comme un scan.
  String? ajouter(String caractere, {DateTime? maintenant}) {
    final DateTime instant = maintenant ?? DateTime.now();

    // Fin de code : le lecteur envoie Entrée (ou Tab selon le réglage).
    if (caractere == '\n' || caractere == '\r' || caractere == '\t') {
      final bool rapide = _estRapide(instant);
      final String code = _tampon.toString().trim();
      reinitialiser();
      if (!rapide || code.length < longueurMin) return null;
      return code;
    }

    // Caractère de contrôle : on ignore.
    if (caractere.isEmpty) return null;
    final int code = caractere.codeUnitAt(0);
    if (code < 0x20 || code == 0x7f) return null;

    // Trop lent depuis le dernier caractère : c'est de la frappe humaine.
    if (_dernier != null && instant.difference(_dernier!) > intervalleMax) {
      reinitialiser();
    }

    _debut ??= instant;
    _dernier = instant;
    _tampon.write(caractere);

    // Saisie interminable : on abandonne (ce n'est pas un scan).
    if (instant.difference(_debut!) > dureeMax) {
      reinitialiser();
    }
    return null;
  }

  bool _estRapide(DateTime instant) {
    if (_debut == null) return false;
    return instant.difference(_debut!) <= dureeMax;
  }
}

/// Un code ressemble-t-il à un code-barres / QR ?
///
/// Sert au champ de recherche de la caisse : si le commerçant scanne pendant
/// que le champ a le focus, le texte reçu est un code, pas une recherche.
///
/// ⚠️ Une recherche ordinaire (« savon », « eau casino ») doit rester une
/// recherche : on exige soit une étiquette de l'application (`PROD:`, `COND:`,
/// `BAL:`), soit un code contenant de nombreux chiffres.
bool ressembleACodeBarre(String texte) {
  final String t = texte.trim();
  if (t.length < 6) return false;
  if (t.contains(' ')) return false;

  // Étiquettes imprimées par l'application.
  if (t.contains(':')) return true;

  if (!RegExp(r'^[A-Za-z0-9_\-]+$').hasMatch(t)) return false;

  // Un code-barres fabricant contient des chiffres (EAN-8, EAN-13, UPC…).
  final int chiffres = RegExp(r'[0-9]').allMatches(t).length;
  return chiffres >= 4;
}

/// Enveloppe une zone de l'écran pour capter un lecteur externe.
///
/// Le lecteur étant un clavier, il suffit d'écouter les touches au niveau de
/// l'écran : aucun pilote, aucune permission, aucun appairage.
///
/// ⚠️ Quand un champ de texte a le focus, c'est lui qui reçoit les caractères
/// (comportement normal de Flutter) : la caisse gère ce cas via le champ de
/// recherche, qui reconnaît lui aussi un scan (voir [ressembleACodeBarre]).
class ZoneScannerUsb extends StatefulWidget {
  const ZoneScannerUsb({
    super.key,
    required this.onCode,
    required this.child,
    this.autofocus = true,
    this.actif = true,
  });

  /// Appelé avec le code complet (sans la touche Entrée).
  final ValueChanged<String> onCode;

  final Widget child;

  /// Prend le focus clavier à l'ouverture (indispensable pour capter un
  /// lecteur USB sans que le commerçant clique quelque part).
  final bool autofocus;

  /// Permet de suspendre la capture (ex. pendant un dialogue).
  final bool actif;

  @override
  State<ZoneScannerUsb> createState() => _ZoneScannerUsbState();
}

class _ZoneScannerUsbState extends State<ZoneScannerUsb> {
  final TamponScannerUsb _tampon = TamponScannerUsb();
  final FocusNode _focus = FocusNode(debugLabel: 'zone-scanner-usb');

  @override
  void initState() {
    super.initState();
    // Un lecteur peut scanner avant tout clic : on écoute le clavier dès
    // l'ouverture de l'écran.
    HardwareKeyboard.instance.addHandler(_surTouche);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_surTouche);
    _focus.dispose();
    super.dispose();
  }

  /// Handler GLOBAL : il voit toutes les touches, y compris quand un champ de
  /// texte a le focus. On ne consomme jamais la touche (retour `false`) : la
  /// frappe humaine continue donc de fonctionner normalement.
  bool _surTouche(KeyEvent evenement) {
    if (!widget.actif || !mounted) return false;
    if (evenement is! KeyDownEvent && evenement is! KeyRepeatEvent) {
      return false;
    }

    final LogicalKeyboardKey touche = evenement.logicalKey;

    if (touche == LogicalKeyboardKey.enter ||
        touche == LogicalKeyboardKey.numpadEnter ||
        touche == LogicalKeyboardKey.tab) {
      final String? code = _tampon.ajouter('\n');
      if (code != null) {
        widget.onCode(code);
        return true;
      }
      return false;
    }

    final String? caractere = evenement.character;
    if (caractere == null || caractere.isEmpty) return false;

    final String? code = _tampon.ajouter(caractere);
    if (code != null) {
      widget.onCode(code);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focus,
      autofocus: widget.autofocus,
      // Le `Focus` ne sert qu'à garantir qu'un élément de l'écran tient le
      // focus clavier ; la capture réelle passe par HardwareKeyboard.
      child: widget.child,
    );
  }
}
