// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swahili (`sw`).
class AppLocalizationsSw extends AppLocalizations {
  AppLocalizationsSw([String locale = 'sw']) : super(locale);

  @override
  String get settingsTitle => 'Mipangilio';

  @override
  String get profileTitle => 'Wasifu Wangu';

  @override
  String get profileSubtitle => 'Angalia na ubadilishe maelezo ya kibinafsi';

  @override
  String get manageUsersTitle => 'Dhibiti Watumiaji';

  @override
  String get manageUsersSubtitle => 'Unda, thibitisha na udhibiti ufikiaji';

  @override
  String get changePasswordTitle => 'Badilisha Nenosiri';

  @override
  String get changePasswordSubtitle => 'Sasisha vitambulisho vyako vya kuingia';

  @override
  String get languageTitle => 'Lugha ya Programu';

  @override
  String get helpAndSupportTitle => 'Msaada na Usaidizi';

  @override
  String get logoutButton => 'Ondoka';

  @override
  String get currentLanguageLabel => 'Sasa:';

  @override
  String get chooseLanguageDialogTitle => 'Chagua Lugha 🌐';

  @override
  String get applyButton => 'Tuma';

  @override
  String get cancelButton => 'Ghairi';

  @override
  String get adminSectionTitle => 'Zana za Utawala';

  @override
  String get manageCategories => 'Dhibiti Kategoria';

  @override
  String get manageCategoriesSubtitle =>
      'Ongeza, hariri, au futa kategoria za bidhaa';

  @override
  String get statStockStatus => 'Hali ya Akiba';

  @override
  String statStockLowCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bidhaa $count Ziko Chini',
      one: 'Bidhaa 1 Iko Chini',
      zero: 'Kila kitu Sawa',
    );
    return '$_temp0';
  }

  @override
  String get errorLoadingStats =>
      'Hitilafu imetokea wakati wa kupakia takwimu. Inaonyesha data ya jumla.';

  @override
  String get statDailySales => 'Mauzo ya Leo';

  @override
  String get statTotalSalesOverall => 'Jumla ya Mauzo Yote';

  @override
  String get user => 'Mtumiaji';

  @override
  String get statisticsTitle => 'Takwimu';

  @override
  String get statTotalSales => 'Jumla ya Mauzo';

  @override
  String get statSalesCount => 'Mauzo (idadi)';

  @override
  String get statProductsCount => 'Bidhaa';

  @override
  String get statClientsCount => 'Wateja';

  @override
  String get buttonAddProduct => 'Ongeza Bidhaa';

  @override
  String get productUnitDefault => 'kitengo';

  @override
  String get buttonManageStock => 'Dhibiti Hisa';

  @override
  String get buttonNewSale => 'Mauzo Mapya';

  @override
  String get buttonReports => 'Ripoti';

  @override
  String get navHome => 'Nyumbani';

  @override
  String get navStock => 'Hisa';

  @override
  String get navReports => 'Ripoti';

  @override
  String get navSettings => 'Mipangilio';

  @override
  String homeWelcomeMessage(Object name) {
    return 'Karibu $name — Furahia mauzo mema!';
  }

  @override
  String homeSummaryGreeting(Object name) {
    return 'Jambo $name';
  }

  @override
  String homeSummaryProductsSales(num productCount, num salesCount) {
    String _temp0 = intl.Intl.pluralLogic(
      productCount,
      locale: localeName,
      other: 'bidhaa $productCount',
      one: 'bidhaa moja',
      zero: 'hakuna bidhaa',
    );
    String _temp1 = intl.Intl.pluralLogic(
      salesCount,
      locale: localeName,
      other: 'mauzo $salesCount',
      one: 'mauzo moja',
      zero: 'hakuna mauzo',
    );
    return 'Una $_temp0 na $_temp1.';
  }

  @override
  String get themeTitle => 'Mandhari ya Programu';

  @override
  String get currentThemeLabel => 'Sasa:';

  @override
  String get chooseThemeDialogTitle => 'Chagua Mandhari 🎨';

  @override
  String get themeSystem => 'Mfumo Chaguomsingi';

  @override
  String get themeLight => 'Mweupe';

  @override
  String get themeDark => 'Mweusi';

  @override
  String get notificationsTitle => 'Arifa na Maonyo';

  @override
  String lowStockAlert(int lowStockCount) {
    String _temp0 = intl.Intl.pluralLogic(
      lowStockCount,
      locale: localeName,
      other: '$lowStockCount',
      one: '1',
    );
    return 'Onyo Akiba Chini: Bidhaa $_temp0 zinahitaji kuongezwa.';
  }

  @override
  String get lowStockAlertSubtitle =>
      'Bonyeza hapa kuona orodha na kuagiza tena.';

  @override
  String get addProductTitle => 'Bidhaa Mpya';

  @override
  String get categoryOther => 'Nyingine';

  @override
  String get categoryRequired => 'Tafadhali chagua kategoria.';

  @override
  String get priceValidation =>
      'Bei ya kununua na kuuza lazima ziwe kubwa kuliko sifuri.';

  @override
  String get priceMarkupValidation =>
      'Bei ya kuuza lazima iwe kubwa zaidi kuliko bei ya kununua.';

  @override
  String get productSaved => 'Bidhaa imehifadhiwa kwa mafanikio!';

  @override
  String get saving => 'Inahifadhi...';

  @override
  String get saveError => 'Hitilafu wakati wa kuhifadhi';

  @override
  String get productNameLabel => 'Jina la Bidhaa';

  @override
  String get productCategoryLabel => 'Kategoria';

  @override
  String get productPriceCost => 'Bei ya Kununua';

  @override
  String get productPriceSell => 'Bei ya Kuuza';

  @override
  String get productQuantityLabel => 'Kiasi cha Akiba';

  @override
  String get nameRequired => 'Jina linahitajika';

  @override
  String get priceRequired => 'Bei inahitajika';

  @override
  String get quantityRequired => 'Kiasi kinahitajika';

  @override
  String get saveButton => 'Hifadhi Bidhaa';

  @override
  String get photoOptionTitle => 'Ongeza Picha';

  @override
  String get photoOptionGallery => 'Chagua kutoka kwenye Ghala';

  @override
  String get photoOptionCamera => 'Piga Picha';

  @override
  String get photoOptionDelete => 'Futa picha ya sasa';

  @override
  String get changePhoto => 'Badilisha Picha';

  @override
  String get addPhoto => 'Ongeza Picha';

  @override
  String errorGallery(Object error) {
    return 'Hitilafu ya Ghala: $error';
  }

  @override
  String errorCamera(Object error) {
    return 'Hitilafu ya Kamera: $error';
  }

  @override
  String loadingError(Object error) {
    return 'Hitilafu ya kupakia: $error';
  }

  @override
  String get internalLoadingError => 'Hitilafu ya ndani ya kupakia.';

  @override
  String get loginWelcome => 'Karibu';

  @override
  String get loginEmailLabel => 'Barua pepe';

  @override
  String get loginPinLabel => 'PIN';

  @override
  String get loginButton => 'Ingia';

  @override
  String get loginCreateStore => 'Unda Duka';

  @override
  String get emailRequired => 'Barua pepe inahitajika.';

  @override
  String get pinRequired => 'PIN inahitajika.';

  @override
  String get pinInvalid => 'PIN si sahihi (min namba 4, si 0000/1234).';

  @override
  String get loginErrorCredentials => 'Barua pepe au PIN si sahihi';

  @override
  String get loginErrorPending => 'Akaunti inasubiri uthibitisho wa msimamizi';

  @override
  String get loginErrorGeneric => 'Hitilafu wakati wa kuingia';

  @override
  String get loginBiometricButton =>
      'Ingia kwa Alama ya Vidole / Kitambulisho cha Uso';

  @override
  String get biometricPrompt =>
      'Tafadhali thibitisha ili kuingia kwenye Biashara Yangu.';

  @override
  String get biometricLoginFailed =>
      'Kuingia kumeshindwa. Tafadhali tumia Barua pepe/PIN.';

  @override
  String get biometricNoUser =>
      'Tafadhali ingia kwanza kwa kutumia Barua pepe/PIN.';

  @override
  String get biometricError =>
      'Hitilafu ya uthibitishaji wa kibayometriki. Tafadhali jaribu tena.';

  @override
  String get productAdded => 'Bidhaa imeongezwa kwa mafanikio';

  @override
  String get setupTitleNewStore => 'Unda Duka Jipya';

  @override
  String get setupTitleNewUser => 'Unda Mtumiaji Mpya';

  @override
  String get setupTitleEdit => 'Hariri Mtumiaji';

  @override
  String get setupLabelName => 'Jina Kamili';

  @override
  String get setupLabelEmail => 'Barua pepe (Kitambulisho)';

  @override
  String get setupLabelPin => 'PIN ya kuingia (namba 4+)';

  @override
  String get setupLabelRole => 'Jukumu';

  @override
  String get roleVendor => 'Muuzaji';

  @override
  String get roleAdmin => 'Msimamizi';

  @override
  String get setupButtonCreate => 'Unda Akaunti';

  @override
  String get setupNoticeValidation =>
      'Kumbuka: Akaunti zilizoundwa zitasubiri uthibitisho wa msimamizi.';

  @override
  String get setupInitialSuccess =>
      'Akaunti imeundwa. Tafadhali ingia baada ya uthibitisho.';

  @override
  String get userCreatedSuccess => 'Mtumiaji ameundwa kwa mafanikio.';

  @override
  String get userUpdatedSuccess => 'Mtumiaji amesasishwa kwa mafanikio.';

  @override
  String get setupErrorGeneric => 'Hitilafu wakati wa kuhifadhi';

  @override
  String get unitLabel => 'Kitengo';

  @override
  String get unitRequired => 'Kitengo kinahitajika.';

  @override
  String get unitUnity => 'kitengo';

  @override
  String get unitKg => 'kg';

  @override
  String get unitDozen => 'dosari';

  @override
  String get unitLiter => 'lita';

  @override
  String get unitMeter => 'mita';

  @override
  String get errorLoadingData =>
      'Imeshindwa kupakia data. Jaribu tena au angalia muunganisho wako.';

  @override
  String get newSaleTitle => 'Mauzo Mapya';

  @override
  String get errorUserNotLoggedIn =>
      'Hitilafu: Kipindi cha mtumiaji kimepotea. Tafadhali ingia tena.';

  @override
  String get clientNewTitle => 'Mteja Mpya';

  @override
  String get clientAddedSuccess => 'Mteja ameongezwa kwa mafanikio.';

  @override
  String get errorSavingClient => 'Hitilafu wakati wa kuhifadhi mteja';

  @override
  String get errorSavingClientGeneric =>
      'Hitilafu isiyotarajiwa wakati wa kuhifadhi.';

  @override
  String get fieldName => 'Jina Kamili';

  @override
  String get fieldPhone => 'Simu';

  @override
  String get fieldEmail => 'Barua pepe';

  @override
  String get validationNameRequired => 'Jina linahitajika.';

  @override
  String get validationEmailInvalid =>
      'Tafadhali ingiza anwani ya barua pepe halali.';

  @override
  String get buttonSaveClient => 'Hifadhi Mteja';

  @override
  String productSubtitle(Object price, Object stock, Object unit) {
    return 'Bei: $price • Akiba: $stock $unit';
  }

  @override
  String addToCartTitle(Object productName) {
    return 'Ongeza $productName';
  }

  @override
  String dialogQuantityLabel(Object unit) {
    return 'Kiasi ($unit)';
  }

  @override
  String get invalidQuantity => 'Kiasi si sahihi';

  @override
  String insufficientStock(Object maxStock, Object unit) {
    return 'Akiba haitoshi. Max: $maxStock $unit';
  }

  @override
  String get outOfStock => 'Bidhaa imeisha.';

  @override
  String totalAmount(Object amount, Object currencyUnit) {
    return 'Jumla: $amount $currencyUnit';
  }

  @override
  String get paymentModeHint => 'Njia ya Malipo';

  @override
  String paymentMode(Object mode) {
    return '$mode';
  }

  @override
  String get recordSaleButton => 'Rekodi Mauzo';

  @override
  String get saleRecorded => 'Mauzo yamerekodiwa kwa mafanikio.';

  @override
  String get saleError => 'Hitilafu wakati wa kurekodi mauzo';

  @override
  String get permissionDenied => 'Ruhusa imekataliwa.';

  @override
  String get addButton => 'Ongeza';

  @override
  String get stockManagementTitle => 'Akiba & Bei';

  @override
  String get searchProductHint => 'Tafuta bidhaa au kategoria...';

  @override
  String addedToSale(Object produitName) {
    return 'Bidhaa $produitName imeongezwa kwenye mauzo';
  }

  @override
  String get updateButton => 'Sasisha Taarifa ya Bidhaa';

  @override
  String get productUpdated => 'Taarifa ya bidhaa imesasishwa kwa mafanikio.';

  @override
  String get headerAddStock => 'Ongeza Akiba (Rejesha)';

  @override
  String get labelQuantityToAdd => 'Kiasi cha Kuongeza';

  @override
  String get labelNewPurchasePrice => 'Bei Mpya ya Kununua (kwa kitengo)';

  @override
  String get buttonAddToStock => 'Rejesha Akiba';

  @override
  String get msgInvalidStockInput =>
      'Tafadhali ingiza kiasi sahihi na chanya na bei ya kununua.';

  @override
  String get msgStockAddedSuccess =>
      'Akiba imeongezwa kwa mafanikio na historia kurekodiwa.';

  @override
  String get msgStockAddFailure => 'Imeshindwa kuongeza akiba';

  @override
  String get headerStockHistory => 'Historia ya Urejeshaji Akiba';

  @override
  String get msgNoHistoryFound =>
      'Hakuna historia ya urejeshaji akiba iliyopatikana kwa bidhaa hii.';

  @override
  String get labelAdded => 'Imeongezwa';

  @override
  String get labelPurchasePrice => 'Bei ya Kununua';

  @override
  String get labelUnknownDate => 'Tarehe Isiyojulikana';

  @override
  String get validationInvalidNumber => 'Tafadhali ingiza namba halali.';

  @override
  String loadingHistoryError(Object error) {
    return 'Hitilafu ya kupakia historia: $error';
  }

  @override
  String get currencyUnit => 'CDF';

  @override
  String get reportsTitle => 'Ripoti za Shughuli';

  @override
  String reportsTitleUser(Object name) {
    return 'Ripoti - $name';
  }

  @override
  String get reportsSelectPeriod => 'Chagua Kipindi';

  @override
  String reportsDateRange(Object endDate, Object startDate) {
    return 'Kipindi: Kutoka $startDate hadi $endDate';
  }

  @override
  String get reportsPeriodDay => 'Siku (Siku 7 Zilizopita)';

  @override
  String get reportsPeriodWeek => 'Wiki (Wiki 12 Zilizopita)';

  @override
  String get reportsPeriodMonth => 'Mwezi (Miezi 6 Iliyopita)';

  @override
  String get reportsPeriodYear => 'Mwaka (Miaka 5 Iliyopita)';

  @override
  String get reportsDetailTitle => 'Maelezo kwa Kipindi';

  @override
  String reportsDetailSubtitle(Object currencyUnit, Object qty, Object total) {
    return 'Mapato: $total $currencyUnit • Kiasi: $qty';
  }

  @override
  String get reportsTopProductsTitle => 'Bidhaa 10 Bora (Kipindi Kamili)';

  @override
  String reportsTopProductSubtitle(
      Object currencyUnit, Object qty, Object revenue) {
    return 'Kiasi kilichouzwa: $qty • Mapato: $revenue $currencyUnit';
  }

  @override
  String get reportsNoData =>
      'Hakuna data ya mauzo iliyopatikana kwa kipindi na mtumiaji aliyechaguliwa.';

  @override
  String get reportsNoCategoryData =>
      'Hakuna mauzo yaliyorekodiwa kwa kategoria yoyote katika kipindi hiki.';

  @override
  String get noPeriodLabel => 'Haina/A - Kipindi';

  @override
  String reportTitleForDate(Object date) {
    return 'Ripoti ya $date';
  }

  @override
  String get buttonPrintReport => 'Chapisha Ripoti';

  @override
  String reportStoreName(Object name) {
    return 'Duka: $name';
  }

  @override
  String get reportSummaryTitle => 'Muhtasari wa Siku';

  @override
  String get reportTotalRevenue => 'Jumla ya Mapato ya Mauzo (TR)';

  @override
  String get reportTotalProfit => 'Faida ya Siku';

  @override
  String get reportTotalQty => 'Jumla ya Kiasi Kilichouzwa';

  @override
  String get reportQtyByCategory => 'Kiasi cha Bidhaa Zilizouzwa kwa Kategoria';

  @override
  String get reportDetailedSales => 'Maelezo ya Mauzo kwa Bidhaa';

  @override
  String get reportProduct => 'Bidhaa';

  @override
  String get reportQty => 'Kiasi';

  @override
  String get reportAmount => 'Kiasi';

  @override
  String get reportUnitsLabel => 'vitengo';

  @override
  String get errorPrinting => 'Hitilafu wakati wa kuchapisha';

  @override
  String get reportTopProductsTitle => 'Bidhaa Zinazouza Zaidi kwa Siku';

  @override
  String get pdfReportTitle => 'Ripoti ya Mauzo ya Kila Siku';

  @override
  String get pdfStore => 'Duka';

  @override
  String get pdfReportDate => 'Tarehe ya Ripoti';

  @override
  String get pdfSummaryTitle => 'Muhtasari wa Siku';

  @override
  String get pdfTotalRevenue => 'Jumla ya Mapato ya Mauzo (TR)';

  @override
  String get pdfTotalQty => 'Jumla ya Kiasi Kilichouzwa';

  @override
  String get pdfTotalProfit => 'Faida ya Siku';

  @override
  String get pdfSalesByCategory => 'Mauzo kwa Kategoria';

  @override
  String get pdfDetailedSales => 'Maelezo ya Mauzo kwa Bidhaa';

  @override
  String get pdfProduct => 'Bidhaa';

  @override
  String get pdfQuantity => 'Kiasi';

  @override
  String get pdfAmountSold => 'Kiasi Kilichouzwa';

  @override
  String get pdfTopProductsTitle => 'Bidhaa Zinazouza Zaidi kwa Siku';

  @override
  String pdfTopProductQty(Object qty) {
    return 'Vitengo $qty';
  }

  @override
  String get pdfCategory => 'Kategoria';

  @override
  String get saleRecordedAndInvoiceGenerated =>
      'Mauzo yamerekodiwa. Ankara imetolewa kwa ajili ya ufuatiliaji.';

  @override
  String get sessionError => 'Hitilafu ya kipindi. Tafadhali ingia tena.';

  @override
  String get invoiceTitle => 'ANKARA YA MAUZO';

  @override
  String get invoiceName => 'Ankara';

  @override
  String get invoiceTotal => 'JUMLA YA KIASI KINACHOTAKIWA';

  @override
  String get pdfItem => 'Bidhaa';

  @override
  String get pdfQty => 'Kiasi';

  @override
  String get pdfUnit => 'Kitengo';

  @override
  String get pdfPrice => 'Bei ya Kitengo';

  @override
  String get pdfTotal => 'Jumla';

  @override
  String get pdfStoreInfo => 'Imeuzwa na';

  @override
  String get pdfDate => 'Tarehe na Saa';

  @override
  String get pdfPaymentMode => 'Njia ya Malipo';

  @override
  String invoiceThankYou(Object date) {
    return 'Asante kwa ununuzi wako uliofanywa mnamo $date';
  }

  @override
  String invoiceTraceability(Object id) {
    return 'Kitambulisho cha kipekee cha Muamala (Ufuatiliaji): $id';
  }

  @override
  String get defaultStoreName => 'Duka la Biashara';

  @override
  String get searchProductLabel => 'Tafuta Bidhaa';

  @override
  String get searchHint => 'Jina au Kitengo...';

  @override
  String get noResultsFound => 'Hakuna bidhaa inayolingana na utafutaji wako.';

  @override
  String get noProductsAvailable =>
      'Hakuna bidhaa zinazopatikana. Ongeza zingine kwenye Hisa.';

  @override
  String get deleteButton => 'Futa';

  @override
  String get confirmDeleteProductTitle => 'Thibitisha Kufuta';

  @override
  String confirmDeleteProductMessage(Object productName) {
    return 'Una uhakika unataka kufuta bidhaa $productName? Kitendo hiki hakiwezi kutenduliwa.';
  }

  @override
  String productDeletedSuccess(Object productName) {
    return 'Bidhaa $productName imefutwa kwa mafanikio.';
  }

  @override
  String get productDeleteError => 'Hitilafu wakati wa kufuta bidhaa.';

  @override
  String supplyProductTitle(Object productName) {
    return 'Rejesha Akiba $productName';
  }

  @override
  String get supplyQuantityHint => 'Kiasi cha kuongeza';

  @override
  String get supplyPriceHint => 'Bei ya ununuzi kwa kitengo';

  @override
  String supplySuccess(Object qty, Object unit) {
    return 'Akiba imesasishwa. Imeongeza $qty $unit.';
  }

  @override
  String get supplyError => 'Hitilafu wakati wa kurejesha akiba.';

  @override
  String get invalidQuantityError => 'Tafadhali ingiza kiasi chanya na halali.';

  @override
  String get priceValidationRestock =>
      'Tafadhali ingiza bei ya ununuzi kwa kitengo chanya na halali.';

  @override
  String traceabilityHistoryTitle(Object productName) {
    return 'Historia ya Urejeshaji Akiba: $productName';
  }

  @override
  String get traceabilityEmpty =>
      'Hakuna historia ya urejeshaji akiba iliyorekodiwa kwa bidhaa hii.';

  @override
  String get atDate => 'Tarehe';

  @override
  String get atPrice => 'Bei ya Kitengo';

  @override
  String get dateUnknown => 'Tarehe Isiyojulikana';

  @override
  String get closeButton => 'Funga';

  @override
  String formatDate(Object date) {
    return '$date';
  }

  @override
  String get okButton => 'SAWA';

  @override
  String get categoryNone => 'Hakuna';

  @override
  String get optionalLabel => 'Hiari';

  @override
  String get settingsAboutTitle => 'Kuhusu';

  @override
  String get invalidPrice => 'Bei si sahihi';

  @override
  String get sessionExpired => 'Kipindi kimeisha';

  @override
  String get genericError => 'Hitilafu imetokea';

  @override
  String get aboutAppDescription =>
      'Programu hii inakuwezesha kusimamia mauzo na hesabu zako kwa ufanisi na usalama.';

  @override
  String get aboutAppPolicy =>
      'Tunaheshimu faragha yako na data zako binafsi kulingana na sera yetu.';

  @override
  String get aboutAppContact =>
      'Wasiliana nasi: +243974084668, Andrelukengu67@gmail.com, Lubumbashi, Haut-Katanga';
}
