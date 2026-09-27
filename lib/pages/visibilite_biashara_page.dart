// lib/pages/visibilite_biashara_page.dart
//
// 🛒 MODULE 19 — « MA VISIBILITÉ BIASHARA » (TABLEAU DE BORD COMMERÇANT).
//
// Répond à la seule question qui compte pour le patron : « qu'est-ce que
// Biashara m'apporte réellement ? »
//
// Les indicateurs sont présentés en QUATRE niveaux bien distincts, du plus
// faible au plus fort engagement :
//
//   VISIBILITÉ → l'article a été AFFICHÉ dans une recherche ;
//   INTÉRÊT     → la fiche a été CONSULTÉE, partagée ou cliquée ;
//   INTENTION   → la personne a demandé l'ITINÉRAIRE, a APPELÉ, a écrit ;
//   CONVERSION  → un achat a été RÉELLEMENT attribué à Biashara.
//
// ⚠️ Une consultation n'est JAMAIS comptée comme un achat. La conversion
//    n'apparaît que lorsqu'un code d'attribution (QR/lien/code) a été utilisé :
//    c'est la seule mesure honnête.

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/lien_attribution.dart';
import 'package:biashara_yangu/models/visibilite_biashara.dart';
import 'package:biashara_yangu/services/vitrine_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';

class VisibiliteBiasharaPage extends StatefulWidget {
  const VisibiliteBiasharaPage({super.key});

  @override
  State<VisibiliteBiasharaPage> createState() => _VisibiliteBiasharaPageState();
}

class _VisibiliteBiasharaPageState extends State<VisibiliteBiasharaPage> {
  final VitrineService _vitrine = VitrineService.instance;

  VisibiliteBiashara? _donnees;
  List<LienAttribution> _codes = const <LienAttribution>[];
  int _jours = 30;
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final DateTime fin = DateTime.now();
      final VisibiliteBiashara donnees = await _vitrine.visibilite(
        debut: fin.subtract(Duration(days: _jours - 1)),
        fin: fin,
      );
      final List<LienAttribution> codes = await _vitrine.attributions();

      if (!mounted) return;
      setState(() {
        _donnees = donnees;
        _codes = codes;
        _chargement = false;
      });
    } on VitrineException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texte)));
  }

  Future<void> _creerCode() async {
    final String? libelle = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => const _DialogueCodeAttribution(),
    );
    if (libelle == null || !mounted) return;

    try {
      final LienAttribution? code = await _vitrine.creerAttribution(
        libelle: libelle.isEmpty ? null : libelle,
      );
      if (code == null) return;
      _message('Code créé : ${code.code}');
      await Clipboard.setData(ClipboardData(text: code.messageClient));
      await _charger();
    } on VitrineException catch (e) {
      _message(e.message);
    }
  }

  Future<void> _supprimerCode(LienAttribution code) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Supprimer le code ${code.code} ?'),
        content: const Text(
          'Les ventes déjà rattachées à ce code restent dans votre historique. '
          'Seul le code cesse de fonctionner.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirme != true) return;

    try {
      await _vitrine.supprimerAttribution(code.id);
      await _charger();
    } on VitrineException catch (e) {
      _message(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ma visibilité Biashara'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Recharger',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: ModernLoader(taille: 46))
          : (_erreur != null ? _etatErreur(theme) : _contenu(theme)),
    );
  }

  Widget _etatErreur(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.insights_rounded,
                size: 44, color: AppCouleurs.alerte),
            const SizedBox(height: 12),
            Text(
              _erreur ?? 'Statistiques indisponibles.',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
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

  Widget _contenu(ThemeData theme) {
    final VisibiliteBiashara donnees = _donnees ?? const VisibiliteBiashara();

    return RefreshIndicator(
      onRefresh: _charger,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
        children: <Widget>[
          // ---- Période ----
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Text('Période',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
                for (final int jours in <int>[7, 30, 90]) ...<Widget>[
                  ChoiceChip(
                    label: Text('$jours jours'),
                    selected: _jours == jours,
                    onSelected: (_) {
                      setState(() => _jours = jours);
                      _charger();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ---- Les 4 niveaux, clairement séparés ----
          _niveau(
            theme,
            categorie: CategorieEvenement.visibilite,
            valeur: donnees.resume.visibilite,
            icone: Icons.visibility_rounded,
            couleur: AppCouleurs.marine,
          ),
          _niveau(
            theme,
            categorie: CategorieEvenement.interet,
            valeur: donnees.resume.interet,
            icone: Icons.touch_app_rounded,
            couleur: AppCouleurs.info,
            detail: donnees.resume.tauxInteret == null
                ? null
                : '${donnees.resume.tauxInteret} % des affichages',
          ),
          _niveau(
            theme,
            categorie: CategorieEvenement.intention,
            valeur: donnees.resume.intention,
            icone: Icons.directions_rounded,
            couleur: AppCouleurs.orangeFonce,
            detail: donnees.resume.tauxIntention == null
                ? null
                : '${donnees.resume.tauxIntention} % des affichages',
          ),
          _niveau(
            theme,
            categorie: CategorieEvenement.conversion,
            valeur: donnees.resume.conversion,
            icone: Icons.shopping_cart_checkout_rounded,
            couleur: AppCouleurs.succes,
          ),

          if (donnees.noteConversion != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              donnees.noteConversion!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'Évolution journalière',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          if (donnees.parJour.isEmpty)
            Text(
              'Aucune donnée sur cette période.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                child: Column(
                  children: <Widget>[
                    SizedBox(
                      height: 190,
                      child: BarChart(_graphique(theme, donnees.parJour)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        _legende(theme, 'Affichages', AppCouleurs.marine),
                        const SizedBox(width: 14),
                        _legende(theme, 'Intentions', AppCouleurs.orangeFonce),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
          Text(
            'Ce qui vous apporte le plus',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          if (donnees.parType.isEmpty)
            Text(
              'Aucun événement enregistré sur cette période.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final CompteurEvenement compteur in donnees.parType)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Icon(
                      _iconeCategorie(compteur.categorie),
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        compteur.libelle,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      '${compteur.nb}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

          if (donnees.topProduits.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              'Produits les plus consultés',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            for (final ProduitVisible produit in donnees.topProduits)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        produit.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        children: <Widget>[
                          _miniStat(theme, 'Vues', produit.vues),
                          _miniStat(theme, 'Itinéraires', produit.itineraire),
                          _miniStat(theme, 'Appels', produit.telephone),
                          _miniStat(theme, 'WhatsApp', produit.whatsapp),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],

          const SizedBox(height: 20),
          Text(
            'Recherches qui vous ont trouvé',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            '${donnees.nbRecherches} recherche'
            '${donnees.nbRecherches > 1 ? 's' : ''} distincte'
            '${donnees.nbRecherches > 1 ? 's' : ''} ont affiché vos articles. '
            'Biashara ne conserve aucune information sur les personnes qui '
            'effectuent ces recherches.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),

          // ---- Codes d'attribution (conversion honnête) ----
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Codes & attribution des ventes',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton.icon(
                onPressed: _creerCode,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Créer'),
              ),
            ],
          ),
          Text(
            'Un QR code, un lien ou un code promotionnel permet de rattacher '
            'une vente RÉELLE à Biashara. Tant qu\'aucun code n\'est utilisé, '
            'aucune conversion n\'est affichée : nous ne transformons jamais '
            'une consultation en achat supposé.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          if (_codes.isEmpty)
            Text(
              'Aucun code pour le moment.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final LienAttribution code in _codes)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.qr_code_2_rounded,
                      color: AppCouleurs.marine),
                  title: Text(
                    code.code,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                  subtitle: Text(
                    '${code.type.libelle}'
                    '${code.libelle == null ? '' : ' · ${code.libelle}'}'
                    ' · ${code.utilisations} utilisation'
                    '${code.utilisations > 1 ? 's' : ''}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Supprimer',
                    onPressed: () => _supprimerCode(code),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                  onTap: () async {
                    await Clipboard.setData(
                      ClipboardData(text: code.messageClient),
                    );
                    _message('Instructions copiées.');
                  },
                ),
              ),

          if (donnees.publicites.isNotEmpty) ...<Widget>[
            const SizedBox(height: 20),
            Text(
              'Campagnes publicitaires',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            for (final Map<String, dynamic> pub in donnees.publicites)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.campaign_rounded,
                      color: AppCouleurs.orange),
                  title: Text(
                    (pub['titre'] ?? 'Campagne').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${(pub['statut'] ?? '').toString()} · '
                    '${pub['impressions'] ?? 0} affichage(s) · '
                    '${pub['clics'] ?? 0} clic(s)',
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _niveau(
    ThemeData theme, {
    required CategorieEvenement categorie,
    required int valeur,
    required IconData icone,
    required Color couleur,
    String? detail,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: couleur.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icone, color: couleur),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Text(
                        categorie.libelle.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: couleur,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          categorie.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$valeur',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: couleur,
                    ),
                  ),
                  if (detail != null)
                    Text(
                      detail,
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

  Widget _miniStat(ThemeData theme, String libelle, int valeur) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$valeur',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text(
          libelle,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _legende(ThemeData theme, String libelle, Color couleur) {
    return Row(
      children: <Widget>[
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: couleur,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(libelle, style: theme.textTheme.labelSmall),
      ],
    );
  }

  IconData _iconeCategorie(CategorieEvenement categorie) {
    switch (categorie) {
      case CategorieEvenement.visibilite:
        return Icons.visibility_rounded;
      case CategorieEvenement.interet:
        return Icons.touch_app_rounded;
      case CategorieEvenement.intention:
        return Icons.directions_rounded;
      case CategorieEvenement.conversion:
        return Icons.shopping_cart_checkout_rounded;
      case CategorieEvenement.autre:
        return Icons.insights_rounded;
    }
  }

  /// Graphique : affichages (marine) et intentions (orange) par journée.
  ///
  /// Deux barres par jour plutôt qu'une courbe : la comparaison
  /// affichages → intentions est immédiatement lisible par un commerçant.
  BarChartData _graphique(ThemeData theme, List<JourVisibilite> jours) {
    final List<JourVisibilite> serie = jours.length > 30
        ? jours.sublist(jours.length - 30)
        : jours;

    double maxValeur = 1;
    for (final JourVisibilite jour in serie) {
      if (jour.visibilite > maxValeur) maxValeur = jour.visibilite.toDouble();
      if (jour.intention > maxValeur) maxValeur = jour.intention.toDouble();
    }

    return BarChartData(
      alignment: BarChartAlignment.spaceAround,
      minY: 0,
      maxY: maxValeur * 1.2,
      borderData: FlBorderData(show: false),
      gridData: FlGridData(show: true, drawVerticalLine: false),
      titlesData: FlTitlesData(
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            interval: (serie.length / 4).ceilToDouble().clamp(1, 999),
            getTitlesWidget: (double value, TitleMeta meta) {
              final int index = value.toInt();
              if (index < 0 || index >= serie.length) {
                return const SizedBox.shrink();
              }
              final DateTime jour = serie[index].jour;
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${jour.day}/${jour.month}',
                  style: const TextStyle(fontSize: 9),
                ),
              );
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(enabled: false),
      barGroups: <BarChartGroupData>[
        for (int i = 0; i < serie.length; i++)
          BarChartGroupData(
            x: i,
            barsSpace: 2,
            barRods: <BarChartRodData>[
              BarChartRodData(
                toY: serie[i].visibilite.toDouble(),
                width: serie.length > 20 ? 3 : 7,
                borderRadius: BorderRadius.circular(2),
                color: AppCouleurs.marine,
              ),
              BarChartRodData(
                toY: serie[i].intention.toDouble(),
                width: serie.length > 20 ? 3 : 7,
                borderRadius: BorderRadius.circular(2),
                color: AppCouleurs.orangeFonce,
              ),
            ],
          ),
      ],
    );
  }
}

/// Boîte de dialogue de création d'un code d'attribution.
class _DialogueCodeAttribution extends StatefulWidget {
  const _DialogueCodeAttribution();

  @override
  State<_DialogueCodeAttribution> createState() =>
      _DialogueCodeAttributionState();
}

class _DialogueCodeAttributionState extends State<_DialogueCodeAttribution> {
  final TextEditingController _libelle = TextEditingController();

  @override
  void dispose() {
    _libelle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Créer un code d\'attribution'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Affichez ce code (ou son QR) sur votre vitrine ou vos tickets. '
            'Quand un client l\'utilise, la vente peut être rattachée à '
            'Biashara.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _libelle,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Libellé (facultatif)',
              hintText: 'ex. QR vitrine Katuba',
              prefixIcon: Icon(Icons.label_outline_rounded),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_libelle.text.trim()),
          child: const Text('Créer'),
        ),
      ],
    );
  }
}
