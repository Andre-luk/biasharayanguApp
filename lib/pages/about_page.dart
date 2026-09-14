// lib/pages/about_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard
import 'package:biashara_yangu/l10n/app_localizations.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String phone = '+243974084668';
  static const String email = 'Andrelukengu67@gmail.com';
  static const String address = 'Lubumbashi, Haut-Katanga, République démocratique du Congo';
  static const String appName = 'Biashara Yangu';
  static const String appVersion = '1.0.0'; // Mettre à jour si tu utilises package_info_plus

  void _copyToClipboard(BuildContext context, String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copié·e dans le presse-papiers'), duration: const Duration(seconds: 2)),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(text, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _sectionText(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Text(text, style: theme.textTheme.bodyMedium, textAlign: TextAlign.justify);
  }

  @override
  Widget build(BuildContext context) {
    final T = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(T.settingsAboutTitle ?? 'À propos'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Center(
                child: Column(
                  children: [
                    Hero(
                      tag: 'app_logo',
                      child: Image.asset('assets/Biashara_app_off-.png', height: 80),
                    ),
                    const SizedBox(height: 10),
                    Text(appName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Text('Version $appVersion', style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Presentation
              _sectionTitle(context, 'Présentation'),
              _sectionText(
                context,
                // Texte professionnel proposé
                'Biashara Yangu est une solution mobile légère et hors-connexion pour la gestion '
                    'quotidienne des petites entreprises. Conçue pour les commerçants et les boutiques '
                    'de terrain, l\'application permet de suivre le stock, d\'enregistrer des ventes, '
                    'de générer des factures, et de synchroniser les données avec le cloud lorsque la '
                    'connexion internet est disponible. L\'approche \"offline-first\" garantit que vous '
                    'pouvez travailler sans interruption, même dans des zones à connectivité limitée.',
              ),
              const SizedBox(height: 18),

              // Fonctionnalités courtes
              _sectionTitle(context, 'Fonctionnalités principales'),
              _sectionText(
                context,
                '• Gestion simple et rapide des produits et stocks.\n'
                    '• Saisie de ventes (caisse) avec génération d\'un ticket/facture.\n'
                    '• Utilisateurs secondaires (collaborateurs) limités à la caisse.\n'
                    '• Synchronisation bidirectionnelle avec Supabase quand connecté.\n'
                    '• Historique des approvisionnements et journal des ventes.',
              ),
              const SizedBox(height: 18),

              // Politique et confidentialité (résumé)
              _sectionTitle(context, 'Confidentialité & Politique'),
              _sectionText(
                context,
                'Vos données (produits, ventes, clients) sont stockées localement sur votre appareil '
                    'et synchronisées avec le serveur Supabase configuré par l\'application uniquement si vous autorisez la synchronisation. '
                    'Nous respectons la confidentialité de vos données : elles ne sont pas vendues à des tiers. '
                    'Les informations sensibles (mots de passe) sont stockées sous forme hachée localement. '
                    'Pour toute demande de suppression complète de vos données sur nos serveurs, contactez le support ci-dessous.',
              ),
              const SizedBox(height: 18),

              // Conditions d'utilisation (résumé)
              _sectionTitle(context, 'Conditions d\'utilisation (résumé)'),
              _sectionText(
                context,
                'L\'utilisation de Biashara Yangu implique l\'acceptation que l\'éditeur ne soit pas tenu responsable '
                    'des pertes financières résultant d\'une mauvaise utilisation de l\'application. Il est recommandé '
                    'd\'effectuer des sauvegardes régulières et d\'utiliser des mots de passe robustes pour les comptes.',
              ),
              const SizedBox(height: 18),

              // Contact
              _sectionTitle(context, 'Contact & Support'),
              _sectionText(context, 'Pour assistance technique, partenariats ou demandes générales :'),
              const SizedBox(height: 8),

              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Theme.of(context).dividerColor)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Téléphone
                      Row(
                        children: [
                          const Icon(Icons.phone, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(phone, style: Theme.of(context).textTheme.bodyMedium)),
                          IconButton(
                            tooltip: 'Copier le numéro',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () => _copyToClipboard(context, 'Numéro', phone),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Email
                      Row(
                        children: [
                          const Icon(Icons.email, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(email, style: Theme.of(context).textTheme.bodyMedium)),
                          IconButton(
                            tooltip: 'Copier l\'email',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () => _copyToClipboard(context, 'Email', email),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Adresse
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 18),
                          const SizedBox(width: 10),
                          Expanded(child: Text(address, style: Theme.of(context).textTheme.bodyMedium)),
                          IconButton(
                            tooltip: 'Copier l\'adresse',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () => _copyToClipboard(context, 'Adresse', address),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // Support & heures
              _sectionTitle(context, 'Support'),
              _sectionText(
                context,
                'Heures d\'assistance : lundi — vendredi, 09:00 — 17:00 (heure locale). '
                    'Pour les demandes urgentes, envoyez un message WhatsApp au numéro indiqué ou un email en décrivant précisément votre problème.',
              ),
              const SizedBox(height: 18),

              // Mentions légales courtes
              _sectionTitle(context, 'Mentions légales'),
              _sectionText(
                context,
                'Ce logiciel est fourni tel quel. L\'éditeur se réserve le droit de modifier les fonctionnalités, '
                    'les politiques et les conditions d\'utilisation à tout moment avec ou sans préavis. '
                    'Les mises à jour seront publiées via les canaux de distribution habituels.',
              ),
              const SizedBox(height: 24),

              // Footer: license / version
              Center(
                child: Column(
                  children: [
                    Text('© ${DateTime.now().year} Biashara Yangu', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 6),
                    Text('Version: $appVersion', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
