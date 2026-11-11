// lib/pages/pressing/pressing_reglages_page.dart
//
// 🧺 MODULE 35 — RÉGLAGES & CATALOGUE DU PRESSING.
//
// Un pressing sans catalogue ne peut RIEN facturer : avant de prendre un
// vêtement, il faut dire ce qu'il sait traiter (prestations), quels vêtements
// il reçoit (types), et COMBIEN il facture (tarifs). Cet écran est donc l'étape
// qui rend le module utilisable.
//
// CINQ ONGLETS
//   1. Réglages    — devise, délai standard, supplément d'urgence, politique de
//                    remise, collecte, fidélité, notifications ;
//   2. Vêtements   — les types reçus (chemise, costume, couverture…) ;
//   3. Prestations — ce qui est facturé (lavage, repassage, détachage, express…) ;
//   4. Tarifs      — le prix d'une prestation pour un type de vêtement (ou le
//                    tarif par défaut de la prestation) ;
//   5. Étapes      — le circuit de traitement d'un vêtement.
//
// ⚠️ Tout est décidé par le serveur : cet écran transmet, il ne calcule rien.
//    Le droit requis est `pressing_depots/modifier` (le responsable).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/pressing_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class PressingReglagesPage extends StatefulWidget {
  const PressingReglagesPage({super.key});

  @override
  State<PressingReglagesPage> createState() => _PressingReglagesPageState();
}

class _PressingReglagesPageState extends State<PressingReglagesPage> {
  bool _chargement = true;
  String? _erreur;
  bool _enregistrementConfig = false;

  PressingConfig _config = PressingConfig.defaut;
  PressingCatalogue _catalogue = const PressingCatalogue();
  List<PressingEtape> _etapes = const <PressingEtape>[];

  // — Formulaire des réglages —
  final TextEditingController _devise = TextEditingController();
  final TextEditingController _delai = TextEditingController();
  final TextEditingController _urgence = TextEditingController();
  final TextEditingController _fraisCollecte = TextEditingController();
  final TextEditingController _fideliteSeuil = TextEditingController();
  final TextEditingController _fidelitePct = TextEditingController();

  String _politique = 'SOLDE_OBLIGATOIRE';
  bool _collecteActive = false;
  bool _fideliteActive = false;
  bool _notifyDepot = true;
  bool _notifyPret = true;
  bool _notifyRetard = true;
  bool _notifyPaiement = true;

  /// Prestation sélectionnée dans l'onglet Tarifs.
  String? _prestationChoisie;

  bool get _peutModifier =>
      PermissionService.instance.peut(
        PageAccess.pressingDepots,
        ActionAccess.modifier,
      ) ||
      PermissionService.instance.peut(
        PageAccess.pressingDepots,
        ActionAccess.creer,
      );

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _devise.dispose();
    _delai.dispose();
    _urgence.dispose();
    _fraisCollecte.dispose();
    _fideliteSeuil.dispose();
    _fidelitePct.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _charger() async {
    setState(() {
      _chargement = _catalogue.estVide && _etapes.isEmpty;
      _erreur = null;
    });
    try {
      final PressingConfig config = await PressingService.instance.config();
      final PressingCatalogue catalogue =
          await PressingService.instance.catalogue();
      final List<PressingEtape> etapes =
          await PressingService.instance.etapes();

      if (!mounted) return;
      setState(() {
        _config = config;
        _catalogue = catalogue;
        _etapes = etapes;
        _prestationChoisie = catalogue.prestations.isEmpty
            ? null
            : (catalogue.prestations
                        .any((PressingPrestation p) => p.id == _prestationChoisie)
                    ? _prestationChoisie
                    : catalogue.prestations.first.id);
        _remplirFormulaire(config);
        _chargement = false;
      });
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    }
  }

  void _remplirFormulaire(PressingConfig config) {
    _devise.text = config.devise;
    _delai.text = config.delaiStandardJours.toString();
    _urgence.text = _texteNombre(config.supplementUrgence);
    _fraisCollecte.text = _texteNombre(config.fraisCollecte);
    _fideliteSeuil.text = _texteNombre(config.fideliteSeuil);
    _fidelitePct.text = _texteNombre(config.fideliteRemisePct);
    _politique = config.politiqueRemise;
    _collecteActive = config.collecteActive;
    _fideliteActive = config.fideliteActive;
    _notifyDepot = config.notifyDepot;
    _notifyPret = config.notifyPret;
    _notifyRetard = config.notifyRetard;
    _notifyPaiement = config.notifyPaiement;
  }

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT DES RÉGLAGES
  // ---------------------------------------------------------------------------

  Future<void> _enregistrerConfig() async {
    if (_enregistrementConfig) return;

    final int? delai = int.tryParse(_delai.text.trim());
    final double urgence = parseMontantSaisi(_urgence.text) ?? 0;
    final double frais = parseMontantSaisi(_fraisCollecte.text) ?? 0;
    final double seuil = parseMontantSaisi(_fideliteSeuil.text) ?? 0;
    final double pct = parseMontantSaisi(_fidelitePct.text) ?? 0;

    if (delai == null || delai < 0 || delai > 90) {
      _message('Le délai standard doit être un nombre de jours (0 à 90).',
          erreur: true);
      return;
    }
    if (pct < 0 || pct > 100) {
      _message('La remise fidélité doit être comprise entre 0 et 100 %.',
          erreur: true);
      return;
    }

    setState(() => _enregistrementConfig = true);
    try {
      final PressingConfig config = await PressingService.instance
          .enregistrerConfig(
        PressingConfig(
          devise: _devise.text.trim().isEmpty ? 'CDF' : _devise.text.trim(),
          delaiStandardJours: delai,
          supplementUrgence: urgence,
          politiqueRemise: _politique,
          collecteActive: _collecteActive,
          fraisCollecte: frais,
          fideliteActive: _fideliteActive,
          fideliteSeuil: seuil,
          fideliteRemisePct: pct,
          notifyDepot: _notifyDepot,
          notifyPret: _notifyPret,
          notifyRetard: _notifyRetard,
          notifyPaiement: _notifyPaiement,
        ),
      );
      if (!mounted) return;
      setState(() {
        _config = config;
        _enregistrementConfig = false;
      });
      _message('Réglages du pressing enregistrés.');
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() => _enregistrementConfig = false);
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS CATALOGUE
  // ---------------------------------------------------------------------------

  Future<void> _preparerCatalogue() async {
    try {
      final PressingCatalogue catalogue =
          await PressingService.instance.amorcerCatalogue();
      if (!mounted) return;
      setState(() {
        _catalogue = catalogue;
        _prestationChoisie = catalogue.prestations.isEmpty
            ? null
            : catalogue.prestations.first.id;
      });
      _message(
        'Catalogue de départ créé : '
        '${catalogue.categories.length} type(s) de vêtement, '
        '${catalogue.prestations.length} prestation(s). '
        'Les tarifs restent à définir.',
      );
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _preparerEtapes() async {
    try {
      final List<PressingEtape> etapes =
          await PressingService.instance.amorcerEtapes();
      if (!mounted) return;
      setState(() => _etapes = etapes);
      _message('Étapes de traitement préparées (${etapes.length}).');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _enregistrerCategorie(PressingCategorie? existante) async {
    final _SaisieNom? saisie = await showDialog<_SaisieNom>(
      context: context,
      builder: (BuildContext ctx) => _DialogueTexte(
        titre: existante == null
            ? 'Nouveau type de vêtement'
            : 'Modifier « ${existante.nom} »',
        libelle: 'Nom du vêtement',
        aide: 'Ex. : chemise, costume, couverture, robe…',
        valeurInitiale: existante?.nom,
      ),
    );
    if (saisie == null) return;

    try {
      await PressingService.instance.categorieEnregistrer(
        id: existante?.id,
        nom: saisie.texte,
        ordre: existante?.ordre ?? 100,
        actif: existante?.actif ?? true,
      );
      await _charger();
      _message('Type de vêtement enregistré.');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _basculerCategorie(PressingCategorie categorie) async {
    try {
      await PressingService.instance.categorieEnregistrer(
        id: categorie.id,
        nom: categorie.nom,
        ordre: categorie.ordre,
        actif: !categorie.actif,
      );
      await _charger();
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _dialoguePrestation(PressingPrestation? existante) async {
    final _SaisiePrestation? saisie = await showDialog<_SaisiePrestation>(
      context: context,
      builder: (BuildContext ctx) => _DialoguePrestation(existante: existante),
    );
    if (saisie == null) return;

    try {
      await PressingService.instance.prestationEnregistrer(
        id: existante?.id,
        nom: saisie.nom,
        description: saisie.description,
        dureeHeures: saisie.dureeHeures,
        delaiJours: saisie.delaiJours,
        supplementUrgence: saisie.supplementUrgence,
        actif: existante?.actif ?? true,
      );
      await _charger();
      _message('Prestation enregistrée.');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _basculerPrestation(PressingPrestation prestation) async {
    try {
      await PressingService.instance.prestationEnregistrer(
        id: prestation.id,
        nom: prestation.nom,
        description: prestation.description,
        dureeHeures: prestation.dureeHeures,
        delaiJours: prestation.delaiJours,
        supplementUrgence: prestation.supplementUrgence,
        actif: !prestation.actif,
      );
      await _charger();
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  /// Prix actuellement appliqué pour (prestation, type de vêtement).
  double? _prixActuel(String prestationId, String? categorieId) {
    for (final PressingTarif t in _catalogue.tarifs) {
      if (t.prestationId == prestationId &&
          t.categorieId == categorieId &&
          t.actif) {
        return t.prix;
      }
    }
    return null;
  }

  PressingTarif? _tarifDe(String prestationId, String? categorieId) {
    for (final PressingTarif t in _catalogue.tarifs) {
      if (t.prestationId == prestationId &&
          t.categorieId == categorieId &&
          t.actif) {
        return t;
      }
    }
    return null;
  }

  Future<void> _definirTarif(
    PressingPrestation prestation,
    PressingCategorie? categorie,
  ) async {
    final double? actuel = _prixActuel(prestation.id, categorie?.id);
    final double? prix = await showDialog<double>(
      context: context,
      builder: (BuildContext ctx) => _DialoguePrix(
        titre: categorie == null
            ? 'Tarif par défaut — ${prestation.nom}'
            : '${prestation.nom} — ${categorie.nom}',
        aide: categorie == null
            ? 'Appliqué quand aucun tarif spécifique n\'existe pour le vêtement.'
            : 'Prix facturé pour ce type de vêtement.',
        devise: _config.devise,
        valeurInitiale: actuel,
      ),
    );
    if (prix == null) return;

    try {
      if (prix <= 0) {
        final PressingTarif? existant = _tarifDe(prestation.id, categorie?.id);
        if (existant == null) {
          _message('Aucun tarif à retirer pour cette ligne.', erreur: true);
          return;
        }
        await PressingService.instance.tarifSupprimer(existant.id);
        await _charger();
        _message('Tarif retiré.');
        return;
      }
      await PressingService.instance.tarifDefinir(
        prestationId: prestation.id,
        categorieId: categorie?.id,
        prix: prix,
      );
      await _charger();
      _message('Tarif enregistré.');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _dialogueEtape(PressingEtape? existante) async {
    final _SaisieEtape? saisie = await showDialog<_SaisieEtape>(
      context: context,
      builder: (BuildContext ctx) => _DialogueEtape(
        existante: existante,
        ordreSuivant: _etapes.isEmpty
            ? 10
            : (_etapes
                        .map((PressingEtape e) => e.ordre)
                        .reduce((int a, int b) => a > b ? a : b) +
                    10),
      ),
    );
    if (saisie == null) return;

    try {
      await PressingService.instance.etapeEnregistrer(
        id: existante?.id,
        code: saisie.code,
        libelle: saisie.libelle,
        ordre: saisie.ordre,
        finale: saisie.finale,
        actif: existante?.actif ?? true,
      );
      await _charger();
      _message('Étape enregistrée.');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _basculerEtape(PressingEtape etape) async {
    try {
      await PressingService.instance.etapeEnregistrer(
        id: etape.id,
        code: etape.code,
        libelle: etape.libelle,
        ordre: etape.ordre,
        finale: etape.estFinale,
        actif: !etape.actif,
      );
      await _charger();
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Réglages du pressing'),
          actions: <Widget>[
            IconButton(
              tooltip: 'Actualiser',
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: <Widget>[
              Tab(text: 'Réglages', icon: Icon(Icons.tune_rounded, size: 20)),
              Tab(text: 'Vêtements', icon: Icon(Icons.checkroom_rounded, size: 20)),
              Tab(text: 'Prestations', icon: Icon(Icons.local_laundry_service_rounded, size: 20)),
              Tab(text: 'Tarifs', icon: Icon(Icons.sell_rounded, size: 20)),
              Tab(text: 'Étapes', icon: Icon(Icons.route_rounded, size: 20)),
            ],
          ),
        ),
        body: _chargement
            ? const Center(child: CircularProgressIndicator())
            : _erreur != null
                ? _vueErreur(_erreur!)
                : TabBarView(
                    children: <Widget>[
                      _ongletReglages(),
                      _ongletCategories(),
                      _ongletPrestations(),
                      _ongletTarifs(),
                      _ongletEtapes(),
                    ],
                  ),
      ),
    );
  }

  Widget _vueErreur(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 56, color: AppCouleurs.danger),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _encart(String texte, {IconData icone = Icons.info_outline_rounded}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppCouleurs.marine.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icone, size: 18, color: AppCouleurs.marine),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texte, style: const TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }

  Widget _titre(String texte, {String? aide}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            texte,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          if (aide != null)
            Text(
              aide,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
        ],
      ),
    );
  }

  InputDecoration _deco(String libelle, {String? aide, IconData? icone}) {
    return InputDecoration(
      labelText: libelle,
      helperText: aide,
      helperMaxLines: 2,
      prefixIcon: icone == null ? null : Icon(icone),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  // — ONGLET 1 : RÉGLAGES ----------------------------------------------------

  Widget _ongletReglages() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        _encart(
          'Ces réglages s\'appliquent à TOUT le pressing : ils décident du '
          'délai promis au client, du supplément d\'urgence, et si un vêtement '
          'peut être remis avec un solde impayé.',
        ),
        _titre('Identité et délais'),
        TextField(
          controller: _devise,
          textCapitalization: TextCapitalization.characters,
          decoration: _deco('Devise', aide: 'Ex. : CDF, USD', icone: Icons.payments_outlined),
          enabled: _peutModifier,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _delai,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
          decoration: _deco('Délai standard (jours)',
              aide: 'Délai promis au client pour un traitement normal.',
              icone: Icons.schedule_rounded),
          enabled: _peutModifier,
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _urgence,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: _deco('Supplément d\'urgence',
              aide: 'Montant ajouté quand le client veut son vêtement plus vite.',
              icone: Icons.bolt_rounded),
          enabled: _peutModifier,
        ),
        const SizedBox(height: 18),
        _titre('Remise des vêtements',
            aide: 'Décide si un vêtement peut sortir avec un solde impayé.'),
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment<String>(
              value: 'SOLDE_OBLIGATOIRE',
              label: Text('Solde obligatoire'),
              icon: Icon(Icons.lock_rounded, size: 18),
            ),
            ButtonSegment<String>(
              value: 'REMISE_POSSIBLE',
              label: Text('Remise avec dette'),
              icon: Icon(Icons.lock_open_rounded, size: 18),
            ),
          ],
          selected: <String>{_politique},
          onSelectionChanged: _peutModifier
              ? (Set<String> choix) => setState(() => _politique = choix.first)
              : null,
        ),
        const SizedBox(height: 18),
        _titre('Collecte et livraison'),
        SwitchListTile(
          value: _collecteActive,
          onChanged: _peutModifier
              ? (bool v) => setState(() => _collecteActive = v)
              : null,
          title: const Text('Collecte à domicile'),
          subtitle: const Text('L\'agent peut programmer un ramassage.'),
          contentPadding: EdgeInsets.zero,
        ),
        if (_collecteActive)
          TextField(
            controller: _fraisCollecte,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _deco('Frais de collecte',
                icone: Icons.local_shipping_outlined),
            enabled: _peutModifier,
          ),
        const SizedBox(height: 18),
        _titre('Carte de fidélité'),
        SwitchListTile(
          value: _fideliteActive,
          onChanged: _peutModifier
              ? (bool v) => setState(() => _fideliteActive = v)
              : null,
          title: const Text('Fidélité activée'),
          subtitle: const Text('Une remise s\'applique après un certain montant.'),
          contentPadding: EdgeInsets.zero,
        ),
        if (_fideliteActive) ...<Widget>[
          TextField(
            controller: _fideliteSeuil,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _deco('Seuil de fidélité',
                aide: 'Montant cumulé à atteindre.', icone: Icons.flag_rounded),
            enabled: _peutModifier,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _fidelitePct,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: _deco('Remise fidélité (%)',
                icone: Icons.percent_rounded),
            enabled: _peutModifier,
          ),
        ],
        const SizedBox(height: 18),
        _titre('Notifications'),
        SwitchListTile(
          value: _notifyDepot,
          onChanged: _peutModifier ? (bool v) => setState(() => _notifyDepot = v) : null,
          title: const Text('Confirmer le dépôt'),
          subtitle: const Text('Message au client avec le reçu.'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _notifyPret,
          onChanged: _peutModifier ? (bool v) => setState(() => _notifyPret = v) : null,
          title: const Text('Prévenir quand c\'est prêt'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _notifyRetard,
          onChanged: _peutModifier ? (bool v) => setState(() => _notifyRetard = v) : null,
          title: const Text('Rappeler les retards'),
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          value: _notifyPaiement,
          onChanged: _peutModifier ? (bool v) => setState(() => _notifyPaiement = v) : null,
          title: const Text('Confirmer les paiements'),
          contentPadding: EdgeInsets.zero,
        ),
        const SizedBox(height: 16),
        if (_peutModifier)
          FilledButton.icon(
            onPressed: _enregistrementConfig ? null : _enregistrerConfig,
            icon: _enregistrementConfig
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_enregistrementConfig
                ? 'Enregistrement…'
                : 'Enregistrer les réglages'),
          )
        else
          const Text(
            'Seul le responsable du pressing peut modifier ces réglages.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
      ],
    );
  }

  // — ONGLET 2 : TYPES DE VÊTEMENTS ------------------------------------------

  Widget _ongletCategories() {
    final List<PressingCategorie> cats = _catalogue.categories;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        _encart(
          'Les types de vêtements reçus. Ils servent à appliquer le BON tarif : '
          'une couverture ne se facture pas comme une chemise.',
          icone: Icons.checkroom_rounded,
        ),
        if (cats.isEmpty)
          _vide(
            'Aucun type de vêtement.',
            action: _peutModifier ? _preparerCatalogue : null,
            libelleAction: 'Créer le catalogue de départ',
          )
        else
          ...cats.map(
            (PressingCategorie c) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(c.nom),
                subtitle: Text(c.actif ? 'Actif' : 'Désactivé'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_peutModifier)
                      IconButton(
                        tooltip: 'Renommer',
                        onPressed: () => _enregistrerCategorie(c),
                        icon: const Icon(Icons.edit_rounded, size: 20),
                      ),
                    if (_peutModifier)
                      Switch(
                        value: c.actif,
                        onChanged: (_) => _basculerCategorie(c),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_peutModifier) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _enregistrerCategorie(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter un type de vêtement'),
          ),
        ],
      ],
    );
  }

  // — ONGLET 3 : PRESTATIONS -------------------------------------------------

  Widget _ongletPrestations() {
    final List<PressingPrestation> prestations = _catalogue.prestations;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        _encart(
          'Ce que le pressing facture : lavage, repassage, détachage, express… '
          'Chaque prestation a son délai et son supplément d\'urgence.',
          icone: Icons.local_laundry_service_rounded,
        ),
        if (prestations.isEmpty)
          _vide(
            'Aucune prestation.',
            action: _peutModifier ? _preparerCatalogue : null,
            libelleAction: 'Créer le catalogue de départ',
          )
        else
          ...prestations.map(
            (PressingPrestation p) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(p.nom),
                subtitle: Text(
                  <String>[
                    'Délai ${p.delaiJours} j',
                    if (p.supplementUrgence > 0)
                      'urgence +${formatMontant(p.supplementUrgence)}',
                    if (!p.actif) 'DÉSACTIVÉE',
                    if ((p.description ?? '').trim().isNotEmpty) p.description!,
                  ].join(' · '),
                ),
                isThreeLine: (p.description ?? '').trim().isNotEmpty,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_peutModifier)
                      IconButton(
                        tooltip: 'Modifier',
                        onPressed: () => _dialoguePrestation(p),
                        icon: const Icon(Icons.edit_rounded, size: 20),
                      ),
                    if (_peutModifier)
                      Switch(
                        value: p.actif,
                        onChanged: (_) => _basculerPrestation(p),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_peutModifier) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _dialoguePrestation(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter une prestation'),
          ),
        ],
      ],
    );
  }

  // — ONGLET 4 : TARIFS ------------------------------------------------------

  Widget _ongletTarifs() {
    final List<PressingPrestation> prestations = _catalogue.prestations;
    if (prestations.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _vide('Créez d\'abord une prestation et des types de vêtements.'),
        ],
      );
    }

    final PressingPrestation choisie =
        _catalogue.prestationParId(_prestationChoisie) ?? prestations.first;
    final List<PressingCategorie> cats = _catalogue.categories;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: <Widget>[
        _encart(
          'Le prix facturé au dépôt. Le tarif du vêtement prime ; s\'il n\'existe '
          'pas, le tarif par défaut de la prestation s\'applique.',
          icone: Icons.sell_rounded,
        ),
        _titre('Prestation'),
        DropdownButtonFormField<String>(
          initialValue: choisie.id,
          isExpanded: true,
          decoration: _deco('Prestation facturée'),
          items: prestations
              .map((PressingPrestation p) => DropdownMenuItem<String>(
                    value: p.id,
                    child: Text(
                      p.actif ? p.nom : '${p.nom} (désactivée)',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ))
              .toList(growable: false),
          onChanged: (String? id) => setState(() => _prestationChoisie = id),
        ),
        const SizedBox(height: 16),
        _titre('Tarifs', aide: 'Vide = aucun prix : l\'agent le saisira au dépôt.'),
        Card(
          elevation: 0,
          child: ListTile(
            leading: const Icon(Icons.star_rounded, color: AppCouleurs.orange),
            title: const Text('Tarif par défaut'),
            subtitle: const Text('Appliqué à tous les vêtements sans tarif propre'),
            trailing: Text(
              _prixActuel(choisie.id, null) == null
                  ? 'à définir'
                  : formatMontant(_prixActuel(choisie.id, null)!),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: _prixActuel(choisie.id, null) == null
                    ? Colors.grey
                    : AppCouleurs.marine,
              ),
            ),
            onTap: _peutModifier ? () => _definirTarif(choisie, null) : null,
          ),
        ),
        const SizedBox(height: 8),
        ...cats.map((PressingCategorie c) {
          final double? prix = _prixActuel(choisie.id, c.id);
          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              title: Text(c.nom),
              subtitle: c.actif ? null : const Text('Type désactivé'),
              trailing: Text(
                prix == null ? 'tarif par défaut' : formatMontant(prix),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: prix == null ? FontWeight.normal : FontWeight.bold,
                  color: prix == null ? Colors.grey : AppCouleurs.marine,
                ),
              ),
              onTap: _peutModifier ? () => _definirTarif(choisie, c) : null,
            ),
          );
        }),
        const SizedBox(height: 10),
        if (_peutModifier)
          Text(
            'Touchez une ligne pour fixer (ou retirer) le prix. '
            'Un prix laissé vide utlise le tarif par défaut.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
      ],
    );
  }

  // — ONGLET 5 : ÉTAPES ------------------------------------------------------

  Widget _ongletEtapes() {
    final List<PressingEtape> etapes = <PressingEtape>[..._etapes]
      ..sort((PressingEtape a, PressingEtape b) => a.ordre.compareTo(b.ordre));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        _encart(
          'Le circuit d\'un vêtement, dans l\'ordre. L\'étape « finale » est '
          'celle qui rend le vêtement remis­able : c\'est elle qui prévient le '
          'client que sa commande est prête.',
          icone: Icons.route_rounded,
        ),
        if (etapes.isEmpty)
          _vide(
            'Aucune étape définie.',
            action: _peutModifier ? _preparerEtapes : null,
            libelleAction: 'Préparer les étapes par défaut',
          )
        else
          ...etapes.map(
            (PressingEtape e) => Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: AppCouleurs.marine.withValues(alpha: 0.10),
                  child: Text(
                    e.ordre.toString(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(e.libelle),
                subtitle: Text(
                  <String>[
                    'code : ${e.code}',
                    if (e.estFinale) 'ÉTAPE FINALE',
                    if (!e.actif) 'désactivée',
                  ].join(' · '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (_peutModifier)
                      IconButton(
                        tooltip: 'Modifier',
                        onPressed: () => _dialogueEtape(e),
                        icon: const Icon(Icons.edit_rounded, size: 20),
                      ),
                    if (_peutModifier)
                      Switch(
                        value: e.actif,
                        onChanged: (_) => _basculerEtape(e),
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (_peutModifier) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _dialogueEtape(null),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter une étape'),
          ),
        ],
      ],
    );
  }

  Widget _vide(String texte, {VoidCallback? action, String? libelleAction}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: <Widget>[
          Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 10),
          Text(
            texte,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          if (action != null && libelleAction != null) ...<Widget>[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: Text(libelleAction),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
//  BOÎTES DE DIALOGUE
// =============================================================================

class _SaisieNom {
  const _SaisieNom(this.texte);
  final String texte;
}

class _DialogueTexte extends StatefulWidget {
  const _DialogueTexte({
    required this.titre,
    required this.libelle,
    this.aide,
    this.valeurInitiale,
  });

  final String titre;
  final String libelle;
  final String? aide;
  final String? valeurInitiale;

  @override
  State<_DialogueTexte> createState() => _DialogueTexteState();
}

class _DialogueTexteState extends State<_DialogueTexte> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.valeurInitiale);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _valider() {
    final String texte = _ctrl.text.trim();
    if (texte.length < 2) return;
    Navigator.of(context).pop(_SaisieNom(texte));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: widget.libelle,
          helperText: widget.aide,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _valider(),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _SaisiePrestation {
  const _SaisiePrestation({
    required this.nom,
    required this.dureeHeures,
    required this.delaiJours,
    required this.supplementUrgence,
    this.description,
  });

  final String nom;
  final String? description;
  final int dureeHeures;
  final int delaiJours;
  final double supplementUrgence;
}

class _DialoguePrestation extends StatefulWidget {
  const _DialoguePrestation({this.existante});

  final PressingPrestation? existante;

  @override
  State<_DialoguePrestation> createState() => _DialoguePrestationState();
}

class _DialoguePrestationState extends State<_DialoguePrestation> {
  late final TextEditingController _nom =
      TextEditingController(text: widget.existante?.nom ?? '');
  late final TextEditingController _description =
      TextEditingController(text: widget.existante?.description ?? '');
  late final TextEditingController _duree = TextEditingController(
      text: (widget.existante?.dureeHeures ?? 24).toString());
  late final TextEditingController _delai = TextEditingController(
      text: (widget.existante?.delaiJours ?? 3).toString());
  late final TextEditingController _urgence = TextEditingController(
      text: _texteNombre(
          widget.existante?.supplementUrgence ?? 0));

  String? _erreur;

  @override
  void dispose() {
    _nom.dispose();
    _description.dispose();
    _duree.dispose();
    _delai.dispose();
    _urgence.dispose();
    super.dispose();
  }

  void _valider() {
    final String nom = _nom.text.trim();
    if (nom.length < 2) {
      setState(() => _erreur = 'Indiquez le nom de la prestation.');
      return;
    }
    final int duree = int.tryParse(_duree.text.trim()) ?? 24;
    final int delai = int.tryParse(_delai.text.trim()) ?? 3;
    if (delai < 0 || delai > 90) {
      setState(() => _erreur = 'Le délai doit être compris entre 0 et 90 jours.');
      return;
    }
    Navigator.of(context).pop(
      _SaisiePrestation(
        nom: nom,
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        dureeHeures: duree,
        delaiJours: delai,
        supplementUrgence: parseMontantSaisi(_urgence.text) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existante == null
          ? 'Nouvelle prestation'
          : 'Modifier « ${widget.existante!.nom} »'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nom,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom',
                hintText: 'Lavage, repassage, détachage…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (facultative)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _delai,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Délai (jours)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _duree,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Durée (heures)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _urgence,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Supplément d\'urgence',
                helperText: '0 = aucun supplément',
                border: OutlineInputBorder(),
              ),
            ),
            if (_erreur != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _erreur!,
                style: TextStyle(color: AppCouleurs.danger, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _DialoguePrix extends StatefulWidget {
  const _DialoguePrix({
    required this.titre,
    required this.devise,
    this.aide,
    this.valeurInitiale,
  });

  final String titre;
  final String devise;
  final String? aide;
  final double? valeurInitiale;

  @override
  State<_DialoguePrix> createState() => _DialoguePrixState();
}

class _DialoguePrixState extends State<_DialoguePrix> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.valeurInitiale == null
        ? ''
        : _texteNombre(widget.valeurInitiale!),
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titre),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Prix (${widget.devise})',
              helperText: widget.aide,
              helperMaxLines: 2,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Laissez vide ou 0 pour retirer ce tarif.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(parseMontantSaisi(_ctrl.text) ?? 0),
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _SaisieEtape {
  const _SaisieEtape({
    required this.code,
    required this.libelle,
    required this.ordre,
    required this.finale,
  });

  final String code;
  final String libelle;
  final int ordre;
  final bool finale;
}

class _DialogueEtape extends StatefulWidget {
  const _DialogueEtape({this.existante, required this.ordreSuivant});

  final PressingEtape? existante;
  final int ordreSuivant;

  @override
  State<_DialogueEtape> createState() => _DialogueEtapeState();
}

class _DialogueEtapeState extends State<_DialogueEtape> {
  late final TextEditingController _libelle =
      TextEditingController(text: widget.existante?.libelle ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.existante?.code ?? '');
  late final TextEditingController _ordre = TextEditingController(
      text: (widget.existante?.ordre ?? widget.ordreSuivant).toString());

  bool _finale = false;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _finale = widget.existante?.estFinale ?? false;
  }

  @override
  void dispose() {
    _libelle.dispose();
    _code.dispose();
    _ordre.dispose();
    super.dispose();
  }

  /// Code technique déduit du libellé : « Repassage » → « REPASSAGE ».
  static String _codeDepuis(String libelle) {
    final String base = libelle
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return base.isEmpty ? 'ETAPE' : base;
  }

  void _valider() {
    final String libelle = _libelle.text.trim();
    if (libelle.length < 2) {
      setState(() => _erreur = 'Indiquez le nom de l\'étape.');
      return;
    }
    final String code = _code.text.trim().isEmpty
        ? _codeDepuis(libelle)
        : _codeDepuis(_code.text);
    final int ordre = int.tryParse(_ordre.text.trim()) ??
        widget.ordreSuivant;
    Navigator.of(context).pop(
      _SaisieEtape(code: code, libelle: libelle, ordre: ordre, finale: _finale),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existante == null
          ? 'Nouvelle étape'
          : 'Modifier « ${widget.existante!.libelle} »'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _libelle,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nom de l\'étape',
                hintText: 'Lavage, repassage, contrôle…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ordre,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly
              ],
              decoration: const InputDecoration(
                labelText: 'Ordre',
                helperText: 'Plus petit = plus tôt dans le circuit.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              value: _finale,
              onChanged: (bool v) => setState(() => _finale = v),
              title: const Text('Étape finale'),
              subtitle: const Text(
                  'Le vêtement devient « prêt » : le client peut être prévenu.'),
              contentPadding: EdgeInsets.zero,
            ),
            if (_erreur != null)
              Text(
                _erreur!,
                style: TextStyle(color: AppCouleurs.danger, fontSize: 12.5),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _valider, child: const Text('Enregistrer')),
      ],
    );
  }
}

/// « 1500 » → « 1500 », « 12.5 » → « 12,5 » (saisie française).
String _texteNombre(double v) {
  if (v == v.roundToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2).replaceAll('.', ',');
}
