// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get profileTitle => 'Mon Profil';

  @override
  String get profileSubtitle =>
      'Voir et modifier les informations personnelles';

  @override
  String get manageUsersTitle => 'Gérer les Utilisateurs';

  @override
  String get manageUsersSubtitle => 'Créer, valider et gérer l\'accès';

  @override
  String get changePasswordTitle => 'Changer le Mot de Passe';

  @override
  String get changePasswordSubtitle =>
      'Mettre à jour vos identifiants de connexion';

  @override
  String get languageTitle => 'Langue de l\'Application';

  @override
  String get helpAndSupportTitle => 'Aide et Support';

  @override
  String get logoutButton => 'Déconnexion';

  @override
  String get currentLanguageLabel => 'Actuelle :';

  @override
  String get chooseLanguageDialogTitle => 'Choisir la Langue 🌐';

  @override
  String get applyButton => 'Appliquer';

  @override
  String get cancelButton => 'Annuler';

  @override
  String get adminSectionTitle => 'Outils d\'Administration';

  @override
  String get manageCategories => 'Gérer les Catégories';

  @override
  String get manageCategoriesSubtitle =>
      'Ajouter, modifier ou supprimer des catégories de produits';

  @override
  String get statStockStatus => 'Statut du Stock';

  @override
  String statStockLowCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Produits en Stock Faible',
      one: '1 Produit en Stock Faible',
      zero: 'Tout est OK',
    );
    return '$_temp0';
  }

  @override
  String get errorLoadingStats =>
      'Une erreur s\'est produite lors du chargement des statistiques. Affichage des données générales.';

  @override
  String get statDailySales => 'Ventes du Jour';

  @override
  String get statTotalSalesOverall => 'Total des Ventes Globales';

  @override
  String get user => 'Utilisateur';

  @override
  String get statisticsTitle => 'Statistiques';

  @override
  String get statTotalSales => 'Total des Ventes';

  @override
  String get statSalesCount => 'Nombre de Ventes';

  @override
  String get statProductsCount => 'Produits';

  @override
  String get statClientsCount => 'Clients';

  @override
  String get buttonAddProduct => 'Ajouter Produit';

  @override
  String get productUnitDefault => 'unité';

  @override
  String get buttonManageStock => 'Gérer le Stock';

  @override
  String get buttonNewSale => 'Nouvelle Vente';

  @override
  String get buttonReports => 'Rapports';

  @override
  String get navHome => 'Accueil';

  @override
  String get navStock => 'Stock';

  @override
  String get navReports => 'Rapports';

  @override
  String get navSettings => 'Paramètres';

  @override
  String homeWelcomeMessage(Object name) {
    return 'Bienvenue $name — Bonnes ventes!';
  }

  @override
  String homeSummaryGreeting(Object name) {
    return 'Bonjour $name';
  }

  @override
  String homeSummaryProductsSales(num productCount, num salesCount) {
    String _temp0 = intl.Intl.pluralLogic(
      productCount,
      locale: localeName,
      other: '$productCount produits',
      one: 'un seul produit',
      zero: 'aucun produit',
    );
    String _temp1 = intl.Intl.pluralLogic(
      salesCount,
      locale: localeName,
      other: '$salesCount ventes',
      one: 'une seule vente',
      zero: 'aucune vente',
    );
    return 'Vous avez $_temp0 et $_temp1.';
  }

  @override
  String get themeTitle => 'Thème de l\'Application';

  @override
  String get currentThemeLabel => 'Actuel :';

  @override
  String get chooseThemeDialogTitle => 'Choisir le Thème 🎨';

  @override
  String get themeSystem => 'Défaut Système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get notificationsTitle => 'Notifications et Alertes';

  @override
  String lowStockAlert(int lowStockCount) {
    String _temp0 = intl.Intl.pluralLogic(
      lowStockCount,
      locale: localeName,
      other: '$lowStockCount produits',
      one: '1 produit',
    );
    return 'Alerte Stock Faible : $_temp0 ont besoin d\'être réapprovisionnés.';
  }

  @override
  String get lowStockAlertSubtitle =>
      'Cliquez ici pour voir la liste et commander à nouveau.';

  @override
  String get addProductTitle => 'Nouveau Produit';

  @override
  String get categoryOther => 'Autre';

  @override
  String get categoryRequired => 'Veuillez sélectionner une catégorie.';

  @override
  String get priceValidation =>
      'Les prix d\'achat et de vente doivent être supérieurs à zéro.';

  @override
  String get priceMarkupValidation =>
      'Le prix de vente doit être supérieur au prix d\'achat.';

  @override
  String get productSaved => 'Produit sauvegardé avec succès!';

  @override
  String get saving => 'Sauvegarde en cours...';

  @override
  String get saveError => 'Erreur lors de la sauvegarde';

  @override
  String get productNameLabel => 'Nom du Produit';

  @override
  String get productCategoryLabel => 'Catégorie';

  @override
  String get productPriceCost => 'Prix d\'Achat';

  @override
  String get productPriceSell => 'Prix de Vente';

  @override
  String get productQuantityLabel => 'Quantité en Stock';

  @override
  String get nameRequired => 'Le nom est requis';

  @override
  String get priceRequired => 'Le prix est requis';

  @override
  String get quantityRequired => 'La quantité est requise';

  @override
  String get saveButton => 'Sauvegarder Produit';

  @override
  String get photoOptionTitle => 'Ajouter Photo';

  @override
  String get photoOptionGallery => 'Choisir depuis la Galerie';

  @override
  String get photoOptionCamera => 'Prendre une Photo';

  @override
  String get photoOptionDelete => 'Supprimer la photo actuelle';

  @override
  String get changePhoto => 'Changer Photo';

  @override
  String get addPhoto => 'Ajouter Photo';

  @override
  String errorGallery(Object error) {
    return 'Erreur de Galerie : $error';
  }

  @override
  String errorCamera(Object error) {
    return 'Erreur de Caméra : $error';
  }

  @override
  String loadingError(Object error) {
    return 'Erreur de chargement : $error';
  }

  @override
  String get internalLoadingError => 'Erreur de chargement interne.';

  @override
  String get loginWelcome => 'Bienvenue';

  @override
  String get loginEmailLabel => 'Email';

  @override
  String get loginPinLabel => 'PIN';

  @override
  String get loginButton => 'Connexion';

  @override
  String get loginCreateStore => 'Créer un Magasin';

  @override
  String get emailRequired => 'L\'email est requis.';

  @override
  String get pinRequired => 'Le code PIN est requis.';

  @override
  String get pinInvalid => 'Code PIN invalide (min 4 chiffres, pas 0000/1234).';

  @override
  String get loginErrorCredentials => 'Email ou PIN incorrect';

  @override
  String get loginErrorPending =>
      'Compte en attente de validation par l\'administrateur';

  @override
  String get loginErrorGeneric => 'Erreur lors de la connexion';

  @override
  String get loginBiometricButton => 'Se connecter avec Empreinte / Face ID';

  @override
  String get biometricPrompt =>
      'Veuillez vous authentifier pour vous connecter à Mon Commerce.';

  @override
  String get biometricLoginFailed =>
      'Échec de la connexion. Veuillez utiliser Email/PIN.';

  @override
  String get biometricNoUser =>
      'Veuillez vous connecter d\'abord avec Email/PIN.';

  @override
  String get biometricError =>
      'Erreur d\'authentification biométrique. Veuillez réessayer.';

  @override
  String get productAdded => 'Produit ajouté avec succès';

  @override
  String get setupTitleNewStore => 'Créer un Nouveau Magasin';

  @override
  String get setupTitleNewUser => 'Créer un Nouvel Utilisateur';

  @override
  String get setupTitleEdit => 'Modifier Utilisateur';

  @override
  String get setupLabelName => 'Nom Complet';

  @override
  String get setupLabelEmail => 'Email (Identifiant)';

  @override
  String get setupLabelPin => 'PIN de connexion (4+ chiffres)';

  @override
  String get setupLabelRole => 'Rôle';

  @override
  String get roleVendor => 'Vendeur';

  @override
  String get roleAdmin => 'Administrateur';

  @override
  String get setupButtonCreate => 'Créer le Compte';

  @override
  String get setupNoticeValidation =>
      'Note : Les comptes créés seront en attente de validation par un administrateur.';

  @override
  String get setupInitialSuccess =>
      'Compte créé. Veuillez vous connecter après validation.';

  @override
  String get userCreatedSuccess => 'Utilisateur créé avec succès.';

  @override
  String get userUpdatedSuccess => 'Utilisateur mis à jour avec succès.';

  @override
  String get setupErrorGeneric => 'Erreur lors de la sauvegarde';

  @override
  String get unitLabel => 'Unité';

  @override
  String get unitRequired => 'L\'unité est requise.';

  @override
  String get unitUnity => 'unité';

  @override
  String get unitKg => 'kg';

  @override
  String get unitDozen => 'douzaine';

  @override
  String get unitLiter => 'litre';

  @override
  String get unitMeter => 'mètre';

  @override
  String get errorLoadingData =>
      'Échec du chargement des données. Veuillez réessayer ou vérifier votre connexion.';

  @override
  String get newSaleTitle => 'Nouvelle Vente';

  @override
  String get errorUserNotLoggedIn =>
      'Erreur : La session utilisateur est perdue. Veuillez vous reconnecter.';

  @override
  String get clientNewTitle => 'Nouveau Client';

  @override
  String get clientAddedSuccess => 'Client ajouté avec succès.';

  @override
  String get errorSavingClient => 'Erreur lors de la sauvegarde du client';

  @override
  String get errorSavingClientGeneric =>
      'Erreur inattendue lors de la sauvegarde.';

  @override
  String get fieldName => 'Nom Complet';

  @override
  String get fieldPhone => 'Téléphone';

  @override
  String get fieldEmail => 'Email';

  @override
  String get validationNameRequired => 'Le nom est requis.';

  @override
  String get validationEmailInvalid =>
      'Veuillez entrer une adresse email valide.';

  @override
  String get buttonSaveClient => 'Sauvegarder Client';

  @override
  String productSubtitle(Object price, Object stock, Object unit) {
    return 'Prix : $price • Stock : $stock $unit';
  }

  @override
  String addToCartTitle(Object productName) {
    return 'Ajouter $productName';
  }

  @override
  String dialogQuantityLabel(Object unit) {
    return 'Quantité ($unit)';
  }

  @override
  String get invalidQuantity => 'Quantité invalide';

  @override
  String insufficientStock(Object maxStock, Object unit) {
    return 'Stock insuffisant. Max : $maxStock $unit';
  }

  @override
  String get outOfStock => 'Produit épuisé.';

  @override
  String totalAmount(Object amount, Object currencyUnit) {
    return 'Total : $amount $currencyUnit';
  }

  @override
  String get paymentModeHint => 'Mode de Paiement';

  @override
  String paymentMode(Object mode) {
    return '$mode';
  }

  @override
  String get recordSaleButton => 'Enregistrer Vente';

  @override
  String get saleRecorded => 'Vente enregistrée avec succès.';

  @override
  String get saleError => 'Erreur lors de l\'enregistrement de la vente';

  @override
  String get permissionDenied => 'Permission refusée.';

  @override
  String get addButton => 'Ajouter';

  @override
  String get stockManagementTitle => 'Stock & Prix';

  @override
  String get searchProductHint => 'Rechercher produit ou catégorie...';

  @override
  String addedToSale(Object produitName) {
    return 'Produit $produitName ajouté à la vente';
  }

  @override
  String get updateButton => 'Mettre à Jour Produit';

  @override
  String get productUpdated => 'Informations produit mises à jour avec succès.';

  @override
  String get headerAddStock => 'Ajouter du Stock (Réapprovisionner)';

  @override
  String get labelQuantityToAdd => 'Quantité à Ajouter';

  @override
  String get labelNewPurchasePrice => 'Nouveau Prix d\'Achat (par unité)';

  @override
  String get buttonAddToStock => 'Réapprovisionner';

  @override
  String get msgInvalidStockInput =>
      'Veuillez entrer une quantité et un prix d\'achat valides et positifs.';

  @override
  String get msgStockAddedSuccess =>
      'Stock ajouté avec succès et historique enregistré.';

  @override
  String get msgStockAddFailure => 'Échec de l\'ajout du stock';

  @override
  String get headerStockHistory => 'Historique de Réapprovisionnement';

  @override
  String get msgNoHistoryFound =>
      'Aucun historique de réapprovisionnement trouvé pour ce produit.';

  @override
  String get labelAdded => 'Ajouté';

  @override
  String get labelPurchasePrice => 'Prix d\'Achat';

  @override
  String get labelUnknownDate => 'Date Inconnue';

  @override
  String get validationInvalidNumber => 'Veuillez entrer un nombre valide.';

  @override
  String loadingHistoryError(Object error) {
    return 'Erreur de chargement de l\'historique : $error';
  }

  @override
  String get currencyUnit => 'CDF';

  @override
  String get reportsTitle => 'Rapports d\'Activité';

  @override
  String reportsTitleUser(Object name) {
    return 'Rapport - $name';
  }

  @override
  String get reportsSelectPeriod => 'Sélectionner la Période';

  @override
  String reportsDateRange(Object endDate, Object startDate) {
    return 'Période : Du $startDate au $endDate';
  }

  @override
  String get reportsPeriodDay => 'Jour (7 Derniers Jours)';

  @override
  String get reportsPeriodWeek => 'Semaine (12 Dernières Semaines)';

  @override
  String get reportsPeriodMonth => 'Mois (6 Derniers Mois)';

  @override
  String get reportsPeriodYear => 'Année (5 Dernières Années)';

  @override
  String get reportsDetailTitle => 'Détails par Période';

  @override
  String reportsDetailSubtitle(Object currencyUnit, Object qty, Object total) {
    return 'Revenu : $total $currencyUnit • Quantité : $qty';
  }

  @override
  String get reportsTopProductsTitle =>
      'Top 10 des Produits (Période Complète)';

  @override
  String reportsTopProductSubtitle(
      Object currencyUnit, Object qty, Object revenue) {
    return 'Quantité vendue : $qty • Revenu : $revenue $currencyUnit';
  }

  @override
  String get reportsNoData =>
      'Aucune donnée de vente trouvée pour la période et l\'utilisateur sélectionnés.';

  @override
  String get reportsNoCategoryData =>
      'Aucune vente enregistrée pour aucune catégorie dans cette période.';

  @override
  String get noPeriodLabel => 'Non/Applicable - Période';

  @override
  String reportTitleForDate(Object date) {
    return 'Rapport du $date';
  }

  @override
  String get buttonPrintReport => 'Imprimer le Rapport';

  @override
  String reportStoreName(Object name) {
    return 'Magasin : $name';
  }

  @override
  String get reportSummaryTitle => 'Résumé du Jour';

  @override
  String get reportTotalRevenue => 'Revenu Total des Ventes (TR)';

  @override
  String get reportTotalProfit => 'Profit du Jour';

  @override
  String get reportTotalQty => 'Quantité Totale Vendue';

  @override
  String get reportQtyByCategory => 'Quantité de Produits Vendus par Catégorie';

  @override
  String get reportDetailedSales => 'Détails des Ventes par Produit';

  @override
  String get reportProduct => 'Produit';

  @override
  String get reportQty => 'Quantité';

  @override
  String get reportAmount => 'Montant';

  @override
  String get reportUnitsLabel => 'unités';

  @override
  String get errorPrinting => 'Erreur lors de l\'impression';

  @override
  String get reportTopProductsTitle => 'Produits les Plus Vendus du Jour';

  @override
  String get pdfReportTitle => 'Rapport Quotidien des Ventes';

  @override
  String get pdfStore => 'Magasin';

  @override
  String get pdfReportDate => 'Date du Rapport';

  @override
  String get pdfSummaryTitle => 'Résumé Quotidien';

  @override
  String get pdfTotalRevenue => 'Revenu Total des Ventes (TR)';

  @override
  String get pdfTotalQty => 'Quantité Totale Vendue';

  @override
  String get pdfTotalProfit => 'Profit du Jour';

  @override
  String get pdfSalesByCategory => 'Ventes par Catégorie';

  @override
  String get pdfDetailedSales => 'Détails des Ventes par Produit';

  @override
  String get pdfProduct => 'Produit';

  @override
  String get pdfQuantity => 'Quantité';

  @override
  String get pdfAmountSold => 'Montant Vendu';

  @override
  String get pdfTopProductsTitle => 'Produits les Plus Vendus du Jour';

  @override
  String pdfTopProductQty(Object qty) {
    return '$qty Unités';
  }

  @override
  String get pdfCategory => 'Catégorie';

  @override
  String get saleRecordedAndInvoiceGenerated =>
      'Vente enregistrée. Facture générée pour traçabilité.';

  @override
  String get sessionError => 'Erreur de session. Veuillez vous reconnecter.';

  @override
  String get invoiceTitle => 'FACTURE DE VENTE';

  @override
  String get invoiceName => 'Facture';

  @override
  String get invoiceTotal => 'MONTANT TOTAL DÛ';

  @override
  String get pdfItem => 'Article';

  @override
  String get pdfQty => 'Qté';

  @override
  String get pdfUnit => 'Unité';

  @override
  String get pdfPrice => 'Prix Unitaire';

  @override
  String get pdfTotal => 'Total';

  @override
  String get pdfStoreInfo => 'Vendu par';

  @override
  String get pdfDate => 'Date et Heure';

  @override
  String get pdfPaymentMode => 'Mode de Paiement';

  @override
  String invoiceThankYou(Object date) {
    return 'Merci pour votre achat effectué le $date';
  }

  @override
  String invoiceTraceability(Object id) {
    return 'ID Unique de Transaction (Traçabilité) : $id';
  }

  @override
  String get defaultStoreName => 'Mon Commerce';

  @override
  String get searchProductLabel => 'Rechercher Produit';

  @override
  String get searchHint => 'Nom ou Catégorie...';

  @override
  String get noResultsFound => 'Aucun produit ne correspond à votre recherche.';

  @override
  String get noProductsAvailable =>
      'Aucun produit disponible. Ajoutez-en au Stock.';

  @override
  String get deleteButton => 'Supprimer';

  @override
  String get confirmDeleteProductTitle => 'Confirmer la Suppression';

  @override
  String confirmDeleteProductMessage(Object productName) {
    return 'Êtes-vous sûr de vouloir supprimer le produit $productName ? Cette action est irréversible.';
  }

  @override
  String productDeletedSuccess(Object productName) {
    return 'Produit $productName supprimé avec succès.';
  }

  @override
  String get productDeleteError => 'Erreur lors de la suppression du produit.';

  @override
  String supplyProductTitle(Object productName) {
    return 'Réapprovisionner $productName';
  }

  @override
  String get supplyQuantityHint => 'Quantité à ajouter';

  @override
  String get supplyPriceHint => 'Prix d\'achat par unité';

  @override
  String supplySuccess(Object qty, Object unit) {
    return 'Stock mis à jour. Ajout de $qty $unit.';
  }

  @override
  String get supplyError => 'Erreur lors du réapprovisionnement.';

  @override
  String get invalidQuantityError =>
      'Veuillez entrer une quantité positive et valide.';

  @override
  String get priceValidationRestock =>
      'Veuillez entrer un prix d\'achat par unité positif et valide.';

  @override
  String traceabilityHistoryTitle(Object productName) {
    return 'Historique de Réapprovisionnement : $productName';
  }

  @override
  String get traceabilityEmpty =>
      'Aucun historique de réapprovisionnement enregistré pour ce produit.';

  @override
  String get atDate => 'Date';

  @override
  String get atPrice => 'Prix Unitaire';

  @override
  String get dateUnknown => 'Date Inconnue';

  @override
  String get closeButton => 'Fermer';

  @override
  String formatDate(Object date) {
    return '$date';
  }

  @override
  String get okButton => 'OK';

  @override
  String get categoryNone => 'Aucune';

  @override
  String get optionalLabel => 'Optionnel';

  @override
  String get settingsAboutTitle => 'À propos';

  @override
  String get invalidPrice => 'Prix invalide';

  @override
  String get sessionExpired => 'Session expirée';

  @override
  String get genericError => 'Une erreur est survenue';

  @override
  String get aboutAppDescription =>
      'Cette application permet de gérer vos ventes et votre stock de manière efficace et sécurisée.';

  @override
  String get aboutAppPolicy =>
      'Nous respectons votre vie privée et vos données personnelles conformément à notre politique.';

  @override
  String get aboutAppContact =>
      'Contactez-nous : +243974084668, Andrelukengu67@gmail.com, Lubumbashi, Haut-Katanga';
}
