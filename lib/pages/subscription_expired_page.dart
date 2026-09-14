import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:url_launcher/url_launcher.dart';

class SubscriptionExpiredPage extends StatelessWidget {
  const SubscriptionExpiredPage({super.key});

  Future<void> _contactSupport() async {
    final Uri whatsappUrl = Uri.parse("https://wa.me/243974084668");
    try {
      if (!await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication)) {
        throw Exception('Impossible d\'ouvrir WhatsApp');
      }
    } catch (e) {
      debugPrint("Erreur URL Launcher: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // ✅ Remplacement de WillPopScope par PopScope (version moderne)
      body: PopScope(
        canPop: false, // Empêche le retour arrière
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth > 700 ? 64.0 : 32.0;
              final iconSize = (constraints.maxWidth * 0.12).clamp(60.0, 120.0);

              return SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    // ✅ On s'assure que le contenu prend au moins toute la hauteur de l'écran
                    minHeight: constraints.maxHeight,
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center, // Centre verticalement
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Icône d'alerte
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.timer_off_outlined,
                            size: iconSize,
                            color: colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 32),

                        Text(
                          'Abonnement expiré',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),

                        // ✅ SUPPRESSION DU Flexible ICI
                        Text(
                          'Votre accès mensuel à Biashara Yangu est arrivé à terme. '
                              'Veuillez contacter l\'administrateur pour renouveler votre compte.',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        const SizedBox(height: 40),

                        // Bouton Renouveler
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: _contactSupport,
                            icon: const Icon(Icons.chat),
                            label: const Text(
                              'Contacter le support',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Bouton Déconnexion
                        TextButton.icon(
                          onPressed: () async {
                            await SessionManager.setUserId("");
                            await SessionManager.setUserRole("");
                            if (context.mounted) context.go('/login');
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Se déconnecter'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}