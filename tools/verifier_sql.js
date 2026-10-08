#!/usr/bin/env node
// ============================================================================
//  BIASHARA YANGU — validation syntaxique d'un fichier SQL
//  Fichier : tools/verifier_sql.js
// ============================================================================
//
//  POURQUOI
//  --------
//  Une migration PostgreSQL qui contient une erreur de syntaxe échoue au
//  milieu de son exécution dans le SQL Editor : les objets déjà créés restent
//  en place et la base se retrouve dans un état intermédiaire. Mieux vaut le
//  savoir AVANT de coller le fichier.
//
//  Ce script découpe le fichier en instructions et les fait analyser par le
//  VÉRITABLE parseur PostgreSQL (libpg-query, le parseur du serveur compilé en
//  WebAssembly) : c'est exactement la grammaire qui acceptera ou refusera la
//  migration.
//
//  ⚠️ Il ne se connecte à AUCUNE base : c'est une analyse de syntaxe pure.
//     Il ne détecte donc pas une table manquante ni un type incompatible.
//
//  MISE EN PLACE
//  -------------
//      mkdir -p /tmp/sqlcheck && cd /tmp/sqlcheck
//      npm init -y && npm install libpg-query
//
//  UTILISATION
//  -----------
//      NODE_PATH=/tmp/sqlcheck/node_modules \
//        node tools/verifier_sql.js supabase/migrations/ma_migration.sql
//
//  Sortie : « N/N instructions valides » → code de sortie 0. Sinon, les
//  instructions fautives sont listées avec leur numéro de ligne.
//
//  BONUS : les corps des fonctions PL/pgSQL et des blocs DO sont rejoués avec
//  le parseur PL/pgSQL du serveur. C'est précieux ici, car le parseur SQL
//  valide bien `create function ... $$ … $$` mais IGNORE le contenu du
//  littéral : une faute de frappe dans le corps ne serait signalée qu'à
//  l'exécution, au milieu de la migration.
// ============================================================================

'use strict';

const fs = require('fs');
const { loadModule, parseSync, parsePlPgSQLSync } = require('libpg-query');

// ⚠️ Le parseur est compilé en WebAssembly : sans cette initialisation, les
//    appels SYNCHRONES échouent par « WASM module not initialized ».

/** Extrait les corps dollar-quotés d'une instruction (utilisé pour le
diagnostic quand une erreur est signalée). */
function corpsPlpgsql(texte) {
  const corps = [];
  const motif = /\$([A-Za-z_][A-Za-z0-9_]*)?\$([\s\S]*?)\$\1\$/g;
  let m;
  while ((m = motif.exec(texte)) !== null) corps.push(m[2]);
  return corps;
}

/** L'instruction porte-t-elle du code PL/pgSQL ?
 *  On ne se fie PAS à « create function » seul : une fonction LANGUAGE sql
 *  n'est pas du PL/pgSQL et doit rester au parseur SQL. */
function estPlpgsql(texte) {
  if (/^\s*do\s/i.test(texte)) return true;
  return /language\s+plpgsql/i.test(texte);
}

/** Découpe un script SQL en instructions, en respectant :
 *   • les chaînes '…' et "…" (avec '' et "" comme échappement) ;
 *   • les littéraux dollar-quotés ($$…$$, $tag$…$tag$) — indispensables ici,
 *     tout le projet écrit ses fonctions PL/pgSQL ainsi ;
 *   • les commentaires -- et les blocs /* … *​/.
 *  Un `;` n'est un séparateur que hors de tout cela. */
function decouper(sql) {
  const instructions = [];
  let courant = '';
  let ligne = 1;
  let ligneDebut = 1;
  let i = 0;
  let tagDollar = null;

  while (i < sql.length) {
    const c = sql[i];
    const suivant = sql[i + 1];

    // — Dans un littéral dollar-quoté : on cherche le tag de fermeture —
    if (tagDollar !== null) {
      if (sql.startsWith(tagDollar, i)) {
        courant += tagDollar;
        i += tagDollar.length;
        tagDollar = null;
        continue;
      }
      if (c === '\n') ligne++;
      courant += c;
      i++;
      continue;
    }

    // — Commentaire de ligne —
    if (c === '-' && suivant === '-') {
      const fin = sql.indexOf('\n', i);
      const bout = fin === -1 ? sql.length : fin;
      courant += sql.slice(i, bout);
      i = bout;
      continue;
    }

    // — Commentaire de bloc —
    if (c === '/' && suivant === '*') {
      const fin = sql.indexOf('*/', i + 2);
      const bout = fin === -1 ? sql.length : fin + 2;
      const bloc = sql.slice(i, bout);
      ligne += (bloc.match(/\n/g) || []).length;
      courant += bloc;
      i = bout;
      continue;
    }

    // — Chaîne simple ou identifiant entre guillemets —
    if (c === "'" || c === '"') {
      const quote = c;
      let j = i + 1;
      while (j < sql.length) {
        if (sql[j] === quote && sql[j + 1] === quote) { j += 2; continue; }
        if (sql[j] === quote) break;
        if (sql[j] === '\n') ligne++;
        j++;
      }
      courant += sql.slice(i, j + 1);
      i = j + 1;
      continue;
    }

    // — Ouverture d'un littéral dollar-quoté ($$ ou $tag$) —
    if (c === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i));
      if (m) {
        tagDollar = m[0];
        courant += tagDollar;
        i += tagDollar.length;
        continue;
      }
    }

    // — Séparateur d'instruction —
    if (c === ';') {
      courant += c;
      instructions.push({ texte: courant, ligne: ligneDebut });
      courant = '';
      i++;
      ligneDebut = ligne;
      continue;
    }

    if (c === '\n') { ligne++; if (courant.trim() === '') ligneDebut = ligne; }
    courant += c;
    i++;
  }

  if (courant.trim() !== '') instructions.push({ texte: courant, ligne: ligneDebut });
  return instructions;
}

/** Une instruction sans autre contenu qu'un commentaire ne se parse pas. */
function estVide(texte) {
  return texte
    .replace(/--[^\n]*/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .trim() === '';
}

function main() {
  const chemin = process.argv[2];
  if (!chemin) {
    console.error('Usage : node tools/verifier_sql.js <fichier.sql>');
    process.exit(2);
  }
  if (!fs.existsSync(chemin)) {
    console.error(`❌ Fichier introuvable : ${chemin}`);
    process.exit(2);
  }

  const sql = fs.readFileSync(chemin, 'utf8');
  const instructions = decouper(sql);

  loadModule().then(() => verifier(instructions));
}

function verifier(instructions) {
  const echecs = [];
  let valides = 0;

  for (const { texte, ligne } of instructions) {
    if (estVide(texte)) continue;

    // ⚠️ Pour une instruction PL/pgSQL, c'est `parsePlPgSQLSync` qu'il faut
    //    appeler — et sur l'INSTRUCTION ENTIÈRE (`do $$ … $$;` ou
    //    `create function … as $$ … $$ language plpgsql;`) : lui seul ouvre le
    //    littéral dollar-quoté et analyse le corps. Le parseur SQL, lui,
    //    valide le squelette mais IGNORE le contenu du $$ … $$.
    //    Le repli sur `parseSync` évite tout faux positif.
    const plpgsql = estPlpgsql(texte);
    let erreur = null;

    if (plpgsql) {
      try {
        parsePlPgSQLSync(texte);
      } catch (e) {
        erreur = e;
        try {
          parseSync(texte);
          erreur = null; // le SQL passe : on ne signale rien
        } catch (_) {
          /* on garde l'erreur PL/pgSQL, plus précise */
        }
      }
    } else {
      try {
        parseSync(texte);
      } catch (e) {
        erreur = e;
      }
    }

    if (!erreur) {
      valides++;
      continue;
    }

    echecs.push({
      ligne,
      message: (plpgsql ? 'corps PL/pgSQL : ' : '') +
        String(erreur.message || erreur).split('\n')[0],
      extrait: texte.trim().split('\n').slice(0, 4).join(' ').slice(0, 160),
    });
  }

  const total = valides + echecs.length;
  if (echecs.length === 0) {
    console.log(`${total}/${total} instructions valides.`);
    process.exit(0);
  }

  console.log(`${valides}/${total} instructions valides — ${echecs.length} EN ERREUR :\n`);
  for (const e of echecs) {
    console.log(`  ⛔ ligne ${e.ligne} : ${e.message}`);
    console.log(`     ${e.extrait}\n`);
  }
  process.exit(1);
}

main();
