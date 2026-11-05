// lib/pages/new_sale_page.dart
import 'dart:async';
import 'package:biashara_yangu/utils/image_locale.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/client.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/dette.dart';
import 'package:biashara_yangu/models/ligne_panier.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/models/vente.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/invoice_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/sync_service.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/donnees_service.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/l10n/app_localizations.dart';
// 🪙 MODULE 18 — montants formatés dans la devise de l'entreprise.
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/widgets/banniere_abonnement.dart';
import 'package:biashara_yangu/widgets/choix_format_vente.dart';
import '../ui/widgets/primary_loader.dart';

class NewSalePage extends StatefulWidget {
  const NewSalePage({super.key});

  @override
  State<NewSalePage> createState() => _NewSalePageState();
}

class _NewSalePageState extends State<NewSalePage> {
  final StreamController<List<Produit>> _productsController =
  StreamController<List<Produit>>.broadcast();

  RealtimeChannel? _productsChannel;

  /// 🔔 MODULE 23 — regroupe les salves d'évènements (temps réel + écritures
  /// locales) pour ne recharger qu'une fois.
  Timer? _antiRebond;

  List<Produit> produits = [];
  List<Client> clients = [];
  Client? selectedClient;
  bool isModeDette = false;

  /// 🔳 MODULE 7 — panier partagé de la boutique : la caisse et le scanner
  /// vendeur y ajoutent leurs lignes (articles et conditionnements).
  final PanierService _panier = PanierService.instance;

  String modePaiement = 'cash';
  bool _loading = true;
  String _searchQuery = '';

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();

  final Map<String, IconData> _paymentModes = {
    'cash': Icons.money,
    'carte': Icons.credit_card,
    'm-pesa': Icons.phone_android,
  };

  String? _currentUserId;
  String? _effectiveOwnerId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    // Le scanner vendeur remplit le même panier : on se rafraîchit à chaque
    // modification (badge, total, quantités…).
    _panier.revision.addListener(_onPanierModifie);
    // 🔔 MODULE 23 — un article créé/modifié ailleurs (autre téléphone, web)
    // doit apparaître ICI sans quitter l'écran.
    DonneesService.instance.revision.addListener(_planifierRechargement);
    _initializeData();
  }

  @override
  void dispose() {
    _panier.revision.removeListener(_onPanierModifie);
    DonneesService.instance.revision.removeListener(_planifierRechargement);
    _antiRebond?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _quantityController.dispose();

    if (_productsChannel != null) {
      Supabase.instance.client.removeChannel(_productsChannel!);
    }

    _productsController.close();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  /// 🔳 MODULE 7 — le panier partagé a changé (scan, retrait, vidage…).
  void _onPanierModifie() {
    if (mounted) setState(() {});
  }

  void _startRealtimeListener() {
    final String ownerId = _effectiveOwnerId ?? '';
    if (ownerId.isEmpty || _productsChannel != null) return;

    final supabase = Supabase.instance.client;

    _productsChannel = supabase
        .channel('new-sale-products-$ownerId')
        .onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'produits',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'owner_id',
        value: ownerId,
      ),
      callback: (payload) {
        // 🔔 MODULE 23 — l'évènement vient du serveur : on resynchronise la
        // copie locale avant de relire (c'était le chaînon manquant :
        // l'écoute existait mais relisait un cache SQLite jamais mis à jour).
        _planifierRechargement();
      },
    )
        .subscribe();
  }

  /// Recharge la caisse après une salve d'évènements (600 ms).
  void _planifierRechargement() {
    _antiRebond?.cancel();
    _antiRebond = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      _reloadData(showLoading: false, syncBeforeLoad: true);
    });
  }

  bool _syncProduitsEnCours = false;

  /// ⚡ MODULE 23 — SYNCHRONISATION CIBLÉE DES PRODUITS.
  ///
  /// Avant : `syncAll()` téléchargeait TOUTES les tables à chaque produit
  /// modifié. C'était la cause principale de la lenteur de la caisse.
  /// Ici, une seule requête (produits + conditionnements) est envoyée, puis
  /// la copie locale est mise à jour. La vente reste utilisable hors ligne.
  Future<void> _synchroniserProduits() async {
    if (_syncProduitsEnCours) return;
    _syncProduitsEnCours = true;
    try {
      final List<Article> articles =
          await ArticleService.instance.getArticles();
      // Écriture par lots : un seul aller-retour SQLite par paquet de 40.
      for (int debut = 0; debut < articles.length; debut += 40) {
        final int fin = (debut + 40 < articles.length)
            ? debut + 40
            : articles.length;
        await Future.wait(
          articles.sublist(debut, fin).map(
                (Article a) => DBHelper.instance.upsertProduitFromSupabase(
                  Produit(
                    nom: a.nom,
                    categorie: a.categorie,
                    prixAchat: a.prixAchat,
                    prixVente: a.prixVente,
                    quantite: a.quantite,
                    uniteMesure: a.uniteMesure,
                    photo: a.photo,
                    createdAt: a.createdAt?.toIso8601String(),
                    updatedAt: a.updatedAt?.toIso8601String(),
                    ownerId: a.ownerId,
                    supabaseId: '${a.id}',
                    isSynced: 1,
                  ),
                ),
              ),
        );
      }
    } catch (e) {
      debugPrint('NewSalePage : synchronisation produits ignorée ($e)');
    } finally {
      _syncProduitsEnCours = false;
    }
  }

  Future<void> _initializeData() async {
    await _reloadData(showLoading: true, syncBeforeLoad: true);
    _startRealtimeListener();
  }

  Future<void> _reloadData({
    required bool showLoading,
    required bool syncBeforeLoad,
  }) async {
    if (!mounted) return;

    if (showLoading) {
      setState(() => _loading = true);
    }

    try {
      _currentUserId = await SessionManager.getUserId();

      if (_currentUserId == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        if (context.mounted) {
          context.go('/login');
        }
        return;
      }

      // Le propriétaire ne change pas pendant la vie de l'écran : on le
      // résout UNE fois (chaque résolution interroge SQLite et parfois le
      // réseau — inutile de la refaire à chaque évènement temps réel).
      _effectiveOwnerId ??=
          await DBHelper.instance.resolveEffectiveOwnerId(_currentUserId!);

      final ownerId = _effectiveOwnerId ?? _currentUserId!;

      if (syncBeforeLoad) {
        await _synchroniserProduits();
      }

      final data = await Future.wait([
        DBHelper.instance.getProduits(ownerId: ownerId),
        DBHelper.instance.getClients(ownerId: ownerId),
      ]);

      if (!mounted) return;

      final loadedProducts = data[0] as List<Produit>;
      final loadedClients = data[1] as List<Client>;

      setState(() {
        produits = loadedProducts;
        clients = loadedClients;
        _loading = false;
      });

      if (!_productsController.isClosed) {
        _productsController.add(loadedProducts);
      }

      // L'écoute temps réel ne démarre qu'une fois le propriétaire connu :
      // elle est filtrée sur SA boutique (pas les évènements de tout le pays).
      if (mounted) _startRealtimeListener();
    } catch (e) {
      debugPrint('Erreur chargement new sale: $e');
      if (!mounted) return;

      setState(() => _loading = false);

      if (!_productsController.isClosed) {
        _productsController.addError(e);
      }
    }
  }

  /// 🔴 CORRECTIF 77 — LA CAISSE PARLE EN IDENTIFIANTS SERVEUR.
  ///
  /// `Produit.id` est l'identifiant LOCAL (SQLite) : envoyé au serveur, il
  /// produisait « Article n° 83 introuvable : il a peut-être été supprimé. »
  /// On travaille donc avec [Produit.idServeur] — le vrai numéro de la ligne
  /// dans `public.produits` — y compris pour les clés du panier.
  ///
  /// Un article jamais envoyé au serveur (créé hors ligne, synchronisation en
  /// attente) ne peut pas être vendu : on le DIT, au lieu de laisser le
  /// serveur refuser à l'encaissement.
  void _updateQuantity(Produit p, double qty) {
    final int? idServeur = p.idServeur;
    if (idServeur == null) {
      _showSnackBar(
        '« ${p.nom} » n\'est pas encore enregistré sur le serveur : '
        'synchronisez (Paramètres → Synchroniser) puis réessayez.',
        isError: true,
      );
      return;
    }

    // Quantité nulle : la ligne quitte le panier.
    if (qty <= 0) {
      _panier.retirer('PROD:$idServeur');
      return;
    }

    if (qty > p.quantite) {
      _showSnackBar(AppLocalizations.of(context)!.outOfStock, isError: true);
      return;
    }

    _panier.definirQuantite(ArticleScanne.depuisProduit(p), qty);
  }

  void _setProductQuantity(Produit p, double qty) => _updateQuantity(p, qty);

  /// 🔎 Retrouve l'article du TÉLÉPHONE correspondant à une ligne du panier.
  ///
  /// Une ligne connaît son numéro de base ; la copie locale, elle, a le sien.
  /// On cherche d'abord par numéro local, puis — pour une ligne scannée — par
  /// `supabase_id`. `null` = article absent de ce téléphone.
  Produit? _produitLocal(LignePanier ligne) {
    final int? idLocal = ligne.produitIdLocal;
    if (idLocal != null) {
      for (final Produit p in produits) {
        if (p.id == idLocal) return p;
      }
    }
    final String numeroServeur = ligne.produitId.toString();
    for (final Produit p in produits) {
      if (p.supabaseId == numeroServeur) return p;
    }
    return null;
  }

  /// ➕ AJOUTER AU PANIER — IMMÉDIAT.
  ///
  /// 🔴 CORRECTIF 78 — l'ajout attendait auparavant une réponse du serveur
  /// (`getArticleById`) AVANT d'inscrire quoi que ce soit : d'où le temps
  /// d'attente, les appuis répétés et l'impression que « le produit ne
  /// s'ajoute pas en une seule fois ».
  ///
  /// Désormais la ligne est ajoutée TOUT DE SUITE (données du téléphone), et
  /// les emballages éventuels (farde, carton…) sont proposés **après**, par un
  /// message discret : la vente n'attend plus jamais le réseau.
  void _ajouterAuPanier(Produit p) {
    final int? idServeur = p.idServeur;
    final double actuel =
        idServeur == null ? 0 : _panier.quantiteProduit(idServeur);
    _updateQuantity(p, actuel + 1);

    // Proposer les emballages sans bloquer ni ralentir l'ajout.
    unawaited(_proposerFormats(p));
  }

  /// 🧾 MULTI-FORMATS (en arrière-plan) — si l'article a des emballages, on
  /// le signale par un message avec un bouton « Choisir ». Aucun échec réseau
  /// n'a d'effet sur le panier : la ligne est déjà ajoutée.
  Future<void> _proposerFormats(Produit p) async {
    final int? idServeur = p.idServeur;
    if (idServeur == null) return;

    try {
      final Article? article =
          await ArticleService.instance.getArticleById(idServeur);
      if (!mounted || article == null) return;

      final List<Conditionnement> formats = article.conditionnements;
      if (formats.isEmpty) return;

      final String liste =
          formats.map((Conditionnement c) => c.libelle).take(3).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('« ${p.nom} » se vend aussi par : $liste'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Choisir',
            onPressed: () => _choisirFormat(article, formats),
          ),
        ),
      );
    } catch (e) {
      // Silencieux : un emballage indisponible ne doit jamais gêner la vente.
      debugPrint('Formats indisponibles pour ${p.nom} : $e');
    }
  }

  Future<void> _choisirFormat(
    Article article,
    List<Conditionnement> formats,
  ) async {
    final ChoixFormatVente? choix = await choisirFormatVente(
      context,
      article: article,
      conditionnements: formats,
    );
    if (choix == null || !mounted) return;

    // La ligne à l'unité laisse la place à l'emballage choisi.
    _panier.retirer('PROD:${article.id}');
    _panier.ajouterArticle(
      ArticleScanne(article: article, conditionnement: choix.format),
      quantite: choix.quantite,
    );
  }

  void _incrementProductQuantity(Produit p, {double step = 1.0}) {
    final int? idServeur = p.idServeur;
    if (idServeur == null) {
      _updateQuantity(p, step);
      return;
    }
    final double current = _panier.quantiteProduit(idServeur);
    _updateQuantity(p, current + step);
  }

  /// Total du panier partagé (lignes scannées ET lignes ajoutées à la main).
  ///
  /// 🛒 MODULE 25 — montant réellement dû : négociations et réduction globale
  /// comprises (les cadeaux, eux, ne coûtent rien au client).
  double get total => _panier.totalAPayer();

  Future<void> _confirmCancelSale() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Annuler la vente ?"),
        content: const Text(
          "Voulez-vous vraiment vider le panier et annuler cette vente en cours ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Non"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Oui, annuler"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      _panier.vider();
      setState(() {
        selectedClient = null;
        isModeDette = false;
        _searchController.clear();
      });
      _showSnackBar("Vente annulée");
    }
  }

  Future<void> _save() async {
    // 🔒 MODULE 3 — Abonnement échu : les ventes sont bloquées (lecture seule).
    // Filet de sécurité en plus du garde-fou de l'accueil et de la bannière.
    if (AbonnementService.instance.lectureSeule) {
      afficherDialogueLectureSeule(context);
      return;
    }

    final T = AppLocalizations.of(context)!;
    if (_panier.estVide) return;

    if (isModeDette && selectedClient == null) {
      _showSnackBar(
        "Veuillez sélectionner un client pour le crédit",
        isError: true,
      );
      return;
    }

    final ownerId = _effectiveOwnerId ?? _currentUserId;
    if (ownerId == null) return;

    setState(() => _loading = true);

    try {
      final now = DateTime.now();
      final String nowIso = now.toIso8601String();
      final ventes = <Vente>[];
      final invoiceItems = <InvoiceItem>[];
      final double currentTotal = total;

      // 🔳 MODULE 7 — lignes du panier partagé :
      //   • `quantite` de la vente = unités de BASE retirées du stock
      //     (une farde de 12 = 12 bouteilles) ;
      //   • `prix` = TOTAL de la ligne (prix du conditionnement × quantité).
      //
      // 🔴 CORRECTIF 78 — ON ENREGISTRE AVEC LE NUMÉRO LOCAL.
      //   `ligne.produitId` est le numéro de la BASE (503…) : la table locale
      //   ne le connaît pas, d'où « Erreur lors de l'enregistrement de la
      //   vente : Exception: Produit ID 503 introuvable ». Ici, tout est local :
      //   on repasse par l'article du téléphone ([_produitLocal]).
      for (final LignePanier ligne in _panier.lignes) {
        final double totalAmount = ligne.total;

        final Produit? local = _produitLocal(ligne);
        if (local == null || local.id == null) {
          if (mounted) {
            setState(() => _loading = false);
            _showSnackBar(
              '« ${ligne.nom} » n\'est pas encore enregistré sur ce téléphone : '
              'synchronisez puis réessayez.',
              isError: true,
            );
          }
          return;
        }

        ventes.add(
          Vente(
            produitId: local.id!,
            quantite: ligne.unitesBase,
            prix: totalAmount,
            modePaiement: isModeDette ? 'dette' : modePaiement,
            createdAt: nowIso,
            ownerId: ownerId,
            sellerId: _currentUserId,
            clientId: selectedClient?.id,
          ),
        );

        invoiceItems.add(
          InvoiceItem(
            name: ligne.libelle,
            quantity: ligne.quantite,
            unit: ligne.vendu.uniteVente,
            pricePerUnit: ligne.prixUnitaire,
            total: totalAmount,
          ),
        );

        final int index =
            produits.indexWhere((Produit pr) => pr.id == local.id);
        if (index >= 0) produits[index].quantite -= ligne.unitesBase;
      }

      final invoiceId =
      await DBHelper.instance.insertMultipleVentesWithStockUpdate(ventes);

      if (isModeDette && selectedClient != null) {
        await DBHelper.instance.insertDette(
          Dette(
            ownerId: ownerId,
            clientId: selectedClient!.id!,
            venteId: invoiceId,
            montantTotal: currentTotal,
            dateCreation: nowIso,
          ),
        );
      }

      if (mounted) {
        _panier.vider();
        setState(() {
          selectedClient = null;
          isModeDette = false;
          _loading = false;
        });

        final user = await DBHelper.instance.getUtilisateurById(ownerId);
        final invoiceService = InvoiceService(
          T: T,
          userName: user?.nom ?? T.defaultStoreName,
          paymentMode: isModeDette ? "Crédit" : modePaiement,
          totalAmount: currentTotal,
          items: invoiceItems,
          saleDate: now,
          invoiceId: invoiceId,
        );

        _showPrintSelectionDialog(invoiceService);
      }

      _triggerImmediateSync();

      // 🔔 CORRECTIF 78 — la vente est enregistrée : le tableau de bord se
      // remet à jour tout seul (totaux, ventes du jour, stock faible).
      DonneesService.instance.signale('vente-caisse');
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnackBar("${T.saleError}: $e", isError: true);
      }
    }
  }

  void _triggerImmediateSync() {
    SyncService.instance.syncAll().then((_) async {
      debugPrint("🚀 Sync OK");
      await _reloadData(showLoading: false, syncBeforeLoad: false);
    }).catchError((e) {
      debugPrint("⚠️ Sync Fail: $e");
    });
  }

  /// 🔳 MODULE 7 — ouvre le scanner plein écran. Les articles scannés
  /// rejoignent le panier partagé et apparaissent ici au retour.
  Future<void> _ouvrirScanner() async {
    await context.push('/scanner');
  }

  void _showSetQuantityDialog(Produit p) {
    final T = AppLocalizations.of(context)!;
    final int? idServeur = p.idServeur;
    final double enPanier =
        idServeur == null ? 0 : _panier.quantiteProduit(idServeur);
    final double currentQty = enPanier > 0 ? enPanier : 1.0;
    _quantityController.text = currentQty.toStringAsFixed(
      currentQty.truncateToDouble() == currentQty ? 0 : 2,
    );

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          T.addToCartTitle(p.nom),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Stock actuel : ${p.quantite} ${p.uniteMesure}'),
            const SizedBox(height: 16),
            TextField(
              controller: _quantityController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: T.dialogQuantityLabel(p.uniteMesure),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(T.cancelButton),
          ),
          FilledButton(
            onPressed: () {
              final qty = double.tryParse(
                _quantityController.text.replaceAll(',', '.'),
              );

              if (qty == null || qty <= 0) {
                _showSnackBar(T.invalidQuantity, isError: true);
                return;
              }

              if (qty > p.quantite) {
                _showSnackBar(
                  T.insufficientStock(
                    p.quantite.toStringAsFixed(2),
                    p.uniteMesure,
                  ),
                  isError: true,
                );
                return;
              }

              Navigator.pop(dialogContext);
              _setProductQuantity(p, qty);
            },
            child: Text(T.addButton),
          ),
        ],
      ),
    );
  }

  void _showClientSelection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scroll) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                "Sélectionner un Client",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: clients.length,
                itemBuilder: (context, i) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(clients[i].nom),
                  subtitle: Text(clients[i].telephone ?? ""),
                  onTap: () {
                    setState(() => selectedClient = clients[i]);
                    Navigator.pop(context);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    if (_loading) {
      return const Scaffold(
        body: Center(child: PrimaryLoader(size: 36)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(T.newSaleTitle),
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Voir le panier',
            onPressed: () => context.push('/main/panier'),
            icon: Badge.count(
              count: _panier.nombreLignes,
              isLabelVisible: !_panier.estVide,
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
          if (!_panier.estVide)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              tooltip: "Annuler la vente",
              onPressed: _confirmCancelSale,
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: T.searchProductLabel,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    FocusScope.of(context).unfocus();
                  },
                )
                    : null,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              ),
            ),
          ),

          // 🔳 MODULE 7 — accès rapide au scanner vendeur (plein écran).
          if (PermissionService.instance.peutVoir(PageAccess.scanner))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton.icon(
                  onPressed: _ouvrirScanner,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 0.4,
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 26),
                  label: const Text('SCANNER UN ARTICLE'),
                ),
              ),
            ),

          Expanded(
            child: StreamBuilder<List<Produit>>(
              stream: _productsController.stream,
              builder: (context, snapshot) {
                final currentProducts = snapshot.data ?? produits;

                final filteredProduits = currentProducts
                    .where(
                      (p) => p.nom.toLowerCase().contains(_searchQuery),
                )
                    .toList();

                if (filteredProduits.isEmpty) {
                  return const Center(
                    child: Icon(Icons.search_off, size: 64, color: Colors.grey),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filteredProduits.length,
                  itemBuilder: (context, i) =>
                      _buildProductCard(filteredProduits[i], T),
                );
              },
            ),
          ),
          _buildCheckoutPanel(T),
        ],
      ),
    );
  }

  Widget _buildProductCard(Produit p, AppLocalizations T) {
    final theme = Theme.of(context);
    final int? idServeur = p.idServeur;
    final double q =
        idServeur == null ? 0.0 : _panier.quantiteProduit(idServeur);
    final isSelected = q > 0;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
          : theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _pickImage(p),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: p.photo != null && imageLocaleExiste(p.photo!)
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: imageFichierLocal(
                    p.photo!,
                    fit: BoxFit.cover,
                  ),
                )
                    : Icon(
                  Icons.add_a_photo,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.nom,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                  ),
                  Text(
                    '${formatMontant(p.prixVente)} / ${p.uniteMesure}',
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Stock: ${p.quantite.toStringAsFixed(1)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: p.quantite <= 5 ? Colors.red : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                if (isSelected)
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: () => _updateQuantity(p, q - 1),
                        ),
                        InkWell(
                          onTap: () => _showSetQuantityDialog(p),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              q.toStringAsFixed(
                                q == q.truncateToDouble() ? 0 : 2,
                              ),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => _incrementProductQuantity(p),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => _ajouterAuPanier(p),
                    child: Text(T.addButton),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutPanel(AppLocalizations T) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(
                  onTap: _showClientSelection,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    constraints: const BoxConstraints(maxWidth: 200),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            selectedClient?.nom ?? "Client (Opt)",
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selectedClient != null)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () => setState(() => selectedClient = null),
                          ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Dette",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Switch(
                      value: isModeDette,
                      onChanged: (v) => setState(() => isModeDette = v),
                      activeColor: Colors.orange,
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('TOTAL', style: theme.textTheme.bodySmall),
                Text(
                  formatMontant(total),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (!isModeDette)
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      value: modePaiement,
                      items: _paymentModes.entries
                          .map(
                            (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text(T.paymentMode(e.key)),
                        ),
                      )
                          .toList(),
                      onChanged: (v) => setState(() => modePaiement = v ?? 'cash'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                if (!isModeDette) const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: !_panier.estVide ? _save : null,
                      style: FilledButton.styleFrom(
                        backgroundColor:
                        isModeDette ? Colors.orange : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(
                        isModeDette ? Icons.warning_amber : Icons.check_circle,
                      ),
                      label: Text(
                        isModeDette ? "CRÉDIT" : T.recordSaleButton,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPrintSelectionDialog(InvoiceService service) {
    final T = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          T.saleRecordedAndInvoiceGenerated,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 60),
            SizedBox(height: 16),
            Text("Prêt pour la facture ?"),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                service.generateAndPrintInvoice(isTicket: true);
              },
              icon: const Icon(Icons.receipt_long),
              label: const Text("Ticket (58mm)"),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                service.generateAndPrintInvoice(isTicket: false);
              },
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text("PDF / A4"),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(T.cancelButton),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppCouleurs.danger : null,
      ),
    );
  }

  Future<void> _pickImage(Produit p) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => p.photo = image.path);
      await DBHelper.instance.updateProduitPhoto(p.id!, image.path);
    }
  }
}