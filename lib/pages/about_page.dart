// lib/pages/about_page.dart
//
// ℹ️ À PROPOS — informations officielles de l'application.
//
// Application : Biashara Yangu (gestion de commerce multi-activités).
// Éditeur : Biashara Tech — Lubumbashi, République Démocratique du Congo.
// Développement : Biashara Tech — développeur principal : Andre Lukengu.
// Collaborateur : La Perle Corp — chargé du marketing.
//
// Cette page rassemble tout ce qu'une application professionnelle doit
// publier : identité, version, éditeur, développeur, contacts officiels,
// mentions légales, technologies et accès aux documents légaux.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/ui/theme/app_theme.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  // ── Identité officielle ────────────────────────────────────────────────────
  static const String appName = 'Biashara Yangu';
  static const String appVersion = '2.9.0';
  static const String appBuild = '33';
  static const String editeur = 'Biashara Tech — Lubumbashi, RDC';
  static const String developpeur = 'Biashara Tech';
  static const String developpeurPrincipal = 'Andre Lukengu';
  static const String participation =
      'La Perle Corp — collaborateur, chargé du marketing';

  // ── Contacts officiels ─────────────────────────────────────────────────────
  static const String email = 'support@biasharayangu.cd';
  static const String phone = '+243 974 084 668';
  static const String adresse =
      'Lubumbashi, Haut-Katanga, République Démocratique du Congo';

  void _copier(BuildContext context, String label, String valeur) {
    Clipboard.setData(ClipboardData(text: valeur));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copié dans le presse-papiers'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'À propos',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _entete(theme),
          _section(
            theme,
            'Présentation',
            'Biashara Yangu est une application professionnelle de gestion '
            'de commerce, pensée pour la réalité congolaise : elle fonctionne '
            'sur Android, Windows et Linux, avec une base locale (même sans '
            'internet) et une synchronisation sécurisée en ligne.\n\n'
            'UNE SEULE application pour tous les métiers : boutique, hôtel, '
            'pharmacie, restaurant, salle des fêtes, boulangerie… Le type '
            'd\'activité choisi active automatiquement les modules utiles '
            '(chambres, commandes, lots & péremption…) et le tableau de bord '
            's\'adapte.',
          ),
          _section(
            theme,
            'Fonctionnalités principales',
            '• Ventes & caisse : panier, scanner, encaissement (espèces, '
            'mobile money, carte, dette), reçus et annulations tracées.\n'
            '• Articles, stock et inventaires, avec seuils d\'alerte.\n'
            '• Clients, crédits et relances WhatsApp / SMS.\n'
            '• Dépenses, dettes, clôtures de caisse et suivi financier.\n'
            '• Rapports & exports PDF/Excel (ventes, finance, stock, '
            'expirations, occupation hôtel, séjours, commandes restaurant…).\n'
            '• Modules métier : hôtel (chambres, réservations, check-in/out, '
            'facture séjour), pharmacie (lots, péremption, blocage de vente), '
            'restaurant (tables, commandes, écran cuisine), salle des '
            'fêtes (salles, événements, prestations, avances), boulangerie '
            '(matières premières, productions, coût de revient) et boucherie '
            '(vente au poids, ticket au kg).\n'
            '• Équipe : 8 rôles et permissions fines par écran et par action.\n'
            '• Biashara Marketplace : vitrine publique géolocalisée — vos '
            'produits trouvables autour des clients (recherche SANS compte, '
            'comparaison des prix, distances, itinéraire), tableau de bord de '
            'visibilité (affichages, intérêt, itinéraires, appels, ventes '
            'attribuées) et campagne publicitaire toujours marquée '
            '« PUBLICITÉ ».\n'
            '• Assistant IA avec quotas et journal d\'audit complet.',
          ),
          _identite(theme),
          _section(
            theme,
            'Mentions officielles',
            'Biashara Yangu est éditée et exploitée par Biashara Tech '
            '(Lubumbashi, République Démocratique du Congo) et développée '
            'par Biashara Tech — développeur principal : Andre Lukengu. '
            'La Perle Corp est collaborateur de Biashara Tech et assure la '
            'charge du marketing du produit.\n\n'
            '© 2026 Biashara Tech — tous droits réservés. '
            '« Biashara Yangu », son logo, ses écrans et son code sont '
            'protégés ; toute reproduction sans autorisation écrite est '
            'interdite.\n\n'
            'Service régi par le droit congolais — juridiction des tribunaux '
            'compétents de Lubumbashi.',
          ),
          _section(
            theme,
            'Technologies & licences open source',
            'L\'application s\'appuie sur des composants libres que nous '
            'remercions :\n'
            '• Flutter & Dart (BSD-3, Google) — interface multiplateforme.\n'
            '• Supabase & PostgreSQL (Apache-2.0 / PostgreSQL License) — '
            'base de données et synchronisation sécurisée.\n'
            '• go_router (BSD-3), flutter_local_notifications (BSD-3), '
            'SQLite (domaine public), pdf & printing (Apache-2.0).\n'
            '• Assistant IA : service DeepSeek, utilisé uniquement pour '
            'répondre à vos questions.',
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      context.pushNamed('politique-confidentialite'),
                  icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                  label: const Text('Confidentialité'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.pushNamed('conditions-utilisation'),
                  icon: const Icon(Icons.gavel_rounded, size: 18),
                  label: const Text('Conditions'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _section(
            theme,
            'Contact & support',
            'Assistance technique, partenariats, informations : l\'équipe '
            'répond du lundi au samedi.',
          ),
          const SizedBox(height: 4),
          _ligneContact(
            context,
            theme,
            icone: Icons.email_outlined,
            libelle: 'Email',
            valeur: email,
          ),
          _ligneContact(
            context,
            theme,
            icone: Icons.phone_outlined,
            libelle: 'Téléphone',
            valeur: phone,
          ),
          _ligneContact(
            context,
            theme,
            icone: Icons.location_on_outlined,
            libelle: 'Adresse',
            valeur: adresse,
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              '$appName — version $appVersion (build $appBuild)\n'
              'Édité par Biashara Tech — Lubumbashi, RDC\n'
              'La Perle Corp — collaborateur (marketing)',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COMPOSANTS
  // ---------------------------------------------------------------------------

  Widget _entete(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppDegrades.primaire,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/Biashara_app_off-.png',
              height: 76,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.storefront_rounded,
                      color: Colors.white, size: 56),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            appName,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Version $appVersion (build $appBuild) • Gestion de commerce '
            'multi-activités',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _section(ThemeData theme, String titre, String contenu) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            titre,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 8),
          Text(
            contenu,
            style: theme.textTheme.bodySmall?.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _identite(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Éditeur & développeur',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
          ),
          const SizedBox(height: 10),
          _ligneIdentite(theme, Icons.business_rounded, 'Éditeur',
              'Biashara Tech'),
          _ligneIdentite(theme, Icons.code_rounded, 'Développement',
              'Biashara Tech'),
          _ligneIdentite(theme, Icons.person_rounded, 'Développeur principal',
              'Andre Lukengu'),
          _ligneIdentite(theme, Icons.handshake_rounded, 'Collaborateur',
              'La Perle Corp — chargé du marketing'),
          _ligneIdentite(theme, Icons.place_rounded, 'Siège',
              'Lubumbashi, RDC'),
        ],
      ),
    );
  }

  Widget _ligneIdentite(
      ThemeData theme, IconData icone, String libelle, String valeur) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          SizedBox(
            width: 140,
            child: Text(libelle, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              valeur,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ligneContact(
    BuildContext context,
    ThemeData theme, {
    required IconData icone,
    required String libelle,
    required String valeur,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(icone, color: theme.colorScheme.primary),
        title: Text(libelle, style: theme.textTheme.bodySmall),
        subtitle: Text(
          valeur,
          style: theme.textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        trailing: IconButton(
          tooltip: 'Copier',
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () => _copier(context, libelle, valeur),
        ),
      ),
    );
  }
}
