// lib/pages/admin_users_page.dart
import 'package:flutter/material.dart';
import 'package:biashara_yangu/db_helper.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/models/admin_plateforme.dart';
import 'package:biashara_yangu/services/admin_plateforme_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/services/reinitialisation_session.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/pages/setup_page.dart';
import 'package:biashara_yangu/pages/admin_agent_terrain_page.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// utilitaires
import 'package:biashara_yangu/utils/session_manager.dart';
import 'package:biashara_yangu/utils/date_utils.dart'; // addMonths

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  final SupabaseService _supabaseService = SupabaseService.instance;
  final supabase = Supabase.instance.client;

  List<Utilisateur> users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      users = await _supabaseService.getAllUtilisateurs();
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.message ?? e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de BDD: $msg')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur inconnue: ${e.toString()}')));
      }
    }
    setState(() => _loading = false);
  }

  // 1) Activation / Désactivation compte (valide)
  Future<void> _toggleAccountActivation(Utilisateur u) async {    final newValidState = (u.valide == 1) ? 0 : 1;
    final action = newValidState == 0 ? 'Désactivé' : 'Activé';

    try {
      // update via Supabase (RLS: admin policy must allow this)
      await _supabaseService.client
          .from('utilisateurs')
          .update({'valide': newValidState})
          .eq('id', u.id?.toString() ?? '');

      // Si je désactive mon propre compte, déco
      final currentUserId = await SessionManager.getUserId();
      if (newValidState == 0 && u.id != null && u.id == currentUserId) {
        // 🧹 CORRECTIF 178 — déconnexion complète : plus aucun droit du
        // compte désactivé ne subsiste en mémoire.
        await ReinitialisationSession.tout();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Votre compte a été $action par un administrateur. Déconnexion...')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Compte de ${u.nom} $action.')),
          );
        }
        await _loadUsers();
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.message ?? e.toString();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur de mise à jour: $msg')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: ${e.toString()}')));
      }
    }
  }

  // 2) Editer utilisateur
  Future<void> _editUser(Utilisateur u) async {
    final res = await Navigator.push<bool?>(
      context,
      MaterialPageRoute<bool?>(
        builder: (_) => SetupPage(editUser: u, adminCreating: true),
      ),
    );
    if (res == true) await _loadUsers();
  }

  // ---------------------------------------------------------------------------
  // 🔐 MODULE 4 — ATTRIBUTION DU RÔLE
  // ---------------------------------------------------------------------------
  //  Un utilisateur ne peut avoir qu'UN rôle : il est écrit dans la colonne
  //  `new_role` (type `role_utilisateur_enum`). L'ancienne colonne `role`
  //  n'est plus modifiée : elle n'est conservée que pour la lecture de repli.
  //
  //  La copie locale est alignée dans la foulée, sinon le prochain démarrage
  //  hors ligne de l'utilisateur repartirait sur son ancien rôle.

  Future<void> _changerRole(Utilisateur u) async {
    if (u.id == null || u.id!.isEmpty) return;

    // 🔐 Correctif 73 — personne ne modifie son propre rôle.
    //  C'est le chemin le plus court vers une élévation de privilèges : un
    //  agent terrain pouvait se promouvoir lui-même « Super Administrateur »
    //  depuis cet écran.
    final String? moi = await SessionManager.getUserId();
    if (!mounted) return;
    if (moi != null && moi == u.id) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Vous ne pouvez pas modifier votre propre rôle.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    // 🔐 Correctif 73 — on n'attribue que les rôles autorisés pour le compte
    //  connecté (un non Super Administrateur n'attribue jamais un rôle de la
    //  plateforme La Perle).
    final List<RoleUtilisateur> attribuables =
        RoleUtilisateur.attribuablesPar(PermissionService.instance.roleCourant);

    final RoleUtilisateur roleActuel = PermissionService.roleDepuisUtilisateur(u);
    RoleUtilisateur choix = roleActuel == RoleUtilisateur.inconnu ||
            !attribuables.contains(roleActuel)
        ? RoleUtilisateur.vendeur
        : roleActuel;

    final bool? confirme = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Rôle de ${u.fullName}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rôle actuel : ${roleActuel.libelle}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<RoleUtilisateur>(
                      initialValue: choix,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      items: attribuables
                          .map((RoleUtilisateur r) => DropdownMenuItem(
                                value: r,
                                child: Text(r.libelle),
                              ))
                          .toList(),
                      onChanged: (RoleUtilisateur? r) {
                        if (r != null) setSheetState(() => choix = r);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Les droits de ce rôle sont configurables dans '
                      '« Système → Permissions des rôles ».',
                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(false),
                            child: const Text('Annuler'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(true),
                            child: const Text('Enregistrer'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (confirme != true) return;
    if (choix == roleActuel) return;
    // Défense en profondeur : la liste ne propose que des rôles autorisés,
    // mais on re-vérifie avant d'écrire.
    if (!attribuables.contains(choix)) return;

    try {
      await supabase
          .from('utilisateurs')
          .update(<String, dynamic>{'new_role': choix.code})
          .eq('id', u.id!);

      // Copie locale : le rôle doit rester juste au prochain démarrage.
      try {
        final Utilisateur? local =
            await DBHelper.instance.getUtilisateurById(u.id!);
        if (local != null) {
          await DBHelper.instance
              .updateUtilisateur(local.copyWith(newRole: choix.code));
        }
      } catch (e) {
        debugPrint('Rôle local non mis à jour: $e');
      }

      // 🔐 Correctif 73 — plus besoin de réaligner la session : modifier son
      //  propre rôle est refusé plus haut, la session courante ne peut donc
      //  pas être désynchronisée par cette action.

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${u.fullName} est désormais « ${choix.libelle} ».'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      await _loadUsers();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Changement de rôle refusé : ${e.message}'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Changement de rôle impossible : $e'),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Future<void> _createUser() async {
    final res = await Navigator.push<bool?>(
      context,
      MaterialPageRoute<bool?>(
        builder: (_) => const SetupPage(adminCreating: true),
      ),
    );
    if (res == true) await _loadUsers();
  }

  /// 🧑‍🌾 MODULE 21 — crée le compte d'un AGENT TERRAIN (compte + mot de passe).
  ///
  /// Passe par `rpc_admin_creer_agent_terrain` : le mot de passe est haché par
  /// la base et la session de l'administrateur n'est pas remplacée.
  Future<void> _creerAgentTerrain() async {
    final bool? cree = await Navigator.push<bool?>(
      context,
      MaterialPageRoute<bool?>(
        builder: (_) => const AdminAgentTerrainPage(),
      ),
    );
    if (cree == true) await _loadUsers();
  }

  // ---------------------------------------------------------------------------
  // 🛡️ MODULE 20 — RETRAIT D'UN COMPTE : ANALYSER AVANT D'AGIR
  // ---------------------------------------------------------------------------
  //  L'ancien comportement supprimait la ligne `utilisateurs` sans regarder
  //  ce qui en dépendait : risque d'échec de contrainte, données orphelines,
  //  ou perte d'historiques (ventes, paiements, dettes, audit) qu'un
  //  commerçant peut avoir à justifier des années plus tard.
  //
  //  Désormais :
  //   1. le SERVEUR calcule les dépendances réelles et recommande une
  //      stratégie (source unique de vérité) ;
  //   2. l'administrateur VOIT l'impact (volume par table) avant de décider ;
  //   3. il choisit parmi désactivation (réversible), anonymisation (identité
  //      effacée, historiques conservés) ou suppression réelle (uniquement
  //      pour un compte sans aucune attache), avec un motif journalisé.
  //
  //  Si la migration 41 n'est pas installée, la suppression est REFUSÉE avec
  //  une consigne claire : jamais de repli silencieux vers l'ancien `delete`.

  Future<void> _retirerCompte(Utilisateur u) async {
    if (u.id == null) return;

    final DependancesUtilisateur? dependances =
        await _analyserDependances(u);
    if (dependances == null || !mounted) return;

    final StrategieSuppression? choix = await _choisirStrategie(u, dependances);
    if (choix == null || !mounted) return;

    // 🧹 MODULE 21 — PURGE TOTALE : chemin distinct, car elle DÉTRUIT les
    // données. Elle s'exécute en deux temps : simulation (on montre le volume
    // exact qui serait effacé), puis exécution réelle après confirmation
    // explicite du nom du compte.
    if (choix == StrategieSuppression.purge) {
      await _purgerCompte(u);
      return;
    }

    final String? motif = choix == StrategieSuppression.desactivation
        ? await _demanderMotifRetrait(u)
        : '';
    if (motif == null || !mounted) return;

    try {
      await AdminPlateformeService.instance.retirerUtilisateur(
        utilisateurId: u.id!,
        strategie: choix,
        motif: motif,
      );
      if (!mounted) return;
      _messageAdmin(_messageSucces(choix));
      await _loadUsers();
    } on AdminPlateformeException catch (e) {
      if (!mounted) return;
      _messageAdmin(e.message, erreur: true);
    }
  }

  String _messageSucces(StrategieSuppression choix) {
    switch (choix) {
      case StrategieSuppression.desactivation:
        return 'Compte désactivé. Aucune donnée n\'a été supprimée.';
      case StrategieSuppression.anonymisation:
        return 'Compte anonymisé. Les historiques restent traçables.';
      case StrategieSuppression.suppression:
        return 'Compte supprimé définitivement.';
      case StrategieSuppression.purge:
        return 'Purge totale effectuée : le compte et ses données ont été '
            'supprimés.';
    }
  }

  /// 🧹 MODULE 21 — Purge totale d'un compte : simulation → confirmation →
  /// exécution. La simulation est demandée AVANT toute suppression pour que
  /// l'administrateur voie le volume réel de ce qu'il s'apprête à détruire.
  Future<void> _purgerCompte(Utilisateur u) async {
    if (u.id == null) return;

    final String? confirmation = await _demanderConfirmationPurge(u);
    if (confirmation == null || !mounted) return;

    try {
      final Map<String, dynamic> apercu =
          await AdminPlateformeService.instance.purgerUtilisateur(
        utilisateurId: u.id!,
        confirmation: confirmation,
        simulation: true,
      );
      if (!mounted) return;

      final bool? confirme = await _confirmerPurge(u, apercu);
      if (confirme != true || !mounted) return;

      final Map<String, dynamic> resultat =
          await AdminPlateformeService.instance.purgerUtilisateur(
        utilisateurId: u.id!,
        confirmation: confirmation,
        simulation: false,
      );
      if (!mounted) return;

      final Object? sauvegarde = resultat['sauvegarde_id'];
      _messageAdmin(
        'Purge effectuée pour ${u.fullName} : '
        '${resultat['lignes_concernees'] ?? 0} ligne(s) supprimée(s), '
        '${resultat['entreprises_supprimees'] ?? 0} entreprise(s), '
        '${resultat['paiements_supprimes'] ?? 0} paiement(s) — '
        'compte de connexion '
        '${resultat['compte_auth_supprime'] == true ? 'supprimé' : 'NON supprimé (à vérifier)'}.'
        '${sauvegarde == null ? '' : ' Sauvegarde : $sauvegarde.'}',
      );
      await _loadUsers();
    } on AdminPlateformeException catch (e) {
      if (!mounted) return;
      _messageAdmin(e.message, erreur: true);
    }
  }

  /// Exige la recopie exacte de l'adresse e-mail du compte à purger : c'est
  /// cette adresse que le serveur exige comme confirmation.
  Future<String?> _demanderConfirmationPurge(Utilisateur u) async {
    final TextEditingController controleur = TextEditingController();
    final String email = u.email.trim().toLowerCase();

    final String? saisie = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Purge totale — confirmation'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Cette opération supprime DÉFINITIVEMENT le compte '
                '${u.fullName}, SES ENTREPRISES et TOUTES leurs données '
                '(produits, stock, ventes, sorties, clients, fournisseurs, '
                'employés, abonnements, paiements, paramètres, sessions, '
                'modules). Elle est irréversible.',
              ),
              const SizedBox(height: 12),
              const Text('Pour confirmer, tapez SUPPRIMER (ou recopiez le nom '
                  'du compte / son adresse e-mail) :'),
              const SizedBox(height: 6),
              SelectableText(
                email.isEmpty ? '(adresse inconnue)' : email,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controleur,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'SUPPRIMER, nom du compte ou adresse e-mail',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, controleur.text.trim()),
            child: const Text('Continuer'),
          ),
        ],
      ),
    );

    controleur.dispose();
    if (saisie == null) return null;

    // Le SERVEUR reste l'autorité (il exige SUPPRIMER, le nom ou l'e-mail).
    // Ici, on évite seulement de lancer une requête pour une saisie vide.
    final String propre = saisie.trim();
    if (propre.isEmpty) {
      if (mounted) {
        _messageAdmin('Confirmation vide : purge annulée.', erreur: true);
      }
      return null;
    }
    return propre;
  }

  /// Affiche le volume EXACT que la purge détruirait (réponse du serveur).
  Future<bool?> _confirmerPurge(
      Utilisateur u, Map<String, dynamic> apercu) async {
    final Map<String, dynamic> detail = Map<String, dynamic>.from(
        (apercu['detail'] as Map?) ?? const <String, dynamic>{});

    return showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Ce qui sera définitivement supprimé'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Compte : ${u.fullName}'),
              Text('Lignes concernées : ${apercu['lignes_concernees'] ?? 0}'),
              const SizedBox(height: 8),
              if (detail.isEmpty)
                const Text('Aucune donnée rattachée à ce compte.')
              else
                for (final MapEntry<String, dynamic> e in detail.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('- ${e.key} : ${e.value}'),
                  ),
              const SizedBox(height: 12),
              Text(
                'Le compte de connexion (mot de passe) est également supprimé. '
                'Cette action ne peut pas être annulée.',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer définitivement'),
          ),
        ],
      ),
    );
  }

  /// Charge le diagnostic serveur ; affiche l'erreur telle quelle sinon.
  Future<DependancesUtilisateur?> _analyserDependances(Utilisateur u) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final DependancesUtilisateur dependances =
          await AdminPlateformeService.instance.dependancesUtilisateur(u.id!);
      if (mounted) Navigator.of(context).pop();
      return dependances;
    } on AdminPlateformeException catch (e) {
      if (mounted) Navigator.of(context).pop();
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Analyse impossible'),
          content: Text(
            e.type == TypeErreurAdmin.nonDeploye
                ? '${e.message}\n\nLa suppression est refusée tant que l\'analyse '
                    'des dépendances n\'est pas disponible : supprimer un compte '
                    'sans savoir ce qui en dépend ferait perdre des historiques.'
                : e.message,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      return null;
    }
  }

  /// Boîte de dialogue : impact réel + stratégie à appliquer.
  Future<StrategieSuppression?> _choisirStrategie(
    Utilisateur u,
    DependancesUtilisateur dependances,
  ) async {
    final StrategieSuppression recommandee =
        dependances.recommandation ?? StrategieSuppression.desactivation;
    StrategieSuppression choix = recommandee;

    return showDialog<StrategieSuppression>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setEtat) => AlertDialog(
          title: Text('Retirer ${u.nom} ?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Impact sur les données :',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (dependances.sansImpact)
                  const Text(
                    'Aucune donnée de gestion ni boutique n\'est rattachée à ce '
                    'compte : une suppression réelle est sans conséquence.',
                  )
                else ...<Widget>[
                  for (final MapEntry<String, int> e in dependances.detailTrie)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text('- ${_libelleTable(e.key)} : ${e.value}'),
                    ),
                  if (dependances.nbEspaces > 0)
                    Text('- Boutiques de l\'entreprise : ${dependances.nbEspaces}'),
                  if (dependances.nbCollaborateurs > 0)
                    Text('- Collaborateurs rattachés : ${dependances.nbCollaborateurs}'),
                ],
                const Divider(height: 22),
                for (final StrategieSuppression s in StrategieSuppression.values)
                  RadioListTile<StrategieSuppression>(
                    value: s,
                    groupValue: choix,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    enabled: switch (s) {
                      StrategieSuppression.suppression =>
                        dependances.suppressionPossible,
                      StrategieSuppression.purge =>
                        PermissionService.instance.estSuperAdmin,
                      _ => true,
                    },
                    title: Row(
                      children: <Widget>[
                        Flexible(child: Text(s.libelle)),
                        if (s == recommandee) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'conseillé',
                              style: TextStyle(fontSize: 10.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(s.description,
                        style: const TextStyle(fontSize: 11.5)),
                    onChanged: (StrategieSuppression? v) =>
                        setEtat(() => choix = v ?? choix),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, choix),
              style: FilledButton.styleFrom(
                backgroundColor: choix == StrategieSuppression.suppression ||
                        choix == StrategieSuppression.purge
                    ? Colors.red
                    : null,
              ),
              child: Text(choix.libelle),
            ),
          ],
        ),
      ),
    );
  }

  /// Motif du retrait : le journal d'audit doit expliquer la décision.
  Future<String?> _demanderMotifRetrait(Utilisateur u) async {
    final TextEditingController motif = TextEditingController();
    String? erreurMotif;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setEtat) => AlertDialog(
          title: const Text('Motif de la désactivation'),
          content: TextField(
            controller: motif,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Motif (obligatoire)',
              hintText: 'Ex. : départ du collaborateur, demande du client',
              errorText: erreurMotif,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                if (motif.text.trim().length < 4) {
                  setEtat(() => erreurMotif =
                      'Indiquez un motif (4 caractères minimum).');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Désactiver'),
            ),
          ],
        ),
      ),
    );

    if (confirme != true) {
      motif.dispose();
      return null;
    }
    final String valeur = motif.text.trim();
    motif.dispose();
    return valeur;
  }

  /// Nom technique de table → libellé lisible par un administrateur.
  String _libelleTable(String table) {
    switch (table) {
      case 'produits':
        return 'Articles du catalogue interne';
      case 'produits_publications':
        return 'Articles publiés sur Biashara';
      case 'ventes':
        return 'Ventes';
      case 'clients':
        return 'Clients';
      case 'dettes':
        return 'Dettes clients';
      case 'paiements_dette':
        return 'Remboursements de dettes';
      case 'depenses':
        return 'Dépenses';
      case 'caisse':
        return 'Mouvements de caisse';
      case 'clotures_caisse':
        return 'Clôtures de caisse';
      case 'publicites':
        return 'Campagnes publicitaires';
      case 'liens_attribution':
        return 'Codes d\'attribution';
      default:
        return table;
    }
  }

  void _messageAdmin(String texte, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texte),
        backgroundColor: erreur ? AppCouleurs.danger : null,
      ),
    );
  }

  // ---------------------------
  // 3) ADMIN: Gérer abonnements
  // ---------------------------

  Future<List<Map<String, dynamic>>> _fetchSubscriptionsForUser(String userId) async {
    try {
      final raw = await supabase
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .order('start_date', ascending: false);

      // raw should be a List<dynamic>
      final List<dynamic> data = raw is List ? raw : <dynamic>[];
      return data.map((e) {
        final mapE = e as Map<String, dynamic>;
        return Map<String, dynamic>.from(mapE);
      }).toList();
    } catch (e) {
      debugPrint('Erreur fetch subs: $e');
      return [];
    }
  }

  Future<void> _createSubscriptionForUser(String userId, String plan, int months, String adminId) async {
    final now = DateTime.now();
    final end = addMonths(now, months);
    try {
      final insertedRaw = await supabase.from('subscriptions').insert({
        'user_id': userId,
        'plan': plan,
        'period_months': months,
        'start_date': now.toIso8601String(),
        'end_date': end.toIso8601String(),
        'active': true,
        'activated_by': adminId,
        'activated_at': now.toIso8601String(),
      }).select();

      // insertedRaw can be List<dynamic> with one item
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abonnement créé avec succès.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur création abonnement: ${e.toString()}')));
      }
    }
  }

  Future<void> _updateSubscription(Map<String, dynamic> subUpdate, String subId) async {
    try {
      await supabase.from('subscriptions').update(subUpdate).eq('id', subId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abonnement mis à jour.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur MAJ abonnement: ${e.toString()}')));
      }
    }
  }

  Future<void> _deleteSubscription(String subId) async {
    try {
      await supabase.from('subscriptions').delete().eq('id', subId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Abonnement supprimé.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur suppression abonnement: ${e.toString()}')));
      }
    }
  }

  // UI pour gérer un utilisateur (afficher liste d'abonnements + actions)
  void _manageUserSubscriptions(Utilisateur u) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _fetchSubscriptionsForUser(u.id?.toString() ?? ''),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return SizedBox(height: 200, child: const Center(child: CircularProgressIndicator()));
          }
          final subs = snap.data ?? [];

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: Wrap(
              children: [
                ListTile(
                  title: Text('Abonnements de ${u.fullName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('${subs.length} enregistrements'),
                  trailing: TextButton.icon(
                    onPressed: () async {
                      // Créer un abonnement rapide: modal simple pour plan + mois
                      Navigator.pop(context);
                      await _showCreateSubscriptionDialog(u);
                      setState(() {}); // rafraîchir la liste générale si besoin
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Ajouter'),
                  ),
                ),
                const Divider(),
                if (subs.isEmpty)
                  const Padding(padding: EdgeInsets.all(16.0), child: Text('Aucun abonnement trouvé.'))
                else
                  ...subs.map((s) {
                    final id = (s['id']?.toString() ?? '');
                    final plan = (s['plan']?.toString() ?? '');
                    final active = s['active'] == true || s['active'] == 1;
                    final start = (s['start_date']?.toString() ?? '');
                    final end = (s['end_date']?.toString() ?? '');
                    final activatedBy = (s['activated_by']?.toString() ?? '');
                    return ListTile(
                      title: Text('$plan ${active ? "(Actif)" : "(Inactif)"}'),
                      subtitle: Text('Débute: $start\nExpire: $end\nActivé par: $activatedBy'),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (choice) async {
                          if (choice == 'deactivate') {
                            Navigator.pop(context);
                            await _updateSubscription({'active': false}, id);
                          } else if (choice == 'activate') {
                            Navigator.pop(context);
                            await _updateSubscription({'active': true}, id);
                          } else if (choice == 'edit') {
                            Navigator.pop(context);
                            await _showEditSubscriptionDialog(id, s);
                          } else if (choice == 'delete') {
                            Navigator.pop(context);
                            _confirmDeleteSubscription(id);
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: active ? 'deactivate' : 'activate', child: Text(active ? 'Désactiver' : 'Activer')),
                          const PopupMenuItem(value: 'edit', child: Text('Éditer')),
                          const PopupMenuItem(value: 'delete', child: Text('Supprimer', style: TextStyle(color: Colors.red))),
                        ],
                      ),
                    );
                  }).toList(),
                const SizedBox(height: 12),
                Center(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fermer'))),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  // Dialog création rapide d'abonnement (plan + mois)
  Future<void> _showCreateSubscriptionDialog(Utilisateur u) async {
    final _planCtrl = TextEditingController(text: 'monthly_basic');
    final _monthsCtrl = TextEditingController(text: '1');
    final adminId = (await SessionManager.getUserId()) ?? '';

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Créer abonnement pour ${u.fullName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: _planCtrl, decoration: const InputDecoration(labelText: 'Plan')),
            TextField(controller: _monthsCtrl, decoration: const InputDecoration(labelText: 'Durée (mois)'), keyboardType: TextInputType.number),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              final plan = _planCtrl.text.trim();
              final months = int.tryParse(_monthsCtrl.text.trim()) ?? 1;
              Navigator.pop(ctx);
              if (u.id != null) await _createSubscriptionForUser(u.id!, plan, months, adminId);
            },
            child: const Text('Créer'),
          ),
        ],
      ),
    );
  }

  // Dialog édition d'abonnement (modifie plan / dates / period)
  Future<void> _showEditSubscriptionDialog(String subId, Map<String, dynamic> sub) async {
    final _planCtrl = TextEditingController(text: sub['plan']?.toString() ?? '');
    final _monthsCtrl = TextEditingController(text: (sub['period_months']?.toString() ?? '1'));
    final _startCtrl = TextEditingController(text: sub['start_date']?.toString() ?? '');
    final _endCtrl = TextEditingController(text: sub['end_date']?.toString() ?? '');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Éditer abonnement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: _planCtrl, decoration: const InputDecoration(labelText: 'Plan')),
              TextField(controller: _monthsCtrl, decoration: const InputDecoration(labelText: 'Durée (mois)'), keyboardType: TextInputType.number),
              TextField(controller: _startCtrl, decoration: const InputDecoration(labelText: 'Start ISO (optionnel)')),
              TextField(controller: _endCtrl, decoration: const InputDecoration(labelText: 'End ISO (optionnel)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () async {
              final plan = _planCtrl.text.trim();
              final months = int.tryParse(_monthsCtrl.text.trim()) ?? (sub['period_months'] ?? 1) as int;
              final Map<String, dynamic> update = {
                'plan': plan,
                'period_months': months,
              };
              if (_startCtrl.text.isNotEmpty) update['start_date'] = _startCtrl.text.trim();
              if (_endCtrl.text.isNotEmpty) update['end_date'] = _endCtrl.text.trim();
              Navigator.pop(ctx);
              await _updateSubscription(update, subId);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteSubscription(String id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cet abonnement ?'),
        content: const Text('Cette opération est définitive.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteSubscription(id);
            },
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ---------------------------
  // Build UI
  // ---------------------------
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        children: [
          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(onPressed: _createUser, icon: const Icon(Icons.person_add), label: const Text('Ajouter un utilisateur')),
                // 🧑‍🌾 MODULE 21 ter — SEUL le Super Admin ou le gestionnaire des
                // comptes crée un agent terrain. Un agent ne peut PAS en créer un
                // autre (le serveur le refuse déjà ; on masque aussi le bouton).
                if (PermissionService.instance.estSuperAdmin ||
                    PermissionService.instance.roleCourant ==
                        RoleUtilisateur.gestionnaireComptes)
                  ElevatedButton.icon(onPressed: _creerAgentTerrain, icon: const Icon(Icons.badge_outlined), label: const Text('Ajouter un agent terrain')),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.refresh), onPressed: _loadUsers, tooltip: 'Rafraîchir'),
              ],
            ),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (users.isEmpty
                ? const Center(child: Text("Aucun utilisateur trouvé."))
                : ListView.separated(
              itemCount: users.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final u = users[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: u.valide == 1 ? Colors.blueAccent : Colors.grey,
                    child: Text(u.nom.isNotEmpty ? u.nom[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(u.nom, style: TextStyle(fontWeight: FontWeight.bold, color: u.valide == 0 ? Colors.grey : Colors.black)),
                  subtitle: Text('${u.email ?? ''} • ${PermissionService.roleDepuisUtilisateur(u).libelle}\nStatut: ${u.valide == 1 ? 'Activé' : 'Désactivé'}'),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.more_vert),
                    onPressed: () => _showAdminActions(context, u),
                  ),
                );
              },
            )),
          ),
        ],
      ),
    );
  }

  // Menu d'actions (attach manage subscriptions)
  void _showAdminActions(BuildContext context, Utilisateur user) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text('Actions pour ${user.nom}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              const Divider(height: 1),
              // 🗑️ SUPPRESSION — action VOLONTAIREMENT visible et rouge :
              // elle était auparavant en bas du menu, en gris, et passait
              // inaperçue. Deux étapes : analyse des dépendances, puis
              // confirmation écrite (nom du compte ou SUPPRIMER).
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  "Supprimer l'utilisateur",
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Supprime le compte ET, si c\'est un propriétaire, ses '
                  'entreprises et toutes leurs données (avec sauvegarde).',
                  style: TextStyle(fontSize: 11),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _retirerCompte(user);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_note, color: Colors.blue),
                title: const Text('Modifier le profil et le rôle'),
                subtitle: Text('Rôle actuel: ${PermissionService.roleDepuisUtilisateur(user).libelle}'),
                onTap: () {
                  Navigator.pop(context);
                  _editUser(user);
                },
              ),
              // 🔐 MODULE 4 — le rôle détermine les pages et les actions.
              ListTile(
                leading: const Icon(Icons.admin_panel_settings_rounded,
                    color: Colors.deepPurple),
                title: const Text('Changer le rôle (permissions)'),
                subtitle: Text(
                    'Actuel : ${PermissionService.roleDepuisUtilisateur(user).libelle}'),
                onTap: () {
                  Navigator.pop(context);
                  _changerRole(user);
                },
              ),
              ListTile(
                leading: Icon(user.valide == 1 ? Icons.block : Icons.check_circle_outline, color: user.valide == 1 ? Colors.red : Colors.green),
                title: Text(user.valide == 1 ? 'Désactiver le compte' : 'Activer le compte'),
                subtitle: Text(user.valide == 1 ? 'L\'utilisateur ne pourra plus se connecter.' : 'L\'utilisateur pourra se connecter.'),
                onTap: () {
                  Navigator.pop(context);
                  _toggleAccountActivation(user);
                },
              ),
              ListTile(
                leading: const Icon(Icons.subscriptions, color: Colors.orange),
                title: const Text('Gérer les abonnements'),
                subtitle: const Text('Voir / créer / modifier les abonnements'),
                onTap: () {
                  Navigator.pop(context);
                  _manageUserSubscriptions(user);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
