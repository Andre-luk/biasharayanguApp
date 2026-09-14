import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_sw.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
    Locale('sw')
  ];

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'My Profile'**
  String get profileTitle;

  /// No description provided for @profileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View and edit personal information'**
  String get profileSubtitle;

  /// No description provided for @manageUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Manage Users'**
  String get manageUsersTitle;

  /// No description provided for @manageUsersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create, validate, and manage access'**
  String get manageUsersSubtitle;

  /// No description provided for @changePasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePasswordTitle;

  /// No description provided for @changePasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update your login credentials'**
  String get changePasswordSubtitle;

  /// No description provided for @languageTitle.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get languageTitle;

  /// No description provided for @helpAndSupportTitle.
  ///
  /// In en, this message translates to:
  /// **'Help and Support'**
  String get helpAndSupportTitle;

  /// No description provided for @logoutButton.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutButton;

  /// No description provided for @currentLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Current:'**
  String get currentLanguageLabel;

  /// No description provided for @chooseLanguageDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Language 🌐'**
  String get chooseLanguageDialogTitle;

  /// No description provided for @applyButton.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get applyButton;

  /// No description provided for @cancelButton.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelButton;

  /// No description provided for @adminSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Admin Tools'**
  String get adminSectionTitle;

  /// No description provided for @manageCategories.
  ///
  /// In en, this message translates to:
  /// **'Manage Categories'**
  String get manageCategories;

  /// No description provided for @manageCategoriesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add, edit, or delete product categories'**
  String get manageCategoriesSubtitle;

  /// No description provided for @statStockStatus.
  ///
  /// In en, this message translates to:
  /// **'Stock Status'**
  String get statStockStatus;

  /// No description provided for @statStockLowCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Everything is OK} one{1 Product is Low} other{{count} Products are Low}}'**
  String statStockLowCount(num count);

  /// No description provided for @errorLoadingStats.
  ///
  /// In en, this message translates to:
  /// **'An error occurred while loading stats. Showing general data.'**
  String get errorLoadingStats;

  /// No description provided for @statDailySales.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Sales'**
  String get statDailySales;

  /// No description provided for @statTotalSalesOverall.
  ///
  /// In en, this message translates to:
  /// **'Total Overall Sales'**
  String get statTotalSalesOverall;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @statisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsTitle;

  /// No description provided for @statTotalSales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get statTotalSales;

  /// No description provided for @statSalesCount.
  ///
  /// In en, this message translates to:
  /// **'Sales (count)'**
  String get statSalesCount;

  /// No description provided for @statProductsCount.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get statProductsCount;

  /// No description provided for @statClientsCount.
  ///
  /// In en, this message translates to:
  /// **'Clients'**
  String get statClientsCount;

  /// No description provided for @buttonAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get buttonAddProduct;

  /// No description provided for @productUnitDefault.
  ///
  /// In en, this message translates to:
  /// **'unit'**
  String get productUnitDefault;

  /// No description provided for @buttonManageStock.
  ///
  /// In en, this message translates to:
  /// **'Manage Stock'**
  String get buttonManageStock;

  /// No description provided for @buttonNewSale.
  ///
  /// In en, this message translates to:
  /// **'New Sale'**
  String get buttonNewSale;

  /// No description provided for @buttonReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get buttonReports;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navStock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get navStock;

  /// No description provided for @navReports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @homeWelcomeMessage.
  ///
  /// In en, this message translates to:
  /// **'Welcome {name} — Enjoy good sales!'**
  String homeWelcomeMessage(Object name);

  /// No description provided for @homeSummaryGreeting.
  ///
  /// In en, this message translates to:
  /// **'Hello {name}'**
  String homeSummaryGreeting(Object name);

  /// No description provided for @homeSummaryProductsSales.
  ///
  /// In en, this message translates to:
  /// **'You have {productCount, plural, =0{no products} one{one product} other{{productCount} products}} and {salesCount, plural, =0{no sales} one{one sale} other{{salesCount} sales}}.'**
  String homeSummaryProductsSales(num productCount, num salesCount);

  /// No description provided for @themeTitle.
  ///
  /// In en, this message translates to:
  /// **'App Theme'**
  String get themeTitle;

  /// No description provided for @currentThemeLabel.
  ///
  /// In en, this message translates to:
  /// **'Current:'**
  String get currentThemeLabel;

  /// No description provided for @chooseThemeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Theme 🎨'**
  String get chooseThemeDialogTitle;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Titre de la section notifications sur la page d'accueil
  ///
  /// In en, this message translates to:
  /// **'Notifications and Alerts'**
  String get notificationsTitle;

  /// Alerte affichée lorsque le stock est faible
  ///
  /// In en, this message translates to:
  /// **'Low Stock Alert: {lowStockCount, plural, one{1 product} other{{lowStockCount} products}} need restocking.'**
  String lowStockAlert(int lowStockCount);

  /// Sous-titre de l'alerte stock faible
  ///
  /// In en, this message translates to:
  /// **'Click here to view the list and reorder.'**
  String get lowStockAlertSubtitle;

  /// No description provided for @addProductTitle.
  ///
  /// In en, this message translates to:
  /// **'New Product'**
  String get addProductTitle;

  /// No description provided for @categoryOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get categoryOther;

  /// No description provided for @categoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a category.'**
  String get categoryRequired;

  /// No description provided for @priceValidation.
  ///
  /// In en, this message translates to:
  /// **'Purchase and selling prices must be greater than zero.'**
  String get priceValidation;

  /// No description provided for @priceMarkupValidation.
  ///
  /// In en, this message translates to:
  /// **'Selling price must be greater than purchase price.'**
  String get priceMarkupValidation;

  /// No description provided for @productSaved.
  ///
  /// In en, this message translates to:
  /// **'Product saved successfully!'**
  String get productSaved;

  /// No description provided for @saving.
  ///
  /// In en, this message translates to:
  /// **'Saving...'**
  String get saving;

  /// No description provided for @saveError.
  ///
  /// In en, this message translates to:
  /// **'Error while saving'**
  String get saveError;

  /// No description provided for @productNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Product Name'**
  String get productNameLabel;

  /// No description provided for @productCategoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get productCategoryLabel;

  /// No description provided for @productPriceCost.
  ///
  /// In en, this message translates to:
  /// **'Purchase Price'**
  String get productPriceCost;

  /// No description provided for @productPriceSell.
  ///
  /// In en, this message translates to:
  /// **'Selling Price'**
  String get productPriceSell;

  /// No description provided for @productQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock Quantity'**
  String get productQuantityLabel;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get nameRequired;

  /// No description provided for @priceRequired.
  ///
  /// In en, this message translates to:
  /// **'Price is required'**
  String get priceRequired;

  /// No description provided for @quantityRequired.
  ///
  /// In en, this message translates to:
  /// **'Quantity is required'**
  String get quantityRequired;

  /// No description provided for @saveButton.
  ///
  /// In en, this message translates to:
  /// **'Save Product'**
  String get saveButton;

  /// No description provided for @photoOptionTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get photoOptionTitle;

  /// No description provided for @photoOptionGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get photoOptionGallery;

  /// No description provided for @photoOptionCamera.
  ///
  /// In en, this message translates to:
  /// **'Take a Photo'**
  String get photoOptionCamera;

  /// No description provided for @photoOptionDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete current photo'**
  String get photoOptionDelete;

  /// No description provided for @changePhoto.
  ///
  /// In en, this message translates to:
  /// **'Change Photo'**
  String get changePhoto;

  /// No description provided for @addPhoto.
  ///
  /// In en, this message translates to:
  /// **'Add Photo'**
  String get addPhoto;

  /// No description provided for @errorGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery Error: {error}'**
  String errorGallery(Object error);

  /// No description provided for @errorCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera Error: {error}'**
  String errorCamera(Object error);

  /// No description provided for @loadingError.
  ///
  /// In en, this message translates to:
  /// **'Loading error: {error}'**
  String loadingError(Object error);

  /// No description provided for @internalLoadingError.
  ///
  /// In en, this message translates to:
  /// **'Internal loading error.'**
  String get internalLoadingError;

  /// No description provided for @loginWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get loginWelcome;

  /// No description provided for @loginEmailLabel.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get loginEmailLabel;

  /// No description provided for @loginPinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get loginPinLabel;

  /// No description provided for @loginButton.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get loginButton;

  /// No description provided for @loginCreateStore.
  ///
  /// In en, this message translates to:
  /// **'Create Store'**
  String get loginCreateStore;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required.'**
  String get emailRequired;

  /// No description provided for @pinRequired.
  ///
  /// In en, this message translates to:
  /// **'PIN is required.'**
  String get pinRequired;

  /// No description provided for @pinInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid PIN (min 4 digits, not 0000/1234).'**
  String get pinInvalid;

  /// No description provided for @loginErrorCredentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or PIN'**
  String get loginErrorCredentials;

  /// No description provided for @loginErrorPending.
  ///
  /// In en, this message translates to:
  /// **'Account pending administrator validation'**
  String get loginErrorPending;

  /// No description provided for @loginErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Error while logging in'**
  String get loginErrorGeneric;

  /// No description provided for @loginBiometricButton.
  ///
  /// In en, this message translates to:
  /// **'Login with Fingerprint / Face ID'**
  String get loginBiometricButton;

  /// No description provided for @biometricPrompt.
  ///
  /// In en, this message translates to:
  /// **'Please authenticate to log in to My Business.'**
  String get biometricPrompt;

  /// No description provided for @biometricLoginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please use Email/PIN.'**
  String get biometricLoginFailed;

  /// No description provided for @biometricNoUser.
  ///
  /// In en, this message translates to:
  /// **'Please log in first using Email/PIN.'**
  String get biometricNoUser;

  /// No description provided for @biometricError.
  ///
  /// In en, this message translates to:
  /// **'Biometric authentication error. Please try again.'**
  String get biometricError;

  /// No description provided for @productAdded.
  ///
  /// In en, this message translates to:
  /// **'Product added successfully'**
  String get productAdded;

  /// No description provided for @setupTitleNewStore.
  ///
  /// In en, this message translates to:
  /// **'Create New Store'**
  String get setupTitleNewStore;

  /// No description provided for @setupTitleNewUser.
  ///
  /// In en, this message translates to:
  /// **'Create New User'**
  String get setupTitleNewUser;

  /// No description provided for @setupTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit User'**
  String get setupTitleEdit;

  /// No description provided for @setupLabelName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get setupLabelName;

  /// No description provided for @setupLabelEmail.
  ///
  /// In en, this message translates to:
  /// **'Email (Identifier)'**
  String get setupLabelEmail;

  /// No description provided for @setupLabelPin.
  ///
  /// In en, this message translates to:
  /// **'Login PIN (4+ digits)'**
  String get setupLabelPin;

  /// No description provided for @setupLabelRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get setupLabelRole;

  /// No description provided for @roleVendor.
  ///
  /// In en, this message translates to:
  /// **'Vendor'**
  String get roleVendor;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get roleAdmin;

  /// No description provided for @setupButtonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get setupButtonCreate;

  /// No description provided for @setupNoticeValidation.
  ///
  /// In en, this message translates to:
  /// **'Note: Created accounts will be pending administrator validation.'**
  String get setupNoticeValidation;

  /// No description provided for @setupInitialSuccess.
  ///
  /// In en, this message translates to:
  /// **'Account created. Please log in after validation.'**
  String get setupInitialSuccess;

  /// No description provided for @userCreatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'User created successfully.'**
  String get userCreatedSuccess;

  /// No description provided for @userUpdatedSuccess.
  ///
  /// In en, this message translates to:
  /// **'User updated successfully.'**
  String get userUpdatedSuccess;

  /// No description provided for @setupErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Error while saving'**
  String get setupErrorGeneric;

  /// No description provided for @unitLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unitLabel;

  /// No description provided for @unitRequired.
  ///
  /// In en, this message translates to:
  /// **'Unit is required.'**
  String get unitRequired;

  /// No description provided for @unitUnity.
  ///
  /// In en, this message translates to:
  /// **'unit'**
  String get unitUnity;

  /// No description provided for @unitKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get unitKg;

  /// No description provided for @unitDozen.
  ///
  /// In en, this message translates to:
  /// **'dozen'**
  String get unitDozen;

  /// No description provided for @unitLiter.
  ///
  /// In en, this message translates to:
  /// **'liter'**
  String get unitLiter;

  /// No description provided for @unitMeter.
  ///
  /// In en, this message translates to:
  /// **'meter'**
  String get unitMeter;

  /// No description provided for @errorLoadingData.
  ///
  /// In en, this message translates to:
  /// **'Failed to load data. Please retry or check your connection.'**
  String get errorLoadingData;

  /// No description provided for @newSaleTitle.
  ///
  /// In en, this message translates to:
  /// **'New Sale'**
  String get newSaleTitle;

  /// No description provided for @errorUserNotLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Error: User session lost. Please log in again.'**
  String get errorUserNotLoggedIn;

  /// No description provided for @clientNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New Client'**
  String get clientNewTitle;

  /// No description provided for @clientAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Client added successfully.'**
  String get clientAddedSuccess;

  /// No description provided for @errorSavingClient.
  ///
  /// In en, this message translates to:
  /// **'Error while saving client'**
  String get errorSavingClient;

  /// No description provided for @errorSavingClientGeneric.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error while saving.'**
  String get errorSavingClientGeneric;

  /// No description provided for @fieldName.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fieldName;

  /// No description provided for @fieldPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get fieldPhone;

  /// No description provided for @fieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get fieldEmail;

  /// No description provided for @validationNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required.'**
  String get validationNameRequired;

  /// No description provided for @validationEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address.'**
  String get validationEmailInvalid;

  /// No description provided for @buttonSaveClient.
  ///
  /// In en, this message translates to:
  /// **'Save Client'**
  String get buttonSaveClient;

  /// No description provided for @productSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Price: {price} • Stock: {stock} {unit}'**
  String productSubtitle(Object price, Object stock, Object unit);

  /// No description provided for @addToCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Add {productName}'**
  String addToCartTitle(Object productName);

  /// No description provided for @dialogQuantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity ({unit})'**
  String dialogQuantityLabel(Object unit);

  /// No description provided for @invalidQuantity.
  ///
  /// In en, this message translates to:
  /// **'Invalid quantity'**
  String get invalidQuantity;

  /// No description provided for @insufficientStock.
  ///
  /// In en, this message translates to:
  /// **'Insufficient stock. Max: {maxStock} {unit}'**
  String insufficientStock(Object maxStock, Object unit);

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Product out of stock.'**
  String get outOfStock;

  /// No description provided for @totalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total: {amount} {currencyUnit}'**
  String totalAmount(Object amount, Object currencyUnit);

  /// No description provided for @paymentModeHint.
  ///
  /// In en, this message translates to:
  /// **'Payment Mode'**
  String get paymentModeHint;

  /// No description provided for @paymentMode.
  ///
  /// In en, this message translates to:
  /// **'{mode}'**
  String paymentMode(Object mode);

  /// No description provided for @recordSaleButton.
  ///
  /// In en, this message translates to:
  /// **'Record Sale'**
  String get recordSaleButton;

  /// No description provided for @saleRecorded.
  ///
  /// In en, this message translates to:
  /// **'Sale recorded successfully.'**
  String get saleRecorded;

  /// No description provided for @saleError.
  ///
  /// In en, this message translates to:
  /// **'Error while recording sale'**
  String get saleError;

  /// No description provided for @permissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Permission denied.'**
  String get permissionDenied;

  /// No description provided for @addButton.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addButton;

  /// No description provided for @stockManagementTitle.
  ///
  /// In en, this message translates to:
  /// **'Stock & Pricing'**
  String get stockManagementTitle;

  /// No description provided for @searchProductHint.
  ///
  /// In en, this message translates to:
  /// **'Search product or category...'**
  String get searchProductHint;

  /// No description provided for @addedToSale.
  ///
  /// In en, this message translates to:
  /// **'Product {produitName} added to sale'**
  String addedToSale(Object produitName);

  /// No description provided for @updateButton.
  ///
  /// In en, this message translates to:
  /// **'Update Product Info'**
  String get updateButton;

  /// No description provided for @productUpdated.
  ///
  /// In en, this message translates to:
  /// **'Product information updated successfully.'**
  String get productUpdated;

  /// No description provided for @headerAddStock.
  ///
  /// In en, this message translates to:
  /// **'Add Stock (Restock)'**
  String get headerAddStock;

  /// No description provided for @labelQuantityToAdd.
  ///
  /// In en, this message translates to:
  /// **'Quantity to Add'**
  String get labelQuantityToAdd;

  /// No description provided for @labelNewPurchasePrice.
  ///
  /// In en, this message translates to:
  /// **'New Purchase Price (per unit)'**
  String get labelNewPurchasePrice;

  /// No description provided for @buttonAddToStock.
  ///
  /// In en, this message translates to:
  /// **'Restock'**
  String get buttonAddToStock;

  /// No description provided for @msgInvalidStockInput.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid and positive quantity and purchase price.'**
  String get msgInvalidStockInput;

  /// No description provided for @msgStockAddedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Stock added successfully and history recorded.'**
  String get msgStockAddedSuccess;

  /// No description provided for @msgStockAddFailure.
  ///
  /// In en, this message translates to:
  /// **'Failed to add stock'**
  String get msgStockAddFailure;

  /// No description provided for @headerStockHistory.
  ///
  /// In en, this message translates to:
  /// **'Restock History'**
  String get headerStockHistory;

  /// No description provided for @msgNoHistoryFound.
  ///
  /// In en, this message translates to:
  /// **'No restock history found for this product.'**
  String get msgNoHistoryFound;

  /// No description provided for @labelAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get labelAdded;

  /// No description provided for @labelPurchasePrice.
  ///
  /// In en, this message translates to:
  /// **'Purchase Price'**
  String get labelPurchasePrice;

  /// No description provided for @labelUnknownDate.
  ///
  /// In en, this message translates to:
  /// **'Unknown Date'**
  String get labelUnknownDate;

  /// No description provided for @validationInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid number.'**
  String get validationInvalidNumber;

  /// No description provided for @loadingHistoryError.
  ///
  /// In en, this message translates to:
  /// **'History loading error: {error}'**
  String loadingHistoryError(Object error);

  /// No description provided for @currencyUnit.
  ///
  /// In en, this message translates to:
  /// **'CDF'**
  String get currencyUnit;

  /// No description provided for @reportsTitle.
  ///
  /// In en, this message translates to:
  /// **'Activity Reports'**
  String get reportsTitle;

  /// No description provided for @reportsTitleUser.
  ///
  /// In en, this message translates to:
  /// **'Report - {name}'**
  String reportsTitleUser(Object name);

  /// No description provided for @reportsSelectPeriod.
  ///
  /// In en, this message translates to:
  /// **'Select Period'**
  String get reportsSelectPeriod;

  /// No description provided for @reportsDateRange.
  ///
  /// In en, this message translates to:
  /// **'Period: From {startDate} to {endDate}'**
  String reportsDateRange(Object endDate, Object startDate);

  /// No description provided for @reportsPeriodDay.
  ///
  /// In en, this message translates to:
  /// **'Day (Last 7 Days)'**
  String get reportsPeriodDay;

  /// No description provided for @reportsPeriodWeek.
  ///
  /// In en, this message translates to:
  /// **'Week (Last 12 Weeks)'**
  String get reportsPeriodWeek;

  /// No description provided for @reportsPeriodMonth.
  ///
  /// In en, this message translates to:
  /// **'Month (Last 6 Months)'**
  String get reportsPeriodMonth;

  /// No description provided for @reportsPeriodYear.
  ///
  /// In en, this message translates to:
  /// **'Year (Last 5 Years)'**
  String get reportsPeriodYear;

  /// No description provided for @reportsDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Details by Period'**
  String get reportsDetailTitle;

  /// No description provided for @reportsDetailSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Revenue: {total} {currencyUnit} • Quantity: {qty}'**
  String reportsDetailSubtitle(Object currencyUnit, Object qty, Object total);

  /// No description provided for @reportsTopProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'Top 10 Products (Full Period)'**
  String get reportsTopProductsTitle;

  /// No description provided for @reportsTopProductSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quantity sold: {qty} • Revenue: {revenue} {currencyUnit}'**
  String reportsTopProductSubtitle(
      Object currencyUnit, Object qty, Object revenue);

  /// No description provided for @reportsNoData.
  ///
  /// In en, this message translates to:
  /// **'No sales data found for the selected period and user.'**
  String get reportsNoData;

  /// No description provided for @reportsNoCategoryData.
  ///
  /// In en, this message translates to:
  /// **'No sales recorded for any category in this period.'**
  String get reportsNoCategoryData;

  /// No description provided for @noPeriodLabel.
  ///
  /// In en, this message translates to:
  /// **'None/A - Period'**
  String get noPeriodLabel;

  /// No description provided for @reportTitleForDate.
  ///
  /// In en, this message translates to:
  /// **'Report for {date}'**
  String reportTitleForDate(Object date);

  /// No description provided for @buttonPrintReport.
  ///
  /// In en, this message translates to:
  /// **'Print Report'**
  String get buttonPrintReport;

  /// No description provided for @reportStoreName.
  ///
  /// In en, this message translates to:
  /// **'Store: {name}'**
  String reportStoreName(Object name);

  /// No description provided for @reportSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Day Summary'**
  String get reportSummaryTitle;

  /// No description provided for @reportTotalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Sales Revenue (TR)'**
  String get reportTotalRevenue;

  /// No description provided for @reportTotalProfit.
  ///
  /// In en, this message translates to:
  /// **'Day Profit'**
  String get reportTotalProfit;

  /// No description provided for @reportTotalQty.
  ///
  /// In en, this message translates to:
  /// **'Total Quantity Sold'**
  String get reportTotalQty;

  /// No description provided for @reportQtyByCategory.
  ///
  /// In en, this message translates to:
  /// **'Quantity of Products Sold by Category'**
  String get reportQtyByCategory;

  /// No description provided for @reportDetailedSales.
  ///
  /// In en, this message translates to:
  /// **'Detailed Sales by Product'**
  String get reportDetailedSales;

  /// No description provided for @reportProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get reportProduct;

  /// No description provided for @reportQty.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get reportQty;

  /// No description provided for @reportAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get reportAmount;

  /// No description provided for @reportUnitsLabel.
  ///
  /// In en, this message translates to:
  /// **'units'**
  String get reportUnitsLabel;

  /// No description provided for @errorPrinting.
  ///
  /// In en, this message translates to:
  /// **'Error while printing'**
  String get errorPrinting;

  /// No description provided for @reportTopProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'Top Selling Products of the Day'**
  String get reportTopProductsTitle;

  /// No description provided for @pdfReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Sales Report'**
  String get pdfReportTitle;

  /// No description provided for @pdfStore.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get pdfStore;

  /// No description provided for @pdfReportDate.
  ///
  /// In en, this message translates to:
  /// **'Report Date'**
  String get pdfReportDate;

  /// No description provided for @pdfSummaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Summary'**
  String get pdfSummaryTitle;

  /// No description provided for @pdfTotalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Sales Revenue (TR)'**
  String get pdfTotalRevenue;

  /// No description provided for @pdfTotalQty.
  ///
  /// In en, this message translates to:
  /// **'Total Quantity Sold'**
  String get pdfTotalQty;

  /// No description provided for @pdfTotalProfit.
  ///
  /// In en, this message translates to:
  /// **'Day Profit'**
  String get pdfTotalProfit;

  /// No description provided for @pdfSalesByCategory.
  ///
  /// In en, this message translates to:
  /// **'Sales by Category'**
  String get pdfSalesByCategory;

  /// No description provided for @pdfDetailedSales.
  ///
  /// In en, this message translates to:
  /// **'Detailed Sales by Product'**
  String get pdfDetailedSales;

  /// No description provided for @pdfProduct.
  ///
  /// In en, this message translates to:
  /// **'Product'**
  String get pdfProduct;

  /// No description provided for @pdfQuantity.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get pdfQuantity;

  /// No description provided for @pdfAmountSold.
  ///
  /// In en, this message translates to:
  /// **'Amount Sold'**
  String get pdfAmountSold;

  /// No description provided for @pdfTopProductsTitle.
  ///
  /// In en, this message translates to:
  /// **'Top Selling Products of the Day'**
  String get pdfTopProductsTitle;

  /// No description provided for @pdfTopProductQty.
  ///
  /// In en, this message translates to:
  /// **'{qty} Units'**
  String pdfTopProductQty(Object qty);

  /// No description provided for @pdfCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get pdfCategory;

  /// Success message when sale is recorded and invoice is generated.
  ///
  /// In en, this message translates to:
  /// **'Sale recorded. Invoice generated for traceability.'**
  String get saleRecordedAndInvoiceGenerated;

  /// Error when user session is lost.
  ///
  /// In en, this message translates to:
  /// **'Session error. Please log in again.'**
  String get sessionError;

  /// Title of the sales invoice document.
  ///
  /// In en, this message translates to:
  /// **'SALES INVOICE'**
  String get invoiceTitle;

  /// Used for file naming and general reference.
  ///
  /// In en, this message translates to:
  /// **'Invoice'**
  String get invoiceName;

  /// Label for the total amount on the invoice.
  ///
  /// In en, this message translates to:
  /// **'TOTAL AMOUNT DUE'**
  String get invoiceTotal;

  /// Column header for product name on PDF.
  ///
  /// In en, this message translates to:
  /// **'Item'**
  String get pdfItem;

  /// Column header for quantity on PDF.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get pdfQty;

  /// Column header for unit of measure on PDF.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get pdfUnit;

  /// Column header for price per unit on PDF.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get pdfPrice;

  /// Column header for total amount per item on PDF.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get pdfTotal;

  /// Label for seller/store information on PDF.
  ///
  /// In en, this message translates to:
  /// **'Sold by'**
  String get pdfStoreInfo;

  /// Label for sale date and time on PDF.
  ///
  /// In en, this message translates to:
  /// **'Date and Time'**
  String get pdfDate;

  /// Label for payment method on PDF.
  ///
  /// In en, this message translates to:
  /// **'Payment Mode'**
  String get pdfPaymentMode;

  /// Closing message on the invoice.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your purchase made on {date}'**
  String invoiceThankYou(Object date);

  /// Traceability ID displayed on the invoice.
  ///
  /// In en, this message translates to:
  /// **'Unique Transaction ID (Traceability): {id}'**
  String invoiceTraceability(Object id);

  /// No description provided for @defaultStoreName.
  ///
  /// In en, this message translates to:
  /// **'My Business Store'**
  String get defaultStoreName;

  /// Lebo kwa ajili ya upau wa kutafutia bidhaa kwenye ukurasa wa mauzo mapya.
  ///
  /// In en, this message translates to:
  /// **'Search Product'**
  String get searchProductLabel;

  /// Maandishi ya dokezo kwa ajili ya upau wa kutafutia bidhaa.
  ///
  /// In en, this message translates to:
  /// **'Name or Category...'**
  String get searchHint;

  /// Ujumbe wakati utafutaji haupati matokeo yoyote.
  ///
  /// In en, this message translates to:
  /// **'No products match your search.'**
  String get noResultsFound;

  /// Ujumbe wakati orodha ya bidhaa ni tupu.
  ///
  /// In en, this message translates to:
  /// **'No products available. Add some to Stock.'**
  String get noProductsAvailable;

  /// Label for the delete button in a confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// Title of the dialog asking for product deletion confirmation.
  ///
  /// In en, this message translates to:
  /// **'Confirm Deletion'**
  String get confirmDeleteProductTitle;

  /// No description provided for @confirmDeleteProductMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete product {productName}? This action cannot be undone.'**
  String confirmDeleteProductMessage(Object productName);

  /// No description provided for @productDeletedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Product {productName} deleted successfully.'**
  String productDeletedSuccess(Object productName);

  /// Error message when product deletion fails.
  ///
  /// In en, this message translates to:
  /// **'Error while deleting product.'**
  String get productDeleteError;

  /// No description provided for @supplyProductTitle.
  ///
  /// In en, this message translates to:
  /// **'Restock {productName}'**
  String supplyProductTitle(Object productName);

  /// Dokezo kwa ajili ya sehemu ya kuweka kiasi katika kisanduku cha mazungumzo ya urejeshaji akiba.
  ///
  /// In en, this message translates to:
  /// **'Quantity to add'**
  String get supplyQuantityHint;

  /// Dokezo kwa ajili ya bei ya ununuzi kwa kitengo katika kisanduku cha mazungumzo ya urejeshaji akiba.
  ///
  /// In en, this message translates to:
  /// **'Purchase price per unit'**
  String get supplyPriceHint;

  /// No description provided for @supplySuccess.
  ///
  /// In en, this message translates to:
  /// **'Stock updated. Added {qty} {unit}.'**
  String supplySuccess(Object qty, Object unit);

  /// Ujumbe wa hitilafu ya jumla kwa kushindwa kwa urejeshaji akiba.
  ///
  /// In en, this message translates to:
  /// **'Error while restocking.'**
  String get supplyError;

  /// Hitilafu ya uthibitishaji kwa kuingiza kiasi katika kisanduku cha mazungumzo ya urejeshaji akiba.
  ///
  /// In en, this message translates to:
  /// **'Please enter a positive and valid quantity.'**
  String get invalidQuantityError;

  /// Validation error for purchase price in restock dialog.
  ///
  /// In en, this message translates to:
  /// **'Please enter a positive and valid purchase price per unit.'**
  String get priceValidationRestock;

  /// No description provided for @traceabilityHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Restock History: {productName}'**
  String traceabilityHistoryTitle(Object productName);

  /// Ujumbe unaoonyeshwa wakati historia ya urejeshaji akiba haina kitu.
  ///
  /// In en, this message translates to:
  /// **'No restock history recorded for this product.'**
  String get traceabilityEmpty;

  /// Lebo kwa ajili ya tarehe ya kuingiza akiba.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get atDate;

  /// Lebo kwa ajili ya bei ya ununuzi kwa kitengo katika kuingiza akiba.
  ///
  /// In en, this message translates to:
  /// **'Unit Price'**
  String get atPrice;

  /// Kibadilishaji nafasi wakati tarehe ya urejeshaji akiba haipatikani.
  ///
  /// In en, this message translates to:
  /// **'Unknown Date'**
  String get dateUnknown;

  /// Lebo kwa ajili ya kitufe cha kufunga kisanduku cha mazungumzo.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeButton;

  /// No description provided for @formatDate.
  ///
  /// In en, this message translates to:
  /// **'{date}'**
  String formatDate(Object date);

  /// No description provided for @okButton.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okButton;

  /// No description provided for @categoryNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get categoryNone;

  /// No description provided for @optionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get optionalLabel;

  /// No description provided for @settingsAboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAboutTitle;

  /// No description provided for @invalidPrice.
  ///
  /// In en, this message translates to:
  /// **'Invalid price'**
  String get invalidPrice;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Session expired'**
  String get sessionExpired;

  /// No description provided for @genericError.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get genericError;

  /// No description provided for @aboutAppDescription.
  ///
  /// In en, this message translates to:
  /// **'This app allows you to efficiently and securely manage your sales and inventory.'**
  String get aboutAppDescription;

  /// No description provided for @aboutAppPolicy.
  ///
  /// In en, this message translates to:
  /// **'We respect your privacy and personal data according to our policy.'**
  String get aboutAppPolicy;

  /// No description provided for @aboutAppContact.
  ///
  /// In en, this message translates to:
  /// **'Contact us: +243974084668, Andrelukengu67@gmail.com, Lubumbashi, Haut-Katanga'**
  String get aboutAppContact;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr', 'sw'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'sw':
      return AppLocalizationsSw();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
