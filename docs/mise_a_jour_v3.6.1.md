# Biashara Yangu — v3.6.1 (build 50)

**Type :** correctif bloquant — vente avec réduction.

**Migration SQL :** **une seule**, à exécuter dans le SQL Editor :

`supabase/migrations/20260916000110_fix_vente_conditionnement.sql`

---

## 1. `record "v_cond" is not assigned yet`

**Ce que le commerçant voyait**

> Lorsque j'ajoute la réduction et valide la vente : `record "v_cond" is not
> assigned yet`.

La vente était refusée, aucune ligne n'était enregistrée (la transaction est
tout ou rien : rien n'est perdu, rien n'est à moitié écrit).

**La cause**

Le récapitulatif renvoyé par `rpc_vente_valider` construisait le libellé du
conditionnement ainsi :

```sql
case when v_cond_id is null then null else v_cond.libelle end
```

PL/pgSQL prépare l'expression **entière** avant de l'exécuter : il lie le champ
`v_cond.libelle` même lorsque la branche n'est pas prise. Or `v_cond` n'est
renseigné que si la ligne possède un emballage. Toute vente d'articles vendus à
l'unité déclenchait donc l'erreur dès qu'un récapitulatif détaillé était
construit (réduction, cadeau ou négociation).

**La correction**

Le libellé est recopié dans une variable **texte** (`v_cond_libelle`) au moment
où le conditionnement est lu. Plus aucune expression ne touche le `record` :
la vente passe, avec ou sans emballage, avec ou sans réduction.

La fonction est remplacée à l'identique (même signature) : **aucune
modification de l'application n'est nécessaire côté téléphone**, mais cette
version embarque le correctif pour les nouvelles installations.

---

## À faire après la publication

1. Exécuter `20260916000110_fix_vente_conditionnement.sql`.
2. Retester une vente avec réduction sur un article vendu à l'unité.
3. Les migrations `0108` et `0109` de la 3.6.0 restent nécessaires si elles
   n'ont pas encore été exécutées.
