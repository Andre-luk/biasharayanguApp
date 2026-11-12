// lib/services/scope_donnees.dart
//
// 🧩 MODULE 15 — L'ESPACE DE TRAVAIL DONT ON AFFICHE LES DONNÉES.
//
// POURQUOI CE FICHIER
//   Toutes les données métier (produits, stock, ventes, caisse, clients,
//   dépenses…) sont rattachées à une colonne `owner_id`. Jusqu'ici cette
//   colonne contenait **l'UUID du patron** : un propriétaire qui ouvrait une
//   deuxième boutique retrouvait donc le MÊME catalogue, le même stock et la
//   même caisse dans les deux.
//
//   Le serveur, lui, sait déjà faire la distinction : `mon_proprietaire()`
//   renvoie l'ESPACE ACTIF (`utilisateurs.espace_actif_id`), avec repli sur
//   l'UUID du patron. L'espace par défaut porte justement l'UUID du patron,
//   donc les données existantes restent valides — aucune migration nécessaire.
//
// CE QUE FAIT CE FICHIER
//   Il expose une valeur unique, mise à jour par [EspaceService] :
//     • au chargement de la liste des espaces ;
//     • à chaque bascule (sélecteur d'entreprise) ;
//     • à la déconnexion (remise à zéro).
//
//   `DBHelper.resolveEffectiveOwnerId` et `ArticleService.proprietaireCourant`
//   la lisent en PREMIER : c'est ce qui fait qu'une lecture ou une écriture
//   vise la boutique affichée, et non plus toutes les boutiques du compte.
//
// ⚠️ Aucun import ici (fichier feuille) : il est lu par `db_helper`, qui ne
//    doit jamais dépendre d'un service réseau.

class ScopeDonnees {
  ScopeDonnees._();

  static String? _espaceActif;

  /// Propriétaire EFFECTIF renvoyé par le serveur (`mon_proprietaire()`).
  ///
  /// Pourquoi une seconde valeur ? Le serveur ne retient `espace_actif_id`
  /// que si l'espace appartient bien à l'entreprise courante du compte
  /// (sinon il retombe sur l'UUID du patron). Écrire avec l'espace choisi
  /// pendant que la RLS attend l'UUID du patron produit des lignes
  /// INVISIBLES : elles s'enregistrent, mais aucun écran ne les revoit.
  ///
  /// Cette valeur, lue UNE fois par espace après un chargement ou une
  /// bascule, garantit que l'application lit et écrit exactement là où la
  /// RLS l'autorise.
  static String? _proprietaireEffectif;

  /// Espace de travail actif, ou `null` tant que la liste n'est pas chargée.
  ///
  /// `null` = comportement historique (patron / collaborateur), ce qui évite
  /// tout effet de bord au démarrage à froid et hors ligne.
  static String? get espaceActif {
    final String? valeur = _espaceActif?.trim();
    return (valeur == null || valeur.isEmpty) ? null : valeur;
  }

  /// Appelé par [EspaceService] après un chargement ou une bascule.
  static void definirEspaceActif(String? id) {
    final String? valeur = id?.trim();
    final String? propre = (valeur == null || valeur.isEmpty) ? null : valeur;
    if (propre != _espaceActif) {
      // L'espace change : la valeur vérifiée par le serveur ne vaut plus.
      _proprietaireEffectif = null;
    }
    _espaceActif = propre;
  }

  /// Déconnexion : plus aucun espace actif (evite de laisser fuiter la
  /// boutique précédente au compte suivant).
  static void reinitialiser() {
    _espaceActif = null;
    _proprietaireEffectif = null;
  }

  /// Propriétaire effectif vérifié par le serveur, ou `null` s'il n'a pas
  /// encore été lu (hors ligne, démarrage à froid).
  static String? get proprietaireEffectif {
    final String? valeur = _proprietaireEffectif?.trim();
    return (valeur == null || valeur.isEmpty) ? null : valeur;
  }

  /// Enregistre la valeur renvoyée par `mon_proprietaire()`.
  static void definirProprietaireEffectif(String? id) {
    final String? valeur = id?.trim();
    _proprietaireEffectif = (valeur == null || valeur.isEmpty) ? null : valeur;
  }

  /// La valeur à utiliser pour `owner_id` : celle du serveur d'abord.
  static String? get proprioPourEcriture => proprietaireEffectif ?? espaceActif;

  /// Un espace est-il connu ? (`false` = démarrage à froid / hors ligne :
  /// on retombe alors sur le comportement historique).
  static bool get estDefini => espaceActif != null;

  /// Pour les tests et le diagnostic.
  static String? get valeurBrute => _espaceActif;

  /// Pour les tests et le diagnostic.
  static String? get proprietaireEffectifBrut => _proprietaireEffectif;
}
