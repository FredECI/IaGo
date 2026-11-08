// Conecta: fórum, respostas, "Ajudou", denúncias, moderação, banimento, intervalo
// e interruptor (CA-C1 a CA-C6, CA-T7, CA-T9).
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

import { baseScenario, newEnv, past, seed, ts } from './helpers.mjs';

let env;
before(async () => (env = await newEnv('demo-iago-conecta')));
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const db = (uid) => env.authenticatedContext(uid, { email_verified: true }).firestore();

const postData = (over = {}) => ({
  communityId: 'matematica',
  authorUid: 'ana',
  authorNickname: 'ana_ok',
  title: 'Dúvida em funções',
  body: 'Como começo?',
  status: 'visible',
  createdAt: ts(),
  ...over,
});
const replyData = (over = {}) => ({
  postId: 'p1',
  authorUid: 'bob',
  authorNickname: 'bob_ok',
  body: 'Comece pelo gráfico.',
  status: 'visible',
  createdAt: ts(),
  ...over,
});

// Escrita do Conecta: o documento e o conectaLimits no mesmo lote.
async function write(uid, path, data) {
  const d = db(uid);
  const batch = writeBatch(d);
  batch.set(doc(d, path), data);
  batch.set(doc(d, `conectaLimits/${uid}`), { lastWriteAt: ts(), lastDocPath: path });
  return batch.commit();
}

const stored = (over = {}) => ({
  communityId: 'matematica',
  authorUid: 'ana',
  authorNickname: 'ana_ok',
  title: 'Dúvida em funções',
  body: 'Como começo?',
  status: 'visible',
  createdAt: past(600),
  ...over,
});
const storedReply = (over = {}) => ({
  postId: 'p1',
  authorUid: 'bob',
  authorNickname: 'bob_ok',
  body: 'Comece pelo gráfico.',
  status: 'visible',
  createdAt: past(500),
  ...over,
});

// ---------- Posts ----------

test('post: membro cria com tudo certo', async () => {
  await seed(env, baseScenario());
  await assertSucceeds(write('ana', 'posts/p1', postData()));
});

test('post: não membro não lê nem cria (CA-C1)', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': stored() });
  await assertFails(getDoc(doc(db('estranho'), 'posts/p1')));
  await assertFails(
    write('estranho', 'posts/p2', postData({ authorUid: 'estranho', authorNickname: 'estranho' })),
  );
  await assertFails(getDocs(query(collection(db('estranho'), 'posts'), where('status', '==', 'visible'))));
});

test('post: autor falso, apelido falso, comunidade, data do cliente, campo extra, status e tamanhos (CA-C2)', async () => {
  await seed(env, baseScenario());
  await assertFails(write('ana', 'posts/a', postData({ authorUid: 'bob' })));
  await assertFails(write('ana', 'posts/b', postData({ authorNickname: 'bob_ok' })));
  await assertFails(write('ana', 'posts/c', postData({ communityId: 'fofoca' })));
  await assertFails(write('ana', 'posts/d', postData({ createdAt: new Date() })));
  await assertFails(write('ana', 'posts/e', postData({ extra: 'x' })));
  await assertFails(write('ana', 'posts/f', postData({ status: 'hidden' })));
  await assertFails(write('ana', 'posts/g', postData({ status: 'pending' })));
  await assertFails(write('ana', 'posts/h', postData({ title: 'abcd' })));
  await assertFails(write('ana', 'posts/i', postData({ title: 'x'.repeat(121) })));
  await assertFails(write('ana', 'posts/j', postData({ body: '' })));
  await assertFails(write('ana', 'posts/k', postData({ body: 'x'.repeat(2001) })));
  // Limites exatos passam.
  await assertSucceeds(write('ana', 'posts/ok1', postData({ title: 'x'.repeat(120), body: 'y'.repeat(2000) })));
});

test('post: todas as comunidades da lista são aceitas e bankId opcional', async () => {
  await seed(env, baseScenario());
  const comunidades = ['linguagens', 'humanas', 'natureza', 'matematica', 'reforco'];
  for (const [i, c] of comunidades.entries()) {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'conectaLimits/ana'));
    });
    await assertSucceeds(
      write('ana', `posts/c${i}`, postData({ communityId: c, ...(i === 0 ? { bankId: 'enem-2022-136' } : {}) })),
    );
  }
});

test('intervalo (CA-C3): dois posts em menos de 30 s, nega; depois de 30 s, aceita', async () => {
  await seed(env, baseScenario());
  await assertSucceeds(write('ana', 'posts/p1', postData()));
  await assertFails(write('ana', 'posts/p2', postData()));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'conectaLimits/ana'), { lastWriteAt: past(10) });
  });
  await assertFails(write('ana', 'posts/p2', postData()));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'conectaLimits/ana'), { lastWriteAt: past(31) });
  });
  await assertSucceeds(write('ana', 'posts/p2', postData()));
});

test('intervalo: post sem atualizar conectaLimits, nega; limite com data do cliente, nega', async () => {
  await seed(env, baseScenario());
  await assertFails(setDoc(doc(db('ana'), 'posts/p1'), postData()));
  const d = db('ana');
  const batch = writeBatch(d);
  batch.set(doc(d, 'posts/p1'), postData());
  batch.set(doc(d, 'conectaLimits/ana'), { lastWriteAt: new Date(), lastDocPath: 'posts/p1' });
  await assertFails(batch.commit());
  const batch2 = writeBatch(d);
  batch2.set(doc(d, 'posts/p1'), postData());
  batch2.set(doc(d, 'conectaLimits/ana'), { lastWriteAt: ts(), lastDocPath: 'posts/p1', extra: 1 });
  await assertFails(batch2.commit());
});

test('intervalo: apagar o limite sendo membro, nega; sem ser membro, passa', async () => {
  await seed(env, {
    ...baseScenario(),
    'conectaLimits/ana': { lastWriteAt: past(5) },
    'conectaLimits/saiu': { lastWriteAt: past(5) },
  });
  await assertFails(deleteDoc(doc(db('ana'), 'conectaLimits/ana')));
  await assertSucceeds(deleteDoc(doc(db('saiu'), 'conectaLimits/saiu')));
  await assertFails(getDoc(doc(db('bob'), 'conectaLimits/ana')));
  await assertSucceeds(getDoc(doc(db('ana'), 'conectaLimits/ana')));
});

test('interruptor (CA-T9): conectaWritesEnabled=false ou ausente ou documento ausente, nega escrita', async () => {
  await seed(env, { ...baseScenario(), 'appConfig/runtime': { conectaWritesEnabled: false } });
  await assertFails(write('ana', 'posts/p1', postData()));
  await seed(env, { 'appConfig/runtime': { conectaEnabled: true } });
  await assertFails(write('ana', 'posts/p1', postData()));
  await seed(env, { 'appConfig/runtime': { conectaWritesEnabled: 'true' } });
  await assertFails(write('ana', 'posts/p1', postData()));
  await seed(env, { 'appConfig/runtime': { conectaWritesEnabled: true } });
  await assertSucceeds(write('ana', 'posts/p1', postData()));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), 'appConfig/runtime'));
    await deleteDoc(doc(ctx.firestore(), 'conectaLimits/ana'));
  });
  await assertFails(write('ana', 'posts/p2', postData()));
});

test('interruptor: com a escrita desligada, resposta, voto e denúncia seguem a regra do interruptor', async () => {
  await seed(env, {
    ...baseScenario(),
    'appConfig/runtime': { conectaWritesEnabled: false },
    'posts/p1': stored(),
    'replies/r1': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok' }),
  });
  await assertFails(write('bob', 'replies/r2', replyData()));
  await assertFails(
    setDoc(doc(db('bob'), 'helpfulVotes/r1_bob'), {
      replyId: 'r1', postId: 'p1', authorUid: 'ana', voterUid: 'bob', createdAt: ts(),
    }),
  );
});

// ---------- Banimento ----------

test('banido não posta, não responde, não vota e não avalia; apaga os próprios dados', async () => {
  await seed(env, {
    ...baseScenario(),
    'bans/bob': { at: 1, reason: 'spam' },
    'posts/p1': stored({ authorUid: 'bob', authorNickname: 'bob_ok' }),
    'posts/p0': stored({ authorUid: 'ana' }),
    'replies/r0': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok', postId: 'p0' }),
    'replies/r1': storedReply({ postId: 'p0' }),
    'replies/r5': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok', postId: 'p0' }),
    'helpfulVotes/r0_bob': { replyId: 'r0', postId: 'p0', authorUid: 'ana', voterUid: 'bob', createdAt: past(5) },
    'questionRatings/enem-2022-1_bob': { bankId: 'enem-2022-1', uid: 'bob', difficulty: 1, quality: 1, updatedAt: past(5) },
  });
  await assertFails(write('bob', 'posts/novo', postData({ authorUid: 'bob', authorNickname: 'bob_ok' })));
  await assertFails(write('bob', 'replies/novo', replyData({ postId: 'p0' })));
  await assertFails(
    setDoc(doc(db('bob'), 'helpfulVotes/r5_bob'), {
      replyId: 'r5', postId: 'p0', authorUid: 'ana', voterUid: 'bob', createdAt: ts(),
    }),
  );
  await assertFails(
    setDoc(doc(db('bob'), 'questionRatings/enem-2022-9_bob'), {
      bankId: 'enem-2022-9', uid: 'bob', area: 'mathematics', subject: 'Matemática', difficulty: 2, quality: 2, updatedAt: ts(),
    }),
  );
  // Ainda apaga os próprios dados.
  await assertSucceeds(deleteDoc(doc(db('bob'), 'posts/p1')));
  await assertSucceeds(deleteDoc(doc(db('bob'), 'replies/r1')));
  await assertSucceeds(deleteDoc(doc(db('bob'), 'helpfulVotes/r0_bob')));
  await assertSucceeds(deleteDoc(doc(db('bob'), 'questionRatings/enem-2022-1_bob')));
  // Banir também tira a leitura do fórum.
  await assertFails(getDoc(doc(db('bob'), 'posts/p0')));
});

// ---------- Visibilidade ----------

test('visibilidade (CA-C4): pending e hidden só para autor e moderador; consulta por status', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/vis': stored({ authorUid: 'ana' }),
    'posts/pen': stored({ authorUid: 'ana', status: 'pending' }),
    'posts/hid': stored({ authorUid: 'ana', status: 'hidden', moderationReason: 'spam' }),
  });
  const bob = db('bob');
  await assertSucceeds(getDoc(doc(bob, 'posts/vis')));
  await assertFails(getDoc(doc(bob, 'posts/pen')));
  await assertFails(getDoc(doc(bob, 'posts/hid')));
  await assertSucceeds(getDoc(doc(db('ana'), 'posts/pen')));
  await assertSucceeds(getDoc(doc(db('ana'), 'posts/hid')));
  await assertSucceeds(getDoc(doc(db('mod'), 'posts/pen')));
  await assertSucceeds(getDoc(doc(db('mod'), 'posts/hid')));
  // Consulta filtrada por status visible passa; sem filtro para um membro comum, não.
  await assertSucceeds(getDocs(query(collection(bob, 'posts'), where('status', '==', 'visible'))));
  await assertFails(getDocs(collection(bob, 'posts')));
  // O autor consulta os próprios, em qualquer status.
  await assertSucceeds(getDocs(query(collection(db('ana'), 'posts'), where('authorUid', '==', 'ana'))));
});

// ---------- Respostas ----------

test('resposta: membro responde post visível; post oculto ou inexistente, nega', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored(),
    'posts/ph': stored({ status: 'hidden' }),
  });
  await assertSucceeds(write('bob', 'replies/r1', replyData()));
  await env.withSecurityRulesDisabled(async (ctx) => deleteDoc(doc(ctx.firestore(), 'conectaLimits/bob')));
  await assertFails(write('bob', 'replies/r2', replyData({ postId: 'ph' })));
  await assertFails(write('bob', 'replies/r3', replyData({ postId: 'nao-existe' })));
});

test('resposta: autor falso, apelido falso, data do cliente, campo extra, tamanho e não membro, nega', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': stored() });
  await assertFails(write('bob', 'replies/a', replyData({ authorUid: 'ana' })));
  await assertFails(write('bob', 'replies/b', replyData({ authorNickname: 'ana_ok' })));
  await assertFails(write('bob', 'replies/c', replyData({ createdAt: new Date() })));
  await assertFails(write('bob', 'replies/d', replyData({ extra: 1 })));
  await assertFails(write('bob', 'replies/e', replyData({ body: '' })));
  await assertFails(write('bob', 'replies/f', replyData({ body: 'x'.repeat(2001) })));
  await assertFails(write('bob', 'replies/g', replyData({ status: 'hidden' })));
  await assertFails(write('estranho', 'replies/h', replyData({ authorUid: 'estranho', authorNickname: 'estranho' })));
});

test('resposta: dois envios em menos de 30 s, nega', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': stored() });
  await assertSucceeds(write('bob', 'replies/r1', replyData()));
  await assertFails(write('bob', 'replies/r2', replyData()));
});

test('resposta: visibilidade igual à do post', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored(),
    'replies/vis': storedReply(),
    'replies/pen': storedReply({ status: 'pending' }),
  });
  await assertSucceeds(getDoc(doc(db('ana'), 'replies/vis')));
  await assertFails(getDoc(doc(db('ana'), 'replies/pen')));
  await assertSucceeds(getDoc(doc(db('bob'), 'replies/pen')));
  await assertSucceeds(getDoc(doc(db('mod'), 'replies/pen')));
  await assertFails(getDoc(doc(db('estranho'), 'replies/vis')));
});

// ---------- Denúncia ----------

const reportData = (over = {}) => ({
  targetType: 'post',
  targetId: 'p1',
  postId: 'p1',
  reason: 'spam',
  details: 'propaganda',
  reporterUid: 'bob',
  status: 'open',
  createdAt: ts(),
  ...over,
});

async function report(uid, targetPath, reportPath, data, newStatus = 'pending') {
  const d = db(uid);
  const batch = writeBatch(d);
  batch.set(doc(d, reportPath), data);
  batch.update(doc(d, targetPath), { status: newStatus });
  return batch.commit();
}

test('denúncia (CA-C4): com relatório no mesmo lote, o post vira pending e some para os outros', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': stored() });
  await assertSucceeds(report('bob', 'posts/p1', 'reports/p1_bob', reportData()));
  const carol = env.authenticatedContext('carol', { email_verified: true }).firestore();
  await assertFails(getDoc(doc(carol, 'posts/p1')));
  await assertSucceeds(getDoc(doc(db('ana'), 'posts/p1')));
  await assertSucceeds(getDoc(doc(db('mod'), 'posts/p1')));
});

test('denúncia: sem relatório no lote, nega; mudar outro campo, nega; hidden direto, nega', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': stored() });
  await assertFails(updateDoc(doc(db('bob'), 'posts/p1'), { status: 'pending' }));
  await assertFails(updateDoc(doc(db('bob'), 'posts/p1'), { status: 'hidden' }));
  await assertFails(updateDoc(doc(db('bob'), 'posts/p1'), { title: 'Troquei o título' }));
  const d = db('bob');
  const batch = writeBatch(d);
  batch.set(doc(d, 'reports/p1_bob'), reportData());
  batch.update(doc(d, 'posts/p1'), { status: 'pending', title: 'Troquei o título' });
  await assertFails(batch.commit());
  // Relatório de outro alvo não serve.
  const batch2 = writeBatch(d);
  batch2.set(doc(d, 'reports/p9_bob'), reportData({ targetId: 'p9' }));
  batch2.update(doc(d, 'posts/p1'), { status: 'pending' });
  await assertFails(batch2.commit());
});

test('denúncia: resposta também vira pending com relatório', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored(),
    'replies/r1': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok' }),
  });
  await assertSucceeds(
    report('bob', 'replies/r1', 'reports/r1_bob', reportData({ targetType: 'reply', targetId: 'r1' })),
  );
});

test('denúncia: duas vezes a mesma pessoa, nega; campos inválidos, nega', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored(),
    'reports/p1_bob': { ...reportData(), createdAt: past(5) },
  });
  await assertFails(setDoc(doc(db('bob'), 'reports/p1_bob'), reportData()));
  await assertFails(setDoc(doc(db('ana'), 'reports/p1_bob'), reportData({ reporterUid: 'ana' })));
  await assertFails(setDoc(doc(db('ana'), 'reports/p1_ana'), reportData({ reporterUid: 'bob' })));
  await assertFails(setDoc(doc(db('ana'), 'reports/p1_ana'), reportData({ reporterUid: 'ana', reason: 'chato' })));
  await assertFails(setDoc(doc(db('ana'), 'reports/p1_ana'), reportData({ reporterUid: 'ana', details: 'x'.repeat(501) })));
  await assertFails(setDoc(doc(db('ana'), 'reports/p1_ana'), reportData({ reporterUid: 'ana', status: 'resolved' })));
  await assertFails(setDoc(doc(db('ana'), 'reports/p1_ana'), reportData({ reporterUid: 'ana', targetType: 'user' })));
  await assertSucceeds(setDoc(doc(db('ana'), 'reports/p1_ana'), reportData({ reporterUid: 'ana' })));
});

test('denúncia: o membro lê só o próprio relatório; o moderador lê todos', async () => {
  await seed(env, {
    ...baseScenario(),
    'reports/p1_bob': { ...reportData(), createdAt: past(5) },
    'reports/p1_ana': { ...reportData({ reporterUid: 'ana' }), createdAt: past(5) },
  });
  await assertSucceeds(getDoc(doc(db('bob'), 'reports/p1_bob')));
  await assertFails(getDoc(doc(db('bob'), 'reports/p1_ana')));
  await assertSucceeds(getDoc(doc(db('mod'), 'reports/p1_bob')));
  await assertSucceeds(
    getDocs(query(collection(db('mod'), 'reports'), where('status', '==', 'open'))),
  );
  await assertFails(getDocs(query(collection(db('bob'), 'reports'), where('status', '==', 'open'))));
  await assertSucceeds(
    getDocs(query(collection(db('bob'), 'reports'), where('reporterUid', '==', 'bob'))),
  );
});

// ---------- Moderação ----------

test('moderação (CA-C5): o moderador restaura e oculta com motivo; membro comum não', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': stored({ status: 'pending' }) });
  await assertSucceeds(
    updateDoc(doc(db('mod'), 'posts/p1'), { status: 'hidden', moderationReason: 'spam', moderatedAt: ts() }),
  );
  await assertSucceeds(updateDoc(doc(db('mod'), 'posts/p1'), { status: 'visible', moderatedAt: ts() }));
  await assertFails(updateDoc(doc(db('mod'), 'posts/p1'), { status: 'pending' }));
  await assertFails(updateDoc(doc(db('mod'), 'posts/p1'), { status: 'visible', title: 'Reescrito' }));
  await assertFails(updateDoc(doc(db('ana'), 'posts/p1'), { status: 'visible' }));
  await assertFails(updateDoc(doc(db('bob'), 'posts/p1'), { status: 'hidden', moderationReason: 'x', moderatedAt: ts() }));
});

test('moderação: o autor vê o motivo; o moderador oculta resposta e resolve relatório', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored({ status: 'hidden', moderationReason: 'spam' }),
    'replies/r1': storedReply(),
    'reports/r1_ana': { ...reportData({ targetType: 'reply', targetId: 'r1', reporterUid: 'ana' }), createdAt: past(5) },
  });
  const p = await assertSucceeds(getDoc(doc(db('ana'), 'posts/p1')));
  if (p.data().moderationReason !== 'spam') throw new Error('motivo ausente');
  await assertSucceeds(
    updateDoc(doc(db('mod'), 'replies/r1'), { status: 'hidden', moderationReason: 'ofensa', moderatedAt: ts() }),
  );
  await assertFails(updateDoc(doc(db('bob'), 'replies/r1'), { status: 'hidden' }));
  await assertSucceeds(
    updateDoc(doc(db('mod'), 'reports/r1_ana'), { status: 'resolved', decision: 'hidden', resolvedBy: 'mod', resolvedAt: ts() }),
  );
  await assertFails(updateDoc(doc(db('bob'), 'reports/r1_ana'), { status: 'resolved' }));
});

test('moderação: só o moderador cria bans; moderador apaga post de outro, membro comum não', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': stored() });
  await assertFails(setDoc(doc(db('ana'), 'bans/bob'), { at: ts(), reason: 'x' }));
  await assertSucceeds(setDoc(doc(db('mod'), 'bans/bob'), { at: ts(), reason: 'spam' }));
  await assertFails(deleteDoc(doc(db('bob'), 'posts/p1')));
  await assertSucceeds(deleteDoc(doc(db('mod'), 'posts/p1')));
});

// ---------- Ajudou ----------

const voteData = (over = {}) => ({
  replyId: 'r1',
  postId: 'p1',
  authorUid: 'bob',
  voterUid: 'ana',
  createdAt: ts(),
  ...over,
});

async function seedVotes() {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored(),
    'replies/r1': storedReply(), // autor: bob
  });
}

test('ajudou (CA-C6): voto válido passa; duas vezes, nega', async () => {
  await seedVotes();
  await assertSucceeds(setDoc(doc(db('ana'), 'helpfulVotes/r1_ana'), voteData()));
  await assertFails(setDoc(doc(db('ana'), 'helpfulVotes/r1_ana'), voteData()));
});

test('ajudou: na própria resposta, autor falso, id errado, voterUid falso e campo extra, nega', async () => {
  await seedVotes();
  await assertFails(
    setDoc(doc(db('bob'), 'helpfulVotes/r1_bob'), voteData({ voterUid: 'bob' })),
  );
  await assertFails(setDoc(doc(db('ana'), 'helpfulVotes/r1_ana'), voteData({ authorUid: 'mod' })));
  await assertFails(setDoc(doc(db('ana'), 'helpfulVotes/r1_mod'), voteData()));
  await assertFails(setDoc(doc(db('ana'), 'helpfulVotes/qualquer'), voteData()));
  await assertFails(setDoc(doc(db('ana'), 'helpfulVotes/r1_ana'), voteData({ voterUid: 'bob' })));
  await assertFails(setDoc(doc(db('ana'), 'helpfulVotes/r1_ana'), voteData({ extra: 1 })));
  await assertFails(setDoc(doc(db('ana'), 'helpfulVotes/r1_ana'), voteData({ createdAt: new Date() })));
  await assertFails(setDoc(doc(db('estranho'), 'helpfulVotes/r1_estranho'), voteData({ voterUid: 'estranho' })));
});

test('ajudou: leitura e exclusão pelo votante e pelo autor da resposta', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored(),
    'replies/r1': storedReply(),
    'helpfulVotes/r1_ana': { ...voteData(), createdAt: past(5) },
  });
  await assertSucceeds(getDoc(doc(db('bob'), 'helpfulVotes/r1_ana')));
  await assertSucceeds(getDoc(doc(db('mod'), 'helpfulVotes/r1_ana')));
  await assertFails(getDoc(doc(db('estranho'), 'helpfulVotes/r1_ana')));
  await assertFails(deleteDoc(doc(db('mod'), 'helpfulVotes/r1_ana')));
  await assertSucceeds(deleteDoc(doc(db('ana'), 'helpfulVotes/r1_ana')));
});

// ---------- Exclusão de conta (CA-T7) ----------

test('exclusão: o autor apaga posts, respostas, votos dados e recebidos, denúncias resolvidas, limite, membership e perfil', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored({ status: 'hidden' }),
    'replies/r1': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok' }),
    'replies/r2': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok', status: 'pending' }),
    'helpfulVotes/r1_bob': { replyId: 'r1', postId: 'p1', authorUid: 'ana', voterUid: 'bob', createdAt: past(5) },
    'helpfulVotes/r9_ana': { replyId: 'r9', postId: 'p1', authorUid: 'bob', voterUid: 'ana', createdAt: past(5) },
    'reports/p1_ana': { ...reportData({ reporterUid: 'ana' }), status: 'resolved', createdAt: past(5) },
    'conectaLimits/ana': { lastWriteAt: past(100) },
  });
  const ana = db('ana');
  await assertSucceeds(deleteDoc(doc(ana, 'posts/p1')));
  await assertSucceeds(deleteDoc(doc(ana, 'replies/r1')));
  await assertSucceeds(deleteDoc(doc(ana, 'replies/r2')));
  await assertSucceeds(deleteDoc(doc(ana, 'helpfulVotes/r1_bob')));
  await assertSucceeds(deleteDoc(doc(ana, 'helpfulVotes/r9_ana')));
  await assertSucceeds(deleteDoc(doc(ana, 'reports/p1_ana')));
  // O limite só sai junto com a membership (mesmo lote).
  await assertFails(deleteDoc(doc(ana, 'conectaLimits/ana')));
  const batch = writeBatch(ana);
  batch.delete(doc(ana, 'conectaLimits/ana'));
  batch.delete(doc(ana, 'memberships/ana'));
  batch.delete(doc(ana, 'profiles/ana'));
  await assertSucceeds(batch.commit());
  // Depois de sair, não lê o fórum nem escreve nele.
  await assertFails(getDoc(doc(ana, 'posts/p0')));
});

test('exclusão: ninguém apaga o que é dos outros (membro comum)', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored(),
    'replies/r1': storedReply(),
    'reports/p1_ana': { ...reportData({ reporterUid: 'ana' }), createdAt: past(5) },
  });
  await assertFails(deleteDoc(doc(db('bob'), 'posts/p1')));
  await assertFails(deleteDoc(doc(db('ana'), 'replies/r1')));
  await assertFails(deleteDoc(doc(db('bob'), 'reports/p1_ana')));
});

// ---------- Limite de chamadas get/exists ----------

test('limite de get/exists: a criação de post e resposta cabe no orçamento das regras', async () => {
  // post: memberships, bans, runtime, conectaLimits (get) e memberships de novo (apelido).
  // resposta: soma o get do post. Se estourasse 10, o Firestore negaria estes casos.
  await seed(env, { ...baseScenario(), 'posts/p1': stored(), 'conectaLimits/ana': { lastWriteAt: past(60) } });
  await assertSucceeds(write('ana', 'posts/p2', postData()));
  await assertSucceeds(write('bob', 'replies/r1', replyData()));
});

test('intervalo: o limite do lote precisa apontar para o documento criado (lastDocPath)', async () => {
  await seed(env, baseScenario());
  const ana = db('ana');
  const tenta = (docPath, lastDocPath) => {
    const batch = writeBatch(ana);
    batch.set(doc(ana, docPath), postData());
    batch.set(doc(ana, 'conectaLimits/ana'), lastDocPath === undefined
      ? { lastWriteAt: ts() }
      : { lastWriteAt: ts(), lastDocPath });
    return batch.commit();
  };
  await assertFails(tenta('posts/p1', undefined));
  await assertFails(tenta('posts/p1', 'posts/outro'));
  await assertFails(tenta('posts/p1', 'replies/p1'));
  await assertSucceeds(tenta('posts/p1', 'posts/p1'));
});

test('regressão: lote com uma resposta e um post juntos não passa pelo mesmo limite', async () => {
  await seed(env, { ...baseScenario(), 'posts/p0': stored() });
  const bob = db('bob');
  const batch = writeBatch(bob);
  batch.set(doc(bob, 'replies/r1'), replyData({ postId: 'p0' }));
  batch.set(doc(bob, 'posts/x1'), postData({ authorUid: 'bob', authorNickname: 'bob_ok' }));
  batch.set(doc(bob, 'conectaLimits/bob'), { lastWriteAt: ts(), lastDocPath: 'replies/r1' });
  await assertFails(batch.commit());
});

test('denúncia: o denunciante não apaga denúncia aberta (o caso não some da fila); resolvida, sim; moderador sempre', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored({ status: 'pending' }),
    'reports/p1_bob': { ...reportData(), createdAt: past(5) },
    'reports/p1_ana': { ...reportData({ reporterUid: 'ana' }), status: 'resolved', createdAt: past(5) },
  });
  await assertFails(deleteDoc(doc(db('bob'), 'reports/p1_bob')));
  await assertSucceeds(deleteDoc(doc(db('ana'), 'reports/p1_ana')));
  await assertSucceeds(deleteDoc(doc(db('mod'), 'reports/p1_bob')));
});

test('denúncia: alvo inexistente, postId incoerente e targetType trocado, nega', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': stored(),
    'posts/p2': stored(),
    'replies/r1': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok' }), // do post p1
  });
  const bob = db('bob');
  const tenta = (id, data) => {
    const batch = writeBatch(bob);
    batch.set(doc(bob, `reports/${id}_bob`), data);
    return batch.commit();
  };
  // Alvo inexistente (post e resposta).
  await assertFails(tenta('nao', reportData({ targetId: 'nao', postId: 'nao' })));
  await assertFails(tenta('nao', reportData({ targetType: 'reply', targetId: 'nao', postId: 'p1' })));
  // postId que não bate com o alvo.
  await assertFails(tenta('p1', reportData({ postId: 'p2' })));
  await assertFails(tenta('r1', reportData({ targetType: 'reply', targetId: 'r1', postId: 'p2' })));
  // targetType trocado: id de resposta como post e id de post como resposta.
  await assertFails(tenta('r1', reportData({ targetType: 'post', targetId: 'r1', postId: 'r1' })));
  await assertFails(tenta('p1', reportData({ targetType: 'reply', targetId: 'p1', postId: 'p1' })));
  // Coerente: passa.
  await assertSucceeds(tenta('p1', reportData()));
  await assertSucceeds(tenta('r1', reportData({ targetType: 'reply', targetId: 'r1', postId: 'p1' })));
});

test('moderador sem membership lê posts e respostas em qualquer status; sem ser moderador nem membro, não', async () => {
  await seed(env, {
    ...baseScenario(),
    'moderators/solo': { ok: true },
    'posts/pen': stored({ status: 'pending' }),
    'posts/hid': stored({ status: 'hidden' }),
    'replies/rpen': storedReply({ status: 'pending' }),
  });
  const solo = db('solo');
  await assertSucceeds(getDoc(doc(solo, 'posts/pen')));
  await assertSucceeds(getDoc(doc(solo, 'posts/hid')));
  await assertSucceeds(getDoc(doc(solo, 'replies/rpen')));
  await assertFails(getDoc(doc(db('estranho'), 'posts/pen')));
});
