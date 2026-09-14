// lib/pages/admin_maintenance_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' show basename, dirname;
import 'package:biashara_yangu/db_helper.dart';

class AdminMaintenancePage extends StatefulWidget {
  const AdminMaintenancePage({super.key});

  @override
  State<AdminMaintenancePage> createState() => _AdminMaintenancePageState();
}

class _AdminMaintenancePageState extends State<AdminMaintenancePage> {
  final DBHelper _dbHelper = DBHelper.instance;
  bool _busy = false;

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ====================================================================
  // SAUVEGARDE : appelle la méthode backupDatabase de DBHelper
  // ====================================================================
  Future<void> _handleBackup() async {
    if (_busy) return;
    setState(() => _busy = true);
    _showSnackBar('Démarrage de la sauvegarde...', isError: false);

    try {
      // backupDatabase doit retourner le chemin complet du fichier backup créé
      final String backupPath = await _dbHelper.backupDatabase();
      final fileName = basename(backupPath);

      _showSnackBar('Sauvegarde terminée: $fileName', isError: false);

      // Afficher le résultat dans une boîte de dialogue
      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('Sauvegarde Réussie ✅'),
            content: Text('Le fichier de sauvegarde a été créé:\n\n$backupPath\n\nPensez à l\'exporter pour le sécuriser.'),
            actions: [
              TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('OK')),
            ],
          );
        },
      );
    } catch (e) {
      _showSnackBar('Erreur de sauvegarde: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ====================================================================
  // RESTAURATION : sélection d'un fichier (ici simulée) puis appel DBHelper.restoreDatabase
  // Remarque: pour une vraie sélection utilisateur, intégrer file_picker.
  // ====================================================================
  Future<void> _handleRestore() async {
    if (_busy) return;

    // Simuler la sélection d'un fichier de backup (ou utiliser FilePicker)
    final String simulatedBackupPath = await _getTestFilePath();

    final backupFile = File(simulatedBackupPath);
    final exists = await backupFile.exists();
    if (!exists) {
      _showSnackBar("Fichier de backup introuvable: $simulatedBackupPath", isError: true);
      return;
    }

    // Confirmation
    final bool confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('⚠️ AVERTISSEMENT: Restauration', style: TextStyle(color: Colors.red)),
          content: const Text(
            'Êtes-vous sûr de vouloir restaurer la base de données ? '
                'TOUTES les données actuelles seront écrasées par le fichier sélectionné.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Annuler')),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ÉCRASER les données', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    ) ??
        false;

    if (!confirm) {
      _showSnackBar('Restauration annulée.', isError: false);
      return;
    }

    setState(() => _busy = true);
    _showSnackBar('Restauration en cours...', isError: false);

    try {
      // restoreDatabase doit prendre le chemin du fichier .db à restaurer
      await _dbHelper.restoreDatabase(simulatedBackupPath);

      _showSnackBar('Restauration réussie !', isError: false);

      // Optionnel : forcer un refresh global / redémarrage de l'app
    } catch (e) {
      _showSnackBar('Erreur de restauration: ${e.toString()}', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ====================================================================
  // Cherche un fichier backup créé précédemment (méthode utilitaire)
  // ====================================================================
  Future<String> _getTestFilePath() async {
    try {
      final String dbPath = await _dbHelper.getDatabasePathFile();
      final databaseDir = Directory(dirname(dbPath));

      final List<FileSystemEntity> children = databaseDir.existsSync() ? databaseDir.listSync() : [];
      final backups = children
          .whereType<File>()
          .where((f) => f.path.endsWith('.db') && basename(f.path).startsWith('biashara_yangu_backup'))
          .toList();

      if (backups.isNotEmpty) {
        // On choisit le plus récent selon la date de modification si possible
        backups.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
        return backups.first.path;
      }
    } catch (_) {
      // ignore et fallback
    }

    // Fallback : retourner le chemin principal de la BD (plutôt que rien)
    return await _dbHelper.getDatabasePathFile();
  }

  // ====================================================================
  // Montrer les logs (interface) — si vous avez une table 'logs', interroger DBHelper ici
  // ====================================================================
  void _showLogs() {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Journal des Activités (Audit)'),
          content: const Text(
            'Cette fonctionnalité nécessite une table "logs" dans la base de données.\n\n'
                'Quand la table existera, vous pourrez interroger DBHelper pour afficher les entrées ici.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Fermer')),
          ],
        );
      },
    );
  }

  // ====================================================================
  // BUILD
  // ====================================================================
  @override
  Widget build(BuildContext context) {
    final double basePadding = 16.0;
    final media = MediaQuery.of(context);
    final bottomPad = basePadding + media.padding.bottom + media.viewInsets.bottom + 16.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance & Sécurité', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(basePadding, basePadding, basePadding, bottomPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gestion de la Base de Données',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const Divider(),

            // Sauvegarde
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.save, color: Colors.blue, size: 30),
                title: const Text('Sauvegarde de la BD'),
                subtitle: const Text('Crée une copie du fichier de base de données à des fins de sécurité.'),
                trailing: _busy
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _handleBackup,
              ),
            ),

            // Restauration
            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.restore, color: Colors.red, size: 30),
                title: const Text('Restauration de la BD'),
                subtitle: const Text('Charge un fichier de sauvegarde, écrasant les données existantes.'),
                trailing: _busy
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _handleRestore,
              ),
            ),

            const SizedBox(height: 24),

            // Journal des Activités
            const Text(
              'Audit & Sécurité',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blueGrey),
            ),
            const Divider(),

            Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 8),
              child: ListTile(
                leading: const Icon(Icons.security, color: Colors.green, size: 30),
                title: const Text('Journal des Activités (Logs)'),
                subtitle: const Text('Consulter l\'historique des actions critiques (administrateur uniquement).'),
                trailing: const Icon(Icons.search, size: 16),
                onTap: _showLogs,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
