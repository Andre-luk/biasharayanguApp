// lib/pages/distribution_pro_page.dart
//
// 🚚 MODULE 24 — TABLEAU DE BORD DE LA DISTRIBUTION.
//
// Distinct des tableaux de bord boutique/hôtel/restaurant : il parle
// d'INTRANTS, de PRODUITS FINIS, de productions, de commerciaux, de remises
// d'argent et de caisse. Chaque rôle ne voit que ce qui le concerne ; les
// mêmes chiffres viennent du serveur (`dist_tableau_bord`).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/pages/distribution_collaborateurs_page.dart';
import 'package:biashara_yangu/pages/distribution_commercial_page.dart';
import 'package:biashara_yangu/pages/distribution_finance_page.dart';
import 'package:biashara_yangu/pages/distribution_journal_page.dart';
import 'package:biashara_yangu/pages/distribution_production_page.dart';
import 'package:biashara_yangu/pages/distribution_stock_page.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/widgets/distribution_widgets.dart';

class DistributionProPage extends StatefulWidget {
  const DistributionProPage({super.key});

  @override
  State<DistributionProPage> createState() => _DistributionProPageState();
}

class _DistributionProPageState extends State<DistributionProPage> {
  final DistributionGestionService _service =
      DistributionGestionService.instance;

  TableauBordDistribution _bord = const TableauBordDistribution();
  List<AnomalieDistribution> _anomalies = const <AnomalieDistribution>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;
    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    try {
      final TableauBordDistribution bord = await _service.tableauBord();
      List<AnomalieDistribution> anomalies = _anomalies;
      if (bord.role.estDirection) {
        try {
          anomalies = await _service.anomalies();
        } catch (e) {
          debugPrint('DistributionProPage anomalies (ignoré) : $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _bord = bord;
        _anomalies = anomalies;
        _chargement = false;
        _erreur = null;
      });
    } on DistributionGestionException catch (e) {
      if (!mounted) return;
      if (silencieux) {
        _message(e.message, erreur: true);
        return;
      }
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e, st) {
      debugPrint('DistributionProPage._charger : $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur =
            'Impossible de charger le tableau de bord Distribution pour le moment.';
        _chargement = false;
      });
    }
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? Colors.red.shade700 : null,
      ),
    );
  }

  Future<void> _ouvrir(Widget page) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext _) => page),
    );
    if (mounted) _charger(silencieux: true);
  }

  Future<void> _ouvrirAnomalies() async {
    if (_anomalies.isEmpty) {
      _message('Aucune anomalie ouverte : tous les écarts sont résolus.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _anomalies.length,
              separatorBuilder: (_, __) => const Divider(height: 24),
              itemBuilder: (BuildContext _, int i) {
                final AnomalieDistribution a = _anomalies[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            a.type.replaceAll('_', ' '),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800),
                          ),
                        ),
                        PuceDistribution(
                          libelle: a.ouverte ? 'Ouverte' : 'Résolue',
                          couleur: a.ouverte
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(a.description),
                    if (a.quantite.abs() > 0)
                      ligneDistribution(
                        'Quantité contestée',
                        quantiteDistribution(a.quantite),
                      ),
                    if (a.montant.abs() > 0)
                      ligneDistribution(
                        'Montant',
                        montantDistribution(a.montant, devise: _bord.devise),
                      ),
                    if (a.ouverte)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () async {
                            final String? decision = await dialogueTexte(
                              ctx,
                              titre: 'Décision du gérant',
                              label: 'Décision (ex. régularisation acceptée)',
                            );
                            if (decision == null) return;
                            try {
                              await _service.resoudreAnomalie(a.id,
                                  decision: decision, motif: decision);
                              if (ctx.mounted) Navigator.of(ctx).pop();
                              _charger(silencieux: true);
                            } on DistributionGestionException catch (e) {
                              _message(e.message, erreur: true);
                            }
                          },
                          child: const Text('Enregistrer une décision'),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _suivreOperation(OperationAttente operation) {
    switch (operation.type) {
      case 'reception_intrants':
        _ouvrir(const DistributionStockPage(ongletInitial: 2));
      case 'demande_intrants_stock':
      case 'demande_intrants_reception':
        _ouvrir(const DistributionProductionPage());
      case 'production_reception':
        _ouvrir(const DistributionProductionPage(ongletInitial: 1));
      case 'demande_commercial_production':
      case 'demande_commercial_stock':
      case 'demande_commercial_reception':
        _ouvrir(DistributionCommercialPage(
          ongletInitial:
              _bord.role == RoleDistribution.commercial ? 5 : 0,
        ));
      case 'retour_reception':
        _ouvrir(const DistributionCommercialPage(ongletInitial: 3));
      case 'remise_comptable':
      case 'remise_gerant':
      case 'depense_validation':
        _ouvrir(const DistributionFinancePage(ongletInitial: 1));
      case 'anomalie':
        _ouvrirAnomalies();
      default:
        _charger(silencieux: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Distribution'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : RefreshIndicator(
                  onRefresh: () => _charger(),
                  child: _contenu(),
                ),
    );
  }

  Widget _vueErreur() {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.cloud_off_rounded,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(_erreur!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _charger(),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contenu() {
    final RoleDistribution role = _bord.role;
    final ThemeData theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        _hero(role),
        const SizedBox(height: 20),

        if (_bord.operations.isNotEmpty) ...<Widget>[
          SectionDistribution(
            titre: 'Opérations en attente',
            sousTitre:
                '${_bord.operations.length} opération(s) attendent une confirmation.',
            child: Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < _bord.operations.length; i++)
                    ListTile(
                      dense: true,
                      leading: Text(
                        _bord.operations[i].icone,
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: Text(_bord.operations[i].libelle),
                      subtitle: Text(
                        <String>[
                          if (_bord.operations[i].numero.isNotEmpty)
                            _bord.operations[i].numero,
                          _bord.operations[i].role.libelle,
                        ].join(' · '),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _suivreOperation(_bord.operations[i]),
                    ),
                ],
              ),
            ),
          ),
        ],

        if (role != RoleDistribution.commercial) ...<Widget>[
          SectionDistribution(
            titre: 'Stock des intrants',
            sousTitre: 'Matières premières disponibles pour la production.',
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: <Widget>[
                CarteKpiDistribution(
                  icone: Icons.science_outlined,
                  libelle: 'Total des intrants',
                  valeur: quantiteDistribution(_bord.intrantsTotal),
                ),
                CarteKpiDistribution(
                  icone: Icons.opacity_rounded,
                  libelle: 'PET',
                  valeur: quantiteDistribution(_bord.pet),
                  couleur: AppCouleurs.orange,
                ),
                CarteKpiDistribution(
                  icone: Icons.circle_outlined,
                  libelle: 'Caps / bouchons',
                  valeur: quantiteDistribution(_bord.caps),
                ),
                CarteKpiDistribution(
                  icone: Icons.local_drink_outlined,
                  libelle: 'Bouteilles vides',
                  valeur: quantiteDistribution(_bord.bouteillesVides),
                ),
              ],
            ),
          ),
          SectionDistribution(
            titre: 'Produits finis',
            sousTitre:
                'Stock central uniquement — hors dotations des commerciaux.',
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: <Widget>[
                CarteKpiDistribution(
                  icone: Icons.inventory_2_outlined,
                  libelle: 'Total produits finis',
                  valeur: quantiteDistribution(_bord.produitsTotal),
                ),
                CarteKpiDistribution(
                  icone: Icons.grid_view_rounded,
                  libelle: 'Fardes',
                  valeur: quantiteDistribution(_bord.fardes),
                  couleur: Colors.blue.shade700,
                ),
                CarteKpiDistribution(
                  icone: Icons.local_drink_rounded,
                  libelle: 'Bouteilles',
                  valeur: quantiteDistribution(_bord.bouteilles),
                  couleur: Colors.teal.shade700,
                ),
                CarteKpiDistribution(
                  icone: Icons.water_drop_outlined,
                  libelle: 'Gros bidons remplis',
                  valeur: quantiteDistribution(_bord.bidons),
                  couleur: Colors.indigo.shade600,
                ),
              ],
            ),
          ),
        ],

        SectionDistribution(
          titre: 'Flux et validations',
          sousTitre: 'Ce qui circule entre production, stock et commerciaux.',
          child: Column(
            children: <Widget>[
              _ligneFlux('Produits attribués aux commerciaux',
                  quantiteDistribution(_bord.attribuesCommerciaux)),
              _ligneFlux('Demandes de production en attente du stock',
                  '${_bord.demandesIntrantsAttenteStock}'),
              _ligneFlux('Intrants sortis, en attente du producteur',
                  '${_bord.demandesIntrantsAttenteProduction}'),
              _ligneFlux('Productions en attente de réception au stock',
                  '${_bord.productionsAttenteStock}'),
              _ligneFlux('Réceptions d\'intrants à confirmer (gérant)',
                  '${_bord.receptionsAttenteGerant}'),
              _ligneFlux('Demandes commerciales en cours',
                  '${_bord.demandesCommercialesEnCours}'),
              _ligneFlux('Retours à compter par le stock',
                  '${_bord.retoursAttenteStock}'),
              _ligneFlux('Anomalies ouvertes',
                  '${_bord.anomaliesOuvertes}',
                  alerte: _bord.anomaliesOuvertes > 0),
            ],
          ),
        ),

        if (role != RoleDistribution.commercial)
          SectionDistribution(
            titre: 'Argent',
            sousTitre:
                'Les ventes d\'un commercial n\'entrent en caisse qu\'après validation du gérant.',
            child: GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.55,
              children: <Widget>[
                CarteKpiDistribution(
                  icone: Icons.point_of_sale_rounded,
                  libelle: 'Ventes réalisées',
                  valeur:
                      montantDistribution(_bord.ventesTotal, devise: _bord.devise),
                  couleur: Colors.green.shade700,
                ),
                CarteKpiDistribution(
                  icone: Icons.savings_outlined,
                  libelle: 'Collecté non remis',
                  valeur: montantDistribution(_bord.collecteNonRemise,
                      devise: _bord.devise),
                  couleur: Colors.orange.shade800,
                ),
                CarteKpiDistribution(
                  icone: Icons.verified_outlined,
                  libelle: 'Reçu et validé (comptable)',
                  valeur: montantDistribution(_bord.montantRecuComptable,
                      devise: _bord.devise),
                ),
                CarteKpiDistribution(
                  icone: Icons.account_balance_wallet_rounded,
                  libelle: 'Caisse disponible',
                  valeur: montantDistribution(_bord.caisseSolde,
                      devise: _bord.devise),
                  couleur: AppCouleurs.orange,
                  onTap: role.estDirection ||
                          role == RoleDistribution.comptable
                      ? () => _ouvrir(const DistributionFinancePage())
                      : null,
                ),
                CarteKpiDistribution(
                  icone: Icons.receipt_long_outlined,
                  libelle: 'Dépenses du mois',
                  valeur: montantDistribution(_bord.depensesMois,
                      devise: _bord.devise),
                  couleur: Colors.red.shade700,
                ),
              ],
            ),
          ),

        SectionDistribution(
          titre: 'Accès rapides',
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: <Widget>[
              if (role != RoleDistribution.commercial)
                TuileDistribution(
                  icone: Icons.inventory_2_outlined,
                  libelle: 'Stock',
                  badge: _bord.receptionsAttenteGerant,
                  onTap: () => _ouvrir(const DistributionStockPage()),
                ),
              if (role.peutProduire)
                TuileDistribution(
                  icone: Icons.factory_outlined,
                  libelle: 'Production',
                  badge: _bord.demandesIntrantsAttenteStock +
                      _bord.productionsAttenteStock,
                  onTap: () => _ouvrir(const DistributionProductionPage()),
                ),
              if (role.peutVendre || role.estDirection)
                TuileDistribution(
                  icone: Icons.local_shipping_outlined,
                  libelle: 'Commerciaux',
                  badge: _bord.demandesCommercialesEnCours +
                      _bord.retoursAttenteStock,
                  onTap: () => _ouvrir(const DistributionCommercialPage()),
                ),
              if (role.peutValiderArgent)
                TuileDistribution(
                  icone: Icons.account_balance_outlined,
                  libelle: 'Caisse & dépenses',
                  badge: _bord.remisesAttenteComptable +
                      _bord.remisesAttenteGerant +
                      _bord.depensesAttente,
                  onTap: () => _ouvrir(const DistributionFinancePage()),
                ),
              if (role.estDirection)
                TuileDistribution(
                  icone: Icons.warning_amber_rounded,
                  libelle: 'Anomalies',
                  badge: _bord.anomaliesOuvertes,
                  couleur: Colors.red.shade700,
                  onTap: _ouvrirAnomalies,
                ),
              TuileDistribution(
                icone: Icons.history_rounded,
                libelle: 'Traçabilité',
                onTap: () => _ouvrir(const DistributionJournalPage()),
              ),
              if (role.peutGererCollaborateurs)
                TuileDistribution(
                  icone: Icons.groups_2_outlined,
                  libelle: 'Collaborateurs',
                  onTap: () => _ouvrir(const DistributionCollaborateursPage()),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ligneFlux(String libelle, String valeur, {bool alerte = false}) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              libelle,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            valeur,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: alerte ? Colors.red.shade700 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(RoleDistribution role) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppDegrades.primaire,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.local_shipping_rounded,
                  color: Colors.white, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Production & distribution',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Vous êtes connecté comme « ${role.libelle} ».',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.88),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _puceHero(
                  Icons.pending_actions_rounded,
                  '${_bord.totalEnAttente} en attente'),
              _puceHero(
                  Icons.account_balance_wallet_rounded,
                  montantDistribution(_bord.caisseSolde, devise: _bord.devise)),
              if (_bord.tourneesEnCours > 0)
                _puceHero(Icons.route_rounded,
                    '${_bord.tourneesEnCours} tournée(s)'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _puceHero(IconData icone, String texte) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icone, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            texte,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
