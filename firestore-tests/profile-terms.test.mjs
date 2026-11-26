// F6 (QA): o que o cadastro e o aceite dos termos gravam em users/{uid} passa
// nas regras atuais. Usa o emulador do Auth (token real) e o do Firestore, com
// o SDK web, o mesmo caminho do app. Rodar com:
//   firebase emulators:exec --only auth,firestore --project demo-iago "node --test firestore-tests/profile-terms.test.mjs"
import { after, before, test as baseTest } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { initializeApp, deleteApp } from 'firebase/app';
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  getAuth,
  sendEmailVerification,
  signOut,
} from 'firebase/auth';
import {
  connectFirestoreEmulator,
  doc,
  getDoc,
  getFirestore,
  setDoc,
  Timestamp,
  collection,
  addDoc,
} from 'firebase/firestore';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

// No CI (só o emulador do Firestore) estes testes são pulados: precisam do Auth.
const hasAuth = Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST);
const test = (name, fn) => baseTest(name, { skip: !hasAuth && 'sem emulador do Auth' }, fn);
const PROJECT = 'demo-iago';
let app, auth, db;

before(async () => {
  if (!hasAuth) return;
  // Carrega as regras atuais no emulador (o emulators:exec já usa firebase.json,
  // mas garantimos o arquivo aqui também).
  const env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: { rules: readFileSync('firestore.rules', 'utf8'), host: '127.0.0.1', port: 8085 },
  });
  await env.cleanup();
  app = initializeApp({ apiKey: 'fake', projectId: PROJECT, authDomain: 'x' }, 'f6-qa');
  auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8085);
});
after(async () => app && deleteApp(app));

const signUp = async (email) => (await createUserWithEmailAndPassword(auth, email, 'segura123')).user;

// Mesmo mapa que FirebaseAuthRepository.signUp grava.
const signUpProfile = (email) => ({
  name: 'Pedro Lima',
  email,
  referralSource: 'friend',
  platformsBefore: ['Outra'],
  termsVersion: '2026-11-09',
  termsAcceptedAt: Timestamp.now(),
  declaredMinAge: 18,
  declaredMinAgeAt: Timestamp.now(),
  createdAt: Timestamp.now(),
});

test('cadastro: o perfil do signUp passa nas regras, com e-mail ainda não verificado', async () => {
  const user = await signUp('f6a@ex.com');
  assert.equal(user.emailVerified, false);
  await setDoc(doc(db, 'users', user.uid), signUpProfile('f6a@ex.com'));
  const snap = await getDoc(doc(db, 'users', user.uid));
  assert.equal(snap.data().termsVersion, '2026-11-09');
  assert.equal(snap.data().declaredMinAge, 18);
  // Evento signed_up do cadastro.
  await addDoc(collection(db, 'users', user.uid, 'events'), {
    type: 'signed_up',
    at: Timestamp.now(),
    referralSource: 'friend',
  });
});

test('cadastro: a verificação de e-mail é emitida pelo Auth', async () => {
  const user = await signUp('f6b@ex.com');
  await sendEmailVerification(user);
  const res = await fetch(`http://127.0.0.1:9099/emulator/v1/projects/${PROJECT}/oobCodes`);
  const { oobCodes } = await res.json();
  assert.ok(oobCodes.some((c) => c.email === 'f6b@ex.com' && c.requestType === 'VERIFY_EMAIL'));
});

test('acceptTerms: merge em perfil existente (conta antiga) passa e preserva os demais campos', async () => {
  const user = await signUp('f6c@ex.com');
  await setDoc(doc(db, 'users', user.uid), { name: 'Ana', email: 'f6c@ex.com', termsVersion: '2026-11-03' });
  await setDoc(
    doc(db, 'users', user.uid),
    {
      termsVersion: '2026-11-09',
      termsAcceptedAt: Timestamp.now(),
      declaredMinAge: 18,
      declaredMinAgeAt: Timestamp.now(),
    },
    { merge: true },
  );
  const d = (await getDoc(doc(db, 'users', user.uid))).data();
  assert.equal(d.termsVersion, '2026-11-09');
  assert.equal(d.name, 'Ana');
  assert.equal(d.declaredMinAge, 18);
});

test('acceptTerms: merge em perfil inexistente cria o documento (caso conta sem perfil)', async () => {
  const user = await signUp('f6d@ex.com');
  await setDoc(
    doc(db, 'users', user.uid),
    { termsVersion: '2026-11-09', termsAcceptedAt: Timestamp.now(), declaredMinAge: 18, declaredMinAgeAt: Timestamp.now() },
    { merge: true },
  );
  assert.equal((await getDoc(doc(db, 'users', user.uid))).data().termsVersion, '2026-11-09');
});

test('um usuário não grava nem lê o perfil de outro (aceite em nome alheio)', async () => {
  const a = await signUp('f6e@ex.com');
  await setDoc(doc(db, 'users', a.uid), signUpProfile('f6e@ex.com'));
  await signOut(auth);
  const b = await signUp('f6f@ex.com');
  await assert.rejects(
    setDoc(doc(db, 'users', a.uid), { termsVersion: 'x' }, { merge: true }),
    /permission/i,
  );
  await assert.rejects(getDoc(doc(db, 'users', a.uid)), /permission/i);
  assert.notEqual(a.uid, b.uid);
});

test('sem login, o perfil não é gravado', async () => {
  await signOut(auth);
  await assert.rejects(setDoc(doc(db, 'users', 'qualquer'), { termsVersion: 'x' }), /permission/i);
});
