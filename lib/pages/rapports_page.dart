// lib/pages/rapports_page.dart
//
// MODULE 11 — ÉCRAN « RAPPORTS ».
//
// Un seul écran pour TOUS les rapports (boutique et plateforme) :
//   1. sélection du type de rapport (la liste est filtrée par les droits) ;
//   2. sélection de la période (raccourcis + plage personnalisée) ;
//   3. filtres propres au type (regroupement, statut, catégorie…) ;
//   4. aperçu (indicateurs + tableau avec totaux) AVANT export ;
//   5. exports : PDF, Excel, partage, impression — chaque opération est
//      tracée côté serveur (registre `rapports_generes` + journal d'audit).
//
// 🔐 MODULE 4 — la page est ouverte par les rôles qui possèdent la page
// `rapports` (propriétaire, comptable, magasinier, Super Admin, Finance La
// Perle) ; chaque type est EN PLUS filtré par les droits fins et le serveur
// revérifie tout (un vendeur reçoit DROIT_REFUSE).

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/rapport.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/rapport_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Raccourcis de période proposés en haut de l'écran.
enum _RaccourciPeriode {
  aujourdHui('Aujourd\'hui'),
  septJours('7 jours'),
  trenteJours('30 jours'),
  ceMois('Ce mois'),
  personnalise('Personnalisée');

  const _RaccourciPeriode(this.libelle);

  final String libelle;
}

class RapportsPage extends StatefulWidget {
  const RapportsPage({super.key, this.showAppBar = true});

  /// `false` quand la page est affichée dans un onglet qui fournit déjà
  /// l'AppBar (espace Super Admin).
  final bool showAppBar;

  @override
  State<RapportsPage> createState() => _RapportsPageState();
}

class _RapportsPageState extends State<RapportsPage> {
  final RapportService _service = RapportService.instance;
  final PermissionService _permissions = PermissionService.instance;

  late final List<TypeRapport> _types;
  TypeRapport? _type;

  _RaccourciPeriode _raccourci = _RaccourciPeriode.trenteJours;
  late DateTime _debut;
  late DateTime _fin;

  // Filtres (utilisés selon le type sélectionné).
  GroupePeriodeRapport _groupe = GroupePeriodeRapport.jour;
  int _limiteTop = 10;
  // 🧩 MODULE 16 C1 — pharmacie : horizon du rapport « Expirations ».
  int _joursExpiration = 90;
  final TextEditingController _controleurCategorie = TextEditingController();
  bool _alerteSeulement = false;
  bool _detailDepenses = false;
  String? _statutDettes;

  bool _chargement = false;
  bool _exportEnCours = false;
  String? _erreur;
  ResultatRapport? _resultat;

  String? _nomEntreprise;
  Uint8List? _logo;

  @override
  void initState() {
    super.initState();

    final DateTime aujourdHui = DateTime.now();
    _fin = DateTime(aujourdHui.year, aujourdHui.month, aujourdHui.day);
    _debut = _fin.subtract(const Duration(days: 29));

    _types = TypeRapport.values.where(_autorise).toList(growable: false);
    _type = _types.isEmpty ? null : _types.first;

    _chargerContexte();
    if (_type != null) {
      _generer();
    }
  }

  @override
  void dispose() {
    _controleurCategorie.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // DROITS — la liste des types est filtrée par la matrice du Module 4.
  // ---------------------------------------------------------------------------

  bool _estPlateforme() => _permissions.roleCourant.estPlateforme;

  /// `true` si le rôle peut générer ce rapport (le serveur revérifie).
  bool _autorise(TypeRapport type) {
    if (_estPlateforme()) {
      if (!type.estPlateforme) return false;
    } else if (type.estPlateforme) {
      return false;
    }

    switch (type) {
      case TypeRapport.ventes:
      case TypeRapport.ventesArticle:
      case TypeRapport.ventesCategorie:
      case TypeRapport.ventesVendeur:
      case TypeRapport.topProduits:
        return _permissions.peut(PageAccess.rapports, ActionAccess.voir);
      case TypeRapport.finance:
        return _permissions.peut(PageAccess.finance, ActionAccess.voir);
      case TypeRapport.stock:
        return _permissions.peut(PageAccess.rapports, ActionAccess.voir) ||
            _permissions.peut(PageAccess.stock, ActionAccess.voir);
      case TypeRapport.caisse:
      case TypeRapport.dettes:
        return _permissions.peut(PageAccess.caisse, ActionAccess.voir) ||
            _permissions.peut(PageAccess.finance, ActionAccess.voir);
      case TypeRapport.depenses:
        return _permissions.peut(PageAccess.depenses, ActionAccess.voir);
      case TypeRapport.expirations:
        // 🧩 MODULE 16 C1 — le rapport « Expirations » n'apparaît que si
        // l'activité a le module lots_expiration (pharmacie…).
        return _permissions.peut(PageAccess.articles, ActionAccess.voir) &&
            ModulesService.instance.moduleActif(ModuleCode.lotsExpiration);
      case TypeRapport.plateformeRevenus:
      case TypeRapport.plateformeImpayes:
      case TypeRapport.plateformeVilles:
      case TypeRapport.plateformeActivites:
        return _permissions.peut(PageAccess.finance, ActionAccess.voir) ||
            _permissions.peut(PageAccess.paiements, ActionAccess.voir);
      case TypeRapport.plateformeAbonnements:
        return _permissions.peut(PageAccess.abonnements, ActionAccess.voir) ||
            _permissions.peut(PageAccess.rapports, ActionAccess.voir);
      case TypeRapport.plateformeNouveauxComptes:
        return _permissions.peut(PageAccess.entreprises, ActionAccess.voir) ||
            _permissions.peut(PageAccess.rapports, ActionAccess.voir);
    }
  }

  /// `true` si le type utilise la période (le stock et les expirations
  /// n'en dépendent pas).
  bool get _typeUtilisePeriode =>
      _type != null &&
      _type != TypeRapport.stock &&
      _type != TypeRapport.expirations;

  // ---------------------------------------------------------------------------
  // CONTEXTE (nom d'entreprise + logo pour les exports)
  // ---------------------------------------------------------------------------

  Future<void> _chargerContexte() async {
    final String? nom =
        _estPlateforme() ? 'La Perle' : await _service.nomEntrepriseCourante();
    final Uint8List? logo = await _service.chargerLogo();
    if (!mounted) return;
    setState(() {
      _nomEntreprise = nom;
      _logo = logo;
    });
  }

  // ---------------------------------------------------------------------------
  // GÉNÉRATION
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _filtresPour(TypeRapport type) {
    switch (type) {
      case TypeRapport.ventes:
        return <String, dynamic>{'groupe': _groupe.code};
      case TypeRapport.topProduits:
        return <String, dynamic>{'limite': _limiteTop};
      case TypeRapport.stock:
        return <String, dynamic>{
          if (_controleurCategorie.text.trim().isNotEmpty)
            'categorie': _controleurCategorie.text.trim(),
          'alerte_seulement': _alerteSeulement,
        };
      case TypeRapport.depenses:
        return <String, dynamic>{'detail': _detailDepenses};
      case TypeRapport.dettes:
        return <String, dynamic>{
          if (_statutDettes != null && _statutDettes!.isNotEmpty)
            'statut': _statutDettes,
        };
      case TypeRapport.expirations:
        // 🧩 MODULE 16 C1 — horizon (jours) du rapport pharmacie.
        return <String, dynamic>{'jours': _joursExpiration};
      case TypeRapport.plateformeNouveauxComptes:
        return <String, dynamic>{'groupe': _groupe.code};
      default:
        return const <String, dynamic>{};
    }
  }

  Future<void> _generer() async {
    final TypeRapport? type = _type;
    if (type == null || _chargement) return;

    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final ResultatRapport resultat = await _service.generer(
        type: type,
        debut: _typeUtilisePeriode ? _debut : null,
        fin: _typeUtilisePeriode ? _fin : null,
        filtres: _filtresPour(type),
      );
      if (!mounted) return;
      setState(() => _resultat = resultat);
    } on RapportServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _resultat = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de générer le rapport : $e';
        _resultat = null;
      });
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  // ---------------------------------------------------------------------------
  // PÉRIODE
  // ---------------------------------------------------------------------------

  void _appliquerRaccourci(_RaccourciPeriode raccourci) {
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdHui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);

    if (raccourci == _RaccourciPeriode.personnalise) {
      _choisirPeriodePersonnalisee();
      return;
    }

    setState(() {
      _raccourci = raccourci;
      switch (raccourci) {
        case _RaccourciPeriode.aujourdHui:
          _debut = aujourdHui;
          _fin = aujourdHui;
        case _RaccourciPeriode.septJours:
          _debut = aujourdHui.subtract(const Duration(days: 6));
          _fin = aujourdHui;
        case _RaccourciPeriode.trenteJours:
          _debut = aujourdHui.subtract(const Duration(days: 29));
          _fin = aujourdHui;
        case _RaccourciPeriode.ceMois:
          _debut = DateTime(aujourdHui.year, aujourdHui.month, 1);
          _fin = aujourdHui;
        case _RaccourciPeriode.personnalise:
          return;
      }
    });
    _generer();
  }

  Future<void> _choisirPeriodePersonnalisee() async {
    final DateTime maintenant = DateTime.now();
    final DateTimeRange? plage = await showDateRangePicker(
      context: context,
      firstDate: DateTime(maintenant.year - 3),
      lastDate: DateTime(maintenant.year, maintenant.month, maintenant.day),
      initialDateRange: DateTimeRange(start: _debut, end: _fin),
      helpText: 'Période du rapport',
      saveText: 'Valider',
    );
    if (plage == null) return;
    setState(() {
      _raccourci = _RaccourciPeriode.personnalise;
      _debut = plage.start;
      _fin = plage.end;
    });
    _generer();
  }

  // ---------------------------------------------------------------------------
  // EXPORTS
  // ---------------------------------------------------------------------------

  Future<void> _exporter({required String action}) async {
    final ResultatRapport? resultat = _resultat;
    if (resultat == null || _exportEnCours) return;

    setState(() => _exportEnCours = true);
    try {
      switch (action) {
        case 'pdf':
          final String chemin = await _service.exporterPDF(
            resultat,
            nomEntreprise: _nomEntreprise,
            logo: _logo,
          );
          _snack('PDF enregistré : $chemin', succes: true, dureeLongue: true);
        case 'excel':
          final String chemin = await _service.exporterExcel(
            resultat,
            nomEntreprise: _nomEntreprise,
          );
          _snack('Excel enregistré : $chemin', succes: true, dureeLongue: true);
        case 'partage':
          await _service.partagerPDF(
            resultat,
            nomEntreprise: _nomEntreprise,
            logo: _logo,
          );
        case 'impression':
          await _service.imprimerPDF(
            resultat,
            nomEntreprise: _nomEntreprise,
            logo: _logo,
          );
      }
    } on RapportServiceException catch (e) {
      _snack(e.message, succes: false);
    } catch (e) {
      _snack('Export impossible : $e', succes: false);
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  void _snack(String message,
      {required bool succes, bool dureeLongue = false}) {
    if (!mounted) return;
    final ThemeData theme = Theme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            succes ? theme.colorScheme.primary : Colors.red.shade700,
        duration: Duration(seconds: dureeLongue ? 6 : 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HISTORIQUE
  // ---------------------------------------------------------------------------

  void _ouvrirHistorique() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          builder: (BuildContext context, ScrollController controleur) {
            return FutureBuilder<List<EntreeHistoriqueRapport>>(
              future: _service.historique(limit: 50),
              builder: (BuildContext context,
                  AsyncSnapshot<List<EntreeHistoriqueRapport>> snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Impossible de charger l\'historique : ${snapshot.error}',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  );
                }

                final List<EntreeHistoriqueRapport> entrees =
                    snapshot.data ?? const <EntreeHistoriqueRapport>[];
                if (entrees.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Aucun rapport généré pour le moment.'),
                    ),
                  );
                }

                return ListView.separated(
                  controller: controleur,
                  itemCount: entrees.length + 1,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (BuildContext context, int index) {
                    if (index == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                        child: Text(
                          'Historique des exports (registre tracé)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }
                    final EntreeHistoriqueRapport entree = entrees[index - 1];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.secondaryContainer,
                        child: Icon(_iconeFormat(entree.format), size: 20),
                      ),
                      title: Text(entree.libelleType),
                      subtitle: Text(
                        <String>[
                          entree.reference,
                          if (entree.periodeTexte != null) entree.periodeTexte!,
                          if (entree.utilisateur.isNotEmpty) entree.utilisateur,
                          formatDateHeure(entree.createdAt),
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        entree.format.libelle,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      onTap: entree.empreinte == null
                          ? null
                          : () {
                              showDialog<void>(
                                context: context,
                                builder: (BuildContext context) => AlertDialog(
                                  title: const Text('Empreinte de l\'export'),
                                  content: SelectableText(entree.empreinte!),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      child: const Text('Fermer'),
                                    ),
                                  ],
                                ),
                              );
                            },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  IconData _iconeFormat(FormatExportRapport format) {
    switch (format) {
      case FormatExportRapport.apercu:
        return Icons.visibility_outlined;
      case FormatExportRapport.pdf:
        return Icons.picture_as_pdf_outlined;
      case FormatExportRapport.excel:
        return Icons.grid_on_outlined;
      case FormatExportRapport.partage:
        return Icons.share_outlined;
      case FormatExportRapport.impression:
        return Icons.print_outlined;
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  PreferredSizeWidget? _appBar() {
    if (!widget.showAppBar) return null;
    return AppBar(
      title: const Text(
        'Rapports',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
      ),
      actions: <Widget>[
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'Historique des exports',
          onPressed: _ouvrirHistorique,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Régénérer',
          onPressed: _type == null ? null : _generer,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_types.isEmpty) {
      return Scaffold(
        appBar: _appBar(),
        body: const AccesRefuse(
          message: 'Votre rôle ne permet pas de générer de rapports.',
        ),
      );
    }

    return Scaffold(
      appBar: _appBar(),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _carteSelection(),
          if (_typeUtilisePeriode) ...<Widget>[
            const SizedBox(height: 12),
            _cartePeriode(),
          ],
          if (_aDesFiltres(_type)) ...<Widget>[
            const SizedBox(height: 12),
            _carteFiltres(_type!),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _chargement ? null : _generer,
            icon: const Icon(Icons.auto_graph),
            label: const Text('Générer l\'aperçu'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_chargement) ...<Widget>[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_erreur != null && !_chargement) ...<Widget>[
            const SizedBox(height: 16),
            _bandeauErreur(_erreur!),
          ],
          if (_resultat != null && !_chargement) ...<Widget>[
            const SizedBox(height: 16),
            _apercuResume(_resultat!),
            const SizedBox(height: 16),
            _apercuTableau(_resultat!),
            const SizedBox(height: 16),
            _barreExports(),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: _ouvrirHistorique,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Historique des rapports générés'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- type de rapport

  Widget _carteSelection() {
    final TypeRapport? type = _type;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  _estPlateforme() ? Icons.public : Icons.business_rounded,
                  size: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  _estPlateforme()
                      ? 'Rapports La Perle'
                      : 'Rapports de l\'entreprise',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppDropdownField<TypeRapport>(
              label: 'Type de rapport',
              value: type,
              prefixIcon: Icons.description_outlined,
              onChanged: (TypeRapport? valeur) {
                if (valeur == null || valeur == _type) return;
                setState(() {
                  _type = valeur;
                  _resultat = null;
                  _erreur = null;
                });
                _generer();
              },
              items: _types
                  .map(
                    (TypeRapport t) => DropdownMenuItem<TypeRapport>(
                      value: t,
                      child: Text(t.libelle, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(growable: false),
            ),
            if (type != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                type.description,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ période

  Widget _cartePeriode() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Période',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _RaccourciPeriode.values
                  .map(
                    (_RaccourciPeriode raccourci) => ChoiceChip(
                      label: Text(raccourci.libelle),
                      selected: _raccourci == raccourci,
                      onSelected: (_) => _appliquerRaccourci(raccourci),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                const Icon(Icons.calendar_today_outlined, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Du ${formatDate(_debut)} au ${formatDate(_fin)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _choisirPeriodePersonnalisee,
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: const Text('Modifier'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ filtres

  bool _aDesFiltres(TypeRapport? type) {
    switch (type) {
      case TypeRapport.ventes:
      case TypeRapport.topProduits:
      case TypeRapport.stock:
      case TypeRapport.depenses:
      case TypeRapport.dettes:
      case TypeRapport.plateformeNouveauxComptes:
        return true;
      default:
        return false;
    }
  }

  Widget _carteFiltres(TypeRapport type) {
    final List<Widget> enfants = <Widget>[];

    switch (type) {
      case TypeRapport.ventes:
      case TypeRapport.plateformeNouveauxComptes:
        enfants.add(const Text('Regroupement',
            style: TextStyle(fontWeight: FontWeight.bold)));
        enfants.add(const SizedBox(height: 8));
        enfants.add(
          Wrap(
            spacing: 8,
            children: GroupePeriodeRapport.values
                .map(
                  (GroupePeriodeRapport groupe) => ChoiceChip(
                    label: Text(groupe.libelle),
                    selected: _groupe == groupe,
                    onSelected: (_) {
                      setState(() => _groupe = groupe);
                      _generer();
                    },
                  ),
                )
                .toList(growable: false),
          ),
        );
      case TypeRapport.topProduits:
        enfants.add(
          AppDropdownField<int>(
            label: 'Nombre d\'articles',
            value: _limiteTop,
            prefixIcon: Icons.filter_list,
            onChanged: (int? valeur) {
              if (valeur == null) return;
              setState(() => _limiteTop = valeur);
              _generer();
            },
            items: const <int>[5, 10, 20, 50]
                .map((int n) => DropdownMenuItem<int>(
                      value: n,
                      child: Text('Top $n'),
                    ))
                .toList(growable: false),
          ),
        );
      case TypeRapport.stock:
        enfants.add(
          TextField(
            controller: _controleurCategorie,
            decoration: InputDecoration(
              labelText: 'Catégorie (facultatif)',
              prefixIcon: const Icon(Icons.category_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
            onSubmitted: (_) => _generer(),
          ),
        );
        enfants.add(
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Alertes seulement (stock ≤ seuil)'),
            value: _alerteSeulement,
            onChanged: (bool valeur) {
              setState(() => _alerteSeulement = valeur);
              _generer();
            },
          ),
        );
      case TypeRapport.depenses:
        enfants.add(
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Détail ligne à ligne'),
            subtitle: const Text('Désactivé : regroupement par catégorie'),
            value: _detailDepenses,
            onChanged: (bool valeur) {
              setState(() => _detailDepenses = valeur);
              _generer();
            },
          ),
        );
      case TypeRapport.expirations:
        // 🧩 MODULE 16 C1 — pharmacie : horizon du suivi.
        enfants.add(const Text('Horizon du suivi',
            style: TextStyle(fontWeight: FontWeight.bold)));
        enfants.add(const SizedBox(height: 8));
        enfants.add(
          Wrap(
            spacing: 8,
            children: <int>[30, 90, 365]
                .map(
                  (int jours) => ChoiceChip(
                    label: Text(jours == 365 ? '1 an' : '≤ $jours jours'),
                    selected: _joursExpiration == jours,
                    onSelected: (_) {
                      setState(() => _joursExpiration = jours);
                      _generer();
                    },
                  ),
                )
                .toList(growable: false),
          ),
        );
      case TypeRapport.dettes:
        enfants.add(const Text('Statut des dettes',
            style: TextStyle(fontWeight: FontWeight.bold)));
        enfants.add(const SizedBox(height: 8));
        enfants.add(
          Wrap(
            spacing: 8,
            children: <Widget>[
              _chipStatut('Toutes', null),
              _chipStatut('Non payées', 'non_paye'),
              _chipStatut('Partielles', 'partiel'),
              _chipStatut('Payées', 'paye'),
            ],
          ),
        );
      default:
        break;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: enfants,
        ),
      ),
    );
  }

  Widget _chipStatut(String libelle, String? statut) {
    return ChoiceChip(
      label: Text(libelle),
      selected: _statutDettes == statut,
      onSelected: (_) {
        setState(() => _statutDettes = statut);
        _generer();
      },
    );
  }

  // ------------------------------------------------------------------- erreur

  Widget _bandeauErreur(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.error_outline, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ aperçu

  Widget _apercuResume(ResultatRapport resultat) {
    final RapportDonnees donnees = resultat.donnees;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                donnees.titre,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Text(
              'Réf. ${resultat.reference}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (donnees.resume.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: donnees.resume
                .map(
                  (LigneResumeRapport indicateur) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          indicateur.libelle,
                          style: const TextStyle(fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          indicateur.valeurFormatee,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _apercuTableau(ResultatRapport resultat) {
    final RapportDonnees donnees = resultat.donnees;

    if (donnees.estVide) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text('Aucune donnée disponible pour cette période.'),
          ),
        ),
      );
    }

    const int maxApercu = 50;
    final List<Map<String, dynamic>> lignes =
        donnees.lignes.take(maxApercu).toList(growable: false);
    final bool aTotaux = donnees.colonnes.any(donnees.aTotal);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                donnees.lignes.length > maxApercu
                    ? 'Aperçu : $maxApercu premières lignes sur ${donnees.lignes.length} — l\'export contient tout.'
                    : '${donnees.lignes.length} ligne(s)',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 42,
                horizontalMargin: 16,
                columnSpacing: 18,
                columns: donnees.colonnes
                    .map(
                      (ColonneRapport colonne) => DataColumn(
                        label: Text(
                          colonne.libelle,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        numeric: _estNumerique(colonne.type),
                      ),
                    )
                    .toList(growable: false),
                rows: <DataRow>[
                  ...lignes.map(
                    (Map<String, dynamic> ligne) => DataRow(
                      cells: donnees.colonnes
                          .map(
                            (ColonneRapport colonne) => DataCell(
                              Text(
                                donnees.valeurFormatee(ligne, colonne),
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                  if (aTotaux)
                    DataRow(
                      color: WidgetStatePropertyAll<Color?>(
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                      ),
                      cells: <DataCell>[
                        for (int i = 0; i < donnees.colonnes.length; i++)
                          DataCell(
                            Text(
                              i == 0
                                  ? 'TOTAUX'
                                  : (donnees
                                          .totalFormate(donnees.colonnes[i]) ??
                                      ''),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _estNumerique(TypeColonneRapport type) =>
      type == TypeColonneRapport.montant ||
      type == TypeColonneRapport.nombre ||
      type == TypeColonneRapport.pourcentage;

  // -------------------------------------------------------------------- exports

  Widget _barreExports() {
    final bool actif = _resultat != null && !_exportEnCours;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Exporter le rapport',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Chaque export est signé (référence + empreinte) et tracé dans le journal.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: actif ? () => _exporter(action: 'pdf') : null,
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('PDF'),
                ),
                FilledButton.tonalIcon(
                  onPressed: actif ? () => _exporter(action: 'excel') : null,
                  icon: const Icon(Icons.grid_on_outlined),
                  label: const Text('Excel'),
                ),
                OutlinedButton.icon(
                  onPressed: actif ? () => _exporter(action: 'partage') : null,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Partager'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      actif ? () => _exporter(action: 'impression') : null,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Imprimer'),
                ),
              ],
            ),
            if (_exportEnCours) ...<Widget>[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
