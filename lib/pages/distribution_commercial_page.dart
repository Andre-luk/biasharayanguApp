// lib/pages/distribution_commercial_page.dart
//
// 🚚 MODULE 24 — ESPACE COMMERCIAL.
//
// Le commercial ne prend JAMAIS de marchandises librement : il demande une
// dotation, la production confirme, le stock autorise, puis il confirme sa
// réception. Il gère ensuite SES clients, SES ventes, SES retours et SES
// remises d'argent. Le gérant/propriétaire voit l'ensemble.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/services/distribution_facture_pdf.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/services/distribution_hors_ligne_service.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/distribution_widgets.dart';

class DistributionCommercialPage extends StatefulWidget {
  const DistributionCommercialPage({super.key, this.ongletInitial = 0});

  final int ongletInitial;

  @override
  State<DistributionCommercialPage> createState() =>
      _DistributionCommercialPageState();
}

class _DistributionCommercialPageState
    extends State<DistributionCommercialPage>
    with SingleTickerProviderStateMixin {
  final DistributionGestionService _service =
      DistributionGestionService.instance;
  late final TabController _tabs =
      TabController(length: 7, vsync: this, initialIndex: widget.ongletInitial);

  RoleDistribution _role = RoleDistribution.aucun;
  List<ProduitCommercial> _mesProduits = const <ProduitCommercial>[];
  List<ProduitCommercial> _catalogue = const <ProduitCommercial>[];
  List<ClientDistribution> _clients = const <ClientDistribution>[];
  List<DemandeCommercial> _demandes = const <DemandeCommercial>[];
  List<VenteDistribution> _ventes = const <VenteDistribution>[];
  List<RetourCommercial> _retours = const <RetourCommercial>[];
  List<RemiseArgent> _remises = const <RemiseArgent>[];
  List<CollaborateurDistribution> _commerciaux =
      const <CollaborateurDistribution>[];
  /// �️ MODULE 24 §9 — grille tarifaire (chargée avec les ventes).
  List<TarifBidon> _tarifs = const <TarifBidon>[];
  /// �🎁 MODULE 24 §10 — bonus et produits endommagés.
  List<BonusDommage> _bonus = const <BonusDommage>[];
  double _soldeARemettre = 0;

  bool _chargement = true;
  /// 📴 Vrai quand l'écran affiche les données mémorisées (aucun réseau).
  bool _modeHorsLigne = false;
  String? _erreur;

  bool get _estCommercial => _role == RoleDistribution.commercial;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    // 📴 MODULE 24 §12 — file hors ligne : on relit ce qui attend et on
    // rebranche l'affichage dès qu'une opération est ajoutée ou envoyée.
    DistributionHorsLigne.instance.enAttente
        .addListener(_onHorsLigneChange);
    DistributionHorsLigne.instance.initialiser();
    _charger();
  }

  void _onHorsLigneChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DistributionHorsLigne.instance.enAttente
        .removeListener(_onHorsLigneChange);
    _tabs.dispose();
    super.dispose();
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
      final RoleDistribution role = await _service.role();
      final List<ProduitCommercial> catalogue =
          await _service.catalogueProduits();
      final List<ClientDistribution> clients = await _service.clients();
      final List<DemandeCommercial> demandes =
          await _service.demandesCommerciales();
      final List<VenteDistribution> ventes = await _service.ventes();
      final List<RetourCommercial> retours = await _service.retours();
      final List<RemiseArgent> remises = await _service.remises();

      List<ProduitCommercial> mesProduits = _mesProduits;
      double solde = _soldeARemettre;
      List<CollaborateurDistribution> commerciaux = _commerciaux;

      // 🎁 MODULE 24 §10 — déclarations de bonus / dommages.
      List<BonusDommage> bonus = _bonus;
      try {
        bonus = await _service.bonus();
      } catch (e) {
        debugPrint('DistributionCommercialPage bonus (ignoré) : $e');
      }

      // 🏷️ MODULE 24 §9 — grille tarifaire.
      List<TarifBidon> tarifs = _tarifs;
      try {
        tarifs = await _service.tarifs();
      } catch (e) {
        debugPrint('DistributionCommercialPage tarifs (ignoré) : $e');
      }

      if (role == RoleDistribution.commercial) {
        mesProduits = await _service.mesProduits();
        solde = await _service.soldeARemettre();
      } else {
        try {
          commerciaux = (await _service.collaborateurs())
              .where((CollaborateurDistribution c) =>
                  c.role == RoleDistribution.commercial)
              .toList();
        } catch (e) {
          debugPrint('DistributionCommercialPage commerciaux (ignoré) : $e');
        }
      }

      if (!mounted) return;
      setState(() {
        _role = role;
        _catalogue = catalogue;
        _mesProduits = mesProduits;
        _clients = clients;
        _demandes = demandes;
        _ventes = ventes;
        _retours = retours;
        _remises = remises;
        _commerciaux = commerciaux;
        _bonus = bonus;
        _tarifs = tarifs;
        _soldeARemettre = solde;
        _chargement = false;
        _erreur = null;
      });

      // 📴 MODULE 24 §12 — cache local : le commercial garde ses produits,
      // ses clients et la grille tarifaire même sans réseau.
      DistributionHorsLigne.instance.mettreEnCache(
        produits: mesProduits,
        clients: clients,
        tarifs: tarifs,
      );
    } on DistributionGestionException catch (e) {
      if (!mounted) return;
      if (silencieux) {
        _message(e.message, erreur: true);
        return;
      }

      // 📴 MODULE 24 §12 — sans réseau, on affiche ce qui a été mémorisé
      // plutôt qu'un écran d'erreur : le commercial peut continuer.
      final List<ProduitCommercial> produitsCache =
          await DistributionHorsLigne.instance.produitsEnCache();
      final List<ClientDistribution> clientsCache =
          await DistributionHorsLigne.instance.clientsEnCache();
      if (!mounted) return;
      if (produitsCache.isNotEmpty) {
        setState(() {
          _mesProduits = produitsCache;
          _clients = clientsCache;
          _modeHorsLigne = true;
          _chargement = false;
          _erreur = null;
        });
        return;
      }

      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e, st) {
      debugPrint('DistributionCommercialPage : $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger l\'espace commercial.';
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

  // ---------------------------------------------------------------------------
  // DEMANDES DE DOTATION
  // ---------------------------------------------------------------------------

  Future<void> _creerDemande() async {
    if (_catalogue.isEmpty) {
      _message('Aucun produit fini au catalogue.', erreur: true);
      return;
    }

    String? commercialId;
    if (!_estCommercial) {
      if (_commerciaux.isEmpty) {
        _message('Créez d\'abord un collaborateur avec le rôle commercial.',
            erreur: true);
        return;
      }
      commercialId = await showDialog<String>(
        context: context,
        builder: (BuildContext ctx) => _ChoixCommercial(
          commerciaux: _commerciaux,
        ),
      );
      if (commercialId == null) return;
    }

    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Demande de produits',
      sousTitre: 'La production confirme, puis le stock autorise la sortie.',
      articles: _catalogue
          .map((ProduitCommercial p) => ArticleQuantite(
                id: p.produitId,
                nom: p.nom,
                unite: p.unite,
                valeurInitiale: 0,
                min: 0,
              ))
          .toList(),
      libelleValider: 'Envoyer',
    );
    if (quantites == null) return;

    final List<Map<String, dynamic>> lignes = quantites.entries
        .where((MapEntry<String, double> e) => e.value > 0)
        .map((MapEntry<String, double> e) => <String, dynamic>{
              'produit_id': e.key,
              'quantite': e.value,
            })
        .toList();
    if (lignes.isEmpty) {
      _message('Indiquez au moins un produit.', erreur: true);
      return;
    }

    try {
      final Map<String, dynamic> r = await _service.creerDemandeCommerciale(
        lignes,
        commercialId: commercialId,
      );
      _message('Demande ${r['numero']} envoyée à la production.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _confirmerProduction(DemandeCommercial d) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Quantités que la production peut fournir',
      articles: d.lignes
          .map((LigneDemandeCommercial l) => ArticleQuantite(
                id: l.produitId,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale: l.demandee,
                min: 0,
              ))
          .toList(),
      libelleValider: 'Confirmer',
    );
    if (quantites == null) return;

    try {
      await _service.confirmerDemandeCommerciale(
        d.id,
        lignes: quantites.entries
            .map((MapEntry<String, double> e) => <String, dynamic>{
                  'produit_id': e.key,
                  'quantite_confirmee': e.value,
                })
            .toList(),
      );
      _message('Demande confirmée : le stock doit maintenant autoriser.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _autoriserStock(DemandeCommercial d) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Quantités à sortir du stock',
      articles: d.lignes
          .map((LigneDemandeCommercial l) => ArticleQuantite(
                id: l.produitId,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale:
                    l.confirmee > 0 ? l.confirmee : l.demandee,
                min: 0,
              ))
          .toList(),
      libelleValider: 'Autoriser et sortir',
    );
    if (quantites == null) return;

    try {
      await _service.autoriserDemandeCommerciale(
        d.id,
        lignes: quantites.entries
            .map((MapEntry<String, double> e) => <String, dynamic>{
                  'produit_id': e.key,
                  'quantite_sortie': e.value,
                })
            .toList(),
      );
      _message('Marchandises attribuées : le commercial doit confirmer.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _refuserDemande(DemandeCommercial d, {required bool parStock}) async {
    final String? motif = await dialogueTexte(
      context,
      titre: parStock ? 'Refus du stock' : 'Refus de la production',
      label: 'Motif du refus',
    );
    if (motif == null) return;

    try {
      if (parStock) {
        await _service.autoriserDemandeCommerciale(d.id,
            refuser: true, motif: motif);
      } else {
        await _service.confirmerDemandeCommerciale(d.id,
            refuser: true, motif: motif);
      }
      _message('Demande refusée.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _receptionnerDotation(DemandeCommercial d) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Confirmer la réception',
      sousTitre: 'Déclarez ce que vous avez réellement reçu.',
      articles: d.lignes
          .map((LigneDemandeCommercial l) => ArticleQuantite(
                id: l.produitId,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale: l.sortie,
                min: 0,
                max: l.sortie,
                description: 'Attribué : ${quantiteDistribution(l.sortie)}',
              ))
          .toList(),
      libelleValider: 'Confirmer',
    );
    if (quantites == null) return;

    final bool ecart = d.lignes.any((LigneDemandeCommercial l) =>
        (quantites[l.produitId] ?? l.sortie) < l.sortie - 0.0001);

    String? motif;
    if (ecart) {
      motif = await dialogueTexte(
        context,
        titre: 'Marchandises manquantes',
        label: 'Expliquez la différence (une anomalie sera ouverte)',
      );
      if (motif == null) return;
    }

    try {
      await _service.receptionnerDemandeCommerciale(
        d.id,
        lignes: quantites.entries
            .map((MapEntry<String, double> e) => <String, dynamic>{
                  'produit_id': e.key,
                  'quantite_recue': e.value,
                })
            .toList(),
        motif: motif,
      );
      _message('Dotation confirmée.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // CLIENTS
  // ---------------------------------------------------------------------------

  Future<void> _enregistrerClient([ClientDistribution? client]) async {
    final _SaisieClient? saisie = await showDialog<_SaisieClient>(
      context: context,
      builder: (BuildContext _) => _DialogueClient(client: client),
    );
    if (saisie == null) return;

    try {
      await _service.enregistrerClient(
        id: client?.id,
        nom: saisie.nom,
        telephone: saisie.telephone,
        adresse: saisie.adresse,
        zone: saisie.zone,
        note: saisie.note,
      );
      _message(client == null ? 'Client ajouté.' : 'Client modifié.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // VENTE
  // ---------------------------------------------------------------------------

  Future<void> _vendre() async {
    if (_mesProduits.isEmpty) {
      _message('Vous n\'avez aucun produit en dotation.', erreur: true);
      return;
    }

    // 🏷️ MODULE 24 §9 — la grille tarifaire décide du prix affiché (le serveur
    // re-applique exactement la même règle à l'enregistrement).
    List<TarifBidon> tarifs = _tarifs;
    if (tarifs.isEmpty) {
      try {
        tarifs = await _service.tarifs();
      } catch (e) {
        debugPrint('DistributionCommercialPage tarifs (ignoré) : $e');
      }
    }
    if (!mounted) return;

    final _SaisieVente? saisie = await showDialog<_SaisieVente>(
      context: context,
      builder: (BuildContext _) => _DialogueVente(
        produits: _mesProduits,
        clients: _clients,
        tarifs: tarifs,
      ),
    );
    if (saisie == null) return;

    try {
      final FactureDistribution facture = await _service.enregistrerVente(
        clientId: saisie.clientId,
        lignes: saisie.lignes,
        montantPaye: saisie.montantPaye,
        mode: saisie.mode,
        typeOperation: saisie.typeOperation,
      );
      _message('Vente ${facture.numero} enregistrée. '
          'L\'argent reste à remettre au comptable.');
      _montrerFacture(facture);
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      // 📴 RÉSEAU COUPÉ ? On propose d'enregistrer la vente hors ligne.
      final bool garder = await _proposerHorsLigne(
        titre: 'Vente non envoyée',
        message: '${e.message}\n\nSi vous n\'avez pas de réseau, la vente '
            'peut être enregistrée sur le téléphone et envoyée plus tard.',
      );
      if (!garder) return;

      String? nomClient;
      for (final ClientDistribution c in _clients) {
        if (c.id == saisie.clientId) nomClient = c.nom;
      }
      await DistributionHorsLigne.instance.ajouterVente(
        lignes: saisie.lignes,
        clientId: saisie.clientId,
        nomClient: nomClient,
        montantPaye: saisie.montantPaye,
        mode: saisie.mode,
        typeOperation: saisie.typeOperation,
      );
      _message('Vente enregistrée hors ligne : elle partira au retour du '
          'réseau.');
    }
  }

  /// Demande confirmation avant de garder une opération sur le téléphone.
  Future<bool> _proposerHorsLigne({
    required String titre,
    required String message,
  }) async {
    final bool? garder = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(titre),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Non, réessayer plus tard'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.cloud_off_rounded, size: 18),
            label: const Text('Enregistrer hors ligne'),
          ),
        ],
      ),
    );
    return garder == true;
  }

  Future<void> _voirFacture(VenteDistribution vente) async {
    try {
      final FactureDistribution? facture = await _service.facture(vente.id);
      if (facture != null) _montrerFacture(facture);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  void _montrerFacture(FactureDistribution facture) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('Facture ${facture.numero}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(facture.entreprise,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                if (facture.entrepriseAdresse.isNotEmpty)
                  Text(facture.entrepriseAdresse),
                if (facture.entrepriseTelephone.isNotEmpty)
                  Text('Tél. ${facture.entrepriseTelephone}'),
                const Divider(height: 20),
                ligneDistribution('Client', facture.client),
                if (facture.clientTelephone.isNotEmpty)
                  ligneDistribution('Téléphone', facture.clientTelephone),
                ligneDistribution('Commercial', facture.commercial),
                ligneDistribution('Paiement', facture.modePaiement),
                const Divider(height: 20),
                for (final LigneVenteDistribution l in facture.lignes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ligneDistribution(
                      '${l.nom} × ${quantiteDistribution(l.quantite)}',
                      montantDistribution(l.total),
                    ),
                  ),
                const Divider(height: 20),
                ligneDistribution('Total', montantDistribution(facture.total),
                    gras: true),
                ligneDistribution('Payé',
                    montantDistribution(facture.montantPaye)),
                if (facture.credit > 0.009)
                  ligneDistribution('Crédit',
                      montantDistribution(facture.credit),
                      couleur: Colors.red.shade700, gras: true),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                await DistributionFacturePdf.imprimer(facture);
              } catch (e) {
                _message('Impression impossible : $e', erreur: true);
              }
            },
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Imprimer'),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                await DistributionFacturePdf.partager(facture);
              } catch (e) {
                _message('Partage impossible : $e', erreur: true);
              }
            },
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Partager'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // RETOURS
  // ---------------------------------------------------------------------------

  Future<void> _declarerRetour() async {
    if (_mesProduits.isEmpty) {
      _message('Aucun produit à retourner.', erreur: true);
      return;
    }

    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Déclarer un retour',
      sousTitre: 'Le stock devra compter les produits retournés.',
      articles: _mesProduits
          .map((ProduitCommercial p) => ArticleQuantite(
                id: p.produitId,
                nom: p.nom,
                unite: p.unite,
                valeurInitiale: 0,
                min: 0,
                max: p.quantite,
                description: 'En votre possession : '
                    '${quantiteDistribution(p.quantite)}',
              ))
          .toList(),
      libelleValider: 'Déclarer',
    );
    if (quantites == null) return;

    final List<Map<String, dynamic>> lignes = quantites.entries
        .where((MapEntry<String, double> e) => e.value > 0)
        .map((MapEntry<String, double> e) => <String, dynamic>{
              'produit_id': e.key,
              'quantite': e.value,
            })
        .toList();
    if (lignes.isEmpty) {
      _message('Indiquez au moins un produit.', erreur: true);
      return;
    }

    try {
      final Map<String, dynamic> r =
          await _service.declarerRetour(lignes);
      _message('Retour ${r['numero']} déclaré : attente du stock.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _compterRetour(RetourCommercial r) async {
    final Map<String, double>? quantites = await dialogueQuantites(
      context,
      titre: 'Compter les produits retournés',
      articles: r.lignes
          .map((LigneRetour l) => ArticleQuantite(
                id: l.produitId,
                nom: l.nom,
                unite: l.unite,
                valeurInitiale: l.declaree,
                min: 0,
                max: l.declaree,
              ))
          .toList(),
      libelleValider: 'Confirmer',
    );
    if (quantites == null) return;

    final bool ecart = r.lignes.any((LigneRetour l) =>
        (quantites[l.produitId] ?? l.declaree) < l.declaree - 0.0001);

    String? motif;
    if (ecart) {
      motif = await dialogueTexte(
        context,
        titre: 'Produits manquants',
        label: 'Expliquez la différence (une anomalie sera ouverte)',
      );
      if (motif == null) return;
    }

    try {
      await _service.receptionnerRetour(
        r.id,
        lignes: quantites.entries
            .map((MapEntry<String, double> e) => <String, dynamic>{
                  'produit_id': e.key,
                  'quantite_recue': e.value,
                })
            .toList(),
        motif: motif,
      );
      _message('Retour réceptionné : les produits sont rentrés au stock.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // REMISE D'ARGENT
  // ---------------------------------------------------------------------------

  Future<void> _declarerRemise() async {
    if (_soldeARemettre <= 0.009) {
      _message('Vous n\'avez aucun montant à remettre.');
      return;
    }

    final TextEditingController montant = TextEditingController(
        text: _soldeARemettre.toStringAsFixed(0));
    String mode = 'especes';

    final bool? envoye = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) => AlertDialog(
          title: const Text('Remettre l\'argent'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ligneDistribution('Montant à remettre',
                  montantDistribution(_soldeARemettre),
                  gras: true),
              const SizedBox(height: 12),
              TextField(
                controller: montant,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Montant remis'),
              ),
              const SizedBox(height: 10),
              AppDropdownField<String>(
                label: 'Moyen de paiement',
                value: mode,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: 'especes', child: Text('Espèces')),
                  DropdownMenuItem<String>(
                      value: 'mobile_money', child: Text('Mobile Money')),
                  DropdownMenuItem<String>(
                      value: 'virement', child: Text('Virement')),
                  DropdownMenuItem<String>(
                      value: 'autre', child: Text('Autre')),
                ],
                onChanged: (String? v) => setState(() => mode = v ?? 'especes'),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Déclarer'),
            ),
          ],
        ),
      ),
    );
    if (envoye != true) {
      montant.dispose();
      return;
    }

    final double valeur =
        double.tryParse(montant.text.replaceAll(' ', '').replaceAll(',', '.')) ??
            0;
    montant.dispose();

    try {
      await _service.declarerRemise(montant: valeur, mode: mode);
      _message('Remise déclarée : le comptable doit la réceptionner.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final List<String> onglets = <String>[
      _estCommercial ? 'Mes produits' : 'Demandes',
      'Clients',
      _estCommercial ? 'Vendre' : 'Ventes',
      'Retours',
      'Remises',
      _estCommercial ? 'Demandes' : 'Commerciaux',
      'Bonus',
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_estCommercial ? 'Mon espace commercial' : 'Commerciaux'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabs: onglets.map((String t) => Tab(text: t)).toList(),
        ),
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_erreur!, textAlign: TextAlign.center),
                  ),
                )
              : Column(
                  children: <Widget>[
                    if (_modeHorsLigne ||
                        DistributionHorsLigne.instance.enAttente.value > 0)
                      _bandeauHorsLigne(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        children: <Widget>[
                          _estCommercial ? _vueMesProduits() : _vueDemandes(),
                          _vueClients(),
                          _estCommercial ? _vueVendre() : _vueVentes(),
                          _vueRetours(),
                          _vueRemises(),
                          _estCommercial ? _vueDemandes() : _vueCommerciaux(),
                          _vueBonus(),
                        ],
                      ),
                    ),
                  ],
                ),
      floatingActionButton: _fab(),
    );
  }

  Widget? _fab() {
    switch (_tabs.index) {
      case 0:
        if (_estCommercial) {
          return FloatingActionButton.extended(
            onPressed: _creerDemande,
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('Demander des produits'),
          );
        }
        return FloatingActionButton.extended(
          onPressed: _creerDemande,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Demande pour un commercial'),
        );
      case 2:
        if (_estCommercial) {
          return FloatingActionButton.extended(
            onPressed: _vendre,
            icon: const Icon(Icons.point_of_sale_rounded),
            label: const Text('Vendre'),
          );
        }
        return null;
      case 3:
        if (_estCommercial) {
          return FloatingActionButton.extended(
            onPressed: _declarerRetour,
            icon: const Icon(Icons.keyboard_return_rounded),
            label: const Text('Déclarer un retour'),
          );
        }
        return null;
      case 4:
        if (_estCommercial) {
          return FloatingActionButton.extended(
            onPressed: _declarerRemise,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Remettre l\'argent'),
          );
        }
        return null;
      case 6:
        // 🎁 MODULE 24 §10 — déclarer un bonus / un produit endommagé.
        return FloatingActionButton.extended(
          onPressed: _declarerBonus,
          icon: const Icon(Icons.card_giftcard_rounded),
          label: const Text('Déclarer'),
        );
      default:
        return null;
    }
  }

  // ---------------------------------------------------------------------------
  // VUES
  // ---------------------------------------------------------------------------

  Widget _vueMesProduits() {
    if (_mesProduits.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucun produit en dotation pour le moment.'),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      itemCount: _mesProduits.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int i) {
        final ProduitCommercial p = _mesProduits[i];
        return Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.4),
          child: ListTile(
            title: Text(p.nom,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Prix autorisé : ${montantDistribution(p.prixVente)}'),
            trailing: Text(
              quantiteDistribution(p.quantite, unite: p.unite),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }

  Widget _vueDemandes() {
    if (_demandes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune demande de dotation.'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _demandes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          final DemandeCommercial d = _demandes[i];
          return Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('${d.numero} · ${d.commercial}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      PuceDistribution(
                        libelle: d.libelleStatut,
                        couleur: d.statut.contains('refusee') ||
                                d.enLitige
                            ? Colors.red.shade700
                            : d.statut == 'recue'
                                ? Colors.green.shade700
                                : Colors.orange.shade800,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final LigneDemandeCommercial l in d.lignes)
                    ligneDistribution(
                      l.nom,
                      'demandé ${quantiteDistribution(l.demandee)}'
                          '${l.confirmee > 0 ? ' · confirmé ${quantiteDistribution(l.confirmee)}' : ''}'
                          '${l.sortie > 0 ? ' · sorti ${quantiteDistribution(l.sortie)}' : ''}'
                          '${l.recue > 0 ? ' · reçu ${quantiteDistribution(l.recue)}' : ''}',
                    ),
                  if (d.motif.isNotEmpty)
                    Text('Motif : ${d.motif}',
                        style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    children: <Widget>[
                      if (d.attenteProduction && _role.peutProduire) ...<Widget>[
                        OutlinedButton(
                          onPressed: () =>
                              _refuserDemande(d, parStock: false),
                          child: const Text('Refuser'),
                        ),
                        FilledButton(
                          onPressed: () => _confirmerProduction(d),
                          child: const Text('Confirmer'),
                        ),
                      ],
                      if (d.attenteStock && _role.peutGererStock) ...<Widget>[
                        OutlinedButton(
                          onPressed: () =>
                              _refuserDemande(d, parStock: true),
                          child: const Text('Refuser'),
                        ),
                        FilledButton(
                          onPressed: () => _autoriserStock(d),
                          child: const Text('Autoriser'),
                        ),
                      ],
                      if (d.attenteCommercial && _estCommercial)
                        FilledButton(
                          onPressed: () => _receptionnerDotation(d),
                          child: const Text('Confirmer la réception'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _vueClients() {
    if (_clients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Text('Aucun client enregistré.'),
              const SizedBox(height: 12),
              if (_estCommercial)
                FilledButton.icon(
                  onPressed: () => _enregistrerClient(),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: const Text('Créer mon premier client'),
                ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _clients.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int i) {
          final ClientDistribution c = _clients[i];
          return Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(c.nom,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(<String>[
                if (c.telephone.isNotEmpty) c.telephone,
                if (c.localisation.isNotEmpty) c.localisation,
                if (!_estCommercial) c.commercial,
              ].join(' · ')),
              trailing: _estCommercial
                  ? IconButton(
                      tooltip: 'Modifier (jamais supprimer)',
                      onPressed: () => _enregistrerClient(c),
                      icon: const Icon(Icons.edit_outlined),
                    )
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _vueVendre() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SectionDistribution(
          titre: 'Ma dotation',
          sousTitre: 'Les prix affichés sont les prix autorisés par l\'entreprise.',
          child: Column(
            children: <Widget>[
              for (final ProduitCommercial p in _mesProduits)
                ligneDistribution(p.nom,
                    '${quantiteDistribution(p.quantite, unite: p.unite)} · ${montantDistribution(p.prixVente)}'),
            ],
          ),
        ),
        Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: <Widget>[
                const Icon(Icons.point_of_sale_rounded, size: 40),
                const SizedBox(height: 8),
                const Text('Enregistrez une vente et générez sa facture.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _vendre,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Nouvelle vente'),
                ),
                const SizedBox(height: 8),
                Text(
                  'L\'argent encaissé ne va pas directement en caisse : '
                  'vous le remettrez au comptable qui le confirmera, puis le '
                  'gérant validera l\'entrée en caisse.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _vueVentes() {
    if (_ventes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune vente enregistrée.'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _ventes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int i) {
          final VenteDistribution v = _ventes[i];
          return Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: ListTile(
              title: Text('${v.numero} · ${v.client}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(<String>[
                v.commercial,
                if (v.date != null) _date(v.date!),
                if (v.aCredit)
                  'crédit ${montantDistribution(v.credit)}',
              ].join(' · ')),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(montantDistribution(v.total),
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(v.modePaiement,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              onTap: () => _voirFacture(v),
            ),
          );
        },
      ),
    );
  }

  Widget _vueRetours() {
    if (_retours.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucun retour de marchandises.'),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _retours.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int i) {
          final RetourCommercial r = _retours[i];
          return Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text('${r.numero} · ${r.commercial}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      PuceDistribution(
                        libelle: r.libelleStatut,
                        couleur: r.enAttente
                            ? Colors.orange.shade800
                            : r.statut == 'en_litige'
                                ? Colors.red.shade700
                                : Colors.green.shade700,
                      ),
                    ],
                  ),
                  for (final LigneRetour l in r.lignes)
                    ligneDistribution(
                      l.nom,
                      'déclaré ${quantiteDistribution(l.declaree)}'
                          '${l.recue > 0 ? ' · compté ${quantiteDistribution(l.recue)}' : ''}',
                    ),
                  if (r.enAttente && _role.peutGererStock) ...<Widget>[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: () => _compterRetour(r),
                        child: const Text('Compter et recevoir'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _vueRemises() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: <Widget>[
        if (_estCommercial)
          Card(
            elevation: 0,
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: <Widget>[
                  Text('Argent à remettre',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Text(
                    montantDistribution(_soldeARemettre),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _declarerRemise,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Déclarer une remise'),
                  ),
                ],
              ),
            ),
          ),
        if (_remises.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Aucune remise d\'argent.', textAlign: TextAlign.center),
          )
        else
          for (final RemiseArgent r in _remises)
            Card(
              elevation: 0,
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.4),
              child: ListTile(
                title: Text('${r.numero} · ${r.commercial}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(r.libelleStatut),
                trailing: Text(
                  montantDistribution(r.montantDeclare),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 📴 MODULE 24 §12 — BANDEAU HORS LIGNE
  // ---------------------------------------------------------------------------

  Widget _bandeauHorsLigne() {
    final ThemeData theme = Theme.of(context);
    final int nb = DistributionHorsLigne.instance.enAttente.value;
    final bool envoi = DistributionHorsLigne.instance.synchronisation.value;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.orange.withValues(alpha: 0.14),
      child: Row(
        children: <Widget>[
          Icon(Icons.cloud_off_rounded,
              size: 20, color: Colors.orange.shade900),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nb > 0
                  ? '$nb opération(s) en attente d\'envoi'
                  : 'Hors ligne : données mémorisées sur ce téléphone.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton.icon(
            onPressed: envoi
                ? null
                : () async {
                    if (_modeHorsLigne) {
                      setState(() => _modeHorsLigne = false);
                      await _charger();
                      return;
                    }
                    await _synchroniser();
                  },
            icon: envoi
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_modeHorsLigne
                    ? Icons.refresh_rounded
                    : Icons.sync_rounded,
                    size: 18),
            label: Text(envoi
                ? 'Envoi…'
                : (_modeHorsLigne ? 'Réessayer' : 'Synchroniser')),
          ),
        ],
      ),
    );
  }

  Future<void> _synchroniser() async {
    final ResultatSynchronisation r =
        await DistributionHorsLigne.instance.synchroniser();
    _message(r.message, erreur: r.conflits > 0 || r.reseauIndisponible);
    if (r.envoyees > 0) _charger(silencieux: true);
  }

  // ---------------------------------------------------------------------------
  // 🎁 MODULE 24 §10 — BONUS ET PRODUITS ENDOMMAGÉS
  // ---------------------------------------------------------------------------

  Widget _vueBonus() {
    final ThemeData theme = Theme.of(context);

    if (_bonus.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.card_giftcard_rounded,
                  size: 48, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 10),
              const Text(
                'Aucun bonus ni produit endommagé déclaré.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Un bonus offert ou un produit cassé se déclare ici : le stock '
                'ne bouge qu\'après validation du gérant.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        itemCount: _bonus.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (BuildContext context, int i) {
          final BonusDommage b = _bonus[i];
          final bool peutValider = _role.estDirection && b.enAttente;

          return Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${b.nature.libelle} — ${b.nomProduit}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      PuceDistribution(
                        libelle: b.libelleStatut,
                        couleur: b.valide
                            ? Colors.green.shade700
                            : b.enAttente
                                ? Colors.orange.shade800
                                : Colors.red.shade700,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ligneDistribution(
                    'Quantité',
                    quantiteDistribution(b.quantite),
                  ),
                  ligneDistribution('Valeur', montantDistribution(b.valeur)),
                  if (b.commercial.isNotEmpty)
                    ligneDistribution('Commercial', b.commercial),
                  ligneDistribution('Motif', b.motif),
                  if (b.justificatif.isNotEmpty)
                    ligneDistribution('Justificatif', b.justificatif),
                  if (b.motifRefus.isNotEmpty)
                    ligneDistribution('Motif du refus', b.motifRefus),
                  if (peutValider) ...<Widget>[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => _validerBonus(b, false),
                          icon: const Icon(Icons.block_rounded, size: 18),
                          label: const Text('Refuser'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _validerBonus(b, true),
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: const Text('Valider'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _declarerBonus() async {
    final List<ProduitCommercial> produits =
        _estCommercial ? _mesProduits : _catalogue;
    if (produits.isEmpty) {
      _message('Aucun produit disponible pour une déclaration.', erreur: true);
      return;
    }

    final _SaisieBonus? saisie = await showDialog<_SaisieBonus>(
      context: context,
      builder: (BuildContext _) => _DialogueBonus(produits: produits),
    );
    if (saisie == null) return;

    try {
      await _service.declarerBonus(
        produitId: saisie.produitId,
        nature: saisie.nature,
        quantite: saisie.quantite,
        motif: saisie.motif,
        justificatif: saisie.justificatif,
      );
      _message('Déclaration enregistrée : elle attend la validation du gérant.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Future<void> _validerBonus(BonusDommage b, bool valider) async {
    String? motif;
    if (!valider) {
      motif = await dialogueTexte(
        context,
        titre: 'Refuser la déclaration',
        label: 'Motif du refus (obligatoire)',
      );
      if (motif == null) return;
      if (motif.trim().length < 3) {
        _message('Indiquez un motif de refus (3 caractères minimum).',
            erreur: true);
        return;
      }
    }

    try {
      await _service.validerBonus(b.id, valider: valider, motif: motif);
      _message(valider
          ? 'Déclaration validée : le stock du commercial a été ajusté.'
          : 'Déclaration refusée.');
      _charger(silencieux: true);
    } on DistributionGestionException catch (e) {
      _message(e.message, erreur: true);
    }
  }

  Widget _vueCommerciaux() {
    if (_ventes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Aucune vente à analyser.'),
        ),
      );
    }

    final Map<String, double> totaux = <String, double>{};
    final Map<String, int> nombre = <String, int>{};
    for (final VenteDistribution v in _ventes) {
      final String cle = v.commercial.isEmpty ? 'Commercial' : v.commercial;
      totaux[cle] = (totaux[cle] ?? 0) + v.total;
      nombre[cle] = (nombre[cle] ?? 0) + 1;
    }

    final List<String> cles = totaux.keys.toList()
      ..sort((String a, String b) => (totaux[b] ?? 0).compareTo(totaux[a] ?? 0));

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: cles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int i) {
        final String nom = cles[i];
        return Card(
          elevation: 0,
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.4),
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(nom,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${nombre[nom] ?? 0} vente(s)'),
            trailing: Text(
              montantDistribution(totaux[nom] ?? 0),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        );
      },
    );
  }

  static String _date(DateTime date) {
    final DateTime d = date.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }
}

// ---------------------------------------------------------------------------
// DIALOGUES
// ---------------------------------------------------------------------------

class _ChoixCommercial extends StatelessWidget {
  const _ChoixCommercial({required this.commerciaux});

  final List<CollaborateurDistribution> commerciaux;

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: const Text('Pour quel commercial ?'),
      children: <Widget>[
        for (final CollaborateurDistribution c in commerciaux)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(c.id),
            child: Text(c.nomComplet.isEmpty ? c.email : c.nomComplet),
          ),
      ],
    );
  }
}

class _SaisieClient {
  const _SaisieClient(
      this.nom, this.telephone, this.adresse, this.zone, this.note);

  final String nom;
  final String telephone;
  final String adresse;
  final String zone;
  final String note;
}

class _DialogueClient extends StatefulWidget {
  const _DialogueClient({this.client});

  final ClientDistribution? client;

  @override
  State<_DialogueClient> createState() => _DialogueClientState();
}

class _DialogueClientState extends State<_DialogueClient> {
  late final TextEditingController _nom =
      TextEditingController(text: widget.client?.nom ?? '');
  late final TextEditingController _telephone =
      TextEditingController(text: widget.client?.telephone ?? '');
  late final TextEditingController _adresse =
      TextEditingController(text: widget.client?.adresse ?? '');
  late final TextEditingController _zone =
      TextEditingController(text: widget.client?.zone ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.client?.note ?? '');

  @override
  void dispose() {
    _nom.dispose();
    _telephone.dispose();
    _adresse.dispose();
    _zone.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.client == null ? 'Nouveau client' : 'Modifier le client'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _nom,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nom du client'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _telephone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Téléphone'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _adresse,
              decoration: const InputDecoration(labelText: 'Adresse'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _zone,
              decoration: const InputDecoration(labelText: 'Quartier / zone'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (facultatif)'),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            if (_nom.text.trim().isEmpty) return;
            Navigator.of(context).pop(_SaisieClient(
              _nom.text.trim(),
              _telephone.text.trim(),
              _adresse.text.trim(),
              _zone.text.trim(),
              _note.text.trim(),
            ));
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _SaisieVente {
  const _SaisieVente(this.clientId, this.lignes, this.montantPaye, this.mode,
      this.typeOperation);

  final String? clientId;
  final List<Map<String, dynamic>> lignes;
  final double montantPaye;
  final String mode;
  final TypeOperationTarif typeOperation;
}

class _DialogueVente extends StatefulWidget {
  const _DialogueVente({
    required this.produits,
    required this.clients,
    this.tarifs = const <TarifBidon>[],
  });

  final List<ProduitCommercial> produits;
  final List<ClientDistribution> clients;

  /// 🏷️ MODULE 24 §9 — grille tarifaire (peut être vide).
  final List<TarifBidon> tarifs;

  @override
  State<_DialogueVente> createState() => _DialogueVenteState();
}

class _DialogueVenteState extends State<_DialogueVente> {
  String? _clientId;
  String _mode = 'especes';
  final Map<String, TextEditingController> _quantites =
      <String, TextEditingController>{};
  final TextEditingController _paye = TextEditingController();

  @override
  void initState() {
    super.initState();
    for (final ProduitCommercial p in widget.produits) {
      _quantites[p.produitId] = TextEditingController(text: '0');
    }
  }

  @override
  void dispose() {
    for (final TextEditingController c in _quantites.values) {
      c.dispose();
    }
    _paye.dispose();
    super.dispose();
  }

  double _lire(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;

  TypeOperationTarif _type = TypeOperationTarif.standard;

  /// Prix effectif d'un produit : grille (type choisi) puis grille `standard`,
  /// sinon prix catalogue — exactement la règle appliquée par le serveur.
  double _prixDe(ProduitCommercial p) {
    double? trouve;
    for (final TarifBidon t in widget.tarifs) {
      if (t.produitId == p.produitId &&
          t.type == _type &&
          t.actif &&
          t.prix > 0) {
        trouve = t.prix;
        break;
      }
    }
    if (trouve == null && _type != TypeOperationTarif.standard) {
      for (final TarifBidon t in widget.tarifs) {
        if (t.produitId == p.produitId &&
            t.type == TypeOperationTarif.standard &&
            t.actif &&
            t.prix > 0) {
          trouve = t.prix;
          break;
        }
      }
    }
    return trouve ?? p.prixVente;
  }

  double get _total {
    double total = 0;
    for (final ProduitCommercial p in widget.produits) {
      total += _lire(_quantites[p.produitId]!) * _prixDe(p);
    }
    return total;
  }

  List<Map<String, dynamic>> get _lignes {
    final List<Map<String, dynamic>> lignes = <Map<String, dynamic>>[];
    for (final ProduitCommercial p in widget.produits) {
      final double q = _lire(_quantites[p.produitId]!);
      if (q > 0) {
        lignes.add(<String, dynamic>{
          'produit_id': p.produitId,
          'quantite': q,
          // Prix gardé pour le rejeu hors ligne (le serveur le recalcule).
          'prix_unitaire': _prixDe(p),
        });
      }
    }
    return lignes;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle vente'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              AppDropdownField<String?>(
                label: 'Client',
                value: _clientId,
                items: <DropdownMenuItem<String?>>[
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Client comptant'),
                  ),
                  ...widget.clients.map((ClientDistribution c) =>
                      DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.nom),
                      )),
                ],
                onChanged: (String? v) => setState(() => _clientId = v),
              ),
              const SizedBox(height: 12),
              // 🏷️ MODULE 24 §9 — type d'opération : bidon neuf, échange,
              // remplissage… Le prix affiché suit la grille configurée.
              AppDropdownField<TypeOperationTarif>(
                label: 'Type d\'opération',
                value: _type,
                prefixIcon: Icons.local_offer_outlined,
                items: TypeOperationTarif.values
                    .map((TypeOperationTarif t) =>
                        DropdownMenuItem<TypeOperationTarif>(
                          value: t,
                          child: Text(t.libelle),
                        ))
                    .toList(growable: false),
                onChanged: (TypeOperationTarif? v) {
                  if (v != null) setState(() => _type = v);
                },
              ),
              const SizedBox(height: 12),
              for (final ProduitCommercial p in widget.produits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(p.nom,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            Text(
                              '${montantDistribution(_prixDe(p))} · '
                              '${quantiteDistribution(p.quantite)} en stock',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: _quantites[p.produitId],
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[0-9., ]')),
                          ],
                          textAlign: TextAlign.right,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            isDense: true,
                            suffixText: p.unite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              Row(
                children: <Widget>[
                  const Expanded(
                      child: Text('Total',
                          style: TextStyle(fontWeight: FontWeight.w800))),
                  Text(montantDistribution(_total),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _paye,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Montant payé (laisser vide = total)',
                ),
              ),
              const SizedBox(height: 10),
              AppDropdownField<String>(
                label: 'Mode de paiement',
                value: _mode,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: 'especes', child: Text('Espèces')),
                  DropdownMenuItem<String>(
                      value: 'mobile_money', child: Text('Mobile Money')),
                  DropdownMenuItem<String>(
                      value: 'carte', child: Text('Carte')),
                  DropdownMenuItem<String>(
                      value: 'virement', child: Text('Virement')),
                  DropdownMenuItem<String>(
                      value: 'credit', child: Text('Crédit (non payé)')),
                ],
                onChanged: (String? v) => setState(() => _mode = v ?? 'especes'),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final List<Map<String, dynamic>> lignes = _lignes;
            if (lignes.isEmpty) return;
            final double total = _total;
            final double paye =
                _paye.text.trim().isEmpty ? total : _lire(_paye);
            if (paye < 0 || paye > total + 0.009) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Le montant payé dépasse le total.')));
              return;
            }
            Navigator.of(context).pop(
                _SaisieVente(_clientId, lignes, paye, _mode, _type));
          },
          child: const Text('Enregistrer la vente'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 🎁 DÉCLARATION D'UN BONUS / PRODUIT ENDOMMAGÉ (module 24 §10)
// ---------------------------------------------------------------------------

class _SaisieBonus {
  const _SaisieBonus({
    required this.produitId,
    required this.nature,
    required this.quantite,
    required this.motif,
    this.justificatif,
  });

  final String produitId;
  final NatureBonus nature;
  final double quantite;
  final String motif;
  final String? justificatif;
}

class _DialogueBonus extends StatefulWidget {
  const _DialogueBonus({required this.produits});

  final List<ProduitCommercial> produits;

  @override
  State<_DialogueBonus> createState() => _DialogueBonusState();
}

class _DialogueBonusState extends State<_DialogueBonus> {
  final TextEditingController _quantite = TextEditingController(text: '1');
  final TextEditingController _motif = TextEditingController();
  final TextEditingController _justificatif = TextEditingController();

  String? _produitId;
  NatureBonus _nature = NatureBonus.bonus;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _produitId = widget.produits.first.produitId;
  }

  @override
  void dispose() {
    _quantite.dispose();
    _motif.dispose();
    _justificatif.dispose();
    super.dispose();
  }

  double get _qte =>
      double.tryParse(_quantite.text.replaceAll(' ', '').replaceAll(',', '.')) ??
      0;

  void _valider() {
    if (_qte <= 0) {
      setState(() => _erreur = 'Saisissez une quantité supérieure à zéro.');
      return;
    }
    if (_motif.text.trim().length < 3) {
      setState(() => _erreur = 'Indiquez le motif (3 caractères minimum).');
      return;
    }
    Navigator.of(context).pop(
      _SaisieBonus(
        produitId: _produitId!,
        nature: _nature,
        quantite: _qte,
        motif: _motif.text.trim(),
        justificatif: _justificatif.text.trim().isEmpty
            ? null
            : _justificatif.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bonus / produit endommagé'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AppDropdownField<String>(
                label: 'Produit',
                value: _produitId,
                items: widget.produits
                    .map((ProduitCommercial p) => DropdownMenuItem<String>(
                          value: p.produitId,
                          child: Text(p.nom),
                        ))
                    .toList(growable: false),
                onChanged: (String? v) {
                  if (v != null) setState(() => _produitId = v);
                },
              ),
              const SizedBox(height: 12),
              AppDropdownField<NatureBonus>(
                label: 'Nature',
                value: _nature,
                items: NatureBonus.values
                    .map((NatureBonus n) => DropdownMenuItem<NatureBonus>(
                          value: n,
                          child: Text(n.libelle),
                        ))
                    .toList(growable: false),
                onChanged: (NatureBonus? v) {
                  if (v != null) setState(() => _nature = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _quantite,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantité *'),
                onChanged: (_) => setState(() => _erreur = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _motif,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Motif *',
                  hintText: 'Ex. : bidon crevé au transport',
                ),
                onChanged: (_) => setState(() => _erreur = null),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _justificatif,
                decoration: const InputDecoration(
                  labelText: 'Justificatif (facultatif)',
                  hintText: 'Référence, nom du témoin, photo…',
                ),
              ),
              if (_erreur != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(
                  _erreur!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                'Le stock du commercial n\'est retiré qu\'après validation du '
                'gérant : la déclaration seule ne modifie rien.',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _valider, child: const Text('Déclarer')),
      ],
    );
  }
}
