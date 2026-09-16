// lib/pages/dette_form_page.dart
//
// MODULE 10 — FORMULAIRE « NOUVELLE DETTE ».
//
// Le client est choisi dans le répertoire (`public.clients`) ; l'écriture
// passe par `rpc_dette_creer` (droit `caisse/creer`, journalisée).

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:biashara_yangu/models/dette_client.dart';
import 'package:biashara_yangu/services/dette_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/widgets/app_dropdown_field.dart';

class DetteFormPage extends StatefulWidget {
  const DetteFormPage({super.key});

  @override
  State<DetteFormPage> createState() => _DetteFormPageState();
}

class _DetteFormPageState extends State<DetteFormPage> {
  final DetteService _dettes = DetteService.instance;

  final TextEditingController _montantCtrl = TextEditingController();

  List<ClientDetteOption>? _clients;
  bool _chargementClients = true;
  String? _erreurClients;

  ClientDetteOption? _client;
  DateTime? _echeance;
  bool _enregistrement = false;

  @override
  void initState() {
    super.initState();
    _chargerClients();
  }

  @override
  void dispose() {
    _montantCtrl.dispose();
    super.dispose();
  }

  Future<void> _chargerClients() async {
    setState(() {
      _chargementClients = true;
      _erreurClients = null;
    });
    try {
      final List<ClientDetteOption> clients = await _dettes.listerClients();
      if (!mounted) return;
      setState(() => _clients = clients);
    } on DetteServiceException catch (e) {
      if (!mounted) return;
      setState(() => _erreurClients = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _erreurClients = 'Impossible de charger les clients : $e');
    } finally {
      if (mounted) setState(() => _chargementClients = false);
    }
  }

  double get _montant {
    final String texte =
        _montantCtrl.text.replaceAll(' ', '').replaceAll(',', '.');
    return double.tryParse(texte) ?? 0;
  }

  Future<void> _choisirEcheance() async {
    final DateTime maintenant = DateTime.now();
    final DateTime aujourdHui =
        DateTime(maintenant.year, maintenant.month, maintenant.day);
    final DateTime? choix = await showDatePicker(
      context: context,
      initialDate: _echeance ?? aujourdHui.add(const Duration(days: 7)),
      firstDate: aujourdHui,
      lastDate: DateTime(maintenant.year + 5),
      helpText: 'Date d\'échéance (facultative)',
    );
    if (choix != null) setState(() => _echeance = choix);
  }

  Future<void> _enregistrer() async {
    final ClientDetteOption? client = _client;
    if (client == null) {
      _afficherErreur('Choisissez le client concerné.');
      return;
    }
    if (_montant <= 0) {
      _afficherErreur('Le montant de la dette doit être supérieur à zéro.');
      return;
    }

    setState(() => _enregistrement = true);
    try {
      final DetteClient dette = await _dettes.creerDette(
        clientId: client.id,
        montantTotal: _montant,
        dateEcheance: _echeance,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Dette de ${formatMontant(dette.montantTotal)} enregistrée pour ${dette.client}.',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      Navigator.of(context).pop(true);
    } on DetteServiceException catch (e) {
      if (!mounted) return;
      _afficherErreur(e.message);
    } catch (e) {
      if (!mounted) return;
      _afficherErreur('Erreur inattendue : $e');
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  void _afficherErreur(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Nouvelle dette',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: false,
      ),
      body: _construireCorps(theme),
    );
  }

  Widget _construireCorps(ThemeData theme) {
    if (_chargementClients) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_erreurClients != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.cloud_off_rounded,
                  size: 56, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_erreurClients!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _chargerClients,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final List<ClientDetteOption> clients = _clients ?? <ClientDetteOption>[];

    if (clients.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.people_alt_rounded,
                  size: 56, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text(
                'Aucun client dans votre répertoire :\ncréez d\'abord un client pour enregistrer une dette.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => context.push('/main/clients'),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Ouvrir les clients'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        AppDropdownField<ClientDetteOption>(
          label: 'Client *',
          value: _client,
          hint: 'Choisir un client…',
          prefixIcon: Icons.person_rounded,
          items: clients
              .map(
                (ClientDetteOption client) => DropdownMenuItem<ClientDetteOption>(
                  value: client,
                  child: Text(
                    client.telephone == null || client.telephone!.isEmpty
                        ? client.nom
                        : '${client.nom} · ${client.telephone}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(growable: false),
          onChanged: (ClientDetteOption? valeur) {
            setState(() => _client = valeur);
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _montantCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Montant total de la dette (CDF) *',
            hintText: 'Ex. : 25 000',
            prefixIcon: const Icon(Icons.payments_rounded),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          child: ListTile(
            leading: const Icon(Icons.event_available_rounded),
            title: const Text('Échéance de règlement (facultatif)'),
            subtitle: Text(
              _echeance == null
                  ? 'Aucune échéance — utile pour les relances.'
                  : formatDate(_echeance),
            ),
            trailing: _echeance == null
                ? const Icon(Icons.edit_calendar_rounded)
                : IconButton(
                    tooltip: 'Retirer l\'échéance',
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () => setState(() => _echeance = null),
                  ),
            onTap: _choisirEcheance,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 52,
          child: FilledButton.icon(
            onPressed: _enregistrement ? null : _enregistrer,
            icon: _enregistrement
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _enregistrement ? 'Enregistrement…' : 'Enregistrer la dette',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Les règlements se font ensuite depuis l\'écran « Dettes clients » '
          '(paiements partiels acceptés) ; chaque règlement met à jour le '
          'statut automatiquement.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
