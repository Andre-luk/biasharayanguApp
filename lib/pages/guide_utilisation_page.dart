// lib/pages/guide_utilisation_page.dart
//
// 📖 GUIDE D'UTILISATION — chaque module, pas à pas.
//
// Guide officiel en français simple : démarrage, boutique (les bases),
// pharmacie, hôtel, restaurant, équipe, assistant IA/abonnement et
// réglages. Accessible depuis les Paramètres ET depuis le bouton « ? »
// de chaque écran métier.

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
          _Entete(),
          _TitreSection(
            '🚀 Démarrage',
            'Créer le compte, activer l\'abonnement et se connecter.',
          ),
          _Etape(
            numero: '1',
            titre: 'Créer votre compte',
            icone: Icons.person_add_alt_1_rounded,
            points: <String>[
              'Écran d\'accueil → « Créer un compte » : nom complet, email, '
                  'mot de passe, nom de la boutique (optionnel), téléphone et '
                  'ville.',
              'Votre compte passe par DEUX vérifications : le service comptes '
                  'contrôle vos informations, puis la finance confirme votre '
                  'paiement.',
              'Paiement TOTAL : 30 jours d\'accès immédiats. Paiement '
                  'PARTIEL : 7 jours d\'essai, puis le solde complète '
                  'l\'activation.',
            ],
          ),
          _Etape(
            numero: '2',
            titre: 'Choisir votre activité',
            icone: Icons.storefront_rounded,
            points: <String>[
              'Votre type d\'activité (boutique, hôtel, pharmacie, '
                  'restaurant…) détermine les modules affichés : chambres, '
                  'commandes, lots & péremption…',
              'Un hôtel voit « Chambres, Réservations, Réception » ; un '
                  'restaurant voit « Tables, Commandes, Cuisine » ; tout le '
                  'monde garde les ventes, le stock et la caisse.',
              'Pour créer plusieurs entreprises (pack multi-entreprises) : '
                  'accueil → « Mes entreprises ».',
            ],
          ),
          _TitreSection(
            '🛒 Boutique — les bases',
            'Les modules communs à toutes les activités : produits, stock, '
            'ventes, caisse, clients, rapports.',
          ),
          _Etape(
            numero: '3',
            titre: 'Créer vos articles et votre stock',
            icone: Icons.inventory_2_rounded,
            points: <String>[
              'Articles & catalogue → ajoutez : nom, catégorie, prix d\'achat, '
                  'prix de vente, unité, quantité et seuil d\'alerte.',
              'Créez des conditionnements (ex. « Farde de 12 ») : les prix et '
                  'le stock sont convertis automatiquement.',
              'Stock → « Approvisionnement » pour les entrées, « Ajustement » '
                  'pour corriger, « Inventaire » pour compter.',
              'Import d\'articles : bouton « Import » (fichier CSV/Excel) pour '
                  'démarrer rapidement.',
            ],
          ),
          _Etape(
            numero: '4',
            titre: 'Faire une vente',
            icone: Icons.point_of_sale_rounded,
            points: <String>[
              '« Nouvelle vente » : ajoutez les articles au panier (recherche '
                  'ou scan du QR code), ajustez les quantités.',
              '« Encaisser » : mode de paiement (espèces, mobile money, carte, '
                  'virement, dette), montant reçu — le rendu est calculé '
                  'automatiquement.',
              'La vente reçoit un numéro officiel (VTE-…), le stock se met à '
                  'jour tout seul et une notification confirme l\'encaissement.',
            ],
          ),
          _Etape(
            numero: '5',
            titre: 'Clients, crédits et dettes',
            icone: Icons.people_alt_rounded,
            points: <String>[
              'Clients → créez une fiche (nom, téléphone) pour suivre les '
                  'crédits.',
              'Vendez « à crédit » : la dette est enregistrée avec ses '
                  'échéances.',
              'Dettes clients → encaissez les remboursements et relancez par '
                  'WhatsApp ou SMS en un clic.',
            ],
          ),
          _Etape(
            numero: '6',
            titre: 'Caisse, clôture et finance',
            icone: Icons.account_balance_wallet_rounded,
            points: <String>[
              'Caisse → solde et historique des entrées/sorties, clôture du '
                  'jour en fin de service.',
              'Finance → CA, dépenses, bénéfice net et marge.',
              'Dépenses → enregistrez loyer, transport, salaires…',
            ],
          ),
          _Etape(
            numero: '7',
            titre: 'Rapports, exports et QR codes',
            icone: Icons.bar_chart_rounded,
            points: <String>[
              'Rapports de l\'entreprise : choisissez la période et le type '
                  '(ventes, articles, finance, stock, dettes…), puis exportez '
                  'en PDF ou Excel.',
              'Les rapports s\'adaptent à votre activité : expirations '
                  '(pharmacie), occupation et séjours (hôtel), commandes '
                  '(restaurant).',
              'QR codes : imprimez les étiquettes de vos articles (le prix '
                  'n\'est jamais dans le code — il est relu à chaque scan).',
            ],
          ),
          _TitreSection(
            '💊 Pharmacie',
            'Activée si votre activité est « Pharmacie » : suivez les lots et '
            'les dates de péremption, bloquez les ventes expirées.',
          ),
          _Etape(
            numero: '8',
            titre: 'Lots et dates de péremption',
            icone: Icons.medication_rounded,
            points: <String>[
              'Sur chaque article : renseignez le numéro de LOT et la DATE '
                  'D\'EXPIRATION (facultatifs, mais recommandés).',
              'Carte « Expirations » sur l\'accueil : compteur rouge dès '
                  'qu\'un produit est expiré ou expire sous 30 jours.',
              'Écran Expirations : tri par urgence (expirés → ≤ 30 jours) '
                  'avec filtres et valeurs du stock.',
            ],
          ),
          _Etape(
            numero: '9',
            titre: 'Vente bloquée si expiré',
            icone: Icons.block_rounded,
            points: <String>[
              'Par sécurité, la caisse REFUSE de vendre un produit dont la '
                  'date est dépassée (message clair au comptoir).',
              'Un produit SANS date n\'est jamais bloqué — vos autres rayons '
                  'ne changent pas.',
              'Le patron peut autoriser la vente des expirés : réglage '
                  '`ventes.bloquer_produits_expires` (paramètre boutique).',
              'Rapport « Expirations » : la liste des produits à retirer, '
                  'lot par lot.',
            ],
          ),
          _TitreSection(
            '🏨 Hôtel',
            'Activée si votre activité est « Hôtel » : chambres, réservations, '
            'arrivées, départs et facture de séjour.',
          ),
          _Etape(
            numero: '10',
            titre: 'Configurer les chambres',
            icone: Icons.king_bed_rounded,
            points: <String>[
              'Chambres → « Nouvelle chambre » : numéro, type (Simple, '
                  'Double, Suite…), capacité et prix par nuit.',
              'Le statut suit la vraie vie : Libre → Réservée → Occupée → '
                  'À nettoyer → Libre.',
              'Après le ménage, passez la chambre « Libre » (bouton de la '
                  'Réception ou de la liste des chambres).',
            ],
          ),
          _Etape(
            numero: '11',
            titre: 'Prendre une réservation',
            icone: Icons.event_available_rounded,
            points: <String>[
              'Réservations → « Nouvelle réservation » : chambre, dates, '
                  'nombre de personnes, client (fiche ou simple nom).',
              'Le prix/nuit est pré-rempli (modifiable pour un tarif négocié) '
                  'et le total est calculé : nuits × prix.',
              'Enregistrez l\'avance éventuelle : le reste à payer est suivi '
                  'automatiquement.',
              'Impossible de doubler une réservation : le serveur refuse deux '
                  'séjours sur la même chambre aux mêmes dates.',
            ],
          ),
          _Etape(
            numero: '12',
            titre: 'Arrivée et départ (réception)',
            icone: Icons.room_service_rounded,
            points: <String>[
              'Écran Réception : la liste des ARRIVÉES du jour — bouton '
                  '« Arrivée » pour le check-in (lit bébé ? notez-le dans la '
                  'réservation).',
              'Les DÉPARTS du jour apparaissent en dessous : bouton '
                  '« Départ » — encaissez le solde restant s\'il y en a un.',
              'La chambre passe automatiquement « Occupée » puis '
                  '« À nettoyer ».',
              'Besoin d\'encaisser un acompte en cours de séjour ? Menu '
                  '« Encaisser » sur la ligne du client.',
            ],
          ),
          _Etape(
            numero: '13',
            titre: 'Facture de séjour et rapports',
            icone: Icons.receipt_long_rounded,
            points: <String>[
              'Sur une réservation : « Voir la facture » — récapitulatif '
                  'client, chambre, nuits × prix, avance et reste à payer.',
              'Rapports : « Occupation (hôtel) » (taux, arrivées/départs par '
                  'jour, nuits vendues, CA séjours) et « Arrivées & départs » '
                  '(liste des séjours avec soldes).',
            ],
          ),
          _TitreSection(
            '🍽️ Restaurant',
            'Activée si votre activité est « Restaurant » : plan de salle, '
            'commandes, écran cuisine et encaissement via la caisse.',
          ),
          _Etape(
            numero: '14',
            titre: 'Configurer les tables',
            icone: Icons.table_restaurant_rounded,
            points: <String>[
              'Tables → « Nouvelle table » : numéro, zone (Salle, Terrasse…) '
                  'et nombre de places.',
              'La table devient « Occupée » dès qu\'une commande est ouverte '
                  'et redevient « Libre » après encaissement ou annulation.',
              '« Réservée » permet d\'anticiper un client attendu.',
            ],
          ),
          _Etape(
            numero: '15',
            titre: 'Prendre et envoyer une commande',
            icone: Icons.restaurant_menu_rounded,
            points: <String>[
              'Touchez une table → « Prendre une commande » (client et nombre '
                  'de personnes en option).',
              'Ajoutez les plats et boissons depuis le catalogue : chaque '
                  'ligne fige le prix et le nom au moment de la commande.',
              '« Envoyer en cuisine » : la commande part en préparation. Un '
                  'article ajouté plus tard la repasse en saisie (il doit '
                  'repartir en cuisine).',
            ],
          ),
          _Etape(
            numero: '16',
            titre: 'L\'écran cuisine',
            icone: Icons.soup_kitchen_rounded,
            points: <String>[
              'Cuisine : trois colonnes — À préparer → En préparation → '
                  'Prêtes à servir (mise à jour automatique toutes les '
                  '20 secondes).',
              'Le cuisinier touche « Commencer » puis « Prête » ; le serveur '
                  'marque « Marquer servie » et encaisse à la fin du repas.',
              'Astuce : mettez une tablette en cuisine, l\'écran reste ouvert.',
            ],
          ),
          _Etape(
            numero: '17',
            titre: 'Encaisser la commande',
            icone: Icons.payments_rounded,
            points: <String>[
              'Bouton « Encaisser » du détail de commande : la vente réelle '
                  'est créée dans la CAISSE (stock décrémenté, reçu et '
                  'journal compris).',
              'La table redevient libre toute seule.',
              'Rapport « Commandes (restaurant) » : commandes par jour, '
                  'encaissées, annulées et montant.',
            ],
          ),
          _TitreSection(
            '🎉 Salle des fêtes',
            'Activée si votre activité est « Salle des fêtes » : salles, '
            'calendrier des événements, prestations et encaissements.',
          ),
          _Etape(
            numero: '18',
            titre: 'Créer vos salles',
            icone: Icons.meeting_room_rounded,
            points: <String>[
              'Événements → icône salle (en haut) → « Nouvelle salle » : nom, '
                  'capacité, prix par jour et équipements (sono, parking…).',
              'Le prix par jour est un tarif proposé : vous pouvez le '
                  'négocier pour chaque événement.',
              'Désactivez une salle plutôt que de la supprimer si elle a '
                  'déjà des événements.',
            ],
          ),
          _Etape(
            numero: '19',
            titre: 'Enregistrer un événement',
            icone: Icons.celebration_rounded,
            points: <String>[
              'Événements → « Nouvel événement » : salle, titre (Mariage '
                  'Kabeya…), client, dates, heures et nombre d\'invités.',
              'Une salle ne peut pas être réservée deux fois sur les mêmes '
                  'dates : le calendrier est protégé automatiquement.',
              'L\'avance éventuelle est encaissée dès la création ; le solde '
                  'se suit dans le dossier.',
            ],
          ),
          _Etape(
            numero: '20',
            titre: 'Prestations, cycle de vie et encaissements',
            icone: Icons.room_service_rounded,
            points: <String>[
              'Ouvrez le dossier : ajoutez les prestations (traiteur, '
                  'décoration, sonorisation…) — elles S\'AJOUTENT au prix de '
                  'la salle.',
              'Faites avancer le dossier : Réservé → Confirmé → En cours → '
                  'Terminé (ou Annulé avec motif).',
              'Bouton « Encaisser » : avances, acomptes et soldes, avec le '
                  'mode de paiement — tout est tracé.',
              'Le tableau de bord d\'accueil affiche les événements à venir ; '
                  'la carte « Événements » rappelle le solde à encaisser.',
            ],
          ),
          _TitreSection(
            '🥖 Boulangerie',
            'Activée si votre activité est « Boulangerie » : matières '
            'premières, productions du jour, pertes et coût de revient.',
          ),
          _Etape(
            numero: '21',
            titre: 'Créer vos matières premières',
            icone: Icons.science_rounded,
            points: <String>[
              'Production → icône Sciences (en haut) → « Nouvelle matière » : '
                  'farine, levure, sucre… avec l\'unité (kg, l…) et le SEUIL '
                  'D\'ALERTE.',
              'Le prix par unité sert au calcul du coût de revient ; il se '
                  'met à jour à chaque approvisionnement.',
              'Une matière en alerte s\'affiche en rouge sur l\'accueil et '
                  'dans l\'atelier.',
            ],
          ),
          _Etape(
            numero: '22',
            titre: 'Approvisionner et surveiller le stock',
            icone: Icons.add_box_rounded,
            points: <String>[
              'Menu d\'une matière → « Approvisionner » : quantité reçue et '
                  'prix payé (le stock augmente immédiatement).',
              '« Inventaire (ajuster) » corrige le stock au niveau réellement '
                  'constaté (raison obligatoire : pesée, casse…).',
              'Le filtre « Alertes » liste ce qui manque avant la fournée.',
            ],
          ),
          _Etape(
            numero: '23',
            titre: 'Lancer et clôturer une production',
            icone: Icons.bakery_dining_rounded,
            points: <String>[
              'Production → « Nouvelle production » : produit fini (pain, '
                  'croissant…) et quantité prévue.',
              'Ouvrez le dossier : ajoutez les matières utilisées — elles '
                  'sont DÉDUITES du stock avec leur coût du moment.',
              '« Clôturer » : saisissez la quantité réellement produite — le '
                  'produit fini ENTRE EN STOCK, les pertes et le coût de '
                  'revient unitaire sont calculés automatiquement.',
              'Annuler une production en cours rend les matières au stock.',
            ],
          ),
          _TitreSection(
            '🥩 Vente au poids (boucherie)',
            'Activée si votre activité est « Boucherie » : les articles se '
            'vendent au kilo, avec pesée et ticket au poids.',
          ),
          _Etape(
            numero: '24',
            titre: 'Marquer un article « vendu au poids »',
            icone: Icons.scale_rounded,
            points: <String>[
              'Articles → ouvrez la fiche → activez « Vendu au poids (kg) » '
                  '(l\'unité se remplit en kg automatiquement).',
              'Le prix saisi est alors le prix AU KILO ; la liste affiche '
                  '« / kg » pour le repérer d\'un coup d\'œil.',
              'Le stock reste suivi en kg : il accepte les décimales '
                  '(12,5 kg).',
            ],
          ),
          _Etape(
            numero: '25',
            titre: 'Vendre à la pesée',
            icone: Icons.shopping_cart_checkout_rounded,
            points: <String>[
              'Au scan (ou au panier), la fiche propose la saisie du POIDS : '
                  'boutons + / − par pas de 0,5 kg ou saisie directe '
                  '(0,75 kg).',
              'Le ticket, la vente et le stock utilisent le poids exact — '
                  'rien à convertir.',
              'Astuce : branchez une balance à étiquette QR (module QR) pour '
                  'scanner directement le produit pesé.',
            ],
          ),
          _TitreSection(
            '👥 Équipe, assistant et réglages',
          ),
          _Etape(
            numero: '26',
            titre: 'Travailler en équipe',
            icone: Icons.badge_rounded,
            points: <String>[
              'Collaborateurs → ajoutez vos employés et leur rôle : Vendeur '
                  '(caisse), Magasinier (stock), Comptable, Gestionnaire…',
              'Chaque rôle ne voit que ses écrans : le vendeur d\'hôtel fait '
                  'les arrivées/départs sans toucher aux prix des chambres.',
              'Le patron garde tout : prix, rapports, permissions, '
                  'abonnement.',
            ],
          ),
          _Etape(
            numero: '27',
            titre: 'Assistant IA et abonnement',
            icone: Icons.smart_toy_rounded,
            points: <String>[
              'Assistant IA : posez vos questions (ventes du jour, conseils, '
                  'résumés) — les quotas se rechargent par packs de 10 à 100.',
              'Mon abonnement : suivez votre dossier d\'activation, vos '
                  'montants et vos échéances.',
              'En cas d\'impayé : le compte est restreint mais RIEN n\'est '
                  'supprimé — tout revient après régularisation.',
            ],
          ),
          _Etape(
            numero: '28',
            titre: 'Notifications, confort et légal',
            icone: Icons.settings_applications_rounded,
            points: <String>[
              'Paramètres → Notifications : alerte à chaque vente et rapport '
                  'de fin de journée (choisissez l\'heure).',
              'Accessibilité : agrandissez le texte pour un écran plus '
                  'confortable en boutique.',
              'Confidentialité et Conditions d\'utilisation : documents '
                  'officiels complets (droit congolais — Lubumbashi, RDC).',
              'Besoin d\'aide ? support@biasharayangu.cd — du lundi au '
                  'samedi.',
            ],
          ),
        ],
      ),
    );
  }
}

/// Bandeau d'introduction du guide.
class _Entete extends StatelessWidget {
  const _Entete();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppDegrades.primaire,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Row(
        children: <Widget>[
          Icon(Icons.menu_book_rounded, color: Colors.white, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Le guide officiel : 28 étapes pour maîtriser CHAQUE module — '
              'de la première vente à la production de votre boulangerie.',
              style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Titre de section (module).
class _TitreSection extends StatelessWidget {
  const _TitreSection(this.titre, [this.sousTitre]);

  final String titre;
  final String? sousTitre;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            titre,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (sousTitre != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(sousTitre!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// Une étape du guide (numéro, titre, icône, points clés).
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
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 15,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.12),
                child: Text(
                  numero,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(icone, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titre,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...points.map(
            (String point) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      point,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
