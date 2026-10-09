// lib/pages/achat_quotas_page.dart
//
// MODULE 13 — ÉCRAN « ACHETER DES QUOTAS » (Étape 6).
//
// Trois usages dans UN écran, selon le rôle :
//
//   1. TOUT MEMBRE — commander un pack (10 · 20 · 50 · 100 quotas) :
//      la demande part au SUPER ADMIN qui l'approuve ou la refuse ; le
//      MONTANT est calculé côté serveur (jamais saisi par le client) ;
//
//   2. LE PATRON (propriétaire) — ATTRIBUER des quotas du pool de
//      l'entreprise à un collaborateur (anti-abus : chacun consomme son
//      allocation) et RÉGLER une demande depuis SA CAISSE (« Marquer payé » —
//      une dépense « Quotas IA » est alors écrite dans la finance) ;
//
//   3. LE SUPER ADMIN — recevoir les demandes (Approuver / Refuser) et
//      confirmer les encaissements.
//
// ⚠️ Le montant de chaque demande/achat est TOUJOURS affiché, y compris
// impayé — l'argent dû pour l'assistant reste visible en permanence.

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/agent_ia.dart';
import 'package:biashara_yangu/models/permission.dart';
import 'package:biashara_yangu/services/agent_service.dart';
import 'package:biashara_yangu/services/permission_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';
import 'package:biashara_yangu/widgets/permission_gate.dart';

/// Écran de gestion des quotas IA (achat, attribution, validation).
class AchatQuotasPage extends StatefulWidget {
  const AchatQuotasPage({super.key});

  @override
  State<AchatQuotasPage> createState() => _AchatQuotasPageState();
}

class _AchatQuotasPageState extends State<AchatQuotasPage> {
  final AgentService _service = AgentService.instance;
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _attributionController = TextEditingController();

  static const Map<String, String> _modesPaiement = <String, String>{
    'especes': 'Espèces',
    'mobile_money': 'Mobile Money',
    'carte': 'Carte',
    'virement': 'Virement',
  };

  EtatAgentIa? _etat;
  List<AchatQuotas> _achats = const <AchatQuotas>[];
  bool _chargement = true;
  bool _actionEnCours = false;
  String? _erreur;

  /// 🪙 CORRECTIF 68 — le catalogue vient désormais de la base.
  ///  Vide = catalogue injoignable (migration non exécutée, hors ligne) : on
  ///  retombe alors sur la grille locale, sans jamais laisser l'écran vide.
  List<PackQuotas> _packsCatalogue = const <PackQuotas>[];

  /// Où sont passés les quotas : pool restant + solde de chaque collaborateur.
  AttributionsQuotas _attributions = AttributionsQuotas.vide;

  int _packQuotas = 10;
  String _mode = 'especes';
  String? _attributionMembre;

  /// Les packs à afficher : le catalogue s'il est joignable, sinon la grille
  /// d'origine (règle fail-open du projet).
  List<PackQuotas> get _packs {
    if (_packsCatalogue.isNotEmpty) return _packsCatalogue;
    return PackQuotas.depuisConfig((_etat ?? EtatAgentIa.defaut).config);
  }

  /// Le pack sélectionné.
  ///
  /// ⚠️ REPLI sur le premier pack si celui qui était choisi a disparu du
  /// catalogue : le Super Admin a pu le supprimer ou le désactiver entre
  /// l'ouverture de l'écran et le clic. Un `firstWhere` sans repli ferait
  /// planter l'écran au pire moment — au moment de payer.
  PackQuotas get _packSelectionne {
    final List<PackQuotas> packs = _packs;
    for (final PackQuotas pack in packs) {
      if (pack.quotas == _packQuotas) return pack;
    }
    return packs.first;
  }

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _attributionController.dispose();
    super.dispose();
  }

  /// 🪙 MODULE 18 — les quotas IA sont facturés en CDF par la plateforme :
  /// ces montants s'affichent toujours en CDF (pas dans la devise du client).
  static String _montant(double valeur) =>
      formatMontant(valeur, devise: deviseParDefaut);

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _charger() async {
    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    try {
      final List<dynamic> resultats = await Future.wait<dynamic>(<Future<dynamic>>[
        _service.chargerEtat(),
        _service.listerAchats(),
      ]);
      if (!mounted) return;
      setState(() {
        _etat = resultats[0] as EtatAgentIa;
        _achats = resultats[1] as List<AchatQuotas>;
        _chargement = false;
      });

      //  Correctif 68 — chargements SECONDAIRES, jamais bloquants : si la
      //  migration n'est pas exécutée, l'achat doit continuer de fonctionner
      //  avec la grille locale.
      final List<PackQuotas> packs = await _service.chargerPacks(
        config: (_etat ?? EtatAgentIa.defaut).config,
      );

      AttributionsQuotas attributions = AttributionsQuotas.vide;
      try {
        attributions = await _service.chargerAttributions();
      } catch (e) {
        debugPrint('AchatQuotasPage (attributions) : $e');
      }

      if (!mounted) return;
      setState(() {
        _packsCatalogue = packs;
        _attributions = attributions;
      });
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      setState(() {
        _erreur = e.message;
        _chargement = false;
      });
    } catch (e) {
      debugPrint('AchatQuotasPage._charger : $e');
      if (!mounted) return;
      setState(() {
        _erreur = 'Impossible de charger les quotas.';
        _chargement = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------

  Future<void> _demander() async {
    final EtatAgentIa? etat = _etat;
    if (etat == null) return;

    final PackQuotas pack = _packSelectionne;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        icon: const Icon(Icons.shopping_cart_checkout_rounded),
        title: const Text('Envoyer la demande ?'),
        content: Text(
          'Pack de ${pack.quotas} quotas — ${_montant(pack.prix)}\n'
          'Paiement : ${_modesPaiement[_mode] ?? _mode}\n\n'
          'Le Super Admin va recevoir votre demande. Une fois approuvée, les '
          'quotas arrivent dans le pool de l\'entreprise, puis le paiement '
          'sera suivi (payé / impayé).',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Envoyer la demande'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    await _executer(
      () => _service.demanderAchat(
        nombreQuotas: _packQuotas,
        modePaiement: _mode,
        note: _noteController.text,
      ),
      succes: 'Demande envoyée : le Super Admin va la traiter.',
    );
    _noteController.clear();
  }

  Future<void> _valider(AchatQuotas achat, bool approuver) async {
    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        icon: Icon(
          approuver ? Icons.check_circle_outline_rounded : Icons.cancel_outlined,
          color: approuver ? Colors.green.shade700 : Colors.red.shade700,
        ),
        title: Text(approuver ? 'Approuver la demande ?' : 'Refuser la demande ?'),
        content: Text(
          '${achat.nombreQuotas} quotas — ${_montant(achat.montantCdf)}'
          '${achat.utilisateurNom.isEmpty ? '' : ' (${achat.utilisateurNom})'}\n\n'
          '${approuver ? 'Les quotas seront crédités dans le pool de l\'entreprise.' : 'La demande sera refusée.'}',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Retour'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: approuver ? null : Colors.red.shade700,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(approuver ? 'Approuver' : 'Refuser'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    await _executer(
      () => _service.validerAchat(achatId: achat.id, approuver: approuver),
      succes: approuver
          ? 'Demande approuvée : quotas crédités.'
          : 'Demande refusée.',
    );
  }

  Future<void> _marquerPaye(AchatQuotas achat) async {
    final bool estProprietaire = _etat?.estProprietaire ?? false;

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        icon: Icon(Icons.payments_rounded, color: Colors.green.shade700),
        title: const Text('Marquer ce paiement payé ?'),
        content: Text(
          'Montant : ${_montant(achat.montantCdf)} — ${achat.nombreQuotas} quotas.\n\n'
          '${estProprietaire ? 'Une dépense « Quotas IA » sera écrite dans la caisse de l\'entreprise.' : 'Vous confirmez que la plateforme a bien encaissé ce montant.'}',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Retour'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmer le paiement'),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    await _executer(
      () => _service.marquerPaye(achatId: achat.id),
      succes: estProprietaire
          ? 'Paiement enregistré : dépense écrite dans la caisse.'
          : 'Paiement confirmé.',
    );
  }

  Future<void> _attribuer() async {
    final String? membre = _attributionMembre;
    final int? quotas = int.tryParse(_attributionController.text.trim());

    if (membre == null || quotas == null || quotas < 1) {
      _snack('Choisissez un collaborateur et indiquez un nombre de quotas (≥ 1).',
          erreur: true);
      return;
    }

    final MembreQuota? cible = _etat?.collaborateurs
        .where((MembreQuota m) => m.id == membre)
        .firstOrNull;

    await _executer(
      () => _service.attribuer(utilisateurId: membre, quotas: quotas),
      succes: '$quotas quotas attribués à ${cible?.nom ?? 'ce collaborateur'}.',
    );
    _attributionController.clear();
  }

  Future<void> _executer(
    Future<Map<String, dynamic>> Function() action, {
    required String succes,
  }) async {
    setState(() => _actionEnCours = true);
    try {
      final Map<String, dynamic> resultat = await action();
      if (!mounted) return;
      final Object? pool = resultat['pool_restant'];
      _snack(pool is num ? '$succes (pool : $pool restants)' : succes);
      await _charger();
    } on AgentServiceException catch (e) {
      if (!mounted) return;
      _snack(e.message, erreur: true);
    } catch (e) {
      debugPrint('AchatQuotasPage._executer : $e');
      if (!mounted) return;
      _snack('Action impossible : vérifiez votre réseau.', erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  void _snack(String message, {bool erreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: erreur ? Colors.red.shade700 : null,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (!PermissionService.instance.peutVoir(PageAccess.assistantIa)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Quotas IA')),
        body: const AccesRefuse(
          message: 'Votre rôle ne permet pas de gérer les quotas IA.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quotas IA',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _chargement ? null : _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _vueErreur()
              : RefreshIndicator(
                  onRefresh: _charger,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                    children: <Widget>[
                      _carteSoldes(),
                      const SizedBox(height: 16),
                      _sectionTitre('Commander un pack', Icons.add_shopping_cart_rounded),
                      _cartePacks(),
                      const SizedBox(height: 14),
                      _carteFormulaire(),
                      if (_etat?.estProprietaire == true) ...<Widget>[
                        const SizedBox(height: 22),
                        _sectionTitre(
                          'Attribuer des quotas (patron)',
                          Icons.family_restroom_rounded,
                        ),
                        _carteAttribution(),
                        // 🪙 CORRECTIF 68 — où sont passés les quotas ?
                        _carteAttributions(),
                      ],
                      const SizedBox(height: 22),
                      _sectionTitre(
                        'Demandes & achats',
                        Icons.receipt_long_rounded,
                      ),
                      _blocAchats(),
                    ],
                  ),
                ),
    );
  }

  Widget _vueErreur() {
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
              onPressed: _charger,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitre(String titre, IconData icone) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Icon(icone, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Text(
            titre,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _carteSoldes() {
    final EtatAgentIa etat = _etat ?? EtatAgentIa.defaut;
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: null,
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _statQuota(
                  'Mon solde',
                  etat.moi.quotasDisponibles,
                  Icons.person_rounded,
                ),
              ),
              if (etat.pool != null)
                Expanded(
                  child: _statQuota(
                    'Pool entreprise',
                    etat.pool!.quotasDisponibles,
                    Icons.groups_rounded,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tarif : ${_montant(etat.config.tarifParQuota)} / quota '
            '· 1 quota = ${etat.config.caracteresParQuota} caractères de réponse '
            '· pack de 10 = ${_montant(etat.config.prixPack10Quotas)}',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (etat.pool != null && etat.pool!.quotasDisponibles > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Le patron distribue le pool à l\'équipe (chaque membre '
                'consomme uniquement son allocation).',
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statQuota(String libelle, int valeur, IconData icone) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icone, size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              libelle,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$valeur',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _cartePacks() {
    final EtatAgentIa etat = _etat ?? EtatAgentIa.defaut;
    final List<PackQuotas> packs = _packs;
    final ThemeData theme = Theme.of(context);

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: packs.map((PackQuotas pack) {
        final bool selectionne = pack.quotas == _packQuotas;
        final double economie = etat.config.tarifParQuota > 0
            ? (1 - pack.prixParQuota / etat.config.tarifParQuota) * 100
            : 0;

        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _actionEnCours
              ? null
              : () => setState(() => _packQuotas = pack.quotas),
          child: Container(
            width: (MediaQuery.of(context).size.width - 52) / 2,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: selectionne
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                  : theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selectionne
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selectionne ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${pack.quotas} quotas',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (pack.quotas == 10)
                      const Text('⭐', style: TextStyle(fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _montant(pack.prix),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  pack.quotas == 10
                      ? 'Populaire'
                      : '−${economie.toStringAsFixed(0)} % / quota',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(growable: false),
    );
  }

  Widget _carteFormulaire() {
    final EtatAgentIa etat = _etat ?? EtatAgentIa.defaut;
    final PackQuotas pack = _packSelectionne;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppDropdownField<String>(
            label: 'Mode de paiement',
            value: _mode,
            items: _modesPaiement.entries
                .map((MapEntry<String, String> e) => DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.value),
                    ))
                .toList(growable: false),
            onChanged: _actionEnCours
                ? null
                : (String? valeur) => setState(() => _mode = valeur ?? _mode),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteController,
            enabled: !_actionEnCours,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Note (optionnel)',
              hintText: 'Ex. « pour la caisse du samedi »',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_actionEnCours || !etat.config.actif) ? null : _demander,
              icon: _actionEnCours
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: Text('Envoyer la demande — ${_montant(pack.prix)}'),
            ),
          ),
          if (!etat.config.actif)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'L\'assistant est désactivé : les demandes sont suspendues.',
                style: TextStyle(fontSize: 11.5, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 🪙 CORRECTIF 68 — OÙ SONT PASSÉS LES QUOTAS ?
  // ---------------------------------------------------------------------------

  /// Le solde de chaque collaborateur et le pool restant.
  ///
  /// Avant ce correctif, le patron voyait la liste des membres SANS leur
  /// solde : il ne pouvait donc pas savoir qui détenait quoi, ni décider quoi
  /// reprendre. Un quota attribué à un vendeur parti était perdu.
  Widget _carteAttributions() {
    final ThemeData theme = Theme.of(context);

    if (_attributions.estVide) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          'Aucun collaborateur ne détient de quotas pour le moment : le pool '
          'de l\'entreprise est intact.',
          style: TextStyle(fontSize: 12.5),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Pool restant : ${_attributions.poolDisponible}   •   '
            'chez les membres : ${_attributions.totalChezLesMembres}   •   '
            'déjà consommés : ${_attributions.totalConsomme}',
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          ..._attributions.attributions
              .map((AttributionQuota a) => _ligneAttribution(theme, a)),
          const SizedBox(height: 6),
          const Text(
            'Les quotas DÉJÀ CONSOMMÉS ne sont jamais reprenables : le service '
            'a été rendu par l\'assistant.',
            style: TextStyle(fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _ligneAttribution(ThemeData theme, AttributionQuota attribution) {
    final String auteur = (attribution.attribueParNom ?? '').trim().isEmpty
        ? ''
        : ' • attribué par ${attribution.attribueParNom}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  attribution.nom,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                Text(
                  '${attribution.quotasDisponibles} disponible(s) • '
                  '${attribution.quotasUtilisesTotal} consommé(s)$auteur',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (attribution.peutEtreReprise)
            TextButton(
              onPressed:
                  _actionEnCours ? null : () => _reprendre(attribution),
              child: const Text('Reprendre'),
            )
          else
            Text('tout consommé', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }

  /// Reprend des quotas non consommés et les rend au pool.
  Future<void> _reprendre(AttributionQuota attribution) async {
    final TextEditingController quantite =
        TextEditingController(text: '${attribution.quotasDisponibles}');

    final bool? confirme = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Reprendre des quotas ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${attribution.nom} détient encore '
                '${attribution.quotasDisponibles} quota(s) non consommé(s).'),
            const SizedBox(height: 12),
            TextField(
              controller: quantite,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quotas à reprendre',
                helperText: 'Ils retournent au pool de l\'entreprise.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Renoncer'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reprendre'),
          ),
        ],
      ),
    );

    if (confirme != true) {
      quantite.dispose();
      return;
    }

    final int? nombre = int.tryParse(quantite.text.trim());
    quantite.dispose();

    if (nombre == null || nombre < 1) {
      _snack('Indiquez un nombre de quotas valide.', erreur: true);
      return;
    }

    setState(() => _actionEnCours = true);
    try {
      final Map<String, dynamic> reponse = await _service.annulerAttribution(
        utilisateurId: attribution.utilisateurId,
        quotas: nombre,
      );
      _snack(
        '${reponse['quotas_repris'] ?? nombre} quota(s) repris à '
        '${attribution.nom} — pool : ${reponse['pool_restant'] ?? '?'}.',
      );
      await _charger();
    } on AgentServiceException catch (e) {
      _snack(e.message, erreur: true);
    } finally {
      if (mounted) setState(() => _actionEnCours = false);
    }
  }

  Widget _carteAttribution() {
    final EtatAgentIa etat = _etat ?? EtatAgentIa.defaut;
    final int pool = etat.pool?.quotasDisponibles ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Pool actuel : $pool quotas à distribuer.',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          AppDropdownField<String>(
            label: 'Collaborateur',
            value: _attributionMembre,
            hint: etat.collaborateurs.isEmpty
                ? 'Aucun collaborateur'
                : 'Choisir…',
            items: etat.collaborateurs
                .map(
                  (MembreQuota membre) => DropdownMenuItem<String>(
                    value: membre.id,
                    child: Text(
                      membre.nom,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: _actionEnCours
                ? null
                : (String? valeur) =>
                    setState(() => _attributionMembre = valeur),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _attributionController,
            enabled: !_actionEnCours,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Nombre de quotas à attribuer',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_actionEnCours || pool <= 0) ? null : _attribuer,
              icon: const Icon(Icons.family_restroom_rounded),
              label: Text(
                pool <= 0
                    ? 'Pool vide — demandez un pack d\'abord'
                    : 'Attribuer les quotas',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blocAchats() {
    if (_achats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Aucune demande pour le moment.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Column(
      children: _achats.map(_carteAchat).toList(growable: false),
    );
  }

  Widget _carteAchat(AchatQuotas achat) {
    final ThemeData theme = Theme.of(context);
    final EtatAgentIa etat = _etat ?? EtatAgentIa.defaut;

    final Color couleurStatut = achat.enAttente
        ? Colors.orange.shade800
        : achat.approuve
            ? Colors.green.shade700
            : Colors.blueGrey.shade600;
    final String libelleStatut = achat.enAttente
        ? 'En attente'
        : achat.approuve
            ? 'Approuvé'
            : 'Refusé';

    final bool peutValider = etat.estSuperAdmin && achat.enAttente;
    final bool peutPayer =
        achat.approuve && achat.impaye && (etat.estSuperAdmin || etat.estProprietaire);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${achat.nombreQuotas} quotas'
                  '${achat.utilisateurNom.isEmpty ? '' : ' — ${achat.utilisateurNom}'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: couleurStatut.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  libelleStatut,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: couleurStatut,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Text(
                _montant(achat.montantCdf),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  color: achat.paye ? Colors.green.shade700 : Colors.red.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: achat.paye
                      ? Colors.green.withValues(alpha: 0.12)
                      : Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: achat.paye
                        ? Colors.green.withValues(alpha: 0.5)
                        : Colors.red.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  achat.paye ? 'PAYÉ' : 'IMPAYÉ',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: achat.paye ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _modesPaiement[achat.modePaiement] ?? achat.modePaiement,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (achat.note != null && achat.note!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              'Note : ${achat.note}',
              style: TextStyle(
                fontSize: 11.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (achat.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                formatDateHeure(achat.createdAt),
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.8),
                ),
              ),
            ),
          if (peutValider || peutPayer) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                if (peutValider) ...<Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          _actionEnCours ? null : () => _valider(achat, true),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approuver'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _actionEnCours ? null : () => _valider(achat, false),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Refuser'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade700,
                        side: BorderSide(color: Colors.red.shade300),
                      ),
                    ),
                  ),
                ],
                if (peutPayer)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed:
                          _actionEnCours ? null : () => _marquerPaye(achat),
                      icon: const Icon(Icons.payments_rounded, size: 18),
                      label: const Text('Marquer payé'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade300),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
