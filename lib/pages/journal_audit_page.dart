// lib/pages/journal_audit_page.dart
//
// MODULE 12 — ÉCRAN « JOURNAL D'AUDIT ».
//
// Accessible :
//   • au personnel plateforme (`audit/voir`) → toutes les boutiques ;
//   • au PROPRIÉTAIRE (`audit/voir`)         → SA boutique uniquement.
//
// Fonctions :
//   • liste paginée (50 par page, bouton « Charger plus ») ;
//   • filtres : recherche libre, action, niveau, période, utilisateur,
//     entreprise (plateforme) — portée appliquée par le SERVEUR (RLS) ;
//   • détail d'une entrée en JSON lisible (copiable) ;
//   • export PDF signé (référence + empreinte) — lui-même journalisé ;
//   • vérification de la chaîne d'empreintes (plateforme uniquement).
//
// ⚠️ Le journal est APPEND-ONLY : cet écran ne propose aucune modification ni
// suppression — c'est une garantie du serveur (triggers + RLS).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/audit.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/audit_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Écran du journal d'audit.
class JournalAuditPage extends StatefulWidget {
  const JournalAuditPage({super.key});

  @override
  State<JournalAuditPage> createState() => _JournalAuditPageState();
}

class _OptionFiltre {
  const _OptionFiltre(this.id, this.libelle);

  final String id;
  final String libelle;
}

class _JournalAuditPageState extends State<JournalAuditPage> {
  final AuditService _service = AuditService.instance;
  final TextEditingController _rechercheController = TextEditingController();

  static const int _taillePage = 50;

  // — Filtres —
  String? _action;
  String? _niveau;
  DateTimeRange? _periode;
  String? _utilisateurId;
  String? _entrepriseId;

  // — Options de filtres (chargées en best-effort) —
  List<_OptionFiltre> _utilisateurs = const <_OptionFiltre>[];
  List<_OptionFiltre> _entreprises = const <_OptionFiltre>[];
  String? _nomEntreprise;

  // — Données —
  List<EntreeAudit> _lignes = const <EntreeAudit>[];
  int _total = 0;
  bool _chargement = true;
  bool _chargementPlus = false;
  bool _exportEnCours = false;
  String? _erreur;

  bool get _estPlateforme => PermissionService.instance.estPlateforme;

  @override
  void initState() {
    super.initState();
    _chargerOptions();
    _charger();
  }

  @override
  void dispose() {
    _rechercheController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _chargerOptions() async {
    try {
      final SupabaseClient client = SupabaseService.instance.client;
      String? nomEntreprise;

      final dynamic users = await client
          .from('utilisateurs')
          .select('id, nom, email')
          .order('nom')
          .limit(400);
      final List<_OptionFiltre> utilisateurs = <_OptionFiltre>[];
      for (final dynamic ligne in (users is List ? users : const <dynamic>[])) {
        final Map<String, dynamic> map = Map<String, dynamic>.from(ligne as Map);
        final String nom = (map['nom'] ?? '').toString().trim();
        final String email = (map['email'] ?? '').toString().trim();
        utilisateurs.add(_OptionFiltre(
          map['id'].toString(),
          nom.isNotEmpty ? nom : email,
        ));
      }

      List<_OptionFiltre> entreprises = const <_OptionFiltre>[];
      if (_estPlateforme) {
        final dynamic liste = await client
            .from('entreprises')
            .select('id, nom')
            .order('nom')
            .limit(300);
        final List<_OptionFiltre> collectees = <_OptionFiltre>[];
        for (final dynamic ligne in (liste is List ? liste : const <dynamic>[])) {
          final Map<String, dynamic> map = Map<String, dynamic>.from(ligne as Map);
          collectees.add(_OptionFiltre(
            map['id'].toString(),
            (map['nom'] ?? '(sans nom)').toString(),
          ));
        }
        entreprises = collectees;
      } else {
        // Nom de SA boutique, pour l'en-tête de l'export PDF (best-effort).
        try {
          final String? uid = client.auth.currentUser?.id;
          if (uid != null) {
            final dynamic profil = await client
                .from('utilisateurs')
                .select('parent_id, entreprise_id')
                .eq('id', uid)
                .maybeSingle();
            final Map<String, dynamic>? pmap = profil is Map
                ? Map<String, dynamic>.from(profil)
                : null;
            final String owner = (pmap?['parent_id'] ??
                    pmap?['entreprise_id'] ??
                    uid)
                .toString();
            final dynamic entreprise = await client
                .from('entreprises')
                .select('nom')
                .eq('id', owner)
                .maybeSingle();
            final Map<String, dynamic>? emap = entreprise is Map
                ? Map<String, dynamic>.from(entreprise)
                : null;
            final String? nom = emap?['nom']?.toString();
            if (nom != null && nom.trim().isNotEmpty) {
              nomEntreprise = nom.trim();
            }
          }
        } catch (_) {
          // Purement cosmétique : l'export reste possible sans le nom.
        }
      }

      if (!mounted) return;
      setState(() {
        _utilisateurs = utilisateurs;
        _entreprises = entreprises;
        _nomEntreprise = nomEntreprise;
      });
    } catch (e) {
      // Les options de filtre sont un confort : jamais bloquantes.
      debugPrint('JournalAuditPage : options de filtres indisponibles ($e)');
    }
  }

  Future<void> _charger({bool plus = false}) async {
    if (!mounted) return;

    setState(() {
      if (plus) {
        _chargementPlus = true;
      } else {
        _chargement = true;
        _erreur = null;
      }
    });

    try {
      final PageAudit page = await _service.listerAvecFiltres(
        utilisateurId: _utilisateurId,
        action: _action,
        niveau: _niveau,
        debut: _periode?.start,
        fin: _periode?.end,
        entrepriseId: _entrepriseId,
        recherche: _rechercheController.text,
        limit: _taillePage,
        offset: plus ? _lignes.length : 0,
      );

      if (!mounted) return;
      setState(() {
        _lignes = plus
            ? <EntreeAudit>[..._lignes, ...page.lignes]
            : page.lignes;
        _total = page.total;
        _erreur = null;
        _chargement = false;
        _chargementPlus = false;
      });
    } on AuditServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
        _chargementPlus = false;
      });
    } catch (e, st) {
      debugPrint('JournalAuditPage._charger : $e\n$st');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger le journal.';
        _chargement = false;
        _chargementPlus = false;
      });
    }
  }

  void _reinitialiserFiltres() {
    _rechercheController.clear();
    setState(() {
      _action = null;
      _niveau = null;
      _periode = null;
      _utilisateurId = null;
      _entrepriseId = null;
    });
    _charger();
  }

  Future<void> _choisirPeriode() async {
    final DateTime maintenant = DateTime.now();
    final DateTimeRange? choisi = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: maintenant.add(const Duration(days: 1)),
      initialDateRange: _periode,
      helpText: 'Période du journal',
      saveText: 'Appliquer',
    );
    if (choisi == null) return;
    setState(() => _periode = choisi);
    _charger();
  }

  // ---------------------------------------------------------------------------
  // EXPORT & VÉRIFICATION
  // ---------------------------------------------------------------------------

  Future<void> _exporterPDF() async {
    setState(() => _exportEnCours = true);
    try {
      final String chemin = await _service.exporterAuditPDF(
        utilisateurId: _utilisateurId,
        action: _action,
        niveau: _niveau,
        debut: _periode?.start,
        fin: _periode?.end,
        entrepriseId: _entrepriseId,
        recherche: _rechercheController.text,
        nomEntreprise: _nomEntreprise,
      );
      if (!mounted) return;
      _message('Export PDF enregistré :\n$chemin');
    } on AuditServiceException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    } catch (e) {
      debugPrint('JournalAuditPage._exporterPDF : $e');
      if (!mounted) return;
      _message('Export impossible : vérifiez votre connexion.', erreur: true);
    } finally {
      if (mounted) setState(() => _exportEnCours = false);
    }
  }

  Future<void> _verifierIntegrite() async {
    try {
      final VerificationAudit resultat = await _service.verifierIntegrite(limit: 500);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) {
          final bool ok = resultat.verifie;
          return AlertDialog(
            icon: Icon(
              ok ? Icons.verified_rounded : Icons.warning_amber_rounded,
              color: ok ? Colors.green.shade700 : Colors.red.shade700,
              size: 42,
            ),
            title: Text(ok ? 'Chaîne intègre' : 'Anomalies détectées'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  ok
                      ? '${resultat.nbControle} entrée(s) contrôlée(s) : '
                          'aucune altération détectée.'
                      : '${resultat.nbAnomalies} anomalie(s) sur '
                          '${resultat.nbControle} entrée(s) contrôlée(s).',
                ),
                if (resultat.premierSeq != null && resultat.dernierSeq != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Séquence ${resultat.premierSeq} → ${resultat.dernierSeq}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                if (!ok) ...<Widget>[
                  const SizedBox(height: 12),
                  for (final Map<String, dynamic> anomalie
                      in resultat.anomalies.take(5))
                    Text(
                      '• seq ${anomalie['seq']} — ${anomalie['action']}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      );
    } on AuditServiceException catch (e) {
      if (!mounted) return;
      _message(e.message, erreur: true);
    } catch (e) {
      debugPrint('JournalAuditPage._verifierIntegrite : $e');
      if (!mounted) return;
      _message('Vérification impossible : vérifiez votre réseau.', erreur: true);
    }
  }

  void _message(String message, {bool erreur = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DÉTAIL D'UNE ENTRÉE
  // ---------------------------------------------------------------------------

  Future<void> _ouvrirDetail(EntreeAudit entree) async {
    final String json = const JsonEncoder.withIndent('  ').convert(
      <String, dynamic>{
        'seq': entree.seq,
        'id': entree.id,
        'action': entree.action,
        'niveau': entree.niveau.code,
        'utilisateur_id': entree.utilisateurId,
        'utilisateur': entree.utilisateur,
        'entreprise_id': entree.entrepriseId,
        'ip_address': entree.ipAddress,
        'user_agent': entree.userAgent,
        'created_at': entree.createdAt?.toIso8601String(),
        'details': entree.details,
      },
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (BuildContext ctx) {
        final ThemeData theme = Theme.of(ctx);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entree.libelleAction,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    _PuceNiveau(niveau: entree.niveau),
                    IconButton(
                      tooltip: 'Copier (JSON)',
                      icon: const Icon(Icons.copy_rounded, size: 20),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: json));
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        if (mounted) _message('Entrée copiée dans le presse-papiers.');
                      },
                    ),
                  ],
                ),
                Text(
                  '${formatDateHeure(entree.createdAt)}'
                  '${entree.anonyme ? ' · (sans session)' : ' · ${entree.utilisateur}'}'
                  '${entree.ipAddress == null ? '' : ' · IP ${entree.ipAddress}'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Divider(height: 20),
                Flexible(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        json,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  Color _couleurNiveau(NiveauAudit niveau) {
    switch (niveau) {
      case NiveauAudit.critique:
        return Colors.red.shade700;
      case NiveauAudit.haut:
        return Colors.orange.shade800;
      case NiveauAudit.moyen:
        return Colors.blue.shade700;
      case NiveauAudit.info:
        return Colors.grey.shade600;
    }
  }

  IconData _iconeNiveau(NiveauAudit niveau) {
    switch (niveau) {
      case NiveauAudit.critique:
        return Icons.gpp_maybe_rounded;
      case NiveauAudit.haut:
        return Icons.report_problem_rounded;
      case NiveauAudit.moyen:
        return Icons.info_rounded;
      case NiveauAudit.info:
        return Icons.notes_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.peutVoir(PageAccess.audit)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Journal d\'audit')),
        body: const AccesRefuse(
          message: 'Votre rôle ne permet pas de consulter le journal d\'audit.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Journal d\'audit',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          if (_estPlateforme)
            IconButton(
              tooltip: 'Vérifier l\'intégrité de la chaîne',
              onPressed: _verifierIntegrite,
              icon: const Icon(Icons.verified_user_rounded),
            ),
          IconButton(
            tooltip: 'Exporter la vue en PDF',
            onPressed: _exportEnCours ? null : _exporterPDF,
            icon: _exportEnCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.picture_as_pdf_rounded),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: () => _charger(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildFiltres(),
          Expanded(child: _buildListe()),
        ],
      ),
    );
  }

  Widget _buildFiltres() {
    final ThemeData theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surface,
      child: ExpansionTile(
        leading: const Icon(Icons.filter_alt_rounded),
        title: const Text(
          'Filtres',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          _resumeFiltres(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: <Widget>[
          TextField(
            controller: _rechercheController,
            decoration: InputDecoration(
              hintText: 'Rechercher (action, détails, IP…)',
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              suffixIcon: IconButton(
                icon: const Icon(Icons.send_rounded, size: 18),
                onPressed: () => _charger(),
              ),
            ),
            onSubmitted: (_) => _charger(),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: AppDropdownField<String?>(
                  label: 'Action',
                  value: _action,
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Toutes'),
                    ),
                    ...CatalogueAudit.toutes.map(
                      (String code) => DropdownMenuItem<String?>(
                        value: code,
                        child: Text(
                          CatalogueAudit.libelle(code),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (String? valeur) {
                    setState(() => _action = valeur);
                    _charger();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppDropdownField<String?>(
                  label: 'Niveau',
                  value: _niveau,
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous'),
                    ),
                    ...NiveauAudit.values.map(
                      (NiveauAudit niveau) => DropdownMenuItem<String?>(
                        value: niveau.code,
                        child: Text(niveau.libelle),
                      ),
                    ),
                  ],
                  onChanged: (String? valeur) {
                    setState(() => _niveau = valeur);
                    _charger();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _choisirPeriode,
                  icon: const Icon(Icons.date_range_rounded, size: 18),
                  label: Text(
                    _periode == null
                        ? 'Toute la période'
                        : '${formatDate(_periode!.start)} → ${formatDate(_periode!.end)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (_periode != null)
                IconButton(
                  tooltip: 'Effacer la période',
                  onPressed: () {
                    setState(() => _periode = null);
                    _charger();
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: AppDropdownField<String?>(
                  label: 'Utilisateur',
                  value: _utilisateurId,
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Tous'),
                    ),
                    ..._utilisateurs.map(
                      (_OptionFiltre option) => DropdownMenuItem<String?>(
                        value: option.id,
                        child: Text(
                          option.libelle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (String? valeur) {
                    setState(() => _utilisateurId = valeur);
                    _charger();
                  },
                ),
              ),
              if (_estPlateforme) ...<Widget>[
                const SizedBox(width: 10),
                Expanded(
                  child: AppDropdownField<String?>(
                    label: 'Entreprise',
                    value: _entrepriseId,
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Toutes'),
                      ),
                      ..._entreprises.map(
                        (_OptionFiltre option) => DropdownMenuItem<String?>(
                          value: option.id,
                          child: Text(
                            option.libelle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (String? valeur) {
                      setState(() => _entrepriseId = valeur);
                      _charger();
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _reinitialiserFiltres,
              icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
              label: const Text('Réinitialiser'),
            ),
          ),
        ],
      ),
    );
  }

  String _resumeFiltres() {
    final List<String> morceaux = <String>[];
    if (_action != null) morceaux.add(CatalogueAudit.libelle(_action));
    if (_niveau != null) morceaux.add('Niveau ${_niveau!.toLowerCase()}');
    if (_periode != null) {
      morceaux.add(
          '${formatDate(_periode!.start)} → ${formatDate(_periode!.end)}');
    }
    if (_rechercheController.text.trim().isNotEmpty) morceaux.add('Recherche');
    if (morceaux.isEmpty) return 'Aucun filtre actif';
    return morceaux.join(' · ');
  }

  Widget _buildListe() {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erreur != null && _lignes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(_erreur!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _charger(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_lignes.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          const SizedBox(height: 90),
          Icon(Icons.history_edu_rounded,
              size: 64, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Aucune entrée ne correspond aux filtres.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: () => _charger(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        itemCount: _lignes.length + 2,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$_total entrée(s) · ${_lignes.length} affichée(s)',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }

          if (index == _lignes.length + 1) {
            if (_lignes.length >= _total) {
              return const Padding(
                padding: EdgeInsets.only(top: 14),
                child: Center(
                  child: Text(
                    '— fin du journal —',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(top: 14),
              child: OutlinedButton.icon(
                onPressed: _chargementPlus ? null : () => _charger(plus: true),
                icon: _chargementPlus
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.expand_more_rounded),
                label: Text('Charger plus (${_total - _lignes.length} restantes)'),
              ),
            );
          }

          return _carteEntree(_lignes[index - 1]);
        },
      ),
    );
  }

  Widget _carteEntree(EntreeAudit entree) {
    final ThemeData theme = Theme.of(context);
    final Color couleur = _couleurNiveau(entree.niveau);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _ouvrirDetail(entree),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.13),
                  shape: BoxShape.circle,
                ),
                child: Icon(_iconeNiveau(entree.niveau), color: couleur, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entree.libelleAction,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDateHeure(entree.createdAt)} · '
                      '${entree.anonyme ? 'sans session' : entree.utilisateur}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${entree.action}'
                      '${entree.ipAddress == null ? '' : ' · ${entree.ipAddress}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _PuceNiveau(niveau: entree.niveau),
            ],
          ),
        ),
      ),
    );
  }
}

/// Petite puce colorée affichant le niveau d'une entrée.
class _PuceNiveau extends StatelessWidget {
  const _PuceNiveau({required this.niveau});

  final NiveauAudit niveau;

  Color get _couleur {
    switch (niveau) {
      case NiveauAudit.critique:
        return Colors.red.shade700;
      case NiveauAudit.haut:
        return Colors.orange.shade800;
      case NiveauAudit.moyen:
        return Colors.blue.shade700;
      case NiveauAudit.info:
        return Colors.grey.shade600;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _couleur.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _couleur.withValues(alpha: 0.5)),
      ),
      child: Text(
        niveau.libelle,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: _couleur,
        ),
      ),
    );
  }
}
