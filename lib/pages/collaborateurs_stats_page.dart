// lib/pages/collaborateurs_stats_page.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:biashara_yangu/models/collaborateur_stats.dart';
import 'package:biashara_yangu/models/rapport_vendeurs.dart';
import 'package:biashara_yangu/models/utilisateur.dart';
import 'package:biashara_yangu/models/vente.dart';
// 🧑‍🤝‍🧑 CORRECTIF 179 — rapport serveur par collaborateur (stock au moment
// de chaque vente, chaîne « qui a vendu avant »).
import 'package:biashara_yangu/services/rapport_vendeurs_service.dart';
// 📅 CORRECTIF 179 — la date de référence vient du SERVEUR (Lubumbashi) :
// deux téléphones différents voient forcément les mêmes chiffres.
import 'package:biashara_yangu/services/date_locale_service.dart';
// 🧩 0181 — les données métier sont rattachées à l'ESPACE de travail actif.
import 'package:biashara_yangu/services/scope_donnees.dart';
// 🪙 MODULE 18 — montants formatés dans la devise de l'entreprise.
import 'package:biashara_yangu/utils/format_utils.dart';
import 'package:biashara_yangu/utils/partage_pdf.dart';

enum StatsPeriod { today, thisWeek, thisMonth, custom }

class CollaborateursStatsPage extends StatefulWidget {
  final String ownerId;
  const CollaborateursStatsPage({super.key, required this.ownerId});

  @override
  State<CollaborateursStatsPage> createState() =>
      _CollaborateursStatsPageState();
}

class _SellerAgg {
  int ventesCount = 0;
  double totalAmount = 0.0;
  final List<VenteDetail> details = [];

  void add(VenteDetail detail) {
    ventesCount += 1;
    totalAmount += detail.prixTotal;
    details.add(detail);
  }
}

class _CollaborateursStatsPageState extends State<CollaborateursStatsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// 🧩 0181 — l'espace de travail effectif (celui que la RLS compare à
  /// `owner_id`). `widget.ownerId` reste l'UTILISATEUR patron (pour
  /// `parent_id` et le nom du patron).
  String get _ownerEspace =>
      ScopeDonnees.proprioPourEcriture ??
      ScopeDonnees.espaceActif ??
      widget.ownerId;

  bool _isLoading = true;
  String? _errorMessage;

  List<CollaborateurStats> _stats = [];
  Map<String, Utilisateur> _sellers = {};
  Map<int, String> _productNames = {};
  Map<String, List<VenteDetail>> _detailsBySeller = {};

  /// 🧑‍🤝‍🧑 CORRECTIF 179 — rapport serveur (stock avant/après chaque vente).
  RapportVendeurs? _rapport;

  /// Renseigné si le rapport serveur n'a pas pu être chargé : l'écran reste
  /// utilisable avec les totaux locaux, et l'utilisateur sait pourquoi le
  /// stock n'est pas affiché.
  String? _stockIndisponible;

  StatsPeriod _selectedPeriod = StatsPeriod.today;
  DateTimeRange? _selectedRange;

  /// 📅 Jour de référence : celui du SERVEUR (Lubumbashi). Tant qu'il n'est
  /// pas chargé, on utilise l'horloge de l'appareil.
  DateTime _jourReference = DateTime.now();

  Utilisateur? _ownerProfile;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  String _formatQty(num qty) {
    return qty == qty.truncateToDouble()
        ? qty.toInt().toString()
        : qty.toStringAsFixed(2);
  }

  String _formatRangeLabel(DateTimeRange range) {
    final start = range.start;
    final endInclusive = range.end.subtract(const Duration(days: 1));

    final startStr = DateFormat('dd/MM/yyyy').format(start);
    final endStr = DateFormat('dd/MM/yyyy').format(endInclusive);

    if (start.year == endInclusive.year &&
        start.month == endInclusive.month &&
        start.day == endInclusive.day) {
      return startStr;
    }

    return '$startStr - $endStr';
  }

  String _displayName(Utilisateur u) {
    final prenom = u.prenom.trim();
    final nom = u.nom.trim();

    if (prenom.isEmpty) return nom;
    return '$prenom $nom';
  }

  String _sellerLabel(String sellerId) {
    // 🧑‍🤝‍🧑 CORRECTIF 179 — le serveur nomme « proprietaire » les ventes non
    // attribuées à un collaborateur (vente faite par le patron lui-même).
    if (sellerId == 'proprietaire') return 'Patron';

    if (_ownerProfile != null && sellerId == _ownerProfile!.id) {
      return 'Patron';
    }

    final user = _sellers[sellerId];
    if (user != null) {
      return _displayName(user);
    }

    return 'Inconnu';
  }

  DateTimeRange _calculateRange(StatsPeriod period) {
    // ⚠️ Plus de `DateTime.now()` ici : la référence est la date du serveur,
    // sinon un téléphone mal réglé demanderait une autre période.
    final DateTime maintenant = _jourReference;
    final DateTime todayStart =
        DateTime(maintenant.year, maintenant.month, maintenant.day);

    switch (period) {
      case StatsPeriod.today:
        return DateTimeRange(
          start: todayStart,
          end: todayStart.add(const Duration(days: 1)),
        );

      case StatsPeriod.thisWeek:
        final startOfWeek =
            todayStart.subtract(Duration(days: maintenant.weekday - 1));
        return DateTimeRange(
          start: startOfWeek,
          end: todayStart.add(const Duration(days: 1)),
        );

      case StatsPeriod.thisMonth:
        return DateTimeRange(
          start: DateTime(todayStart.year, todayStart.month, 1),
          end: todayStart.add(const Duration(days: 1)),
        );

      case StatsPeriod.custom:
        if (_selectedRange == null) {
          return DateTimeRange(
            start: todayStart,
            end: todayStart.add(const Duration(days: 1)),
          );
        }

        final start = DateTime(
          _selectedRange!.start.year,
          _selectedRange!.start.month,
          _selectedRange!.start.day,
        );

        final end = DateTime(
          _selectedRange!.end.year,
          _selectedRange!.end.month,
          _selectedRange!.end.day,
        ).add(const Duration(days: 1));

        return DateTimeRange(start: start, end: end);
    }
  }

  /// 🔁 Bornes envoyées à la lecture de secours de `ventes`.
  ///
  /// Le fuseau est EXPLICITE (`+02:00`, heure de Lubumbashi) : la requête ne
  /// dépend donc ni du fuseau ni de l'heure du téléphone.
  String _isoLubumbashi(DateTime jour) {
    final String y = jour.year.toString().padLeft(4, '0');
    final String m = jour.month.toString().padLeft(2, '0');
    final String d = jour.day.toString().padLeft(2, '0');
    return '$y-$m-${d}T00:00:00+02:00';
  }
  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 📅 La date de référence est demandée au SERVEUR avant tout calcul de
      // période (repli : horloge de l'appareil si le réseau manque).
      _jourReference = await DateLocaleService.instance.charger();

      await Future.wait([
        _loadOwnerProfile(),
        _loadSellers(),
        _loadProductNames(),
      ]);

      await _loadStats();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erreur de chargement : $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage!)),
      );
    }
  }

  Future<void> _loadOwnerProfile() async {
    final data = await _supabase
        .from('utilisateurs')
        .select(
            'id, nom, prenom, avatar, role, parent_id, email, created_at, valide')
        .eq('id', widget.ownerId)
        .maybeSingle();

    if (data != null) {
      _ownerProfile = Utilisateur.fromMap(Map<String, dynamic>.from(data));
    }
  }

  Future<void> _loadSellers() async {
    // 🧩 0181 — équipe de l'ESPACE actif uniquement (la RLS le garantit déjà,
    //    le filtre explicite évite d'afficher d'anciens collaborateurs d'une
    //    autre entreprise si la base n'a pas encore la migration 0181).
    dynamic requete = _supabase
        .from('utilisateurs')
        .select(
            'id, nom, prenom, avatar, role, parent_id, email, created_at, valide')
        .eq('parent_id', widget.ownerId);

    final String? espaceActif = ScopeDonnees.proprioPourEcriture;
    if (espaceActif != null && espaceActif.isNotEmpty) {
      requete = requete.eq('espace_actif_id', espaceActif);
    }

    final data = await requete;
    final list = (data as List)
        .map((e) => Utilisateur.fromMap(Map<String, dynamic>.from(e as Map)))
        .where((u) => u.id != null)
        .toList();

    final map = <String, Utilisateur>{};

    if (_ownerProfile?.id != null) {
      map[_ownerProfile!.id!] = _ownerProfile!;
    }

    for (final u in list) {
      map[u.id!] = u;
    }

    _sellers = map;
  }

  Future<void> _loadProductNames() async {
    final data = await _supabase
        .from('produits')
        .select('id, nom')
        .eq('owner_id', _ownerEspace);

    final map = <int, String>{};

    for (final row in (data as List)) {
      final m = Map<String, dynamic>.from(row as Map);
      final id = (m['id'] as num?)?.toInt();
      final nom = (m['nom']?.toString() ?? '').trim();

      if (id != null && nom.isNotEmpty) {
        map[id] = nom;
      }
    }

    _productNames = map;
  }

  Future<void> _loadStats() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final range = _calculateRange(_selectedPeriod);

      final salesData = await _supabase
          .from('ventes')
          .select(
              'id, produit_id, quantite, prix, date, owner_id, seller_id, mode_paiement')
          .eq('owner_id', _ownerEspace)
          .gte('date', _isoLubumbashi(range.start))
          .lt('date', _isoLubumbashi(range.end))
          .order('date', ascending: false);

      final Map<String, _SellerAgg> aggBySeller = {};
      final Map<String, List<VenteDetail>> detailsBySeller = {};

      for (final row in (salesData as List)) {
        final m = Map<String, dynamic>.from(row as Map);

        final sellerIdRaw = m['seller_id']?.toString();
        final sellerId = (sellerIdRaw == null || sellerIdRaw.trim().isEmpty)
            ? widget.ownerId
            : sellerIdRaw;

        final produitId = (m['produit_id'] as num?)?.toInt();
        final qty = (m['quantite'] as num?)?.toDouble() ?? 0.0;
        final total = (m['prix'] as num?)?.toDouble() ?? 0.0;
        final dateStr = m['date']?.toString() ?? '';
        final dateVente = DateTime.tryParse(dateStr) ?? DateTime.now();

        final detail = VenteDetail(
          produitNom: produitId != null
              ? (_productNames[produitId] ?? 'Produit $produitId')
              : 'Produit inconnu',
          quantite: qty,
          dateVente: dateVente,
          prixTotal: total,
          produitIdInt: produitId?.toString(),
        );

        aggBySeller.putIfAbsent(sellerId, () => _SellerAgg()).add(detail);
        detailsBySeller.putIfAbsent(sellerId, () => []).add(detail);
      }

      final results = <CollaborateurStats>[];
      for (final entry in aggBySeller.entries) {
        results.add(
          CollaborateurStats(
            sellerId: entry.key,
            ventesCount: entry.value.ventesCount,
            totalAmount: entry.value.totalAmount,
          ),
        );
      }

      results.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

      // 🧑‍🤝‍🧑 CORRECTIF 179 — le rapport SERVEUR apporte ce que la lecture
      // brute de `ventes` ne peut pas donner : le stock restant AVANT et
      // APRÈS chaque vente, et le nom du vendeur de l'unité précédente.
      //
      // Best-effort : si l'appel échoue (RPC pas encore déployée, réseau),
      // l'écran continue de fonctionner avec les totaux ci-dessus et signale
      // simplement que le stock n'est pas disponible.
      RapportVendeurs? rapport;
      String? stockIndisponible;
      try {
        rapport = await RapportVendeursService.instance.charger(
          entrepriseId: widget.ownerId,
          debut: range.start,
          fin: range.end.subtract(const Duration(days: 1)),
        );
      } on RapportVendeursException catch (e) {
        stockIndisponible = e.message;
      } catch (e) {
        stockIndisponible = 'Stock non disponible : $e';
      }

      if (rapport != null && !rapport.estVide) {
        // Les journaux du serveur contiennent le stock : on remplace les
        // détails locaux par ceux du serveur, vendeur par vendeur.
        final Map<String, List<VenteDetail>> depuisServeur =
            <String, List<VenteDetail>>{};
        final List<CollaborateurStats> statsServeur = <CollaborateurStats>[];

        for (final VendeurRapport vendeur in rapport.vendeurs) {
          depuisServeur[vendeur.id] = vendeur.journal
              .map((JournalVenteVendeur j) => VenteDetail(
                    produitNom: j.produit,
                    quantite: j.quantite,
                    dateVente: j.date ?? DateTime.now(),
                    prixTotal: j.prix,
                    stockAvant: j.stockAvant,
                    stockApres: j.stockApres,
                    venduAvantPar: j.venduAvantPar,
                  ))
              .toList(growable: false);

          statsServeur.add(
            CollaborateurStats(
              sellerId: vendeur.id,
              ventesCount: vendeur.ventes,
              totalAmount: vendeur.ca,
            ),
          );
        }

        if (depuisServeur.isNotEmpty) {
          detailsBySeller
            ..clear()
            ..addAll(depuisServeur);
        }
        if (statsServeur.isNotEmpty) {
          results
            ..clear()
            ..addAll(statsServeur);
        }
      }

      if (!mounted) return;
      setState(() {
        _stats = results;
        _detailsBySeller = detailsBySeller;
        _rapport = rapport;
        _stockIndisponible = stockIndisponible;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Erreur de chargement des statistiques : $e';
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage!)),
      );
    }
  }

  Future<void> _downloadCollaborateurReport(
    String collabId,
    String name,
    List<VenteDetail> details,
    DateTimeRange range,
  ) async {
    try {
      final font = pw.Font.helvetica();
      final bold = pw.Font.helveticaBold();

      final totalAmount = details.fold<double>(
        0.0,
        (sum, item) => sum + item.prixTotal,
      );
      final totalQty = details.fold<double>(
        0.0,
        (sum, item) => sum + item.quantite,
      );

      final pdf = pw.Document();
      final periodText = _formatRangeLabel(range);
      final generatedAt = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      pdf.addPage(
        pw.MultiPage(
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(24),
            theme: pw.ThemeData.withFont(
              base: font,
              bold: bold,
            ),
          ),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Rapport vendeur',
                style:
                    pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Vendeur : $name'),
              pw.Text('Période : $periodText'),
              pw.Text('Généré le : $generatedAt'),
              pw.Divider(),
            ],
          ),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
          build: (context) => [
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Résumé',
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Quantité totale'),
                      pw.Text(_formatQty(totalQty)),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Montant total'),
                      pw.Text(formatMontant(totalAmount)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Détail des ventes',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            if (details.isEmpty)
              pw.Text('Aucun article vendu sur cette période.')
            else
              pw.Table.fromTextArray(
                // 🧑‍🤝‍🧑 CORRECTIF 179 — le stock restant au moment de chaque
                // vente est désormais imprimé dans le rapport du vendeur.
                headers: const [
                  'Produit',
                  'Qté',
                  'Heure',
                  'Stock avant',
                  'Stock après',
                  'Montant',
                ],
                data: details.map((d) {
                  final localDate = d.dateVente.toLocal();
                  final time = DateFormat('HH:mm').format(localDate);

                  return [
                    d.produitNom,
                    _formatQty(d.quantite),
                    time,
                    d.stockConnu ? _formatQty(d.stockAvant ?? 0) : '—',
                    d.stockConnu ? _formatQty(d.stockApres ?? 0) : '—',
                    formatMontant(d.prixTotal),
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                cellAlignments: {
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.center,
                  3: pw.Alignment.centerRight,
                  4: pw.Alignment.centerRight,
                  5: pw.Alignment.centerRight,
                },
                border: pw.TableBorder.all(color: PdfColors.grey400),
              ),
          ],
        ),
      );

      final Uint8List bytes = await pdf.save();
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]+'), '_');
      final fileName =
          'rapport_$safeName${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

      await PartagePdf.partager(bytes, nomFichier: fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erreur lors du téléchargement du rapport : $e")),
      );
    }
  }

  void _showCollaborateurDetails(String collabId, String name) async {
    final range = _calculateRange(_selectedPeriod);
    final details = _detailsBySeller[collabId] ?? const <VenteDetail>[];

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, color: Colors.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Ventes de $name",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: details.isEmpty
                  ? const Center(
                      child: Text("Aucun article vendu sur cette période"),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: details.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final d = details[i];
                        final localDate = d.dateVente.toLocal();
                        final time =
                            "${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}";

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.blue[50],
                                child: Text(
                                  _formatQty(d.quantite),
                                  style: const TextStyle(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      d.produitNom,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      time,
                                      style: const TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                    // 🧑‍🤝‍🧑 CORRECTIF 179 — le stock au moment
                                    // de la vente : « il restait 4 beignets ».
                                    if (d.stockConnu)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Stock : ${_formatQty(d.stockAvant ?? 0)} '
                                          'avant → ${_formatQty(d.stockApres ?? 0)} après',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF1565C0),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      )
                                    else
                                      const Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Stock inconnu (article supprimé)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.orange,
                                          ),
                                        ),
                                      ),
                                    if (d.venduAvantPar != null &&
                                        d.venduAvantPar!.trim().isNotEmpty)
                                      Text(
                                        'Vente précédente de cet article : '
                                        '${d.venduAvantPar}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                formatMontant(d.prixTotal),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.download),
                  label: const Text("Télécharger le rapport PDF"),
                  onPressed: () async {
                    Navigator.of(sheetContext).pop();
                    await _downloadCollaborateurReport(
                      collabId,
                      name,
                      details,
                      range,
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        children: [
          _filterChip("Aujourd'hui", StatsPeriod.today),
          _filterChip("Semaine", StatsPeriod.thisWeek),
          _filterChip("Mois", StatsPeriod.thisMonth),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: ActionChip(
              label: const Text("Calendrier"),
              avatar: const Icon(Icons.calendar_month, size: 16),
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2024),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() {
                    _selectedRange = picked;
                    _selectedPeriod = StatsPeriod.custom;
                  });
                  _loadStats();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, StatsPeriod period) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: ChoiceChip(
        label: Text(label),
        selected: _selectedPeriod == period,
        onSelected: (val) {
          if (val) {
            setState(() => _selectedPeriod = period);
            _loadStats();
          }
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withOpacity(0.12)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummarySection() {
    final ownerName =
        _ownerProfile != null ? _displayName(_ownerProfile!) : 'Patron';

    final totalSales =
        _stats.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final totalQty = _detailsBySeller.values
        .expand((e) => e)
        .fold<double>(0.0, (sum, d) => sum + d.quantite);

    final ownerStats =
        _stats.where((s) => s.sellerId == widget.ownerId).toList();
    final ownerAmount =
        ownerStats.fold<double>(0.0, (sum, s) => sum + s.totalAmount);
    final ownerCount = ownerStats.fold<int>(0, (sum, s) => sum + s.ventesCount);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        children: [
          // Première ligne : Ventes totales et Montant total
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  label: 'Ventes totales',
                  value: totalQty.toStringAsFixed(0),
                  color: Colors.blue,
                  icon: Icons.shopping_cart_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  label: 'Montant total',
                  value: formatMontant(totalSales),
                  color: Colors.green,
                  icon: Icons.payments_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Deuxième ligne : Nom du patron et Nombre de ventes du patron
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  label: 'Patron',
                  value: ownerName,
                  color: Colors.deepPurple,
                  icon: Icons.badge_outlined,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildStatCard(
                  label: 'Ventes du patron',
                  value: '$ownerCount',
                  color: Colors.orange,
                  icon: Icons.storefront_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Carte du Chiffre d'Affaires du Patron (CORRIGÉE)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Expanded permet au texte de prendre la place restante sans pousser le montant
                  Expanded(
                    child: const Text(
                      'Chiffre d’affaires personnel du patron',
                      style: TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow
                          .ellipsis, // Ajoute "..." si vraiment trop long
                      maxLines: 1,
                    ),
                  ),
                  const SizedBox(width: 8), // Petit espace de sécurité
                  Text(
                    formatMontant(ownerAmount),
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSellerCard(CollaborateurStats s) {
    final isOwner = s.sellerId == widget.ownerId ||
        s.sellerId == 'proprietaire';
    final name = isOwner && _ownerProfile != null
        ? _displayName(_ownerProfile!)
        : _sellerLabel(s.sellerId);

    final details = _detailsBySeller[s.sellerId] ?? const <VenteDetail>[];
    // 🧑‍🤝‍🧑 CORRECTIF 179 — stock restant après la dernière vente connue.
    final double? stockRestant =
        _rapport?.vendeurParId(s.sellerId)?.stockApresDerniereVente;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: () => _showCollaborateurDetails(s.sellerId, name),
        leading: CircleAvatar(
          backgroundColor:
              isOwner ? Colors.deepPurple.shade50 : Colors.green.shade50,
          child: Icon(
            isOwner ? Icons.badge : Icons.person,
            color: isOwner ? Colors.deepPurple : Colors.green,
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          stockRestant == null
              ? '${s.ventesCount} ventes enregistrées'
              : '${s.ventesCount} ventes · stock restant '
                  '${_formatQty(stockRestant)}',
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              "${s.totalAmount.toStringAsFixed(0)} FC",
              style: TextStyle(
                color: isOwner ? Colors.deepPurple : Colors.green,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              '${details.length} lignes',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasData = _stats.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Performances des vendeurs"),
        actions: [
          IconButton(
            onPressed: _loadStats,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          // 🧑‍🤝‍🧑 CORRECTIF 179 — si le rapport serveur est indisponible, on
          // le dit clairement plutôt que d'afficher un stock inventé.
          if (_stockIndisponible != null && !_isLoading)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(15, 0, 15, 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: Colors.orange.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Stock non affiché : $_stockIndisponible',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          _buildSummarySection(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Text(_errorMessage!))
                    : !hasData
                        ? const Center(
                            child: Text("Aucune vente sur cette période"))
                        : ListView.builder(
                            padding: const EdgeInsets.only(top: 10),
                            itemCount: _stats.length,
                            itemBuilder: (context, index) {
                              return _buildSellerCard(_stats[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
