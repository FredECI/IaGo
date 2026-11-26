// CA-A4 e CA-R4 (QA): não existe documento contador, e o id das avaliações
// precisa do uid, então não há como criar um "agregado" por questão.
import { after, before, beforeEach, test } from 'node:test';

import { assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';

import { baseScenario, newEnv, seed, ts } from './helpers.mjs';

let env;
before(async () => (env = await newEnv('demo-iago-rating-nocounter')));
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const ana = () => env.authenticatedContext('ana', { email_verified: true }).firestore();
const rating = (over = {}) => ({
  bankId: 'enem-2022-136', uid: 'ana', area: 'mathematics', subject: 'Matemática',
  difficulty: 2, quality: 2, updatedAt: ts(), ...over,
});

test('CA-A4: membro não cria documento contador nem agregado sem o uid no id', async () => {
  await seed(env, baseScenario());
  await assertFails(setDoc(doc(ana(), 'questionRatings/enem-2022-136'), rating()));
  await assertFails(setDoc(doc(ana(), 'questionRatings/enem-2022-136_total'), rating()));
  await assertFails(setDoc(doc(ana(), 'questionRatingCounts/enem-2022-136'), { count: 1, sum: 2 }));
  await assertFails(setDoc(doc(ana(), 'ratingCounters/enem-2022-136'), { count: 1 }));
});

test('CA-R4: bankId fora do padrão fonte-resto, nega', async () => {
  await seed(env, baseScenario());
  for (const id of ['ENEM-2022-1', 'enem_2022','-enem-1', 'enem']) {
    await assertFails(setDoc(doc(ana(), `questionRatings/${id}_ana`), rating({ bankId: id })));
  }
});
