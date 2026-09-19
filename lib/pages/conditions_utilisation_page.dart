// lib/pages/conditions_utilisation_page.dart
//
// ⚖️ CONDITIONS D'UTILISATION DU SERVICE « BIASHARA YANGU ».
//
// Document professionnel présenté dans l'application (Paramètres →
// « Conditions d'utilisation »). Le service est édité et exploité depuis
// Lubumbashi (République Démocratique du Congo) ; le droit congolais
// s'applique. La politique de confidentialité détaillée vit sur une page
// dédiée (« Politique & conditions »).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/ui/theme/app_theme.dart';

class ConditionsUtilisationPage extends StatelessWidget {
  const ConditionsUtilisationPage({super.key});

  static const String _miseAJour = '19 septembre 2026';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Conditions d\'utilisation',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: <Widget>[
          _entete(context),
          _section(
            context,
            titre: '1. Objet et acceptation',
            contenu:
                'Biashara Yangu est un service de gestion commerciale édité '
                'par Biashara Tech, à Lubumbashi (République Démocratique du '
                'Congo). En créant un compte ou en utilisant l\'application, '
                'vous acceptez sans réserve les présentes conditions. Si vous '
                'les refusez, n\'utilisez pas le service.',
          ),
          _section(
            context,
            titre: '2. Description du service',
            contenu:
                'Le service comprend : ventes et encaissements, stock, '
                'caisse, clients et dettes, dépenses, collaborateurs, '
                'rapports et exports, import d\'articles, assistant '
                'intelligent, notifications, sauvegarde en ligne — et des '
                'modules métier selon votre activité (hôtel, pharmacie, '
                'restaurant…). L\'application fonctionne sur Android, '
                'Windows et Linux, avec synchronisation en ligne via '
                'Supabase.',
          ),
          _section(
            context,
            titre: '3. Compte et accès',
            contenu:
                '• Un compte correspond à une entreprise ; vous garantissez '
                'l\'exactitude des informations fournies (nom, téléphone, '
                'activité).\n'
                '• Vos identifiants sont personnels : vous êtes responsable '
                'de leur confidentialité et de toutes les actions effectuées '
                'depuis votre compte.\n'
                '• Le propriétaire gère ses collaborateurs et leurs rôles '
                '(vendeur, magasinier, comptable…). Chaque rôle ne voit que '
                'les écrans autorisés.\n'
                '• Toute suspicion de compromission doit être signalée '
                'immédiatement : support@biasharayangu.cd.',
          ),
          _section(
            context,
            titre: '4. Abonnement, activation et paiements',
            contenu:
                '• Chaque nouveau compte est vérifié par le service comptes '
                'puis validé par la finance avant activation.\n'
                '• Paiement TOTAL : 30 jours d\'accès immédiats. Paiement '
                'PARTIEL : 7 jours d\'essai, le solde est complété ensuite '
                'pour l\'activation complète.\n'
                '• Les montants payés ne sont pas remboursables après '
                'activation ; en cas d\'impayé, le compte est restreint '
                '(consultation possible) sans aucune suppression de '
                'données ; tout revient dès régularisation.\n'
                '• L\'assistant IA fonctionne par quotas, achetés en packs. '
                'Les quotas consommés ne sont pas récupérables.\n'
                '• Les tarifs et les limites (nombre de modules, quotas) '
                'peuvent évoluer avec un préavis d\'un mois affiché dans '
                'l\'application.',
          ),
          _section(
            context,
            titre: '5. Obligations de l\'utilisateur',
            contenu:
                '• Utiliser le service conformément aux lois de la '
                'République Démocratique du Congo.\n'
                '• Respecter les données de vos propres clients '
                '(confidentialité, exactitude).\n'
                '• Maintenir vos appareils à jour et sécurisés.\n'
                '• Signaler toute erreur ou anomalie constatée.',
          ),
          _section(
            context,
            titre: '6. Utilisations interdites',
            contenu:
                '• Créer des comptes frauduleux ou fournir de fausses '
                'identités.\n'
                '• Tenter de contourner les limites d\'abonnement ou de '
                'quotas.\n'
                '• Extraire massivement, revendre ou partager le service ou '
                'ses données sans autorisation écrite.\n'
                '• Falsifier le journal d\'audit, les ventes ou les '
                'rapports.\n'
                '• Introduire des contenus illégaux, haineux ou violents '
                'dans l\'application ou l\'assistant IA.\n'
                'Toute violation entraîne la suspension immédiate du compte, '
                'sans préjudice de poursuites.',
          ),
          _section(
            context,
            titre: '7. Propriété intellectuelle',
            contenu:
                'L\'application, son code, sa marque, ses écrans et sa '
                'documentation restent la propriété exclusive de Biashara '
                'Tech. En revanche, VOS données commerciales (ventes, '
                'clients, stock, rapports…) vous appartiennent : elles ne '
                'sont jamais réutilisées à votre insu.',
          ),
          _section(
            context,
            titre: '8. Disponibilité et maintenance',
            contenu:
                'Le service est fourni « en l\'état », avec un effort de '
                'disponibilité maximal. Les maintenances planifiées sont '
                'communiquées à l\'avance dans l\'application. Une connexion '
                'internet est nécessaire pour la synchronisation ; les '
                'fonctions hors ligne locales restent utilisables.',
          ),
          _section(
            context,
            titre: '9. Limitation de responsabilité',
            contenu:
                'Biashara Tech ne peut être tenue responsable des pertes de '
                'bénéfices, de la mauvaise saisie des données, des pannes '
                'd\'internet ou électriques, ni des dommages indirects. Dans '
                'tous les cas, sa responsabilité est plafonnée au montant '
                'd\'abonnement payé au cours des douze derniers mois.',
          ),
          _section(
            context,
            titre: '10. Suspension et résiliation',
            contenu:
                '• Vous pouvez demander la fermeture de votre compte à '
                'support@biasharayangu.cd ; vos données restent exportables '
                'pendant 30 jours, puis sont supprimées (hors obligations '
                'légales de conservation).\n'
                '• Biashara Tech peut suspendre un compte en cas de fraude, '
                'de non-paiement ou de violation des présentes conditions, '
                'après notification.',
          ),
          _section(
            context,
            titre: '11. Données personnelles',
            contenu:
                'Le traitement des données (compte, activité, sécurité, '
                'assistant IA) est décrit en détail dans la « Politique & '
                'confidentialité » accessible dans les Paramètres de '
                'l\'application.',
          ),
          _section(
            context,
            titre: '12. Droit applicable et juridiction',
            contenu:
                'Les présentes conditions sont régies par le DROIT CONGOLAIS. '
                'En cas de litige, les parties privilégient un règlement '
                'amiable ; à défaut, les tribunaux compétents de LUBUMBASHI '
                '(République Démocratique du Congo) sont seuls compétents.',
          ),
          _section(
            context,
            titre: '13. Modification des conditions',
            contenu:
                'Toute modification est publiée dans l\'application avec sa '
                'date de mise à jour, au moins 15 jours avant son entrée en '
                'vigueur. Continuer à utiliser le service vaut acceptation.',
          ),
          _section(
            context,
            titre: '14. Contact',
            contenu:
                'Biashara Tech — Lubumbashi, République Démocratique du Congo\n'
                'Email : support@biasharayangu.cd\n'
                'Du lundi au samedi.',
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
          Icon(Icons.gavel_rounded, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Les règles du service, en français simple : votre compte, '
              'l\'abonnement, vos responsabilités et les nôtres — droit '
              'congolais, juridiction de Lubumbashi.',
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
