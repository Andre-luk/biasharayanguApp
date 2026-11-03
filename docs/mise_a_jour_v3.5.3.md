# Biashara Yangu — v3.5.3 (build 47)

**Type :** correctifs (SerdiPay + navigation des comptes de distribution)
**Migrations SQL :** aucune nouvelle (les `0100` → `0107` restent valables).

---

## 1. SerdiPay : « clientPhone: validation.required · telecom: validation.required »

Cause : le corps envoyé à `POST /merchant/payment-merchant` pouvait arriver
**sans** `clientPhone` ni `telecom`. Deux chemins concernés :

- le modèle surchargeable `SERDIPAY_CORPS_INITIER` (secret) — s'il est présent
  mais incomplet, il remplaçait le corps par défaut ;
- un numéro ou un opérateur vide dans la ligne ouverte en base.

Correction (Edge Function `serdipay`) : les **champs obligatoires sont
réinjectés** après application du modèle (`merchantCode`, `api_id`,
`api_password`, `merchant_pin`, `clientPhone`, `telecom`, `amount`,
`currency`). Un secret incomplet ne peut plus casser un paiement, et le journal
de la fonction indique lesquels ont été rétablis.

⚠️ **À faire : redéployer la fonction `serdipay`** (Supabase → Edge Functions →
coller `supabase/functions/serdipay/index.ts` → Deploy).

## 2. Comptes production / stock : uniquement leur espace

Un compte de distribution voyait les onglets de la boutique (Stock, Rapports)
et un écran Paramètres où il pouvait modifier des réglages.

- Un **membre de la distribution** n'a plus qu'un onglet : **Distribution**
  (ouvre `/main/distribution` — intrants, production, stock du module, caisse,
  commercial, traçabilité).
- L'accès **Paramètres** du rôle MAGASINIER est retiré (il n'a rien à y
  modifier).
- La **déconnexion** est déplacée là où elle sert : une icône dédiée dans la
  barre du haut de l'espace Distribution, avec confirmation et nettoyage de la
  session, du panier et de l'historique du scanner.

## 3. Rappel

Les membres de la distribution doivent retrouver leurs **intrants** dans
*Distribution → Stock → Intrants* et leurs **demandes** dans
*Distribution → Production → Demandes*. Si ces écrans sont vides, c'est que la
marchandise n'a pas encore été créée (intrants) ou que la production n'a pas
encore fabriqué de produits finis — le catalogue commercial ne montre que les
produits finis existants.
