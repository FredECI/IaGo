// F6 (revisor): depois de verificar o e-mail, `user.reload()` não renova o ID
// token; a regra de memberships lê `request.auth.token.email_verified`. O app
// precisa chamar `getIdToken(true)` (FirebaseAuthRepository.refreshEmailVerified).
//   firebase emulators:exec --only auth,firestore --project demo-iago "node --test firestore-tests/email-verified-token.test.mjs"
import { after, before, test as baseTest } from 'node:test';
import assert from 'node:assert/strict';

import { initializeApp, deleteApp } from 'firebase/app';
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
  reload,
  sendEmailVerification,
} from 'firebase/auth';
import { connectFirestoreEmulator, doc, getFirestore, serverTimestamp, writeBatch } from 'firebase/firestore';

import { newEnv, seed } from './helpers.mjs';

// No CI (só o emulador do Firestore) o teste é pulado: precisa do Auth.
const hasAuth = Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST);
const test = (name, fn) => baseTest(name, { skip: !hasAuth && 'sem emulador do Auth' }, fn);
const PROJECT = 'demo-iago-evt'; // Firestore isolado; o Auth do emulador é o demo-iago
let app, auth, db, env;

before(async () => {
  if (!hasAuth) return;
  env = await newEnv(PROJECT);
  await seed(env, {
    'appConfig/runtime': { conectaEnabled: true },
    'invites/turma1': { ok: true },
  });
  app = initializeApp({ apiKey: 'fake', projectId: PROJECT, authDomain: 'x' }, 'f6-token');
  auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8085);
});
after(async () => {
  if (app) await deleteApp(app);
  if (env) await env.cleanup();
});

// Mesmo lote de CommunityRepository.join (membership + perfil público).
const join = (uid) => {
  const batch = writeBatch(db);
  batch.set(doc(db, `memberships/${uid}`), {
    nickname: 'ana_estuda',
    inviteCode: 'turma1',
    declaredMinAge: 18,
    rulesVersion: '2026-11-08',
    joinedAt: serverTimestamp(),
  });
  batch.set(doc(db, `profiles/${uid}`), { nickname: 'ana_estuda', joinedAt: serverTimestamp() });
  return batch.commit();
};

test('reload não basta: sem renovar o token a entrada é negada; com getIdToken(true) passa', async () => {
  const email = 'token@ex.com';
  const user = (await createUserWithEmailAndPassword(auth, email, 'segura123')).user;
  await sendEmailVerification(user);

  // Verifica pelo link do emulador (oobCode).
  const res = await fetch(`http://127.0.0.1:9099/emulator/v1/projects/demo-iago/oobCodes`);
  const { oobCodes } = await res.json();
  const code = oobCodes.filter((c) => c.email === email && c.requestType === 'VERIFY_EMAIL').at(-1);
  assert.ok(code, 'o emulador emitiu o código de verificação');
  await fetch(code.oobLink);

  await reload(user);
  assert.equal(auth.currentUser.emailVerified, true, 'o usuário local já consta como verificado');

  // Token antigo: email_verified ainda é false.
  await assert.rejects(join(user.uid), /permission/i);

  // Renovado, a mesma entrada passa.
  await auth.currentUser.getIdToken(true);
  await join(user.uid);
});
