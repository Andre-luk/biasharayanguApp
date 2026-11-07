// lib/widgets/actions_facture.dart
//
// 🧾 MODULE 27 — LES MÊMES ACTIONS DE FACTURE PARTOUT.
//
// Après une vente, quel que soit l'écran (caisse classique ou New Sale),
// l'utilisateur voit EXACTEMENT les mêmes possibilités :
//   • récupérer le PDF (téléchargement / partage du fichier) ;
//   • l'envoyer au client sur WhatsApp ;
//   • l'imprimer.
//
// Un seul endroit à maintenir : les écrans appellent [afficherActionsFacture].

import 'package:flutter/material.dart';

import 'package:biashara_yangu/services/facture_vente_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Ouvre la feuille d'actions de la facture d'une vente.
///
/// [telechargeeAutomatiquement] : `true` quand le PDF a déjà été proposé au
/// partage juste après la vente (on adapte le libellé, on ne réimpose rien).
Future<void> afficherActionsFacture(
  BuildContext context,
  DonneesFacture facture, {
  bool telechargeeAutomatiquement = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _FeuilleActions(
      facture: facture,
      telechargeeAutomatiquement: telechargeeAutomatiquement,
    ),
  );
}

class _FeuilleActions extends StatefulWidget {
  const _FeuilleActions({
    required this.facture,
    required this.telechargeeAutomatiquement,
  });

  final DonneesFacture facture;
  final bool telechargeeAutomatiquement;

  @override
  State<_FeuilleActions> createState() => _FeuilleActionsState();
}

class _FeuilleActionsState extends State<_FeuilleActions> {
  bool _enCours = false;
  String? _info;

  Future<void> _executer(Future<bool> Function() action, String succes,
      String echec) async {
    setState(() {
      _enCours = true;
      _info = null;
    });
    final bool ok = await action();
    if (!mounted) return;
    setState(() {
      _enCours = false;
      _info = ok ? succes : echec;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DonneesFacture f = widget.facture;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.receipt_long_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f.numero.isEmpty ? 'Facture' : f.numero,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  formatMontant(f.total),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.telechargeeAutomatiquement
                  ? 'La facture a été proposée au téléchargement. Vous pouvez '
                      'la récupérer à nouveau, l\'envoyer au client ou '
                      'l\'imprimer.'
                  : 'Récupérez la facture, envoyez-la au client ou imprimez-la.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),

            FilledButton.icon(
              onPressed: _enCours
                  ? null
                  : () => _executer(
                        () => FactureVenteService.instance.telecharger(f),
                        'Facture prête : choisissez où l\'enregistrer ou à qui '
                            'l\'envoyer.',
                        'Téléchargement impossible sur cet appareil. '
                            'Essayez « Imprimer » puis « Enregistrer en PDF ».',
                      ),
              icon: _enCours
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
              label: const Text('TÉLÉCHARGER / PARTAGER LE PDF'),
            ),
            const SizedBox(height: 8),

            FilledButton.tonalIcon(
              onPressed: _enCours
                  ? null
                  : () async {
                      await FactureVenteService.instance
                          .proposerEnvoiWhatsApp(context, f);
                    },
              icon: const Icon(Icons.chat_rounded),
              label: const Text('ENVOYER SUR WHATSAPP'),
            ),
            const SizedBox(height: 8),

            OutlinedButton.icon(
              onPressed: _enCours
                  ? null
                  : () => _executer(
                        () => FactureVenteService.instance.imprimer(f),
                        'Impression lancée.',
                        'Impression indisponible sur cet appareil.',
                      ),
              icon: const Icon(Icons.print_rounded),
              label: const Text('IMPRIMER'),
            ),

            if (_info != null) ...<Widget>[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(_info!, style: const TextStyle(fontSize: 12)),
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}
