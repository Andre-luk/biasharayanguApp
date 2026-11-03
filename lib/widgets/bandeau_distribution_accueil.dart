// lib/widgets/bandeau_distribution_accueil.dart
//
// 🚚 MODULE 24 — BANDEAU « ESPACE DISTRIBUTION » DE L'ACCUEIL.
//
// Le tableau de bord d'un compte de distribution ne doit PAS ressembler à
// celui d'une boutique : pas de « ventes du jour » de la boutique, pas de
// stock d'articles, pas de caisse générale. Ce bandeau affiche les seuls
// repères du module 24, lus par `dist_tableau_bord()` :
//
//   • le rôle distribution du compte (gérant, production, stock, commercial,
//     comptable, propriétaire) ;
//   • les opérations qui ATTENDENT ce compte ;
//   • le solde de la caisse de la distribution ;
//   • les anomalies ouvertes.
//
// Il est affiché pour TOUS les comptes de l'univers distribution, y compris
// les collaborateurs (dont l'accueil masque les statistiques de boutique).

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/distribution_gestion.dart';
import 'package:biashara_yangu/pages/distribution_pro_page.dart';
import 'package:biashara_yangu/services/distribution_gestion_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

class BandeauDistributionAccueil extends StatefulWidget {
  const BandeauDistributionAccueil({super.key});

  @override
  State<BandeauDistributionAccueil> createState() =>
      _BandeauDistributionAccueilState();
}

class _BandeauDistributionAccueilState
    extends State<BandeauDistributionAccueil> {
  bool _chargement = true;
  TableauBordDistribution? _bord;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      final TableauBordDistribution bord =
          await DistributionGestionService.instance.tableauBord();
      if (!mounted) return;
      setState(() => _bord = bord);
    } on DistributionGestionException {
      // Compte sans rôle distribution, module non installé, hors ligne : le
      // bandeau reste affiché avec le seul bouton d'ouverture.
    } catch (_) {
      // Idem : l'accueil ne doit jamais casser à cause de ce bandeau.
    } finally {
      if (mounted) setState(() => _chargement = false);
    }
  }

  void _ouvrir() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext _) => const DistributionProPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TableauBordDistribution? bord = _bord;
    final RoleDistribution role = bord?.role ?? RoleDistribution.aucun;
    final String devise = bord?.devise ?? FormatMonetaire.symbole;
    final int enAttente = bord?.totalEnAttente ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppDegrades.primaire,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: AppCouleurs.marine.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.factory_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'ESPACE DISTRIBUTION',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  role == RoleDistribution.aucun ? 'Membre' : role.libelle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_chargement)
            Row(
              children: <Widget>[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Lecture de votre activité…',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
              ],
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                _repere(
                  theme,
                  libelle: 'EN ATTENTE',
                  valeur: '$enAttente',
                  alerte: enAttente > 0,
                ),
                const SizedBox(width: 10),
                _repere(
                  theme,
                  libelle: 'CAISSE',
                  valeur: bord == null
                      ? '—'
                      : formatMontant(bord.caisseSolde, devise: devise),
                ),
                const SizedBox(width: 10),
                _repere(
                  theme,
                  libelle: 'ANOMALIES',
                  valeur: '${bord?.anomaliesOuvertes ?? 0}',
                  alerte: (bord?.anomaliesOuvertes ?? 0) > 0,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _ouvrir,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppCouleurs.marine,
                ),
                icon: const Icon(Icons.dashboard_customize_rounded, size: 18),
                label: const Text('Ouvrir mon tableau de bord'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _repere(
    ThemeData theme, {
    required String libelle,
    required String valeur,
    bool alerte = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              libelle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 9,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              valeur,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: alerte ? AppCouleurs.alerte : Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
