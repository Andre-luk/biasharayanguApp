// lib/pages/ventes_a_verifier_page.dart
//
// 🔌 100 % HORS LIGNE — RÉSOLUTION DE CONFLITS.
//
// Une vente faite hors ligne est rejouée par `rpc_vente_valider`. Si le
// serveur la refuse plusieurs fois (stock insuffisant, produit supprimé…),
// elle ne disparaît PAS et ne tourne pas en boucle : elle devient un
// **conflit** que le patron peut voir ici, puis trancher.
//
// Trois gestes simples :
//   • « Réessayer » — la vente repart (stock réapprovisionné, réseau revenu) ;
//   • lire le motif pour comprendre ce qui bloque ;
//   • rien n'est jamais perdu : la vente reste sur l'appareil.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class VentesAVerifierPage extends StatefulWidget {
  const VentesAVerifierPage({super.key});

  @override
  State<VentesAVerifierPage> createState() => _VentesAVerifierPageState();
}

class _VentesAVerifierPageState extends State<VentesAVerifierPage> {
  bool _chargement = true;
  bool _enCours = false;
  List<Map<String, Object?>> _lignes = const <Map<String, Object?>>[];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    final List<Map<String, Object?>> lignes =
        await SyncService.instance.conflits();
    if (!mounted) return;
    setState(() {
      _lignes = lignes;
      _chargement = false;
    });
  }

  Future<void> _reessayer(int id) async {
    if (_enCours) return;
    setState(() => _enCours = true);
    final bool ok = await SyncService.instance.rejouerConflit(id);
    if (!mounted) return;
    setState(() => _enCours = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Vente renvoyée : elle repartira dès que le serveur l\'accepte.'
              : 'Toujours bloquée : vérifiez le stock ou le produit concerné.',
        ),
      ),
    );
    await _charger();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventes à vérifier'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _lignes.isEmpty
              ? _vide(context)
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _lignes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (BuildContext context, int i) =>
                      _carte(context, _lignes[i]),
                ),
    );
  }

  Widget _vide(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.verified_rounded,
                size: 56, color: AppCouleurs.succes),
            const SizedBox(height: 12),
            const Text(
              'Aucune vente en attente de décision.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tout ce qui a été enregistré sur cet appareil est parti au '
              'serveur.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _carte(BuildContext context, Map<String, Object?> ligne) {
    final int id = (ligne['id'] as num?)?.toInt() ?? 0;
    final double quantite = (ligne['quantite'] as num?)?.toDouble() ?? 0;
    final double prix = (ligne['prix'] as num?)?.toDouble() ?? 0;
    final int tentatives = (ligne['tentatives'] as num?)?.toInt() ?? 0;
    final String motif = '${ligne['sync_erreur'] ?? ''}';
    final DateTime? date = DateTime.tryParse('${ligne['date'] ?? ''}');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.receipt_long_rounded,
                    color: AppCouleurs.danger, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Vente du ${formatDate(date)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  formatMontant(prix),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Quantité : ${formatQuantite(quantite)} · '
                'Tentatives : $tentatives'),
            if (motif.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                motif,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                onPressed: _enCours ? null : () => _reessayer(id),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Réessayer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
