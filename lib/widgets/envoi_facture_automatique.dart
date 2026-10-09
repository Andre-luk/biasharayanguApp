// lib/widgets/envoi_facture_automatique.dart
//
// 🧾 CORRECTIF 67 — ENVOI AUTOMATIQUE DE LA FACTURE APRÈS ENCAISSEMENT.
//
// Le patron a demandé un envoi AUTOMATIQUE, et « peu importe si c'est
// l'agent ». On n'affiche donc AUCUNE boîte de dialogue : dès que
// l'encaissement est enregistré, la facture part sur le WhatsApp du client,
// puis l'application le SIGNALE.
//
// POURQUOI PAS DE QUESTION À L'UTILISATEUR
// ----------------------------------------
// Une confirmation à chaque encaissement se transformerait en clic réflexe :
// au bout de trois jours, personne ne lirait plus le message et certaines
// factures ne partiraient jamais. Or la facture est la contrepartie de
// l'argent reçu. Elle part donc toute seule.
//
// CE QU'ON FAIT QUAND ÇA NE PEUT PAS PARTIR
// -----------------------------------------
// On ne bloque JAMAIS l'encaissement (il est déjà enregistré, l'argent est
// reçu). On le DIT, en distinguant les deux cas :
//   • aucun numéro WhatsApp connu → la facture reste « à envoyer » ;
//   • WhatsApp n'a pas pu s'ouvrir → la facture reste « à envoyer ».
// Dans les deux cas la facture existe en base et reste retrouvable dans
// l'écran « Factures d'abonnement », avec son badge « à envoyer ».

import 'package:flutter/material.dart';

import 'package:biashara_yangu/models/facture_abonnement.dart';
import 'package:biashara_yangu/services/facture_abonnement_service.dart';
import 'package:biashara_yangu/ui/theme/app_theme.dart';

/// Envoie la facture du dernier encaissement de [entrepriseId] sur WhatsApp.
///
/// À appeler APRÈS un encaissement réussi. Ne lève jamais : un problème de
/// facture ne doit pas faire croire que le paiement a échoué.
Future<void> envoyerFactureAbonnementAutomatique(
  BuildContext context, {
  required String entrepriseId,
  String? nomEtablissement,
}) async {
  final FactureAbonnementService service = FactureAbonnementService.instance;

  FactureAbonnement? facture;
  try {
    final List<FactureAbonnement> recentes = await service.lister(
      entrepriseId: entrepriseId,
      limite: 1,
    );
    if (recentes.isNotEmpty) facture = recentes.first;
  } catch (e) {
    debugPrint('Envoi automatique de facture (lecture) : $e');
    return;
  }

  if (facture == null) {
    if (!context.mounted) return;
    _signaler(
      context,
      'Encaissement enregistré, mais aucune facture n\'a pu être retrouvée. '
      'Ouvrez « Factures d\'abonnement » puis « Réparer l\'historique ».',
      couleur: AppCouleurs.alerte,
    );
    return;
  }

  // Déjà envoyée (double encaissement, ou envoi manuel) : on ne renvoie pas
  // la même facture au client sans qu'on le lui demande.
  if (!facture.aEnvoyer) return;

  try {
    await service.envoyerParWhatsApp(
      facture,
      nomEtablissement: nomEtablissement,
    );

    if (!context.mounted) return;
    _signaler(
      context,
      'Facture ${facture.numero} transmise au WhatsApp du client.',
      action: SnackBarAction(
        label: 'Joindre le PDF',
        onPressed: () => service
            .partagerPDF(
              facture!,
              nomEtablissement: nomEtablissement ?? 'Biashara Yangu',
            )
            .catchError((Object e) => debugPrint('Partage du PDF : $e')),
      ),
    );
  } on FactureAbonnementException catch (e) {
    if (!context.mounted) return;

    if (e.type == TypeErreurFacture.telephone) {
      // Le plus fréquent de loin : le client n'a pas laissé de numéro. On le
      // dit clairement, sinon l'opérateur croira que la facture est partie.
      _signaler(
        context,
        'Facture ${facture.numero} émise, mais AUCUN numéro WhatsApp connu '
        'pour ce client : elle reste « à envoyer ».',
        couleur: AppCouleurs.alerte,
      );
      return;
    }

    _signaler(
      context,
      'Facture ${facture.numero} émise, mais l\'envoi WhatsApp a échoué '
      '(elle reste « à envoyer »).',
      couleur: AppCouleurs.alerte,
    );
  }
}

void _signaler(
  BuildContext context,
  String message, {
  Color? couleur,
  SnackBarAction? action,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: couleur,
      action: action,
      duration: const Duration(seconds: 6),
    ),
  );
}
