// Avaliações públicas das questões do acervo (CA-A3, CA-R4).
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc } from 'firebase/firestore';

import { baseScenario, newEnv, past, seed, ts } from './helpers.mjs';

let env;
before(async () => (env = await newEnv('demo-iago-ratings')));
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const db = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();

const rating = (uid, over = {}) => ({
  bankId: 'enem-2022-136',
  uid,
  area: 'mathematics',
  subject: 'Matemática',
  difficulty: 2,
  quality: 3,
  updatedAt: ts(),
  ...over,
});
const path = (uid, bankId = 'enem-2022-136') => `questionRatings/${bankId}_${uid}`;

test('membro cria e altera a própria avaliação', async () => {
  await seed(env, baseScenario());
  await assertSucceeds(setDoc(doc(db('ana'), path('ana')), rating('ana')));
  await assertSucceeds(setDoc(doc(db('ana'), path('ana')), rating('ana', { difficulty: 3, quality: 1 })));
});

test('não membro, sem login e banido não avaliam', async () => {
  await seed(env, { ...baseScenario(), 'bans/bob': { at: 1, reason: 'x' } });
  await assertFails(setDoc(doc(db('estranho'), path('estranho')), rating('estranho')));
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(setDoc(doc(anon, path('ana')), rating('ana')));
  await assertFails(setDoc(doc(db('bob'), path('bob')), rating('bob')));
});

test('id de outra pessoa, id incoerente e uid falso, nega (CA-A3)', async () => {
  await seed(env, baseScenario());
  await assertFails(setDoc(doc(db('ana'), path('bob')), rating('bob')));
  await assertFails(setDoc(doc(db('ana'), path('bob')), rating('ana')));
  await assertFails(setDoc(doc(db('ana'), path('ana')), rating('bob')));
  await assertFails(setDoc(doc(db('ana'), path('ana', 'enem-2022-1')), rating('ana')));
  await assertFails(setDoc(doc(db('ana'), 'questionRatings/qualquer'), rating('ana')));
});

test('nota 0, 4, decimal ou texto, nega; 1 e 3 passam (CA-A3)', async () => {
  await seed(env, baseScenario());
  const ana = db('ana');
  for (const bad of [0, 4, 2.5, '2', null, -1]) {
    await assertFails(setDoc(doc(ana, path('ana')), rating('ana', { difficulty: bad })));
    await assertFails(setDoc(doc(ana, path('ana')), rating('ana', { quality: bad })));
  }
  await assertSucceeds(setDoc(doc(ana, path('ana')), rating('ana', { difficulty: 1, quality: 3 })));
});

test('data do cliente e campo extra, nega', async () => {
  await seed(env, baseScenario());
  await assertFails(setDoc(doc(db('ana'), path('ana')), rating('ana', { updatedAt: new Date() })));
  await assertFails(setDoc(doc(db('ana'), path('ana')), rating('ana', { comment: 'oi' })));
});

test('bankId fora do padrão, nega; de outra fonte no padrão, aceita (CA-R4)', async () => {
  await seed(env, baseScenario());
  const ana = db('ana');
  for (const bad of ['semtraco', 'Enem-2022-1', '1enem-2022-1', '-enem', 'enem-', 'enem 2022', 'enem_2022', 'a-' + 'x'.repeat(60), 'enem.2022', 7]) {
    await assertFails(setDoc(doc(ana, `questionRatings/${bad}_ana`), rating('ana', { bankId: bad })));
  }
  await assertSucceeds(
    setDoc(doc(ana, path('ana', 'obmep-2019-12')), rating('ana', { bankId: 'obmep-2019-12' })),
  );
  await assertSucceeds(
    setDoc(doc(ana, path('ana', 'enem-2022-136-ingles')), rating('ana', { bankId: 'enem-2022-136-ingles' })),
  );
});

test('leitura: só membro lê; não membro, banido e anônimo não', async () => {
  await seed(env, { ...baseScenario(), 'bans/bob': { at: 1, reason: 'x' }, [path('ana')]: { ...rating('ana'), updatedAt: past(5) } });
  await assertSucceeds(getDoc(doc(db('mod'), path('ana'))));
  await assertSucceeds(getDoc(doc(db('ana'), path('ana'))));
  await assertFails(getDoc(doc(db('estranho'), path('ana'))));
  await assertFails(getDoc(doc(db('bob'), path('ana'))));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), path('ana'))));
});

test('exclusão: a própria passa (inclusive de quem saiu); a de outra pessoa, nega', async () => {
  await seed(env, {
    ...baseScenario(),
    [path('ana')]: { ...rating('ana'), updatedAt: past(5) },
    [path('saiu')]: { ...rating('saiu'), updatedAt: past(5) },
  });
  await assertFails(deleteDoc(doc(db('bob'), path('ana'))));
  await assertFails(deleteDoc(doc(db('mod'), path('ana'))));
  await assertSucceeds(deleteDoc(doc(db('ana'), path('ana'))));
  await assertSucceeds(deleteDoc(doc(db('saiu'), path('saiu'))));
});

test('area fora das 4 áreas, matéria vazia, longa ou não texto, e os dois campos ausentes, nega', async () => {
  await seed(env, baseScenario());
  const ana = db('ana');
  for (const area of ['biologia', 'mathematics ', { x: 1 }, 7, null]) {
    await assertFails(setDoc(doc(ana, path('ana')), rating('ana', { area })));
  }
  for (const subject of ['', 'x'.repeat(61), { x: 1 }, 3, null]) {
    await assertFails(setDoc(doc(ana, path('ana')), rating('ana', { subject })));
  }
  const { area, ...semArea } = rating('ana');
  const { subject, ...semMateria } = rating('ana');
  await assertFails(setDoc(doc(ana, path('ana')), semArea));
  await assertFails(setDoc(doc(ana, path('ana')), semMateria));
  for (const a of ['languages', 'humanities', 'naturalSciences', 'mathematics']) {
    await assertSucceeds(setDoc(doc(ana, path('ana')), rating('ana', { area: a, subject: 'x'.repeat(60) })));
  }
});
