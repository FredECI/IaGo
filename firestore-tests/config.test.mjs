// Configuração, papéis e isolamento de users/** (sem mudança de comportamento).
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc } from 'firebase/firestore';

import { baseScenario, newEnv, seed } from './helpers.mjs';

let env;
before(async () => (env = await newEnv('demo-iago-config')));
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const db = (uid, claims) => env.authenticatedContext(uid, claims).firestore();

test('appConfig: só quem está autenticado lê; ninguém escreve', async () => {
  await seed(env, baseScenario());
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, 'appConfig/runtime')));
  await assertSucceeds(getDoc(doc(db('ana'), 'appConfig/runtime')));
  await assertFails(setDoc(doc(db('ana'), 'appConfig/runtime'), { conectaWritesEnabled: true }));
  await assertFails(setDoc(doc(db('mod'), 'appConfig/runtime'), { conectaWritesEnabled: true }));
  await assertFails(setDoc(doc(db('ana'), 'appConfig/outro'), { x: 1 }));
  await assertFails(deleteDoc(doc(db('ana'), 'appConfig/runtime')));
});

test('invites: ninguém lê nem escreve pelo app', async () => {
  await seed(env, baseScenario());
  await assertFails(getDoc(doc(db('ana'), 'invites/turma1')));
  await assertFails(getDocs(collection(db('ana'), 'invites')));
  await assertFails(setDoc(doc(db('ana'), 'invites/meu'), { ok: true }));
});

test('moderators: só o próprio lê; ninguém escreve', async () => {
  await seed(env, baseScenario());
  await assertSucceeds(getDoc(doc(db('mod'), 'moderators/mod')));
  await assertFails(getDoc(doc(db('ana'), 'moderators/mod')));
  await assertFails(setDoc(doc(db('ana'), 'moderators/ana'), { ok: true }));
  await assertFails(setDoc(doc(db('mod'), 'moderators/mod2'), { ok: true }));
});

test('bans: moderador escreve; o banido lê o próprio; outro membro não lê', async () => {
  await seed(env, { ...baseScenario(), 'bans/bob': { at: 1, reason: 'spam' } });
  await assertSucceeds(setDoc(doc(db('mod'), 'bans/ana'), { at: 2, reason: 'spam' }));
  await assertFails(setDoc(doc(db('ana'), 'bans/bob2'), { at: 2, reason: 'x' }));
  await assertSucceeds(getDoc(doc(db('bob'), 'bans/bob')));
  await assertFails(getDoc(doc(db('ana'), 'bans/bob')));
  await assertSucceeds(getDoc(doc(db('mod'), 'bans/bob')));
  await assertFails(deleteDoc(doc(db('ana'), 'bans/bob')));
  await assertSucceeds(deleteDoc(doc(db('mod'), 'bans/bob')));
});

test('users/**: isolamento com membros e o comportamento atual do dono', async () => {
  await seed(env, {
    ...baseScenario(),
    'users/pedro': { name: 'Pedro' },
    'users/pedro/questions/q1': { statement: 'x' },
    'users/pedro/events/e1': { type: 'active' },
  });
  // Membro e moderador não leem dados privados de outro usuário.
  await assertFails(getDoc(doc(db('ana'), 'users/pedro')));
  await assertFails(getDoc(doc(db('mod'), 'users/pedro/questions/q1')));
  await assertFails(getDocs(collection(db('ana'), 'users/pedro/questions')));
  await assertFails(setDoc(doc(db('ana'), 'users/pedro/questions/q2'), { statement: 'y' }));
  // O dono continua lendo e gravando tudo, inclusive campos novos do perfil.
  const pedro = db('pedro');
  await assertSucceeds(
    setDoc(doc(pedro, 'users/pedro'), { name: 'Pedro', declaredMinAge: 18, aiNoticeVersion: '1' }),
  );
  await assertSucceeds(
    setDoc(doc(pedro, 'users/pedro/questions/bank_enem-2022-136'), {
      origin: 'bank',
      bankId: 'enem-2022-136',
    }),
  );
  await assertSucceeds(deleteDoc(doc(pedro, 'users/pedro/questions/q1')));
});

test('users/{uid}/direction e directionSteps: só o dono lê e grava', async () => {
  await seed(env, {
    ...baseScenario(),
    'users/pedro/direction/goal': { exam: 'enem', weeklyHours: 10 },
    'users/pedro/directionSteps/s1': { action: 'collect', status: 'proposed' },
  });
  const pedro = db('pedro');
  await assertSucceeds(getDoc(doc(pedro, 'users/pedro/direction/goal')));
  await assertSucceeds(
    setDoc(doc(pedro, 'users/pedro/direction/goal'), { exam: 'enem', weeklyHours: 12 }),
  );
  await assertSucceeds(
    setDoc(doc(pedro, 'users/pedro/directionSteps/s2'), { action: 'review', status: 'accepted' }),
  );
  await assertSucceeds(getDocs(collection(pedro, 'users/pedro/directionSteps')));
  await assertSucceeds(deleteDoc(doc(pedro, 'users/pedro/directionSteps/s1')));

  for (const other of [db('ana'), db('mod'), env.unauthenticatedContext().firestore()]) {
    await assertFails(getDoc(doc(other, 'users/pedro/direction/goal')));
    await assertFails(setDoc(doc(other, 'users/pedro/direction/goal'), { exam: 'outro' }));
    await assertFails(getDocs(collection(other, 'users/pedro/directionSteps')));
    await assertFails(setDoc(doc(other, 'users/pedro/directionSteps/s9'), { action: 'collect' }));
    await assertFails(deleteDoc(doc(other, 'users/pedro/directionSteps/s2')));
  }
});

test('events: o dono lê os próprios, outro usuário não (sem mudança)', async () => {
  await seed(env, { 'admins/fred': { since: 1 }, 'users/pedro/events/e1': { type: 'active' } });
  await assertSucceeds(getDoc(doc(db('pedro'), 'users/pedro/events/e1')));
  await assertFails(getDoc(doc(db('ana'), 'users/pedro/events/e1')));
});
