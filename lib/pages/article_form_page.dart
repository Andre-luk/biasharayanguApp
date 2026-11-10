// lib/pages/article_form_page.dart
//
// MODULE 5 — ÉCRAN « CRÉER / MODIFIER UN ARTICLE »
//
//   • champs : nom, catégorie, unité de base, prix d'achat, prix de vente,
//     quantité en stock (unité de base), photo (optionnelle), description ;
//   • section « Conditionnements » : liste des emballages existants + bouton
//     « Ajouter un conditionnement ».

import 'package:biashara_yangu/utils/image_locale.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/devise.dart';
import 'package:biashara_yangu/services/devise_service.dart';
import 'package:biashara_yangu/utils/devise_produit.dart';
import 'package:biashara_yangu/models/categorie.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/module_activite.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/statut_expiration.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/code_barre_nom_service.dart';
import 'package:biashara_yangu/services/image_service.dart';
// 🧩 MODULE 16 C1 — les champs lot/date n'apparaissent que si l'activité
// a le module « lots_expiration » (pharmacie, alimentation, dépôt…).
import 'package:biashara_yangu/services/mode_application_service.dart';
import 'package:biashara_yangu/services/modules_service.dart';
import 'package:biashara_yangu/services/peremption_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/code_barre_lecteur.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Valeur technique de l'entrée « Nouvelle catégorie » de la liste déroulante.
const String _valeurNouvelleCategorie = '__nouvelle_categorie__';

class ArticleFormPage extends StatefulWidget {
  const ArticleFormPage({super.key, this.article, this.articleId});

  /// Article à modifier (passé en `extra` par la liste ou le détail).
  final Article? article;

  /// Identifiant de l'article quand on arrive par URL.
  final String? articleId;

  @override
  State<ArticleFormPage> createState() => _ArticleFormPageState();
}

class _ArticleFormPageState extends State<ArticleFormPage> {
  final ArticleService _service = ArticleService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nomController = TextEditingController();
  final TextEditingController _uniteController = TextEditingController();
  final TextEditingController _prixAchatController = TextEditingController();
  final TextEditingController _prixVenteController = TextEditingController();

  /// 💵 MODULE 29 — devise du prix de l'article (`null` = celle de
  /// l'entreprise). Un article peut être prixé en dollars dans une boutique
  /// qui tient ses comptes en francs.
  Devise? _deviseChoisie;

  /// ♾️ MODULE 31 — l'article se vend sans suivi de stock.
  bool _sansStock = false;
  final TextEditingController _quantiteController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // 🏷️ CORRECTIF 59 — code-barres fabricant du produit (EAN-13, UPC…).
  final TextEditingController _codeBarreController = TextEditingController();

  // 🧩 MODULE 16 C1 — pharmacie : lot & date de péremption.
  final TextEditingController _lotController = TextEditingController();
  DateTime? _dateExpiration;

  /// 🧮 CORRECTIF 72 — délai d'alerte RÉGLÉ PAR LA BOUTIQUE.
  ///
  /// La bande d'avertissement de ce formulaire doit dire la MÊME chose que la
  /// liste et l'écran Expirations : un produit annoncé « expire bientôt » ici
  /// doit l'être partout, sinon l'avertissement perd toute autorité.
  int _delaiPeremption = PeremptionService.delaiParDefaut;

  // 🥩 MODULE 16 C6 — boucherie : article vendu au poids (kg).
  bool _vendableAuPoids = false;

  // 👕 MODULE 16 C8 — mode : variantes simples (taille, couleur, marque).
  final TextEditingController _tailleController = TextEditingController();
  final TextEditingController _couleurController = TextEditingController();
  final TextEditingController _marqueController = TextEditingController();

  List<Categorie> _categories = const <Categorie>[];
  String _categorieSelectionnee = '';

  String? _photoUrl; // photo déjà enregistrée (URL Supabase Storage)
  String? _photoLocale; // nouvelle photo choisie sur l'appareil
  bool _photoSupprimee = false;

  Article? _article;
  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreurChargement;

  /// 🏷️ Une recherche de nom est en cours après un scan.
  bool _rechercheCode = false;

  bool get _estModification => _article != null;

  @override
  void initState() {
    super.initState();
    _initialiser();
    _chargerDelaiPeremption();
  }

  /// 🧮 CORRECTIF 72 — best-effort : si la lecture échoue, on garde le délai
  /// par défaut (30 jours), celui qui avait cours avant le correctif.
  Future<void> _chargerDelaiPeremption() async {
    final int delai = await PeremptionService.instance.charger();
    if (!mounted || delai == _delaiPeremption) return;
    setState(() => _delaiPeremption = delai);
  }

  @override
  void dispose() {
    _nomController.dispose();
    _uniteController.dispose();
    _prixAchatController.dispose();
    _prixVenteController.dispose();
    _quantiteController.dispose();
    _descriptionController.dispose();
    _codeBarreController.dispose();
    _lotController.dispose();
    _tailleController.dispose();
    _couleurController.dispose();
    _marqueController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _initialiser() async {
    Article? article = widget.article;

    if (article == null && widget.articleId != null) {
      final int? id = int.tryParse(widget.articleId!);
      if (id != null) {
        try {
          article = await _service.getArticleById(id);
        } on ArticleServiceException catch (e) {
          if (mounted) {
            setState(() {
              _erreurChargement = e.message;
              _chargement = false;
            });
          }
          return;
        }
      }
    }

    List<Categorie> categories = const <Categorie>[];
    try {
      categories = await _service.getCategories();
    } on ArticleServiceException catch (e) {
      debugPrint('ArticleFormPage catégories (ignoré): ${e.message}');
    }

    if (!mounted) return;

    setState(() {
      _article = article;
      _categories = categories;

      if (article != null) {
        _nomController.text = article.nom;
        _uniteController.text = article.uniteMesure;
        _prixAchatController.text = _champNombre(article.prixAchat);
        _prixVenteController.text = _champNombre(article.prixVente);
    _deviseChoisie = (article.devise ?? '').trim().isEmpty
        ? null
        : Devise.fromCode(article.devise);
    _sansStock = article.stockIllimite;
        _quantiteController.text = _champNombre(article.quantite);
        _descriptionController.text = article.description ?? '';
        _codeBarreController.text = article.codeBarre ?? '';
        _lotController.text = article.lotNumero ?? '';
        _dateExpiration = article.dateExpiration;
        _vendableAuPoids = article.vendableAuPoids;
        // 👕 MODULE 16 C8 — variantes connues (les clés libres éventuelles
        // d'un article importé sont conservées à l'enregistrement).
        _tailleController.text = article.attributs['taille'] ?? '';
        _couleurController.text = article.attributs['couleur'] ?? '';
        _marqueController.text = article.attributs['marque'] ?? '';
        _categorieSelectionnee = article.categorie.trim();
        _photoUrl = article.photo;
      }

      _chargement = false;
    });
  }

  // ---------------------------------------------------------------------------
  // 🏷️ CODE-BARRES → NOM DU PRODUIT
  // ---------------------------------------------------------------------------
  //
  //  Le commerçant braque la caméra sur l'emballage : le code est enregistré
  //  ET le nom s'écrit tout seul.
  //
  //  1. Le code appartient déjà à un article de SA boutique → nom, unité et
  //     prix sont repris (remplissage direct, aucune question).
  //  2. Le code est inconnu de la boutique → on interroge une base publique et
  //     on PROPOSE un nom : un appui sur « Utiliser » et il est écrit.
  //  3. Rien n'est trouvé (hors ligne, produit très local) → le code reste
  //     enregistré et le commerçant saisit le nom, comme avant.
  //
  //  ⚠️ Aucun champ déjà rempli n'est écrasé : ce qui a été saisi à la main
  //     reste la priorité du commerçant.

  Future<void> _codeBarreLu(String code) async {
    FocusScope.of(context).unfocus();
    final String brut = code.trim();
    if (brut.isEmpty) return;

    setState(() => _rechercheCode = true);

    // 1. Notre propre catalogue (fonctionne hors ligne grâce au cache local).
    Article? connu;
    try {
      connu = await _service.trouverParCodeBarre(brut);
    } on ArticleServiceException catch (e) {
      debugPrint('ArticleFormPage — recherche code-barres ignorée : ${e.message}');
    } catch (e) {
      debugPrint('ArticleFormPage — recherche code-barres ignorée : $e');
    }

    if (!mounted) return;

    if (connu != null) {
      _appliquerNomConnu(connu);
      setState(() => _rechercheCode = false);
      _message(
        '« ${connu.nom} » reconnu : les champs vides ont été complétés.',
      );
      return;
    }

    // 2. Base publique : seulement une PROPOSITION, jamais une écriture dictée.
    final String? suggestion =
        await CodeBarreNomService.instance.nomProbable(brut);

    if (!mounted) return;
    setState(() => _rechercheCode = false);

    if (suggestion == null || suggestion.trim().isEmpty) {
      _message(
        'Code-barres enregistré. Nouveau produit : saisissez son nom — '
        'il sera reconnu automatiquement la prochaine fois.',
      );
      return;
    }

    if (_nomController.text.trim().isNotEmpty) {
      _message('Code-barres enregistré.');
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('Nom trouvé : « $suggestion »'),
        action: SnackBarAction(
          label: 'Utiliser',
          onPressed: () {
            if (!mounted) return;
            setState(() => _nomController.text = suggestion);
          },
        ),
      ),
    );
  }

  /// Recopie les informations d'un article déjà connu (sans rien écraser).
  void _appliquerNomConnu(Article article) {
    setState(() {
      if (_nomController.text.trim().isEmpty) {
        _nomController.text = article.nom;
      }
      if (_uniteController.text.trim().isEmpty) {
        _uniteController.text = article.uniteMesure;
      }
      final String prixActuel = _prixVenteController.text.trim();
      if (prixActuel.isEmpty || _lireNombre(prixActuel) == 0) {
        _prixVenteController.text = _champNombre(article.prixVente);
      }
    });
  }

  void _message(String texte) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Recharge l'article (après ajout / modification / suppression d'un
  /// conditionnement) en conservant la saisie en cours du formulaire.
  Future<void> _rechargerArticle() async {    final Article? article = _article;
    if (article == null) return;

    try {
      final Article? actualise = await _service.getArticleById(article.id);
      if (!mounted || actualise == null) return;
      setState(() => _article = actualise);
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // SAISIE
  // ---------------------------------------------------------------------------

  String _champNombre(double valeur) {
    if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
    return valeur.toString();
  }

  double _lireNombre(String texte, {double fallback = 0}) {
    final String propre = texte.trim().replaceAll(',', '.');
    if (propre.isEmpty) return fallback;
    return double.tryParse(propre) ?? fallback;
  }

  // ---------------------------------------------------------------------------
  // PHOTO
  // ---------------------------------------------------------------------------

  Future<void> _choisirPhoto() async {
    final String? choix = await showModalBottomSheet<String>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galerie'),
              onTap: () => Navigator.pop(ctx, 'galerie'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Caméra'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Annuler'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choix == null) return;

    final String? chemin = choix == 'camera'
        ? await ImageService.pickFromCamera()
        : await ImageService.pickFromGallery();

    if (!mounted || chemin == null) return;

    setState(() {
      _photoLocale = chemin;
      _photoSupprimee = false;
    });
  }

  void _retirerPhoto() {
    setState(() {
      _photoLocale = null;
      _photoUrl = null;
      _photoSupprimee = true;
    });
  }

  Widget _apercuPhoto() {
    const double taille = 96;

    if (_photoLocale != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageFichierLocal(
          _photoLocale!,
          width: taille,
          height: taille,
          fit: BoxFit.cover,
        ),
      );
    }

    final String? url = _photoSupprimee ? null : _photoUrl;
    if (url != null && url.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          url,
          width: taille,
          height: taille,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _zonePhotoVide(taille),
        ),
      );
    }

    return _zonePhotoVide(taille);
  }

  Widget _zonePhotoVide(double taille) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.add_a_photo_outlined,
        size: taille * 0.4,
        color: colorScheme.primary,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CATÉGORIES
  // ---------------------------------------------------------------------------

  List<DropdownMenuItem<String>> get _itemsCategories {
    final List<DropdownMenuItem<String>> items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(value: '', child: Text('Sans catégorie')),
    ];

    for (final Categorie categorie in _categories) {
      items.add(DropdownMenuItem<String>(
        value: categorie.nom,
        child:
            Text(categorie.nom, maxLines: 1, overflow: TextOverflow.ellipsis),
      ));
    }

    // Une catégorie saisie sur l'article mais absente du référentiel reste
    // sélectionnable (données historiques).
    if (_categorieSelectionnee.isNotEmpty &&
        !_categories.any((Categorie c) =>
            Categorie.normaliser(c.nom) ==
            Categorie.normaliser(_categorieSelectionnee))) {
      items.add(DropdownMenuItem<String>(
        value: _categorieSelectionnee,
        child: Text(_categorieSelectionnee,
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ));
    }

    items.add(const DropdownMenuItem<String>(
      value: _valeurNouvelleCategorie,
      child: Text('＋ Nouvelle catégorie…'),
    ));

    return items;
  }

  Future<void> _creerCategorie() async {
    final TextEditingController controller = TextEditingController();
    String? nom;

    try {
      nom = await showDialog<String>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: const Text('Nouvelle catégorie'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Nom de la catégorie'),
            onSubmitted: (String valeur) => Navigator.pop(ctx, valeur.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Créer'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }

    if (!mounted || nom == null || nom.trim().isEmpty) {
      // Retour à l'état précédent de la liste déroulante.
      setState(() {});
      return;
    }

    try {
      final Categorie creee = await _service.creerCategorie(nom);
      if (!mounted) return;
      setState(() {
        _categories = <Categorie>[..._categories, creee]
          ..sort((Categorie a, Categorie b) => a.nom.compareTo(b.nom));
        _categorieSelectionnee = creee.nom;
      });
      _afficherMessage('Catégorie « ${creee.nom} » créée.');
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    }
  }

  // ---------------------------------------------------------------------------
  // CONDITIONNEMENTS
  // ---------------------------------------------------------------------------

  Future<void> _ajouterConditionnement() async {
    final Article? article = _article;
    if (article == null) return;

    final bool? cree = await context
        .push<bool>('/main/articles/${article.id}/conditionnements/new');
    if (cree == true) await _rechargerArticle();
  }

  Future<void> _modifierConditionnement(Conditionnement conditionnement) async {
    final Article? article = _article;
    if (article == null) return;

    final bool? modifie = await context.push<bool>(
      '/main/articles/${article.id}/conditionnements/${conditionnement.id}/edit',
      extra: conditionnement,
    );
    if (modifie == true) await _rechargerArticle();
  }

  // ---------------------------------------------------------------------------
  // 🧩 MODULE 16 C1 — PHARMACIE : LOT & PÉREMPTION
  // ---------------------------------------------------------------------------

  /// Ouvre le calendrier pour choisir la date de péremption.
  Future<void> _choisirDateExpiration() async {
    final DateTime maintenant = DateTime.now();
    final DateTime? choix = await showDatePicker(
      context: context,
      initialDate: _dateExpiration ?? maintenant,
      firstDate: DateTime(maintenant.year - 5),
      lastDate: DateTime(maintenant.year + 10),
      helpText: 'Date de péremption',
    );
    if (!mounted || choix == null) return;
    setState(() => _dateExpiration = choix);
  }

  static String _libelleDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Section « Lot & péremption » (module lots_expiration actif uniquement).
  Widget _sectionLotsEtExpiration() {
    final ThemeData theme = Theme.of(context);
    final StatutExpiration? statut = StatutExpiration.depuis(_dateExpiration,
        joursProches: _delaiPeremption);
    final int? jours = StatutExpiration.joursRestants(_dateExpiration);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.science_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Text(
              'Lot & péremption',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _lotController,
          textCapitalization: TextCapitalization.characters,
          decoration: _decoration(
            'Numéro de lot (optionnel)',
            hint: 'Ex. : LOT-2026-A17',
            icone: Icons.tag_outlined,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _choisirDateExpiration,
          child: InputDecorator(
            decoration: _decoration(
              'Date de péremption (optionnelle)',
              icone: Icons.event_outlined,
            ).copyWith(
              suffixIcon: _dateExpiration == null
                  ? const Icon(Icons.calendar_month_outlined)
                  : IconButton(
                      tooltip: 'Effacer la date',
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(() => _dateExpiration = null),
                    ),
            ),
            child: Text(
              _dateExpiration == null
                  ? 'Aucune date'
                  : _libelleDate(_dateExpiration!),
              style: TextStyle(
                fontSize: 15,
                color: _dateExpiration == null
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ),
        if (statut == StatutExpiration.expire) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: Colors.red.shade700),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Produit EXPIRÉ (${StatutExpiration.libelleJours(jours)}) — '
                  'la vente sera refusée en caisse.',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                ),
              ),
            ],
          ),
        ] else if (statut == StatutExpiration.proche) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 16, color: Colors.orange.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Expire bientôt (${StatutExpiration.libelleJours(jours)}).',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // 🥩 MODULE 16 C6 — BOUCHERIE : VENTE AU POIDS
  // ---------------------------------------------------------------------------

  /// Section « Vente au poids » (module pesee actif uniquement).
  Widget _sectionVenteAuPoids() {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SwitchListTile(
          value: _vendableAuPoids,
          onChanged: (bool valeur) {
            setState(() {
              _vendableAuPoids = valeur;
              // Un article pesé se mesure en kg : on pré-remplit l'unité.
              if (valeur && _uniteController.text.trim().isEmpty) {
                _uniteController.text = 'kg';
              }
            });
          },
          secondary: const Icon(Icons.scale_rounded),
          title: const Text(
            'Vendu au poids (kg)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            'La caisse proposera la saisie du poids (0,75 kg, pas de '
            '0,5 kg) et le prix indiqué sera le prix AU KILO. '
            'L\'unité de base doit être « kg ».',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
    );
  }

  // 👕 MODULE 16 C8 — MODE : VARIANTES (TAILLE / COULEUR / MARQUE)
  // ---------------------------------------------------------------------------

  /// Section « Variantes » (module variantes actif uniquement).
  ///
  /// Chaque variante reste un ARTICLE à part entière : ces champs servent à
  /// retrouver la fiche (recherche « bleu », « M »…) et à l'afficher.
  Widget _sectionVariantes() {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.palette_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Variantes (mode)',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Taille, couleur, marque… : créez un article PAR variante '
              '(ex. « Chemise — M / Bleu ») — ces champs accélèrent la '
              'recherche et l\'affichage.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _tailleController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: _decoration('Taille',
                        hint: 'S, M, L, 42…', icone: Icons.straighten_rounded),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _couleurController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _decoration('Couleur',
                        hint: 'Bleu, Noir…', icone: Icons.color_lens_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _marqueController,
              textCapitalization: TextCapitalization.words,
              decoration: _decoration('Marque (optionnelle)',
                  hint: 'Casino, Nike…', icone: Icons.sell_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionConditionnements() {
    final Article? article = _article;
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Conditionnements',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              "Emballages vendables (farde, carton…). Leur prix est libre : "
              "il peut différer du prix de base × quantité.",
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (article == null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Text(
                  "Enregistrez d'abord l'article pour lui ajouter des conditionnements.",
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ] else if (article.conditionnements.isEmpty) ...[
              Text(
                'Aucun conditionnement pour le moment.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey.shade600),
              ),
            ] else ...[
              ...article.conditionnements.map(
                (Conditionnement conditionnement) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.qr_code_2_rounded),
                  title: Text(conditionnement.libelle),
                  subtitle: Text(
                    '= ${_champNombre(conditionnement.quantiteUnitesBase)} '
                    '${conditionnement.quantiteUnitesBase > 1 ? Conditionnement.pluriel(article.uniteMesure, conditionnement.quantiteUnitesBase) : article.uniteMesure}'
                    ' · ${prixArticle(conditionnement.prixVente, article.devise)}',
                  ),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: () => _modifierConditionnement(conditionnement),
                ),
              ),
            ],
            const SizedBox(height: 8),
            PermissionGate(
              page: PageAccess.articles,
              action: ActionAccess.creer,
              child: OutlinedButton.icon(
                onPressed: article == null ? null : _ajouterConditionnement,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter un conditionnement'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  Future<void> _enregistrer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _enregistrement = true);
    FocusScope.of(context).unfocus();

    try {
      String? photo = _photoSupprimee ? null : _photoUrl;
      if (_photoLocale != null) {
        photo = await _service.televerserPhoto(_photoLocale!);
      }

      final String nom = _nomController.text.trim();
      // ⚡ MODE RAPIDE : le champ « unité » est masqué. On retombe sur
      // « pièce » (le cas courant) au lieu d'enregistrer une unité vide.
      String unite = _uniteController.text.trim();
      if (unite.isEmpty) unite = 'pièce';
      final double prixAchat = _lireNombre(_prixAchatController.text);
      final double prixVente = _lireNombre(_prixVenteController.text);
      final double quantite = _lireNombre(_quantiteController.text);
      final String description = _descriptionController.text.trim();
      // 🏷️ CORRECTIF 59 — code-barres fabricant du produit.
      final String codeBarre = _codeBarreController.text.trim();
      // 🧩 MODULE 16 C1 — pharmacie : lot & date de péremption (les valeurs
      // d'un article existant sont conservées même si le module est inactif,
      // car les champs sont initialisés depuis l'article).
      final String lotNumero = _lotController.text.trim();

      // 👕 MODULE 16 C8 — variantes : on part des attributs existants pour
      // ne jamais effacer une clé non gérée par ce formulaire.
      final Map<String, String> attributs = Map<String, String>.from(
          _article?.attributs ?? const <String, String>{});
      void poserAttribut(String cle, String valeur) {
        if (valeur.isEmpty) {
          attributs.remove(cle);
        } else {
          attributs[cle] = valeur;
        }
      }

      poserAttribut('taille', _tailleController.text.trim());
      poserAttribut('couleur', _couleurController.text.trim());
      poserAttribut('marque', _marqueController.text.trim());

      if (_estModification) {
        await _service.majArticle(
          id: _article!.id,
          nom: nom,
          categorie: _categorieSelectionnee,
          prixAchat: prixAchat,
          prixVente: prixVente,
          quantite: quantite,
          uniteMesure: unite,
          photo: photo,
          description: description,
          lotNumero: lotNumero,
          dateExpiration: _dateExpiration,
          vendableAuPoids: _vendableAuPoids,
          attributs: attributs,
          codeBarre: codeBarre,
          devise: _deviseChoisie?.code,
          stockIllimite: _sansStock,
        );
        if (!mounted) return;
        _afficherMessage('Modifications enregistrées.');
        context.pop(true);
      } else {
        await _service.creerArticle(
          nom: nom,
          categorie: _categorieSelectionnee,
          prixAchat: prixAchat,
          prixVente: prixVente,
          quantite: quantite,
          uniteMesure: unite,
          photo: photo,
          description: description,
          lotNumero: lotNumero,
          dateExpiration: _dateExpiration,
          vendableAuPoids: _vendableAuPoids,
          attributs: attributs,
          codeBarre: codeBarre,
          devise: _deviseChoisie?.code,
          stockIllimite: _sansStock,
        );
        if (!mounted) return;
        context.pop(true);
      }
    } on ArticleServiceException catch (e) {
      _afficherMessage(e.message, estErreur: true);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
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
        backgroundColor: estErreur
            ? Colors.red.shade700
            : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? hint, IconData? icone}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icone == null ? null : Icon(icone),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  String? _validerObligatoire(String? valeur, String message) {
    if (valeur == null || valeur.trim().isEmpty) return message;
    return null;
  }

  String? _validerNombre(String? valeur, String message) {
    final String propre = (valeur ?? '').trim().replaceAll(',', '.');
    if (propre.isEmpty) return null;
    final double? nombre = double.tryParse(propre);
    if (nombre == null || nombre < 0) return message;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final String titre =
        _estModification ? "Modifier l'article" : 'Nouvel article';

    // ⚡ MODE RAPIDE — même règle que pour l'ajout de produit : en mode
    // simple on ne demande que l'essentiel (nom + prix de vente). Photo,
    // catégorie, unité de base et prix d'achat sont des réglages avancés.
    // L'unité retombe sur « pièce » à l'enregistrement ; les deux modes
    // écrivent exactement les mêmes données.
    final bool avance = ModeApplicationService.instance.afficherReglagesAvances;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          titre,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreurChargement != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child:
                        Text(_erreurChargement!, textAlign: TextAlign.center),
                  ),
                )
              : Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 🌍 CORRECTIF 78 — LE MARCHÉ SE REMPLIT TOUT SEUL.
                      //
                      // La publication n'est plus un geste à faire : dès
                      // l'enregistrement, l'article entre dans le marché
                      // Biashara (le serveur crée sa publication). On le dit
                      // ici, à l'endroit où le commerçant décide, plutôt que
                      // de laisser croire qu'il reste une case à cocher.
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppCouleurs.info.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Icon(Icons.public_rounded,
                                size: 18, color: AppCouleurs.info),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Enregistrer suffit : cet article est '
                                'immédiatement visible dans le marché Biashara. '
                                'Aucune publication à préparer.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // ------------------------------------------------ photo
                      if (avance) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _apercuPhoto(),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Photo (optionnelle)',
                                    style:
                                        Theme.of(context).textTheme.titleSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: _choisirPhoto,
                                        icon: const Icon(
                                            Icons.photo_camera_outlined,
                                            size: 18),
                                        label: const Text('Choisir'),
                                      ),
                                      const SizedBox(width: 8),
                                      if (_photoLocale != null ||
                                          (!_photoSupprimee &&
                                              (_photoUrl ?? '').isNotEmpty))
                                        TextButton(
                                          onPressed: _retirerPhoto,
                                          child: const Text('Retirer'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                      ],

                      // ------------------------------------------------- nom
                      TextFormField(
                        controller: _nomController,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _decoration('Nom *',
                            hint: 'Ex. Eau Casino', icone: Icons.label_outline),
                        validator: (String? v) => _validerObligatoire(
                            v, "Le nom de l'article est obligatoire."),
                      ),
                      const SizedBox(height: 16),

                      // ------------------------------------------- catégorie
                      if (avance) ...[
                        AppDropdownField<String>(
                          label: 'Catégorie',
                          value: _categorieSelectionnee,
                          prefixIcon: Icons.category_outlined,
                          items: _itemsCategories,
                          onChanged: (String? valeur) {
                            if (valeur == _valeurNouvelleCategorie) {
                              _creerCategorie();
                              return;
                            }
                            setState(
                                () => _categorieSelectionnee = valeur ?? '');
                          },
                        ),
                        const SizedBox(height: 16),
                      ],

                      // -------------------------------------- unité de base
                      if (avance) ...[
                        TextFormField(
                          controller: _uniteController,
                          decoration: _decoration(
                            'Unité de mesure de base *',
                            hint: 'bouteille, pièce, kg…',
                            icone: Icons.straighten,
                          ),
                          validator: (String? v) => _validerObligatoire(v,
                              "L'unité de base est obligatoire (ex. bouteille)."),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ---------------------------------------------- prix
                      Row(
                        children: [
                          if (avance)
                            Expanded(
                              child: TextFormField(
                                controller: _prixAchatController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                      RegExp(r'[0-9.,]')),
                                ],
                                decoration: _decoration("Prix d'achat (unité)"),
                                validator: (String? v) => _validerNombre(
                                    v, "Le prix d'achat est invalide."),
                              ),
                            ),
                          if (avance) const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _prixVenteController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'[0-9.,]')),
                              ],
                              decoration: _decoration('Prix de vente (unité)'),
                              validator: (String? v) => _validerNombre(
                                  v, 'Le prix de vente est invalide.'),
                            ),
                          ),
                        ],
                      ),

                      // 💵 MODULE 29 — DANS QUELLE DEVISE EST CE PRIX ?
                      //  Un article peut être en dollars et l'autre en
                      //  francs, dans la même boutique. Le prix est conservé
                      //  tel quel ; la conversion se fait à la vente.
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Devise>(
                        initialValue: _deviseChoisie,
                        decoration: _decoration('Devise du prix').copyWith(
                          prefixIcon: const Icon(Icons.currency_exchange),
                        ),
                        items: <DropdownMenuItem<Devise>>[
                          DropdownMenuItem<Devise>(
                            value: null,
                            child: Text(
                              'Devise de la boutique '
                              '(${DeviseService.instance.symbole})',
                            ),
                          ),
                          ...DeviseService.instance.configuration.devises
                              .map(
                            (Devise d) => DropdownMenuItem<Devise>(
                              value: d,
                              child: Text('${d.code} — ${d.libelle}'),
                            ),
                          ),
                        ],
                        onChanged: (Devise? v) =>
                            setState(() => _deviseChoisie = v),
                      ),
                      // ♾️ MODULE 31 — PRODUIT NON COMPTABLE.
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(top: 12),
                        color: _sansStock
                            ? Theme.of(context)
                                .colorScheme
                                .primaryContainer
                                .withValues(alpha: 0.35)
                            : null,
                        child: SwitchListTile(
                          value: _sansStock,
                          onChanged: (bool v) =>
                              setState(() => _sansStock = v),
                          title: const Text('Vendre sans suivre le stock'),
                          subtitle: const Text(
                            'Produit qui ne peut pas être compté : la caisse '
                            'vendra toujours, sans contrôle ni décompte.',
                          ),
                          secondary: const Icon(Icons.all_inclusive_rounded),
                        ),
                      ),
                      if (_deviseChoisie != null &&
                          _deviseChoisie !=
                              DeviseService.instance.configuration.devise)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Prix converti au taux du jour à la vente '
                            '(1 \$ = ${tauxDuJour.toStringAsFixed(0)} CDF).',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // -------------------------------------------- stock
                      TextFormField(
                        controller: _quantiteController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        decoration: _decoration(
                          'Quantité en stock',
                          hint: "En unités de base",
                          icone: Icons.warehouse_outlined,
                        ),
                        validator: (String? v) =>
                            _validerNombre(v, 'La quantité est invalide.'),
                      ),
                      const SizedBox(height: 16),

                      // ------------------------------------- description
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: _decoration('Description (optionnelle)'),
                      ),

                      const SizedBox(height: 16),

                      // ------------------------------- code-barres 🏷️
                      //  CORRECTIF 59 — le code du fabricant : saisi au
                      //  clavier, scanné à la caméra, ou tapé par une
                      //  douchette USB/Bluetooth.
                      //  🏷️ NOUVEAU — dès que le code est lu, le NOM du
                      //  produit s'écrit automatiquement (catalogue de la
                      //  boutique, sinon proposition issue d'une base
                      //  publique). Plus besoin de taper le nom à la main.
                      ChampCodeBarre(
                        controller: _codeBarreController,
                        aide: 'Scannez le code du fabricant : le nom du '
                            'produit se remplit tout seul.',
                        onCode: _codeBarreLu,
                      ),
                      if (_rechercheCode)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: <Widget>[
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Recherche du nom du produit…',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),

                      // 🧩 MODULE 16 C1 — PHARMACIE : lot & péremption.
                      //  Affiché uniquement si l'activité a le module
                      //  « lots_expiration » (les valeurs restent celles de
                      //  l'article sinon — jamais effacées).
                      if (ModulesService.instance
                          .moduleActif(ModuleCode.lotsExpiration)) ...[
                        const SizedBox(height: 20),
                        _sectionLotsEtExpiration(),
                      ],
                      // 🥩 MODULE 16 C6 — BOUCHERIE : vente au poids.
                      //  Affiché uniquement si l'activité a le module
                      //  « pesee » (les valeurs restent celles de l'article
                      //  sinon — jamais effacées).
                      if (ModulesService.instance
                          .moduleActif(ModuleCode.pesee)) ...[
                        const SizedBox(height: 20),
                        _sectionVenteAuPoids(),
                      ],
                      // 👕 MODULE 16 C8 — MODE : variantes.
                      //  Affiché uniquement si l'activité a le module
                      //  « variantes » (les clés inconnues de l'article
                      //  sont conservées à l'enregistrement).
                      if (ModulesService.instance
                          .moduleActif(ModuleCode.variantes)) ...[
                        const SizedBox(height: 20),
                        _sectionVariantes(),
                      ],
                      const SizedBox(height: 20),

                      // -------------------------------- conditionnements
                      _sectionConditionnements(),
                      const SizedBox(height: 24),

                      // ----------------------------------------- bouton
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _enregistrement ? null : _enregistrer,
                          icon: _enregistrement
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(
                            _estModification
                                ? 'Enregistrer les modifications'
                                : "Créer l'article",
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
