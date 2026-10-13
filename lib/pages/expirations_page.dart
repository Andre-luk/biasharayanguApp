// lib/pages/expirations_page.dart
//
// 🧩 MODULE 16 (phase C1) — PHARMACIE : ÉCRAN « EXPIRATIONS ».
//
// Liste les articles ayant une date de péremption, triés par urgence :
// expirés d'abord, puis les proches (≤ 30 j), puis le reste de l'horizon.
// Filtres rapides (Tous / Expirés / ≤ 30 j), résumé en tête, accès direct à
// la fiche de l'article pour corriger le lot ou la date.
//
// Cet écran n'est accessible que si l'activité a le module
// `lots_expiration` (carte d'accueil / raccourci de la liste des articles).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/statut_expiration.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/peremption_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Filtres rapides de l'écran.
enum _FiltreExpiration {
  tous('Tous'),
  expires('Expirés'),
  proches('≤ 30 j'),
  nonExpires('Valides');

  const _FiltreExpiration(this.libelle);

  final String libelle;
}

class ExpirationsPage extends StatefulWidget {
  const ExpirationsPage({super.key});

  @override
  State<ExpirationsPage> createState() => _ExpirationsPageState();
}

class _ExpirationsPageState extends State<ExpirationsPage> {
  final ArticleService _service = ArticleService.instance;

  List<Article> _articles = const <Article>[];
  _FiltreExpiration _filtre = _FiltreExpiration.tous;

  /// 🧮 CORRECTIF 72 — délai d'alerte RÉGLÉ PAR LA BOUTIQUE. Les filtres et
  /// les comptages suivent ce délai, comme la liste des articles et la
  /// notification : un même produit doit être « proche » partout, ou nulle
  /// part.
  int _delaiPeremption = PeremptionService.delaiParDefaut;

  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _chargerDelai();
    _charger();
  }

  Future<void> _chargerDelai() async {
    final int delai = await PeremptionService.instance.charger();
    if (!mounted || delai == _delaiPeremption) return;
    setState(() => _delaiPeremption = delai);
  }

  Future<void> _charger({bool silencieux = false}) async {
    if (!mounted) return;

    if (!silencieux) {
      setState(() {
        _chargement = true;
        _erreur = null;
      });
    }

    String? messageErreur;
    List<Article> articles = const <Article>[];

    try {
      articles = await _service.listerExpirations();
    } on ArticleServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('ExpirationsPage._charger: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement des expirations.';
    }

    if (!mounted) return;

    if (messageErreur != null) {
      if (silencieux) {
        _afficherMessage(messageErreur, estErreur: true);
        return;
      }
      setState(() {
        _erreur = messageErreur;
        _chargement = false;
      });
      return;
    }

    setState(() {
      _articles = articles;
      _erreur = null;
      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // FILTRES & COMPTAGES
  // ---------------------------------------------------------------------------

  int _compter(StatutExpiration statut) => _articles
      .where((Article a) => a.statutExpirationSelon(_delaiPeremption) == statut)
      .length;

  List<Article> get _articlesFiltres {
    switch (_filtre) {
      case _FiltreExpiration.tous:
        return _articles;
      case _FiltreExpiration.expires:
        return _articles
            .where((Article a) =>
                a.statutExpirationSelon(_delaiPeremption) ==
                StatutExpiration.expire)
            .toList(growable: false);
      case _FiltreExpiration.proches:
        return _articles
            .where((Article a) =>
                a.statutExpirationSelon(_delaiPeremption) ==
                StatutExpiration.proche)
            .toList(growable: false);
      case _FiltreExpiration.nonExpires:
        return _articles
            .where((Article a) =>
                a.statutExpirationSelon(_delaiPeremption) ==
                StatutExpiration.valide)
            .toList(growable: false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  void _afficherMessage(String message, {bool estErreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            estErreur ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Color _couleurStatut(StatutExpiration statut) {
    switch (statut) {
      case StatutExpiration.expire:
        return Colors.red.shade700;
      case StatutExpiration.proche:
        return Colors.orange.shade800;
      case StatutExpiration.valide:
        return Colors.green.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Expirations',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Guide d\'utilisation',
            onPressed: () => context.pushNamed('guide-utilisation'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: _construireCorps(theme),
    );
  }

  Widget _construireCorps(ThemeData theme) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _charger(),
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final List<Article> filtres = _articlesFiltres;

    return RefreshIndicator(
      onRefresh: () => _charger(),
      color: theme.colorScheme.primary,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _resume(theme),
          const SizedBox(height: 12),
          _filtres(theme),
          const SizedBox(height: 8),
          if (filtres.isEmpty)
            _vide(theme)
          else
            for (final Article article in filtres) _ligneArticle(theme, article),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _resume(ThemeData theme) {
    final int expires = _compter(StatutExpiration.expire);
    final int proches = _compter(StatutExpiration.proche);

    if (_articles.isEmpty) {
      return Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: theme.colorScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Aucun article suivi : renseignez une date de péremption sur les '
            'articles pour activer les alertes.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: _compteur(
            theme,
            libelle: 'Expirés',
            valeur: '$expires',
            couleur: Colors.red.shade700,
            icone: Icons.error_outline,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compteur(
            theme,
            libelle: '≤ 30 jours',
            valeur: '$proches',
            couleur: Colors.orange.shade800,
            icone: Icons.warning_amber_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _compteur(
            theme,
            libelle: 'Suivis',
            valeur: '${_articles.length}',
            couleur: theme.colorScheme.primary,
            icone: Icons.science_outlined,
          ),
        ),
      ],
    );
  }

  Widget _compteur(
    ThemeData theme, {
    required String libelle,
    required String valeur,
    required Color couleur,
    required IconData icone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 18, color: couleur),
          const SizedBox(height: 6),
          Text(
            valeur,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: couleur,
            ),
          ),
          Text(
            libelle,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtres(ThemeData theme) {
    return Wrap(
      spacing: 8,
      children: [
        for (final _FiltreExpiration filtre in _FiltreExpiration.values)
          ChoiceChip(
            label: Text(filtre.libelle),
            selected: _filtre == filtre,
            onSelected: (_) => setState(() => _filtre = filtre),
          ),
      ],
    );
  }

  Widget _vide(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 48, color: Colors.green.shade700),
          const SizedBox(height: 10),
          Text(
            'Aucun article dans ce filtre.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _ligneArticle(ThemeData theme, Article article) {
    final StatutExpiration statut =
        article.statutExpiration ?? StatutExpiration.valide;
    final int? jours = StatutExpiration.joursRestants(article.dateExpiration);
    final Color couleur = _couleurStatut(statut);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        onTap: () =>
            context.push<void>('/main/articles/${article.id}', extra: article),
        leading: CircleAvatar(
          backgroundColor: couleur.withValues(alpha: 0.12),
          child: Icon(Icons.medication_outlined, color: couleur, size: 20),
        ),
        title: Text(
          article.nom,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${article.dateExpiration == null ? '' : _dateFr(article.dateExpiration!)}'
          ' • ${StatutExpiration.libelleJours(jours)}'
          '${article.lotNumero == null || article.lotNumero!.isEmpty ? '' : ' • Lot ${article.lotNumero}'}'
          ' • ${formatQuantite(article.quantite)} en stock',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: couleur),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            statut.libelle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: couleur,
            ),
          ),
        ),
      ),
    );
  }

  static String _dateFr(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
