// lib/services/article_service.dart
//
// MODULE 5 — GESTION DES ARTICLES (multi-conditionnements)
//
// Accès Supabase aux trois tables du module :
//
//   • `public.produits`        — l'article de base (stock en unités de base) ;
//   • `public.conditionnements`— les emballages vendables (QR code auto) ;
//   • `public.categories`      — le référentiel des catégories (noms uniques).
//
// Toutes les méthodes publiques lèvent [ArticleServiceException] : les écrans
// n'ont donc jamais à manipuler une `PostgrestException`.

import 'package:biashara_yangu/utils/image_locale.dart';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/categorie.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/mouvement_article.dart';
import 'package:biashara_yangu/models/statut_expiration.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

/// Erreur métier du module « Gestion des articles ».
///
/// [message] est toujours rédigé en français et peut être affiché tel quel
/// à l'utilisateur (SnackBar, écran d'erreur…).
class ArticleServiceException implements Exception {
  const ArticleServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Accès Supabase au catalogue d'une boutique.
///
/// « Propriétaire » d'une boutique :
///   • un compte autonome (le patron) → lui-même ;
///   • un collaborateur (`utilisateurs.parent_id` renseigné) → son patron.
///
/// Toutes les requêtes sont filtrées sur ce propriétaire : chaque boutique
/// ne voit que son propre catalogue (la RLS du Module 5 applique la même
/// règle côté serveur).
class ArticleService {
  ArticleService._();

  static final ArticleService instance = ArticleService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Nom du bucket Storage des photos d'articles (créé par la migration
  /// `20260916000008_module5_articles.sql`).
  static const String bucketPhotos = 'articles';

  // ---------------------------------------------------------------------------
  // PROPRIÉTAIRE COURANT
  // ---------------------------------------------------------------------------

  /// Identifiant du patron de la boutique connectée, ou `null` si aucune
  /// session n'est disponible.
  ///
  /// 1. session Supabase (ou [SessionManager] en secours) ;
  /// 2. `public.utilisateurs.parent_id` → le patron, pour un collaborateur ;
  /// 3. à défaut (hors ligne), la copie locale de l'utilisateur (SQLite).
  Future<String?> proprietaireCourant() async {
    final String? utilisateurId = await _utilisateurCourantId();
    if (utilisateurId == null || utilisateurId.isEmpty) return null;

    try {
      final dynamic reponse = await _client
          .from('utilisateurs')
          .select('parent_id')
          .eq('id', utilisateurId)
          .maybeSingle();

      final String? parent = parseStringOrNull(parseMap(reponse)?['parent_id']);
      return parent ?? utilisateurId;
    } catch (e) {
      debugPrint('ArticleService.proprietaireCourant (Supabase ignoré): $e');
    }

    try {
      final utilisateurLocal =
          await DBHelper.instance.getUtilisateurById(utilisateurId);
      final String? parent = utilisateurLocal?.parentId;
      if (parent != null && parent.isNotEmpty) return parent;
    } catch (e) {
      debugPrint('ArticleService.proprietaireCourant (local ignoré): $e');
    }

    return utilisateurId;
  }

  /// Utilisateur connecté : session Supabase d'abord, session locale ensuite.
  Future<String?> _utilisateurCourantId() async {
    final String? id = _client.auth.currentUser?.id;
    if (id != null && id.isNotEmpty) return id;
    return SessionManager.getUserId();
  }

  /// Identifiant EXIGÉ par le Storage : les policies du bucket n'autorisent
  /// l'écriture que dans le dossier `auth.uid()`.
  String? _authId() {
    final String? id = _client.auth.currentUser?.id;
    return (id == null || id.isEmpty) ? null : id;
  }

  Future<String> _requireProprietaire() async {
    final String? utilisateurId = await _utilisateurCourantId();
    if (utilisateurId == null || utilisateurId.isEmpty) {
      throw const ArticleServiceException(
        'Session introuvable : connectez-vous puis réessayez.',
      );
    }

    final String? proprietaire = await proprietaireCourant();
    return (proprietaire == null || proprietaire.isEmpty)
        ? utilisateurId
        : proprietaire;
  }

  // ---------------------------------------------------------------------------
  // ARTICLES (public.produits)
  // ---------------------------------------------------------------------------

  /// Tous les articles de la boutique, triés par nom, avec leurs
  /// conditionnements.
  ///
  /// Le filtrage (recherche / catégorie) est fait par [filtrer] : les volumes
  /// d'une boutique tiennent en mémoire, et la recherche « code » couvre
  /// aussi les codes-barres des conditionnements, hors de portée d'un simple
  /// `ilike` sur `produits`.
  Future<List<Article>> getArticles() async {
    final String proprietaire = await _requireProprietaire();
    return getArticlesPourProprietaire(proprietaire);
  }

  /// 🏢 MODE PLATEFORME — articles d'une boutique DONNÉE (production des
  /// étiquettes QR par l'administration : elle lit tous les catalogues).
  Future<List<Article>> getArticlesPourProprietaire(String proprietaire) {
    return _executer(
      () async {
        final List<dynamic> reponse = await _client
            .from('produits')
            .select()
            .eq('owner_id', proprietaire)
            .order('nom', ascending: true);

        final List<Article> articles =
            parseMapList(reponse).map(Article.fromMap).toList();

        final Map<int, List<Conditionnement>> parArticle =
            await _conditionnementsParProduit(
          articles.map((Article a) => a.id).toList(),
        );

        return articles
            .map((Article a) => a.copyWith(
                  conditionnements:
                      parArticle[a.id] ?? const <Conditionnement>[],
                ))
            .toList();
      },
      actionLibelle: 'le chargement des articles',
      messageEchec:
          'Impossible de charger les articles. Vérifiez votre connexion internet.',
    );
  }

  /// Un article et ses conditionnements, ou `null` s'il a été supprimé.
  Future<Article?> getArticleById(int id) {
    return _executer(
      () async {
        final dynamic reponse =
            await _client.from('produits').select().eq('id', id).maybeSingle();

        final Map<String, dynamic>? ligne = parseMap(reponse);
        if (ligne == null) return null;

        final Map<int, List<Conditionnement>> parArticle =
            await _conditionnementsParProduit(<int>[id]);

        return Article.fromMap(
          ligne,
          conditionnements: parArticle[id] ?? const <Conditionnement>[],
        );
      },
      actionLibelle: "le chargement de l'article",
      messageEchec:
          "Impossible de charger l'article. Vérifiez votre connexion internet.",
    );
  }

  /// 🏷️ CORRECTIF 59 — retrouve un article par son CODE-BARRES.
  ///
  /// Cherche d'abord `produits.code_barre` (l'unité de base du produit), puis
  /// en repli un CONDITIONNEMENT portant ce code (`code_barre_texte`) : les
  /// codes enregistrés avant le correctif 59 restent donc scannables.
  ///
  /// Renvoie `null` si aucun article de la boutique ne porte ce code — la RLS
  /// garantit qu'un code d'une autre boutique est invisible.
  Future<Article?> trouverParCodeBarre(String code) async {
    final String recherche = code.trim();
    if (recherche.isEmpty) return null;

    final dynamic ligne = await _client
        .from('produits')
        .select()
        .eq('code_barre', recherche)
        .limit(1)
        .maybeSingle();

    if (ligne is Map) {
      return Article.fromMap(Map<String, dynamic>.from(ligne));
    }

    // Repli : le code est celui d'un emballage (Module 5).
    final dynamic emballage = await _client
        .from('conditionnements')
        .select()
        .eq('code_barre_texte', recherche)
        .limit(1)
        .maybeSingle();

    if (emballage is! Map) return null;

    final int? produitId = int.tryParse('${emballage['produit_id']}');
    if (produitId == null) return null;

    return getArticleById(produitId);
  }

  /// Crée un article (le stock de départ est saisi en unités de base).
  Future<Article> creerArticle({
    required String nom,
    required String categorie,
    required double prixAchat,
    required double prixVente,
    required double quantite,
    required String uniteMesure,
    String? photo,
    String? description,
    String? lotNumero,
    DateTime? dateExpiration,
    bool vendableAuPoids = false,
    Map<String, String> attributs = const <String, String>{},
    String? codeBarre,
  }) {
    return _executer(
      () async {
        _validerArticle(
          nom: nom,
          prixAchat: prixAchat,
          prixVente: prixVente,
          quantite: quantite,
          uniteMesure: uniteMesure,
        );

        final String proprietaire = await _requireProprietaire();

        final Map<String, dynamic> reponse = await _client
            .from('produits')
            .insert(<String, dynamic>{
              'nom': nom.trim(),
              'categorie': categorie.trim(),
              'prix_achat': prixAchat,
              'prix_vente': prixVente,
              'quantite': quantite,
              'unite_mesure': uniteMesure.trim(),
              'photo': _texteOuNull(photo),
              'description': _texteOuNull(description),
              // 🧩 MODULE 16 C1 — pharmacie : lot & date de péremption.
              'lot_numero': _texteOuNull(lotNumero),
              'date_expiration': _isoJour(dateExpiration),
              // 🥩 MODULE 16 C6 — boucherie : vente au poids.
              'vendable_au_poids': vendableAuPoids,
              // 👕 MODULE 16 C8 — mode : variantes (taille, couleur…).
              'attributs': attributs,
              // 🏷️ CORRECTIF 59 — code-barres fabricant du produit.
              'code_barre': _texteOuNull(codeBarre),
              'owner_id': proprietaire,
            })
            .select()
            .single();

        return Article.fromMap(reponse);
      },
      actionLibelle: "la création de l'article",
      messageEchec:
          "Impossible de créer l'article. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Met à jour un article (identité, prix, stock, photo, description).
  ///
  /// ⚠️ Le stock est mis à jour DIRECTEMENT (`produits.quantite`) sans créer
  /// de mouvement : les triggers serveur des ventes / approvisionnements
  /// recalculeraient le stock une seconde fois.
  Future<Article> majArticle({
    required int id,
    required String nom,
    required String categorie,
    required double prixAchat,
    required double prixVente,
    required double quantite,
    required String uniteMesure,
    String? photo,
    String? description,
    String? lotNumero,
    DateTime? dateExpiration,
    bool vendableAuPoids = false,
    Map<String, String> attributs = const <String, String>{},
    String? codeBarre,
  }) {
    return _executer(
      () async {
        _validerArticle(
          nom: nom,
          prixAchat: prixAchat,
          prixVente: prixVente,
          quantite: quantite,
          uniteMesure: uniteMesure,
        );

        final Map<String, dynamic> reponse = await _client
            .from('produits')
            .update(<String, dynamic>{
              'nom': nom.trim(),
              'categorie': categorie.trim(),
              'prix_achat': prixAchat,
              'prix_vente': prixVente,
              'quantite': quantite,
              'unite_mesure': uniteMesure.trim(),
              'photo': _texteOuNull(photo),
              'description': _texteOuNull(description),
              // 🧩 MODULE 16 C1 — pharmacie : lot & date de péremption
              //  (une date effacée dans le formulaire doit être vidée ici).
              'lot_numero': _texteOuNull(lotNumero),
              'date_expiration': _isoJour(dateExpiration),
              // 🥩 MODULE 16 C6 — boucherie : vente au poids.
              'vendable_au_poids': vendableAuPoids,
              // 👕 MODULE 16 C8 — mode : variantes (taille, couleur…).
              'attributs': attributs,
              // 🏷️ CORRECTIF 59 — code-barres fabricant du produit
              //  (vidé ici si le champ a été effacé dans le formulaire).
              'code_barre': _texteOuNull(codeBarre),
            })
            .eq('id', id)
            .select()
            .single();

        return Article.fromMap(reponse);
      },
      actionLibelle: "l'enregistrement de l'article",
      messageEchec:
          "Impossible d'enregistrer les modifications. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  // ---------------------------------------------------------------------------
  // 🧩 MODULE 16 C1 — PHARMACIE : LOTS & EXPIRATIONS
  // ---------------------------------------------------------------------------

  /// Articles ayant une date de péremption, triés par urgence (expirés
  /// d'abord, puis les plus proches). [jours] = horizon : les produits
  /// expirant au-delà ne sont pas renvoyés (les expirés le sont toujours).
  Future<List<Article>> listerExpirations({int jours = 365}) async {
    final List<Article> articles = await getArticles();
    final DateTime reference = DateTime.now();
    final DateTime limite =
        DateTime(reference.year, reference.month, reference.day)
            .add(Duration(days: jours));

    final List<Article> concernes = articles
        .where((Article article) =>
            article.dateExpiration != null &&
            !article.dateExpiration!.isAfter(limite))
        .toList(growable: false);

    return StatutExpiration.trierParUrgence(concernes, reference: reference);
  }

  /// Nombre de produits EXPIRÉS ou expirant sous [jours] (carte d'accueil).
  /// Requête légère (identifiants seulement).
  Future<int> compterExpirations({int jours = 30}) {
    return _executer(
      () async {
        final String proprietaire = await _requireProprietaire();
        final DateTime reference = DateTime.now();
        final String limite = _isoJour(
          DateTime(reference.year, reference.month, reference.day)
              .add(Duration(days: jours)),
        )!;

        final List<dynamic> lignes = await _client
            .from('produits')
            .select('id')
            .eq('owner_id', proprietaire)
            .not('date_expiration', 'is', null)
            .lte('date_expiration', limite);

        return lignes.length;
      },
      actionLibelle: 'le comptage des expirations',
      messageEchec:
          'Impossible de compter les produits expirés. Vérifiez votre connexion internet.',
    );
  }

  /// « AAAA-MM-JJ » pour les colonnes `date` de Supabase (`null` accepté).
  static String? _isoJour(DateTime? date) {
    if (date == null) return null;
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  /// Supprime un article.
  ///
  /// Ses conditionnements partent automatiquement : la clé étrangère
  /// `conditionnements.produit_id → produits.id` est en `on delete cascade`.
  Future<void> supprimerArticle(int id) {
    return _executer(
      () async {
        await _client.from('produits').delete().eq('id', id);
      },
      actionLibelle: "la suppression de l'article",
      messageEchec:
          "Impossible de supprimer l'article. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  /// Filtrage en mémoire de la liste des articles.
  ///
  /// [recherche] couvre le nom, la catégorie, les VARIANTES (taille,
  /// couleur, marque — Module 16 C8) ET les codes des conditionnements
  /// (libellé, code-barre, identifiant du QR code) — « recherche par
  /// nom/code » du cahier des charges.
  static List<Article> filtrer(
    List<Article> articles, {
    String? recherche,
    String? categorie,
  }) {
    final String requete = (recherche ?? '').trim().toLowerCase();
    final String categorieCherchee = (categorie ?? '').trim();

    return articles.where((Article article) {
      if (categorieCherchee.isNotEmpty &&
          Categorie.normaliser(article.categorie) !=
              Categorie.normaliser(categorieCherchee)) {
        return false;
      }
      if (requete.isEmpty) return true;

      if (article.nom.toLowerCase().contains(requete)) return true;
      if (article.categorie.toLowerCase().contains(requete)) return true;

      // 👕 MODULE 16 C8 — variantes : « bleu » retrouve la chemise bleue.
      for (final String valeur in article.attributs.values) {
        if (valeur.toLowerCase().contains(requete)) return true;
      }

      for (final Conditionnement conditionnement in article.conditionnements) {
        if (conditionnement.libelle.toLowerCase().contains(requete))
          return true;
        final String? codeBarre = conditionnement.codeBarreTexte;
        if (codeBarre != null && codeBarre.toLowerCase().contains(requete)) {
          return true;
        }
        if (conditionnement.qrCodeId.toLowerCase().contains(requete)) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // CONDITIONNEMENTS (public.conditionnements)
  // ---------------------------------------------------------------------------

  /// Ajoute un conditionnement à un article.
  ///
  /// Le `qr_code_id` est généré AUTOMATIQUEMENT par la base (colonne
  /// `default gen_random_uuid()`), puis relu et renvoyé.
  Future<Conditionnement> ajouterConditionnement({
    required int produitId,
    required String libelle,
    required double quantiteUnitesBase,
    required double prixVente,
    String? codeBarreTexte,
  }) {
    return _executer(
      () async {
        _validerConditionnement(
          libelle: libelle,
          quantiteUnitesBase: quantiteUnitesBase,
          prixVente: prixVente,
        );

        final Map<String, dynamic> reponse = await _client
            .from('conditionnements')
            .insert(<String, dynamic>{
              'produit_id': produitId,
              'libelle': libelle.trim(),
              'quantite_unites_base': quantiteUnitesBase,
              'prix_vente': prixVente,
              'code_barre_texte': _texteOuNull(codeBarreTexte),
            })
            .select()
            .single();

        return Conditionnement.fromMap(reponse);
      },
      actionLibelle: 'la création du conditionnement',
      messageEchec:
          'Impossible de créer le conditionnement. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  /// Met à jour un conditionnement.
  ///
  /// ⚠️ RÈGLE MÉTIER : le prix de vente est écrit TEL QUEL. Changer
  /// [quantiteUnitesBase] ne modifie jamais [prixVente] : le formulaire
  /// n'applique aucune conversion automatique (un emballage peut être vendu
  /// moins cher — ou plus cher — que le prix de base × quantité).
  Future<void> majConditionnement({
    required String id,
    required String libelle,
    required double quantiteUnitesBase,
    required double prixVente,
    String? codeBarreTexte,
  }) {
    return _executer(
      () async {
        _validerConditionnement(
          libelle: libelle,
          quantiteUnitesBase: quantiteUnitesBase,
          prixVente: prixVente,
        );

        await _client.from('conditionnements').update(<String, dynamic>{
          'libelle': libelle.trim(),
          'quantite_unites_base': quantiteUnitesBase,
          'prix_vente': prixVente,
          'code_barre_texte': _texteOuNull(codeBarreTexte),
        }).eq('id', id);
      },
      actionLibelle: 'la mise à jour du conditionnement',
      messageEchec:
          'Impossible d\'enregistrer le conditionnement. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  /// Supprime un conditionnement. L'article de base n'est jamais touché.
  Future<void> supprimerConditionnement(String id) {
    return _executer(
      () async {
        await _client.from('conditionnements').delete().eq('id', id);
      },
      actionLibelle: 'la suppression du conditionnement',
      messageEchec:
          'Impossible de supprimer le conditionnement. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  Future<Map<int, List<Conditionnement>>> _conditionnementsParProduit(
    List<int> produitIds,
  ) async {
    if (produitIds.isEmpty) return <int, List<Conditionnement>>{};

    final List<dynamic> reponse = await _client
        .from('conditionnements')
        .select()
        .inFilter('produit_id', produitIds)
        .order('created_at', ascending: true);

    final Map<int, List<Conditionnement>> resultat =
        <int, List<Conditionnement>>{};

    for (final Conditionnement conditionnement
        in parseMapList(reponse).map(Conditionnement.fromMap)) {
      (resultat[conditionnement.produitId] ??= <Conditionnement>[])
          .add(conditionnement);
    }
    return resultat;
  }

  // ---------------------------------------------------------------------------
  // CATÉGORIES (public.categories)
  // ---------------------------------------------------------------------------

  /// Toutes les catégories, triées par nom.
  Future<List<Categorie>> getCategories() {
    return _executer(
      () async {
        final List<dynamic> reponse = await _client
            .from('categories')
            .select()
            .order('nom', ascending: true);

        return parseMapList(reponse).map(Categorie.fromMap).toList();
      },
      actionLibelle: 'le chargement des catégories',
      messageEchec:
          'Impossible de charger les catégories. Vérifiez votre connexion internet.',
    );
  }

  /// Crée une catégorie. Le nom est unique (erreur claire s'il existe déjà).
  Future<Categorie> creerCategorie(String nom) {
    return _executer(
      () async {
        final String propre = nom.trim();
        if (propre.isEmpty) {
          throw const ArticleServiceException(
            'Le nom de la catégorie ne peut pas être vide.',
          );
        }

        final Map<String, dynamic> reponse = await _client
            .from('categories')
            .insert(<String, dynamic>{'nom': propre})
            .select()
            .single();

        return Categorie.fromMap(reponse);
      },
      actionLibelle: 'la création de la catégorie',
      messageEchec:
          'Impossible de créer la catégorie. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  /// Renomme une catégorie et propage le nouveau nom aux articles de la
  /// boutique qui l'utilisaient (les articles référencent le nom, pas l'id).
  Future<void> renommerCategorie({
    required Categorie categorie,
    required String nouveauNom,
  }) {
    return _executer(
      () async {
        final String propre = nouveauNom.trim();
        if (propre.isEmpty) {
          throw const ArticleServiceException(
            'Le nom de la catégorie ne peut pas être vide.',
          );
        }
        if (propre == categorie.nom) return;

        await _client
            .from('categories')
            .update(<String, dynamic>{'nom': propre}).eq('id', categorie.id);

        // Propagation aux articles de la boutique (best-effort : un échec ici
        // n'annule pas le renommage du référentiel).
        try {
          final String proprietaire = await _requireProprietaire();
          await _client
              .from('produits')
              .update(<String, dynamic>{'categorie': propre})
              .eq('owner_id', proprietaire)
              .eq('categorie', categorie.nom);
        } catch (e) {
          debugPrint(
              'ArticleService.renommerCategorie (propagation ignorée): $e');
        }
      },
      actionLibelle: 'le renommage de la catégorie',
      messageEchec:
          'Impossible de renommer la catégorie. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  /// Supprime une catégorie du référentiel.
  ///
  /// Les articles qui l'utilisaient gardent leur texte : ils apparaîtront
  /// simplement « sans catégorie connue » jusqu'à réaffectation.
  Future<void> supprimerCategorie(int id) {
    return _executer(
      () async {
        await _client.from('categories').delete().eq('id', id);
      },
      actionLibelle: 'la suppression de la catégorie',
      messageEchec:
          'Impossible de supprimer la catégorie. Vérifiez votre connexion internet puis réessayez.',
    );
  }

  // ---------------------------------------------------------------------------
  // MOUVEMENTS DE STOCK (historique en lecture seule)
  // ---------------------------------------------------------------------------

  /// Historique des mouvements d'un article, du plus récent au plus ancien.
  ///
  /// Agrège les trois sources existantes : approvisionnements (entrées),
  /// ajustements (entrées/sorties) et ventes (sorties). Best-effort : une
  /// source illisible (droits, table vide…) ne bloque pas les autres.
  Future<List<MouvementArticle>> getMouvements(int produitId) async {
    final List<MouvementArticle> mouvements = <MouvementArticle>[];

    Future<void> charger(Future<void> Function() tache) async {
      try {
        await tache();
      } catch (e) {
        debugPrint('ArticleService.getMouvements (source ignorée): $e');
      }
    }

    await Future.wait(<Future<void>>[
      charger(() async {
        final List<dynamic> reponse = await _client
            .from('approvisionnements')
            .select('id, quantite_ajoutee, date_approvisionnement')
            .eq('produit_id', produitId)
            .order('date_approvisionnement', ascending: false)
            .limit(100);

        for (final Map<String, dynamic> ligne in parseMapList(reponse)) {
          mouvements.add(MouvementArticle(
            id: 'approvisionnement-${ligne['id']}',
            source: SourceMouvement.approvisionnement,
            quantite: parseDouble(ligne['quantite_ajoutee']),
            date: parseDateTimeOrNull(ligne['date_approvisionnement']),
          ));
        }
      }),
      charger(() async {
        final List<dynamic> reponse = await _client
            .from('ajustements')
            .select('id, quantite, raison, date')
            .eq('produit_id', produitId)
            .order('date', ascending: false)
            .limit(100);

        for (final Map<String, dynamic> ligne in parseMapList(reponse)) {
          mouvements.add(MouvementArticle(
            id: 'ajustement-${ligne['id']}',
            source: SourceMouvement.ajustement,
            quantite: parseDouble(ligne['quantite']),
            motif: parseStringOrNull(ligne['raison']),
            date: parseDateTimeOrNull(ligne['date']),
          ));
        }
      }),
      charger(() async {
        final List<dynamic> reponse = await _client
            .from('ventes')
            .select('id, quantite, mode_paiement, date')
            .eq('produit_id', produitId)
            .order('date', ascending: false)
            .limit(100);

        for (final Map<String, dynamic> ligne in parseMapList(reponse)) {
          mouvements.add(MouvementArticle(
            id: 'vente-${ligne['id']}',
            source: SourceMouvement.vente,
            quantite:
                -parseDouble(ligne['quantite']), // une vente SORT du stock
            motif: parseStringOrNull(ligne['mode_paiement']),
            date: parseDateTimeOrNull(ligne['date']),
          ));
        }
      }),
    ]);

    return MouvementArticle.recentsDAbord(mouvements);
  }

  // ---------------------------------------------------------------------------
  // TEMPS RÉEL
  // ---------------------------------------------------------------------------

  /// S'abonne aux modifications des articles, conditionnements et catégories.
  ///
  /// Renvoie le canal créé : l'appelant **doit** le libérer avec
  /// [arreterEcoute], en général dans `dispose()`.
  ///
  /// Si les tables ne sont pas publiées dans `supabase_realtime`, aucun
  /// événement n'arrive — l'abonnement reste simplement inactif.
  RealtimeChannel ecouterChangements(void Function() onChange) {
    final RealtimeChannel canal = _client.channel(
      'articles-${DateTime.now().microsecondsSinceEpoch}',
    );

    void notifier(PostgresChangePayload payload) {
      try {
        onChange();
      } catch (e) {
        debugPrint('ArticleService temps réel (callback): $e');
      }
    }

    canal
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'produits',
          callback: notifier,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conditionnements',
          callback: notifier,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categories',
          callback: notifier,
        )
        .subscribe();

    return canal;
  }

  /// Libère un canal créé par [ecouterChangements].
  Future<void> arreterEcoute(RealtimeChannel canal) async {
    try {
      await _client.removeChannel(canal);
    } catch (e) {
      debugPrint('ArticleService.arreterEcoute: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // PHOTOS (Supabase Storage — bucket « articles »)
  // ---------------------------------------------------------------------------

  /// Téléverse une photo choisie sur l'appareil et renvoie son URL publique.
  ///
  /// Le fichier est rangé sous `<utilisateur>/<horodatage>.<extension>`
  /// (les policies du bucket n'autorisent l'écriture que dans ce dossier).
  Future<String> televerserPhoto(String cheminLocal) {
    return _executer(
      () async {
        final String? utilisateurId = _authId();
        if (utilisateurId == null) {
          throw const ArticleServiceException(
            'Session introuvable : connectez-vous puis réessayez.',
          );
        }

        final Uint8List? octets = await lireOctetsFichierLocal(cheminLocal);
        if (octets == null) {
          throw const ArticleServiceException(
            "Le fichier photo n'est plus accessible. Choisissez une autre image.",
          );
        }

        // 🌐 PHASE F (web) — l'extension vient du chemin quand il en a une
        // (fichier natif) ; sinon « jpg » (blob navigateur).
        final String brut = cheminLocal.split('.').last.toLowerCase();
        final String extension = cheminLocal.contains('.') &&
                brut.length <= 5 &&
                !brut.contains('/')
            ? brut
            : 'jpg';
        final String chemin =
            '$utilisateurId/${DateTime.now().millisecondsSinceEpoch}.$extension';
        await _client.storage.from(bucketPhotos).uploadBinary(
              chemin,
              octets,
              fileOptions: FileOptions(
                contentType: 'image/$extension',
                upsert: false,
              ),
            );

        return _client.storage.from(bucketPhotos).getPublicUrl(chemin);
      },
      actionLibelle: 'le téléversement de la photo',
      messageEchec:
          "Impossible d'envoyer la photo. Vérifiez votre connexion internet puis réessayez.",
    );
  }

  // ---------------------------------------------------------------------------
  // VALIDATIONS & OUTILS INTERNES
  // ---------------------------------------------------------------------------

  void _validerArticle({
    required String nom,
    required double prixAchat,
    required double prixVente,
    required double quantite,
    required String uniteMesure,
  }) {
    if (nom.trim().isEmpty) {
      throw const ArticleServiceException(
          "Le nom de l'article est obligatoire.");
    }
    if (uniteMesure.trim().isEmpty) {
      throw const ArticleServiceException(
        "L'unité de mesure de base est obligatoire (bouteille, pièce…).",
      );
    }
    if (prixAchat < 0 || prixVente < 0) {
      throw const ArticleServiceException(
        'Les prix ne peuvent pas être négatifs.',
      );
    }
    if (quantite < 0) {
      throw const ArticleServiceException(
        'La quantité en stock ne peut pas être négative.',
      );
    }
  }

  void _validerConditionnement({
    required String libelle,
    required double quantiteUnitesBase,
    required double prixVente,
  }) {
    if (libelle.trim().isEmpty) {
      throw const ArticleServiceException(
        'Le libellé du conditionnement est obligatoire (ex. « Farde de 12 »).',
      );
    }
    if (quantiteUnitesBase <= 0) {
      throw const ArticleServiceException(
        "La quantité en unités de base doit être supérieure à zéro.",
      );
    }
    if (prixVente < 0) {
      throw const ArticleServiceException(
        'Le prix de vente ne peut pas être négatif.',
      );
    }
  }

  String? _texteOuNull(String? valeur) {
    final String texte = (valeur ?? '').trim();
    return texte.isEmpty ? null : texte;
  }

  /// Exécute [action] en traduisant toute erreur en
  /// [ArticleServiceException] dont le message est prêt à être affiché.
  Future<T> _executer<T>(
    Future<T> Function() action, {
    required String actionLibelle,
    required String messageEchec,
  }) async {
    try {
      return await action();
    } on ArticleServiceException {
      rethrow;
    } on PostgrestException catch (e) {
      debugPrint(
          'ArticleService ($actionLibelle) PostgrestException: ${e.code} ${e.message}');
      throw ArticleServiceException(_messagePostgrest(e, actionLibelle));
    } on AuthException catch (e) {
      debugPrint('ArticleService ($actionLibelle) AuthException: ${e.message}');
      throw const ArticleServiceException(
        'Votre session a expiré. Veuillez vous reconnecter.',
      );
    } catch (e, st) {
      debugPrint('ArticleService ($actionLibelle): $e\n$st');
      throw ArticleServiceException(messageEchec);
    }
  }

  /// Traduit une erreur PostgREST en message français compréhensible.
  String _messagePostgrest(PostgrestException e, String actionLibelle) {
    final String? code = e.code;
    final String brut = e.message.toLowerCase();

    switch (code) {
      case '23505':
        return 'Ce nom existe déjà dans la base de données.';
      case '23503':
        return "L'article visé n'existe plus dans la base de données.";
      case '23502':
        return 'Un champ obligatoire est manquant. Vérifiez le formulaire.';
      case '23514':
        return 'Une valeur du formulaire est refusée par la base de données '
            '(quantité de conditionnement positive, par exemple).';
      case '22P02':
        return "La valeur transmise n'est pas valide pour la base de données.";
      case 'PGRST116':
        return "L'article demandé est introuvable.";
    }

    if (code == '42501' ||
        brut.contains('permission') ||
        brut.contains('policy')) {
      return "Accès refusé : votre compte n'a pas les droits nécessaires pour $actionLibelle.";
    }
    if (code == '42P01' ||
        brut.contains('does not exist') ||
        brut.contains('could not find the table')) {
      return 'La base de données est incomplète : exécutez le script SQL du Module 5 '
          '(supabase/migrations/20260916000008_module5_articles.sql).';
    }
    if (brut.contains('failed host lookup') ||
        brut.contains('socket') ||
        brut.contains('network') ||
        brut.contains('connection')) {
      return 'Connexion impossible. Vérifiez votre accès internet puis réessayez.';
    }

    // 🧾 MODULE 17 — les refus du serveur suivent la convention du projet
    // « CODE|message français » (ACTIVATION_REQUISE, ABONNEMENT_EXPIRE…,
    // PRODUIT_EXPIRE…). On affiche directement la partie rédigée.
    final String texte = messageErreur(e.message);
    if (texte != e.message && texte.isNotEmpty) return texte;

    return 'Erreur lors de $actionLibelle : ${e.message}';
  }

  /// Extrait le message utilisateur d'une erreur serveur préfixée
  /// (`CODE|message`), comme les autres services du projet.
  static String messageErreur(String brut) {
    final String texte = brut.trim();

    //  🏷️ CORRECTIF 59 — le code-barres est unique par patron : la base
    //  refuse un doublon. On l'explique en français plutôt que de laisser
    //  passer l'erreur technique de PostgreSQL.
    if (texte.contains('idx_produits_code_barre_unique') ||
        (texte.contains('duplicate key') && texte.contains('code_barre'))) {
      return 'Ce code-barres est déjà utilisé par un autre produit de votre '
          'boutique. Scannez-le depuis la liste pour ouvrir la bonne fiche, '
          'ou saisissez un autre code.';
    }

    final int separateur = texte.indexOf('|');
    if (separateur < 0 || separateur == texte.length - 1) return texte;
    return texte.substring(separateur + 1).trim();
  }
}
