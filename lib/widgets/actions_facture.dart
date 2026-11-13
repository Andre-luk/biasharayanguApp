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
// ⛔ CORRECTIF (14/11/2026) — RIEN N'EST PLUS TÉLÉCHARGÉ AUTOMATIQUEMENT.
// L'ancien enchaînement « vente validée → PDF écrit puis ouvert » déclenchait
// sous Windows « ce fichier ne contient pas l'application associée pour
// effectuer cette action… ». Le patron a demandé que la facture soit
// TÉLÉCHARGÉE ET PARTAGÉE PAR WHATSAPP, à la demande, jamais toute seule.
//
// Un seul endroit à maintenir : les écrans appellent [afficherActionsFacture].

import 'package:flutter/material.dart';

import 'package:biashara_yangu/services/facture_vente_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/partage_pdf.dart';

/// Ouvre la feuille d'actions de la facture d'une vente.
Future<void> afficherActionsFacture(
  BuildContext context,
  DonneesFacture facture,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _FeuilleActions(facture: facture),
  );
}

class _FeuilleActions extends StatefulWidget {
  const _FeuilleActions({required this.facture});

  final DonneesFacture facture;

  @override
  State<_FeuilleActions> createState() => _FeuilleActionsState();
}

class _FeuilleActionsState extends State<_FeuilleActions> {
  bool _enCours = false;
  String? _info;

  /// Chemin du PDF enregistré sur cet appareil (`null` sur mobile / web, ou
  /// avant le premier téléchargement) : sert au bouton « ouvrir le dossier ».
  String? _cheminPdf;

  Future<void> _executer(
      Future<bool> Function() action, String succes, String echec) async {
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
              'Aucun téléchargement automatique : choisissez ce que vous '
              'voulez faire de cette facture.',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _enCours
                  ? null
                  : () async {
                      setState(() {
                        _enCours = true;
                        _info = null;
                      });
                      final ResultatPartage resultat =
                          await FactureVenteService.instance.partager(f);
                      if (!mounted) return;
                      setState(() {
                        _enCours = false;
                        _info = resultat.message;
                        if (resultat.chemin != null) {
                          _cheminPdf = resultat.chemin;
                        }
                      });
                    },
              icon: _enCours
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: Colors.white),
                    )
                  : const Icon(Icons.download_rounded),
              label: const Text('TÉLÉCHARGER LA FACTURE (PDF)'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _enCours
                  ? null
                  : () async {
                      setState(() {
                        _enCours = true;
                        _info = null;
                      });
                      await FactureVenteService.instance
                          .proposerEnvoiWhatsApp(context, f);
                      if (!mounted) return;
                      final ResultatPartage? dernier =
                          FactureVenteService.instance.dernierPartage;
                      setState(() {
                        _enCours = false;
                        _info = dernier?.message ??
                            'Choisissez WhatsApp dans la liste pour envoyer le '
                                'PDF au client.';
                        if (dernier?.chemin != null) {
                          _cheminPdf = dernier!.chemin;
                        }
                      });
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
            // 🖥️ Ordinateur : le PDF est enregistré, mais on n'ouvre JAMAIS le
            // fichier tout seul (message « aucune application associée » sous
            // Windows). On propose le DOSSIER — toujours ouvrable.
            if (_cheminPdf != null) ...<Widget>[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _enCours
                    ? null
                    : () => _executer(
                          () => PartagePdf.ouvrirLeDossier(_cheminPdf!),
                          'Dossier ouvert.',
                          'Le dossier n\'a pas pu être ouvert.',
                        ),
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('OUVRIR LE DOSSIER'),
              ),
            ],
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
