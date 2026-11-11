// lib/services/pressing_notification_service.dart
//
// 🧺 MODULE 35 — PRÉVENIR LE CLIENT.
//
// Un pressing vit d'une promesse : « votre vêtement sera prêt tel jour ». Cet
// écran-là ne sert à rien si personne ne prévient le client quand c'est prêt.
//
// Ce service construit le message et ouvre WhatsApp — c'est le canal qu'utilisent
// réellement les pressings (pas d'e-mail, pas de SMS payant). Le message est
// rédigé ici UNE seule fois : le même texte part de la fiche de la commande et,
// plus tard, des rappels automatiques.
//
// ⚠️ Rien n'est inventé : le numéro vient de la commande (saisi au dépôt), le
//    montant restant vient du serveur, et le nom de l'établissement de sa fiche.
//    Si le numéro manque, on ouvre WhatsApp sans destinataire (l'agent choisit
//    le contact) plutôt que d'échouer.

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:biashara_yangu/models/etablissement.dart';
import 'package:biashara_yangu/models/pressing.dart';
import 'package:biashara_yangu/services/pressing_recu_pdf_service.dart';
import 'package:biashara_yangu/utils/format_utils.dart';

/// États d'une commande qui méritent un message au client.
enum TypeMessagePressing {
  /// Tout ou partie des vêtements est prêt (l'étape finale est atteinte).
  pret,

  /// La date de retrait promise est dépassée et la commande n'est pas remise.
  retard,
}

class PressingNotificationService {
  PressingNotificationService._();

  static final PressingNotificationService instance =
      PressingNotificationService._();

  // ---------------------------------------------------------------------------
  // MESSAGE
  // ---------------------------------------------------------------------------

  /// Le texte envoyé au client.
  ///
  /// [partiel] : vrai quand seulement une partie des vêtements est prête —
  /// le client doit le savoir, sinon il se déplace pour rien.
  String message({
    required PressingCommande commande,
    required Etablissement etablissement,
    TypeMessagePressing type = TypeMessagePressing.pret,
    bool partiel = false,
  }) {
    final String nom = (commande.clientNom ?? '').trim().isEmpty
        ? 'Bonjour'
        : 'Bonjour ${commande.clientNom!.trim()}';
    final StringBuffer sb = StringBuffer();
    sb.write('$nom, ');

    switch (type) {
      case TypeMessagePressing.pret:
        sb.write(partiel
            ? 'une partie de votre commande ${commande.numero} est prête'
            : 'votre commande ${commande.numero} est prête');
        break;
      case TypeMessagePressing.retard:
        sb.write('votre commande ${commande.numero} nous a été confiée et '
            'dépasse la date de retrait prévue');
        break;
    }

    sb.write(' chez ${etablissement.nomAffiche}. ');

    if (type == TypeMessagePressing.pret) {
      if (commande.datePrevue != null) {
        sb.write('Retrait prévu le ${formatDate(commande.datePrevue)}. ');
      }
      if (commande.solde > 0) {
        sb.write('Reste à payer : '
            '${formatMontant(commande.solde, devise: commande.devise)}. ');
      } else {
        sb.write('Votre commande est entièrement réglée. ');
      }
    } else {
      if (commande.datePrevue != null) {
        sb.write('Elle était attendue le ${formatDate(commande.datePrevue)}. ');
      }
      if (commande.solde > 0) {
        sb.write('Solde restant : '
            '${formatMontant(commande.solde, devise: commande.devise)}. ');
      }
      sb.write('Nous vous prions de nous excuser pour ce retard. ');
    }

    sb.write('Merci de votre confiance.');
    return sb.toString();
  }

  // ---------------------------------------------------------------------------
  // ENVOI
  // ---------------------------------------------------------------------------

  /// Ouvre WhatsApp sur le message prêt à envoyer. `true` si l'application a
  /// bien été ouverte.
  Future<bool> envoyer({
    required PressingCommande commande,
    required Etablissement etablissement,
    TypeMessagePressing type = TypeMessagePressing.pret,
    bool partiel = false,
  }) async {
    final String texte = Uri.encodeComponent(
      message(
        commande: commande,
        etablissement: etablissement,
        type: type,
        partiel: partiel,
      ),
    );
    final String? numero = commande.clientTelephone;
    final String base = (numero ?? '').trim().isEmpty
        ? 'https://wa.me/?text=$texte'
        : 'https://wa.me/'
            '${PressingRecuPdfService.normaliserTelephone(numero!)}?text=$texte';

    try {
      return await launchUrl(
        Uri.parse(base),
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('PressingNotificationService.envoyer : $e');
      return false;
    }
  }

  /// Copie le message dans le presse-papiers (quand WhatsApp n'est pas là).
  static String messageSansNumero({
    required PressingCommande commande,
    required Etablissement etablissement,
  }) {
    return PressingNotificationService.instance.message(
      commande: commande,
      etablissement: etablissement,
    );
  }
}
