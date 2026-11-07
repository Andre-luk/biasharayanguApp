// lib/pages/identite_etablissement_page.dart
//
// 🏷️ MODULE 27 — L'IDENTITÉ QUI APPARAÎT SUR LES FACTURES.
//
// Une facture professionnelle commence par l'en-tête : le nom, l'adresse, le
// téléphone, le logo, et — quand le commerçant en possède — le numéro RCCM et
// l'identifiant national. Ces mentions sont FACULTATIVES : laissées vides,
// elles ne s'affichent simplement pas (aucune valeur inventée).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/services/etablissement_service.dart';

class IdentiteEtablissementPage extends StatefulWidget {
  const IdentiteEtablissementPage({super.key});

  @override
  State<IdentiteEtablissementPage> createState() =>
      _IdentiteEtablissementPageState();
}

class _IdentiteEtablissementPageState
    extends State<IdentiteEtablissementPage> {
  final TextEditingController _nom = TextEditingController();
  final TextEditingController _adresse = TextEditingController();
  final TextEditingController _quartier = TextEditingController();
  final TextEditingController _avenue = TextEditingController();
  final TextEditingController _numero = TextEditingController();
  final TextEditingController _repere = TextEditingController();
  final TextEditingController _telephone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _rccm = TextEditingController();
  final TextEditingController _idNational = TextEditingController();

  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;
  String? _info;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _nom,
      _adresse,
      _quartier,
      _avenue,
      _numero,
      _repere,
      _telephone,
      _email,
      _rccm,
      _idNational,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    final Etablissement e =
        await EtablissementService.instance.charger(forcer: true);
    if (!mounted) return;

    setState(() {
      _nom.text = e.nom;
      _adresse.text = e.adresse ?? '';
      _quartier.text = e.quartier ?? '';
      _avenue.text = e.avenue ?? '';
      _numero.text = e.numero ?? '';
      _repere.text = e.repere ?? '';
      _telephone.text = e.telephone ?? '';
      _email.text = e.email ?? '';
      _rccm.text = e.rccm ?? '';
      _idNational.text = e.idNational ?? '';
      _chargement = false;
    });
  }

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();
    if (_nom.text.trim().isEmpty) {
      setState(() => _erreur = 'Le nom de l\'établissement est obligatoire.');
      return;
    }

    setState(() {
      _enregistrement = true;
      _erreur = null;
      _info = null;
    });

    try {
      await EtablissementService.instance.enregistrer(
        nom: _nom.text.trim(),
        adresse: _adresse.text.trim(),
        quartier: _quartier.text.trim(),
        avenue: _avenue.text.trim(),
        numero: _numero.text.trim(),
        repere: _repere.text.trim(),
        telephone: _telephone.text.trim(),
        email: _email.text.trim(),
        rccm: _rccm.text.trim(),
        idNational: _idNational.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _info = 'Identité enregistrée : les prochaines factures l\'utiliseront.';
      });
    } on EtablissementException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Identité de l\'établissement')),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                Text(
                  'Ces informations apparaissent en tête de vos factures. '
                  'Les champs vides sont simplement masqués.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),

                _champ(_nom, 'Nom commercial *', icone: Icons.storefront_rounded),
                const SizedBox(height: 12),
                _champ(_adresse, 'Adresse (rue)',
                    icone: Icons.location_on_outlined),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(child: _champ(_quartier, 'Quartier')),
                    const SizedBox(width: 10),
                    Expanded(child: _champ(_avenue, 'Avenue')),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(child: _champ(_numero, 'N°')),
                    const SizedBox(width: 10),
                    Expanded(child: _champ(_repere, 'Point de repère')),
                  ],
                ),
                const SizedBox(height: 12),
                _champ(_telephone, 'Téléphone',
                    icone: Icons.phone_outlined,
                    clavier: TextInputType.phone,
                    format: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9+ ()-]')),
                    ]),
                const SizedBox(height: 12),
                _champ(_email, 'E-mail',
                    icone: Icons.mail_outline_rounded,
                    clavier: TextInputType.emailAddress),

                const SizedBox(height: 22),
                Text(
                  'Mentions légales (facultatives)',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'Renseignez-les si votre entreprise en possède : elles '
                  'renforcent la valeur juridique de la facture. Laissez vide '
                  'sinon — rien ne sera affiché.',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                _champ(_rccm, 'Numéro RCCM',
                    icone: Icons.badge_outlined,
                    majuscules: true),
                const SizedBox(height: 12),
                _champ(_idNational, 'Identifiant national / ID fiscal',
                    icone: Icons.fingerprint_rounded,
                    majuscules: true),

                if (_erreur != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _bandeau(theme, _erreur!, alerte: true),
                ],
                if (_info != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _bandeau(theme, _info!, succes: true),
                ],

                const SizedBox(height: 20),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _enregistrement ? null : _enregistrer,
                    icon: _enregistrement
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                        _enregistrement ? 'Enregistrement…' : 'ENREGISTRER'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _champ(
    TextEditingController controleur,
    String label, {
    IconData? icone,
    TextInputType? clavier,
    List<TextInputFormatter>? format,
    bool majuscules = false,
  }) {
    return TextField(
      controller: controleur,
      keyboardType: clavier,
      inputFormatters: format,
      textCapitalization:
          majuscules ? TextCapitalization.characters : TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icone == null ? null : Icon(icone, size: 19),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }

  Widget _bandeau(ThemeData theme, String texte,
      {bool alerte = false, bool succes = false}) {
    final Color fond = alerte
        ? Colors.red.withValues(alpha: 0.08)
        : succes
            ? Colors.green.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fond,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(texte, style: const TextStyle(fontSize: 12.5)),
    );
  }
}
