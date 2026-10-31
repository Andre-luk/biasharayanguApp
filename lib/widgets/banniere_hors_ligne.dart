// lib/widgets/banniere_hors_ligne.dart
//
// 📡 BANDEAU « HORS LIGNE ».
//
// Le commerçant doit SAVOIR, en une seconde, pourquoi une donnée semble
// immobile — et être rassuré : sa vente est enregistrée sur l'appareil.
//
// Le bandeau n'apparaît que lorsque le serveur ne répond pas ; dès que la
// connexion revient, il disparaît et la file locale est poussée toute seule
// (`ReseauService` → `SyncService.syncAll`).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/pages/ventes_a_verifier_page.dart';
import 'package:biashara_yangu/services/reseau_service.dart';
import 'package:biashara_yangu/services/sync_service.dart';

class BanniereHorsLigne extends StatelessWidget {
  const BanniereHorsLigne({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ReseauService.instance.enLigne,
      builder: (BuildContext context, bool enLigne, Widget? _) {
        if (enLigne) return const SizedBox.shrink();

        return Material(
          color: const Color(0xFFB45309),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.cloud_off_rounded,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Hors ligne — vos ventes restent enregistrées sur cet '
                      'appareil et seront synchronisées automatiquement.',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  const _LienConflits(),
                  TextButton(
                    onPressed: () =>
                        ReseauService.instance.verifierMaintenant(),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Réessayer',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 🔌 « Ventes à vérifier (N) » — n'apparaît que s'il y a réellement quelque
/// chose à trancher. Une vente rejouée qui échoue plusieurs fois devient un
/// conflit : elle n'est ni perdue, ni réessayée sans fin.
class _LienConflits extends StatelessWidget {
  const _LienConflits();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: SyncService.instance.nombreConflits(),
      builder: (BuildContext context, AsyncSnapshot<int> snap) {
        final int n = snap.data ?? 0;
        if (n <= 0) return const SizedBox.shrink();

        return TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const VentesAVerifierPage(),
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(0, 32),
          ),
          child: Text(
            'À vérifier ($n)',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        );
      },
    );
  }
}
