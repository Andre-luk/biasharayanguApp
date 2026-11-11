import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
// `kIsWeb` : dans un navigateur il n'y a ni dossier ni fichier — la base
// SQLite vit dans IndexedDB sous un simple nom (voir `sqlite_local_web.dart`).
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

import 'utils/sqlite_local.dart';
import 'utils/fichiers_locaux.dart';

import 'models/ajustement.dart';
import 'models/depense.dart';
import 'models/dette.dart';
import 'models/paiement_dette.dart';
import 'models/inventaire_quotidien.dart';
import 'models/produit.dart';
import 'models/conditionnement.dart';
import 'models/vente.dart';
import 'models/utilisateur.dart';
import 'models/client.dart';
import 'models/category.dart';
import 'models/approvisionnement.dart';
import 'services/scope_donnees.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'models/collaborateur_stats.dart';

/// ✅ ENSUITE seulement les variables
final _uuidGenerator = Uuid();


class DBHelper {
  DBHelper._privateConstructor();
  static final DBHelper instance = DBHelper._privateConstructor();

  static Database? _db;

  // 1. On définit la version à 2
  // 🔌 V13 — 100 % HORS LIGNE : cache de lecture + conflits de synchronisation.
  // 🧾 V14 — CONDITIONNEMENTS LOCAUX : la caisse sait, SANS RÉSEAU, qu'un
  //          article se vend à l'unité, en farde ou en carton (et à quel prix).
  static const int _dbVersion = 18;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  Future<Database> _initDB() async {
    // 🌐 NAVIGATEUR — SQLite y est désormais disponible (WebAssembly +
    // IndexedDB), mais sans notion de dossier : la base est désignée par un
    // simple nom, et c'est le worker sqflite qui gère le stockage.
    if (kIsWeb) {
      preparerSqliteLocal();
      return await openDatabase(
        'biashara_yangu.db',
        version: _dbVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    }

    // 🖥️📱 Plateformes installées : SQLite obligatoire.
    if (!sqliteLocalDisponible) {
      throw UnsupportedError(
        'La base locale (SQLite) est indisponible sur cette plateforme.',
      );
    }

    preparerSqliteLocal();

    final documentsDirectory = await getApplicationDocumentsDirectory();
    String path = join(documentsDirectory.path, "biashara_yangu.db");

    return await openDatabase(
      path,
      version: _dbVersion, // Utilise la constante ici
      onCreate: _onCreate,
      onUpgrade: _onUpgrade, // 2. AJOUTE CETTE LIGNE
    );
  }

  // 🌐 PHASE F (web) — le chargement de SQLite embarqué vit désormais dans
  // `utils/sqlite_local_native.dart` (inaccessible au web) et est déclenché
  // par `preparerSqliteLocal()`.


  // ========================= CREATION & MIGRATION =========================

  Future<void> _onCreate(Database db, int version) async {
    // produits
    await db.execute('''
      CREATE TABLE produits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nom TEXT NOT NULL,
  categorie TEXT,
  prix_achat REAL DEFAULT 0.0,
  prix_vente REAL DEFAULT 0.0,
  quantite REAL DEFAULT 0.0,
  unite_mesure TEXT DEFAULT 'unité',
  photo TEXT,
  created_at TEXT,
  owner_id TEXT,
  supabase_id TEXT,
  updated_at TEXT,
  is_synced INTEGER DEFAULT 0,
  code_barre TEXT,
  devise TEXT,
  stock_illimite INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_produits_supabase_id 
      ON produits(supabase_id);
    ''');

    // 🏷️ MODULE 28 — un lecteur USB cherche l'article par son code-barres.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_produits_code_barre
      ON produits(code_barre);
    ''');

    await db.execute('''
CREATE TABLE ajustements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  produit_id INTEGER NOT NULL,
  quantite REAL NOT NULL,
  raison TEXT,
  date TEXT NOT NULL,
  is_synced INTEGER DEFAULT 0,
  supabase_id TEXT,
  owner_id TEXT  -- <--- AJOUTE CETTE LIGNE ICI
)
''');

    // Création table ventes
    await db.execute('''
  CREATE TABLE IF NOT EXISTS ventes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  produit_id INTEGER NOT NULL,
  quantite REAL NOT NULL,
  prix REAL NOT NULL,
  mode_paiement TEXT DEFAULT 'cash',
  date TEXT NOT NULL,
  owner_id TEXT,
  seller_id TEXT,
  client_id INTEGER,
  supabase_id TEXT,
  is_synced INTEGER DEFAULT 0,
  tentatives INTEGER DEFAULT 0,
  sync_erreur TEXT,
  conditionnement_id TEXT,
  quantite_vendue REAL
  )
''');

    // 🔌 V13 — cache de lecture : la dernière réponse connue de chaque écran.
    // Permet d'afficher rapports, abonnements et tableau de bord SANS réseau.
    await db.execute('''
  CREATE TABLE IF NOT EXISTS cache_lecture (
  cle TEXT PRIMARY KEY,
  valeur TEXT NOT NULL,
  maj_le TEXT NOT NULL
  )
''');

    // 🧾 V14 — les FORMATS DE VENTE de chaque article (farde, carton…),
    // recopiés du serveur pour que la caisse les propose même hors ligne.
    await db.execute('''
  CREATE TABLE IF NOT EXISTS conditionnements (
  id TEXT PRIMARY KEY NOT NULL,
  produit_supabase_id TEXT NOT NULL,
  owner_id TEXT,
  libelle TEXT NOT NULL,
  quantite_unites_base REAL NOT NULL DEFAULT 1,
  prix_vente REAL NOT NULL DEFAULT 0,
  qr_code_id TEXT,
  code_barre_texte TEXT
  )
''');
    await db.execute('''
  CREATE INDEX IF NOT EXISTS idx_conditionnements_produit
  ON conditionnements(produit_supabase_id)
''');
    await db.execute('''
  CREATE TABLE utilisateurs (
  id TEXT PRIMARY KEY NOT NULL,
  nom TEXT,
  prenom,
  email TEXT UNIQUE,
  avatar TEXT,
  role TEXT DEFAULT 'vendor',
  new_role TEXT,
  entreprise_id TEXT,
  valide INTEGER DEFAULT 1,
  parent_id TEXT,
  password_hash TEXT -- 🔐 AJOUTÉ
);
''');

    // clients
    await db.execute('''
  CREATE TABLE clients (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    owner_id TEXT,         -- UUID de Supabase
    nom TEXT,
    telephone TEXT,
    email TEXT,
    adresse TEXT,          -- ✅ AJOUTÉ : Cette ligne manquait !
    supabase_id TEXT,      -- 🔑 ID correspondant dans Supabase
    is_synced INTEGER DEFAULT 0 -- 🔑 0=en attente, 1=synchronisé
  )
''');

    await db.execute('''
CREATE TABLE depenses (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  owner_id TEXT NOT NULL,
  motif TEXT NOT NULL,
  montant REAL NOT NULL,
  date TEXT NOT NULL,
  is_synced INTEGER DEFAULT 0,
  supabase_id TEXT
)
''');

    await db.execute('''
CREATE TABLE dettes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  owner_id TEXT NOT NULL,
  client_id INTEGER NOT NULL,
  vente_id INTEGER,
  montant_total REAL NOT NULL,
  montant_paye REAL DEFAULT 0,
  date_creation TEXT NOT NULL,
  statut TEXT DEFAULT 'non_paye',
  is_synced INTEGER DEFAULT 0,
  supabase_id TEXT
)
''');

    await db.execute(''' 
CREATE TABLE paiements_dette (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  dette_id INTEGER NOT NULL,
  montant REAL NOT NULL,
  date_paiement TEXT NOT NULL,
  owner_id TEXT,
  is_synced INTEGER DEFAULT 0,
  supabase_id TEXT
)''');

    await db.execute('''
CREATE TABLE inventaires_quotidiens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  owner_id TEXT NOT NULL,
  produit_id INTEGER NOT NULL,
  quantite_theorique REAL NOT NULL,
  quantite_physique REAL,
  date_cloture TEXT NOT NULL,
  is_synced INTEGER DEFAULT 0,
  supabase_id TEXT
)
''');

    // Catégories
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nom TEXT UNIQUE NOT NULL
      )
    ''');

    // Historique des Approvisionnements (Souvent synchronisé avec le produit)
    await db.execute('''
CREATE TABLE approvisionnements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  produit_id INTEGER NOT NULL,
  quantite_ajoutee REAL NOT NULL,
  prix_achat_unitaire REAL NOT NULL,
  date_approvisionnement TEXT NOT NULL,
  uuid TEXT,                    -- ✅ AJOUT CRITIQUE
  owner_id TEXT,
  supabase_id TEXT,
  is_synced INTEGER DEFAULT 0,
  FOREIGN KEY (produit_id) REFERENCES produits (id) ON DELETE CASCADE
)
''');

    await db.execute('''
  CREATE TABLE subscriptions (
    id TEXT PRIMARY KEY NOT NULL,
    user_id TEXT NOT NULL,
    plan TEXT NOT NULL,
    period_months INTEGER DEFAULT 1,
    start_date TEXT,
    end_date TEXT,
    active INTEGER DEFAULT 0,
    activated_by TEXT,
    activated_at TEXT,
    transaction_id TEXT,
    note TEXT,
    synced INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
  );
  ''');

  }


  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 11) { // On passe à la version 11 pour déclencher la mise à jour
      debugPrint('🚀 Migration V11 : Ajout de la colonne uuid...');

      final tables = ['produits', 'ventes', 'clients', 'approvisionnements', 'categories'];

      for (var table in tables) {
        // On ajoute 'uuid' au cas où ton code l'utilise à la place de 'supabase_id'
        await _safeAddColumn(db, table, 'uuid', 'TEXT');

        // On garde aussi les autres par sécurité
        await _safeAddColumn(db, table, 'supabase_id', 'TEXT');
        await _safeAddColumn(db, table, 'owner_id', 'TEXT');
        await _safeAddColumn(db, table, 'updated_at', 'TEXT');
      }
      debugPrint('✅ Migration V11 terminée.');
    }

    if (oldVersion < 12) {
      // 🔐 MODULE 4 — Système de permissions.
      // `new_role` est la colonne officielle (miroir de Supabase
      // `utilisateurs.new_role`) et `entreprise_id` permet de savoir à quelle
      // boutique un collaborateur se rattache, même hors ligne.
      debugPrint('🚀 Migration V12 : permissions (new_role, entreprise_id)...');
      await _safeAddColumn(db, 'utilisateurs', 'new_role', 'TEXT');
      await _safeAddColumn(db, 'utilisateurs', 'entreprise_id', 'TEXT');
      debugPrint('✅ Migration V12 terminée.');
    }

    if (oldVersion < 13) {
      // 🔌 100 % HORS LIGNE.
      //  • `cache_lecture` : la dernière réponse connue de chaque écran
      //    (rapports, abonnements, tableau de bord) pour fonctionner sans
      //    réseau ;
      //  • `tentatives` / `sync_erreur` sur `ventes` : une vente rejouée qui
      //    échoue n'est plus perdue ni réessayée sans fin → elle devient un
      //    CONFLIT lisible et résoluble.
      debugPrint('🚀 Migration V13 : cache de lecture + conflits de vente...');
      await _safeAddColumn(db, 'ventes', 'tentatives', 'INTEGER DEFAULT 0');
      await _safeAddColumn(db, 'ventes', 'sync_erreur', 'TEXT');
      await db.execute('''
  CREATE TABLE IF NOT EXISTS cache_lecture (
  cle TEXT PRIMARY KEY,
  valeur TEXT NOT NULL,
  maj_le TEXT NOT NULL
  )
''');
      debugPrint('✅ Migration V13 terminée.');
    }

    if (oldVersion < 14) {
      // 🧾 V14 — LES FORMATS DE VENTE, DISPONIBLES HORS LIGNE.
      //  Une farde, un carton, un sachet : chaque emballage a son prix et le
      //  nombre d'unités de base qu'il contient. Sans ce cache, la caisse ne
      //  pouvait proposer les formats qu'en interrogeant le serveur.
      debugPrint('🚀 Migration V14 : conditionnements locaux...');
      await db.execute('''
  CREATE TABLE IF NOT EXISTS conditionnements (
  id TEXT PRIMARY KEY NOT NULL,
  produit_supabase_id TEXT NOT NULL,
  owner_id TEXT,
  libelle TEXT NOT NULL,
  quantite_unites_base REAL NOT NULL DEFAULT 1,
  prix_vente REAL NOT NULL DEFAULT 0,
  qr_code_id TEXT,
  code_barre_texte TEXT
  )
''');
      await db.execute('''
  CREATE INDEX IF NOT EXISTS idx_conditionnements_produit
  ON conditionnements(produit_supabase_id)
''');
      debugPrint('✅ Migration V14 terminée.');
    }

    if (oldVersion < 15) {
      // 🔌 V15 — LE CODE-BARRES FABRICANT, EN LOCAL.
      //  Un lecteur USB lit le code imprimé sur l'emballage du fournisseur.
      //  Sans cette colonne, la caisse devait interroger le réseau pour le
      //  reconnaître : elle ne pouvait donc pas vendre au scanner hors ligne.
      debugPrint('🚀 Migration V15 : code-barres des articles...');
      await _safeAddColumn(db, 'produits', 'code_barre', 'TEXT');
      await db.execute('''
  CREATE INDEX IF NOT EXISTS idx_produits_code_barre
  ON produits(code_barre)
''');
      debugPrint('✅ Migration V15 terminée.');
    }

    if (oldVersion < 16) {
      // 🧾 V16 — LE FORMAT VENDU, JUSQU'AU SERVEUR.
      //  Une farde vendue 12 000 doit être rejouée au serveur AVEC son
      //  conditionnement ; sinon le serveur recalcule au prix de l'unité et
      //  les rapports affichent un montant faux.
      debugPrint('🚀 Migration V16 : conditionnement des ventes...');
      await _safeAddColumn(db, 'ventes', 'conditionnement_id', 'TEXT');
      await _safeAddColumn(db, 'ventes', 'quantite_vendue', 'REAL');
      debugPrint('✅ Migration V16 terminée.');
    }

    if (oldVersion < 17) {
      // 💵 V17 — LA DEVISE DE CHAQUE ARTICLE.
      //  Un produit peut être prixé en dollars et l'autre en francs, dans la
      //  MÊME boutique. La colonne est vide pour les articles existants : ils
      //  gardent la devise de l'entreprise.
      debugPrint('🚀 Migration V17 : devise par article...');
      await _safeAddColumn(db, 'produits', 'devise', 'TEXT');
      debugPrint('✅ Migration V17 terminée.');
    }

    if (oldVersion < 18) {
      // ♾️ V18 — ARTICLES VENDUS SANS SUIVI DE STOCK.
      //  Certains produits ne peuvent pas être comptés : le stock n'est ni
      //  contrôlé ni décrémenté, et la caisse continue de vendre.
      debugPrint('🚀 Migration V18 : stock non suivi...');
      await _safeAddColumn(db, 'produits', 'stock_illimite', 'INTEGER DEFAULT 0');
      debugPrint('✅ Migration V18 terminée.');
    }
  }

  /// Fonction utilitaire pour ajouter une colonne sans crash si elle existe déjà
  Future<void> _safeAddColumn(Database db, String table, String column, String type) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
      debugPrint('Colone [$column] ajoutée à la table [$table]');
    } catch (e) {
      // On ignore l'erreur si la colonne existe déjà (code 1 sur SQLite)
      debugPrint('Note: La colonne [$column] est déjà présente dans [$table].');
    }
  }

  Future<void> close() async {
    final db = _db; // On utilise l'instance privée pour ne pas la recréer
    if (db != null) {
      await db.close();
      _db = null;
      debugPrint('🔐 Base de données fermée.');
    }
  }

  // ========================= MAINTENANCE & SAUVEGARDE (inchangé) =========================

  Future<String> getDatabasePathFile() async {
    // 🌐 Navigateur : pas de chemin de fichier — la base est dans IndexedDB.
    if (kIsWeb) return 'biashara_yangu.db';
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'biashara_yangu.db');
    return path;
  }

  Future<String> backupDatabase() async {
    final databasePath = await getDatabasePathFile();
    if (!await fichierLocalExiste(databasePath)) {
      throw Exception("Fichier de base de données introuvable.");
    }
    final appDocDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', '');
    final backupFileName = 'biashara_yangu_backup_$timestamp.db';
    final backupPath = join(appDocDir.path, backupFileName);
    await close();
    await copierFichierLocal(depuis: databasePath, vers: backupPath);
    return backupPath;
  }

  Future<void> restoreDatabase(String backupFilePath) async {
    if (!await fichierLocalExiste(backupFilePath)) {
      throw Exception("Fichier de sauvegarde introuvable à: $backupFilePath.");
    }
    final databasePath = await getDatabasePathFile();
    await close();
    await copierFichierLocal(depuis: backupFilePath, vers: databasePath);
    _db = await _initDB();
  }

// --------------------- Depenses, inventaire, dettes ---------------------

// --------------------- DEPENSES ---------------------

  Future<int> insertDepense(Depense d) async {
    final db = await database;

    return await db.insert('depenses', {
      'owner_id': d.ownerId,
      'motif': d.motif,
      'montant': d.montant,
      'date': d.date,
      'is_synced': d.isSynced,
      'supabase_id': d.supabaseId,
    });
  }

  Future<List<Depense>> getDepenses({required String ownerId}) async {
    final db = await database;

    final maps = await db.query(
      'depenses',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'date DESC',
    );

    return maps.map((e) => Depense.fromMap(e)).toList();
  }

  Future<Depense?> getDepenseById(int id) async {
    final db = await database;

    final result = await db.query(
      'depenses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return Depense.fromMap(result.first);
  }

  Future<List<Depense>> getUnsyncedDepenses({required String ownerId}) async {
    final db = await database;

    final maps = await db.query(
      'depenses',
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
      orderBy: 'date ASC',
    );

    return maps.map((e) => Depense.fromMap(e)).toList();
  }

  Future<int> markDepenseAsSynced(int localId, String supabaseId) async {
    final db = await database;

    return await db.update(
      'depenses',
      {
        'is_synced': 1,
        'supabase_id': supabaseId,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<int> deleteDepenseById(int id) async {
    final db = await database;
    return await db.delete(
      'depenses',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteDepenseBySupabaseId(String supabaseId) async {
    final db = await database;

    return await db.delete(
      'depenses',
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
    );
  }

  Future<int> upsertDepenseFromSupabase(Depense d) async {
    final db = await database;

    if (d.supabaseId == null || d.supabaseId!.isEmpty) return 0;

    final data = d.toMap()..['is_synced'] = 1;

    final existing = await db.query(
      'depenses',
      where: 'supabase_id = ?',
      whereArgs: [d.supabaseId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final localId = existing.first['id'] as int;
      data.remove('id');

      return await db.update(
        'depenses',
        data,
        where: 'id = ?',
        whereArgs: [localId],
      );
    } else {
      data.remove('id');
      return await db.insert('depenses', data);
    }
  }

// --------------------- DETTES -----------------------

  Future<int> insertDette(Dette d) async {
    final db = await database;

    return await db.insert('dettes', {
      'owner_id': d.ownerId,
      'client_id': d.clientId,
      'vente_id': d.venteId,
      'montant_total': d.montantTotal,
      'montant_paye': d.montantPaye,
      'date_creation': d.dateCreation,
      'statut': d.statut,
      'is_synced': d.isSynced,
      'supabase_id': d.supabaseId,
    });
  }

  Future<List<Dette>> getDettes({required String ownerId}) async {
    final db = await database;

    final maps = await db.query(
      'dettes',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'date_creation DESC',
    );

    return maps.map((e) => Dette.fromMap(e)).toList();
  }

  Future<Dette?> getDetteById(int id) async {
    final db = await database;

    final result = await db.query(
      'dettes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return Dette.fromMap(result.first);
  }

  Future<List<Dette>> getUnsyncedDettes({required String ownerId}) async {
    final db = await database;

    final maps = await db.query(
      'dettes',
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
      orderBy: 'date_creation ASC',
    );

    return maps.map((e) => Dette.fromMap(e)).toList();
  }

  Future<int> markDetteAsSynced(int localId, String supabaseId) async {
    final db = await database;

    return await db.update(
      'dettes',
      {
        'is_synced': 1,
        'supabase_id': supabaseId,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<int> deleteDetteById(int id) async {
    final db = await database;
    return await db.delete(
      'dettes',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteDetteBySupabaseId(String supabaseId) async {
    final db = await database;

    return await db.delete(
      'dettes',
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
    );
  }

  Future<int> upsertDetteFromSupabase(Dette d) async {
    final db = await database;

    if (d.supabaseId == null || d.supabaseId!.isEmpty) return 0;

    final data = d.toMap()..['is_synced'] = 1;

    final existing = await db.query(
      'dettes',
      where: 'supabase_id = ?',
      whereArgs: [d.supabaseId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final localId = existing.first['id'] as int;
      data.remove('id');

      return await db.update(
        'dettes',
        data,
        where: 'id = ?',
        whereArgs: [localId],
      );
    } else {
      data.remove('id');
      return await db.insert('dettes', data);
    }
  }

  Future<int> updateDetteStatus(int id, double montantPaye, String statut) async {
    final db = await instance.database;

    return await db.update(
      'dettes',
      {
        'montant_paye': montantPaye,
        'statut': statut,
        'is_synced': 0, // Marqué pour que SyncService le pousse sur Supabase
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertPaiementDette(PaiementDette p) async {
    final db = await database;
    return await db.insert('paiements_dette', p.toMap());
  }

  Future<double> getTotalPaiementsDette(int detteId) async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT SUM(montant) as total FROM paiements_dette WHERE dette_id = ?',
      [detteId],
    );

    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getUnsyncedPaiements() async {
    final db = await database;

    return await db.query(
      'paiements_dette',
      where: 'is_synced = 0',
    );
  }

  Future<void> markPaiementAsSynced(int id, String supabaseId) async {
    final db = await database;

    await db.update(
      'paiements_dette',
      {
        'is_synced': 1,
        'supabase_id': supabaseId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
// --------------------- INVENTAIRES QUOTIDIENS -------

  Future<int> insertInventaireQuotidien(InventaireQuotidien i) async {
    final db = await database;

    return await db.insert('inventaires_quotidiens', {
      'owner_id': i.ownerId,
      'produit_id': i.produitId,
      'quantite_theorique': i.quantiteTheorique,
      'quantite_physique': i.quantitePhysique,
      'date_cloture': i.dateCloture,
      'is_synced': i.isSynced,
      'supabase_id': i.supabaseId,
    });
  }

  Future<List<InventaireQuotidien>> getInventairesQuotidiens({required String ownerId}) async {
    final db = await database;

    final maps = await db.query(
      'inventaires_quotidiens',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'date_cloture DESC',
    );

    return maps.map((e) => InventaireQuotidien.fromMap(e)).toList();
  }

  Future<InventaireQuotidien?> getInventaireQuotidienById(int id) async {
    final db = await database;

    final result = await db.query(
      'inventaires_quotidiens',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isEmpty) return null;
    return InventaireQuotidien.fromMap(result.first);
  }

  Future<List<InventaireQuotidien>> getUnsyncedInventairesQuotidiens({required String ownerId}) async {
    final db = await database;

    final maps = await db.query(
      'inventaires_quotidiens',
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
      orderBy: 'date_cloture ASC',
    );

    return maps.map((e) => InventaireQuotidien.fromMap(e)).toList();
  }

  Future<int> markInventaireQuotidienAsSynced(int localId, String supabaseId) async {
    final db = await database;

    return await db.update(
      'inventaires_quotidiens',
      {
        'is_synced': 1,
        'supabase_id': supabaseId,
      },
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<int> deleteInventaireQuotidienById(int id) async {
    final db = await database;
    return await db.delete(
      'inventaires_quotidiens',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteInventaireQuotidienBySupabaseId(String supabaseId) async {
    final db = await database;

    return await db.delete(
      'inventaires_quotidiens',
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
    );
  }

  Future<int> upsertInventaireQuotidienFromSupabase(InventaireQuotidien i) async {
    final db = await database;

    if (i.supabaseId == null || i.supabaseId!.isEmpty) return 0;

    final data = i.toMap()..['is_synced'] = 1;

    final existing = await db.query(
      'inventaires_quotidiens',
      where: 'supabase_id = ?',
      whereArgs: [i.supabaseId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final localId = existing.first['id'] as int;
      data.remove('id');

      return await db.update(
        'inventaires_quotidiens',
        data,
        where: 'id = ?',
        whereArgs: [localId],
      );
    } else {
      data.remove('id');
      return await db.insert('inventaires_quotidiens', data);
    }
  }

// --------------------- AJUSTEMENT STOCK ---------------------

  Future<void> applyStockAdjustment({
    required int produitId,
    required double diff,
  }) async {
    final db = await database;

    await db.rawUpdate('''
    UPDATE produits
    SET quantite = quantite + ?,
        is_synced = 0,
        updated_at = ?
    WHERE id = ?
  ''', [
      diff,
      DateTime.now().toIso8601String(),
      produitId,
    ]);
  }

// --------------------- PRODUITS ---------------------

  /// Insert or update product (saveProduit).
  /// If p.id == null -> insert (returns new local id)
  /// else -> update (returns rows affected)
  Future<int> saveProduit(Produit p) async {
    final db = await database;
    final map = p.toMap();

    if (map['created_at'] == null || (map['created_at'] as String).isEmpty) {
      map['created_at'] = DateTime.now().toIso8601String();
    }

    // Toute modification locale = non synchronisée
    map['is_synced'] = 0;
    map['updated_at'] = DateTime.now().toIso8601String();

    final int? existingLocalId = p.id;
    map.remove('id');

    if (existingLocalId != null) {
      return await db.update(
        'produits',
        map,
        where: 'id = ?',
        whereArgs: [existingLocalId],
      );
    } else {
      return await db.insert('produits', map);
    }
  }

  /// Mise à jour du stock (approvisionnement): ajoute quantiteAjoutee (double)
  Future<int> updateStock(int produitId, double quantiteAjoutee) async {
    final db = await database;

    final prod = await db.query(
      'produits',
      where: 'id = ?',
      whereArgs: [produitId],
      limit: 1,
    );

    if (prod.isEmpty) {
      throw Exception('Produit ID $produitId introuvable pour la mise à jour de stock.');
    }

    final currentQty = (prod.first['quantite'] as num?)?.toDouble() ?? 0.0;
    final newQty = currentQty + quantiteAjoutee;
    final now = DateTime.now().toIso8601String();

    return await db.update(
      'produits',
      {
        'quantite': newQty,
        'updated_at': now,
        'is_synced': 0,
      },
      where: 'id = ?',
      whereArgs: [produitId],
    );
  }

  /// Récupère un produit par son ID local (INTEGER)
  Future<Produit?> getProduitById(int id) async {
    final db = await database;
    final maps = await db.query(
      'produits',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Produit.fromMap(maps.first);
  }

  /// Récupère la liste des produits, optionnellement filtrée par ownerId (UUID string)
  Future<List<Produit>> getProduits({String? ownerId}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = (ownerId == null)
        ? await db.query('produits', orderBy: 'nom COLLATE NOCASE ASC')
        : await db.query(
      'produits',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'nom COLLATE NOCASE ASC',
    );

    return maps.map((m) => Produit.fromMap(m)).toList();
  }

  /// Compte le nombre de produits pour un owner
  Future<int> getProduitsCountForUser(String ownerId) async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as c FROM produits WHERE owner_id = ?',
      [ownerId],
    );
    if (res.isEmpty) return 0;
    return (res.first['c'] as int?) ?? 0;
  }

  /// Compte les produits en faible stock (threshold)
  Future<int> countLowStockProducts({
    required String ownerId,
    required int threshold,
  }) async {
    final db = await database;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as c FROM produits WHERE owner_id = ? AND quantite <= ?',
      [ownerId, threshold],
    );
    if (res.isEmpty) return 0;
    return (res.first['c'] as int?) ?? 0;
  }

  /// Récupère produits non synchronisés d'un owner
  Future<List<Produit>> getUnsyncedProduits({required String ownerId}) async {
    final db = await database;
    final maps = await db.query(
      'produits',
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
      orderBy: 'created_at ASC',
    );
    return maps.map((m) => Produit.fromMap(m)).toList();
  }

  /// Upsert produit provenant de Supabase (match via supabase_id).
  /// Marque la ligne comme synchronisée (is_synced = 1).
  Future<int> upsertProduitFromSupabase(Produit p) async {
    final db = await database;
    if (p.supabaseId == null) return 0;

    final data = p.toMap()..['is_synced'] = 1;

    final existing = await db.query(
      'produits',
      where: 'supabase_id = ?',
      whereArgs: [p.supabaseId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final local = existing.first;
      final localUpdatedAtStr = local['updated_at'] as String?;
      final remoteUpdatedAtStr = p.updatedAt;

      if (localUpdatedAtStr != null && remoteUpdatedAtStr != null) {
        final localDate = DateTime.tryParse(localUpdatedAtStr);
        final remoteDate = DateTime.tryParse(remoteUpdatedAtStr);

        if (localDate != null && remoteDate != null) {
          // 🔥 CORRECTION ICI :
          // Si la date locale est PLUS RÉCENTE ou ÉGALE à la date du serveur,
          // on ignore la mise à jour du serveur.
          // On enlève la condition "local['is_synced'] == 0" pour ce check.
          if (localDate.isAfter(remoteDate) || localDate.isAtSameMomentAs(remoteDate)) {
            debugPrint("DBHelper: ⛔ Donnée serveur ignorée (Date locale plus récente ou identique)");
            return 0;
          }
        }
      }

      final id = local['id'] as int;
      data.remove('id');

      return await db.update(
        'produits',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      data.remove('id');
      return await db.insert('produits', data);
    }
  }

  /// Marque un produit local comme synchronisé et assigne son supabase_id
  Future<int> markProduitAsSynced(int localId, String supabaseId) async {
    final db = await database;
    return await db.update(
      'produits',
      {'is_synced': 1, 'supabase_id': supabaseId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  /// Supprime un produit local par id
  Future<int> deleteProduit(int id) async {
    final db = await database;
    return await db.delete('produits', where: 'id = ?', whereArgs: [id]);
  }

  // ===========================================================================
  // 🧾 V14 — FORMATS DE VENTE (CONDITIONNEMENTS) EN LOCAL
  // ===========================================================================
  //
  //  La caisse doit savoir, SANS RÉSEAU, qu'un article se vend à l'unité mais
  //  aussi en farde de 12 ou en carton de 24 — et à quel prix. Ces méthodes
  //  recopient les `conditionnements` du serveur dans la base du téléphone.
  //
  //  ⚠️ La clé est l'identifiant SERVEUR du produit (`supabase_id`) : c'est
  //  celui qu'utilisent le panier et la vente, jamais le numéro local.

  /// Remplace les formats d'un article par ceux qui viennent du serveur.
  ///
  /// On supprime puis on réinsère : un emballage retiré côté serveur doit
  /// disparaître du téléphone (sinon la caisse proposerait un format qui
  /// n'existe plus et la vente serait refusée).
  Future<void> remplacerConditionnementsProduit({
    required String produitSupabaseId,
    String? ownerId,
    required List<Conditionnement> formats,
  }) async {
    final db = await database;
    final String produit = produitSupabaseId.trim();
    if (produit.isEmpty) return;

    await db.delete(
      'conditionnements',
      where: 'produit_supabase_id = ?',
      whereArgs: <Object?>[produit],
    );

    if (formats.isEmpty) return;

    final Batch lot = db.batch();
    for (final Conditionnement c in formats) {
      lot.insert(
        'conditionnements',
        <String, Object?>{
          'id': c.id,
          'produit_supabase_id': produit,
          'owner_id': ownerId,
          'libelle': c.libelle,
          'quantite_unites_base': c.quantiteUnitesBase,
          'prix_vente': c.prixVente,
          'qr_code_id': c.qrCodeId,
          'code_barre_texte': c.codeBarreTexte,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await lot.commit(noResult: true);
  }

  /// Tous les formats de la boutique, groupés par identifiant SERVEUR de
  /// produit (`'123'` → liste des emballages).
  Future<Map<String, List<Conditionnement>>> getConditionnementsParProduit({
    String? ownerId,
  }) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = (ownerId == null)
        ? await db.query('conditionnements')
        : await db.query(
            'conditionnements',
            where: 'owner_id = ?',
            whereArgs: <Object?>[ownerId],
          );

    final Map<String, List<Conditionnement>> resultat =
        <String, List<Conditionnement>>{};
    for (final Map<String, dynamic> m in maps) {
      final String produit = '${m['produit_supabase_id'] ?? ''}';
      if (produit.isEmpty) continue;
      final Conditionnement format = Conditionnement(
        id: '${m['id']}',
        produitId: int.tryParse(produit) ?? 0,
        libelle: '${m['libelle'] ?? ''}',
        quantiteUnitesBase:
            (m['quantite_unites_base'] as num?)?.toDouble() ?? 1,
        prixVente: (m['prix_vente'] as num?)?.toDouble() ?? 0,
        qrCodeId: '${m['qr_code_id'] ?? ''}',
        codeBarreTexte:
            (m['code_barre_texte'] as String?)?.trim().isEmpty ?? true
                ? null
                : m['code_barre_texte'] as String,
      );
      resultat.putIfAbsent(produit, () => <Conditionnement>[]).add(format);
    }

    // Ordre lisible : du plus petit au plus grand emballage.
    for (final List<Conditionnement> liste in resultat.values) {
      liste.sort((Conditionnement a, Conditionnement b) =>
          a.quantiteUnitesBase.compareTo(b.quantiteUnitesBase));
    }
    return resultat;
  }

  /// Formats d'UN article (identifiant serveur).
  Future<List<Conditionnement>> getConditionnementsProduit(
    String produitSupabaseId,
  ) async {
    final Map<String, List<Conditionnement>> tous =
        await getConditionnementsParProduit();
    return tous[produitSupabaseId.trim()] ?? const <Conditionnement>[];
  }

  /// Supprime un produit local par supabase_id
  Future<int> deleteProduitBySupabaseId(String supabaseId) async {
    final db = await database;
    return await db.delete(
      'produits',
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
    );
  }

  /// Met à jour la photo d'un produit (et marque non synchronisé)
  Future<int> updateProduitPhoto(int produitId, String path) async {
    final db = await database;
    return await db.update(
      'produits',
      {'photo': path, 'is_synced': 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [produitId],
    );
  }

  Future<Produit?> getProduitBySupabaseId(String supabaseId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'produits',
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Produit.fromMap(maps.first);
  }

  /// 🧾 MODULE 8 — applique localement une sortie de stock décidée par le
  /// serveur (vente encaissée en ligne via `rpc_vente_valider`).
  ///
  /// Le stock de référence est décrémenté par le trigger du serveur ; cette
  /// méthode ne fait qu'aligner la copie locale pour que la caisse classique
  /// affiche immédiatement le bon stock, sans attendre la synchronisation.
  /// `is_synced` n'est PAS touché : le serveur reste maître de la quantité.
  Future<void> appliquerSortieStockParSupabaseId(
    String supabaseId,
    double quantiteBase,
  ) async {
    if (supabaseId.isEmpty || quantiteBase <= 0) return;

    final Produit? produit = await getProduitBySupabaseId(supabaseId);
    if (produit == null || produit.id == null) return;

    final db = await database;
    final double nouvelle = produit.quantite - quantiteBase;
    await db.update(
      'produits',
      {
        'quantite': nouvelle > 0 ? nouvelle : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [produit.id],
    );
  }

  Future<void> updateProduitQuantity({
    required Produit product,
    required double newQuantity,
    required double purchasePrice,
    required String ownerId,
  }) async {
    final db = await database;

    await db.update(
      'produits',
      {
        'quantite': newQuantity,
        'prix_achat': purchasePrice,
        'is_synced': 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ? AND owner_id = ?',
      whereArgs: [product.id, ownerId],
    );
  }

  Future<int> upsertAjustementFromSupabase(Ajustement a) async {
    final db = await database;

    if (a.supabaseId == null) return 0;

    final data = a.toMap()..['is_synced'] = 1;

    final existing = await db.query(
      'ajustements',
      where: 'supabase_id = ?',
      whereArgs: [a.supabaseId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final id = existing.first['id'] as int;

      data.remove('id');

      return await db.update(
        'ajustements',
        data,
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      data.remove('id');
      return await db.insert('ajustements', data);
    }
  }

  Future<int> insertAjustement({
    required int produitId,
    required double quantite, // C'est le delta (ex: -2.0)
    required String raison,
  }) async {
    final db = await database;

    // Utilisation d'une précision à la milliseconde pour garantir la comparaison
    final now = DateTime.now().toIso8601String();

    final produit = await getProduitById(produitId);
    if (produit == null) {
      throw Exception('Produit introuvable pour l\'ajustement');
    }

    return await db.transaction((txn) async {
      // 1. Enregistrement du mouvement dans l'historique (Table ajustements)
      // On stocke le delta tel quel pour la synchronisation
      await txn.insert('ajustements', {
        'produit_id': produitId,
        'quantite': quantite,
        'raison': raison,
        'date': now,
        'owner_id': produit.ownerId,
        'is_synced': 0, // Sera synchronisé par le SyncService
      });

      // 2. Calcul du nouveau stock réel pour l'affichage local
      final double nouveauStock = produit.quantite + quantite;

      // 3. Mise à jour de la table 'produits'
      // C'est ici que l'on définit la "nouvelle vérité" locale
      return await txn.update(
        'produits',
        {
          'quantite': nouveauStock,
          'updated_at': now, // 🛡️ CRITIQUE : Permet au DBHelper de rejeter les vieux stocks du serveur
          'is_synced': 0,    // Indique qu'une synchro vers Supabase est nécessaire
        },
        where: 'id = ?',
        whereArgs: [produitId],
      );
    });
  }

  Future<List<Ajustement>> getUnsyncedAjustements({
    required String ownerId,
  }) async {
    final db = await database;

    final maps = await db.query(
      'ajustements',
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
      orderBy: 'date ASC',
    );

    return maps.map((e) => Ajustement.fromMap(e)).toList();
  }

  Future<void> markAjustementAsSynced(int id, String supabaseId) async {
    final db = await database;

    await db.update(
      'ajustements',
      {
        'is_synced': 1,
        'supabase_id': supabaseId,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> deleteAjustementBySupabaseId(String supabaseId) async {
    final db = await database;

    return await db.delete(
      'ajustements',
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
    );
  }
// --------------------- VENTES ---------------------

  String _toUtcIso(DateTime d) => d.toUtc().toIso8601String();

  DateTime _startOfDayLocal(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime _endExclusiveOfDayLocal(DateTime d) =>
      DateTime(d.year, d.month, d.day).add(const Duration(days: 1));

  /// Compte les ventes du jour pour un owner
  Future<int> getVentesCountForUserToday(String userId) async {
    final db = await database;
    final utilisateur = await getUtilisateurById(userId);
    final isCollaborator = utilisateur?.parentId != null;

    final String column = isCollaborator ? 'seller_id' : 'owner_id';

    final start = _toUtcIso(_startOfDayLocal(DateTime.now()));
    final end = _toUtcIso(_endExclusiveOfDayLocal(DateTime.now()));

    final List<Map<String, dynamic>> result = await db.rawQuery('''
    SELECT COUNT(*) as c
    FROM ventes
    WHERE $column = ?
      AND datetime(date) >= datetime(?)
      AND datetime(date) < datetime(?)
  ''', [userId, start, end]);

    return (result.first['c'] as int?) ?? 0;
  }

  /// Montant total historique
  Future<double> getTotalVentesAmountForUser(String userId) async {
    final db = await database;
    final utilisateur = await getUtilisateurById(userId);
    final isCollaborator = utilisateur?.parentId != null;

    final String column = isCollaborator ? 'seller_id' : 'owner_id';

    final List<Map<String, dynamic>> result = await db.rawQuery('''
    SELECT SUM(prix) as s
    FROM ventes
    WHERE $column = ?
  ''', [userId]);

    final val = result.first['s'];
    return (val == null) ? 0.0 : (val as num).toDouble();
  }

  /// Montant total aujourd'hui
  Future<double> getTotalVentesAmountForUserToday(String userId) async {
    final db = await database;
    final utilisateur = await getUtilisateurById(userId);
    final isCollaborator = utilisateur?.parentId != null;

    final String column = isCollaborator ? 'seller_id' : 'owner_id';

    final start = _toUtcIso(_startOfDayLocal(DateTime.now()));
    final end = _toUtcIso(_endExclusiveOfDayLocal(DateTime.now()));

    final List<Map<String, dynamic>> result = await db.rawQuery('''
    SELECT SUM(prix) as s
    FROM ventes
    WHERE $column = ?
      AND datetime(date) >= datetime(?)
      AND datetime(date) < datetime(?)
  ''', [userId, start, end]);

    final val = result.first['s'];
    return (val == null) ? 0.0 : (val as num).toDouble();
  }

  /// Insère une vente unique et met à jour le stock local
  Future<int> insertVenteWithStockUpdate(Vente v) async {
    if (v.sellerId == null || v.sellerId!.isEmpty) {
      throw Exception("La vente doit avoir un sellerId");
    }

    final db = await database;
    return await db.transaction((txn) async {
      final prod = await txn.query(
        'produits',
        columns: ['quantite'],
        where: 'id = ?',
        whereArgs: [v.produitId],
        limit: 1,
      );
      if (prod.isEmpty) throw Exception('Produit introuvable');

      final currentQty = (prod.first['quantite'] as num?)?.toDouble() ?? 0.0;
      if (currentQty < v.quantite) throw Exception('Stock insuffisant');

      final Map<String, dynamic> venteMap = v.toMap();
      venteMap['is_synced'] = 0;
      venteMap['mode_paiement'] = v.modePaiement.isEmpty ? 'cash' : v.modePaiement;

      final id = await txn.insert('ventes', venteMap);

      await txn.update(
        'produits',
        {'quantite': currentQty - v.quantite},
        where: 'id = ?',
        whereArgs: [v.produitId],
      );

      return id;
    });
  }

  /// Insère plusieurs ventes (Panier) et met à jour le stock local
  Future<int> insertMultipleVentesWithStockUpdate(List<Vente> ventes) async {
    if (ventes.isEmpty) return 0;
    final db = await database;

    return await db.transaction((txn) async {
      int firstSaleId = 0;

      for (final vente in ventes) {
        if (vente.sellerId == null || vente.sellerId!.isEmpty) {
          throw Exception("Chaque vente doit avoir un sellerId");
        }

        final List<Map<String, dynamic>> prod = await txn.query(
          'produits',
          columns: ['quantite', 'nom', 'stock_illimite'],
          where: 'id = ?',
          whereArgs: [vente.produitId],
          limit: 1,
        );

        if (prod.isEmpty) throw Exception('Produit ID ${vente.produitId} introuvable');

        // ♾️ MODULE 31 — un article vendu SANS suivi de stock n'est jamais
        //  bloqué et son stock n'est pas décrémenté : il ne peut pas être
        //  compté (eau au robinet, service, fabrication à la demande…).
        final bool sansStock =
            (prod.first['stock_illimite'] as num?)?.toInt() == 1;

        final currentQty = (prod.first['quantite'] as num?)?.toDouble() ?? 0.0;
        if (!sansStock && currentQty < vente.quantite) {
          throw Exception('Stock insuffisant pour ${prod.first['nom']}');
        }

        final Map<String, dynamic> venteMap = vente.toMap();
        venteMap['is_synced'] = 0;
        if (venteMap['mode_paiement'] == null || venteMap['mode_paiement'].isEmpty) {
          venteMap['mode_paiement'] = 'cash';
        }

        final int newVenteId = await txn.insert(
          'ventes',
          venteMap,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        if (firstSaleId == 0) firstSaleId = newVenteId;

        if (!sansStock) {
          await txn.update(
            'produits',
            {'quantite': currentQty - vente.quantite},
            where: 'id = ?',
            whereArgs: [vente.produitId],
          );
        }
      }

      return firstSaleId;
    });
  }

  Future<List<Vente>> getVentes({String? ownerId}) async {
    final db = await database;
    final maps = (ownerId == null)
        ? await db.query('ventes', orderBy: 'date DESC')
        : await db.query(
      'ventes',
      where: 'owner_id = ?',
      whereArgs: [ownerId],
      orderBy: 'date DESC',
    );

    return maps.map((m) => Vente.fromMap(m)).toList();
  }

  Future<List<Vente>> getUnsyncedVentes({required String ownerId}) async {
    final db = await database;
    final maps = await db.query(
      'ventes',
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
      orderBy: 'date ASC',
    );
    return maps.map((m) => Vente.fromMap(m)).toList();
  }

  Future<int> upsertVenteFromSupabase(Vente v) async {
    final db = await database;
    final map = v.toMap()..['is_synced'] = 1;

    if (v.supabaseId == null) throw Exception("Besoin de supabaseId");

    int? localProduitId;
    try {
      localProduitId = (v.produitId is int)
          ? v.produitId as int
          : int.tryParse(v.produitId.toString());
    } catch (_) {
      localProduitId = null;
    }

    if (localProduitId == null) {
      final List<Map<String, dynamic>> found = await db.query(
        'produits',
        columns: ['id'],
        where: 'supabase_id = ?',
        whereArgs: [v.produitId?.toString()],
        limit: 1,
      );
      if (found.isNotEmpty) {
        localProduitId = found.first['id'] as int?;
      }
    }

    if (localProduitId != null) {
      map['produit_id'] = localProduitId;
    }

    final existing = await db.query(
      'ventes',
      where: 'supabase_id = ?',
      whereArgs: [v.supabaseId],
      limit: 1,
    );

    if (existing.isNotEmpty) {
      final localId = existing.first['id'] as int;
      map.remove('id');
      return await db.update('ventes', map, where: 'id = ?', whereArgs: [localId]);
    } else {
      map.remove('id');
      return await db.insert('ventes', map);
    }
  }

  // =======================================================================
  // 🔌 100 % HORS LIGNE — CACHE DE LECTURE
  // -----------------------------------------------------------------------
  // Chaque écran qui lit une RPC met sa dernière réponse connue ici. Hors
  // ligne (ou si le serveur met trop de temps), on relit cette valeur : le
  // patron voit ses chiffres au lieu d'un écran vide.
  // =======================================================================

  /// Dernière valeur connue de [cle], ou `null`.
  Future<String?> cacheLire(String cle) async {
    try {
      final db = await database;
      final List<Map<String, Object?>> lignes = await db.query(
        'cache_lecture',
        columns: <String>['valeur'],
        where: 'cle = ?',
        whereArgs: <Object?>[cle],
        limit: 1,
      );
      if (lignes.isEmpty) return null;
      return lignes.first['valeur'] as String?;
    } catch (e) {
      debugPrint('cacheLire($cle) ignoré : $e');
      return null;
    }
  }

  /// Enregistre (ou remplace) la valeur de [cle].
  Future<void> cacheEcrire(String cle, String valeur) async {
    try {
      final db = await database;
      await db.insert(
        'cache_lecture',
        <String, Object?>{
          'cle': cle,
          'valeur': valeur,
          'maj_le': DateTime.now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('cacheEcrire($cle) ignoré : $e');
    }
  }

  /// Date de la dernière mise à jour de [cle] (pour prévenir l'utilisateur).
  Future<DateTime?> cacheMiseAJour(String cle) async {
    try {
      final db = await database;
      final List<Map<String, Object?>> lignes = await db.query(
        'cache_lecture',
        columns: <String>['maj_le'],
        where: 'cle = ?',
        whereArgs: <Object?>[cle],
        limit: 1,
      );
      if (lignes.isEmpty) return null;
      return DateTime.tryParse('${lignes.first['maj_le']}')?.toLocal();
    } catch (_) {
      return null;
    }
  }

  Future<void> cachePurger(String cle) async {
    try {
      final db = await database;
      await db.delete('cache_lecture', where: 'cle = ?', whereArgs: <Object?>[cle]);
    } catch (_) {}
  }

  /// Vide le cache (déconnexion, changement d'entreprise…).
  Future<void> cacheVider() async {
    try {
      final db = await database;
      await db.delete('cache_lecture');
    } catch (_) {}
  }

  /// Nombre d'entrées en cache (diagnostic).
  Future<int> cacheCompter() async {
    try {
      final db = await database;
      final List<Map<String, Object?>> l =
          await db.rawQuery('SELECT COUNT(*) AS n FROM cache_lecture');
      return (l.first['n'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // =======================================================================
  // 🔌 100 % HORS LIGNE — CONFLITS DE VENTE
  // -----------------------------------------------------------------------
  // `is_synced` : 0 = en file, 1 = synchronisée, -1 = CONFLIT à trancher.
  // Une vente en conflit n'est jamais supprimée : elle attend une décision.
  // =======================================================================

  /// Enregistre un échec de synchronisation pour la vente [localId].
  ///
  /// Au-delà de [maxTentatives], la vente passe en **conflit**
  /// (`is_synced = -1`) : elle sort de la file automatique pour ne pas
  /// boucler indéfiniment, mais reste visible et rejouable à la main.
  /// Renvoie `true` si la vente est désormais en conflit.
  Future<bool> marquerVenteEnEchec(
    int localId,
    String motif, {
    int maxTentatives = 5,
  }) async {
    try {
      final db = await database;
      final List<Map<String, Object?>> lignes = await db.query(
        'ventes',
        columns: <String>['tentatives', 'is_synced'],
        where: 'id = ?',
        whereArgs: <Object?>[localId],
        limit: 1,
      );
      if (lignes.isEmpty) return false;
      if ((lignes.first['is_synced'] as num?)?.toInt() == 1) return false;

      final int faites = (lignes.first['tentatives'] as num?)?.toInt() ?? 0;
      final int total = faites + 1;
      final bool conflit = total >= maxTentatives;

      await db.update(
        'ventes',
        <String, Object?>{
          'tentatives': total,
          'sync_erreur': motif.length > 500 ? motif.substring(0, 500) : motif,
          if (conflit) 'is_synced': -1,
        },
        where: 'id = ?',
        whereArgs: <Object?>[localId],
      );
      return conflit;
    } catch (e) {
      debugPrint('marquerVenteEnEchec($localId) ignoré : $e');
      return false;
    }
  }

  /// Ventes en conflit (à trancher par l'utilisateur).
  Future<List<Map<String, Object?>>> getVentesEnConflit({
    required String ownerId,
  }) async {
    try {
      final db = await database;
      return await db.query(
        'ventes',
        where: 'owner_id = ? AND is_synced = -1',
        whereArgs: <Object?>[ownerId],
        orderBy: 'date ASC',
      );
    } catch (e) {
      debugPrint('getVentesEnConflit ignoré : $e');
      return const <Map<String, Object?>>[];
    }
  }

  /// Combien de ventes attendent une décision ?
  Future<int> compterVentesEnConflit({required String ownerId}) async {
    try {
      final db = await database;
      final List<Map<String, Object?>> l = await db.rawQuery(
        'SELECT COUNT(*) AS n FROM ventes WHERE owner_id = ? AND is_synced = -1',
        <Object?>[ownerId],
      );
      return (l.first['n'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Remet une vente en conflit dans la file (l'utilisateur a corrigé le
  /// stock, ou décide de réessayer). Le compteur repart de zéro.
  Future<void> remettreVenteEnFile(int localId) async {
    try {
      final db = await database;
      await db.update(
        'ventes',
        <String, Object?>{'is_synced': 0, 'tentatives': 0},
        where: 'id = ?',
        whereArgs: <Object?>[localId],
      );
    } catch (e) {
      debugPrint('remettreVenteEnFile($localId) ignoré : $e');
    }
  }

  Future<int> markVenteAsSynced(int localId, String supabaseId) async {
    final db = await database;
    return await db.update(
      'ventes',
      {'is_synced': 1, 'supabase_id': supabaseId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  Future<int> deleteVenteBySupabaseId(String supabaseId) async {
    final db = await database;
    return await db.delete('ventes', where: 'supabase_id = ?', whereArgs: [supabaseId]);
  }

  /// Récupère les stats pour tous les collaborateurs d'un owner
  Future<List<CollaborateurStats>> getStatsByCollaborateur(String ownerId) async {
    final db = await database;

    final List<Map<String, dynamic>> result = await db.rawQuery('''
    SELECT seller_id, COUNT(*) AS ventes_count, SUM(prix) AS total_amount
    FROM ventes
    WHERE owner_id = ?
    GROUP BY seller_id
    ORDER BY total_amount DESC
  ''', [ownerId]);

    return result.map((row) => CollaborateurStats(
      sellerId: row['seller_id'] as String,
      ventesCount: (row['ventes_count'] as int?) ?? 0,
      totalAmount: (row['total_amount'] as num?)?.toDouble() ?? 0.0,
    )).toList();
  }

  /// Récupère les stats pour un collaborateur précis
  Future<CollaborateurStats?> getStatsForSeller(String ownerId, String sellerId) async {
    final db = await database;

    final List<Map<String, dynamic>> result = await db.rawQuery('''
    SELECT seller_id, COUNT(*) AS ventes_count, SUM(prix) AS total_amount
    FROM ventes
    WHERE owner_id = ? AND seller_id = ?
    GROUP BY seller_id
  ''', [ownerId, sellerId]);

    if (result.isEmpty) return null;

    final row = result.first;
    return CollaborateurStats(
      sellerId: row['seller_id'] as String,
      ventesCount: (row['ventes_count'] as int?) ?? 0,
      totalAmount: (row['total_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Stats pour un collaborateur entre deux dates
  Future<CollaborateurStats?> getStatsForSellerPeriod(
      String ownerId, String sellerId, DateTime start, DateTime end) async {

    final db = await database;

    final String startDate = start.toIso8601String().substring(0, 10);
    final String endDate = end.toIso8601String().substring(0, 10);

    final List<Map<String, dynamic>> result = await db.rawQuery('''
    SELECT COUNT(*) AS ventes_count, SUM(prix) AS total_amount
    FROM ventes
    WHERE owner_id = ? 
      AND seller_id = ? 
      AND date(date) >= ?
      AND date(date) < ?
  ''', [ownerId, sellerId, startDate, endDate]);

    if (result.isEmpty) return null;

    final row = result.first;

    return CollaborateurStats(
      sellerId: sellerId,
      ventesCount: (row['ventes_count'] as int?) ?? 0,
      totalAmount: (row['total_amount'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Future<Vente?> getVenteById(int id) async {
    final db = await database;

    final result = await db.query(
      'ventes',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return Vente.fromMap(result.first);
    }

    return null;
  }

  Future<List<VenteDetail>> getDetailedSalesForSellerPeriod(
      String ownerId,
      String sellerId,
      DateTime start,
      DateTime end,
      ) async {
    final db = await database;

    final startIso = start.toUtc().toIso8601String();
    final endIso = end.toUtc().toIso8601String();

    final List<Map<String, dynamic>> res = await db.rawQuery('''
    SELECT
      p.nom as produit_nom,
      v.quantite,
      v.date as date_vente,
      v.prix as prix_total
    FROM ventes v
    LEFT JOIN produits p
      ON (p.id = v.produit_id OR p.supabase_id = v.produit_id)
    WHERE v.owner_id = ?
      AND v.seller_id = ?
      AND datetime(v.date) >= datetime(?)
      AND datetime(v.date) < datetime(?)
    ORDER BY v.date DESC
  ''', [ownerId, sellerId, startIso, endIso]);

    return res.map((map) => VenteDetail(
      produitNom: map['produit_nom']?.toString() ?? 'Inconnu',
      quantite: (map['quantite'] as num?)?.toDouble() ?? 0.0,
      dateVente: DateTime.tryParse(map['date_vente']?.toString() ?? '') ?? DateTime.now(),
      prixTotal: (map['prix_total'] as num?)?.toDouble() ?? 0.0,
    )).toList();
  }
  // ========================= CLIENTS =========================

  Future<int> insertClient(Client c) async {
    final db = await database;
    final map = c.toMap();
    // 🔑 Ajouté: Marquer le nouveau client comme non synchronisé
    map['is_synced'] = 0;
    // La fonction 'saveClient' serait préférable ici pour gérer update/insert.
    return await db.insert('clients', map);
  }

  // ✅ NOUVEAU: Récupère un client par son ID local
  Future<Client?> getClientById(int id) async {
    final db = await database;
    final maps = await db.query(
      'clients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (maps.isNotEmpty) {
      return Client.fromMap(maps.first);
    }
    return null;
  }

  Future<List<Client>> getClients({String? ownerId}) async {
    final db = await database;
    final maps = (ownerId == null)
        ? await db.query('clients', orderBy: 'nom ASC')
        : await db.query('clients', where: 'owner_id = ?', whereArgs: [ownerId], orderBy: 'nom ASC');
    return maps.map((m) => Client.fromMap(m)).toList();
  }

// 🔑 Ajouté: Pour la synchronisation: obtenir tous les clients non synchronisés
  Future<List<Client>> getUnsyncedClients({required String ownerId}) async {
    final db = await database;
    final maps = await db.query(
      'clients',
      where: 'owner_id = ? AND is_synced = 0',
      whereArgs: [ownerId],
      orderBy: 'nom ASC',
    );
    return maps.map((m) => Client.fromMap(m)).toList();
  }

// ✅ NOUVEAU: Insère ou met à jour un client provenant de Supabase (Upsert)
  /// Utilisé pour la synchronisation descendante (Cloud -> Local).
  Future<int> upsertClientFromSupabase(Client c) async {
    final db = await database;
    final map = c.toMap();

    // S'assurer que le client est marqué comme SYNC (1) car il vient du serveur
    map['is_synced'] = 1;
    if (c.supabaseId == null) {
      throw Exception("Le client Supabase doit avoir un 'supabaseId' pour l'upsert.");
    }

    // 1. Vérifier si le client existe déjà localement via son supabase_id
    final existing = await db.query(
        'clients',
        where: 'supabase_id = ?',
        whereArgs: [c.supabaseId],
        limit: 1
    );

    if (existing.isNotEmpty) {
      // 2. Si la ligne existe localement -> MISE À JOUR (on utilise l'ID local existant)
      final localId = existing.first['id'] as int;
      // On retire l'ID local de la map pour l'update
      map.remove('id');
      return await db.update('clients', map, where: 'id = ?', whereArgs: [localId]);
    } else {
      // 3. Si c'est un nouvel enregistrement du serveur -> INSERTION
      // On retire l'ID local de la map pour laisser SQLite l'auto-incrémenter
      map.remove('id');
      return await db.insert('clients', map);
    }
  }

// 🔑 Ajouté: Pour la synchronisation: marquer comme synchronisé
  Future<int> markClientAsSynced(int localId, String supabaseId) async {
    final db = await database;
    return await db.update(
      'clients',
      {'is_synced': 1, 'supabase_id': supabaseId},
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  // 🚀 NOUVEAU: Remplace insertClient et updateClient par une fonction unique (recommandé)
  Future<int> updateClient(Client c) async {
    final db = await database;
    // 🔑 Ajouté: Mettre à jour is_synced à 0 en cas de modification
    final map = c.toMap();
    map['is_synced'] = 0;
    return await db.update('clients', map, where: 'id = ?', whereArgs: [c.id]);
  }

  Future<int> deleteClient(int id) async {
    final db = await database;
    // La suppression locale doit être gérée lors de la synchro (soft delete ou envoi de commande DELETE)
    return await db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  // ✅ NOUVEAU: Suppression par ID Supabase (pour la gestion Realtime DELETE dans SyncService)
  Future<int> deleteClientBySupabaseId(String supabaseId) async {
    final db = await database;
    return await db.delete('clients', where: 'supabase_id = ?', whereArgs: [supabaseId]);
  }

  Future<Client?> getClientBySupabaseId(String supabaseId) async {
    final db = await database;

    final maps = await db.query(
      'clients',
      where: 'supabase_id = ?',
      whereArgs: [supabaseId],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Client.fromMap(maps.first);
  }
  // ========================= UTILISATEURS =========================

  /// Insère ou met à jour un utilisateur.
  /// Utilise ConflictAlgorithm.replace pour que les infos synchronisées écrasent les locales.
  Future<int> insertUtilisateur(Utilisateur u, {String? password}) async {
    if (u.id == null || u.id!.isEmpty) {
      throw Exception("L'ID de l'utilisateur (UUID Supabase) est requis.");
    }

    final db = await database;
    final data = u.toMap();

    // Si mot de passe fourni, on le hash
    if (password != null && password.isNotEmpty) {
      final bytes = utf8.encode(password);
      final hash = sha256.convert(bytes).toString();
      data['password_hash'] = hash;
    }

    return await db.insert(
      'utilisateurs',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Récupère un utilisateur par email
  Future<Utilisateur?> getUtilisateurByEmail(String email) async {
    final db = await database;
    final maps = await db.query(
      'utilisateurs',
      where: 'email = ?',
      whereArgs: [email.toLowerCase().trim()],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Utilisateur.fromMap(maps.first);
  }

  /// Récupère un utilisateur par ID
  Future<Utilisateur?> getUtilisateurById(String id) async {
    final db = await database;
    final maps = await db.query(
      'utilisateurs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Utilisateur.fromMap(maps.first);
  }

  /// Utile pour détecter le premier utilisateur de l'app
  Future<Utilisateur?> getFirstUtilisateur() async {
    final db = await database;
    final maps = await db.query('utilisateurs', limit: 1);
    if (maps.isEmpty) return null;
    return Utilisateur.fromMap(maps.first);
  }

  /// Récupère tous les utilisateurs
  Future<List<Utilisateur>> getAllUtilisateurs() async {
    final db = await database;
    final maps = await db.query('utilisateurs', orderBy: 'nom ASC');
    return maps.map((m) => Utilisateur.fromMap(m)).toList();
  }

  /// Récupère spécifiquement les collaborateurs d'un patron
  Future<List<Utilisateur>> getCollaborateurs(String patronId) async {
    final db = await database;
    final maps = await db.query(
      'utilisateurs',
      where: 'parent_id = ?',
      whereArgs: [patronId],
      orderBy: 'nom ASC',
    );
    return maps.map((m) => Utilisateur.fromMap(m)).toList();
  }

  /// Compte le nombre de collaborateurs pour un patron
  Future<int> countCollaborateurs(String patronId) async {
    final db = await database;
    final res = await db.rawQuery(
        "SELECT COUNT(*) as c FROM utilisateurs WHERE parent_id = ?",
        [patronId]
    );
    return (res.first['c'] as int?) ?? 0;
  }

  /// Active ou désactive un utilisateur
  Future<int> setUtilisateurValide(String id, int valide) async {
    final db = await database;
    return await db.update(
      'utilisateurs',
      {'valide': valide},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Met à jour un utilisateur
  Future<int> updateUtilisateur(Utilisateur u, {String? password}) async {
    final db = await database;
    final data = u.toMap();

    if (password != null && password.isNotEmpty) {
      final bytes = utf8.encode(password);
      final hash = sha256.convert(bytes).toString();
      data['password_hash'] = hash;
    }

    return await db.update(
      'utilisateurs',
      data,
      where: 'id = ?',
      whereArgs: [u.id],
    );
  }

  /// Supprime un utilisateur (simple)
  Future<int> deleteUtilisateur(String id) async {
    final db = await database;
    return await db.delete('utilisateurs', where: 'id = ?', whereArgs: [id]);
  }

  /// Supprime un utilisateur en protégeant le dernier administrateur
  Future<int> deleteUtilisateurSafely(String id) async {
    final db = await database;
    final target = await db.query(
      'utilisateurs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    // 🔐 MODULE 4 — un SUPER_ADMIN (nouvelle colonne `new_role`) est protégé
    // au même titre qu'un ancien compte `admin` : sans lui, plus personne ne
    // peut administrer la plateforme.
    final String? ancienRole = target.isNotEmpty
        ? target.first['role'] as String?
        : null;
    final String? nouveauRole = target.isNotEmpty
        ? target.first['new_role'] as String?
        : null;

    final bool estAdministrateur = ancienRole == 'admin' ||
        (nouveauRole ?? '').toUpperCase() == 'SUPER_ADMIN';

    if (estAdministrateur) {
      final adminsCountRes = await db.rawQuery(
          "SELECT COUNT(*) as c FROM utilisateurs "
          "WHERE role = ? OR upper(coalesce(new_role, '')) = ?",
          ['admin', 'SUPER_ADMIN']);
      final adminsCount = (adminsCountRes.first['c'] as int?) ?? 0;
      if (adminsCount <= 1) {
        throw Exception('Impossible de supprimer le dernier administrateur.');
      }
    }

    return await db.delete('utilisateurs', where: 'id = ?', whereArgs: [id]);
  }

  /// 🔐 Login collaborateur local (email + mot de passe)
  Future<Utilisateur?> getUtilisateurByEmailAndPassword(
      String email,
      String password,
      ) async {
    final db = await database;
    final hash = sha256.convert(utf8.encode(password)).toString();
    final maps = await db.query(
      'utilisateurs',
      where: 'email = ? AND password_hash = ? AND valide = 1',
      whereArgs: [email.toLowerCase().trim(), hash],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return Utilisateur.fromMap(maps.first);
  }

  /// Recherche un utilisateur par email + password_hash
  Future<Utilisateur?> getUtilisateurByEmailAndPasswordHash(
      String email,
      String passwordHash,
      ) async {
    final db = await database;

    final result = await db.query(
      'utilisateurs',
      where: 'email = ? AND password_hash = ?',
      whereArgs: [email, passwordHash],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return Utilisateur.fromMap(result.first);
    }
    return null;
  }

  /// 🧩 MODULE 15 — identifiant du propriétaire des données de la BOUTIQUE
  /// affichée : l'espace actif s'il est connu, sinon le patron du compte.
  ///
  /// À utiliser par tous les écrans qui lisent/écrivent des données métier
  /// (produits, ventes, caisse, clients, dettes, dépenses, inventaires…) :
  /// c'est ce qui fait qu'une boutique ne voit pas le catalogue de l'autre.
  Future<String?> ownerDonneesDe(String userId) async {
    final String? espace = ScopeDonnees.espaceActif;
    if (espace != null) return espace;
    return resolveEffectiveOwnerId(userId);
  }

  Future<String?> resolveEffectiveOwnerId(String userId) async {
    // 🧩 MODULE 15 — LA BOUTIQUE AFFICHÉE PORTE SES PROPRES DONNÉES.
    //    `ScopeDonnees` est renseigné par `EspaceService` (liste des espaces,
    //    bascule, déconnexion). Tant qu'il est vide (démarrage à froid, hors
    //    ligne), on garde exactement le comportement historique ci-dessous :
    //    l'espace par défaut porte l'UUID du patron, donc rien ne change pour
    //    un compte à une seule boutique.
    final String? espace = ScopeDonnees.espaceActif;
    if (espace != null) return espace;

    final db = await database;

    final result = await db.query(
      'utilisateurs',
      columns: ['id', 'parent_id'],
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );

    if (result.isEmpty) return null;

    final parentId = result.first['parent_id'] as String?;

    // 🔑 Si parentId existe → collaborateur → owner = parentId
    return parentId ?? userId;
  }

  /// Récupère tous les collaborateurs d'un owner
  Future<List<Utilisateur>> getAllCollaborateurs(String ownerId) async {
    final db = await database;
    final maps = await db.query(
      'utilisateurs',
      where: 'parent_id = ?',
      whereArgs: [ownerId],
    );

    return maps.map((m) => Utilisateur.fromMap(m)).toList();
  }

  Future<int> deleteUtilisateurById(String id) async {
    final db = await database;
    return await db.delete(
      'utilisateurs',
      where: 'id = ?',
      whereArgs: [id],
    );
  }



  // ========================= CATEGORIES =========================

  Future<int> insertCategoryIfNotExists(String name, {String? ownerId}) async {
    final db = await database;
    final trimmed = (name ?? '').trim();
    if (trimmed.isEmpty) throw Exception('Nom de catégorie vide');

    return await db.transaction<int>((txn) async {
      final existing = await txn.query('categories', where: 'nom = ?', whereArgs: [trimmed], limit: 1);
      if (existing.isNotEmpty) {
        return existing.first['id'] as int;
      }
      final id = await txn.insert('categories', {'nom': trimmed});
      return id;
    });
  }

  Future<void> updateCategory(String oldCategory, String newCategory, String ownerId) async {
    final db = await database;
    final oldTrim = oldCategory.trim();
    final newTrim = newCategory.trim();
    if (newTrim.isEmpty) throw Exception('Nom de nouvelle catégorie vide');

    await db.transaction((txn) async {
      // 🔑 Ajouté: Mettre à jour is_synced du produit à 0
      await txn.update(
        'produits',
        {'categorie': newTrim, 'is_synced': 0},
        where: 'categorie = ? AND owner_id = ?',
        whereArgs: [oldTrim, ownerId],
      );
      try {
        final existsNew = await txn.query('categories', where: 'nom = ?', whereArgs: [newTrim], limit: 1);
        if (existsNew.isNotEmpty) {
          await txn.delete('categories', where: 'nom = ?', whereArgs: [oldTrim]);
        } else {
          await txn.update('categories', {'nom': newTrim}, where: 'nom = ?', whereArgs: [oldTrim]);
        }
      } catch (_) {
        // ignore errors (table may not exist)
      }
    });
  }

  Future<void> deleteCategory(String category, String defaultCategory, String ownerId) async {
    final db = await database;
    final catTrim = category.trim();
    final defTrim = defaultCategory.trim();
    await db.transaction((txn) async {
      // 🔑 Ajouté: Mettre à jour is_synced du produit à 0
      await txn.update(
        'produits',
        {'categorie': defTrim, 'is_synced': 0},
        where: 'categorie = ? AND owner_id = ?',
        whereArgs: [catTrim, ownerId],
      );
      try {
        await txn.delete('categories', where: 'nom = ?', whereArgs: [catTrim]);
      } catch (_) {
        // ignore
      }
    });
  }

  Future<int> insertCategory(Category category) async {
    final db = await database;
    return await db.insert(
      'categories',
      category.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Category>> getCategories() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('categories', orderBy: 'nom ASC');
    return List.generate(maps.length, (i) {
      return Category.fromMap(maps[i]);
    });
  }

  Future<int> updateCategoryTable(Category category) async {
    final db = await database;
    return await db.update(
      'categories',
      category.toMap(),
      where: 'id = ?',
      whereArgs: [category.id],
    );
  }

  Future<int> deleteCategoryTable(int id) async {
    final db = await database;
    return await db.delete(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ========================= APPROVISIONNEMENT=========================

  Future<int> insertApprovisionnement(Approvisionnement appro) async {
    final db = await database;

    // On prépare la map pour SQLite
    final map = appro.toMap();

    // Marquer comme non synchronisé
    map['is_synced'] = 0;

    // NE PAS mettre à jour produits.quantite ici !
    // La quantité sera synchronisée par le trigger serveur et Realtime

    return await db.insert('approvisionnements', map);
  }

  Future<List<Approvisionnement>> getHistoriqueApprovisionnement(int produitId) async {
    final db = await database;
    final result = await db.query(
      'approvisionnements',
      where: 'produit_id = ?',
      whereArgs: [produitId],
      orderBy: 'date_approvisionnement DESC',
    );

    return result.map((map) => Approvisionnement.fromMap(map)).toList();
  }


  Future<int> addStockAndLog(
      Produit produit, double quantiteAjout, double nouveauPrixAchat) async {
    final db = await database;

    if (produit.id == null) {
      throw Exception("L'ID du produit est manquant pour l'approvisionnement.");
    }

    final ownerId = produit.ownerId;
    if (ownerId == null) {
      throw Exception("Owner ID du produit manquant.");
    }

    return await db.transaction<int>((txn) async {
      final nowIso = DateTime.now().toIso8601String();

      // -----------------------------
      // 1) On ne touche PLUS au produit !
      // On ne le marque pas is_synced = 0.
      // Le serveur (Trigger) ou le Realtime se chargera de mettre à jour le stock et le prix.
      // -----------------------------

      // -----------------------------
      // 2) Insérer le log d'approvisionnement
      // -----------------------------
      final String generatedUuid = _uuidGenerator.v4();
      final approvisionnement = Approvisionnement(
        produitId: produit.id!,
        quantiteAjoutee: quantiteAjout,
        prixAchatUnitaire: nouveauPrixAchat,
        dateApprovisionnement: nowIso,
        uuid: generatedUuid,
        ownerId: ownerId,
        isSynced: 0, // C'EST LUI SEUL QUI DOIT ÊTRE SYNCHRONISÉ
      );

      final mapAppro = approvisionnement.toMap();
      mapAppro['is_synced'] = 0;

      final logId = await txn.insert('approvisionnements', mapAppro);

      // 3) On met à jour le stock LOCALEMENT (Optionnel mais recommandé pour l'UX)
      // MAIS ON LE GARDE is_synced = 1 pour ne pas l'envoyer au serveur !
      await txn.rawUpdate(
          'UPDATE produits SET quantite = quantite + ?, prix_achat = ?, is_synced = 1 WHERE id = ?',
          [quantiteAjout, nouveauPrixAchat, produit.id]
      );

      return logId;
    });
  }
  Future<List<Approvisionnement>> getUnsyncedApprovisionnements({
    required String ownerId,
  }) async {
    final db = await database;

    final maps = await db.query(
      'approvisionnements',
      where: 'owner_id = ? AND is_synced = 0 AND uuid IS NOT NULL',
      whereArgs: [ownerId],
    );

    return maps.map((m) => Approvisionnement.fromMap(m)).toList();
  }

  /// Marque un approvisionnement comme synchronisé
  Future<int> markApprovisionnementAsSynced(int localId, String supabaseId) async {
    final db = await database;
    return await db.update(
      'approvisionnements',
      {'is_synced': 1, 'supabase_id': supabaseId}, // Assure-toi d'avoir la colonne supabase_id dans ta table locale
      where: 'id = ?',
      whereArgs: [localId],
    );
  }

  // ========================= STATS / UTILS (inchangé) =========================

  Future<List<String>> getDistinctCategories({String? ownerId}) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> rows = await db.rawQuery(ownerId != null
          ? '''
            SELECT nom AS category FROM categories
            UNION
            SELECT DISTINCT categorie AS category FROM produits WHERE owner_id = ?
            ORDER BY category ASC
          '''
          : '''
            SELECT nom AS category FROM categories
            UNION
            SELECT DISTINCT categorie AS category FROM produits
            ORDER BY category ASC
          ''',
          ownerId != null ? [ownerId] : null);

      final list = rows
          .map((m) => (m['category'] as String?)?.trim())
          .where((s) => s != null && s!.isNotEmpty)
          .map((s) => s!)
          .toList();

      final deduped = <String>{};
      final out = <String>[];
      for (var c in list) {
        if (!deduped.contains(c)) {
          deduped.add(c);
          out.add(c);
        }
      }
      out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return out;
    } catch (e) {
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        ownerId != null
            ? '''SELECT DISTINCT categorie as category FROM produits WHERE owner_id = ? ORDER BY category ASC'''
            : '''SELECT DISTINCT categorie as category FROM produits ORDER BY category ASC''',
        ownerId != null ? [ownerId] : null,
      );
      return maps
          .map((m) => (m['category'] as String?)?.trim())
          .where((s) => s != null && s!.isNotEmpty)
          .map((s) => s!)
          .toList();
    }
  }
  Future<int> getVentesCountForUser(String ownerId) async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM ventes WHERE owner_id = ?', [ownerId]);
    final c = res.first['c'];
    return (c == null) ? 0 : (c as int);
  }
  Future<int> updateUserPasswordOffline(String email, String hashedPass) async {
    final db = await instance.database;
    return await db.update(
      'utilisateurs',
      {'password': hashedPass},
      where: 'email = ?',
      whereArgs: [email],
    );
  }

  Future<int> getDistinctClientsCountForUser(String ownerId) async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(DISTINCT client_id) as c FROM ventes WHERE owner_id = ?', [ownerId]);
    final c = res.first['c'];
    return (c == null) ? 0 : (c as int);
  }

  Future<int> getUtilisateurCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM utilisateurs');
    final c = res.first['c'];
    return (c == null) ? 0 : (c as int);
  }

  Future<double> getTotalVentesAmount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT SUM(prix) as total FROM ventes');
    final total = res.first['total'];
    if (total == null) return 0.0;
    return (total as num).toDouble();
  }

  Future<int> getVentesCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM ventes');
    final c = res.first['c'];
    return (c == null) ? 0 : (c as int);
  }

  Future<int> getProduitsCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as c FROM produits');
    final c = res.first['c'];
    return (c == null) ? 0 : (c as int);
  }

  Future<Map<String, dynamic>> getDailyReportDetails({
    required String ownerId,
    required DateTime date,
  }) async {
    final db = await database;
    final dateStr = date.toIso8601String().substring(0, 10);

    final res = await db.rawQuery('''
      SELECT
        v.quantite as qty,
        v.prix as total_price,
        p.nom,
        p.categorie,
        p.prix_achat,
        p.prix_vente
      FROM ventes v
      JOIN produits p ON p.id = v.produit_id
      WHERE v.owner_id = ? AND v.date LIKE ? || '%'
    ''', [ownerId, dateStr]);

    double totalRevenue = 0.0;
    double totalCost = 0.0;
    double totalQuantity = 0.0;
    Map<String, double> qtyByCategory = {};
    Map<String, double> qtyByProduct = {};
    Map<String, Map<String, dynamic>> productSummary = {};

    for (var row in res) {
      final qty = (row['qty'] as num).toDouble();
      final totalSalePrice = (row['total_price'] as num).toDouble();
      final nom = row['nom'] as String;
      final categorie = row['categorie'] as String;

      final unitCost = (row['prix_achat'] as num).toDouble();

      totalRevenue += totalSalePrice;
      totalCost += (unitCost * qty);
      totalQuantity += qty;

      qtyByCategory[categorie] = (qtyByCategory[categorie] ?? 0.0) + qty;

      qtyByProduct[nom] = (qtyByProduct[nom] ?? 0.0) + qty;

      if (!productSummary.containsKey(nom)) {
        productSummary[nom] = {'produit_nom': nom, 'quantite': 0.0, 'montant_vente': 0.0};
      }
      productSummary[nom]?['quantite'] += qty;
      productSummary[nom]?['montant_vente'] += totalSalePrice;
    }

    final totalProfit = totalRevenue - totalCost;

    final sortedTopProducts = qtyByProduct.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return {
      'date': dateStr,
      'total_revenue': totalRevenue,
      'total_quantity': totalQuantity,
      'total_profit': totalProfit,
      'qty_by_category': qtyByCategory,
      'top_products': sortedTopProducts.map((e) => {'nom': e.key, 'qty_sold': e.value}).toList(),
      'detailed_sales': productSummary.values.toList(),
    };
  }

  Future<List<Map<String,dynamic>>> getTopProducts({
    String? ownerId,
    required DateTime from,
    required DateTime to,
    int limit = 10,
  }) async {
    final db = await database;
    final args = <Object?>[from.toIso8601String(), to.toIso8601String()];
    String whereOwner = '';
    if (ownerId != null) { whereOwner = 'AND v.owner_id = ?'; args.add(ownerId); }
    final res = await db.rawQuery('''
      SELECT p.id, p.nom, p.categorie, SUM(v.quantite) as qty_sold, SUM(v.prix) as revenue
      FROM ventes v
      JOIN produits p ON p.id = v.produit_id
      WHERE v.date BETWEEN ? AND ? $whereOwner
      GROUP BY p.id, p.nom, p.categorie
      ORDER BY qty_sold DESC
      LIMIT ?
    ''', [...args, limit]);
    return res;
  }


  Future<List<Map<String,dynamic>>> getSalesSeries({
    String? ownerId,
    required DateTime from,
    required DateTime to,
    required String period, // 'day'|'week'|'month'|'year'
  }) async {
    final db = await database;
    String groupExpr;
    switch (period) {
      case 'month':
        groupExpr = "strftime('%Y-%m', date)";
        break;
      case 'year':
        groupExpr = "strftime('%Y', date)";
        break;
      case 'week':
        groupExpr = "strftime('%Y', date) || '-W' || strftime('%W', date)";
        break;
      default:
        groupExpr = "strftime('%Y-%m-%d', date)";
    }
    final args = <Object?>[from.toIso8601String(), to.toIso8601String()];
    String whereOwner = '';
    if (ownerId != null) { whereOwner = 'AND owner_id = ?'; args.add(ownerId); }

    final res = await db.rawQuery('''
      SELECT $groupExpr as period, SUM(prix) as total, SUM(quantite) as qty
      FROM ventes
      WHERE date BETWEEN ? AND ? $whereOwner
      GROUP BY period
      ORDER BY period ASC
    ''', args);
    return res;
  }
}

