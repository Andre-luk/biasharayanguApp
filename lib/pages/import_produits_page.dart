// lib/pages/import_produits_page.dart
//
// MODULE 12 — ÉCRAN « IMPORTER DES ARTICLES » (IMPORT RAPIDE).
//
// Parcours en trois étapes, pensé pour le téléphone :
//   1. SOURCE — coller le contenu d'un fichier CSV/TSV (copié d'Excel, de
//      WhatsApp, d'un fournisseur…) ou choisir un fichier sur l'appareil ;
//   2. VÉRIFICATION — résumé (prêts / refusés), aperçu des premières lignes,
//      erreurs ligne à ligne, option « mettre à jour les fiches existantes » ;
//   3. RÉSULTAT — créés / mis à jour / ignorés / erreurs, puis retour à la
//      liste des articles.
//
// ⚠️ Règles serveur : l'import est réservé à `articles/creer`, limité à
// 500 lignes par appel (découpage automatique), les doublons par nom sont
// ignorés (ou leur FICHE mise à jour — jamais la quantité : le stock ne bouge
// que par les mouvements tracés du Module 9) et TOUT est journalisé en une
// entrée `IMPORT_PRODUITS`.

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/import_produits.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/import_produits_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/import_csv.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Écran d'import rapide d'articles.
class ImportProduitsPage extends StatefulWidget {
  const ImportProduitsPage({super.key});

  @override
  State<ImportProduitsPage> createState() => _ImportProduitsPageState();
}

class _ImportProduitsPageState extends State<ImportProduitsPage> {
  final ImportProduitsService _service = ImportProduitsService.instance;
  final TextEditingController _contenuController = TextEditingController();

  AnalyseImport? _analyse;
  ResultatImport? _resultat;

  bool _analyseEnCours = false;
  bool _importEnCours = false;
  bool _mettreAJour = false;
  String? _nomFichier;

  static const Map<String, String> _libellesColonnes = <String, String>{
    'nom': 'Nom',
    'categorie': 'Catégorie',
    'prix_achat': 'Prix d\'achat',
    'prix_vente': 'Prix de vente',
    'quantite': 'Quantité',
    'unite_mesure': 'Unité',
    'description': 'Description',
  };

  @override
  void dispose() {
    _contenuController.dispose();
    super.dispose();
  }

  bool get _acces =>
      PermissionService.instance.peut(PageAccess.articles, ActionAccess.creer);

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _choisirFichier() async {
    if (_analyseEnCours) return;
    setState(() => _analyseEnCours = true);

    try {
      const XTypeGroup groupe = XTypeGroup(
        label: 'Fichiers CSV / texte',
        extensions: <String>['csv', 'txt', 'tsv'],
        mimeTypes: <String>[
          'text/csv',
          'text/comma-separated-values',
          'text/plain',
          'text/tab-separated-values',
        ],
      );

      final XFile? fichier =
          await openFile(acceptedTypeGroups: <XTypeGroup>[groupe]);
      if (fichier == null) return;

      final Uint8List octets = await fichier.readAsBytes();
      final String contenu =
          ImportCsv.retirerBom(utf8.decode(octets, allowMalformed: true));

      if (!mounted) return;
      setState(() {
        _nomFichier = fichier.name;
        _contenuController.text = contenu;
        _analyse = _service.analyserContenu(contenu);
        _resultat = null;
      });
    } catch (e) {
      debugPrint('ImportProduitsPage._choisirFichier : $e');
      if (!mounted) return;
      _message(
        'Sélection de fichier indisponible sur cet appareil : collez le '
        'contenu du fichier dans la zone ci-dessous.',
        erreur: true,
      );
    } finally {
      if (mounted) setState(() => _analyseEnCours = false);
    }
  }

  void _insererModele() {
    _contenuController.text = ImportCsv.modele;
    setState(() {
      _nomFichier = null;
      _analyse = null;
      _resultat = null;
    });
  }

  void _analyser() {
    final String texte = _contenuController.text;
    if (texte.trim().isEmpty) {
      _message('Collez d\'abord le contenu d\'un fichier (ou insérez le modèle).',
          erreur: true);
      return;
    }

    setState(() {
      _analyse = _service.analyserContenu(texte);
      _resultat = null;
    });
  }

  Future<void> _importer() async {
    final AnalyseImport? analyse = _analyse;
    if (analyse == null || analyse.lignes.isEmpty) return;

    setState(() => _importEnCours = true);
    try {
      final ResultatImport resultat = await _service.importer(
        analyse.lignes,
        mettreAJour: _mettreAJour,
      );

      if (!mounted) return;
      setState(() => _resultat = resultat);
      _message(
        'Import terminé : ${resultat.crees} créé(s), '
        '${resultat.misAJour} mis à jour, ${resultat.ignores} ignoré(s).',
      );
    } on ImportProduitsException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    } catch (e) {
      debugPrint('ImportProduitsPage._importer : $e');
      if (!mounted) return;
      _message('Import impossible : vérifiez votre réseau puis réessayez.',
          erreur: true);
    } finally {
      if (mounted) setState(() => _importEnCours = false);
    }
  }

  void _nouvelImport() {
    setState(() {
      _contenuController.clear();
      _nomFichier = null;
      _analyse = null;
      _resultat = null;
    });
  }

  void _message(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_acces) {
      return Scaffold(
        appBar: AppBar(title: const Text('Importer des articles')),
        body: const AccesRefuse(
          message: 'Votre rôle ne permet pas de créer des articles.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Importer des articles',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          if (_contenuController.text.trim().isNotEmpty)
            IconButton(
              tooltip: 'Nouvel import',
              onPressed: _nouvelImport,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: <Widget>[
          _carteSource(),
          const SizedBox(height: 14),
          if (_analyse != null) ...<Widget>[
            _carteVerification(),
            const SizedBox(height: 14),
          ],
          if (_resultat != null) _carteResultat(),
        ],
      ),
    );
  }

  Widget _carteEtape(String titre, IconData icone, Widget enfant) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icone, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          enfant,
        ],
      ),
    );
  }

  // =========================================================================
  // ÉTAPE 1 — SOURCE
  // =========================================================================

  Widget _carteSource() {
    return _carteEtape(
      '1 · Source des données',
      Icons.upload_file_rounded,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Collez le contenu d\'un fichier CSV (export Excel, liste d\'un '
            'fournisseur…) ou choisissez un fichier sur l\'appareil.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _analyseEnCours ? null : _choisirFichier,
                  icon: _analyseEnCours
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open_rounded),
                  label: const Text('Choisir un fichier…'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _insererModele,
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('Insérer un modèle'),
                ),
              ),
            ],
          ),
          if (_nomFichier != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Icon(Icons.insert_drive_file_outlined,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _nomFichier!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _contenuController,
            minLines: 6,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
            decoration: InputDecoration(
              hintText: ImportCsv.modele,
              hintStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.55),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            'Séparateurs acceptés : ; , tabulation. Colonnes : '
            '${_libellesColonnes.values.join(', ')}. '
            'Seul « nom » est obligatoire.',
            style: TextStyle(
              fontSize: 11.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _analyser,
              icon: const Icon(Icons.checklist_rounded),
              label: const Text('Analyser le contenu'),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ÉTAPE 2 — VÉRIFICATION
  // =========================================================================

  Widget _carteVerification() {
    final AnalyseImport analyse = _analyse!;
    final ThemeData theme = Theme.of(context);

    if (analyse.erreurGlobale != null) {
      return _carteEtape(
        '2 · Vérification',
        Icons.rule_rounded,
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(Icons.error_outline_rounded,
                  color: theme.colorScheme.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  analyse.erreurGlobale!,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _carteEtape(
      '2 · Vérification',
      Icons.rule_rounded,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _puce(
                '${analyse.nbValides} article(s) prêt(s)',
                Colors.green.shade700,
                Icons.check_circle_rounded,
              ),
              if (analyse.nbErreurs > 0)
                _puce(
                  '${analyse.nbErreurs} ligne(s) refusée(s)',
                  Colors.red.shade700,
                  Icons.cancel_rounded,
                ),
              _puce(
                '${analyse.totalLignes} ligne(s) lue(s)',
                Colors.blueGrey.shade600,
                Icons.format_list_bulleted_rounded,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Colonnes reconnues : ${analyse.colonnesUtilisees.map((String c) => _libellesColonnes[c] ?? c).join(', ')}',
            style: const TextStyle(fontSize: 12),
          ),
          if (analyse.colonnesInconnues.isNotEmpty)
            Text(
              'Colonnes ignorées : ${analyse.colonnesInconnues.join(', ')}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          if (analyse.lignes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'Aperçu',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            for (final LigneImport ligne in analyse.lignes.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        ligne.nom,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${formatMontant(ligne.prixVente)} · ${_quantite(ligne.quantite)} ${ligne.uniteMesure ?? ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            if (analyse.lignes.length > 6)
              Text(
                '… et ${analyse.lignes.length - 6} autre(s).',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
          ],
          if (analyse.erreurs.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const Text(
              'Lignes refusées',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            const SizedBox(height: 4),
            for (final ErreurImport erreur in analyse.erreurs.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• Ligne ${erreur.ligne}'
                  '${erreur.nom == null ? '' : ' (${erreur.nom})'} : ${erreur.message}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                  ),
                ),
              ),
            if (analyse.erreurs.length > 12)
              Text(
                '… et ${analyse.erreurs.length - 12} autre(s) erreur(s).',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
          ],
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _mettreAJour,
            onChanged: (bool valeur) => setState(() => _mettreAJour = valeur),
            title: const Text(
              'Mettre à jour les articles existants (même nom)',
              style: TextStyle(fontSize: 13.5),
            ),
            subtitle: const Text(
              'La fiche (prix, catégorie, unité) est mise à jour — jamais la '
              'quantité : le stock ne bouge que par les mouvements tracés.',
              style: TextStyle(fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_importEnCours || analyse.lignes.isEmpty)
                  ? null
                  : _importer,
              icon: _importEnCours
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt_rounded),
              label: Text(
                _importEnCours
                    ? 'Import en cours…'
                    : 'Importer ${analyse.lignes.length} article(s)',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _puce(String texte, Color couleur, IconData icone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: couleur.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icone, size: 14, color: couleur),
          const SizedBox(width: 5),
          Text(
            texte,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: couleur,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ÉTAPE 3 — RÉSULTAT
  // =========================================================================

  Widget _carteResultat() {
    final ResultatImport resultat = _resultat!;
    final ThemeData theme = Theme.of(context);

    return _carteEtape(
      '3 · Résultat',
      Icons.task_alt_rounded,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _puce('${resultat.crees} créé(s)', Colors.green.shade700,
                  Icons.add_circle_rounded),
              if (resultat.misAJour > 0)
                _puce('${resultat.misAJour} mis à jour', Colors.blue.shade700,
                    Icons.update_rounded),
              if (resultat.ignores > 0)
                _puce('${resultat.ignores} ignoré(s)',
                    Colors.blueGrey.shade600, Icons.remove_circle_outline_rounded),
              if (resultat.aDesErreurs)
                _puce('${resultat.erreurs.length} erreur(s)',
                    Colors.red.shade700, Icons.cancel_rounded),
            ],
          ),
          const SizedBox(height: 10),
          if (resultat.aDesErreurs) ...<Widget>[
            for (final ErreurImport erreur in resultat.erreurs.take(12))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '• Ligne ${erreur.ligne}'
                  '${erreur.nom == null ? '' : ' (${erreur.nom})'} : ${erreur.message}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ),
            if (resultat.erreurs.length > 12)
              Text(
                '… et ${resultat.erreurs.length - 12} autre(s) erreur(s).',
                style: const TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            const SizedBox(height: 10),
          ],
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: <Widget>[
                Icon(Icons.history_edu_rounded, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Import journalisé (IMPORT_PRODUITS, niveau HAUT) : '
                    'auteur, lignes lues et erreurs sont conservés dans le '
                    'journal d\'audit.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _nouvelImport,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Nouvel import'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.inventory_2_rounded),
                  label: const Text('Voir les articles'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _quantite(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  }
}
