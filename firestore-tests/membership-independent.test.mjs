// Membresia independente do Conecta: entrar no piloto com o fórum fechado.
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc } from 'firebase/firestore';

import { enter, newEnv, seed, ts } from './helpers.mjs';

let env;
before(async () => (env = await newEnv('demo-iago-member-indep')));
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const verified = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();
const unverified = (uid) => env.authenticatedContext(uid, { email_verified: false }).firestore();
const join = (over = {}) => ({
  nickname: 'novato',
  inviteCode: 'turma1',
  declaredMinAge: 18,
  rulesVersion: '1',
  joinedAt: ts(),
  ...over,
});
const closed = {
  'invites/turma1': { ok: true },
  'appConfig/runtime': { conectaEnabled: false, conectaWritesEnabled: false },
};

test('conecta fechado: e-mail verificado e convite válido criam membership + profile', async () => {
  await seed(env, closed);
  const db = verified('novo');
  await assertSucceeds(enter(doc(db, 'memberships/novo'), join()));
  await assertSucceeds(getDoc(doc(db, 'memberships/novo')));
});

test('conecta fechado: sem e-mail verificado, convite falso ou menor de idade, nega', async () => {
  await seed(env, closed);
  await assertFails(enter(doc(unverified('a'), 'memberships/a'), join()));
  await assertFails(enter(doc(verified('b'), 'memberships/b'), join({ inviteCode: 'falso' })));
  await assertFails(enter(doc(verified('c'), 'memberships/c'), join({ declaredMinAge: 17 })));
});
