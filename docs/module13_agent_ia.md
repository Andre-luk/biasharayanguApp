# 🤖 Module 13 — Assistant IA (DeepSeek)

> Guide **complet (étapes 1 à 10)** : migrations SQL, déploiement de l'Edge
> Function `agent-ia`, secrets, écrans Flutter et tests.
> Aucune compilation locale n'est nécessaire : tout se fait dans le navigateur
> (Supabase) + un terminal pour les tests.
>
> ⚠️ **Si tu avais déjà déployé la version « étape 2 »** (2 outils pilotes) :
> recolle `supabase/functions/agent-ia/index.ts` dans l'éditeur Supabase — la
> version livrée contient désormais **les 35 outils** (ventes, stock, finance,
> clients, rapports, collaborateurs, abonnement, QR) et le flux de
> **confirmation des actions destructives**.

---

## 1. Vue d'ensemble — qui fait quoi

```
Application Flutter ──JWT utilisateur──▶ Edge Function « agent-ia »
                                              │
        ┌─────────────────────────────────────┼───────────────────────────────┐
        ▼                                     ▼                               ▼
   Vérifications :                     DeepSeek API                    Supabase (base)
   • JWT (auth.getUser)                (clé DEEPSEEK_API_KEY           • agent_ia_conversations
   • abonnement actif                   en secret — jamais             • agent_ia_actions
   • solde de quotas > 0                dans l'app)                    • rpc_agent_ia_debiter
   • rate limiting (30 msg/h)          deepseek-chat, 500 tokens        • journal_audit (AGENT_IA)
   • outils exécutés avec LE JWT
     de l'utilisateur (RLS +
     permissions serveur)
```

- **La clé DeepSeek ne quitte JAMAIS le serveur Supabase** (secret d'Edge
  Function) : l'application ne voit que l'Edge Function.
- Les **outils** de l'agent (ventes, stock, finance…) s'exécutent avec le
  **JWT de l'utilisateur** : la RLS et les permissions `peut(...)` des modules
  précédents restent l'autorité finale — un vendeur ne pourra jamais faire par
  l'IA ce que son rôle interdit.
- **35 outils** sont exposés à DeepSeek (liste au § 10) ; les actions
  destructives (annuler une vente, supprimer un article, ajuster le stock,
  modifier un prix) exigent une **confirmation explicite** de l'utilisateur
  (voir § 11).

---

## 2. AVANT DE DÉPLOYER — les migrations SQL

Dans **Supabase → SQL Editor**, exécute dans l'ordre (si pas déjà fait) :

1. `supabase/migrations/20260916000014_module13_agent_ia.sql`
   → les 5 tables (`agent_ia_config`, `agent_ia_quotas`, `agent_ia_achats`,
   `agent_ia_conversations`, `agent_ia_actions`) + RLS + configuration par
   défaut (150 CDF/quota, 20 caractères, pack 10 = 1 000 CDF, 5 offerts).
2. `supabase/migrations/20260916000015_module13_agent_ia_rpc.sql`
   → `rpc_agent_ia_debiter` : le **débit atomique** des quotas (réservé au
   service_role).
3. `supabase/migrations/20260916000016_module13_achats_rpc.sql`
   → `rpc_agent_ia_etat` (création du pool + bonus de bienvenue),
   `rpc_agent_ia_demander_achat`, `rpc_agent_ia_valider_achat`,
   `rpc_agent_ia_marquer_paye`, `rpc_agent_ia_attribuer`,
   `rpc_agent_ia_config_maj` + page `assistant_ia` dans les permissions.

> Si le Module 12 n'est pas encore passé : exécute d'abord
> `20260916000013_module12_audit_securite.sql` (journal d'audit renforcé —
> les traces `AGENT_IA` s'y ajoutent).

---

## 3. DÉPLOYER L'EDGE FUNCTION (copier-coller, sans rien installer)

1. Ouvre **`https://supabase.com/dashboard`** → ton projet
   (`pqzcliibocndiyqbyddr`).
2. Menu **Edge Functions** → bouton **« Deploy a new function »** (ou
   « Create a new function »).
3. Choisis **« Via Editor »** (l'option navigateur — pas besoin de la CLI).
4. **Nom de la fonction : `agent-ia`** (exactement, en minuscules).
5. **Colle tout le contenu** du fichier
   `supabase/functions/agent-ia/index.ts` (dans ce dépôt).
6. Laisse **« Enforce JWT verification » ACTIVÉ** (la fonction revérifie de
   toute façon la session elle-même).
7. Clique **Deploy** — attends la fin du déploiement (coche verte).

---

## 4. LE SECRET `DEEPSEEK_API_KEY`

1. Va sur **`https://platform.deepseek.com`** → connecte-toi → menu
   **API Keys** → **Create new key** → copie la clé (`sk-…`).
   ⚠️ La clé ne s'affiche **qu'une seule fois** : garde-la de côté.
   Vérifie aussi que ton compte DeepSeek a du **crédit** (menu *Top up*).
2. Dans **Supabase → Edge Functions → Secrets** (ou *Project Settings →
   Edge Functions → Secrets*) → **Add new secret** :
   - Name : `DEEPSEEK_API_KEY`
   - Value : la clé `sk-…`
3. Enregistre. La fonction lira ce secret à chaque appel.

> 🔒 **Règles d'or** : la clé ne doit JAMAIS être collée dans l'application,
> dans un message, ni committée dans le dépôt. Si elle fuite, révoque-la
> chez DeepSeek et crée-en une nouvelle.

---

## 5. DONNER DES QUOTAS À TON COMPTE POUR TESTER

🥳 **Plus besoin de SQL manuel** : dès le premier appel à
`rpc_agent_ia_etat` (ouverture de l'écran « Quotas IA » ou premier message),
le pool de l'entreprise est créé avec le **bonus de bienvenue**
(5 quotas par défaut).

Pour un test rapide avant d'avoir des acheteurs, le SQL reste utile :

```sql
-- 1. Trouver l'identifiant de ton compte (et de ton entreprise si tu en as une)
select u.id as utilisateur_id, u.nom, u.email,
       coalesce(u.entreprise_id, u.parent_id, u.id) as entreprise_id
  from public.utilisateurs u
 where u.email ilike '%super.admin%';

-- 2. Créditer 30 quotas (remplace les 2 UUID par ceux lus ci-dessus)
insert into public.agent_ia_quotas
  (utilisateur_id, entreprise_id, quotas_disponibles, quotas_achetes_total, attribue_par)
values
  ('<UUID-UTILISATEUR>', '<UUID-ENTREPRISE>', 30, 30, '<UUID-UTILISATEUR>')
on conflict (utilisateur_id)
do update set
  quotas_disponibles  = excluded.quotas_disponibles,
  quotas_achetes_total = excluded.quotas_achetes_total,
  updated_at = now();
```
💡 Pour créditer **le pool de l'entreprise** (row `utilisateur_id is null`),
utilise l'écran **Quotas IA → Approbation d'une demande** (Super Admin) ou
l'attribution par le propriétaire — c'est le flux officiel, tracé dans le
journal (voir § 12).
---

## 6. TESTER DEPUIS UN TERMINAL (curl)

### 6.a Obtenir un jeton de session

Remplace `<TON-EMAIL>` / `<TON-MOT-DE-PASSE>` par ton compte de test.
La clé `apikey` (anon) est dans `lib/main.dart` du dépôt (ligne `anonKey`).

```bash
curl -s -X POST \
  "https://pqzcliibocndiyqbyddr.supabase.co/auth/v1/token?grant_type=password" \
  -H "apikey: <ANON_KEY>" \
  -H "Content-Type: application/json" \
  -d '{"email":"<TON-EMAIL>","password":"<TON-MOT-DE-PASSE>"}'
```

Copie la valeur `access_token` de la réponse.

### 6.b Appeler l'assistant

```bash
TOKEN="<colle le access_token ici>"

curl -s -X POST \
  "https://pqzcliibocndiyqbyddr.supabase.co/functions/v1/agent-ia" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"Bonjour ! Quelles sont les informations de mon entreprise ?"}' \
  | python3 -m json.tool
```

**Réponse attendue** (ordre des champs stable) :

```json
{
  "reponse": "✅ Votre entreprise … Votre abonnement est actif … Il vous reste 30 quotas.",
  "quotas_consommes": 6,
  "montant_cdf": 900,
  "solde_restant": 24,
  "caracteres_reponse": 105,
  "actions": [{ "outil": "informations_entreprise", "succes": true }]
}
```

Vérifie ensuite dans le SQL Editor que tout est tracé :

```sql
select role, contenu, quotas_consommes, action_executee, created_at
  from public.agent_ia_conversations order by created_at desc limit 10;

select outil, succes, created_at
  from public.agent_ia_actions order by created_at desc limit 10;

select seq, action, niveau, details
  from public.journal_audit where action = 'AGENT_IA'
 order by seq desc limit 5;
```

---

## 7. LA FACTURATION (rappel)

- 1 quota = **20 caractères** de réponse utile (`caracteres_par_quota`) ;
- minimum **1 quota** facturé, même pour une réponse courte ;
- montant = quotas × **150 CDF** (`tarif_par_quota`) ;
- Exemple : réponse de 105 caractères → ⌈105 / 20⌉ = **6 quotas** → **900 CDF** ;
- le solde est **débité après la réponse** (`rpc_agent_ia_debiter`, atomique) ;
- solde = 0 → l'assistant répond `QUOTAS_EPUISES` et propose l'achat d'un pack.

---

## 8. CODES D'ERREUR DE LA FONCTION

| Code HTTP | `erreur` | Signification |
|---|---|---|
| 401 | `SESSION_ABSENTE` | Jeton manquant/expiré → se reconnecter |
| 402 | `QUOTAS_EPUISES` | Solde à zéro → acheter un pack |
| 403 | `ASSISTANT_DESACTIVE` | Désactivé par l'administrateur |
| 403 | `ABONNEMENT_EXPIRE` / `ABONNEMENT_BLOQUE` | Abonnement échu (lecture seule) ou suspendu |
| 429 | `LIMITE_MESSAGES` / `LIMITE_CARACTERES` | Rate limiting (30 msg/h, 5000 car./h) |
| 400 | `MESSAGE_VIDE` / `MESSAGE_TROP_LONG` | Message absent ou > 2000 caractères |
| 400 | `CONFIRMATION_REQUISE` | Action destructive sans confirmation (voir § 11) |
| 502/500 | `ERREUR_INTERNE` | Incident (réseau DeepSeek, etc.) — réessayer |
| 503 | `SECRET_MANQUANT` | `DEEPSEEK_API_KEY` non configurée |

---

## 9. OÙ TOUT EST TRACÉ

| Quoi | Où |
|---|---|
| Chaque message (utilisateur + assistant) | `agent_ia_conversations` (avec `quotas_consommes`) |
| Chaque outil exécuté (paramètres, résultat, succès) | `agent_ia_actions` |
| Chaque conversation (résumé + coût) | `journal_audit`, action `AGENT_IA` (niveau MOYEN) |
| Débit des quotas | `agent_ia_quotas` (`quotas_utilises_total`) |

---

## 10. LES 35 OUTILS DE L'AGENT

| Domaine | Outils | Rôles typiques |
|---|---|---|
| 🧺 Ventes | `rechercher_produit`, `creer_vente`, `annuler_vente` ⚠️, `lister_ventes_du_jour`, `lister_ventes_periode` | Vendeur, Propriétaire |
| 📦 Produits & stock | `ajouter_produit`, `modifier_produit` ⚠️ (prix), `supprimer_produit` ⚠️, `consulter_stock`, `lister_stock_faible`, `ajouter_stock`, `ajuster_stock` ⚠️, `rechercher_produit_par_qr` | Magasinier, Propriétaire |
| 💰 Finance | `consulter_caisse`, `ajouter_depense`, `lister_depenses_periode`, `consulter_dettes_client`, `enregistrer_paiement_dette` | Comptable, Propriétaire |
| 👥 Clients | `ajouter_client`, `rechercher_client`, `lister_clients` | Tous rôles métier |
| 📊 Rapports | `generer_rapport_ventes`, `rapport_top_produits`, `rapport_chiffre_affaires`, `rapport_stock` | Propriétaire, Comptable |
| 🧑‍🤝‍🧑 Collaborateurs | `lister_collaborateurs`, `ajouter_collaborateur`, `modifier_role_collaborateur` | Propriétaire seul |
| 📅 Abonnement | `consulter_abonnement`, `voir_jours_restants`, `enregistrer_paiement_abonnement` | Propriétaire |
| 🏷️ QR | `generer_qr_produit`, `imprimer_etiquettes` | Magasinier, Propriétaire |
| ℹ️ Informations | `informations_entreprise`, `statistiques_globales` | Selon rôle |

⚠️ = action **destructive ou sensible** (voir § 11).

Chaque outil s'exécute **avec le JWT de l'utilisateur** : même si le modèle
proposait une action interdite, la RLS/permission serveur la refuse et
l'agent répond avec l'erreur traduite.

---

## 11. CONFIRMATION DES ACTIONS DESTRUCTIVES

Les outils suivants exigent un argument `confirmation: true` que **seul
l'utilisateur peut donner** (le prompt système demande à l'agent de
reformuler la demande et d'attendre un « oui » explicite) :

| Outil | Danger |
|---|---|
| `annuler_vente` | annule une vente, retire la caisse, restitue le stock |
| `supprimer_produit` | supprime un article du catalogue |
| `ajuster_stock` | corrige le stock (inventaire) |
| `modifier_produit` | uniquement quand le **prix** change |

Si le modèle appelle sans confirmation, la fonction renvoie
`MSG_CONFIRMATION` : l'erreur est **forcée côté serveur**, aucun contournement
possible.

---

## 12. LES ÉCRANS FLUTTER

| Écran | Route | Qui | Rôle |
|---|---|---|---|
| 💬 Assistant IA (chat) | `/assistant-ia` | rôles avec la page `assistant_ia` | Poser une question ; les actions exécutées s'affichent (✅/❌) ; coût en CDF et quotas après chaque réponse ; bouton « Acheter des quotas » quand le solde est à zéro. |
| 🛒 Quotas IA | `/achat-quotas` | tous les rôles métier | Soldes (pool + perso), les 4 packs (10/20/50/100), demande d'achat (mode : espèces, mobile money, carte, virement) ; le **propriétaire** attribue des quotas à son équipe ; le **Super Admin** approuve/refuse et marque payé. Le **montant est TOUJOURS affiché**, même impayé. |
| ⚙️ Configuration IA | `/agent-ia-config` | Super Admin (via `parametres/modifier`) | Tarif/quota (100–150 CDF), caractères par quota, prix du pack de 10, quotas offerts, activation/désactivation. Chaque enregistrement est journalisé (`AGENT_IA_CONFIG`, CRITIQUE). |

**Cycle d'un achat** : un membre demande un pack → le Super Admin approuve
(le pool est crédité atomiquement) → le paiement est suivi (IMPAYÉ / PAYÉ) →
quand le **propriétaire** marque « payé », une **vraie dépense** est écrite
dans sa caisse (catégorie `ia`, motif « Quotas IA — N quotas ») ; quand c'est
le Super Admin, il confirme simplement l'encaissement.

---

## 13. TESTS

```bash
# Tests unitaires du module (modèles, fautes/erreurs, catalogue d'outils)
flutter test test/agent_ia_test.dart

# Suite complète du projet (permissions incluses)
flutter test
```

L'Edge Function est validée hors ligne par `esbuild` (transpilation) +
`tsc --noEmit` (types), et les migrations SQL par le parseur PostgreSQL
(`check3.js`) : toutes les instructions passent sans erreur.

---

## 14. ÉTAPES DU MODULE (toutes livrées)

| Étape | Contenu | État |
|---|---|---|
| 1 | Tables + config + RLS (`20260916000014`) | ✅ |
| 2 | Edge Function `agent-ia` + débit atomique (`20260916000015`) | ✅ |
| 3 | Modèles Dart + `AgentService` | ✅ |
| 4 | Écran chat `/assistant-ia` | ✅ |
| 5 | Outils ventes & produits & stock (Étape 5) | ✅ |
| 6 | Achat de quotas `/achat-quotas` (`20260916000016`) | ✅ |
| 7 | Configuration IA `/agent-ia-config` (Super Admin) | ✅ |
| 8 | Outils finance, clients, rapports, collaborateurs, abonnement, QR | ✅ |
| 9 | Confirmations des actions destructives | ✅ |
| 10 | Tests (`test/agent_ia_test.dart`) + documentation | ✅ |
