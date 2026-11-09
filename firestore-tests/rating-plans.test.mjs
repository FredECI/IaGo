// Avaliações: executa, campo a campo, os MESMOS lotes que o app monta
// (lib/data/firebase/rating_write_plans.dart). O fixture
// fixtures/rating_plans.json é gerado por test/data/rating_rules_fixture_test.dart,
// que falha se ele ficar desatualizado. Cobre CA-A1, CA-A2 (leitura agregada),
// CA-A3, CA-A5 e a matéria vazia (AV1).
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  average,
  collection,
  count,
  deleteField,
  doc,
  getAggregateFromServer,
  getDoc,
  query,
  where,
  writeBatch,
} from 'firebase/firestore';

import { baseScenario, newEnv, past, seed, ts } from './helpers.mjs';

const PLANS = JSON.parse(readFileSync('firestore-tests/fixtures/rating_plans.json', 'utf8'));

let env;
before(async () => (env = await newEnv('demo-iago-rating-plans')));
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const db = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();
const plan = (name) => structuredClone(PLANS[name]);
const decode = (v) => {
  if (v && typeof v === 'object' && '$' in v) return v.$ === 'delete' ? deleteField() : ts();
  return v;
};

function run(uid, writes) {
  const d = db(uid);
  const batch = writeBatch(d);
  for (const w of writes) {
    const ref = doc(d, w.path);
    const data = w.data && Object.fromEntries(Object.entries(w.data).map(([k, v]) => [k, decode(v)]));
    if (w.kind === 'set') batch.set(ref, data);
    else if (w.kind === 'update') batch.update(ref, data);
    else batch.delete(ref);
  }
  return batch.commit();
}

const mutated = (name, fn) => {
  const p = plan(name);
  fn(p);
  return p;
};
const data = (p) => p[0].data;

const stored = (uid, over = {}) => ({
  bankId: 'enem-2022-136',
  uid,
  area: 'mathematics',
  subject: 'Matemática',
  difficulty: 2,
  quality: 2,
  updatedAt: past(5),
  ...over,
});

test('CA-A1: o lote do app avalia, altera e remove; fica uma avaliação por pessoa', async () => {
  await seed(env, baseScenario());
  await assertSucceeds(run('ana', plan('rate')));
  await assertSucceeds(run('ana', plan('rateChange')));
  const d = await getDoc(doc(db('ana'), 'questionRatings/enem-2022-136_ana'));
  if (d.data().difficulty !== 3 || d.data().quality !== 1) throw new Error('alteração perdida');
  await assertSucceeds(run('ana', plan('remove')));
  if ((await getDoc(doc(db('ana'), 'questionRatings/enem-2022-136_ana'))).exists()) throw new Error('não removeu');
});

test('avaliação: de outra fonte e questão sem matéria (grupo = rótulo da área) passam', async () => {
  await seed(env, baseScenario());
  await assertSucceeds(run('ana', plan('rateOtherSource')));
  await assertSucceeds(run('ana', plan('rateNoSubject')));
  const d = await getDoc(doc(db('ana'), 'questionRatings/enem-2022-12_ana'));
  if (d.data().subject !== 'Ciências da Natureza') throw new Error(`subject: ${d.data().subject}`);
  // Matéria muito longa é cortada em 60 antes de gravar.
  await assertSucceeds(run('ana', plan('rateLongSubject')));
});

test('CA-A3: variações proibidas do lote (nota, uid, id, área, matéria, data, campo extra)', async () => {
  await seed(env, baseScenario());
  const bad = [
    (p) => (data(p).difficulty = 0),
    (p) => (data(p).difficulty = 4),
    (p) => (data(p).quality = 2.5),
    (p) => (data(p).quality = '2'),
    (p) => (data(p).uid = 'bob'),
    (p) => (data(p).bankId = 'enem-2022-1'),
    (p) => (data(p).area = 'biologia'),
    (p) => (data(p).subject = ''),
    (p) => (data(p).subject = 'x'.repeat(61)),
    (p) => (data(p).updatedAt = '2020-01-01'),
    (p) => (data(p).comment = 'oi'),
    (p) => (p[0].path = 'questionRatings/enem-2022-136_bob'),
  ];
  for (const fn of bad) await assertFails(run('ana', mutated('rate', fn)));
  // Não membro não avalia nem lê.
  await assertFails(run('estranho', mutated('rate', (p) => {
    data(p).uid = 'estranho';
    p[0].path = 'questionRatings/enem-2022-136_estranho';
  })));
});

test('CA-A3: remover a avaliação de outra pessoa, nega', async () => {
  await seed(env, { ...baseScenario(), 'questionRatings/enem-2022-136_ana': stored('ana') });
  await assertFails(run('bob', plan('remove')));
  await assertSucceeds(run('ana', plan('remove')));
});

test('CA-A2/CA-A4: a agregação do app (count, average) funciona para membro, sem documento contador', async () => {
  await seed(env, {
    ...baseScenario(),
    'questionRatings/enem-2022-136_ana': stored('ana', { difficulty: 3, quality: 3 }),
    'questionRatings/enem-2022-136_bob': stored('bob', { difficulty: 2, quality: 2 }),
    'questionRatings/enem-2022-136_mod': stored('mod', { difficulty: 1, quality: 1 }),
    'questionRatings/enem-2022-7_ana': stored('ana', { bankId: 'enem-2022-7', difficulty: 3, quality: 1 }),
  });
  const ana = db('ana');
  const q = await assertSucceeds(
    getAggregateFromServer(
      query(collection(ana, 'questionRatings'), where('bankId', '==', 'enem-2022-136')),
      { n: count(), d: average('difficulty'), q: average('quality') },
    ),
  );
  if (q.data().n !== 3 || q.data().d !== 2 || q.data().q !== 2) throw new Error(JSON.stringify(q.data()));
  const g = await assertSucceeds(
    getAggregateFromServer(
      query(collection(ana, 'questionRatings'), where('subject', '==', 'Matemática')),
      { n: count(), d: average('difficulty') },
    ),
  );
  if (g.data().n !== 4) throw new Error(`grupo: ${g.data().n}`);
  // Não membro não agrega.
  await assertFails(
    getAggregateFromServer(
      query(collection(db('estranho'), 'questionRatings'), where('bankId', '==', 'enem-2022-136')),
      { n: count() },
    ),
  );
});

test('CA-A5: a nota privada grava só myDifficulty/myQuality e não mexe em updatedAt', async () => {
  const created = past(900);
  const edited = past(800);
  await seed(env, {
    'users/ana/questions/bank_enem-2022-136': {
      statement: 'x', createdAt: created, updatedAt: edited, origin: 'bank', bankId: 'enem-2022-136',
    },
    'users/ana/questions/q1': { statement: 'y', createdAt: created, updatedAt: created, myDifficulty: 1, myQuality: 1 },
  });
  const path = 'users/ana/questions/bank_enem-2022-136';
  await assertSucceeds(run('ana', plan('privateRate')));
  const after = (await getDoc(doc(db('ana'), path))).data();
  if (after.myDifficulty !== 2 || after.myQuality !== 3) throw new Error('nota não gravada');
  if (!after.updatedAt.isEqual(edited) || !after.createdAt.isEqual(created)) throw new Error('updatedAt mudou');
  // Apagar a nota remove os campos e também preserva updatedAt.
  await assertSucceeds(run('ana', plan('privateClear')));
  const cleared = (await getDoc(doc(db('ana'), 'users/ana/questions/q1'))).data();
  if ('myDifficulty' in cleared || 'myQuality' in cleared) throw new Error('nota não apagada');
  if (!cleared.updatedAt.isEqual(created)) throw new Error('updatedAt mudou');
  // Só o dono grava.
  await assertFails(run('bob', mutated('privateRate', (p) => (p[0].path = path))));
});
