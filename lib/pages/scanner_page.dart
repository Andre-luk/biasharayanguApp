// lib/pages/scanner_page.dart
//
// MODULE 7 — INTERFACE VENDEUR : « SCANNER UN ARTICLE ».
//
// Écran plein écran réservé aux rôles disposant de la page `scanner`
// (VENDEUR, PROPRIÉTAIRE — Module 4) :
//
//   1. caméra plein écran + détection automatique des CODES-BARRES (EAN-13,
//      UPC, Code 128…) ET des QR codes de l'application (scan continu,
//      sans jamais fermer l'écran) ;
//   2. feedback visuel (flash + bannière) et sonore (caisse + vibration) ;
//   3. fiche d'ajout au panier : nom, conditionnement, PRIX RELU DANS LA BASE,
//      stock, quantité (défaut 1), sous-total, bouton « Ajouter au panier » ;
//   4. historique des 5 derniers scans avec re-scan rapide ;
//   5. cas particuliers : QR inconnu (message d'erreur), rupture de stock
//      (avertissement + ajout bloqué), abonnement échu/suspendu (écran
//      d'information, scan bloqué).
//
// ⚠️ Le vendeur ne modifie JAMAIS un prix : tout est lu dans Supabase au
// moment du scan (les étiquettes QR ne contiennent aucune valeur monétaire).

import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/panier_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/scanner_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/widgets/code_barre_lecteur.dart';

// ---------------------------------------------------------------------------
// PALETTE DE L'ÉCRAN (thème sombre, la caméra occupe tout l'espace)
// ---------------------------------------------------------------------------

const Color _fondSombre = Color(0xFF101216);
const Color _vertAccent = Color(0xFF69F0AE);
const Color _vertBouton = Color(0xFF2E7D32);
const Color _rougeAlerte = Color(0xFFEF5350);

/// Taille du cadre de visée (px logiques), et sa position verticale.
const double _tailleCadre = 264;
const double _hauteurCadre = 0.38; // fraction de la hauteur de l'écran

/// Écran « Scanner un article » du vendeur.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _controleur;
  late final AnimationController _animationLigne;
  final AudioPlayer _audio = AudioPlayer();

  // --- contrôles d'accès (effectués avant de démarrer la caméra) ---
  bool _pret = false;
  bool _accesRefuse = false;
  bool _abonnementBloque = false;
  String _messageAbonnement = '';

  // --- état du scan ---
  bool _traitement = false;
  String? _dernierCode;
  DateTime? _dernierScanAt;

  // --- feedback ---
  String? _retourMessage;
  bool _retourSucces = true;
  Timer? _timerRetour;
  Color _couleurFlash = Colors.transparent;
  Timer? _timerFlash;

  @override
  void initState() {
    super.initState();
    _controleur = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      //  🏷️ CORRECTIF 59 — codes-barres FABRICANTS + QR codes de
      //  l'application : une étiquette déjà imprimée reste scannable.
      formats: formatsCodesBarres,
      autoZoom: true,
    );
    _animationLigne = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1900),
    )..repeat(reverse: true);
    _preparer();
  }

  @override
  void dispose() {
    _timerRetour?.cancel();
    _timerFlash?.cancel();
    _animationLigne.dispose();
    _audio.dispose();
    _controleur.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CONTRÔLES D'ACCÈS (RÔLE PUIS ABONNEMENT)
  // ---------------------------------------------------------------------------

  /// Vérifie le droit du rôle puis l'abonnement (Module 3), avant d'allumer
  /// la caméra. En cas d'abonnement EXPIRE/SUSPENDU, un écran d'information
  /// remplace le scanner — le blocage est immédiat (cahier des charges).
  Future<void> _preparer() async {
    final bool autorise = PermissionService.instance.peutVoir(PageAccess.scanner);

    EtatAccesAbonnement acces = AbonnementService.instance.acces.value;
    try {
      final String? userId = await SessionManager.getUserId();
      if (userId != null && userId.isNotEmpty) {
        acces = await AbonnementService.instance.verifierAccesUtilisateur(userId);
      }
    } catch (e) {
      debugPrint('ScannerPage : vérification d\'abonnement ignorée ($e)');
    }

    if (!mounted) return;
    setState(() {
      _accesRefuse = !autorise;
      _abonnementBloque = acces.bloque || acces.lectureSeule;
      _messageAbonnement = acces.message ?? '';
      _pret = true;
    });
  }

  /// `true` quand l'abonnement interdit désormais toute vente.
  bool get _venteInterdite {
    final EtatAccesAbonnement etat = AbonnementService.instance.acces.value;
    return etat.bloque || etat.lectureSeule;
  }

  // ---------------------------------------------------------------------------
  // DÉTECTION DES QR CODES (SCAN EN CONTINU)
  // ---------------------------------------------------------------------------

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (!_pret || _accesRefuse || _abonnementBloque || _traitement) return;

    // 🔒 Module 3 — l'abonnement peut expirer pendant la session : on
    // rebascule sur l'écran d'information dès le prochain scan.
    if (_venteInterdite) {
      setState(() {
        _abonnementBloque = true;
        _messageAbonnement =
            AbonnementService.instance.acces.value.message ?? '';
      });
      return;
    }

    final String? brut = capture.barcodes
        .map((Barcode code) => code.rawValue)
        .firstWhere(
          (String? valeur) => valeur != null && valeur.trim().isNotEmpty,
          orElse: () => null,
        );
    if (brut == null) return;

    // Anti-rebond : le même code relu dans la foulée (plusieurs frames
    // successives) est ignoré.
    final DateTime maintenant = DateTime.now();
    if (_dernierCode == brut &&
        _dernierScanAt != null &&
        maintenant.difference(_dernierScanAt!) <
            const Duration(milliseconds: 2500)) {
      return;
    }
    _dernierCode = brut;
    _dernierScanAt = maintenant;
    _traitement = true;

    try {
      final ArticleScanne scanne = await ScannerService.instance.resoudre(brut);
      await _feedbackScanReussi();
      ScannerService.instance.enregistrerScan(scanne);

      if (!mounted) return;
      final bool ajoute = await _ouvrirFicheAjout(scanne) ?? false;
      if (!mounted) return;
      if (ajoute) {
        _afficherRetour('Article ajouté au panier', succes: true);
        unawaited(_vibrationLegere());
      }
    } on ScannerException catch (e) {
      await _feedbackErreur();
      if (!mounted) return;
      _afficherRetour(e.message, succes: false);
    } finally {
      _traitement = false;
    }
  }

  /// Re-scan rapide depuis l'historique : les données (prix, stock) sont
  /// RELUES dans la base avant d'ouvrir la fiche d'ajout.
  Future<void> _reajouter(ArticleScanne entree) async {
    if (_traitement || _abonnementBloque || _accesRefuse) return;
    if (_venteInterdite) {
      setState(() => _abonnementBloque = true);
      return;
    }

    _traitement = true;
    try {
      final ArticleScanne frais =
          await ScannerService.instance.resoudre(entree.code);
      ScannerService.instance.enregistrerScan(frais);

      if (!mounted) return;
      final bool ajoute = await _ouvrirFicheAjout(frais) ?? false;
      if (!mounted) return;
      if (ajoute) {
        _afficherRetour('Article ajouté au panier', succes: true);
        unawaited(_vibrationLegere());
      }
    } on ScannerException catch (e) {
      if (!mounted) return;
      _afficherRetour(e.message, succes: false);
    } finally {
      _traitement = false;
    }
  }

  /// Ouvre la fiche d'ajout au panier ; renvoie `true` si l'article a été
  /// ajouté.
  Future<bool?> _ouvrirFicheAjout(ArticleScanne scanne) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) => _FicheAjoutPanier(article: scanne),
    );
  }

  // ---------------------------------------------------------------------------
  // FEEDBACKS (VISUEL + SONORE)
  // ---------------------------------------------------------------------------

  Future<void> _feedbackScanReussi() async {
    _flash(_vertAccent);
    try {
      await Vibration.vibrate(duration: 70);
    } catch (e) {
      debugPrint('ScannerPage : vibration ignorée ($e)');
    }
    try {
      await _audio.play(AssetSource('sounds/cash_register.mp3'));
    } catch (e) {
      debugPrint('ScannerPage : son ignoré ($e)');
    }
  }

  Future<void> _feedbackErreur() async {
    _flash(_rougeAlerte);
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (e) {
      debugPrint('ScannerPage : alerte ignorée ($e)');
    }
  }

  Future<void> _vibrationLegere() async {
    try {
      await Vibration.vibrate(duration: 40);
    } catch (_) {
      // Appareil sans vibreur : sans conséquence.
    }
  }

  /// Flash coloré très bref au centre de l'écran.
  void _flash(Color couleur) {
    _timerFlash?.cancel();
    if (!mounted) return;
    setState(() => _couleurFlash = couleur);
    _timerFlash = Timer(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _couleurFlash = Colors.transparent);
    });
  }

  /// Bannière de feedback (« Article ajouté », erreur…).
  void _afficherRetour(String message, {required bool succes}) {
    _timerRetour?.cancel();
    if (!mounted) return;
    setState(() {
      _retourMessage = message;
      _retourSucces = succes;
    });
    _timerRetour = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) setState(() => _retourMessage = null);
    });
  }

  /// Ferme le scanner et rend la main à l'écran précédent (la caisse).
  void _terminer() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main/new-sale');
    }
  }

  /// 🔳 MODULE 8 — ouvre le panier pour vérifier la vente puis l'encaisser.
  void _ouvrirPanier() => context.push('/main/panier');

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!_pret) {
      return const Scaffold(
        backgroundColor: _fondSombre,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    if (_accesRefuse) {
      return _EcranInformation(
        icone: Icons.lock_outline_rounded,
        titre: 'Accès non autorisé',
        message:
            'Votre rôle ne permet pas d\'utiliser le scanner. Contactez le '
            'responsable de la boutique.',
        libelleAction: 'Retour aux ventes',
        onAction: _terminer,
      );
    }

    if (_abonnementBloque) {
      return _EcranAbonnementBloque(
        message: _messageAbonnement,
        onRetour: _terminer,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // 1. Caméra plein écran.
          MobileScanner(
            controller: _controleur,
            onDetect: _onDetect,
            errorBuilder: (BuildContext context, MobileScannerException erreur) =>
                _CameraIndisponible(
              message: erreur.errorCode ==
                      MobileScannerErrorCode.permissionDenied
                  ? 'Accès à la caméra refusé. Autorisez la caméra dans les '
                      'réglages du téléphone, puis rouvrez le scanner.'
                  : 'Caméra indisponible sur cet appareil. Utilisez un '
                      'téléphone pour scanner les articles.',
              onFermer: _terminer,
            ),
          ),

          // 2. Voile sombre + cadre de visée + ligne de balayage.
          _buildCadre(context),

          // 3. Flash de feedback (vert = scan, rouge = erreur).
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              color: _couleurFlash == Colors.transparent
                  ? Colors.transparent
                  : _couleurFlash.withValues(alpha: 0.22),
            ),
          ),

          // 4. Barre supérieure (fermer, lampe, caméra opposée).
          _buildBarreHaute(context),

          // 5. Bannière de retour.
          if (_retourMessage != null) _buildBanniereRetour(context),

          // 6. Panier + historique des 5 derniers scans.
          _buildPanneauBas(context),
        ],
      ),
    );
  }

  /// Rectangle de visée avec ligne de balayage animée.
  Widget _buildCadre(BuildContext context) {
    final Size taille = MediaQuery.sizeOf(context);
    final double cote = math.min(_tailleCadre, taille.width - 56);
    final Rect cadre = Rect.fromCenter(
      center: Offset(taille.width / 2, taille.height * _hauteurCadre),
      width: cote,
      height: cote,
    );

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _animationLigne,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _PeintureCadreScan(
            cadre: cadre,
            progression: _animationLigne.value,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildBarreHaute(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Row(
            children: <Widget>[
              _boutonRond(
                icone: Icons.close_rounded,
                infobulle: 'Fermer le scanner',
                onTap: _terminer,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Scanner un article',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ValueListenableBuilder<MobileScannerState>(
                valueListenable: _controleur,
                builder: (BuildContext context, MobileScannerState etat,
                    Widget? child) {
                  final bool lampe = etat.torchState == TorchState.on;
                  return _boutonRond(
                    icone:
                        lampe ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                    infobulle: lampe ? 'Éteindre la lampe' : 'Allumer la lampe',
                    onTap: () => _controleur.toggleTorch(),
                  );
                },
              ),
              const SizedBox(width: 8),
              _boutonRond(
                icone: Icons.cameraswitch_rounded,
                infobulle: 'Changer de caméra',
                onTap: () => _controleur.switchCamera(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _boutonRond({
    required IconData icone,
    required String infobulle,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: infobulle,
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icone, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  Widget _buildBanniereRetour(BuildContext context) {
    final Color couleur = _retourSucces ? _vertBouton : _rougeAlerte;
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 66,
      left: 16,
      right: 16,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: couleur.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(14),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: <Widget>[
              Icon(
                _retourSucces
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _retourMessage ?? '',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Panier en cours + historique des 5 derniers scans.
  Widget _buildPanneauBas(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Colors.transparent, Color(0xE6000000)],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Alignez le QR code dans le cadre — le scan reste actif.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              _buildResumePanier(),
              const SizedBox(height: 12),
              _buildHistorique(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumePanier() {
    return ValueListenableBuilder<int>(
      valueListenable: PanierService.instance.revision,
      builder: (BuildContext context, int revision, Widget? child) {
        final PanierService panier = PanierService.instance;
        return Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.shopping_cart_rounded,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    panier.estVide
                        ? 'Panier vide'
                        : '${panier.nombreLignes} ligne(s) · '
                            '${formatMontant(panier.total())}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (!panier.estVide)
              FilledButton.icon(
                onPressed: _ouvrirPanier,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.shopping_cart_checkout_rounded, size: 18),
                label: const Text(
                  'Voir le panier',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildHistorique() {
    return ValueListenableBuilder<List<ArticleScanne>>(
      valueListenable: ScannerService.instance.historique,
      builder: (BuildContext context, List<ArticleScanne> entrees,
          Widget? child) {
        if (entrees.isEmpty) {
          return const Text(
            'Les 5 derniers scans s\'afficheront ici.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '5 derniers scans',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: entrees.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 10),
                itemBuilder: (BuildContext context, int index) =>
                    _carteHistorique(entrees[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _carteHistorique(ArticleScanne entree) {
    return Container(
      width: 196,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            entree.nom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            entree.estConditionnement
                ? entree.libelleConditionnement
                : entree.uniteVente,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const Spacer(),
          Row(
            children: <Widget>[
              Text(
                formatMontant(entree.prixUnitaire),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (entree.enRupture)
                const Text(
                  'Rupture',
                  style: TextStyle(
                    color: _rougeAlerte,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                SizedBox(
                  width: 30,
                  height: 30,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    tooltip: 'Re-ajouter au panier',
                    icon: const Icon(Icons.add_circle_rounded,
                        color: _vertAccent),
                    onPressed: () => _reajouter(entree),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// FICHE D'AJOUT AU PANIER (POPUP APRÈS SCAN)
// ===========================================================================

/// Fiche « Ajouter au panier » : prix réel, stock, quantité, sous-total.
class _FicheAjoutPanier extends StatefulWidget {
  const _FicheAjoutPanier({required this.article});

  final ArticleScanne article;

  @override
  State<_FicheAjoutPanier> createState() => _FicheAjoutPanierState();
}

class _FicheAjoutPanierState extends State<_FicheAjoutPanier> {
  late final TextEditingController _quantiteControleur;
  double _quantite = 1;
  String? _erreur;

  /// 🧾 MULTI-FORMATS — autres formats de vente de l'article (plaquette,
  /// sachet, carton…) avec leur propre prix. Quand l'article scanné est
  /// l'unité de base, l'utilisateur peut basculer d'un format à l'autre.
  List<Conditionnement> _formats = const <Conditionnement>[];
  Conditionnement? _choix;

  /// Article effectivement vendu (unité de base ou format retenu).
  ArticleScanne get _article => _choix == null
      ? widget.article
      : ArticleScanne(article: widget.article.article, conditionnement: _choix);

  /// `true` quand le rôle connecté peut remplir le panier (VENDEUR : oui).
  bool get _peutVendre =>
      PermissionService.instance.peut(PageAccess.panier, ActionAccess.creer);

  @override
  void initState() {
    super.initState();
    final double maximum = _article.quantiteMaxVendable;
    // Stock plus petit que 1 (ex. « 0,5 kg ») : la quantité par défaut est le
    // maximum vendable.
    _quantite = maximum > 0 && maximum < 1 ? maximum : 1;
    _quantiteControleur = TextEditingController(
      text: _texteQuantite(_quantite),
    );
    _chargerFormats();
  }

  /// Charge les autres formats de vente de l'article (best-effort : hors
  /// ligne, on reste sur l'unité de base).
  Future<void> _chargerFormats() async {
    if (widget.article.conditionnement != null) return;
    try {
      final Article? article =
          await ArticleService.instance.getArticleById(widget.article.produitId);
      if (!mounted) return;
      setState(() {
        _formats = article?.conditionnements ?? const <Conditionnement>[];
      });
    } catch (_) {
      // Sans réseau, on garde l'unité de base : la vente n'est pas bloquée.
    }
  }

  /// Bascule vers un format (ou revient à l'unité de base).
  void _choisirFormat(Conditionnement? format) {
    setState(() {
      _choix = format;
      final double pas = _article.pasQuantite;
      final double maximum = _article.quantiteMaxVendable;
      double q = 1;
      if (maximum > 0 && maximum < q) q = maximum;
      if (q < pas) q = pas;
      _quantite = q;
      _erreur = null;
      _quantiteControleur.text = _texteQuantite(q);
    });
  }

  @override
  void dispose() {
    _quantiteControleur.dispose();
    super.dispose();
  }

  // --- saisie de la quantité -------------------------------------------------

  static double? _analyser(String texte) {
    final String propre = texte.trim().replaceAll(',', '.');
    if (propre.isEmpty) return null;
    return double.tryParse(propre);
  }

  static String _texteQuantite(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur
        .toStringAsFixed(2)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  void _saisieQuantite(String texte) {
    final double? valeur = _analyser(texte);
    setState(() {
      if (valeur == null || valeur <= 0) {
        _erreur = 'Quantité invalide.';
        return;
      }
      final double maximum = _article.quantiteMaxVendable;
      if (maximum > 0 && valeur > maximum) {
        _erreur = 'Stock insuffisant : maximum '
            '${_texteQuantite(maximum)} ${_article.uniteVentePlurielle(maximum)}.';
        return;
      }
      _erreur = null;
      _quantite = valeur;
    });
  }

  void _ajuster(double delta) {
    final double maximum = _article.quantiteMaxVendable;
    double valeur = _quantite + delta;
    // 🥩 MODULE 16 C6 — article pesé : minimum 0,5 kg ; sinon 1 unité.
    final double minimum = _article.pasQuantite;
    if (valeur < minimum) valeur = minimum;
    if (maximum > 0 && valeur > maximum) valeur = maximum;
    setState(() {
      _quantite = valeur;
      _erreur = null;
      _quantiteControleur.text = _texteQuantite(valeur);
    });
  }

  void _ajouter() {
    final double? valeur = _analyser(_quantiteControleur.text);
    if (valeur == null || valeur <= 0) {
      setState(() => _erreur = 'Quantité invalide.');
      return;
    }
    final double maximum = _article.quantiteMaxVendable;
    if (maximum > 0 && valeur > maximum) {
      setState(() {
        _erreur = 'Stock insuffisant : maximum '
            '${_texteQuantite(maximum)} ${_article.uniteVentePlurielle(maximum)}.';
      });
      return;
    }

    PanierService.instance.ajouterArticle(_article, quantite: valeur);
    Navigator.of(context).pop(true);
  }

  // --- interface -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final double maximum = _article.quantiteMaxVendable;
    final bool rupture = _article.enRupture;
    final bool ajoutPossible =
        !rupture && _erreur == null && _peutVendre;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF16181D),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // Poignée.
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

                _buildEntete(),
                const SizedBox(height: 16),
                if (_formats.isNotEmpty) ...<Widget>[
                  _buildFormats(),
                  const SizedBox(height: 14),
                ],
                _buildPrix(),
                const SizedBox(height: 12),
                _buildStock(),

                if (rupture) ...<Widget>[
                  const SizedBox(height: 12),
                  _buildAvertissementRupture(),
                ],

                const SizedBox(height: 16),
                _buildQuantite(rupture: rupture, maximum: maximum),
                if (_erreur != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    _erreur!,
                    style: const TextStyle(color: _rougeAlerte, fontSize: 12),
                  ),
                ],

                const SizedBox(height: 18),
                _buildSousTotal(),
                const SizedBox(height: 18),
                _buildBoutonAjout(ajoutPossible: ajoutPossible, rupture: rupture),
                if (!_peutVendre) ...<Widget>[
                  const SizedBox(height: 10),
                  const Text(
                    'Votre rôle ne permet pas d\'ajouter des articles au '
                    'panier.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntete() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 56,
            height: 56,
            color: Colors.white10,
            child: _vignette(),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _article.nom,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_article.estConditionnement) ...<Widget>[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${_article.libelleConditionnement} · '
                    '${_texteQuantite(_article.unitesBaseParVente)} '
                    '${pluriel(_article.article.uniteMesure, _article.unitesBaseParVente)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _vignette() {
    final String? photo = _article.article.photo;
    if (photo != null && photo.startsWith('http')) {
      return Image.network(
        photo,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object erreur,
                StackTrace? trace) =>
            const Icon(Icons.inventory_2_rounded, color: Colors.white24),
      );
    }
    return const Icon(Icons.inventory_2_rounded, color: Colors.white24);
  }

  /// 🧾 Chips des formats de vente (unité de base + emballages).
  Widget _buildFormats() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Format de vente',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _chipFormat(null),
            for (final Conditionnement c in _formats) _chipFormat(c),
          ],
        ),
      ],
    );
  }

  Widget _chipFormat(Conditionnement? format) {
    final bool selectionne = _choix?.id == format?.id;
    final String libelle = format == null
        ? '${_article.article.uniteMesure} · '
            '${formatMontant(_article.article.prixVente)}'
        : '${format.libelle} · ${formatMontant(format.prixVente)}';
    return ChoiceChip(
      selected: selectionne,
      onSelected: (_) => _choisirFormat(format),
      label: Text(libelle, style: const TextStyle(fontSize: 12)),
      selectedColor: _vertAccent.withValues(alpha: 0.25),
      labelStyle: TextStyle(
        color: selectionne ? _vertAccent : Colors.white70,
        fontWeight: selectionne ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
        color: selectionne ? _vertAccent : Colors.white24,
      ),
    );
  }

  Widget _buildPrix() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              _article.prixUnitaireTexte(),
              style: const TextStyle(
                color: _vertAccent,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                '/ ${_article.uniteVente}',
                style: const TextStyle(color: Colors.white54, fontSize: 12.5),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Row(
          children: <Widget>[
            Icon(Icons.cloud_done_rounded, color: Colors.white38, size: 13),
            SizedBox(width: 5),
            Text(
              'Prix actuel lu dans la base de données (non modifiable)',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        // 🥩 MODULE 16 C6 — boucherie : rappel de la vente au poids.
        if (_article.vendableAuPoids) ...<Widget>[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _vertAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _vertAccent.withValues(alpha: 0.4)),
            ),
            child: const Text(
              '🥩 Vendu au poids — indiquez le poids en kg (ex. 0,75)',
              style: TextStyle(
                color: _vertAccent,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.inventory_2_outlined, color: Colors.white54, size: 16),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _article.resumeStock(),
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvertissementRupture() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _rougeAlerte.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _rougeAlerte.withValues(alpha: 0.45)),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: _rougeAlerte, size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Rupture de stock : cet article ne peut pas être vendu pour le '
              'moment.',
              style: TextStyle(color: Color(0xFFFFCDD2), fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantite({required bool rupture, required double maximum}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Text(
              'Quantité',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _boutonPas(
              icone: Icons.remove_rounded,
              actif: !rupture && _quantite > _article.pasQuantite,
              onTap: () => _ajuster(-_article.pasQuantite),
            ),
            SizedBox(
              width: 92,
              child: TextField(
                controller: _quantiteControleur,
                enabled: !rupture,
                onChanged: _saisieQuantite,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.07),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            _boutonPas(
              icone: Icons.add_rounded,
              actif: !rupture && _quantite < maximum,
              onTap: () => _ajuster(_article.pasQuantite),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          rupture
              ? 'Vente impossible tant que le stock n\'est pas réapprovisionné.'
              : 'Maximum vendable : ${_texteQuantite(maximum)} '
                  '${_article.uniteVentePlurielle(maximum)}.',
          style: const TextStyle(color: Colors.white38, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _boutonPas({
    required IconData icone,
    required bool actif,
    required VoidCallback onTap,
  }) {
    return Material(
      color: actif ? Colors.white12 : Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: actif ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            icone,
            size: 19,
            color: actif ? Colors.white : Colors.white24,
          ),
        ),
      ),
    );
  }

  Widget _buildSousTotal() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        const Text(
          'Sous-total',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          _article.sousTotalTexte(_quantite),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildBoutonAjout({
    required bool ajoutPossible,
    required bool rupture,
  }) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: ajoutPossible ? _ajouter : null,
        style: FilledButton.styleFrom(
          backgroundColor: _vertBouton,
          disabledBackgroundColor: Colors.white12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.add_shopping_cart_rounded),
        label: Text(
          rupture ? 'Rupture de stock' : 'Ajouter au panier',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }
}

// ===========================================================================
// ÉCRANS D'INFORMATION (BLOCAGE)
// ===========================================================================

/// Écran d'information générique (accès refusé…).
class _EcranInformation extends StatelessWidget {
  const _EcranInformation({
    required this.icone,
    required this.titre,
    required this.message,
    required this.libelleAction,
    required this.onAction,
  });

  final IconData icone;
  final String titre;
  final String message;
  final String libelleAction;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondSombre,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icone, color: Colors.white54, size: 64),
                const SizedBox(height: 20),
                Text(
                  titre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                  ),
                  child: Text(libelleAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 🚫 MODULE 3 — Abonnement EXPIRE / suspendu : le scan est bloqué et cet
/// écran d'information l'explique au vendeur.
class _EcranAbonnementBloque extends StatelessWidget {
  const _EcranAbonnementBloque({
    required this.message,
    required this.onRetour,
  });

  final String message;
  final VoidCallback onRetour;

  Future<void> _contacter() async {
    final Uri whatsapp = Uri.parse('https://wa.me/243974084668');
    try {
      await launchUrl(whatsapp, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('ScannerPage : ouverture WhatsApp impossible ($e)');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondSombre,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: _rougeAlerte.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_clock_rounded,
                    color: _rougeAlerte,
                    size: 54,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Scanner indisponible',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message.isEmpty
                      ? 'L\'abonnement de votre entreprise est échu. Les '
                          'ventes sont bloquées jusqu\'au renouvellement.'
                      : message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14.5),
                ),
                const SizedBox(height: 10),
                const Text(
                  'La consultation reste possible ; seul le scan des ventes '
                  'est interdit.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white38, fontSize: 12.5),
                ),
                const SizedBox(height: 26),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _contacter,
                    style: FilledButton.styleFrom(
                      backgroundColor: _vertBouton,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text(
                      'Contacter la plateforme',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: onRetour,
                  child: const Text(
                    'Retour aux ventes',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Message affiché quand la caméra ne peut pas démarrer (permission refusée,
/// appareil sans caméra…).
class _CameraIndisponible extends StatelessWidget {
  const _CameraIndisponible({
    required this.message,
    required this.onFermer,
  });

  final String message;
  final VoidCallback onFermer;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _fondSombre,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.no_photography_rounded,
                  color: Colors.white38,
                  size: 64,
                ),
                const SizedBox(height: 18),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: onFermer,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text('Fermer'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// DESSIN DU CADRE DE VISÉE
// ===========================================================================

/// Voile sombre percé d'un carré clair, coins blancs + ligne de balayage.
class _PeintureCadreScan extends CustomPainter {
  const _PeintureCadreScan({required this.cadre, required this.progression});

  final Rect cadre;
  final double progression;

  @override
  void paint(Canvas canvas, Size size) {
    // Voile avec découpe (even-odd : le carré reste transparent).
    final Path voile = Path()
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(cadre, const Radius.circular(22)));
    voile.fillType = PathFillType.evenOdd;
    canvas.drawPath(voile, Paint()..color = const Color(0xB8000000));

    // Coins blancs.
    const double coin = 26;
    final Path coins = Path()
      ..moveTo(cadre.left, cadre.top + coin)
      ..lineTo(cadre.left, cadre.top)
      ..lineTo(cadre.left + coin, cadre.top)
      ..moveTo(cadre.right - coin, cadre.top)
      ..lineTo(cadre.right, cadre.top)
      ..lineTo(cadre.right, cadre.top + coin)
      ..moveTo(cadre.right, cadre.bottom - coin)
      ..lineTo(cadre.right, cadre.bottom)
      ..lineTo(cadre.right - coin, cadre.bottom)
      ..moveTo(cadre.left + coin, cadre.bottom)
      ..lineTo(cadre.left, cadre.bottom)
      ..lineTo(cadre.left, cadre.bottom - coin);
    canvas.drawPath(
      coins,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    // Ligne de balayage (avec halo).
    final double y = cadre.top + 14 + (cadre.height - 28) * progression;
    final Offset debut = Offset(cadre.left + 18, y);
    final Offset fin = Offset(cadre.right - 18, y);
    canvas.drawLine(
      debut,
      fin,
      Paint()
        ..color = _vertAccent
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(
      debut,
      fin,
      Paint()
        ..color = const Color(0xFFB9F6CA)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_PeintureCadreScan ancienne) =>
      ancienne.progression != progression || ancienne.cadre != cadre;
}
