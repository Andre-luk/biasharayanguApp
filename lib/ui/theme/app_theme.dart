// lib/ui/theme/app_theme.dart
//
// 🎨 DESIGN SYSTEM « Biashara Yangu »
//
// Un seul endroit pour toute l'identité visuelle de l'application :
//   • `AppCouleurs`  — la palette de marque (bleu marine + orange du logo) ;
//   • `AppDegrades`  — les dégradés utilisés par les cartes et boutons ;
//   • `AppTheme`     — les thèmes Material 3 clair et sombre.
//
// Toutes les pages héritent automatiquement de ce thème : boutons, champs,
// cartes, barres de navigation, dialogues, bannières… Il suffit donc de
// modifier ce fichier pour faire évoluer le design de toute l'application.

import 'package:flutter/material.dart';

/// Palette officielle : reprend les couleurs du logo (bleu marine + orange).
class AppCouleurs {
  const AppCouleurs._();

  // — Bleu marine (cercle du logo) —
  static const Color marine = Color(0xFF1F3864);
  static const Color marineClair = Color(0xFF2E5AA8);
  static const Color marineProfond = Color(0xFF16294A);

  // — Orange (écran du téléphone du logo) —
  static const Color orange = Color(0xFFF08A4B);
  static const Color orangeFonce = Color(0xFFD96E2B);

  // — Couleurs d'état —
  static const Color succes = Color(0xFF16A34A);
  static const Color alerte = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFDC2626);
  static const Color info = Color(0xFF0EA5E9);

  // — Fonds —
  static const Color fondClair = Color(0xFFF4F6FB);
  static const Color fondSombre = Color(0xFF0E1116);
  static const Color carteSombre = Color(0xFF171C25);
}

/// Dégradés prêts à l'emploi (cartes « hero », boutons, bannières).
class AppDegrades {
  const AppDegrades._();

  /// Dégradé de marque : bleu marine → bleu plus clair.
  static const LinearGradient primaire = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[AppCouleurs.marine, AppCouleurs.marineClair],
  );

  /// Dégradé « premium » utilisé par la carte des ventes du jour.
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[
      AppCouleurs.marineProfond,
      AppCouleurs.marine,
      Color(0xFF33549C),
    ],
    stops: <double>[0.0, 0.55, 1.0],
  );

  /// Dégradé orange (accent, actions secondaires).
  static const LinearGradient accent = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[AppCouleurs.orange, AppCouleurs.orangeFonce],
  );

  /// Dégradé très clair pour les fonds d'écran d'authentification.
  static const LinearGradient fondClair = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFFFFFFFF), Color(0xFFEDF1F9)],
  );

  /// Dégradé sombre pour les fonds d'écran d'authentification.
  static const LinearGradient fondSombre = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0xFF0E1116), Color(0xFF141A26)],
  );
}

/// Fabrique des thèmes Material 3 de l'application.
class AppTheme {
  const AppTheme._();

  /// Thème clair (par défaut).
  static ThemeData clair() {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: AppCouleurs.marine,
      brightness: Brightness.light,
    );
    final ColorScheme scheme = base.copyWith(
      primary: AppCouleurs.marine,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFDCE6FA),
      onPrimaryContainer: AppCouleurs.marineProfond,
      secondary: AppCouleurs.orangeFonce,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFFFE8D8),
      onSecondaryContainer: const Color(0xFF7A3A0F),
      tertiary: AppCouleurs.marineClair,
      onTertiary: Colors.white,
      error: AppCouleurs.danger,
      surface: Colors.white,
      onSurface: const Color(0xFF151A23),
      outlineVariant: const Color(0xFFE3E7F0),
    );
    return _construire(scheme);
  }

  /// Thème sombre.
  static ThemeData sombre() {
    final ColorScheme base = ColorScheme.fromSeed(
      seedColor: AppCouleurs.marineClair,
      brightness: Brightness.dark,
    );
    final ColorScheme scheme = base.copyWith(
      primary: const Color(0xFF8FB4F2),
      onPrimary: AppCouleurs.marineProfond,
      primaryContainer: const Color(0xFF243B66),
      onPrimaryContainer: const Color(0xFFD9E5FF),
      secondary: AppCouleurs.orange,
      onSecondary: const Color(0xFF3A1C05),
      secondaryContainer: const Color(0xFF5A3312),
      onSecondaryContainer: const Color(0xFFFFDCC2),
      error: const Color(0xFFFF6B6B),
      surface: AppCouleurs.carteSombre,
      onSurface: const Color(0xFFE8ECF4),
      outlineVariant: const Color(0xFF2A3242),
    );
    return _construire(scheme);
  }

  /// Squelette commun : typographie, composants, formes.
  static ThemeData _construire(ColorScheme scheme) {
    final bool sombre = scheme.brightness == Brightness.dark;
    final ThemeData base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
    );

    // — Typographie : plus affirmée, plus lisible sur petit écran. —
    final TextTheme texte = base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.35),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
    );

    final BorderRadius rayon16 = BorderRadius.circular(16);
    final BorderRadius rayon20 = BorderRadius.circular(20);

    return base.copyWith(
      textTheme: texte,
      scaffoldBackgroundColor:
          sombre ? AppCouleurs.fondSombre : AppCouleurs.fondClair,

      // — Barre d'application : plate, sobre, sans ombre parasite. —
      appBarTheme: AppBarTheme(
        backgroundColor: sombre ? AppCouleurs.fondSombre : Colors.white,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: texte.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 19,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),

      // — Cartes : fond plein, coins doux, contour discret. —
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: rayon20,
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),

      // — Champs de saisie : remplis, coins 16, focus net. —
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sombre
            ? const Color(0xFF1E2531)
            : const Color(0xFFF3F5FA),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: rayon16,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: rayon16,
          borderSide: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: rayon16,
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: rayon16,
          borderSide: const BorderSide(color: AppCouleurs.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: rayon16,
          borderSide: const BorderSide(color: AppCouleurs.danger, width: 1.6),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),

      // — Boutons : hauts, arrondis, texte lisible. —
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: rayon16),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 0.2,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: rayon16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          side: BorderSide(color: scheme.outlineVariant, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: rayon16),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // — Barre de navigation basse (Material 3). —
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        elevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> etats) {
            final bool selectionne = etats.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11.5,
              fontWeight: selectionne ? FontWeight.w800 : FontWeight.w600,
              color: selectionne ? scheme.primary : scheme.onSurfaceVariant,
            );
          },
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> etats) {
            final bool selectionne = etats.contains(WidgetState.selected);
            return IconThemeData(
              size: 24,
              color: selectionne ? scheme.primary : scheme.onSurfaceVariant,
            );
          },
        ),
      ),

      // — Divers composants. —
      //  🎨 PUCES / FILTRES : couleurs EXPLICITES pour les deux états —
      //  sans elles, le texte des filtres perdait sa couleur (noir sur fond
      //  sombre = illisible en thème sombre).
      //    • non sélectionné : fond doux + texte normal ;
      //    • sélectionné     : fond marine (bleu clair en sombre) + texte
      //      onPrimary (blanc en clair, marine profond en sombre).
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        backgroundColor: sombre ? const Color(0xFF1E2531) : const Color(0xFFF3F5FA),
        selectedColor: scheme.primary,
        secondarySelectedColor: scheme.primary,
        checkmarkColor: scheme.onPrimary,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          color: scheme.onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
          color: scheme.onPrimary,
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        iconColor: scheme.onSurfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 2,
        backgroundColor: sombre ? const Color(0xFF232B39) : const Color(0xFF1E2A3D),
        contentTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        insetPadding: const EdgeInsets.all(16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: texte.titleLarge?.copyWith(color: scheme.onSurface),
        contentTextStyle: texte.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.12),
        linearMinHeight: 6,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: sombre ? const Color(0xFF2A3242) : const Color(0xFF243044),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      dividerColor: scheme.outlineVariant,
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
