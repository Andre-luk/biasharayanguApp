// lib/pages/factures_abonnement_page.dart
//
// 🧾 CORRECTIF 67 — ÉCRAN DES FACTURES D'ABONNEMENT.
//
// Un seul écran pour les deux espaces :
//   • la PLATEFORME (Finance / Super Admin) voit toutes les factures, peut en
//     éditer une à la main, en envoyer une, ou annuler une facture non
//     encaissée ;
//   • un CLIENT ne voit que les siennes (la RPC décide, pas l'écran) et peut
//     les consulter ou les redemander ;
//   • un AGENT DE TERRAIN voit celles des comptes qu'il suit — c'est lui qui
//     encaisse dans la rue, il doit pouvoir remontrer la facture.
//
// ⚠️ L'écran n'est JAMAIS l'autorité : chaque bouton masqué l'est aussi parce
// que le serveur refuserait l'opération (rôles revérifiés dans les RPC).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/facture_abonnement.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/entreprise_service.dart';
import 'package:biashara_yangu/services/facture_abonnement_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/ui/widgets/modern_loader.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Filtres proposés au-dessus de la liste.
enum _FiltreFactures {
  toutes('Toutes'),
  aEnvoyer('À envoyer'),
  impayees('Reste à payer'),
  annulees('Annulées');

  const _FiltreFactures(this.libelle);

  final String libelle;
}

class FacturesAbonnementPage extends StatefulWidget {
  const FacturesAbonnementPage({
    super.key,
    this.entrepriseId,
    this.nomEtablissement,
    this.showAppBar = true,
  });

  /// Filtre sur une boutique précise (la plateforme en gère plusieurs).
  final String? entrepriseId;

  /// Nom affiché en en-tête et dans le message WhatsApp.
  final String? nomEtablissement;

  final bool showAppBar;

  @override
  State<FacturesAbonnementPage> createState() => _FacturesAbonnementPageState();
}

class _FacturesAbonnementPageState extends State<FacturesAbonnementPage> {
  final FactureAbonnementService _service = FactureAbonnementService.instance;
  final TextEditingController _recherche = TextEditingController();

  List<FactureAbonnement> _factures = const <FactureAbonnement>[];
  int _aEnvoyer = 0;
  bool _chargement = true;
  bool _actionEnCours = false;
  String? _erreur;
  _FiltreFactures _filtre = _FiltreFactures.toutes;

  // ── Qui a le droit de faire quoi.
  bool get _estFinanceOuSuper =>
      PermissionService.instance.roleCourant == RoleUtilisateur.financeLaperle ||
      PermissionService.instance.roleCourant == RoleUtilisateur.superAdmin;

  bool get _peutEnvoyer =>
      PermissionService.instance.peutModifier(PageAccess.facturesAbonnement) ||
      _estFinanceOuSuper;

  bool get _peutGenerer => _estFinanceOuSuper;

  bool get _peutAnnuler => _estFinanceOuSuper;

  bool get _peutReparer =>
      PermissionService.instance.roleCourant == RoleUtilisateur.superAdmin;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  @override
  void dispose() {
    _recherche.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _charger({bool silencieux = false}) async {
    if (!silencieux) setState(() => _chargement = true);

    try {
      final List<FactureAbonnement> factures = await _service.lister(
        entrepriseId: widget.entrepriseId,
        limite: 300,
        inclureAnnulees: true,
      );
      final FacturesAEnvoyer restantes = await _service.aEnvoyer(
        entrepriseId: widget.entrepriseId,
      );

      if (!mounted) return;
      setState(() {
        _factures = factures;
        _aEnvoyer = restantes.total;
        _chargement = false;
        _erreur = null;
      });
    } on FactureAbonnementException catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = e.message;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  void _avertir(String message, {bool erreur = false, SnackBarAction? action}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        action: action,
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  Future<void> _envoyer(FactureAbonnement facture) async {
    if (!_peutEnvoyer) {
      _avertir(
        'Vous n\'êtes pas habilité à envoyer cette facture.',
        erreur: true,
      );
      return;
    }

    setState(() => _actionEnCours = true);
    try {
      await _service.envoyerParWhatsApp(
        facture,
        nomEtablissement: widget.nomEtablissement,
      );

      if (!mounted) return;
      _avertir(
        'Facture ${facture.numero} transmise à WhatsApp.',
        action: SnackBarAction(
          label: 'Joindre le PDF',
          onPressed: () => _partagerPDF(facture),
        ),
      );
      await _charger(silencieux: true);
    } on FactureAbonnementException catch (e) {
      _avertir(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _partagerPDF(FactureAbonnement facture) async {
    setState(() => _actionEnCours = true);
    try {
      await _service.partagerPDF(
        facture,
        nomEtablissement: widget.nomEtablissement ?? 'Biashara Yangu',
      );
    } catch (e) {
      _avertir('Impossible de partager la facture : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _telechargerPDF(FactureAbonnement facture) async {
    setState(() => _actionEnCours = true);
    try {
      final String? chemin = await _service.exporterPDF(
        facture,
        nomEtablissement: widget.nomEtablissement ?? 'Biashara Yangu',
      );
      _avertir(
        chemin == null
            ? 'Facture ${facture.numero} enregistrée dans les téléchargements.'
            : 'Facture enregistrée : $chemin',
      );
    } catch (e) {
      _avertir('Impossible d\'enregistrer la facture : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _imprimerPDF(FactureAbonnement facture) async {
    setState(() => _actionEnCours = true);
    try {
      await _service.imprimerPDF(
        facture,
        nomEtablissement: widget.nomEtablissement ?? 'Biashara Yangu',
      );
    } catch (e) {
      _avertir('Impression impossible : $e', erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _annuler(FactureAbonnement facture) async {
    final TextEditingController motif = TextEditingController();

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Annuler cette facture ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${facture.numero} — ${facture.nomAffiche}'),
            const SizedBox(height: 8),
            const Text(
              'La facture n\'est jamais supprimée : elle est marquée annulée '
              'et garde le motif. Une facture qui atteste un versement déjà '
              'encaissé ne peut pas être annulée.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motif,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Motif de l\'annulation (obligatoire)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Renoncer'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Annuler la facture'),
          ),
        ],
      ),
    );

    if (confirme != true) {
      motif.dispose();
      return;
    }

    setState(() => _actionEnCours = true);
    try {
      await _service.annuler(facture.id, motif.text.trim());
      _avertir('Facture ${facture.numero} annulée.');
      await _charger(silencieux: true);
    } on FactureAbonnementException catch (e) {
      _avertir(e.message, erreur: true);
    } finally {
      motif.dispose();
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _genererMain() async {
    if (widget.entrepriseId == null) {
      _avertir(
        'Ouvrez une boutique pour éditer une facture à la main.',
        erreur: true,
      );
      return;
    }

    setState(() => _actionEnCours = true);
    try {
      final FactureAbonnement? facture = await _service.generer(
        widget.entrepriseId!,
        note: 'État de compte établi à la main.',
      );
      _avertir(facture == null
          ? 'Aucune facture n\'a pu être établie.'
          : 'Facture ${facture.numero} établie.');
      await _charger(silencieux: true);
    } on FactureAbonnementException catch (e) {
      _avertir(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Future<void> _reparer() async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Réparer l\'historique ?'),
        content: const Text(
          'Les encaissements enregistrés avant cette version n\'ont pas de '
          'facture. Cette opération les reconstruit. Elle n\'efface rien et '
          'peut être relancée sans risque.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Renoncer'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Réparer'),
          ),
        ],
      ),
    );

    if (confirme != true) return;

    setState(() => _actionEnCours = true);
    try {
      final ResultatRattrapageFactures resultat = await _service.rattraper(
        entrepriseId: widget.entrepriseId,
      );
      _avertir(
        'Historique réparé : ${resultat.creees} facture(s) reconstruite(s), '
        '${resultat.ignorees} déjà présente(s).',
      );
      await _charger(silencieux: true);
    } on FactureAbonnementException catch (e) {
      _avertir(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  // ---------------------------------------------------------------------------
  // AFFICHAGE
  // ---------------------------------------------------------------------------

  List<FactureAbonnement> get _listeFiltree {
    final String requete = _recherche.text.trim().toLowerCase();

    return _factures.where((FactureAbonnement f) {
      switch (_filtre) {
        case _FiltreFactures.aEnvoyer:
          if (!f.aEnvoyer) return false;
          break;
        case _FiltreFactures.impayees:
          if (f.estSoldee || f.estAnnulee) return false;
          break;
        case _FiltreFactures.annulees:
          if (!f.estAnnulee) return false;
          break;
        case _FiltreFactures.toutes:
          if (f.estAnnulee) return false;
          break;
      }

      if (requete.isEmpty) return true;

      return f.numero.toLowerCase().contains(requete) ||
          f.clientNom.toLowerCase().contains(requete) ||
          (f.clientTelephone ?? '').toLowerCase().contains(requete);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Widget corps = _chargement
        ? const Center(child: ModernLoader())
        : _erreur != null
            ? _vueErreur(theme)
            : Column(
                children: <Widget>[
                  _barreOutils(theme),
                  if (_actionEnCours) const BarreProgressionModerne(),
                  Expanded(child: _liste(theme)),
                ],
              );

    if (!widget.showAppBar) return corps;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Factures d\'abonnement'),
        actions: <Widget>[
          if (_peutReparer)
            IconButton(
              tooltip: 'Réparer l\'historique',
              onPressed: _actionEnCours ? null : _reparer,
              icon: const Icon(Icons.build_circle_outlined),
            ),
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _actionEnCours
                ? null
                : () => _charger(silencieux: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _peutGenerer && widget.entrepriseId != null
          ? FloatingActionButton.extended(
              onPressed: _actionEnCours ? null : _genererMain,
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('État de compte'),
            )
          : null,
      body: corps,
    );
  }

  Widget _vueErreur(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded,
                size: 48, color: AppCouleurs.alerte),
            const SizedBox(height: 12),
            Text(
              _erreur!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
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

  Widget _barreOutils(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_aEnvoyer > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppCouleurs.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppCouleurs.orange, width: 0.8),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.mark_email_unread_rounded,
                      color: AppCouleurs.orangeFonce, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$_aEnvoyer facture(s) émise(s) mais pas encore envoyée(s) '
                      'au client.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          TextField(
            controller: _recherche,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'Rechercher un numéro, un client, un téléphone',
              prefixIcon: Icon(Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                for (final _FiltreFactures filtre in _FiltreFactures.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(filtre.libelle),
                      selected: _filtre == filtre,
                      onSelected: (_) => setState(() => _filtre = filtre),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liste(ThemeData theme) {
    final List<FactureAbonnement> factures = _listeFiltree;

    if (factures.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.description_outlined,
                  size: 48, color: AppCouleurs.marineClair),
              const SizedBox(height: 12),
              Text(
                _factures.isEmpty
                    ? 'Aucune facture pour le moment.\nElles sont créées '
                        'automatiquement à chaque encaissement d\'abonnement.'
                    : 'Aucune facture ne correspond à ce filtre.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(silencieux: true),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        itemCount: factures.length,
        itemBuilder: (BuildContext _, int index) =>
            _carteFacture(theme, factures[index]),
      ),
    );
  }

  Widget _carteFacture(ThemeData theme, FactureAbonnement facture) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    facture.numero,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                _puceType(facture),
                const SizedBox(width: 6),
                _puceStatut(facture),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${facture.nomAffiche} • ${formatDate(facture.genereLe)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            _ligneMontant('Installation (1er mois inclus)',
                facture.installationAffichee),
            _ligneMontant('Abonnement mensuel', facture.mensuelAffiche),
            const Divider(height: 16),
            _ligneMontant('Montant dû', facture.totalAffiche),
            _ligneMontant('Avance déjà versée', facture.avanceAffichee),
            _ligneMontant('Versement reçu', facture.regleAffiche),
            _ligneMontant('Total payé', facture.payeAffiche, gras: true),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: (facture.estSoldee ? AppCouleurs.succes : AppCouleurs.alerte)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    facture.estSoldee ? 'Cycle réglé' : 'Reste à payer',
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    facture.soldeAffiche,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: facture.estSoldee
                          ? AppCouleurs.succes
                          : AppCouleurs.orangeFonce,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Générée par ${facture.resumeEmetteur}',
              style: theme.textTheme.bodySmall,
            ),
            Text(facture.resumeEnvoi, style: theme.textTheme.bodySmall),
            if (!facture.additionJuste)
              // Garde-fou visible : si l'addition ne tombe pas juste, on ne
              // présente pas le document comme une preuve.
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '⚠️ Addition incohérente : ne pas remettre ce document au '
                  'client avant vérification.',
                  style: TextStyle(fontSize: 11.5, color: AppCouleurs.danger),
                ),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: <Widget>[
                if (facture.aEnvoyer)
                  TextButton.icon(
                    onPressed: _actionEnCours || !_peutEnvoyer
                        ? null
                        : () => _envoyer(facture),
                    icon: const Icon(Icons.send_rounded, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                TextButton.icon(
                  onPressed:
                      _actionEnCours ? null : () => _partagerPDF(facture),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Partager'),
                ),
                TextButton.icon(
                  onPressed:
                      _actionEnCours ? null : () => _telechargerPDF(facture),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('PDF'),
                ),
                TextButton.icon(
                  onPressed:
                      _actionEnCours ? null : () => _imprimerPDF(facture),
                  icon: const Icon(Icons.print_rounded, size: 18),
                  label: const Text('Imprimer'),
                ),
                if (_peutAnnuler && !facture.estAnnulee)
                  TextButton.icon(
                    onPressed:
                        _actionEnCours ? null : () => _annuler(facture),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('Annuler'),
                    style: TextButton.styleFrom(
                        foregroundColor: AppCouleurs.danger),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ligneMontant(String libelle, String valeur, {bool gras = false}) {
    final TextStyle style = TextStyle(
      fontSize: 12.5,
      fontWeight: gras ? FontWeight.bold : FontWeight.normal,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Flexible(child: Text(libelle, style: style)),
          Text(valeur, style: style),
        ],
      ),
    );
  }

  Widget _puceType(FactureAbonnement facture) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppCouleurs.marine.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        facture.libelleType,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppCouleurs.marine,
        ),
      ),
    );
  }

  Widget _puceStatut(FactureAbonnement facture) {
    final Color couleur = switch (facture.statut) {
      StatutFactureAbonnement.emise => AppCouleurs.alerte,
      StatutFactureAbonnement.envoyee => AppCouleurs.info,
      StatutFactureAbonnement.annulee => AppCouleurs.danger,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        facture.statut.libelle,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: couleur,
        ),
      ),
    );
  }
}

/// Point d'entrée « gestion » : la plateforme choisit d'abord la boutique.
///
/// Sans ce choix, une liste fusionnée de tous les clients serait illisible —
/// et surtout, on ne saurait pas à qui attribuer une facture éditée à la main.
class FacturesAbonnementBoutiquePage extends StatefulWidget {
  const FacturesAbonnementBoutiquePage({super.key});

  @override
  State<FacturesAbonnementBoutiquePage> createState() =>
      _FacturesAbonnementBoutiquePageState();
}

class _FacturesAbonnementBoutiquePageState
    extends State<FacturesAbonnementBoutiquePage> {
  final EntrepriseService _entreprises = EntrepriseService.instance;

  List<Entreprise> _boutiques = const <Entreprise>[];
  bool _chargement = true;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _charger());
  }

  Future<void> _charger() async {
    setState(() => _chargement = true);
    try {
      final List<Entreprise> entreprises = await _entreprises.getEntreprises();
      if (!mounted) return;
      setState(() {
        _boutiques = entreprises;
        _chargement = false;
        _erreur = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _chargement = false;
        _erreur = 'Impossible de lire les boutiques : $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chargement) {
      return const Scaffold(body: Center(child: ModernLoader()));
    }

    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Factures d\'abonnement'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _erreur != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_erreur!, textAlign: TextAlign.center),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _boutiques.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (BuildContext _, int index) {
                final Entreprise entreprise = _boutiques[index];

                return Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppCouleurs.marine,
                      child: Icon(Icons.storefront_rounded,
                          color: Colors.white, size: 20),
                    ),
                    title: Text(entreprise.nom),
                    subtitle: Text('Ouvrir les factures de cette boutique',
                        style: theme.textTheme.bodySmall),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FacturesAbonnementPage(
                          entrepriseId: entreprise.id,
                          nomEtablissement: entreprise.nom,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
