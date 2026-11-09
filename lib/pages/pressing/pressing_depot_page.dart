// lib/pages/pressing/pressing_depot_page.dart
//
// 🧺 MODULE 35 — NOUVEAU DÉPÔT AU PRESSING.
//
// CE QUE FAIT CET ÉCRAN
//   L'agent reçoit un client et ses vêtements. Il doit pouvoir travailler vite,
//   au comptoir, sur téléphone comme sur tablette :
//     1. choisir le client (recherche par nom/téléphone) ou en créer un ;
//     2. ajouter les vêtements : type, prestation, prix si le catalogue n'en
//        a pas, état au dépôt et défauts constatés (anti-litige) ;
//     3. indiquer une remise, un supplément, l'urgence, la date promise ;
//     4. encaisser une avance (ou rien) ;
//     5. enregistrer → le serveur numérote, fige les prix et renvoie le reçu.
//
// ⚠️ Les totaux affichés ne sont qu'une ESTIMATION pour l'agent : le serveur
//    recalcule tout et fait foi (prix du catalogue, plafonds, remise).
//
// ⚠️ Aucune donnée inventée : si le catalogue est vide, l'écran propose de
//    le préparer (types de vêtements + prestations), sans imposer de prix.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';
import 'package:biashara_yangu/services/pressing_recu_pdf_service.dart';
import 'package:biashara_yangu/services/pressing_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// Un vêtement en cours de saisie.
///
/// Champs simples, tous modifiables par `setState` : l'agent remplit la fiche
/// au comptoir, sans étape obligatoire.
class _Saisie {
  String? categorieId;
  String? prestationId;
  String designation = '';
  double quantite = 1;
  double? prix;
  String etatDepot = '';
  String defauts = '';
  String observations = '';

  _Saisie();
}

class PressingDepotPage extends StatefulWidget {
  const PressingDepotPage({super.key, this.commande});

  /// Renseigné pour... plus tard (duplication d'un dépôt). `null` = nouveau.
  final PressingCommande? commande;

  @override
  State<PressingDepotPage> createState() => _PressingDepotPageState();
}

class _PressingDepotPageState extends State<PressingDepotPage> {
  final TextEditingController _rechercheClient = TextEditingController();
  final TextEditingController _designation = TextEditingController();
  final TextEditingController _defauts = TextEditingController();
  final TextEditingController _remise = TextEditingController();
  final TextEditingController _supplement = TextEditingController();
  final TextEditingController _montantRecu = TextEditingController();
  final TextEditingController _notes = TextEditingController();

  bool _chargement = true;
  bool _envoi = false;
  String? _erreur;

  PressingCatalogue _catalogue = const PressingCatalogue();
  PressingConfig _config = PressingConfig.defaut;
  List<PressingClient> _clients = const <PressingClient>[];

  PressingClient? _clientChoisi;
  String _nouveauNom = '';
  String _nouveauTelephone = '';
  final List<_Saisie> _lignes = <_Saisie>[];

  bool _urgence = false;
  String _modePaiement = 'especes';
  DateTime _datePrevue = DateTime.now().add(const Duration(days: 3));

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _rechercheClient.dispose();
    _designation.dispose();
    _defauts.dispose();
    _remise.dispose();
    _supplement.dispose();
    _montantRecu.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });
    try {
      final PressingConfig config = await PressingService.instance.config();
      final PressingCatalogue catalogue =
          await PressingService.instance.catalogue();
      final List<PressingClient> clients =
          await PressingService.instance.clients(limite: 200);

      if (!mounted) return;
      setState(() {
        _config = config;
        _catalogue = catalogue;
        _clients = clients;
        _datePrevue =
            DateTime.now().add(Duration(days: config.delaiStandardJours));
        if (_lignes.isEmpty) _lignes.add(_Saisie());
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

  void _message(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  double get _totalLignes => _lignes.fold<double>(
        0,
        (double somme, _Saisie l) =>
            somme + (l.prix ?? _catalogue.prixPour(l.prestationId ?? '', l.categorieId) ?? 0) * l.quantite,
      );

  double get _remiseValeur =>
      double.tryParse(_remise.text.replaceAll(',', '.')) ?? 0;

  double get _supplementValeur =>
      double.tryParse(_supplement.text.replaceAll(',', '.')) ?? 0;

  double get _totalEstime {
    final double brut = _totalLignes - _remiseValeur + _supplementValeur;
    return brut < 0 ? 0 : brut;
  }

  // ---------------------------------------------------------------------------
  // CLIENT
  // ---------------------------------------------------------------------------

  Future<void> _creerClient() async {
    final TextEditingController nom = TextEditingController();
    final TextEditingController tel = TextEditingController();
    final TextEditingController adresse = TextEditingController();
    final GlobalKey<FormState> cle = GlobalKey<FormState>();

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nouveau client'),
        content: Form(
          key: cle,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextFormField(
                controller: nom,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nom complet',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (String? v) =>
                    (v ?? '').trim().isEmpty ? 'Indiquez le nom.' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: tel,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Téléphone',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: adresse,
                decoration: const InputDecoration(
                  labelText: 'Adresse (facultatif)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              if (cle.currentState?.validate() != true) return;
              Navigator.of(ctx).pop(true);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );

    final String nomTexte = nom.text.trim();
    final String telTexte = tel.text.trim();
    final String adresseTexte = adresse.text.trim();
    nom.dispose();
    tel.dispose();
    adresse.dispose();

    if (ok != true) return;

    try {
      final String id = await PressingService.instance.clientEnregistrer(
        nom: nomTexte,
        telephone: telTexte.isEmpty ? null : telTexte,
        adresse: adresseTexte.isEmpty ? null : adresseTexte,
      );
      final List<PressingClient> clients =
          await PressingService.instance.clients(limite: 200);
      if (!mounted) return;
      setState(() {
        _clients = clients;
        // On ne sélectionne la fiche que si elle est réellement connue : un
        // identifiant vide enverrait une valeur invalide au serveur.
        for (final PressingClient c in clients) {
          if (c.id == id) {
            _clientChoisi = c;
            break;
          }
        }
        _nouveauNom = '';
        _nouveauTelephone = '';
      });
      _message('Client enregistré.');
    } on PressingException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // VÊTEMENTS
  // ---------------------------------------------------------------------------

  void _ajouterLigne() {
    setState(() => _lignes.add(_Saisie()));
  }

  void _supprimerLigne(int index) {
    if (_lignes.length == 1) {
      _message('Le dépôt doit contenir au moins un vêtement.', erreur: true);
      return;
    }
    setState(() => _lignes.removeAt(index));
  }

  Future<void> _detailsVetement(int index) async {
    final _Saisie ligne = _lignes[index];
    final TextEditingController designation =
        TextEditingController(text: ligne.designation);
    final TextEditingController etat = TextEditingController(text: ligne.etatDepot);
    final TextEditingController defauts =
        TextEditingController(text: ligne.defauts);
    final TextEditingController obs =
        TextEditingController(text: ligne.observations);

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Détail du vêtement'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: designation,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Désignation (ex. Chemise blanche)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: etat,
                  decoration: const InputDecoration(
                    labelText: 'État au dépôt (bon, usé…)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: defauts,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Taches / défauts constatés',
                    helperText: 'Protège le pressing en cas de litige',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: obs,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Observations (facultatif)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );

    if (ok == true) {
      setState(() {
        ligne.designation = designation.text.trim();
        ligne.etatDepot = etat.text.trim();
        ligne.defauts = defauts.text.trim();
        ligne.observations = obs.text.trim();
      });
    }

    designation.dispose();
    etat.dispose();
    defauts.dispose();
    obs.dispose();
  }

  Future<void> _prixManuel(int index) async {
    final _Saisie ligne = _lignes[index];
    final TextEditingController prix = TextEditingController(
      text: (ligne.prix ?? 0) == 0
          ? ''
          : (ligne.prix! == ligne.prix!.roundToDouble()
              ? ligne.prix!.toStringAsFixed(0)
              : ligne.prix!.toStringAsFixed(2)),
    );

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Prix du vêtement'),
        content: TextField(
          controller: prix,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: 'Prix (${_config.devise})',
            helperText: 'Laissez vide pour utiliser le tarif du catalogue',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );

    final String texte = prix.text.replaceAll(',', '.');
    prix.dispose();

    if (ok != true) return;
    setState(() {
      ligne.prix = texte.trim().isEmpty ? null : double.tryParse(texte);
    });
  }

  Future<void> _choisirDate() async {
    final DateTime? choisie = await showDatePicker(
      context: context,
      initialDate: _datePrevue,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Date de retrait prévue',
    );
    if (choisie != null) setState(() => _datePrevue = choisie);
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  Future<void> _enregistrer() async {
    if (_envoi) return;

    final List<_Saisie> valides = _lignes
        .where((_Saisie l) =>
            l.categorieId != null || l.designation.trim().isNotEmpty)
        .toList(growable: false);

    if (valides.isEmpty) {
      _message('Ajoutez au moins un vêtement avec son type.', erreur: true);
      return;
    }

    for (final _Saisie l in valides) {
      final double prix =
          l.prix ?? _catalogue.prixPour(l.prestationId ?? '', l.categorieId) ?? 0;
      if (prix <= 0) {
        _message(
          'Le vêtement « ${_libelleLigne(l)} » n\'a pas de prix : saisissez-le '
          'ou complétez le catalogue.',
          erreur: true,
        );
        return;
      }
    }

    setState(() => _envoi = true);

    try {
      String? clientId = _clientChoisi?.id;
      if (clientId != null && clientId.trim().isEmpty) clientId = null;
      if (clientId == null && _nouveauNom.trim().isNotEmpty) {
        clientId = await PressingService.instance.clientEnregistrer(
          nom: _nouveauNom.trim(),
          telephone:
              _nouveauTelephone.trim().isEmpty ? null : _nouveauTelephone.trim(),
        );
      }

      final double? recu = double.tryParse(
        _montantRecu.text.replaceAll(',', '.'),
      );

      final PressingCommande commande = await PressingService.instance.depot(
        clientId: clientId,
        lignes: valides
            .map(
              (_Saisie l) => LigneDepot(
                categorieId: l.categorieId,
                prestationId: l.prestationId,
                designation: l.designation,
                quantite: l.quantite,
                etatDepot: l.etatDepot,
                defauts: l.defauts,
                observations: l.observations,
                prixUnitaire: l.prix,
              ),
            )
            .toList(growable: false),
        datePrevue: _datePrevue,
        remise: _remiseValeur,
        supplement: _supplementValeur,
        urgence: _urgence,
        observations: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        paiementMontant: (recu != null && recu > 0) ? recu : null,
        paiementMode: _modePaiement,
      );

      if (!mounted) return;

      _message('Dépôt ${commande.numero} enregistré.');

      // Le reçu est produit tout de suite : le client repart avec.
      Etablissement etab = EtablissementService.instance.courant;
      try {
        etab = await EtablissementService.instance.charger();
      } catch (_) {
        // Une fiche ancienne vaut mieux qu'un reçu bloqué.
      }

      final DonneesRecuPressing donnees = DonneesRecuPressing(
        commande: commande,
        etablissement: etab,
        soldeObligatoire: _config.soldeObligatoire,
      );

      final bool enregistre =
          await PressingRecuPdfService.instance.telecharger(donnees);

      if (!mounted) return;
      await afficherActionsRecu(
        context,
        donnees,
        telechargeeAutomatiquement: enregistre,
      );
      if (!mounted) return;
      Navigator.of(context).pop(commande);
    } on PressingException catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _message(e.message, erreur: true);
    }
  }

  String _libelleLigne(_Saisie l) {
    if (l.designation.trim().isNotEmpty) return l.designation.trim();
    final PressingCategorie? c = _catalogue.categorieParId(l.categorieId);
    return c?.nom ?? 'Vêtement';
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nouveau dépôt'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser le catalogue',
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur(_erreur!)
              : _contenu(),
      bottomNavigationBar: _chargement || _erreur != null ? null : _barreTotale(),
    );
  }

  Widget _vueErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const SizedBox(height: 40),
        Icon(Icons.error_outline, size: 48, color: AppCouleurs.danger),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }

  Widget _contenu() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
      children: <Widget>[
        if (_catalogue.estVide) _avertissementCatalogue(),
        _sectionClient(),
        const SizedBox(height: 16),
        _sectionVetements(),
        const SizedBox(height: 16),
        _sectionOptions(),
        const SizedBox(height: 16),
        _sectionPaiement(),
      ],
    );
  }

  Widget _avertissementCatalogue() {
    return Card(
      color: AppCouleurs.alerte.withValues(alpha: 0.12),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded, color: AppCouleurs.alerte),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Votre catalogue est vide',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Préparez la liste des types de vêtements et des prestations. '
              'Aucun prix ne sera imposé : vous fixerez vos tarifs ensuite.',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () async {
                try {
                  final PressingCatalogue catalogue =
                      await PressingService.instance.amorcerCatalogue();
                  if (!mounted) return;
                  setState(() => _catalogue = catalogue);
                  _message('Catalogue préparé : ajoutez vos prix.');
                } on PressingException catch (e) {
                  _message(e.message, erreur: true);
                }
              },
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('Préparer le catalogue'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionClient() {
    final String recherche = _rechercheClient.text.trim().toLowerCase();
    final List<PressingClient> filtres = recherche.isEmpty
        ? _clients.take(5).toList(growable: false)
        : _clients
            .where((PressingClient c) =>
                c.nom.toLowerCase().contains(recherche) ||
                (c.telephone ?? '').contains(recherche))
            .take(10)
            .toList(growable: false);

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Client', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_clientChoisi != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppCouleurs.marineClair.withValues(alpha: 0.15),
                  child: const Icon(Icons.person_rounded,
                      color: AppCouleurs.marineClair),
                ),
                title: Text(_clientChoisi!.nom),
                subtitle: (_clientChoisi!.sousTitre).isEmpty
                    ? null
                    : Text(_clientChoisi!.sousTitre),
                trailing: IconButton(
                  tooltip: 'Changer de client',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => _clientChoisi = null),
                ),
              )
            else ...<Widget>[
              TextField(
                controller: _rechercheClient,
                decoration: const InputDecoration(
                  hintText: 'Rechercher un client (nom, téléphone)',
                  prefixIcon: Icon(Icons.search_rounded),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (filtres.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                ...filtres.map(
                  (PressingClient c) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline_rounded),
                    title: Text(c.nom),
                    subtitle: (c.sousTitre).isEmpty ? null : Text(c.sousTitre),
                    onTap: () => setState(() {
                      _clientChoisi = c;
                      _rechercheClient.clear();
                    }),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  TextButton.icon(
                    onPressed: _creerClient,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Nouveau client'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => setState(() {
                      _clientChoisi = null;
                      _nouveauNom = '';
                      _nouveauTelephone = '';
                    }),
                    child: const Text('Client de passage'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionVetements() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Vêtements déposés',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
            Text(
              '${_lignes.length}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List<Widget>.generate(_lignes.length, (int i) => _carteLigne(i)),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: _ajouterLigne,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Ajouter un vêtement'),
        ),
      ],
    );
  }

  Widget _carteLigne(int index) {
    final _Saisie ligne = _lignes[index];
    final double? prixCatalogue =
        _catalogue.prixPour(ligne.prestationId ?? '', ligne.categorieId);
    final double prix = ligne.prix ?? prixCatalogue ?? 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 13,
                  backgroundColor: AppCouleurs.marineClair.withValues(alpha: 0.15),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppCouleurs.marineClair,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _libelleLigne(ligne),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: () => _supprimerLigne(index),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: ligne.categorieId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Type de vêtement',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _catalogue.categories
                        .where((PressingCategorie c) => c.actif)
                        .map(
                          (PressingCategorie c) => DropdownMenuItem<String>(
                            value: c.id,
                            child: Text(c.nom, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (String? v) => setState(
                      () => ligne.categorieId = v,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: ligne.prestationId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Prestation',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _catalogue.prestations
                        .where((PressingPrestation p) => p.actif)
                        .map(
                          (PressingPrestation p) => DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(p.nom, overflow: TextOverflow.ellipsis),
                          ),
                        )
                        .toList(),
                    onChanged: (String? v) => setState(
                      () => ligne.prestationId = v,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                _compteur(ligne),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _prixManuel(index),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Prix (${_config.devise})',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: ligne.prix == null && prixCatalogue != null
                            ? 'Tarif du catalogue'
                            : null,
                      ),
                      child: Text(
                        prix <= 0
                            ? 'À saisir'
                            : formatMontant(prix, devise: _config.devise),
                        style: TextStyle(
                          color: prix <= 0
                              ? AppCouleurs.danger
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'État et défauts',
                  icon: Icon(
                    (ligne.defauts.trim().isEmpty && ligne.designation.trim().isEmpty)
                        ? Icons.notes_rounded
                        : Icons.check_circle_rounded,
                    color: (ligne.defauts.trim().isEmpty && ligne.designation.trim().isEmpty)
                        ? null
                        : AppCouleurs.succes,
                  ),
                  onPressed: () => _detailsVetement(index),
                ),
              ],
            ),
            if (ligne.defauts.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: AppCouleurs.alerte),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Défaut constaté : ${ligne.defauts.trim()}',
                        style: const TextStyle(fontSize: 11.5),
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

  Widget _compteur(_Saisie ligne) {
    return Row(
      children: <Widget>[
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline_rounded),
          onPressed: ligne.quantite <= 1
              ? null
              : () => setState(() => ligne.quantite -= 1),
        ),
        Text(
          ligne.quantite == ligne.quantite.roundToDouble()
              ? ligne.quantite.toStringAsFixed(0)
              : ligne.quantite.toStringAsFixed(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline_rounded),
          onPressed: () => setState(() => ligne.quantite += 1),
        ),
      ],
    );
  }

  Widget _sectionOptions() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Délai et conditions',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_rounded),
              title: const Text('Retrait prévu'),
              subtitle: Text(formatDate(_datePrevue)),
              trailing: TextButton(
                onPressed: _choisirDate,
                child: const Text('Changer'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _urgence,
              onChanged: (bool v) => setState(() => _urgence = v),
              title: const Text('Service express'),
              subtitle: const Text('Le vêtement est traité en priorité'),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _remise,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Remise',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _supplement,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Supplément',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _notes,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Observations sur le dépôt (facultatif)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionPaiement() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Encaissement (facultatif)',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _montantRecu,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Montant reçu maintenant',
                helperText: 'Laissez vide si le client paie au retrait',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'especes',
                  label: Text('Espèces'),
                  icon: Icon(Icons.payments_rounded),
                ),
                ButtonSegment<String>(
                  value: 'mobile_money',
                  label: Text('Mobile'),
                  icon: Icon(Icons.phone_android_rounded),
                ),
                ButtonSegment<String>(
                  value: 'carte',
                  label: Text('Carte'),
                  icon: Icon(Icons.credit_card_rounded),
                ),
              ],
              selected: <String>{_modePaiement},
              onSelectionChanged: (Set<String> v) =>
                  setState(() => _modePaiement = v.first),
            ),
          ],
        ),
      ),
    );
  }

  Widget _barreTotale() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text('Total estimé', style: TextStyle(fontSize: 11.5)),
                  Text(
                    formatMontant(_totalEstime, devise: _config.devise),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _envoi ? null : _enregistrer,
              icon: _envoi
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_envoi ? 'Enregistrement…' : 'Enregistrer le dépôt'),
            ),
          ],
        ),
      ),
    );
  }
}
