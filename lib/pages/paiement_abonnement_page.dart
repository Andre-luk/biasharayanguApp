// lib/pages/paiement_abonnement_page.dart
//
// MODULE 3 — Écran « Enregistrer un paiement » (moteur d'abonnement).
//
// Champs : montant, type (AVANCE / SOLDE / RENOUVELLEMENT), mode de paiement,
// note. L'enregistrement passe par `AbonnementService.enregistrerPaiement` :
// la base historise dans `paiements_abonnements_laperle`, recalcule le solde,
// le statut et les dates dans la même transaction.
//
// Un aperçu montre, avant validation, ce que deviendra l'abonnement
// (nouveau solde, statut, date d'expiration).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/entreprise.dart';
import 'package:biashara_yangu/models/paiement_laperle.dart';
import 'package:biashara_yangu/models/statut_abonnement.dart';
import 'package:biashara_yangu/services/abonnement_service.dart';
import 'package:biashara_yangu/services/paiement_platforme_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class PaiementAbonnementPage extends StatefulWidget {
  const PaiementAbonnementPage({super.key, this.entreprise, this.entrepriseId});

  /// Entreprise concernée par le paiement.
  final Entreprise? entreprise;

  /// Identifiant utilisé en secours lorsque l'écran est ouvert par URL directe.
  final String? entrepriseId;

  @override
  State<PaiementAbonnementPage> createState() => _PaiementAbonnementPageState();
}

class _PaiementAbonnementPageState extends State<PaiementAbonnementPage> {
  final AbonnementService _service = AbonnementService.instance;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _montantController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  Entreprise? _entreprise;
  SoldeAbonnement? _solde;
  int _dureeAbonnementJours = 30;

  /// Prix que le serveur facturera pour le PROCHAIN cycle.
  ///
  /// Indispensable quand l'abonnement est échu : `montant_total_du` décrit le
  /// cycle précédent, or le moteur en ouvre un nouveau au prix mensuel actuel.
  /// Proposer l'ancien montant faisait refuser le paiement
  /// (« le montant dépasse le solde restant »).
  double _prixCycle = 0;

  TypePaiement _type = TypePaiement.avance;
  String _modePaiement = modesPaiementDisponibles.first;

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreurChargement;

  @override
  void initState() {
    super.initState();
    _entreprise = widget.entreprise;
    _initialiser();
  }

  @override
  void dispose() {
    _montantController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _initialiser() async {
    final String? id = widget.entrepriseId ?? _entreprise?.id;

    if (id == null) {
      setState(() {
        _erreurChargement = "Identifiant de l'entreprise manquant.";
        _chargement = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _chargement = true;
      _erreurChargement = null;
    });

    String? messageErreur;
    Entreprise? entreprise = widget.entreprise;
    int duree = 30;

    try {
      if (entreprise == null) {
        entreprise = await _service.getEntreprise(id);
      }

      if (entreprise == null) {
        messageErreur =
            'Cette entreprise est introuvable. Elle a peut-être été supprimée.';
      } else {
        duree = await _service.getDureeAbonnement(entreprise.groupeTarifaireId);
      }
    } on AbonnementServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('PaiementAbonnementPage._initialiser: $e\n$st');
      messageErreur =
          'Une erreur inattendue est survenue lors du chargement du formulaire.';
    }

    if (!mounted) return;

    if (messageErreur != null || entreprise == null) {
      setState(() {
        _erreurChargement =
            messageErreur ?? 'Entreprise introuvable pour ce paiement.';
        _chargement = false;
      });
      return;
    }

    final SoldeAbonnement solde =
        AbonnementService.soldeDepuisEntreprise(entreprise);

    // ⚠️ Un abonnement échu est RENOUVELÉ, pas « soldé » : le moteur ouvre un
    // nouveau cycle au prix mensuel actuel. On demande donc à la base le prix
    // du prochain cycle, sinon l'écran propose le montant du cycle précédent
    // et le serveur refuse le paiement.
    final bool nouveauCycle = AbonnementService.ouvreNouveauCycle(solde);
    double prixCycle = 0;
    if (nouveauCycle) {
      prixCycle = await _service.prixDuCycle(entreprise.id);
    }

    // La règle vit dans le service (testée) : jamais le montant du cycle
    // précédent quand un nouveau cycle va s'ouvrir.
    final double montantPropose = AbonnementService.montantAEncaisser(
      solde: solde,
      prixCycle: prixCycle,
    );

    setState(() {
      _entreprise = entreprise;
      _solde = solde;
      _prixCycle = prixCycle;
      _dureeAbonnementJours = duree;
      _chargement = false;

      _montantController.text =
          montantPropose > 0 ? montantPropose.toStringAsFixed(0) : '';

      _type = nouveauCycle
          ? TypePaiement.renouvellement
          : (montantPropose > 0 && montantPropose <= solde.solde
              ? TypePaiement.solde
              : TypePaiement.avance);
    });
  }

  // ---------------------------------------------------------------------------
  // LECTURE / VALIDATION
  // ---------------------------------------------------------------------------

  /// Accepte « 15 000 », « 15000 » et « 15000,50 ».
  double? _analyserMontant(String texte) {
    final String nettoye = texte
        .replaceAll(' ', '')
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll(',', '.');

    if (nettoye.isEmpty) return null;
    return double.tryParse(nettoye);
  }

  double get _montantSaisi => _analyserMontant(_montantController.text) ?? 0;

  /// Plafond du paiement : le solde restant, ou le montant de l'abonnement
  /// lorsqu'un nouveau cycle doit être ouvert (renouvellement).
  double get _plafond {
    final SoldeAbonnement? solde = _solde;
    if (solde == null) return 0;
    if (_estRenouvellement) {
      return _prixCycle > 0 ? _prixCycle : solde.total;
    }
    return solde.solde;
  }

  /// `true` quand le paiement va ouvrir un NOUVEAU cycle : le solde du cycle
  /// courant est nul, ou l'abonnement est échu.
  bool get _estRenouvellement {
    final SoldeAbonnement? solde = _solde;
    if (solde == null) return false;
    return solde.solde <= 0 || solde.statut == StatutAbonnement.expire;
  }

  /// Montant sur lequel le moteur va imputer ce paiement.
  double get _baseImputation {
    final SoldeAbonnement? solde = _solde;
    if (solde == null) return 0;
    if (_estRenouvellement) {
      return _prixCycle > 0 ? _prixCycle : solde.total;
    }
    return solde.solde;
  }

  /// Aperçu du statut après paiement (reproduit la règle de la base).
  StatutAbonnement? get _statutApres {
    final SoldeAbonnement? solde = _solde;
    if (solde == null) return null;

    final double montant = _montantSaisi;
    final bool complet = _estRenouvellement
        ? montant >= solde.total - 0.001
        : montant >= solde.solde - 0.001;

    if (complet) {
      // Un compte suspendu n'est jamais réactivé par un paiement.
      return solde.statut == StatutAbonnement.suspendu
          ? StatutAbonnement.suspendu
          : StatutAbonnement.actif;
    }

    if (solde.statut == StatutAbonnement.expire) {
      return StatutAbonnement.enAttenteComplement;
    }
    return solde.statut;
  }

  /// Nouvelle date d'expiration si le paiement solde le cycle.
  DateTime? get _expirationApres {
    final SoldeAbonnement? solde = _solde;
    if (solde == null) return null;
    if (_statutApres != StatutAbonnement.actif) return null;

    return AbonnementService.calculerFinCycle(
      statut: solde.statut,
      dateExpiration: solde.dateExpiration,
      dureeJours: _dureeAbonnementJours,
    );
  }

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();

    if (!(_formKey.currentState?.validate() ?? false)) {
      _afficherMessage(
        'Veuillez corriger les champs signalés en rouge.',
        estErreur: true,
      );
      return;
    }

    final Entreprise? entreprise = _entreprise;
    if (entreprise == null) return;

    // 💳 AUDIT DES PAIEMENTS — MOBILE MONEY = SERDIPAY, JAMAIS LA CAISSE.
    //  Avant ce correctif, choisir « Mobile Money » appelait directement le
    //  moteur d'abonnement : l'abonnement était activé sans transaction.
    //  Désormais le seul chemin est l'écran SerdiPay (montant calculé en base,
    //  crédit après confirmation du webhook).
    if (PaiementPlatformeService.estMobileMoney(_modePaiement)) {
      final bool paye = await PaiementPlatformeService.payerParMobileMoney(
        context,
        entrepriseId: entreprise.id,
        libelleEntreprise: entreprise.nom,
      );
      if (!mounted) return;
      if (paye) Navigator.of(context).pop(true);
      return;
    }

    // Aucun contrat d'acquisition carte : on ne fait pas semblant d'encaisser.
    if (!PaiementPlatformeService.estEspeces(_modePaiement) &&
        _modePaiement.toLowerCase().contains('carte')) {
      _afficherMessage(
        PaiementPlatformeService.messageModeIndisponible(_modePaiement),
        estErreur: true,
      );
      return;
    }

    setState(() => _enregistrement = true);

    String? messageErreur;
    try {
      await _service.enregistrerPaiement(
        entrepriseId: entreprise.id,
        montant: _montantSaisi,
        type: _type,
        modePaiement: _modePaiement,
        note: _noteController.text,
      );
    } on AbonnementServiceException catch (e) {
      messageErreur = e.message;
    } catch (e, st) {
      debugPrint('PaiementAbonnementPage._enregistrer: $e\n$st');
      messageErreur =
          "Une erreur inattendue est survenue lors de l'enregistrement.";
    }

    if (!mounted) return;

    if (messageErreur != null) {
      setState(() => _enregistrement = false);
      _afficherMessage(messageErreur, estErreur: true);
      return;
    }

    Navigator.of(context).pop(true);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  void _afficherMessage(String message, {bool estErreur = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: estErreur
            ? Colors.red.shade700
            : Theme.of(context).colorScheme.primary,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool pret = !_chargement && _erreurChargement == null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Enregistrer un paiement',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: _construireCorps(theme),
      bottomNavigationBar: pret ? _barreActions() : null,
    );
  }

  Widget _construireCorps(ThemeData theme) {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erreurChargement != null) {
      return _vueErreur(theme);
    }

    final SoldeAbonnement? solde = _solde;
    final Entreprise? entreprise = _entreprise;
    if (solde == null || entreprise == null) {
      return _vueErreur(theme);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _recapitulatif(theme, entreprise, solde),
            const SizedBox(height: 20),
            _titreSection(theme, 'Paiement', Icons.payments_rounded),
            const SizedBox(height: 12),
            TextFormField(
              controller: _montantController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9., ]')),
              ],
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                labelText: 'Montant encaissé *',
                suffixText: deviseParDefaut,
                prefixIcon: const Icon(Icons.attach_money_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              validator: (String? valeur) {
                final String texte = (valeur ?? '').trim();
                if (texte.isEmpty) {
                  return 'Veuillez saisir le montant encaissé.';
                }

                final double? analyse = _analyserMontant(texte);
                if (analyse == null) {
                  return 'Montant invalide : utilisez uniquement des chiffres.';
                }
                if (analyse <= 0) {
                  return 'Le montant doit être supérieur à zéro.';
                }
                if (analyse > _plafond + 0.001) {
                  return _estRenouvellement
                      ? 'Le montant dépasse le prix de l\'abonnement '
                          '(${formatMontant(_plafond)}).'
                      : 'Le montant dépasse le solde restant '
                          '(${formatMontant(_plafond)}).';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            AppDropdownField<TypePaiement>(
              label: 'Type de paiement *',
              value: _type,
              prefixIcon: Icons.category_outlined,
              items: TypePaiement.values
                  .map(
                    (TypePaiement type) => DropdownMenuItem<TypePaiement>(
                      value: type,
                      child: Text(type.libelle),
                    ),
                  )
                  .toList(),
              onChanged: (TypePaiement? valeur) {
                if (valeur == null) return;
                setState(() => _type = valeur);
              },
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                _descriptionType(_type),
                style: TextStyle(
                  fontSize: 11.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 14),
            AppDropdownField<String>(
              label: 'Mode de paiement',
              value: _modePaiement,
              prefixIcon: Icons.account_balance_wallet_outlined,
              items: modesPaiementDisponibles
                  .map(
                    (String mode) => DropdownMenuItem<String>(
                      value: mode,
                      child: Text(mode),
                    ),
                  )
                  .toList(),
              onChanged: (String? valeur) {
                if (valeur == null) return;
                setState(() => _modePaiement = valeur);
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _noteController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Note (facultative)',
                hintText: 'Ex. : reçu n° 123, paiement partiel convenu…',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 34),
                  child: Icon(Icons.notes_rounded),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _apercu(theme, solde),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  String _descriptionType(TypePaiement type) {
    switch (type) {
      case TypePaiement.avance:
        return "Premier versement (acompte) : le statut reste « Essai 7 jours » "
            "tant que le solde n'est pas intégralement réglé.";
      case TypePaiement.solde:
        return "Règlement du reste à payer : l'abonnement devient « Actif » "
            'dès que le solde atteint zéro.';
      case TypePaiement.renouvellement:
        return "Ouvre un nouveau cycle : le paiement repart du montant de la "
            'grille tarifaire de l\'entreprise.';
    }
  }

  Widget _recapitulatif(
    ThemeData theme,
    Entreprise entreprise,
    SoldeAbonnement solde,
  ) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              entreprise.nom.isEmpty ? 'Entreprise sans nom' : entreprise.nom,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Divider(height: 20),
            _ligneRecap('Statut actuel', solde.statut.libelle),
            _ligneRecap(
              _estRenouvellement ? 'Cycle précédent' : 'Montant total dû',
              formatMontant(solde.total),
            ),
            _ligneRecap('Déjà payé', formatMontant(solde.paye)),
            if (_estRenouvellement && _prixCycle > 0) ...<Widget>[
              _ligneRecap(
                'Nouveau cycle à encaisser',
                formatMontant(_prixCycle),
                accent: true,
              ),
            ] else ...<Widget>[
              _ligneRecap(
                'Solde restant',
                formatMontant(solde.solde),
                accent: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _apercu(ThemeData theme, SoldeAbonnement solde) {
    final double montant = _montantSaisi;
    final double base = _baseImputation;
    final double nouveauSolde = base - montant > 0 ? base - montant : 0;
    final StatutAbonnement? statutApres = _statutApres;
    final DateTime? expirationApres = _expirationApres;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.preview_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Après ce paiement',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const Divider(height: 22),
            _ligneRecap(
              'Nouveau solde restant',
              montant > 0 ? formatMontant(nouveauSolde) : '—',
              accent: true,
            ),
            _ligneRecap(
              'Statut',
              statutApres?.libelle ?? '—',
            ),
            _ligneRecap(
              "Nouvelle date d'expiration",
              expirationApres == null ? '—' : formatDate(expirationApres),
            ),
            if (_estRenouvellement) ...[
              const SizedBox(height: 8),
              Text(
                "L'abonnement est soldé : ce paiement ouvre un nouveau cycle "
                "de $_dureeAbonnementJours jour"
                "${_dureeAbonnementJours > 1 ? 's' : ''}. Un règlement complet "
                "repart de la date d'expiration si elle est encore future.",
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _ligneRecap(String libelle, String valeur, {bool accent = false}) {
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(libelle, style: const TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              valeur,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: accent ? FontWeight.bold : FontWeight.w600,
                color: accent ? theme.colorScheme.primary : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _titreSection(ThemeData theme, String titre, IconData icone) {
    return Row(
      children: [
        Icon(icone, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Text(
          titre,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }

  Widget _barreActions() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _enregistrement
                    ? null
                    : () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Annuler'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: _enregistrement ? null : _enregistrer,
                icon: _enregistrement
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label:
                    Text(_enregistrement ? 'Enregistrement...' : 'Enregistrer'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vueErreur(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Formulaire indisponible',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _erreurChargement!,
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _initialiser,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Retour'),
            ),
          ],
        ),
      ),
    );
  }
}
