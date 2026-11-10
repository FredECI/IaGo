// M1: todos os tipos de evento de métrica (campos novos incluídos) passam pelas
// regras de users/{uid}/events como o app os grava; terceiros não gravam.
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collectionGroup, doc, getDocs, setDoc, Timestamp } from 'firebase/firestore';

import { newEnv, seed } from './helpers.mjs';

let env;
before(async () => (env = await newEnv('demo-iago-metrics-events')));
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const db = (uid) => env.authenticatedContext(uid).firestore();
const at = () => Timestamp.fromMillis(Date.now());

// Um exemplo de cada tipo, com os campos que o app grava (lib/features/**).
const EXAMPLES = {
  signed_up: { referralSource: 'friend', platformsBefore: 3 },
  question_saved: { seconds: 22, questionType: 'objective' },
  list_created: { questionCount: 10 },
  list_exported: {
    questionCount: 10,
    exportIndex: 2,
    assemblySeconds: 540,
    bankQuestionCount: 3,
    hadAcceptedListStep: true,
  },
  satisfaction: { score: 9, platformsNow: 2 },
  satisfaction_dismissed: {},
  questions_bulk_saved: { origin: 'import', count: 5, seconds: 40, discardedCount: 1 },
  import_run: { source: 'text', files: 1, extracted: 5, failedFiles: 0, partial: false },
  direction_plan_created: { source: 'rules' },
  direction_step_done: { onTime: true, source: 'rules', action: 'buildList' },
  direction_step_missed: { source: 'rules', action: 'buildList' },
  ai_fallback: { feature: 'import', reason: 'quota' },
  rating_saved: {},
  community_post: { communityId: 'matematica', postId: 'p1' },
  community_reply: { postId: 'p1', replyId: 'r1' },
  helpful_given: { postId: 'p1', replyId: 'r1' },
  report_filed: { reason: 'spam' },
};

for (const [type, data] of Object.entries(EXAMPLES)) {
  test(`o dono grava evento ${type}`, async () => {
    await assertSucceeds(setDoc(doc(db('pedro'), `users/pedro/events/e-${type}`), { ...data, type, at: at() }));
  });
}

test('o dono grava "active" com id fixo por dia (set repetido = update)', async () => {
  const ref = doc(db('pedro'), 'users/pedro/events/active-2026-11-20');
  await assertSucceeds(setDoc(ref, { type: 'active', at: at() }));
  await assertSucceeds(setDoc(ref, { type: 'active', at: at() }));
});

test('outro usuário e anônimo não gravam eventos alheios', async () => {
  const body = { type: 'community_post', communityId: 'matematica', postId: 'p1', at: at() };
  await assertFails(setDoc(doc(db('ana'), 'users/pedro/events/x'), body));
  await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'users/pedro/events/x'), body));
});

test('admin lê os eventos de todos por collection group; usuário comum não', async () => {
  await seed(env, {
    'admins/fred': { since: 1 },
    'users/pedro/events/e1': { type: 'community_post', postId: 'p1', at: at() },
    'users/ana/events/e1': { type: 'helpful_given', replyId: 'r1', at: at() },
  });
  const snap = await assertSucceeds(getDocs(collectionGroup(db('fred'), 'events')));
  if (snap.size !== 2) throw new Error(`esperava 2 eventos, veio ${snap.size}`);
  await assertFails(getDocs(collectionGroup(db('pedro'), 'events')));
});
