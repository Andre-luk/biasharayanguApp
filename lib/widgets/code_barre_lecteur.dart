// lib/widgets/code_barre_lecteur.dart
//
// 🏷️ CORRECTIF 59 — LECTEUR DE CODES-BARRES RÉUTILISABLE, PARTOUT.
//
// DEUX FAÇONS DE LIRE, COMPLÉMENTAIRES :
//
//   • LA CAMÉRA — codes-barres FABRICANTS (EAN-13, EAN-8, UPC-A/E, Code 128,
//     Code 39/93, ITF-14, Codabar, DataMatrix) ET les QR codes déjà émis par
//     l'application, pour ne casser aucune étiquette imprimée ;
//
//   • UNE DOUCHETTE USB / BLUETOOTH — ces lecteurs « tapent » le code comme
//     un clavier. Le champ [ChampCodeBarre] les reçoit sans configuration :
//     il suffit que le champ ait le focus.
//
// MODE D'EMPLOI DANS UN ÉCRAN
//
//   // 1. Lire un code brut (rend `null` si l'utilisateur ferme) :
//   final String? code = await lireCodeBarre(context, titre: 'Produit');
//
//   // 2. Ou poser un champ prêt à l'emploi dans un formulaire :
//   ChampCodeBarre(
//     controller: _codeBarreController,
//     onCode: (String code) => _chercherProduit(code),
//   )
//
// ⚠️ Aucun prix, aucune identité d'article ici : ce fichier ne fait QUE
// rendre un code. C'est `ScannerService` / `ArticleService` qui décident quoi
// en faire.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:vibration/vibration.dart';

// ---------------------------------------------------------------------------
// PALETTE (écran sombre : la caméra occupe tout l'espace)
// ---------------------------------------------------------------------------

const Color _fond = Color(0xFF101216);
const Color _accent = Color(0xFF69F0AE);

/// Formats acceptés par le lecteur.
///
/// Volontairement large : un commerçant scanne aussi bien le code-barres de
/// son fournisseur que les étiquettes QR déjà imprimées par l'application.
const List<BarcodeFormat> formatsCodesBarres = <BarcodeFormat>[
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.itf14,
  BarcodeFormat.codabar,
  BarcodeFormat.dataMatrix,
  BarcodeFormat.qrCode,
];

/// Ouvre le lecteur en plein écran et renvoie le code lu.
///
/// Renvoie `null` si l'utilisateur ferme l'écran sans rien scanner : dans ce
/// cas l'appelant ne doit RIEN changer (pas de champ vidé, pas d'erreur).
Future<String?> lireCodeBarre(
  BuildContext context, {
  String titre = 'Scanner un code-barres',
  String aide = 'Placez le code-barres dans le cadre.',
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute<String>(
      fullscreenDialog: true,
      builder: (BuildContext ctx) => LecteurCodeBarre(titre: titre, aide: aide),
    ),
  );
}

// ---------------------------------------------------------------------------
// L'ÉCRAN DE LECTURE
// ---------------------------------------------------------------------------

/// Écran plein écran de lecture d'un code-barres. Préférez [lireCodeBarre].
class LecteurCodeBarre extends StatefulWidget {
  const LecteurCodeBarre({
    super.key,
    this.titre = 'Scanner un code-barres',
    this.aide = 'Placez le code-barres dans le cadre.',
  });

  final String titre;
  final String aide;

  @override
  State<LecteurCodeBarre> createState() => _LecteurCodeBarreState();
}

class _LecteurCodeBarreState extends State<LecteurCodeBarre> {
  late final MobileScannerController _controleur = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: formatsCodesBarres,
    autoZoom: true,
  );

  /// Anti-rebond : une même étiquette est relue sur plusieurs images.
  String? _dernierCode;
  DateTime? _dernierAt;
  bool _termine = false;

  @override
  void dispose() {
    _controleur.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_termine) return;

    final String? brut = capture.barcodes
        .map((Barcode code) => code.rawValue)
        .firstWhere(
          (String? valeur) => valeur != null && valeur.trim().isNotEmpty,
          orElse: () => null,
        );
    if (brut == null) return;

    _retenir(brut);
  }

  /// Retient [brut] et referme l'écran en le rendant à l'appelant.
  void _retenir(String brut) {
    final String code = brut.trim();
    if (code.isEmpty || _termine) return;

    final DateTime maintenant = DateTime.now();
    if (_dernierCode == code &&
        _dernierAt != null &&
        maintenant.difference(_dernierAt!) < const Duration(milliseconds: 1200)) {
      return;
    }
    _dernierCode = code;
    _dernierAt = maintenant;
    _termine = true;

    unawaited(_confirmer());
    Navigator.of(context).pop(code);
  }

  /// Retour physique au commerçant : vibration courte + clic système.
  Future<void> _confirmer() async {
    try {
      await Vibration.vibrate(duration: 70);
    } catch (_) {
      // Appareil sans vibreur : sans conséquence.
    }
    try {
      await SystemSound.play(SystemSoundType.click);
    } catch (_) {
      // Plateforme sans son système : sans conséquence.
    }
  }

  /// Repli utile : code-barres abîmé, illisible ou douchette branchée.
  Future<void> _saisirAlaMain() async {
    final TextEditingController saisie = TextEditingController();
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Saisir le code'),
        content: TextField(
          controller: saisie,
          autofocus: true,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'Code-barres',
            helperText: 'Une douchette peut aussi taper le code ici.',
          ),
          onSubmitted: (String valeur) {
            final String propre = valeur.trim();
            Navigator.of(ctx).pop(propre.isEmpty ? null : propre);
          },
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final String propre = saisie.text.trim();
              Navigator.of(ctx).pop(propre.isEmpty ? null : propre);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );

    saisie.dispose();
    if (code != null && mounted) _retenir(code);
  }

  void _fermer() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fond,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MobileScanner(
            controller: _controleur,
            onDetect: _onDetect,
            errorBuilder:
                (BuildContext context, MobileScannerException erreur) =>
                    _CameraIndisponible(
              message: erreur.errorCode == MobileScannerErrorCode.permissionDenied
                  ? 'Accès à la caméra refusé. Autorisez la caméra dans les '
                      'réglages du téléphone, puis rouvrez le lecteur.'
                  : 'Caméra indisponible sur cet appareil. Utilisez la saisie '
                      'à la main ou une douchette.',
              onSaisie: _saisirAlaMain,
            ),
          ),

          // Cadre de visée.
          Center(
            child: Container(
              width: 264,
              height: 168,
              decoration: BoxDecoration(
                border: Border.all(color: _accent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),

          // Bandeau supérieur : titre + aide + fermeture.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  IconButton(
                    onPressed: _fermer,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Fermer',
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.titre,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.aide,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _controleur.toggleTorch(),
                    icon: const Icon(
                      Icons.flashlight_on_rounded,
                      color: Colors.white,
                    ),
                    tooltip: 'Lampe',
                  ),
                ],
              ),
            ),
          ),

          // Bandeau inférieur : saisie à la main (douchette, code abîmé).
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.tonalIcon(
                  onPressed: _saisirAlaMain,
                  icon: const Icon(Icons.keyboard_rounded),
                  label: const Text('Saisir le code à la main'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Écran de remplacement quand la caméra n'est pas utilisable.
class _CameraIndisponible extends StatelessWidget {
  const _CameraIndisponible({required this.message, required this.onSaisie});

  final String message;
  final VoidCallback onSaisie;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _fond,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.no_photography_rounded,
                  size: 56, color: Colors.white54),
              const SizedBox(height: 14),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 18),
              FilledButton.tonalIcon(
                onPressed: onSaisie,
                icon: const Icon(Icons.keyboard_rounded),
                label: const Text('Saisir le code à la main'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// LE CHAMP DE FORMULAIRE
// ---------------------------------------------------------------------------

/// Champ « code-barres » : saisie au clavier, à la douchette, ou au scan.
///
/// Utilisable tel quel dans n'importe quel formulaire : il ne connaît ni les
/// articles ni les prix, il rend simplement le code.
class ChampCodeBarre extends StatelessWidget {
  const ChampCodeBarre({
    super.key,
    required this.controller,
    this.label = 'Code-barres',
    this.aide,
    this.onCode,
    this.enabled = true,
    this.validator,
  });

  final TextEditingController controller;
  final String label;

  /// Petite phrase d'explication sous le champ.
  final String? aide;

  /// Appelé avec le code PROPRE (espaces retirés) : après un scan, ou après
  /// validation au clavier / à la douchette.
  final ValueChanged<String>? onCode;

  final bool enabled;
  final String? Function(String?)? validator;

  Future<void> _scanner(BuildContext context) async {
    final String? code = await lireCodeBarre(context, titre: label);
    if (code == null || !context.mounted) return;
    controller.text = code;
    onCode?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      textInputAction: TextInputAction.done,
      onSubmitted: (String valeur) {
        final String code = valeur.trim();
        if (code.isNotEmpty) onCode?.call(code);
      },
      decoration: InputDecoration(
        labelText: label,
        helperText: aide,
        errorText: validator?.call(controller.text),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        prefixIcon: const Icon(Icons.qr_code_2_rounded),
        suffixIcon: IconButton(
          tooltip: 'Scanner avec la caméra',
          onPressed: enabled ? () => _scanner(context) : null,
          icon: const Icon(Icons.photo_camera_rounded),
        ),
      ),
    );
  }
}
