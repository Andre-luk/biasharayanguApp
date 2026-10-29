// lib/pages/mes_ventes_page.dart
//
// MODULE 8 — HISTORIQUE DES VENTES DU VENDEUR.
//
// « Ses ventes du jour » : les lignes de `public.ventes` du vendeur connecté,
// regroupées par vente (`vente_uuid`, numéro VTE-…). Filtres :
//   • jour (sélecteur de date, par défaut aujourd'hui) ;
//   • mode de paiement.
// Taper une vente ouvre son détail (articles, quantités, totaux).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/vente_enregistree.dart';
import 'package:biashara_yangu/services/donnees_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/vente_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Écran « Mes ventes » — historique filtrable du vendeur connecté.
class MesVentesPage extends StatefulWidget {
  const MesVentesPage({super.key});

  @override
  State<MesVentesPage> createState() => _MesVentesPageState();
}

class _MesVentesPageState extends State<MesVentesPage> {
  DateTime _jour = DateTime.now();
  String? _modeFiltre;
  late Future<List<VenteHistorique>> _futur;

  @override
  void initState() {
    super.initState();
    _futur = _charger();
    // 🔔 MODULE 23 — une vente encaissée (caisse, vente rapide, tournée)
    // apparaît immédiatement dans l'historique, sans changer d'écran.
    DonneesService.instance.revision.addListener(_recharger);
  }

  @override
  void dispose() {
    DonneesService.instance.revision.removeListener(_recharger);
    super.dispose();
  }

  Future<List<VenteHistorique>> _charger() {
    return VenteService.instance.historiqueVendeur(
      jour: _jour,
      modePaiement: _modeFiltre,
    );
  }

  void _recharger() {
    if (!mounted) return;
    setState(() => _futur = _charger());
  }

  bool get _estAujourdhui {
    final DateTime maintenant = DateTime.now();
    return _jour.year == maintenant.year &&
        _jour.month == maintenant.month &&
        _jour.day == maintenant.day;
  }

  String get _libelleJour =>
      _estAujourdhui ? 'Aujourd\'hui' : formatDate(_jour);

  Future<void> _choisirJour() async {
    final DateTime? choisi = await showDatePicker(
      context: context,
      initialDate: _jour,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Ventes du jour',
    );
    if (choisi == null) return;
    _jour = choisi;
    _recharger();
  }

  void _choisirMode(String? mode) {
    _modeFiltre = mode;
    _recharger();
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes ventes'),
        actions: <Widget>[
          TextButton.icon(
            onPressed: _choisirJour,
            icon: const Icon(Icons.calendar_month_rounded, size: 20),
            label: Text(
              _libelleJour,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildFiltres(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _recharger();
                await _futur;
              },
              child: FutureBuilder<List<VenteHistorique>>(
                future: _futur,
                builder: (
                  BuildContext context,
                  AsyncSnapshot<List<VenteHistorique>> snapshot,
                ) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return _buildMessage(
                      icone: Icons.wifi_off_rounded,
                      message: snapshot.error is VenteServiceException
                          ? (snapshot.error as VenteServiceException).message
                          : 'Impossible de charger vos ventes.',
                      action: FilledButton.icon(
                        onPressed: _recharger,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Réessayer'),
                      ),
                    );
                  }

                  final List<VenteHistorique> ventes =
                      snapshot.data ?? const <VenteHistorique>[];
                  if (ventes.isEmpty) {
                    return _buildMessage(
                      icone: Icons.receipt_long_outlined,
                      message:
                          'Aucune vente ${_estAujourdhui ? 'aujourd\'hui' : 'ce jour-là'}'
                          '${_modeFiltre == null ? '' : ' avec ce mode de paiement'}.',
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
                    itemCount: ventes.length + 1,
                    itemBuilder: (BuildContext context, int index) {
                      if (index == 0) return _buildTotalDuJour(ventes);
                      return _buildCarteVente(ventes[index - 1]);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltres() {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: <Widget>[
          ChoiceChip(
            label: const Text('Tout'),
            selected: _modeFiltre == null,
            onSelected: (_) => _choisirMode(null),
          ),
          ...VenteService.modesPaiement.entries.map(
            (MapEntry<String, String> entree) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChip(
                label: Text(entree.value),
                selected: _modeFiltre == entree.key,
                onSelected: (_) => _choisirMode(entree.key),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalDuJour(List<VenteHistorique> ventes) {
    double total = 0;
    for (final VenteHistorique vente in ventes) {
      total += vente.total;
    }

    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${ventes.length} vente(s)',
                style: TextStyle(
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                formatMontant(total),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Icon(
            Icons.savings_rounded,
            size: 32,
            color: theme.colorScheme.primary.withValues(alpha: 0.6),
          ),
        ],
      ),
    );
  }

  Widget _buildCarteVente(VenteHistorique vente) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _ouvrirDetail(vente),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_rounded,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      vente.libelleNumero,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDateHeure(vente.date)} · '
                      '${vente.nombreLignes} article(s)',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    formatMontant(vente.total),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    VenteService.libelleMode(vente.modePaiement),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessage({
    required IconData icone,
    required String message,
    Widget? action,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: <Widget>[
        const SizedBox(height: 90),
        Icon(icone, size: 56, color: Theme.of(context).colorScheme.outline),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        if (action != null) ...<Widget>[
          const SizedBox(height: 18),
          Center(child: action),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // DÉTAIL D'UNE VENTE
  // ---------------------------------------------------------------------------

  void _ouvrirDetail(VenteHistorique vente) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext contexte) {
        final ThemeData theme = Theme.of(contexte);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  vente.libelleNumero,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '${formatDateHeure(vente.date)} · '
                  '${VenteService.libelleMode(vente.modePaiement)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Divider(height: 22),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: vente.lignes
                        .map((LigneVenteHistorique ligne) =>
                            _buildLigneDetail(theme, ligne))
                        .toList(),
                  ),
                ),
                const Divider(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    const Text('TOTAL',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      formatMontant(vente.total),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                // 🔐 MODULE 12 — annulation réservée au propriétaire (le
                // serveur le revérifie, la trace est CRITIQUE et écrite AVANT
                // toute modification).
                if (_peutAnnuler) ...<Widget>[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(contexte).pop();
                      _confirmerAnnulation(vente);
                    },
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Annuler cette vente'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade300),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  bool get _peutAnnuler {
    final RoleUtilisateur role = PermissionService.instance.roleCourant;
    return role == RoleUtilisateur.proprietaire ||
        role == RoleUtilisateur.superAdmin;
  }

  /// Demande la raison puis annule la vente côté serveur (transaction unique).
  Future<void> _confirmerAnnulation(VenteHistorique vente) async {
    final TextEditingController raisonController = TextEditingController();

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
          title: const Text('Annuler cette vente ?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '${vente.libelleNumero} — ${formatMontant(vente.total)}.\n'
                'Le stock sera restitué, l\'encaissement retiré de la caisse '
                'et l\'annulation journalisée (niveau CRITIQUE).',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: raisonController,
                autofocus: true,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Raison de l\'annulation *',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Retour'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Annuler la vente'),
            ),
          ],
        );
      },
    );

    if (confirme != true || !mounted) return;

    final String raison = raisonController.text.trim();
    if (raison.length < 3) {
      _snack('Indiquez la raison (3 caractères minimum).', erreur: true);
      return;
    }

    // `cle` vaut le vente_uuid, ou « ligne:<id> » pour une vente historique.
    final bool parLigne = vente.cle.startsWith('ligne:');
    final int? venteId =
        parLigne ? int.tryParse(vente.cle.substring('ligne:'.length)) : null;
    final String? venteUuid = parLigne ? null : vente.cle;

    try {
      await VenteService.instance.annulerVente(
        venteUuid: venteUuid,
        venteId: venteId,
        raison: raison,
      );
      if (!mounted) return;
      _snack('Vente annulée : stock restitué et caisse mise à jour.');
      _recharger();
    } on VenteServiceException catch (e) {
      if (!mounted) return;
      _snack(e.message, erreur: true);
    }
  }

  void _snack(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Widget _buildLigneDetail(ThemeData theme, LigneVenteHistorique ligne) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ligne.nom,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${_nombreTexte(ligne.quantiteVendue)} ${ligne.unite}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMontant(ligne.total),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// « 12 » pour une quantité entière, « 1 », « 0,5 » sinon.
String _nombreTexte(double valeur) {
  if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
  return valeur
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}
