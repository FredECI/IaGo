// C5 / CA-T7: exclusão de conta em cascata, contra as regras reais e com o
// emulador do Auth (token real, e-mail verificado). Espelha em JS a sequência de
// lib/data/firebase/account_erasure.dart + firebase_auth_repository.dart
// (inventário, dados públicos, membro/perfil/limite, subcoleções, usuário do
// Auth) e confere a forma dos lotes com o fixture gerado pelo Dart
// (fixtures/erasure_plans.json, testado em test/data/account_erasure_test.dart).
// Rodar com:
//   firebase emulators:exec --only auth,firestore --project demo-iago "node --test firestore-tests/account-erasure.test.mjs"
// No CI (só o Firestore) estes testes são pulados: precisam do Auth.
import { after, before, test as baseTest } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { initializeApp, deleteApp } from 'firebase/app';
import {
  connectAuthEmulator,
  createUserWithEmailAndPassword,
  deleteUser,
  getAuth,
  sendEmailVerification,
  signInWithEmailAndPassword,
} from 'firebase/auth';
import {
  collection,
  collectionGroup,
  connectFirestoreEmulator,
  doc,
  getDocs,
  getFirestore,
  query,
  serverTimestamp,
  setDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

import { newEnv, past } from './helpers.mjs';

const hasAuth = Boolean(process.env.FIREBASE_AUTH_EMULATOR_HOST);
const test = (name, fn) => baseTest(name, { skip: !hasAuth && 'sem emulador do Auth' }, fn);
const PROJECT = 'demo-iago-c5';
const FIXTURE = JSON.parse(readFileSync('firestore-tests/fixtures/erasure_plans.json', 'utf8'));
const USER_COLLECTIONS = ['questions', 'questionImages', 'lists', 'events', 'direction', 'directionSteps'];

let env, app, auth, db;
let n = 0;

before(async () => {
  if (!hasAuth) return;
  env = await newEnv(PROJECT);
  app = initializeApp({ apiKey: 'fake', projectId: PROJECT, authDomain: 'x' }, 'c5-qa');
  auth = getAuth(app);
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true });
  db = getFirestore(app);
  connectFirestoreEmulator(db, '127.0.0.1', 8085);
});
after(async () => {
  if (!hasAuth) return;
  await deleteApp(app);
  await env.cleanup();
});

const seed = (entries) =>
  env.withSecurityRulesDisabled(async (ctx) => {
    for (const [path, data] of Object.entries(entries)) await setDoc(doc(ctx.firestore(), path), data);
  });

// Cadastra, verifica o e-mail no emulador e renova o token (como refreshEmailVerified).
async function newVerifiedUser() {
  const email = `c5-${Date.now()}-${n++}@ex.com`;
  const user = (await createUserWithEmailAndPassword(auth, email, 'segura123')).user;
  await sendEmailVerification(user);
  const { oobCodes } = await (
    await fetch(`http://127.0.0.1:9099/emulator/v1/projects/demo-iago/oobCodes`)
  ).json();
  const code = oobCodes.filter((c) => c.email === email && c.requestType === 'VERIFY_EMAIL').pop().oobCode;
  await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:update?key=fake', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ oobCode: code }),
  });
  await user.reload();
  await user.getIdToken(true);
  return { user, email };
}

const ids = async (q) => (await getDocs(q)).docs.map((d) => d.id);

// Espelha FirebaseAuthRepository._inventory + CommunityRepository.myFootprint.
async function inventory(uid) {
  const reports = await getDocs(query(collection(db, 'reports'), where('reporterUid', '==', uid)));
  const ratingIds = await ids(query(collection(db, 'questionRatings'), where('uid', '==', uid)));
  return {
    posts: await ids(query(collection(db, 'posts'), where('authorUid', '==', uid))),
    replies: await ids(query(collection(db, 'replies'), where('authorUid', '==', uid))),
    votesGiven: await ids(query(collection(db, 'helpfulVotes'), where('voterUid', '==', uid))),
    resolved: reports.docs.filter((d) => d.data().status !== 'open').map((d) => d.id),
    ratingIds,
  };
}

// Espelha accountErasureStages (account_erasure.dart).
function stages(uid, inv) {
  const writes = [
    ...inv.posts.map((i) => `posts/${i}`),
    ...inv.replies.map((i) => `replies/${i}`),
    ...inv.votesGiven.map((i) => `helpfulVotes/${i}`),
    ...inv.ratingIds.map((i) => `questionRatings/${i}`),
    ...inv.resolved.map((i) => `reports/${i}`),
  ];
  const out = [];
  for (let i = 0; i < writes.length; i += 400) out.push(writes.slice(i, i + 400));
  out.push([`conectaLimits/${uid}`, `memberships/${uid}`, `profiles/${uid}`]);
  return out;
}

const commit = (paths) => {
  const batch = writeBatch(db);
  for (const p of paths) batch.delete(doc(db, p));
  return batch.commit();
};

async function deleteUserData(uid) {
  for (const name of USER_COLLECTIONS) {
    for (const d of (await getDocs(collection(db, 'users', uid, name))).docs) await commit([d.ref.path]);
  }
  await commit([`users/${uid}`]);
}

// Tudo do usuário, lido sem regras.
const leftovers = async (uid) => {
  const out = {};
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    const q = async (key, qq) => (out[key] = (await getDocs(qq)).docs.map((d) => d.id));
    await q('posts', query(collection(f, 'posts'), where('authorUid', '==', uid)));
    await q('replies', query(collection(f, 'replies'), where('authorUid', '==', uid)));
    await q('votes', query(collection(f, 'helpfulVotes'), where('voterUid', '==', uid)));
    await q('ratings', query(collection(f, 'questionRatings'), where('uid', '==', uid)));
    await q('reports', query(collection(f, 'reports'), where('reporterUid', '==', uid)));
    for (const p of ['memberships', 'profiles', 'conectaLimits', 'users']) {
      out[p] = (await getDocs(collection(f, p))).docs.map((d) => d.id).filter((i) => i === uid);
    }
    out.userSubdocs = (await getDocs(collectionGroup(f, 'events'))).docs
      .map((d) => d.ref.path)
      .filter((p) => p.startsWith(`users/${uid}/`));
  });
  return out;
};

// A (a conta que sai) e B (outro membro). Entrada, avaliação, voto e denúncia
// passam pelas regras; post/resposta são semeados por causa do intervalo de 30 s.
async function scenario() {
  const { user, email } = await newVerifiedUser();
  const uid = user.uid;
  const b = `b${n}`;
  await seed({
    'appConfig/runtime': { conectaEnabled: true, conectaWritesEnabled: true },
    'invites/turma1': { ok: true },
    [`memberships/${b}`]: { nickname: 'bob_ok', inviteCode: 'turma1', declaredMinAge: 18, rulesVersion: '1', joinedAt: past(900) },
    [`profiles/${b}`]: { nickname: 'bob_ok', joinedAt: past(900) },
    [`posts/pb${n}`]: { communityId: 'matematica', authorUid: b, authorNickname: 'bob_ok', title: 'Dúvida do Bob', body: 'x', status: 'visible', createdAt: past(800) },
    [`replies/rb${n}`]: { postId: `pb${n}`, authorUid: b, authorNickname: 'bob_ok', body: 'resposta do Bob', status: 'visible', createdAt: past(700) },
  });
  // 1. Entra no piloto (lote do app: membership + perfil).
  const join = writeBatch(db);
  join.set(doc(db, 'memberships', uid), {
    nickname: 'ana_ok', inviteCode: 'turma1', declaredMinAge: 18, rulesVersion: '1', joinedAt: serverTimestamp(),
  });
  join.set(doc(db, 'profiles', uid), { nickname: 'ana_ok', joinedAt: serverTimestamp() });
  await join.commit();
  await setDoc(doc(db, 'users', uid), { name: 'Ana', email, termsVersion: '2026-11-09' });
  await setDoc(doc(db, 'users', uid, 'events', 'e1'), { type: 'signed_up', at: serverTimestamp() });
  await setDoc(doc(db, 'users', uid, 'questions', 'q1'), { statement: 'x' });
  // 2. Posta e responde (semeado), recebe voto de B.
  await seed({
    [`posts/pa${n}`]: { communityId: 'matematica', authorUid: uid, authorNickname: 'ana_ok', title: 'Dúvida da Ana', body: 'x', status: 'visible', createdAt: past(300) },
    [`replies/ra${n}`]: { postId: `pb${n}`, authorUid: uid, authorNickname: 'ana_ok', body: 'resposta da Ana', status: 'visible', createdAt: past(200) },
    [`helpfulVotes/ra${n}_${b}`]: { replyId: `ra${n}`, postId: `pb${n}`, authorUid: uid, voterUid: b, createdAt: past(100) },
    [`conectaLimits/${uid}`]: { lastWriteAt: past(200), lastDocPath: `replies/ra${n}` },
    // Denúncia resolvida da Ana (a rotina de moderação não apaga ao resolver).
    [`reports/ra${n}_${uid}`]: { targetType: 'reply', targetId: `ra${n}`, postId: `pb${n}`, reason: 'spam', details: '', reporterUid: uid, status: 'resolved', createdAt: past(150) },
  });
  // 3. Vota na resposta do Bob, avalia e denuncia (pelas regras).
  await setDoc(doc(db, 'helpfulVotes', `rb${n}_${uid}`), {
    replyId: `rb${n}`, postId: `pb${n}`, authorUid: b, voterUid: uid, createdAt: serverTimestamp(),
  });
  await setDoc(doc(db, 'questionRatings', `enem-2022-1_${uid}`), {
    bankId: 'enem-2022-1', uid, area: 'mathematics', subject: 'Matemática', difficulty: 2, quality: 3, updatedAt: serverTimestamp(),
  });
  await setDoc(doc(db, 'reports', `pb${n}_${uid}`), {
    targetType: 'post', targetId: `pb${n}`, postId: `pb${n}`, reason: 'spam', details: '', reporterUid: uid, status: 'open', createdAt: serverTimestamp(),
  });
  return { user, uid, b, email };
}

test('o fixture do Dart tem a mesma forma dos lotes aqui (dados públicos, depois membro/perfil/limite)', () => {
  const mine = stages('ana', {
    posts: ['p1'], replies: ['r1'], votesGiven: ['r9_ana'], ratingIds: ['enem-2022-1_ana'], resolved: ['p8_ana'],
  });
  const dart = FIXTURE.stages.map((s) => s.map((w) => w.path));
  assert.deepEqual(dart, mine);
  assert.ok(FIXTURE.stages.every((s) => s.every((w) => w.kind === 'delete')));
});

test('CA-T7: excluir a conta não deixa nada, só a denúncia aberta; o Auth some por último', async () => {
  const { user, uid, b } = await scenario();
  assert.ok((await inventory(uid)).ratingIds.length === 1, 'o inventário enxerga a avaliação');

  const inv = await inventory(uid);
  for (const s of stages(uid, inv)) await commit(s);
  await deleteUserData(uid);
  // Só agora o usuário do Auth.
  await deleteUser(user);

  const left = await leftovers(uid);
  assert.deepEqual(left.posts, []);
  assert.deepEqual(left.replies, []);
  assert.deepEqual(left.votes, []);
  assert.deepEqual(left.ratings, []);
  assert.deepEqual(left.memberships, []);
  assert.deepEqual(left.profiles, []);
  assert.deepEqual(left.conectaLimits, []);
  assert.deepEqual(left.users, []);
  assert.deepEqual(left.userSubdocs, []);
  // Só a denúncia aberta permanece.
  assert.deepEqual(left.reports, [`pb${n}_${uid}`]);
  // O que é dos outros fica: post e resposta do Bob.
  await env.withSecurityRulesDisabled(async (ctx) => {
    const f = ctx.firestore();
    const posts = (await getDocs(query(collection(f, 'posts'), where('authorUid', '==', b)))).docs;
    assert.equal(posts.length, 1);
  });
});

test('falha no meio: o Auth não é apagado e a nova tentativa termina o serviço', async () => {
  const { user, uid } = await scenario();
  const inv = await inventory(uid);
  const [first] = stages(uid, inv);
  // Simula a queda depois do 1º lote (dados públicos apagados, membro ainda não).
  await commit(first);
  let left = await leftovers(uid);
  assert.deepEqual(left.posts, []);
  assert.deepEqual(left.memberships, [uid], 'membro ainda existe: a exclusão ficou pela metade');
  // O usuário do Auth continua válido (a pessoa ainda consegue entrar de novo).
  await signInWithEmailAndPassword(auth, user.email, 'segura123');

  // Nova tentativa: o inventário é refeito (as avaliações ainda são legíveis porque
  // o membro ainda existe) e a sequência termina sem erro.
  const again = await inventory(uid);
  assert.deepEqual(again.posts, []);
  assert.deepEqual(again.ratingIds, []); // já apagada no 1º lote
  for (const s of stages(uid, again)) await commit(s);
  await deleteUserData(uid);
  await deleteUser(auth.currentUser);

  left = await leftovers(uid);
  for (const k of ['posts', 'replies', 'votes', 'ratings', 'memberships', 'profiles', 'conectaLimits', 'users', 'userSubdocs']) {
    assert.deepEqual(left[k], [], k);
  }
});

test('regras: com o usuário do Auth já apagado, as exclusões seriam negadas (por isso ele é o último)', async () => {
  const { user, uid } = await scenario();
  const inv = await inventory(uid);
  await deleteUser(user);
  await assert.rejects(commit(stages(uid, inv).at(-1)), /permission/i);
});

test('banido: a exclusão também apaga as próprias avaliações e o resto', async () => {
  const { user, uid } = await scenario();
  await seed({ [`bans/${uid}`]: { at: past(10), reason: 'x' } });
  const inv = await inventory(uid);
  assert.equal(inv.ratingIds.length, 1, 'banido ainda enxerga a própria avaliação');
  for (const s of stages(uid, inv)) await commit(s);
  await deleteUserData(uid);
  await deleteUser(user);
  const left = await leftovers(uid);
  for (const k of ['posts', 'replies', 'votes', 'ratings', 'memberships', 'profiles', 'conectaLimits', 'users', 'userSubdocs']) {
    assert.deepEqual(left[k], [], k);
  }
});

test('ex-membro (saiu antes de excluir): as avaliações também são alcançadas', async () => {
  const { user, uid } = await scenario();
  const leave = writeBatch(db);
  leave.delete(doc(db, 'memberships', uid));
  leave.delete(doc(db, 'profiles', uid));
  await leave.commit();
  const inv = await inventory(uid);
  assert.equal(inv.ratingIds.length, 1);
  for (const s of stages(uid, inv)) await commit(s);
  await deleteUserData(uid);
  await deleteUser(user);
  assert.deepEqual((await leftovers(uid)).ratings, []);
});
