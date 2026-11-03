# Biashara Yangu — v3.5.4 (build 48)

**Type :** correctifs SerdiPay (côté serveur) — l'application elle-même n'a pas
changé de comportement depuis la 3.5.3.

**Migrations SQL :** aucune nouvelle.

---

## 1. « clientPhone: validation.required · telecom: validation.required »

Diagnostic mené en interrogeant directement l'API SerdiPay (via l'endpoint
`/diag-paiement`, sans créer de transaction) :

| Corps envoyé | Réponse |
|---|---|
| `{}` | `400` « Wrong Merchant code send » |
| champs complets + `clientPhone:""`, `telecom:""` | `400` **le message exact signalé** |
| champs complets + numéro réel + 100 CDF | `402` « amount is not within allowed range! min: 2300 – max : 5750000 CDF » |

Conclusion : les noms de champs sont bons, les identifiants sont acceptés ;
seules **les valeurs étaient vides**.

Correction (Edge Function `serdipay`) :

- le téléphone et l'opérateur sont repris de la **requête** quand la ligne
  ouverte en base ne les contient pas ;
- **tous** les champs obligatoires sont réinjectés après application d'un
  éventuel modèle `SERDIPAY_CORPS_INITIER` (un secret incomplet ne peut plus
  casser un paiement) ;
- le journal de la fonction indique les champs rétablis.

## 2. Barème Mobile Money

SerdiPay n'accepte que **2 300 à 5 750 000 CDF** par transaction. En dehors de
cette plage, la fonction renvoie désormais un message clair
(`MONTANT_HORS_BAREME`) au lieu du message technique du fournisseur.
Une avance de 1 000 CDF par Mobile Money n'est donc pas possible.

Bornes surchargeables par `SERDIPAY_MONTANT_MIN` / `SERDIPAY_MONTANT_MAX`.

---

## À faire

1. **Redéployer la fonction `serdipay`** (le code est dans
   `supabase/functions/serdipay/index.ts`).
2. Aucune migration à exécuter.
3. Publier cette version si tu veux que les téléphones affichent la bonne
   version ; les correctifs de paiement, eux, sont **déjà actifs** dès le
   redéploiement, même sur les anciennes installations.
