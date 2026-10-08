// lib/services/scanner_service.dart
//
// MODULE 7 — RÉSOLUTION DES QR CODES SCANNÉS PAR LE VENDEUR.
//
// Le QR code ne contient QUE l'identité de l'objet (Module 6) :
//
//     PROD:123                → l'article public.produits n° 123
//     COND:<uuid>             → le conditionnement (qr_code_id)
//
// 🏷️ CORRECTIF 59 — un code qui n'est PAS une étiquette de l'application est
// désormais traité comme un CODE-BARRES FABRICANT (EAN-13, UPC, Code 128,
// ITF-14…) : on le cherche dans `produits.code_barre`, puis, en repli, dans
// `conditionnements.code_barre_texte` (codes saisis avant le correctif 59).
//
// [resoudre] relit dans Supabase l'article et/ou le conditionnement VISÉS,
// puis renvoie un [ArticleScanne] complet : stock, prix unitaire et unité
// vendue sont donc toujours à jour, même si l'étiquette a été imprimée il y
// a longtemps.
//
// Les erreurs sont des [ScannerException] au message déjà rédigé en français :
//   • [TypeErreurScan.formatInconnu] — QR étranger ou mal formé ;
//   • [TypeErreurScan.introuvable]   — l'objet n'existe plus, ou il appartient
//     à une autre boutique (la RLS le rend invisible) ;
//   • [TypeErreurScan.reseau]        — base injoignable.
//
// Le service tient aussi l'historique des [tailleHistorique] derniers scans,
// affiché sous la caméra (re-scan rapide au panier).

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/article_scanne.dart';
import 'package:biashara_yangu/models/conditionnement.dart';
import 'package:biashara_yangu/models/etiquette_qr.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/json_parsing.dart';

/// Nature d'une erreur de scan (le message reste affichable tel quel).
enum TypeErreurScan { formatInconnu, introuvable, reseau }

/// Erreur métier du scanner (message en français destiné au vendeur).
class ScannerException implements Exception {
  const ScannerException(
    this.message, {
    this.type = TypeErreurScan.introuvable,
  });

  final String message;
  final TypeErreurScan type;

  @override
  String toString() => message;
}

/// Lecture des articles / conditionnements à partir d'un code scanné.
///
/// Singleton : `ScannerService.instance`.
class ScannerService {
  ScannerService._();

  static final ScannerService instance = ScannerService._();

  /// Nombre de scans conservés dans l'historique rapide.
  static const int tailleHistorique = 5;

  /// Format d'un `qr_code_id` (uuid v4 généré par la base).
  static final RegExp _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  SupabaseClient get _client => SupabaseService.instance.client;

  /// Les [tailleHistorique] derniers articles scannés, du plus récent au plus
  /// ancien (affichés sous la caméra pour re-ajouter au panier).
  final ValueNotifier<List<ArticleScanne>> historique =
      ValueNotifier<List<ArticleScanne>>(const <ArticleScanne>[]);

  // ---------------------------------------------------------------------------
  // RÉSOLUTION D'UN CODE
  // ---------------------------------------------------------------------------

  /// Relit l'objet désigné par [codeBrut] (« `PROD:123` », « `COND:<uuid>` »).
  ///
  /// Lève une [ScannerException] si le code est inconnu, si l'objet n'existe
  /// plus ou si la base est injoignable.
  Future<ArticleScanne> resoudre(String? codeBrut) async {
    final EtiquetteQr? etiquette = EtiquetteQr.decoder(codeBrut);

    //  🏷️ CORRECTIF 59 — ce n'est pas une étiquette de l'application : on le
    //  traite comme un code-barres fabricant.
    if (etiquette == null) {
      return _resoudreCodeBarre(codeBrut);
    }

    try {
      switch (etiquette.type) {
        case TypeQrCode.article:
          return await _resoudreArticle(etiquette);
        case TypeQrCode.conditionnement:
          return await _resoudreConditionnement(etiquette);
      }
    } on ScannerException {
      rethrow;
    } catch (e) {
      debugPrint('ScannerService.resoudre : $e');
      throw const ScannerException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurScan.reseau,
      );
    }
  }

  /// 🏷️ CORRECTIF 59 — résout un CODE-BARRES FABRICANT.
  ///
  /// Cherche le code dans `produits.code_barre` puis, en repli, dans les
  /// conditionnements : un code déjà enregistré sur un emballage reste donc
  /// scannable. Le code est comparé à l'identique, espaces retirés.
  Future<ArticleScanne> _resoudreCodeBarre(String? codeBrut) async {
    final String code = (codeBrut ?? '').trim();
    if (code.isEmpty) {
      throw const ScannerException(
        'Code illisible : aucun code-barres détecté.',
        type: TypeErreurScan.formatInconnu,
      );
    }

    try {
      final Article? article =
          await ArticleService.instance.trouverParCodeBarre(code);

      if (article == null) {
        throw ScannerException(
          'Code-barres inconnu : aucun produit de votre boutique ne porte « '
          '$code ». Enregistrez ce code dans la fiche du produit, puis '
          'réessayez.',
          type: TypeErreurScan.introuvable,
        );
      }

      return ArticleScanne(article: article);
    } on ScannerException {
      rethrow;
    } catch (e) {
      debugPrint('ScannerService._resoudreCodeBarre : $e');
      throw const ScannerException(
        'Connexion impossible : vérifiez votre réseau puis réessayez.',
        type: TypeErreurScan.reseau,
      );
    }
  }

  /// `PROD:<id>` → l'article correspondant, relu dans `public.produits`.
  Future<ArticleScanne> _resoudreArticle(EtiquetteQr etiquette) async {
    final int? id = int.tryParse(etiquette.identifiant);
    if (id == null) {
      throw const ScannerException(
        'QR code illisible : identifiant d\'article invalide.',
        type: TypeErreurScan.formatInconnu,
      );
    }

    final dynamic reponse = await _client
        .from('produits')
        .select()
        .eq('id', id)
        .maybeSingle();

    final Map<String, dynamic>? ligne = parseMap(reponse);
    if (ligne == null) {
      throw const ScannerException(
        'Article introuvable : il a peut-être été supprimé, ou il appartient '
        'à une autre boutique.',
      );
    }

    return ArticleScanne(article: Article.fromMap(ligne));
  }

  /// `COND:<uuid>` → le conditionnement PUIS son article.
  ///
  /// C'est le prix DU CONDITIONNEMENT qui est mis en avant (il est librement
  /// fixé par le patron, Module 5), et le stock de l'article qui sert de
  /// limite de vente.
  Future<ArticleScanne> _resoudreConditionnement(EtiquetteQr etiquette) async {
    final String qrCodeId = etiquette.identifiant;
    if (!_uuid.hasMatch(qrCodeId)) {
      throw const ScannerException(
        'QR code illisible : identifiant de conditionnement invalide.',
        type: TypeErreurScan.formatInconnu,
      );
    }

    final dynamic reponse = await _client
        .from('conditionnements')
        .select()
        .eq('qr_code_id', qrCodeId)
        .maybeSingle();

    final Map<String, dynamic>? ligne = parseMap(reponse);
    if (ligne == null) {
      throw const ScannerException(
        'Conditionnement introuvable : cette étiquette a peut-être été '
        'supprimée.',
      );
    }

    final Conditionnement conditionnement = Conditionnement.fromMap(ligne);

    final dynamic reponseArticle = await _client
        .from('produits')
        .select()
        .eq('id', conditionnement.produitId)
        .maybeSingle();

    final Map<String, dynamic>? ligneArticle = parseMap(reponseArticle);
    if (ligneArticle == null) {
      throw const ScannerException(
        'L\'article de ce conditionnement est introuvable.',
      );
    }

    return ArticleScanne(
      article: Article.fromMap(ligneArticle),
      conditionnement: conditionnement,
    );
  }

  // ---------------------------------------------------------------------------
  // HISTORIQUE RAPIDE (5 DERNIERS SCANS)
  // ---------------------------------------------------------------------------

  /// Enregistre un scan réussi : le code réapparaît en tête d'historique et
  /// les doublons sont fusionnés (une seule entrée par code).
  void enregistrerScan(ArticleScanne scanne) {
    final List<ArticleScanne> liste = <ArticleScanne>[
      scanne,
      ...historique.value.where((ArticleScanne e) => e.code != scanne.code),
    ];
    historique.value =
        List<ArticleScanne>.unmodifiable(liste.take(tailleHistorique));
  }

  /// Vide l'historique (déconnexion, changement de boutique…).
  void viderHistorique() {
    if (historique.value.isEmpty) return;
    historique.value = const <ArticleScanne>[];
  }
}
