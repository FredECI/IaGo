// Testes das regras do Firestore no emulador (projeto demo-iago, sem conta).
// Rodar na raiz do projeto:
//   firebase emulators:exec --only firestore "node --test firestore-tests/rules.test.mjs"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  Bytes,
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  setDoc,
} from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-iago',
    firestore: {
      rules: readFileSync('firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8085,
    },
  });
});

after(async () => env.cleanup());

beforeEach(async () => env.clearFirestore());

const db = (uid) => env.authenticatedContext(uid).firestore();

test('o dono lê e escreve o perfil, as questões e as listas', async () => {
  const pedro = db('pedro');
  await assertSucceeds(setDoc(doc(pedro, 'users/pedro'), { name: 'Pedro' }));
  await assertSucceeds(setDoc(doc(pedro, 'users/pedro/questions/q1'), { statement: 'x' }));
  await assertSucceeds(setDoc(doc(pedro, 'users/pedro/lists/l1'), { name: 'Reforço' }));
  await assertSucceeds(getDoc(doc(pedro, 'users/pedro/questions/q1')));
  await assertSucceeds(deleteDoc(doc(pedro, 'users/pedro/lists/l1')));
});

test('ninguém lê nem escreve dados de outro usuário', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'users/pedro/questions/q1'), { statement: 'x' });
  });
  const ana = db('ana');
  await assertFails(getDoc(doc(ana, 'users/pedro/questions/q1')));
  await assertFails(setDoc(doc(ana, 'users/pedro/questions/q2'), { statement: 'y' }));
  await assertFails(getDoc(doc(ana, 'users/pedro')));
});

test('sem login, nada é lido nem escrito', async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, 'users/pedro')));
  await assertFails(setDoc(doc(anon, 'users/pedro/questions/q1'), { statement: 'x' }));
});

test('imagem compactada até 350 KB passa; acima disso é recusada', async () => {
  const pedro = db('pedro');
  const ok = Bytes.fromUint8Array(new Uint8Array(300 * 1024));
  const big = Bytes.fromUint8Array(new Uint8Array(400 * 1024));
  await assertSucceeds(setDoc(doc(pedro, 'users/pedro/questionImages/q1'), { bytes: ok }));
  await assertFails(setDoc(doc(pedro, 'users/pedro/questionImages/q2'), { bytes: big }));
  await assertFails(setDoc(doc(pedro, 'users/pedro/questionImages/q3'), { bytes: 'texto' }));
});

test('métricas agregadas: só administradores leem os eventos de todos', async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'admins/fred'), { since: '2026-11-03' });
    await setDoc(doc(ctx.firestore(), 'users/pedro/events/e1'), { type: 'question_saved' });
  });
  await assertSucceeds(getDocs(collectionGroup(db('fred'), 'events')));
  await assertFails(getDocs(collectionGroup(db('ana'), 'events')));
  // O dono não consulta os eventos de todos; lê só os dele, pelo caminho.
  await assertFails(getDocs(collectionGroup(db('pedro'), 'events')));
  await assertSucceeds(getDoc(doc(db('pedro'), 'users/pedro/events/e1')));
});

test('a lista de admins não pode ser alterada pelo app', async () => {
  await assertFails(setDoc(doc(db('ana'), 'admins/ana'), { since: 'hoje' }));
  await assertSucceeds(getDoc(doc(db('ana'), 'admins/ana')));
  await assertFails(getDoc(doc(db('ana'), 'admins/fred')));
});
