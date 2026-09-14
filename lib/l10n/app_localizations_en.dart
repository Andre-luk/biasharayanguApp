// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get settingsTitle => 'Settings';

  @override
  String get profileTitle => 'My Profile';

  @override
  String get profileSubtitle => 'View and edit personal information';

  @override
  String get manageUsersTitle => 'Manage Users';

  @override
  String get manageUsersSubtitle => 'Create, validate, and manage access';

  @override
  String get changePasswordTitle => 'Change Password';

  @override
  String get changePasswordSubtitle => 'Update your login credentials';

  @override
  String get languageTitle => 'App Language';

  @override
  String get helpAndSupportTitle => 'Help and Support';

  @override
  String get logoutButton => 'Logout';

  @override
  String get currentLanguageLabel => 'Current:';

  @override
  String get chooseLanguageDialogTitle => 'Choose Language 🌐';

  @override
  String get applyButton => 'Apply';

  @override
  String get cancelButton => 'Cancel';

  @override
  String get adminSectionTitle => 'Admin Tools';

  @override
  String get manageCategories => 'Manage Categories';

  @override
  String get manageCategoriesSubtitle =>
      'Add, edit, or delete product categories';

  @override
  String get statStockStatus => 'Stock Status';

  @override
  String statStockLowCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Products are Low',
      one: '1 Product is Low',
      zero: 'Everything is OK',
    );
    return '$_temp0';
  }

  @override
  String get errorLoadingStats =>
      'An error occurred while loading stats. Showing general data.';

  @override
  String get statDailySales => 'Today\'s Sales';

  @override
  String get statTotalSalesOverall => 'Total Overall Sales';

  @override
  String get user => 'User';

  @override
  String get statisticsTitle => 'Statistics';

  @override
  String get statTotalSales => 'Total Sales';

  @override
  String get statSalesCount => 'Sales (count)';

  @override
  String get statProductsCount => 'Products';

  @override
  String get statClientsCount => 'Clients';

  @override
  String get buttonAddProduct => 'Add Product';

  @override
  String get productUnitDefault => 'unit';

  @override
  String get buttonManageStock => 'Manage Stock';

  @override
  String get buttonNewSale => 'New Sale';

  @override
  String get buttonReports => 'Reports';

  @override
  String get navHome => 'Home';

  @override
  String get navStock => 'Stock';

  @override
  String get navReports => 'Reports';

  @override
  String get navSettings => 'Settings';

  @override
  String homeWelcomeMessage(Object name) {
    return 'Welcome $name — Enjoy good sales!';
  }

  @override
  String homeSummaryGreeting(Object name) {
    return 'Hello $name';
  }

  @override
  String homeSummaryProductsSales(num productCount, num salesCount) {
    String _temp0 = intl.Intl.pluralLogic(
      productCount,
      locale: localeName,
      other: '$productCount products',
      one: 'one product',
      zero: 'no products',
    );
    String _temp1 = intl.Intl.pluralLogic(
      salesCount,
      locale: localeName,
      other: '$salesCount sales',
      one: 'one sale',
      zero: 'no sales',
    );
    return 'You have $_temp0 and $_temp1.';
  }

  @override
  String get themeTitle => 'App Theme';

  @override
  String get currentThemeLabel => 'Current:';

  @override
  String get chooseThemeDialogTitle => 'Choose Theme 🎨';

  @override
  String get themeSystem => 'System Default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get notificationsTitle => 'Notifications and Alerts';

  @override
  String lowStockAlert(int lowStockCount) {
    String _temp0 = intl.Intl.pluralLogic(
      lowStockCount,
      locale: localeName,
      other: '$lowStockCount products',
      one: '1 product',
    );
    return 'Low Stock Alert: $_temp0 need restocking.';
  }

  @override
  String get lowStockAlertSubtitle =>
      'Click here to view the list and reorder.';

  @override
  String get addProductTitle => 'New Product';

  @override
  String get categoryOther => 'Other';

  @override
  String get categoryRequired => 'Please select a category.';

  @override
  String get priceValidation =>
      'Purchase and selling prices must be greater than zero.';

  @override
  String get priceMarkupValidation =>
      'Selling price must be greater than purchase price.';

  @override
  String get productSaved => 'Product saved successfully!';

  @override
  String get saving => 'Saving...';

  @override
  String get saveError => 'Error while saving';

  @override
  String get productNameLabel => 'Product Name';

  @override
  String get productCategoryLabel => 'Category';

  @override
  String get productPriceCost => 'Purchase Price';

  @override
  String get productPriceSell => 'Selling Price';

  @override
  String get productQuantityLabel => 'Stock Quantity';

  @override
  String get nameRequired => 'Name is required';

  @override
  String get priceRequired => 'Price is required';

  @override
  String get quantityRequired => 'Quantity is required';

  @override
  String get saveButton => 'Save Product';

  @override
  String get photoOptionTitle => 'Add Photo';

  @override
  String get photoOptionGallery => 'Choose from Gallery';

  @override
  String get photoOptionCamera => 'Take a Photo';

  @override
  String get photoOptionDelete => 'Delete current photo';

  @override
  String get changePhoto => 'Change Photo';

  @override
  String get addPhoto => 'Add Photo';

  @override
  String errorGallery(Object error) {
    return 'Gallery Error: $error';
  }

  @override
  String errorCamera(Object error) {
    return 'Camera Error: $error';
  }

  @override
  String loadingError(Object error) {
    return 'Loading error: $error';
  }

  @override
  String get internalLoadingError => 'Internal loading error.';

  @override
  String get loginWelcome => 'Welcome';

  @override
  String get loginEmailLabel => 'Email';

  @override
  String get loginPinLabel => 'PIN';

  @override
  String get loginButton => 'Login';

  @override
  String get loginCreateStore => 'Create Store';

  @override
  String get emailRequired => 'Email is required.';

  @override
  String get pinRequired => 'PIN is required.';

  @override
  String get pinInvalid => 'Invalid PIN (min 4 digits, not 0000/1234).';

  @override
  String get loginErrorCredentials => 'Incorrect email or PIN';

  @override
  String get loginErrorPending => 'Account pending administrator validation';

  @override
  String get loginErrorGeneric => 'Error while logging in';

  @override
  String get loginBiometricButton => 'Login with Fingerprint / Face ID';

  @override
  String get biometricPrompt => 'Please authenticate to log in to My Business.';

  @override
  String get biometricLoginFailed => 'Login failed. Please use Email/PIN.';

  @override
  String get biometricNoUser => 'Please log in first using Email/PIN.';

  @override
  String get biometricError =>
      'Biometric authentication error. Please try again.';

  @override
  String get productAdded => 'Product added successfully';

  @override
  String get setupTitleNewStore => 'Create New Store';

  @override
  String get setupTitleNewUser => 'Create New User';

  @override
  String get setupTitleEdit => 'Edit User';

  @override
  String get setupLabelName => 'Full Name';

  @override
  String get setupLabelEmail => 'Email (Identifier)';

  @override
  String get setupLabelPin => 'Login PIN (4+ digits)';

  @override
  String get setupLabelRole => 'Role';

  @override
  String get roleVendor => 'Vendor';

  @override
  String get roleAdmin => 'Admin';

  @override
  String get setupButtonCreate => 'Create Account';

  @override
  String get setupNoticeValidation =>
      'Note: Created accounts will be pending administrator validation.';

  @override
  String get setupInitialSuccess =>
      'Account created. Please log in after validation.';

  @override
  String get userCreatedSuccess => 'User created successfully.';

  @override
  String get userUpdatedSuccess => 'User updated successfully.';

  @override
  String get setupErrorGeneric => 'Error while saving';

  @override
  String get unitLabel => 'Unit';

  @override
  String get unitRequired => 'Unit is required.';

  @override
  String get unitUnity => 'unit';

  @override
  String get unitKg => 'kg';

  @override
  String get unitDozen => 'dozen';

  @override
  String get unitLiter => 'liter';

  @override
  String get unitMeter => 'meter';

  @override
  String get errorLoadingData =>
      'Failed to load data. Please retry or check your connection.';

  @override
  String get newSaleTitle => 'New Sale';

  @override
  String get errorUserNotLoggedIn =>
      'Error: User session lost. Please log in again.';

  @override
  String get clientNewTitle => 'New Client';

  @override
  String get clientAddedSuccess => 'Client added successfully.';

  @override
  String get errorSavingClient => 'Error while saving client';

  @override
  String get errorSavingClientGeneric => 'Unexpected error while saving.';

  @override
  String get fieldName => 'Full Name';

  @override
  String get fieldPhone => 'Phone';

  @override
  String get fieldEmail => 'Email';

  @override
  String get validationNameRequired => 'Name is required.';

  @override
  String get validationEmailInvalid => 'Please enter a valid email address.';

  @override
  String get buttonSaveClient => 'Save Client';

  @override
  String productSubtitle(Object price, Object stock, Object unit) {
    return 'Price: $price • Stock: $stock $unit';
  }

  @override
  String addToCartTitle(Object productName) {
    return 'Add $productName';
  }

  @override
  String dialogQuantityLabel(Object unit) {
    return 'Quantity ($unit)';
  }

  @override
  String get invalidQuantity => 'Invalid quantity';

  @override
  String insufficientStock(Object maxStock, Object unit) {
    return 'Insufficient stock. Max: $maxStock $unit';
  }

  @override
  String get outOfStock => 'Product out of stock.';

  @override
  String totalAmount(Object amount, Object currencyUnit) {
    return 'Total: $amount $currencyUnit';
  }

  @override
  String get paymentModeHint => 'Payment Mode';

  @override
  String paymentMode(Object mode) {
    return '$mode';
  }

  @override
  String get recordSaleButton => 'Record Sale';

  @override
  String get saleRecorded => 'Sale recorded successfully.';

  @override
  String get saleError => 'Error while recording sale';

  @override
  String get permissionDenied => 'Permission denied.';

  @override
  String get addButton => 'Add';

  @override
  String get stockManagementTitle => 'Stock & Pricing';

  @override
  String get searchProductHint => 'Search product or category...';

  @override
  String addedToSale(Object produitName) {
    return 'Product $produitName added to sale';
  }

  @override
  String get updateButton => 'Update Product Info';

  @override
  String get productUpdated => 'Product information updated successfully.';

  @override
  String get headerAddStock => 'Add Stock (Restock)';

  @override
  String get labelQuantityToAdd => 'Quantity to Add';

  @override
  String get labelNewPurchasePrice => 'New Purchase Price (per unit)';

  @override
  String get buttonAddToStock => 'Restock';

  @override
  String get msgInvalidStockInput =>
      'Please enter a valid and positive quantity and purchase price.';

  @override
  String get msgStockAddedSuccess =>
      'Stock added successfully and history recorded.';

  @override
  String get msgStockAddFailure => 'Failed to add stock';

  @override
  String get headerStockHistory => 'Restock History';

  @override
  String get msgNoHistoryFound => 'No restock history found for this product.';

  @override
  String get labelAdded => 'Added';

  @override
  String get labelPurchasePrice => 'Purchase Price';

  @override
  String get labelUnknownDate => 'Unknown Date';

  @override
  String get validationInvalidNumber => 'Please enter a valid number.';

  @override
  String loadingHistoryError(Object error) {
    return 'History loading error: $error';
  }

  @override
  String get currencyUnit => 'CDF';

  @override
  String get reportsTitle => 'Activity Reports';

  @override
  String reportsTitleUser(Object name) {
    return 'Report - $name';
  }

  @override
  String get reportsSelectPeriod => 'Select Period';

  @override
  String reportsDateRange(Object endDate, Object startDate) {
    return 'Period: From $startDate to $endDate';
  }

  @override
  String get reportsPeriodDay => 'Day (Last 7 Days)';

  @override
  String get reportsPeriodWeek => 'Week (Last 12 Weeks)';

  @override
  String get reportsPeriodMonth => 'Month (Last 6 Months)';

  @override
  String get reportsPeriodYear => 'Year (Last 5 Years)';

  @override
  String get reportsDetailTitle => 'Details by Period';

  @override
  String reportsDetailSubtitle(Object currencyUnit, Object qty, Object total) {
    return 'Revenue: $total $currencyUnit • Quantity: $qty';
  }

  @override
  String get reportsTopProductsTitle => 'Top 10 Products (Full Period)';

  @override
  String reportsTopProductSubtitle(
      Object currencyUnit, Object qty, Object revenue) {
    return 'Quantity sold: $qty • Revenue: $revenue $currencyUnit';
  }

  @override
  String get reportsNoData =>
      'No sales data found for the selected period and user.';

  @override
  String get reportsNoCategoryData =>
      'No sales recorded for any category in this period.';

  @override
  String get noPeriodLabel => 'None/A - Period';

  @override
  String reportTitleForDate(Object date) {
    return 'Report for $date';
  }

  @override
  String get buttonPrintReport => 'Print Report';

  @override
  String reportStoreName(Object name) {
    return 'Store: $name';
  }

  @override
  String get reportSummaryTitle => 'Day Summary';

  @override
  String get reportTotalRevenue => 'Total Sales Revenue (TR)';

  @override
  String get reportTotalProfit => 'Day Profit';

  @override
  String get reportTotalQty => 'Total Quantity Sold';

  @override
  String get reportQtyByCategory => 'Quantity of Products Sold by Category';

  @override
  String get reportDetailedSales => 'Detailed Sales by Product';

  @override
  String get reportProduct => 'Product';

  @override
  String get reportQty => 'Quantity';

  @override
  String get reportAmount => 'Amount';

  @override
  String get reportUnitsLabel => 'units';

  @override
  String get errorPrinting => 'Error while printing';

  @override
  String get reportTopProductsTitle => 'Top Selling Products of the Day';

  @override
  String get pdfReportTitle => 'Daily Sales Report';

  @override
  String get pdfStore => 'Store';

  @override
  String get pdfReportDate => 'Report Date';

  @override
  String get pdfSummaryTitle => 'Daily Summary';

  @override
  String get pdfTotalRevenue => 'Total Sales Revenue (TR)';

  @override
  String get pdfTotalQty => 'Total Quantity Sold';

  @override
  String get pdfTotalProfit => 'Day Profit';

  @override
  String get pdfSalesByCategory => 'Sales by Category';

  @override
  String get pdfDetailedSales => 'Detailed Sales by Product';

  @override
  String get pdfProduct => 'Product';

  @override
  String get pdfQuantity => 'Quantity';

  @override
  String get pdfAmountSold => 'Amount Sold';

  @override
  String get pdfTopProductsTitle => 'Top Selling Products of the Day';

  @override
  String pdfTopProductQty(Object qty) {
    return '$qty Units';
  }

  @override
  String get pdfCategory => 'Category';

  @override
  String get saleRecordedAndInvoiceGenerated =>
      'Sale recorded. Invoice generated for traceability.';

  @override
  String get sessionError => 'Session error. Please log in again.';

  @override
  String get invoiceTitle => 'SALES INVOICE';

  @override
  String get invoiceName => 'Invoice';

  @override
  String get invoiceTotal => 'TOTAL AMOUNT DUE';

  @override
  String get pdfItem => 'Item';

  @override
  String get pdfQty => 'Qty';

  @override
  String get pdfUnit => 'Unit';

  @override
  String get pdfPrice => 'Unit Price';

  @override
  String get pdfTotal => 'Total';

  @override
  String get pdfStoreInfo => 'Sold by';

  @override
  String get pdfDate => 'Date and Time';

  @override
  String get pdfPaymentMode => 'Payment Mode';

  @override
  String invoiceThankYou(Object date) {
    return 'Thank you for your purchase made on $date';
  }

  @override
  String invoiceTraceability(Object id) {
    return 'Unique Transaction ID (Traceability): $id';
  }

  @override
  String get defaultStoreName => 'My Business Store';

  @override
  String get searchProductLabel => 'Search Product';

  @override
  String get searchHint => 'Name or Category...';

  @override
  String get noResultsFound => 'No products match your search.';

  @override
  String get noProductsAvailable => 'No products available. Add some to Stock.';

  @override
  String get deleteButton => 'Delete';

  @override
  String get confirmDeleteProductTitle => 'Confirm Deletion';

  @override
  String confirmDeleteProductMessage(Object productName) {
    return 'Are you sure you want to delete product $productName? This action cannot be undone.';
  }

  @override
  String productDeletedSuccess(Object productName) {
    return 'Product $productName deleted successfully.';
  }

  @override
  String get productDeleteError => 'Error while deleting product.';

  @override
  String supplyProductTitle(Object productName) {
    return 'Restock $productName';
  }

  @override
  String get supplyQuantityHint => 'Quantity to add';

  @override
  String get supplyPriceHint => 'Purchase price per unit';

  @override
  String supplySuccess(Object qty, Object unit) {
    return 'Stock updated. Added $qty $unit.';
  }

  @override
  String get supplyError => 'Error while restocking.';

  @override
  String get invalidQuantityError =>
      'Please enter a positive and valid quantity.';

  @override
  String get priceValidationRestock =>
      'Please enter a positive and valid purchase price per unit.';

  @override
  String traceabilityHistoryTitle(Object productName) {
    return 'Restock History: $productName';
  }

  @override
  String get traceabilityEmpty =>
      'No restock history recorded for this product.';

  @override
  String get atDate => 'Date';

  @override
  String get atPrice => 'Unit Price';

  @override
  String get dateUnknown => 'Unknown Date';

  @override
  String get closeButton => 'Close';

  @override
  String formatDate(Object date) {
    return '$date';
  }

  @override
  String get okButton => 'OK';

  @override
  String get categoryNone => 'None';

  @override
  String get optionalLabel => 'Optional';

  @override
  String get settingsAboutTitle => 'About';

  @override
  String get invalidPrice => 'Invalid price';

  @override
  String get sessionExpired => 'Session expired';

  @override
  String get genericError => 'An error occurred';

  @override
  String get aboutAppDescription =>
      'This app allows you to efficiently and securely manage your sales and inventory.';

  @override
  String get aboutAppPolicy =>
      'We respect your privacy and personal data according to our policy.';

  @override
  String get aboutAppContact =>
      'Contact us: +243974084668, Andrelukengu67@gmail.com, Lubumbashi, Haut-Katanga';
}
