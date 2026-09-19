// lib/pages/politique_confidentialite_page.dart
//
// 🔒 POLITIQUE DE CONFIDENTIALITÉ & CONDITIONS D'UTILISATION.
//
// Document professionnel présenté dans l'application (Paramètres →
// « Politique & conditions »), relu depuis le dépôt du projet.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/ui/theme/app_theme.dart';

class PolitiqueConfidentialitePage extends StatelessWidget {
  const PolitiqueConfidentialitePage({super.key});

  static const String _miseAJour = '19 septembre 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Politique & conditions',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _entete(context),
          _section(
            context,
            titre: '1. Qui sommes-nous ?',
            contenu:
                'Biashara Yangu est une application de gestion de commerce '
                'éditée et exploitée par La Perle (Lubumbashi, République '
                'Démocratique du Congo). Elle permet aux entreprises '
                '(boutiques, hôtels, pharmacies, restaurants…) de gérer '
                'ventes, stock, caisse, dettes, collaborateurs, rapports et '
                'un assistant intelligent — à Lubumbashi et partout en RDC.',
          ),
          _section(
            context,
            titre: '2. Données que nous traitons',
            contenu:
                '• Compte : nom, email, téléphone, rôle, entreprise '
                'd\'appartenance.\n'
                '• Activité commerciale : produits, ventes, clients, '
                'dépenses, dettes, mouvements de stock, paiements '
                'd\'abonnement.\n'
                '• Sécurité : connexions (date, adresse IP, appareil) et '
                'journal d\'audit des actions sensibles.\n'
                '• Assistant IA : questions posées et réponses générées '
                '(pour le calcul des quotas et la qualité du service).\n\n'
                'Nous ne collectons ni vos contacts personnels, ni vos '
                'photos, ni votre position GPS.',
          ),
          _section(
            context,
            titre: '3. Pourquoi ces données ?',
            contenu:
                '• Fournir le service : vendre, suivre le stock, éditer vos '
                'rapports.\n'
                '• Sécurité : détecter les connexions suspectes, tracer les '
                'actions sensibles (prix, stock, comptes).\n'
                '• Abonnement : calculer votre solde, vos échéances et vos '
                'reçus.\n'
                '• Amélioration : statistiques agrégées et anonymes.',
          ),
          _section(
            context,
            titre: '4. Où vivent vos données ?',
            contenu:
                'Vos données sont hébergées chez Supabase (infrastructure '
                'PostgreSQL chiffrée, serveurs sécurisés). Chaque entreprise '
                'ne peut accéder QU\'À ses propres données : c\'est garanti '
                'par des règles de sécurité au niveau de la base '
                '(Row Level Security). Les questions posées à l\'assistant IA '
                'sont transmises au service DeepSeek uniquement pour produire '
                'la réponse demandée.',
          ),
          _section(
            context,
            titre: '5. Durée de conservation',
            contenu:
                'Vos données commerciales restent conservées tant que votre '
                'compte existe — même si l\'abonnement est échu, RIEN n\'est '
                'supprimé : vous retrouvez tout après régularisation. Le '
                'journal d\'audit est conservé 12 mois minimum.',
          ),
          _section(
            context,
            titre: '6. Vos droits',
            contenu:
                '• Accéder à vos données (rapports et exports PDF/Excel).\n'
                '• Corriger vos informations depuis l\'application.\n'
                '• Demander la suppression de votre compte : '
                'support@biasharayangu.cd (traitée sous 30 jours, hors '
                'obligations légales de conservation).\n'
                '• Refuser les communications non essentielles.',
          ),
          _section(
            context,
            titre: '7. Conditions d\'utilisation',
            contenu:
                '• Un compte est destiné à une entreprise ; les identifiants '
                'sont personnels et confidentiels.\n'
                '• Chaque compte est vérifié par le service comptes puis '
                'validé par la finance avant activation (paiement partiel : '
                '7 jours d\'essai puis complément du solde ; paiement total : '
                '30 jours immédiats).\n'
                '• Les paiements d\'abonnement ne sont pas remboursables '
                'après activation.\n'
                '• Toute tentative de fraude (faux comptes, manipulation des '
                'prix ou du journal) entraîne la suspension du compte.\n'
                '• L\'utilisation de l\'assistant IA est facturée en quotas, '
                'achetés par packs de 10 à 100.\n'
                '• Le service est fourni « en l\'état » ; La Perle s\'engage '
                'sur un effort de disponibilité maximal (maintenance '
                'planifiée communiquée à l\'avance).\n\n'
                'Le détail complet (abonnement, responsabilité, résiliation) '
                'figure sur la page « Conditions d\'utilisation » des '
                'Paramètres.',
          ),
          _section(
            context,
            titre: '8. Droit applicable',
            contenu:
                'Le service est édité et exploité depuis la République '
                'Démocratique du Congo. Les présentes règles sont régies par '
                'le DROIT CONGOLAIS ; tout litige relève des tribunaux '
                'compétents de LUBUMBASHI, après une tentative de règlement '
                'amiable (support@biasharayangu.cd).',
          ),
          _section(
            context,
            titre: '9. Nous contacter',
            contenu:
                'La Perle — Lubumbashi, RDC\n'
                'Email : support@biasharayangu.cd\n'
                'Pour toute question relative à vos données ou à '
                'l\'application, l\'équipe répond du lundi au samedi.',
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'Version du document : $_miseAJour',
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entete(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppDegrades.primaire,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.privacy_tip_rounded, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'La confiance est notre première richesse : voici, en français '
              'simple, ce que nous faisons de vos données — et ce que vous '
              'pouvez exiger de nous.',
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context, {
    required String titre,
    required String contenu,
  }) {
    final ThemeData theme = Theme.of(context);
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
}
