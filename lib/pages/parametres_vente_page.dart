// lib/pages/parametres_vente_page.dart
//
// 🛒 MODULE 25 — « VENTES FLEXIBLES » : LE CONTRÔLE DU PROPRIÉTAIRE.
//
// Un seul écran, trois décisions et un rapport :
//   1. NÉGOCIATION  — autoriser, limiter (%), fixer un prix plancher,
//                     choisir les collaborateurs autorisés ;
//   2. RÉDUCTION    — autoriser, limiter (%), plafonner en montant ;
//   3. CADEAUX      — autoriser, choisir les collaborateurs autorisés ;
//   4. RAPPORTS     — ce que la flexibilité a rapporté et coûté.
//
// ⚠️ Les valeurs enregistrées ne sont JAMAIS la seule protection : le serveur
//    revérifie chaque vente (migration 0108). Cet écran sert à décider et à
//    expliquer, pas à sécuriser.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/article.dart';
import 'package:biashara_yangu/models/parametres_vente.dart';
import 'package:biashara_yangu/services/article_service.dart';
import 'package:biashara_yangu/services/supabase_service.dart';
import 'package:biashara_yangu/services/ventes_commerciales_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/session_manager.dart';

class ParametresVentePage extends StatefulWidget {
  const ParametresVentePage({super.key});

  @override
  State<ParametresVentePage> createState() => _ParametresVentePageState();
}

class _ParametresVentePageState extends State<ParametresVentePage> {
  final TextEditingController _negociationPct = TextEditingController();
  final TextEditingController _negociationMin = TextEditingController();
  final TextEditingController _reductionPct = TextEditingController();
  final TextEditingController _reductionMontant = TextEditingController();
  final TextEditingController _validationSeuil = TextEditingController();

  ParametresVente _parametres = ParametresVente.aucun;
  bool _chargement = true;
  bool _enregistrement = false;
  String? _erreur;
  String? _info;

  Map<String, dynamic> _resume = <String, dynamic>{};
  List<Map<String, dynamic>> _historique = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _collaborateurs = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _negociationPct.dispose();
    _negociationMin.dispose();
    _reductionPct.dispose();
    _reductionMontant.dispose();
    _validationSeuil.dispose();
    super.dispose();
  }

  SupabaseClient get _client => SupabaseService.instance.client;

  // ---------------------------------------------------------------------------
  // CHARGEMENT
  // ---------------------------------------------------------------------------

  Future<void> _charger() async {
    setState(() {
      _chargement = true;
      _erreur = null;
    });

    final ParametresVente p =
        await VentesCommercialesService.instance.charger(forcer: true);
    final Map<String, dynamic> resume =
        await VentesCommercialesService.instance.resume();
    final List<Map<String, dynamic>> historique =
        await VentesCommercialesService.instance.historique(limite: 30);
    final List<Map<String, dynamic>> collaborateurs = await _chargerEquipe();

    if (!mounted) return;
    setState(() {
      _parametres = p;
      _resume = resume;
      _historique = historique;
      _collaborateurs = collaborateurs;
      _negociationPct.text = p.negociationMaxPct.toStringAsFixed(0);
      _negociationMin.text = p.negociationPrixMin == null
          ? ''
          : p.negociationPrixMin!.toStringAsFixed(0);
      _reductionPct.text = p.reductionMaxPct.toStringAsFixed(0);
      _reductionMontant.text = p.reductionMaxMontant == null
          ? ''
          : p.reductionMaxMontant!.toStringAsFixed(0);
      _validationSeuil.text =
          p.validationSeuil == null ? '' : p.validationSeuil!.toStringAsFixed(0);
      _chargement = false;
    });
  }

  Future<List<Map<String, dynamic>>> _chargerEquipe() async {
    try {
      final String? uid = await SessionManager.getUserId();
      if (uid == null || uid.isEmpty) return const <Map<String, dynamic>>[];

      // 🧩 0181 — `parent_id` porte l'UTILISATEUR patron, jamais l'espace :
      //    l'ancien filtre `parent_id = <espace>` renvoyait une liste vide.
      //    La RLS borne ensuite la liste à l'entreprise active.
      String patron = uid;
      try {
        final dynamic moi = await _client
            .from('utilisateurs')
            .select('parent_id')
            .eq('id', uid)
            .maybeSingle();
        final String? parent =
            (moi is Map) ? moi['parent_id']?.toString() : null;
        if (parent != null && parent.isNotEmpty) patron = parent;
      } catch (e) {
        debugPrint('ParametresVentePage patron (ignoré) : $e');
      }

      final dynamic reponse = await _client
          .from('utilisateurs')
          .select('id, nom, prenom, role, valide')
          .eq('parent_id', patron)
          .order('nom', ascending: true);

      if (reponse is! List) return const <Map<String, dynamic>>[];
      return reponse
          .whereType<Map>()
          .map((Map e) => Map<String, dynamic>.from(e))
          .where((Map<String, dynamic> e) =>
              (e['valide'] as num?)?.toInt() != 0)
          .toList(growable: false);
    } catch (e) {
      debugPrint('ParametresVentePage équipe : $e');
      return const <Map<String, dynamic>>[];
    }
  }

  // ---------------------------------------------------------------------------
  // ENREGISTREMENT
  // ---------------------------------------------------------------------------

  double? _nombre(TextEditingController c) {
    final String texte = c.text.trim().replaceAll(',', '.');
    if (texte.isEmpty) return null;
    return double.tryParse(texte);
  }

  Future<void> _enregistrer() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _enregistrement = true;
      _erreur = null;
      _info = null;
    });

    try {
      final ParametresVente p = _parametres.copyWith(
        negociationMaxPct: _nombre(_negociationPct) ?? 0,
        negociationPrixMin: _nombre(_negociationMin),
        effacerPrixMin: _negociationMin.text.trim().isEmpty,
        reductionMaxPct: _nombre(_reductionPct) ?? 0,
        reductionMaxMontant: _nombre(_reductionMontant),
        effacerReductionMax: _reductionMontant.text.trim().isEmpty,
        validationSeuil: _nombre(_validationSeuil),
        effacerSeuil: _validationSeuil.text.trim().isEmpty,
      );

      await VentesCommercialesService.instance.enregistrer(p);
      if (!mounted) return;
      setState(() {
        _parametres = VentesCommercialesService.instance.courant;
        _info = 'Réglages enregistrés.';
      });
      await _charger();
    } on VentesCommercialesException catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _enregistrement = false);
    }
  }

  // ---------------------------------------------------------------------------
  // COLLABORATEURS AUTORISÉS
  // ---------------------------------------------------------------------------

  Future<void> _choisirCollaborateurs({
    required String titre,
    required List<String> selection,
    required void Function(List<String>) appliquer,
  }) async {
    final Set<String> choisies = selection.toSet();

    final List<String>? resultat = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setLocal) {
            return AlertDialog(
              title: Text(titre),
              content: SizedBox(
                width: double.maxFinite,
                child: _collaborateurs.isEmpty
                    ? const Text(
                        'Aucun collaborateur enregistré : toutes les personnes '
                        'autorisées à encaisser pourront utiliser cette option.')
                    : ListView(
                        shrinkWrap: true,
                        children: _collaborateurs.map((Map<String, dynamic> c) {
                          final String id = '${c['id']}';
                          final String nom = '${c['prenom'] ?? ''} '
                                  '${c['nom'] ?? ''}'
                              .trim();
                          return CheckboxListTile(
                            dense: true,
                            value: choisies.contains(id),
                            title: Text(nom.isEmpty ? 'Collaborateur' : nom),
                            subtitle: Text('${c['role'] ?? ''}'),
                            onChanged: (bool? coche) {
                              setLocal(() {
                                if (coche == true) {
                                  choisies.add(id);
                                } else {
                                  choisies.remove(id);
                                }
                              });
                            },
                          );
                        }).toList(growable: false),
                      ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuler'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(<String>[]),
                  child: const Text('Tous'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.of(context).pop(choisies.toList(growable: false)),
                  child: const Text('Appliquer'),
                ),
              ],
            );
          },
        );
      },
    );

    if (resultat == null || !mounted) return;
    setState(() => appliquer(resultat));
  }

  // ---------------------------------------------------------------------------
  // INTERFACE
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_chargement) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ventes flexibles'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Rafraîchir',
            onPressed: _charger,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          if (!_parametres.estProprietaire)
            _encadre(
              theme,
              'Seul le propriétaire peut modifier ces réglages. Vous les '
              'consultez en lecture seule.',
            ),
          _carteNegociation(theme),
          const SizedBox(height: 14),
          _carteReduction(theme),
          const SizedBox(height: 14),
          _carteCadeaux(theme),
          const SizedBox(height: 14),
          _carteBonusAuto(theme),
          const SizedBox(height: 14),
          _carteValidation(theme),
          if (_erreur != null) ...<Widget>[
            const SizedBox(height: 12),
            _encadre(theme, _erreur!, alerte: true),
          ],
          if (_info != null) ...<Widget>[
            const SizedBox(height: 12),
            _encadre(theme, _info!, succes: true),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: (!_parametres.estProprietaire || _enregistrement)
                  ? null
                  : _enregistrer,
              icon: _enregistrement
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.save_rounded),
              label: Text(_enregistrement ? 'Enregistrement…' : 'ENREGISTRER'),
            ),
          ),
          const SizedBox(height: 26),
          _carteRapports(theme),
          const SizedBox(height: 14),
          _carteHistorique(theme),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _carteNegociation(ThemeData theme) {
    return _carte(
      theme,
      icone: Icons.price_change_outlined,
      titre: 'Négociation du prix',
      sousTitre: 'Le vendeur peut baisser le prix d\'une ligne pendant la '
          'vente. Le prix du catalogue n\'est jamais modifié.',
      actif: _parametres.negociationActivee,
      onChange: (bool v) =>
          setState(() => _parametres = _parametres.copyWith(negociationActivee: v)),
      enfants: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _champNombre(
                _negociationPct,
                label: 'Réduction maximale par ligne (%)',
                suffixe: '%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _champNombre(
                _negociationMin,
                label: 'Prix minimum (facultatif)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _boutonCollaborateurs(
          theme,
          libelle: 'Qui peut négocier',
          selection: _parametres.negociationCollaborateurs,
          onPressed: () => _choisirCollaborateurs(
            titre: 'Autoriser la négociation',
            selection: _parametres.negociationCollaborateurs,
            appliquer: (List<String> ids) => _parametres =
                _parametres.copyWith(negociationCollaborateurs: ids),
          ),
        ),
      ],
    );
  }

  Widget _carteReduction(ThemeData theme) {
    return _carte(
      theme,
      icone: Icons.local_offer_outlined,
      titre: 'Réduction sur le panier',
      sousTitre: 'Une remise sur le total de la facture, en montant ou en '
          'pourcentage. Une seule réduction par vente.',
      actif: _parametres.reductionActivee,
      onChange: (bool v) =>
          setState(() => _parametres = _parametres.copyWith(reductionActivee: v)),
      enfants: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _champNombre(
                _reductionPct,
                label: 'Réduction maximale (%)',
                suffixe: '%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _champNombre(
                _reductionMontant,
                label: 'Plafond (facultatif)',
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _boutonCollaborateurs(
          theme,
          libelle: 'Qui peut réduire',
          selection: _parametres.reductionCollaborateurs,
          onPressed: () => _choisirCollaborateurs(
            titre: 'Autoriser les réductions',
            selection: _parametres.reductionCollaborateurs,
            appliquer: (List<String> ids) => _parametres =
                _parametres.copyWith(reductionCollaborateurs: ids),
          ),
        ),
      ],
    );
  }

  Widget _carteCadeaux(ThemeData theme) {
    return _carte(
      theme,
      icone: Icons.card_giftcard_rounded,
      titre: 'Cadeaux commerciaux',
      sousTitre: 'Offrir un ou plusieurs produits. Le cadeau sort du stock, '
          'n\'est pas facturé et n\'entre jamais dans le chiffre d\'affaires.',
      actif: _parametres.cadeauxActifs,
      onChange: (bool v) =>
          setState(() => _parametres = _parametres.copyWith(cadeauxActifs: v)),
      enfants: <Widget>[
        _boutonCollaborateurs(
          theme,
          libelle: 'Qui peut offrir',
          selection: _parametres.cadeauCollaborateurs,
          onPressed: () => _choisirCollaborateurs(
            titre: 'Autoriser les cadeaux',
            selection: _parametres.cadeauCollaborateurs,
            appliquer: (List<String> ids) =>
                _parametres = _parametres.copyWith(cadeauCollaborateurs: ids),
          ),
        ),
      ],
    );
  }

  Widget _carteBonusAuto(ThemeData theme) {
    final List<RegleBonusAuto> regles = _parametres.bonusAuto;

    return _carte(
      theme,
      icone: Icons.auto_awesome_rounded,
      titre: 'Bonus automatiques',
      sousTitre: 'Un achat d\'un montant donné déclenche un cadeau, sans '
          'intervention du vendeur. Chaque règle ne s\'applique qu\'une fois '
          'par vente.',
      actif: regles.isNotEmpty,
      onChange: (bool v) {
        if (!v) {
          setState(() => _parametres =
              _parametres.copyWith(bonusAuto: const <RegleBonusAuto>[]));
        } else {
          _ajouterRegleBonus();
        }
      },
      enfants: <Widget>[
        ...regles.map(
          (RegleBonusAuto regle) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Dès ${formatMontant(regle.seuilMontant)} d\'achat : '
                    '${_nombreTexte(regle.quantite)} × '
                    '${regle.produitNom ?? 'produit #${regle.produitId}'}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                IconButton(
                  tooltip: 'Retirer cette règle',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                  onPressed: _parametres.estProprietaire
                      ? () => setState(() {
                            _parametres = _parametres.copyWith(
                              bonusAuto: regles
                                  .where((RegleBonusAuto r) => r != regle)
                                  .toList(growable: false),
                            );
                          })
                      : null,
                ),
              ],
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _parametres.estProprietaire ? _ajouterRegleBonus : null,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Ajouter une règle'),
          ),
        ),
      ],
    );
  }

  /// Ajoute une règle de bonus : seuil, produit, quantité.
  Future<void> _ajouterRegleBonus() async {
    List<Article> articles;
    try {
      articles = await ArticleService.instance.getArticles();
    } catch (e) {
      if (mounted) setState(() => _erreur = 'Produits indisponibles : $e');
      return;
    }
    if (!mounted) return;

    final RegleBonusAuto? regle = await showDialog<RegleBonusAuto>(
      context: context,
      builder: (BuildContext context) => _DialogueBonusAuto(articles: articles),
    );
    if (regle == null || !mounted) return;

    setState(() {
      _parametres = _parametres.copyWith(
        cadeauxActifs: true,
        bonusAuto: <RegleBonusAuto>[..._parametres.bonusAuto, regle],
      );
    });
  }

  Widget _carteValidation(ThemeData theme) {    return _carte(
      theme,
      icone: Icons.verified_user_outlined,
      titre: 'Validation du responsable',
      sousTitre: 'Au-delà de ce montant accordé (négociation + réduction), '
          'seul le propriétaire peut conclure la vente.',
      actif: _parametres.validationSeuil != null,
      onChange: (bool v) {
        setState(() {
          if (!v) {
            _validationSeuil.clear();
            _parametres = _parametres.copyWith(effacerSeuil: true);
          }
        });
      },
      enfants: <Widget>[
        _champNombre(_validationSeuil, label: 'Seuil de validation'),
      ],
    );
  }

  Widget _carteRapports(ThemeData theme) {
    final bool complet = _resume['marge_incomplete'] != true;
    final Object? marge = _resume['marge'];

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.insights_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  '30 derniers jours',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            _ligneRapport(theme, 'Chiffre d\'affaires brut',
                _resume['ca_brut']),
            _ligneRapport(theme, 'Négociations accordées',
                _resume['montant_negociation'], negatif: true),
            _ligneRapport(theme, 'Réductions sur panier',
                _resume['reductions'], negatif: true),
            _ligneRapport(theme, 'Montant réellement facturé',
                _resume['montant_facture'], gras: true),
            const Divider(height: 18),
            _ligneRapport(theme, 'Ventes négociées',
                _resume['ventes_negociees'], nombre: true),
            _ligneRapport(theme, 'Ventes au prix normal',
                _resume['ventes_au_prix_normal'], nombre: true),
            _ligneRapport(theme, 'Cadeaux distribués',
                _resume['nb_cadeaux'], nombre: true),
            _ligneRapport(theme, 'Valeur des cadeaux',
                _resume['valeur_cadeaux']),
            _ligneRapport(theme, 'Coût des cadeaux',
                _resume['cout_cadeaux']),
            if (((_resume['nb_ventes_sous_cout'] as num?)?.toInt() ?? 0) > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: _encadre(
                  theme,
                  '⚠️ ${_resume['nb_ventes_sous_cout']} ligne(s) vendue(s) '
                  'sous le prix d\'achat : la négociation ou la réduction a '
                  'mangé la marge.',
                  alerte: true,
                ),
              ),
            const Divider(height: 18),
            if (!complet || marge == null)
              _encadre(
                theme,
                'Marge non calculée : renseignez le prix d\'achat de vos '
                'articles. Une marge sans coût connu serait un chiffre faux.',
              )
            else
              _ligneRapport(theme, 'Marge commerciale', marge, gras: true),
          ],
        ),
      ),
    );
  }

  Widget _carteHistorique(ThemeData theme) {
    if (_historique.isEmpty) {
      return _encadre(
        theme,
        'Aucune négociation, réduction ou cadeau enregistré pour le moment.',
      );
    }

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.history_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Historique des opérations',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 20),
            ..._historique.map((Map<String, dynamic> h) {
              final String numero = '${h['numero_vente'] ?? '—'}';
              final String vendeur = '${h['vendeur'] ?? 'Boutique'}';
              final double negoc = _d(h['negociation']);
              final double remise = _d(h['remise']);
              final double total = _d(h['total_final']);
              final int cadeaux = (h['cadeaux'] is List)
                  ? (h['cadeaux'] as List).length
                  : 0;

              final List<String> details = <String>[
                if (negoc > 0) 'négociation ${formatMontant(negoc)}',
                if (remise > 0) 'réduction ${formatMontant(remise)}',
                if (cadeaux > 0) '$cadeaux cadeau(x)',
              ];

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '$numero · $vendeur',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          formatMontant(total),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      details.isEmpty ? '—' : details.join(' · '),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PETITS WIDGETS
  // ---------------------------------------------------------------------------

  double _d(dynamic valeur) {
    if (valeur is num) return valeur.toDouble();
    return double.tryParse('${valeur ?? ''}') ?? 0;
  }

  Widget _carte(
    ThemeData theme, {
    required IconData icone,
    required String titre,
    required String sousTitre,
    required bool actif,
    required void Function(bool) onChange,
    List<Widget> enfants = const <Widget>[],
  }) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icone, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    titre,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Switch(
                  value: actif,
                  onChanged: _parametres.estProprietaire ? onChange : null,
                ),
              ],
            ),
            Text(
              sousTitre,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actif && enfants.isNotEmpty) ...<Widget>[
              const SizedBox(height: 14),
              ...enfants,
            ],
          ],
        ),
      ),
    );
  }

  Widget _champNombre(
    TextEditingController controleur, {
    required String label,
    String? suffixe,
  }) {
    return TextField(
      controller: controleur,
      enabled: _parametres.estProprietaire,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffixe,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
    );
  }

  Widget _boutonCollaborateurs(
    ThemeData theme, {
    required String libelle,
    required List<String> selection,
    required VoidCallback onPressed,
  }) {
    final String texte = selection.isEmpty
        ? 'Tous les collaborateurs'
        : '${selection.length} collaborateur(s)';

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            libelle,
            style: TextStyle(
              fontSize: 12.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _parametres.estProprietaire ? onPressed : null,
          icon: const Icon(Icons.group_outlined, size: 17),
          label: Text(texte, style: const TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }

  Widget _ligneRapport(
    ThemeData theme,
    String libelle,
    Object? valeur, {
    bool gras = false,
    bool negatif = false,
    bool nombre = false,
  }) {
    final String texte;
    if (valeur == null) {
      texte = '—';
    } else if (nombre) {
      texte = '${(valeur as num?)?.toInt() ?? 0}';
    } else {
      final double montant =
          valeur is num ? valeur.toDouble() : double.tryParse('$valeur') ?? 0;
      texte = '${negatif && montant > 0 ? '- ' : ''}${formatMontant(montant)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Expanded(
            child: Text(
              libelle,
              style: TextStyle(
                fontSize: 12.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            texte,
            style: TextStyle(
              fontSize: 13,
              fontWeight: gras ? FontWeight.w900 : FontWeight.w600,
              color: negatif ? Colors.orange.shade800 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _encadre(
    ThemeData theme,
    String texte, {
    bool alerte = false,
    bool succes = false,
  }) {
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

/// 🎁 Création d'une règle de bonus automatique.
class _DialogueBonusAuto extends StatefulWidget {
  const _DialogueBonusAuto({required this.articles});

  final List<Article> articles;

  @override
  State<_DialogueBonusAuto> createState() => _DialogueBonusAutoState();
}

class _DialogueBonusAutoState extends State<_DialogueBonusAuto> {
  final TextEditingController _seuil = TextEditingController();
  final TextEditingController _quantite = TextEditingController(text: '1');
  int? _produitId;
  String? _erreur;

  @override
  void dispose() {
    _seuil.dispose();
    _quantite.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Bonus automatique'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _seuil,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Montant d\'achat déclencheur',
                helperText: 'Ex. 10 000 : dès 10 000 d\'achat, le cadeau part.',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _produitId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Produit offert',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: widget.articles
                  .map((Article a) => DropdownMenuItem<int>(
                        value: a.id,
                        child: Text(a.nom, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(growable: false),
              onChanged: (int? v) => setState(() {
                _produitId = v;
                _erreur = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantite,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Quantité offerte',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            if (_erreur != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _erreur!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 12.5),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () {
            final double? seuil = double.tryParse(
                _seuil.text.trim().replaceAll(',', '.'));
            final double? quantite = double.tryParse(
                _quantite.text.trim().replaceAll(',', '.'));
            if (seuil == null || seuil <= 0) {
              setState(() => _erreur = 'Indiquez un montant d\'achat.');
              return;
            }
            if (_produitId == null) {
              setState(() => _erreur = 'Choisissez le produit offert.');
              return;
            }
            if (quantite == null || quantite <= 0) {
              setState(() => _erreur = 'Indiquez une quantité supérieure à 0.');
              return;
            }

            Article? article;
            for (final Article a in widget.articles) {
              if (a.id == _produitId) article = a;
            }

            Navigator.of(context).pop(
              RegleBonusAuto(
                seuilMontant: seuil,
                produitId: _produitId!,
                quantite: quantite,
                produitNom: article?.nom,
              ),
            );
          },
          child: const Text('Ajouter'),
        ),
      ],
    );
  }
}

/// « 12 » pour une quantité entière, « 1,5 » sinon.
String _nombreTexte(double valeur) {
  if (valeur == valeur.roundToDouble()) return valeur.toStringAsFixed(0);
  return valeur
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}
