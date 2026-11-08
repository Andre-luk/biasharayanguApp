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
import 'package:biashara_yangu/models/pesee.dart';
import 'package:biashara_yangu/models/produit.dart';
import 'package:biashara_yangu/models/vente.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';
import 'package:biashara_yangu/services/facture_vente_service.dart';
import 'package:biashara_yangu/services/lecteur_code_barre_usb.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/scanner_service.dart';
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
import 'package:biashara_yangu/widgets/actions_facture.dart';
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

  /// 🧾 V14 — FORMATS DE VENTE PAR ARTICLE (clé = identifiant SERVEUR).
  ///
  /// « Ce produit se vend-il aussi en farde / carton ? » : la réponse est
  /// chargée depuis la base du téléphone, donc disponible MÊME HORS LIGNE.
  /// Une carte produit qui a des formats ouvre le sélecteur à l'ajout.
  Map<String, List<Conditionnement>> _formatsParProduit =
      <String, List<Conditionnement>>{};

  /// 🔳 MODULE 7 — panier partagé de la boutique : la caisse et le scanner
  /// vendeur y ajoutent leurs lignes (articles et conditionnements).
  final PanierService _panier = PanierService.instance;

  String modePaiement = 'cash';
  bool _loading = true;
  String _searchQuery = '';

  final ImagePicker _picker = ImagePicker();
  final TextEditingController _searchController = TextEditingController();

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
                (Article a) async {
                  await DBHelper.instance.upsertProduitFromSupabase(
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
                      // 🏷️ MODULE 28 — le code-barres fabricant descend sur
                      // le téléphone : le lecteur USB reconnaît l'article
                      // même sans réseau.
                      codeBarre: a.codeBarre,
                    ),
                  );

                  // 🧾 V14 — les FORMATS de l'article suivent le produit :
                  // la caisse peut alors proposer « à l'unité / farde /
                  // carton » sans aucune requête réseau au moment de vendre.
                  await DBHelper.instance.remplacerConditionnementsProduit(
                    produitSupabaseId: '${a.id}',
                    ownerId: a.ownerId,
                    formats: a.conditionnements,
                  );
                },
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
        DBHelper.instance.getConditionnementsParProduit(ownerId: ownerId),
      ]);

      if (!mounted) return;

      final loadedProducts = data[0] as List<Produit>;
      final loadedClients = data[1] as List<Client>;
      final formats =
          data[2] as Map<String, List<Conditionnement>>;

      setState(() {
        produits = loadedProducts;
        clients = loadedClients;
        _formatsParProduit = formats;
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

    // 🧾 MODULE 27 — LA QUANTITÉ S'APPLIQUE À LA BONNE LIGNE.
    //  Une farde est rangée sous `COND:…`. Si l'article a déjà des lignes au
    //  panier (farde + bouteilles), la quantité demandée porte sur la
    //  DERNIÈRE ligne ajoutée : c'est celle que le vendeur vient de toucher.
    final List<LignePanier> lignes = _panier.lignesProduit(idServeur);
    final LignePanier? cible = lignes.isEmpty ? null : lignes.last;

    // Quantité nulle : la ligne quitte le panier.
    if (qty <= 0) {
      if (cible != null) {
        _panier.retirer(cible.cle);
      } else {
        _panier.retirer('PROD:$idServeur');
      }
      setState(() {});
      return;
    }

    if (cible == null) {
      // Aucune ligne : on ajoute à l'unité de base (stock en unités de base).
      if (qty > p.quantite) {
        _showSnackBar(AppLocalizations.of(context)!.outOfStock, isError: true);
        return;
      }
      _panier.definirQuantite(ArticleScanne.depuisProduit(p), qty);
      setState(() {});
      return;
    }

    _modifierQuantiteLigne(p, cible, qty);
  }

  /// 🧾 MODULE 27 — change la quantité d'UNE ligne, en respectant son format.
  ///
  /// Le stock est toujours compté en UNITÉS DE BASE : 2 fardes de 12 = 24
  /// bouteilles, et non 2. Un contrôle faux faisait refuser l'ajout sans
  /// explication (« rien ne s'affiche »).
  void _modifierQuantiteLigne(Produit p, LignePanier ligne, double quantite) {
    if (quantite <= 0) {
      _panier.retirer(ligne.cle);
      setState(() {});
      return;
    }

    final int? idServeur = p.idServeur;
    final double dejaAuPanier =
        idServeur == null ? 0 : _panier.unitesBaseProduit(idServeur);
    final double nouvelleBase = dejaAuPanier -
        ligne.unitesBase +
        ligne.vendu.unitesBasePour(quantite);

    if (nouvelleBase > p.quantite + 0.0001) {
      final double restant = p.quantite - (dejaAuPanier - ligne.unitesBase);
      _showSnackBar(
        'Stock insuffisant pour ${p.nom} : il reste '
        '${_quantiteTexte(restant > 0 ? restant : 0)} ${p.uniteMesure}.',
        isError: true,
      );
      return;
    }

    _panier.definirQuantite(ligne.vendu, quantite);
    setState(() {});
  }

  /// ➖ Retire une unité du dernier format ajouté (ou la ligne entière).
  void _decrementerProduit(Produit p) {
    final int? idServeur = p.idServeur;
    if (idServeur == null) return;
    final List<LignePanier> lignes = _panier.lignesProduit(idServeur);
    if (lignes.isEmpty) return;

    final LignePanier ligne = lignes.last;
    final double pas = ligne.vendu.pasQuantite;
    final double nouvelle = ligne.quantite - pas;
    if (nouvelle <= 0) {
      _panier.retirer(ligne.cle);
      setState(() {});
      return;
    }
    _panier.definirQuantite(ligne.vendu, nouvelle);
    setState(() {});
  }

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

  /// ➕ AJOUTER AU PANIER — IMMÉDIAT, AVEC LE FORMAT.
  ///
  /// 🔴 CORRECTIF 78 — l'ajout attendait auparavant une réponse du serveur
  /// AVANT d'inscrire quoi que ce soit : d'où le temps d'attente et
  /// l'impression que « le produit ne s'ajoute pas en une seule fois ».
  ///
  /// 🧾 V14 — LE FORMAT SE CHOISIT MAINTENANT. Si l'article possède des
  /// emballages (farde, carton, sachet…), la caisse ouvre le sélecteur
  /// **au moment de l'ajout** : le vendeur voit tout de suite les prix par
  /// format et choisit la quantité. Les formats viennent de la base LOCALE
  /// (`conditionnements`, V14) : cela fonctionne donc même sans réseau.
  ///
  /// Un article sans emballage s'ajoute directement à l'unité, comme avant.
  Future<void> _ajouterAuPanier(Produit p) async {
    final int? idServeur = p.idServeur;
    if (idServeur == null) {
      _updateQuantity(p, 0);
      return;
    }

    final List<Conditionnement> formats =
        _formatsParProduit['$idServeur'] ?? const <Conditionnement>[];

    // Aucun emballage : ajout à l'unité, immédiat et inchangé.
    if (formats.isEmpty) {
      final double actuel = _panier.quantiteProduit(idServeur);
      _updateQuantity(p, actuel + 1);
      return;
    }

    // L'article se vend sous plusieurs formats : on demande lequel.
    final Article article = _articleDepuisProduit(p, formats);

    if (_panier.quantiteProduit(idServeur) > 0) {
      // Une ligne « à l'unité » est déjà au panier : le sélecteur s'ouvre
      // quand même, c'est la seule façon de composer un panier mixte
      // (2 bouteilles + 1 farde).
      debugPrint('Caisse : ligne unité déjà présente pour ${p.nom}');
    }

    final ChoixFormatVente? choix = await choisirFormatVente(
      context,
      article: article,
      conditionnements: formats,
    );
    if (choix == null || !mounted) return;

    _ajouterLigneFormat(p, article, choix);
  }

  /// Ajoute la ligne correspondant au format choisi, en tenant compte du
  /// stock réel du téléphone (jamais plus que disponible).
  void _ajouterLigneFormat(
    Produit p,
    Article article,
    ChoixFormatVente choix,
  ) {
    final ArticleScanne scanne = ArticleScanne(
      article: article,
      conditionnement: choix.format,
      produitIdLocal: p.id,
    );

    // ⚠️ Le stock se compte en UNITÉS DE BASE, tous formats confondus :
    // « 3 bouteilles + 2 fardes de 12 » consomme 27 bouteilles, pas 5.
    final int? idServeur = p.idServeur;
    double baseAuPanier = 0;
    for (final LignePanier ligne in _panier.lignes) {
      if (ligne.produitId == idServeur) baseAuPanier += ligne.unitesBase;
    }
    final double baseDemandee = scanne.unitesBasePour(choix.quantite);

    if (baseAuPanier + baseDemandee > p.quantite + 0.0001) {
      final double restant = p.quantite - baseAuPanier;
      _showSnackBar(
        'Stock insuffisant pour ${p.nom} : '
        '${restant > 0 ? _quantiteTexte(restant) : '0'} '
        '${p.uniteMesure} encore disponible(s).',
        isError: true,
      );
      return;
    }

    final double ajoutee =
        _panier.ajouterArticle(scanne, quantite: choix.quantite);

    if (ajoutee <= 0) {
      _showSnackBar(
        '« ${p.nom} » n\'a plus de stock dans ce format.',
        isError: true,
      );
      return;
    }

    setState(() {});

    final String libelle = choix.format == null
        ? p.uniteMesure
        : '${choix.format!.libelle} '
            '(${choix.format!.quantiteUnitesBase.toStringAsFixed(0)} '
            '${p.uniteMesure})';
    _showSnackBar('${p.nom} — $libelle ajouté au panier.');
  }

  // ---------------------------------------------------------------------------
  // 🔌 MODULE 28 — LECTEUR DE CODES-BARRES USB / BLUETOOTH EXTERNE
  // ---------------------------------------------------------------------------

  /// Retrouve un article du téléphone par son identifiant SERVEUR.
  Produit? _produitParIdServeur(int idServeur) {
    for (final Produit p in produits) {
      if (p.idServeur == idServeur) return p;
    }
    return null;
  }

  /// Retrouve un article du téléphone par son code-barres fabricant.
  Produit? _produitParCodeBarre(String code) {
    final String recherche = code.trim().toLowerCase();
    if (recherche.isEmpty) return null;
    for (final Produit p in produits) {
      final String codeProduit = (p.codeBarre ?? '').trim().toLowerCase();
      if (codeProduit.isNotEmpty && codeProduit == recherche) return p;
    }
    return null;
  }

  /// Retrouve un emballage (farde, carton…) vendu par son QR ou son code-barres.
  ({Produit produit, Conditionnement format})? _formatParCode(String code) {
    final String recherche = code.trim().toLowerCase();
    if (recherche.isEmpty) return null;

    for (final MapEntry<String, List<Conditionnement>> entree
        in _formatsParProduit.entries) {
      final int? idServeur = int.tryParse(entree.key);
      if (idServeur == null) continue;

      for (final Conditionnement c in entree.value) {
        final String qr = c.qrCodeId.trim().toLowerCase();
        final String id = c.id.trim().toLowerCase();
        final String barre = (c.codeBarreTexte ?? '').trim().toLowerCase();

        final bool correspond = (qr.isNotEmpty && qr == recherche) ||
            (id.isNotEmpty && id == recherche) ||
            (barre.isNotEmpty && barre == recherche);
        if (!correspond) continue;

        final Produit? p = _produitParIdServeur(idServeur);
        if (p != null) return (produit: p, format: c);
      }
    }
    return null;
  }

  /// 🔌 MODULE 28 — UN CODE LU PAR UN LECTEUR EXTERNE ENTRE DANS LA VENTE.
  ///
  /// Ordre de reconnaissance (tout en LOCAL d'abord : un lecteur USB doit
  /// fonctionner même sans réseau) :
  ///   1. étiquette de balance `BAL:<produit>:<grammes>` ;
  ///   2. étiquette de l'application `PROD:<id>` / `COND:<uuid>` ;
  ///   3. code-barres fabricant d'un emballage (farde, carton…), puis d'un
  ///      article — les deux sont recopiés sur le téléphone ;
  ///   4. en dernier recours, le serveur (article jamais synchronisé ici).
  ///
  /// 🩹 Si le poste est en clavier AZERTY et le lecteur réglé en QWERTY, le
  /// code arrive décalé (« &&&é » au lieu de « 1112 »). On réessaie donc avec
  /// le code réécrit avant de déclarer l'article inconnu.
  Future<void> _traiterCodeScan(String codeBrut) async {
    final String code = codeBrut.trim();
    if (code.isEmpty || !mounted) return;

    // Un code scanné ne doit pas rester dans la recherche.
    if (_searchController.text.isNotEmpty) _searchController.clear();

    if (await _resoudreCodeLocal(code)) return;

    final String corrige = corrigerCodeClavier(code);
    if (corrige != code && await _resoudreCodeLocal(corrige)) return;

    // 4. LE SERVEUR, EN DERNIER RECOURS -------------------------------------
    for (final String candidat in <String>{code, corrige}) {
      try {
        final ArticleScanne scanne =
            await ScannerService.instance.resoudre(candidat);
        if (!mounted) return;
        final double ajoutee = _panier.ajouterArticle(scanne, quantite: 1);
        setState(() {});
        if (ajoutee <= 0) {
          _showSnackBar('« ${scanne.nom} » n\'a plus de stock.', isError: true);
          return;
        }
        _showSnackBar('${scanne.libelleComplet} ajouté au panier.');
        return;
      } catch (e) {
        debugPrint('Caisse : scan réseau ignoré ($candidat) — $e');
      }
    }

    _scanInconnu(code);
  }

  /// Reconnaît un code SANS réseau. Renvoie `true` dès qu'il a été traité
  /// (ajouté au panier ou refusé pour cause de stock), `false` si le code
  /// n'appartient pas à cette boutique.
  Future<bool> _resoudreCodeLocal(String code) async {
    // 1. ÉTIQUETTE DE BALANCE ------------------------------------------------
    final ({int produitId, double poids})? balance =
        PeseeCalculs.decoderCodeBalance(code);
    if (balance != null) {
      final Produit? p = _produitParIdServeur(balance.produitId);
      if (p == null) return false;
      final ArticleScanne scanne =
          ArticleScanne.depuisProduit(p).avecPoids(balance.poids);
      final double ajoutee =
          _panier.ajouterArticle(scanne, quantite: balance.poids);
      setState(() {});
      if (ajoutee <= 0) {
        _showSnackBar('Stock insuffisant pour ${p.nom}.', isError: true);
        return true;
      }
      _showSnackBar('${p.nom} — ${_quantiteTexte(balance.poids)} kg ajouté.');
      return true;
    }

    // 2. ÉTIQUETTE DE L'APPLICATION -----------------------------------------
    final RegExpMatch? article =
        RegExp(r'^PROD:(\d+)$', caseSensitive: false).firstMatch(code);
    if (article != null) {
      final int? idServeur = int.tryParse(article.group(1)!);
      final Produit? p =
          idServeur == null ? null : _produitParIdServeur(idServeur);
      if (p == null) return false;
      await _ajouterAuPanier(p);
      return true;
    }

    final RegExpMatch? emballage =
        RegExp(r'^COND:(.+)$', caseSensitive: false).firstMatch(code);
    if (emballage != null) {
      final ({Produit produit, Conditionnement format})? trouve =
          _formatParCode(emballage.group(1)!);
      if (trouve == null) return false;
      _ajouterFormatScanne(trouve.produit, trouve.format);
      return true;
    }

    // 3. CODE-BARRES FABRICANT ----------------------------------------------
    final ({Produit produit, Conditionnement format})? format =
        _formatParCode(code);
    if (format != null) {
      _ajouterFormatScanne(format.produit, format.format);
      return true;
    }

    final Produit? parCode = _produitParCodeBarre(code);
    if (parCode != null) {
      await _ajouterAuPanier(parCode);
      return true;
    }

    return false;
  }

  /// Ajoute 1 exemplaire d'un emballage scanné (farde, carton…).
  void _ajouterFormatScanne(Produit p, Conditionnement format) {
    final int? idServeur = p.idServeur;
    if (idServeur == null) {
      _updateQuantity(p, 0);
      return;
    }
    final List<Conditionnement> formats =
        _formatsParProduit['$idServeur'] ?? const <Conditionnement>[];
    _ajouterLigneFormat(
      p,
      _articleDepuisProduit(p, formats),
      ChoixFormatVente(format, quantite: 1),
    );
  }

  /// Message clair quand un code lu n'est pas (encore) connu de la boutique.
  void _scanInconnu(String code) {
    _showSnackBar(
      'Code « $code » non reconnu. Enregistrez d\'abord son code-barres sur '
      'la fiche de l\'article (Paramètres → Articles).',
      isError: true,
    );
  }

  /// « 12 » pour une quantité entière, « 1,5 » sinon.
  String _quantiteTexte(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '')
        .replaceAll('.', ',');
  }
  /// Construit l'[Article] attendu par le sélecteur à partir du produit local.
  ///
  /// Le prix de vente et l'unité sont ceux du téléphone : le serveur les
  /// revérifiera de toute façon à l'encaissement.
  Article _articleDepuisProduit(Produit p, List<Conditionnement> formats) {
    final int idServeur = int.tryParse(p.supabaseId ?? '') ?? (p.id ?? 0);
    return Article(
      id: idServeur,
      nom: p.nom,
      categorie: p.categorie,
      prixAchat: p.prixAchat,
      prixVente: p.prixVente.toDouble(),
      quantite: p.quantite,
      uniteMesure: p.uniteMesure,
      photo: p.photo,
      ownerId: p.ownerId,
      conditionnements: formats,
    );
  }

  /// ➕ Augmente la quantité du DERNIER format de l'article déjà au panier.
  ///
  /// 🧾 MODULE 27 — Avant, ce bouton créait une ligne « à l'unité » à côté de
  /// la farde : le vendeur croyait que son « + » ne faisait rien (le compteur
  /// de la carte ne bougeait pas). Si l'article n'est pas encore au panier, on
  /// passe par le sélecteur de format normal.
  void _incrementProductQuantity(Produit p, {double step = 1.0}) {
    final int? idServeur = p.idServeur;
    if (idServeur == null) {
      _updateQuantity(p, step);
      return;
    }

    final List<LignePanier> lignes = _panier.lignesProduit(idServeur);
    if (lignes.isEmpty) {
      // Rien au panier : on ajoute (le format est demandé si nécessaire).
      _ajouterAuPanier(p);
      return;
    }

    final LignePanier ligne = lignes.last;
    final double pas = ligne.vendu.pasQuantite;
    _modifierQuantiteLigne(p, ligne, ligne.quantite + (pas * step));
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
      final double currentTotal = total;

      // 🧾 MODULE 27 — on prépare les lignes de la FACTURE avant de vider le
      // panier : c'est la même structure que la caisse classique.
      final List<LigneFacture> lignesFacture = <LigneFacture>[];

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
            // 🧾 MODULE 28 — LE FORMAT PART AVEC LA VENTE. Sans lui, la
            // synchronisation rejouait la farde au prix de l'unité × 12.
            conditionnementId: ligne.conditionnementId,
            quantiteVendue: ligne.quantite,
          ),
        );

        lignesFacture.add(
          LigneFacture(
            designation: ligne.libelle,
            quantite: ligne.quantite,
            unite: ligne.vendu.uniteVente,
            prixUnitaire: ligne.prixUnitaireEffectif,
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

        // 🧾 MODULE 27 — FACTURE PROFESSIONNELLE, GÉNÉRÉE AUTOMATIQUEMENT.
        //  Même service que la caisse classique : modèle, numérotation,
        //  calculs et partage WhatsApp identiques.
        await EtablissementService.instance.charger();
        if (mounted) {
          final DonneesFacture facture = DonneesFacture(
            // 🧾 MODULE 27 — même numérotation que la caisse en ligne
            //  (`VTE-AAAAMMJJ-NNNN`), construite par le service de facture.
            numero: FactureVenteService.numeroVente(
              sequence: invoiceId,
              date: now,
            ),
            date: now,
            etablissement: EtablissementService.instance.courant,
            lignes: lignesFacture,
            total: currentTotal,
            modePaiement: isModeDette
                ? 'Crédit'
                : _libelleModePaiement(modePaiement),
            statut: isModeDette ? StatutFacture.credit : StatutFacture.payee,
            clientNom: selectedClient?.nom,
            clientTelephone: selectedClient?.telephone,
            clientAdresse: selectedClient?.adresse,
            montantPaye: isModeDette ? 0 : currentTotal,
            solde: isModeDette ? currentTotal : 0,
            venteId: invoiceId,
            devise: EtablissementService.instance.courant.devise,
          );

          final bool telechargee =
              await FactureVenteService.instance.telecharger(facture);

          if (mounted) {
            await afficherActionsFacture(
              context,
              facture,
              telechargeeAutomatiquement: telechargee,
            );
          }
        }
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

  /// 🧾 MODULE 27 — RÉGLAGE DE LA QUANTITÉ, FORMAT PAR FORMAT.
  ///
  /// Avant, ce dialogue affichait une seule quantité et comparait des
  /// « fardes » à un stock exprimé en bouteilles : 2 fardes de 12 étaient
  /// refusées comme « stock insuffisant » alors que 24 bouteilles étaient en
  /// rayon. Désormais chaque ligne du panier a son propre compteur, et le
  /// stock est toujours vérifié en UNITÉS DE BASE.
  void _showSetQuantityDialog(Produit p) {
    final int? idServeur = p.idServeur;
    if (idServeur == null) {
      _showSnackBar(
        '« ${p.nom} » n\'est pas encore enregistré sur le serveur : '
        'synchronisez (Paramètres → Synchroniser) puis réessayez.',
        isError: true,
      );
      return;
    }

    // Aucun format encore choisi : on ouvre le sélecteur complet.
    if (_panier.lignesProduit(idServeur).isEmpty) {
      _ajouterAuPanier(p);
      return;
    }

    final List<Conditionnement> formats =
        _formatsParProduit['$idServeur'] ?? const <Conditionnement>[];

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialogState) {
          final List<LignePanier> lignes = _panier.lignesProduit(idServeur);
          final double total = _panier.unitesBaseProduit(idServeur);

          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              p.nom,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Stock : ${_quantiteTexte(p.quantite)} ${p.uniteMesure} — '
                  'au panier : ${_quantiteTexte(total)} ${p.uniteMesure}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                if (lignes.isEmpty)
                  const Text('Ce produit n\'est plus au panier.')
                else
                  ...lignes.map((LignePanier ligne) {
                    final String unite = ligne.vendu.estConditionnement
                        ? ligne.vendu.libelleConditionnement
                        : p.uniteMesure;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  unite,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  formatMontant(ligne.total),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: () {
                              final double pas = ligne.vendu.pasQuantite;
                              _modifierQuantiteLigne(
                                p,
                                ligne,
                                ligne.quantite - pas,
                              );
                              setDialogState(() {});
                            },
                          ),
                          SizedBox(
                            width: 44,
                            child: Text(
                              _quantiteTexte(ligne.quantite),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_outline),
                            onPressed: () {
                              final double pas = ligne.vendu.pasQuantite;
                              _modifierQuantiteLigne(
                                p,
                                ligne,
                                ligne.quantite + pas,
                              );
                              setDialogState(() {});
                            },
                          ),
                          IconButton(
                            tooltip: 'Retirer',
                            icon: const Icon(Icons.delete_outline, size: 20),
                            onPressed: () {
                              _panier.retirer(ligne.cle);
                              setState(() {});
                              setDialogState(() {});
                            },
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
            actions: <Widget>[
              if (formats.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    _ajouterAuPanier(p);
                  },
                  icon: const Icon(Icons.add_shopping_cart, size: 18),
                  label: const Text('Autre format'),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Terminé'),
              ),
            ],
          );
        },
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

    return ZoneScannerUsb(
      onCode: _traiterCodeScan,
      actif: !_loading,
      child: Scaffold(
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
              // 🔌 MODULE 28 — SI LE LECTEUR USB A LE FOCUS ICI.
              //  Le lecteur est un clavier : le code arrive dans ce champ.
              //  Entrée, reconnue comme un code, l'ajoute à la vente au lieu
              //  de lancer une recherche stérile.
              textInputAction: TextInputAction.done,
              onSubmitted: (String valeur) {
                if (ressembleACodeBarre(valeur)) {
                  _traiterCodeScan(valeur);
                }
              },
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
      ),
    );
  }

  Widget _buildProductCard(Produit p, AppLocalizations T) {
    final theme = Theme.of(context);
    final int? idServeur = p.idServeur;

    // 🧾 MODULE 27 — ON COMPTE TOUTES LES LIGNES DE L'ARTICLE.
    //  Avant, seule la ligne « à l'unité » (`PROD:…`) était comptée : une
    //  farde ajoutée au panier n'apparaissait donc PAS sur la carte, et le
    //  bouton « + » créait une ligne à l'unité au lieu d'augmenter la farde.
    final List<LignePanier> lignes = idServeur == null
        ? const <LignePanier>[]
        : _panier.lignesProduit(idServeur);
    final double unitesBase =
        idServeur == null ? 0.0 : _panier.unitesBaseProduit(idServeur);
    final isSelected = lignes.isNotEmpty;

    // 🧾 V14 — les formats de CET article (farde, carton…), lus en local.
    final List<Conditionnement> formats = idServeur == null
        ? const <Conditionnement>[]
        : (_formatsParProduit['$idServeur'] ?? const <Conditionnement>[]);
    final bool multiFormats = formats.isNotEmpty;

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
                  // 🧾 V14 — le vendeur voit AVANT de cliquer que l'article
                  // se vend aussi en farde / carton.
                  if (multiFormats)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Aussi : ${formats.map((Conditionnement c) => c.libelle).take(3).join(', ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
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
                          tooltip: 'Diminuer',
                          onPressed: () => _decrementerProduit(p),
                        ),
                        InkWell(
                          onTap: () => _showSetQuantityDialog(p),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            // 🧾 MODULE 27 — la carte affiche les UNITÉS DE
                            // BASE réellement au panier (farde comprise), et
                            // non plus « 0 » alors que la farde y était.
                            child: Text(
                              _quantiteTexte(unitesBase),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          tooltip: 'Augmenter',
                          onPressed: () => _incrementProductQuantity(p),
                        ),
                      ],
                    ),
                  )
                else
                  FilledButton.tonal(
                    onPressed: () => _ajouterAuPanier(p),
                    child: Text(multiFormats ? 'Choisir' : T.addButton),
                  ),
                // Le détail par format : « 2 × Farde de 12 · 3 bouteilles ».
                if (isSelected && lignes.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      lignes
                          .map(
                            (LignePanier l) =>
                                '${_quantiteTexte(l.quantite)} × '
                                '${l.vendu.estConditionnement ? l.vendu.libelleConditionnement : p.uniteMesure}',
                          )
                          .join(' · '),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: theme.colorScheme.primary,
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

  /// 🧾 V14 — les lignes du panier, format compris (« 2 × Farde de 12 »).
  Widget _buildLignesPanier(ThemeData theme) {
    final List<LignePanier> lignes = _panier.lignes;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 132),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: lignes.map((LignePanier ligne) {
            final String quantite = ligne.quantite ==
                    ligne.quantite.roundToDouble()
                ? ligne.quantite.toStringAsFixed(0)
                : ligne.quantite.toStringAsFixed(2);

            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '$quantite × ${ligne.nom}'
                      '${ligne.vendu.estConditionnement ? ' (${ligne.vendu.libelleConditionnement})' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Text(
                    formatMontant(ligne.total),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 28,
                    ),
                    tooltip: 'Retirer du panier',
                    icon: const Icon(Icons.close_rounded, size: 17),
                    onPressed: () {
                      _panier.retirer(ligne.cle);
                      setState(() {});
                    },
                  ),
                ],
              ),
            );
          }).toList(growable: false),
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
            // 🧾 V14 — CE QUI EST VRAIMENT DANS LE PANIER.
            //  Avec plusieurs formats, « 2 fardes + 3 bouteilles » doit être
            //  lisible d'un coup d'œil : on liste les lignes, chacune
            //  supprimable d'un geste.
            if (_panier.lignes.isNotEmpty) ...<Widget>[
              _buildLignesPanier(theme),
              const SizedBox(height: 8),
            ],
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

  /// Libellé lisible d'un mode de paiement de la caisse (`cash`, `carte`…).
  String _libelleModePaiement(String code) {
    switch (code) {
      case 'cash':
        return 'Espèces';
      case 'carte':
        return 'Carte';
      case 'm-pesa':
        return 'Mobile Money';
      default:
        return code;
    }
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