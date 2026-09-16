// lib/pages/depenses_finance_page.dart
//
// MODULE 10 — ÉCRAN « DÉPENSES » (Supabase).
//
// Remplace l'ancien écran SQLite (conservé dans le projet mais débranché) :
// les dépenses sont stockées dans `public.depenses`, lues via
// `rpc_depenses_liste`, créées par `rpc_depense_creer` et supprimées par
// `rpc_depense_supprimer` (chaque opération est journalisée côté serveur).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/depense_finance.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/finance_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class DepensesFinancePage extends StatefulWidget {
  const DepensesFinancePage({super.key});

  @override
  State<DepensesFinancePage> createState() => _DepensesFinancePageState();
}

class _DepensesFinancePageState extends State<DepensesFinancePage> {
  final FinanceService _finance = FinanceService.instance;

  bool _chargement = true;
  String? _erreur;
  ResultatListeDepenses? _liste;

  /// Période en jours (`null` = tout l'historique).
  int? _jours = 30;
  String? _categorie;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  DateTime? get _debut {
    final int? jours = _jours;
    if (jours == null) return null;
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdHui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    return aujourdHui.subtract(Duration(days: jours - 1));
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = _liste == null;
      _erreur = null;
    });
    try {
      final ResultatListeDepenses liste = await _finance.listerDepenses(
        debut: _debut,
        fin: DateTime.now(),
        categorie: _categorie,
      );
      if (!mounted) return;
      setState(() => _liste = liste);
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreur = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreur = 'Impossible de charger les dépenses : $e');
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  bool get _peutCreer =>
      PermissionService.instance.peut(PageAccess.depenses, ActionAccess.creer);
  bool get _peutSupprimer => PermissionService.instance
      .peut(PageAccess.depenses, ActionAccess.supprimer);

  Future<void> _ouvrirFormulaire() async {
    final bool? cree = await context.push<bool>('/main/depenses/new');
    if (cree == true) _charger();
  }

  Future<void> _supprimer(DepenseFinance depense) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Supprimer la dépense ?'),
        content: Text(
          '${depense.motif}\n${formatMontant(depense.montant)} — ${formatDate(depense.date)}\n\n'
          'À réserver aux erreurs de saisie : la suppression est tracée dans le journal.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    try {
      await _finance.supprimerDepense(depense.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dépense « ${depense.motif} » supprimée.'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      _charger();
    } on FinanceServiceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red.shade700),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RENDU
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Dépenses',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _peutCreer
          ? FloatingActionButton.extended(
              onPressed: _ouvrirFormulaire,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nouvelle dépense'),
            )
          : null,
      body: _construireCorps(),
    );
  }

  Widget _construireCorps() {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.cloud_off_rounded,
                  size: 56, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _charger,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final ResultatListeDepenses liste = _liste ?? const ResultatListeDepenses();

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: <Widget>[
          _carteTotaux(liste),
          const SizedBox(height: 12),
          _filtres(liste),
          const SizedBox(height: 12),
          if (liste.lignes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  children: <Widget>[
                    Icon(Icons.payments_rounded,
                        size: 40,
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 8),
                    const Text('Aucune dépense sur la période.'),
                  ],
                ),
              ),
            )
          else
            ...liste.lignes.map(
              (DepenseFinance depense) => _tuileDepense(depense),
            ),
        ],
      ),
    );
  }

  Widget _carteTotaux(ResultatListeDepenses liste) {
    final ThemeData theme = Theme.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.shade700.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.payments_rounded,
                  color: Colors.red.shade700, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Total des dépenses',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    formatMontant(liste.totaux.total),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade700,
                    ),
                  ),
                  Text(
                    '${liste.totaux.nb} dépense(s) · moyenne ${formatMontant(liste.totaux.moyenne)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filtres(ResultatListeDepenses liste) {
    final List<String> categories = <String>{
      ...FinanceService.categoriesParDefaut,
      ...liste.categories,
    }.toList()
      ..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              ChoiceChip(
                label: const Text('7 jours'),
                selected: _jours == 7,
                onSelected: (bool selection) {
                  if (!selection) return;
                  setState(() => _jours = 7);
                  _charger();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('30 jours'),
                selected: _jours == 30,
                onSelected: (bool selection) {
                  if (!selection) return;
                  setState(() => _jours = 30);
                  _charger();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Tout'),
                selected: _jours == null,
                onSelected: (bool selection) {
                  if (!selection) return;
                  setState(() => _jours = null);
                  _charger();
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Catégorie',
            prefixIcon: const Icon(Icons.label_outline_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _categorie,
              isExpanded: true,
              isDense: true,
              items: <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Toutes les catégories'),
                ),
                ...categories.map(
                  (String categorie) => DropdownMenuItem<String?>(
                    value: categorie,
                    child: Text(categorie),
                  ),
                ),
              ],
              onChanged: (String? valeur) {
                setState(() => _categorie = valeur);
                _charger();
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _tuileDepense(DepenseFinance depense) {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.red.shade700.withValues(alpha: 0.1),
          child: Icon(Icons.payments_rounded,
              color: Colors.red.shade700, size: 20),
        ),
        title: Text(
          depense.motif,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${formatDate(depense.date)} · ${depense.categorie}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              formatMontant(depense.montant),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            if (_peutSupprimer)
              PopupMenuButton<String>(
                tooltip: 'Actions',
                onSelected: (String action) {
                  if (action == 'supprimer') _supprimer(depense);
                },
                itemBuilder: (BuildContext context) =>
                    <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'supprimer',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline_rounded),
                      title: Text('Supprimer'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
