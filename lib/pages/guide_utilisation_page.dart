// lib/pages/guide_utilisation_page.dart
//
// 📖 GUIDE D'UTILISATION — apprendre Biashara Yangu pas à pas.
//
// Un guide professionnel, en français simple, organisé par tâches :
// démarrer, vendre, gérer le stock, encaisser, publier ses QR codes,
// suivre la finance, travailler en équipe, utiliser l'assistant IA et
// gérer son abonnement.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/ui/theme/app_theme.dart';

class GuideUtilisationPage extends StatelessWidget {
  const GuideUtilisationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Guide d\'utilisation',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: const <Widget>[
          _Etape(
            numero: '1',
            titre: 'Créer votre compte',
            icone: Icons.person_add_alt_1_rounded,
            points: <String>[
              'Écran d\'accueil → « Créer un compte » : nom complet, email, '
                  'mot de passe, nom de votre boutique (optionnel) et ville.',
              'Votre compte passe par DEUX vérifications avant activation : '
                  'le service comptes contrôle vos informations, puis la '
                  'finance confirme votre paiement.',
              'Vous recevez ensuite votre accès : votre entreprise porte un '
                  'essai de 7 jours (paiement partiel) ou directement 30 jours '
                  '(paiement total).',
            ],
          ),
          _Etape(
            numero: '2',
            titre: 'Faire votre première vente',
            icone: Icons.point_of_sale_rounded,
            points: <String>[
              '« Nouvelle vente » : ajoutez les articles au panier '
                  '(recherche ou scan du QR code).',
              '« Encaiser » : choisissez le mode de paiement (espèces, mobile '
                  'money, carte, virement), saisissez le montant reçu — le '
                  'rendu est calculé automatiquement.',
              'Votre vente reçoit un numéro officiel (VTE-…) et le stock est '
                  'mis à jour tout seul.',
            ],
          ),
          _Etape(
            numero: '3',
            titre: 'Gérer vos produits et votre stock',
            icone: Icons.inventory_2_rounded,
            points: <String>[
              'Ajoutez vos articles : nom, catégorie, prix d\'achat, prix de '
                  'vente, unité, quantité.',
              'Créez des conditionnements (ex. « Farde de 12 ») — les prix '
                  'et le stock sont convertis automatiquement.',
              'Définissez un seuil d\'alerte : dès qu\'un article baisse, il '
                  'apparaît « en alerte » sur l\'accueil.',
              'Entrées de stock, ajustements et inventaires sont tracés dans '
                  'le journal.',
            ],
          ),
          _Etape(
            numero: '4',
            titre: 'Imprimer vos QR codes produits',
            icone: Icons.qr_code_2_rounded,
            points: <String>[
              '« QR codes » : sélectionnez vos articles et conditionnements.',
              'Choisissez la taille, le format (PNG/SVG/PDF) et le nombre de '
                  'copies par étiquette : plusieurs QR du MÊME produit sur '
                  'une seule feuille.',
              'Les QR codes ne contiennent JAMAIS le prix : il est relu dans '
                  'la base à chaque scan — vos étiquettes ne périment pas.',
            ],
          ),
          _Etape(
            numero: '5',
            titre: 'Suivre votre argent',
            icone: Icons.account_balance_wallet_rounded,
            points: <String>[
              '« Caisse » : solde du jour et clôture en fin de journée.',
              '« Dépenses » : enregistrez chaque sortie d\'argent avec sa '
                  'catégorie (transport, loyer, marchandises…).',
              '« Dettes clients » : suivez ce qu\'on vous doit, enregistrez '
                  'les remboursements, relancez par WhatsApp/SMS.',
              '« Finance » : chiffre d\'affaires, bénéfices et graphiques.',
            ],
          ),
          _Etape(
            numero: '6',
            titre: 'Travailler en équipe',
            icone: Icons.groups_rounded,
            points: <String>[
              'Le patron donne son « code boutique » à chaque employé.',
              'L\'employé s\'inscrit avec ce code : il devient Vendeur '
                  '(caissier), Magasinier ou Comptable selon son rôle.',
              'Chaque rôle ne voit que ce qui le concerne : un caissier vend, '
                  'un magasinier gère le stock — personne ne touche au reste.',
            ],
          ),
          _Etape(
            numero: '7',
            titre: 'Utiliser l\'assistant IA 🤖',
            icone: Icons.smart_toy_rounded,
            points: <String>[
              'Posez vos questions en français : « quelles sont mes ventes '
                  'aujourd\'hui ? », « montre-moi le stock faible ».',
              'L\'assistant peut aussi AGIR : créer une vente, ajouter un '
                  'client, enregistrer une dépense… toujours dans la limite '
                  'de vos droits, et jamais sans confirmation pour les '
                  'actions sensibles.',
              'Chaque réponse consomme des quotas ; les packs s\'achètent '
                  'depuis « Quotas IA » (1000 CDF = 10 quotas).',
            ],
          ),
          _Etape(
            numero: '8',
            titre: 'Votre abonnement',
            icone: Icons.workspace_premium_rounded,
            points: <String>[
              'Paiement partiel : 7 jours d\'essai, puis complétez le solde. '
                  'Si le solde n\'est pas payé à la fin : accès restreint '
                  '(vous voyez toujours votre solde et pouvez payer).',
              'Paiement total : l\'abonnement de 30 jours démarre '
                  'immédiatement après validation de la finance.',
              'La finance valide chaque paiement : montant, mode, référence '
                  'de transaction — tout est tracé.',
            ],
          ),
          _Etape(
            numero: '?',
            titre: 'Besoin d\'aide ?',
            icone: Icons.support_agent_rounded,
            points: <String>[
              'Email : support@biasharayangu.cd',
              'Vos questions sont traitées par l\'équipe Biashara Yangu '
                  '(La Perle).',
              'Ne partagez JAMAIS votre mot de passe : personne de l\'équipe '
                  'ne vous le demandera.',
            ],
          ),
        ],
      ),
    );
  }
}

class _Etape extends StatelessWidget {
  const _Etape({
    required this.numero,
    required this.titre,
    required this.icone,
    required this.points,
  });

  final String numero;
  final String titre;
  final IconData icone;
  final List<String> points;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: AppDegrades.primaire,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  numero,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(icone, size: 20, color: AppCouleurs.marine),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...points.map((String point) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(Icons.chevron_right_rounded,
                          size: 16, color: AppCouleurs.orangeFonce),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        point,
                        style: theme.textTheme.bodySmall?.copyWith(height: 1.45),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
