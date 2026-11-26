// Conecta: executa, campo a campo, os MESMOS lotes que o app monta
// (lib/data/firebase/community_write_plans.dart). O fixture
// fixtures/community_plans.json é gerado pelo teste Dart
// test/data/community_rules_fixture_test.dart, que falha se ele ficar
// desatualizado. Cobre CA-C1 a CA-C6 e CA-T7 (parte da C1) contra as regras reais.
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  deleteField,
  doc,
  getCountFromServer,
  getDoc,
  getDocs,
  orderBy,
  query,
  where,
  writeBatch,
} from 'firebase/firestore';

import { baseScenario, newEnv, past, seed, ts } from './helpers.mjs';

const PLANS = JSON.parse(readFileSync('firestore-tests/fixtures/community_plans.json', 'utf8'));

let env;
before(async () => (env = await newEnv('demo-iago-plans')));
after(async () => env.cleanup());
beforeEach(async () => env.clearFirestore());

const db = (uid, verified = true) =>
  env.authenticatedContext(uid, { email_verified: verified }).firestore();

const plan = (name) => structuredClone(PLANS[name]);

const decode = (v) => {
  if (v && typeof v === 'object' && '$' in v) return v.$ === 'delete' ? deleteField() : ts();
  return v;
};

// Executa o plano como um único lote, como o repositório faz.
function run(uid, writes, { verified = true } = {}) {
  const d = db(uid, verified);
  const batch = writeBatch(d);
  for (const w of writes) {
    const ref = doc(d, w.path);
    const data = w.data && Object.fromEntries(Object.entries(w.data).map(([k, v]) => [k, decode(v)]));
    if (w.kind === 'set') batch.set(ref, data);
    else if (w.kind === 'update') batch.update(ref, data);
    else batch.delete(ref);
  }
  return batch.commit();
}

const find = (writes, path) => writes.find((w) => w.path === path);
const without = (writes, path) => writes.filter((w) => w.path !== path);
const mutated = (name, fn) => {
  const p = plan(name);
  fn(p);
  return p;
};

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
const storedReport = (over = {}) => ({
  targetType: 'post',
  targetId: 'p1',
  postId: 'p1',
  reason: 'spam',
  details: '',
  reporterUid: 'bob',
  status: 'open',
  createdAt: past(5),
  ...over,
});

const base = (extra = {}) => ({ ...baseScenario(), ...extra });

// ---------- Entrar, renomear, sair (CA-C1) ----------

test('entrar: o lote do app (membership + perfil) passa; membership privada, perfil legível', async () => {
  await seed(env, base());
  await assertSucceeds(run('novo', plan('join')));
  await assertSucceeds(getDoc(doc(db('ana'), 'profiles/novo')));
  await assertFails(getDoc(doc(db('ana'), 'memberships/novo')));
  await assertSucceeds(getDoc(doc(db('novo'), 'memberships/novo')));
});

test('entrar sem convite: nega com inviteRequired; passa com inviteRequired=false', async () => {
  await seed(env, base());
  await assertFails(run('novo', plan('joinNoInvite')));
  await seed(env, {
    'appConfig/runtime': { conectaEnabled: true, conectaWritesEnabled: true, inviteRequired: false },
  });
  await assertSucceeds(run('novo', plan('joinNoInvite')));
});

test('entrar: e-mail não verificado, convite falso, idade, campo extra, apelido e lote incompleto, nega', async () => {
  await seed(env, base());
  const m = (p) => find(p, 'memberships/novo').data;
  const pr = (p) => find(p, 'profiles/novo').data;
  await assertFails(run('novo', plan('join'), { verified: false }));
  await assertFails(run('novo', mutated('join', (p) => (m(p).inviteCode = 'inexistente'))));
  await assertFails(run('novo', mutated('join', (p) => (m(p).declaredMinAge = 17))));
  await assertFails(run('novo', mutated('join', (p) => (m(p).declaredMinAge = '18'))));
  await assertFails(run('novo', mutated('join', (p) => (m(p).extra = 1))));
  await assertFails(run('novo', mutated('join', (p) => (m(p).joinedAt = '2020-01-01'))));
  await assertFails(run('novo', mutated('join', (p) => (m(p).nickname = pr(p).nickname = 'ab'))));
  await assertFails(run('novo', mutated('join', (p) => (m(p).nickname = pr(p).nickname = 'x'.repeat(25)))));
  await assertFails(run('novo', mutated('join', (p) => (pr(p).nickname = 'outro_apelido'))));
  await assertFails(run('novo', mutated('join', (p) => (pr(p).extra = 1))));
  await assertFails(run('novo', without(plan('join'), 'profiles/novo')));
  // Gravar a membership de outra pessoa.
  await assertFails(run('estranho', plan('join')));
  // Limites exatos do apelido passam.
  await assertSucceeds(run('novo', mutated('join', (p) => (m(p).nickname = pr(p).nickname = 'abc'))));
});

test('entrar: minAge maior no runtime nega a declaração de 18', async () => {
  await seed(env, base({ 'appConfig/runtime': { conectaWritesEnabled: true, minAge: 21 } }));
  await assertFails(run('novo', plan('join')));
});

test('renomear: o lote do app passa; um documento só, apelido divergente ou outro campo, nega', async () => {
  await seed(env, base());
  await assertFails(run('ana', without(plan('rename'), 'profiles/ana')));
  await assertFails(run('ana', without(plan('rename'), 'memberships/ana')));
  await assertFails(run('ana', mutated('rename', (p) => (find(p, 'profiles/ana').data.nickname = 'ana_outra'))));
  await assertFails(run('ana', mutated('rename', (p) => (find(p, 'memberships/ana').data.declaredMinAge = 99))));
  await assertFails(run('bob', plan('rename'))); // documentos de outra pessoa
  await assertSucceeds(run('ana', plan('rename')));
  // O post seguinte usa o apelido novo (as regras comparam com o perfil).
  await assertSucceeds(
    run('ana', mutated('post', (p) => (find(p, 'posts/pNovo').data.authorNickname = 'ana_nova'))),
  );
});

test('sair: o lote do app passa; só a membership ou documentos alheios, nega; depois não lê o fórum', async () => {
  await seed(env, base({ 'posts/p1': stored({ authorUid: 'bob', authorNickname: 'bob_ok' }) }));
  await assertFails(run('ana', without(plan('leave'), 'profiles/ana')));
  await assertFails(run('bob', plan('leave'))); // 'bob' apagando memberships/ana
  await assertSucceeds(getDoc(doc(db('ana'), 'posts/p1')));
  await assertSucceeds(run('ana', plan('leave')));
  await assertFails(getDoc(doc(db('ana'), 'posts/p1')));
  await assertFails(getDoc(doc(db('ana'), 'profiles/bob')));
});

// ---------- Postar (CA-C2, CA-C3) ----------

test('post: os lotes do app (sem e com bankId) passam', async () => {
  await seed(env, base());
  await assertSucceeds(run('ana', plan('post')));
  await env.withSecurityRulesDisabled(async (ctx) => {
    await deleteDoc(doc(ctx.firestore(), 'conectaLimits/ana'));
    await deleteDoc(doc(ctx.firestore(), 'posts/pNovo'));
  });
  await assertSucceeds(run('ana', plan('postBank')));
  const d = await getDoc(doc(db('bob'), 'posts/pNovo'));
  if (d.data().bankId !== 'enem-2022-136') throw new Error('bankId perdido');
});

test('post: variações proibidas do lote (CA-C2 e CA-C3)', async () => {
  await seed(env, base());
  const post = (p) => find(p, 'posts/pNovo').data;
  const lim = (p) => find(p, 'conectaLimits/ana').data;
  await assertFails(run('ana', mutated('post', (p) => (post(p).authorUid = 'bob'))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).authorNickname = 'bob_ok'))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).createdAt = '2020-01-01'))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).extra = 1))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).status = 'hidden'))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).communityId = 'fofoca'))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).title = 'abcd'))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).body = ''))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).body = 'x'.repeat(2001)))));
  await assertFails(run('ana', mutated('post', (p) => (post(p).bankId = 'ENEM 2022'))));
  await assertFails(run('ana', without(plan('post'), 'conectaLimits/ana')));
  await assertFails(run('ana', mutated('post', (p) => (lim(p).lastDocPath = 'posts/outro'))));
  await assertFails(run('estranho', plan('post'))); // não membro (limite e post em nome de ana)
});

test('post: não membro, banido e interruptor desligado, nega o lote do app', async () => {
  await seed(env, base({ 'bans/ana': { at: past(5), reason: 'spam' } }));
  await assertFails(run('ana', plan('post')));
  await env.withSecurityRulesDisabled(async (ctx) => deleteDoc(doc(ctx.firestore(), 'bans/ana')));
  await seed(env, { 'appConfig/runtime': { conectaEnabled: true, conectaWritesEnabled: false } });
  await assertFails(run('ana', plan('post')));
  await seed(env, { 'appConfig/runtime': { conectaEnabled: true, conectaWritesEnabled: true } });
  await assertSucceeds(run('ana', plan('post')));
});

test('post: dois lotes do app em menos de 30 s, o segundo nega (CA-C3)', async () => {
  await seed(env, base());
  await assertSucceeds(run('ana', plan('post')));
  await assertFails(
    run(
      'ana',
      mutated('post', (p) => {
        find(p, 'posts/pNovo').path = 'posts/outro';
        find(p, 'conectaLimits/ana').data.lastDocPath = 'posts/outro';
      }),
    ),
  );
});

// ---------- Responder ----------

test('resposta: o lote do app passa em post visível; em post oculto ou inexistente, nega', async () => {
  await seed(env, base({ 'posts/p1': stored(), 'posts/ph': stored({ status: 'hidden' }) }));
  await assertSucceeds(run('bob', plan('reply')));
  await env.withSecurityRulesDisabled(async (ctx) => deleteDoc(doc(ctx.firestore(), 'conectaLimits/bob')));
  const oculto = mutated('reply', (p) => {
    find(p, 'replies/rNovo').data.postId = 'ph';
    find(p, 'replies/rNovo').path = 'replies/r2';
    find(p, 'conectaLimits/bob').data.lastDocPath = 'replies/r2';
  });
  await assertFails(run('bob', oculto));
  const inexistente = mutated('reply', (p) => {
    find(p, 'replies/rNovo').data.postId = 'nao-existe';
    find(p, 'replies/rNovo').path = 'replies/r3';
    find(p, 'conectaLimits/bob').data.lastDocPath = 'replies/r3';
  });
  await assertFails(run('bob', inexistente));
});

test('resposta: autor, apelido, data, campo extra, status, tamanho e lote sem limite, nega', async () => {
  await seed(env, base({ 'posts/p1': stored() }));
  const r = (p) => find(p, 'replies/rNovo').data;
  await assertFails(run('bob', mutated('reply', (p) => (r(p).authorUid = 'ana'))));
  await assertFails(run('bob', mutated('reply', (p) => (r(p).authorNickname = 'ana_ok'))));
  await assertFails(run('bob', mutated('reply', (p) => (r(p).createdAt = '2020-01-01'))));
  await assertFails(run('bob', mutated('reply', (p) => (r(p).extra = 1))));
  await assertFails(run('bob', mutated('reply', (p) => (r(p).status = 'hidden'))));
  await assertFails(run('bob', mutated('reply', (p) => (r(p).body = ''))));
  await assertFails(run('bob', mutated('reply', (p) => (r(p).body = 'x'.repeat(2001)))));
  await assertFails(run('bob', without(plan('reply'), 'conectaLimits/bob')));
  await assertFails(run('estranho', plan('reply')));
  await assertSucceeds(run('bob', mutated('reply', (p) => (r(p).body = 'x'.repeat(2000)))));
  // Intervalo (CA-C3) também vale para a resposta.
  await assertFails(
    run(
      'bob',
      mutated('reply', (p) => {
        find(p, 'replies/rNovo').path = 'replies/r2';
        find(p, 'conectaLimits/bob').data.lastDocPath = 'replies/r2';
      }),
    ),
  );
});

// ---------- Ajudou (CA-C6) ----------

async function seedHelpful(extra = {}) {
  await seed(env, base({ 'posts/p1': stored(), 'replies/r1': storedReply(), ...extra }));
}

test('ajudou: o lote do app passa uma vez; repetir, nega; "desmarcar" passa e permite marcar de novo', async () => {
  await seedHelpful();
  await assertSucceeds(run('ana', plan('helpful')));
  await assertFails(run('ana', plan('helpful')));
  await assertSucceeds(run('ana', plan('unhelpful')));
  await assertSucceeds(run('ana', plan('helpful')));
});

test('ajudou: na própria resposta, autor falso, voter falso, id errado, campo extra, data e não membro, nega', async () => {
  await seedHelpful();
  const v = (p) => find(p, 'helpfulVotes/r1_ana').data;
  // bob votando na própria resposta (r1 é dele), com o documento como o app o monta.
  await assertFails(
    run('bob', [
      {
        kind: 'set',
        path: 'helpfulVotes/r1_bob',
        data: { ...find(plan('helpful'), 'helpfulVotes/r1_ana').data, voterUid: 'bob' },
      },
    ]),
  );
  await assertFails(run('ana', mutated('helpful', (p) => (v(p).authorUid = 'mod'))));
  await assertFails(run('ana', mutated('helpful', (p) => (v(p).voterUid = 'bob'))));
  await assertFails(run('ana', mutated('helpful', (p) => (v(p).extra = 1))));
  await assertFails(run('ana', mutated('helpful', (p) => (v(p).createdAt = '2020-01-01'))));
  await assertFails(run('ana', mutated('helpful', (p) => (find(p, 'helpfulVotes/r1_ana').path = 'helpfulVotes/r1_mod'))));
  await assertFails(run('estranho', mutated('helpful', (p) => {
    v(p).voterUid = 'estranho';
    find(p, 'helpfulVotes/r1_ana').path = 'helpfulVotes/r1_estranho';
  })));
});

test('ajudou: "desmarcar" só vale para o votante; outro membro não apaga o voto', async () => {
  await seedHelpful({
    'helpfulVotes/r1_ana': { replyId: 'r1', postId: 'p1', authorUid: 'bob', voterUid: 'ana', createdAt: past(5) },
  });
  await assertFails(run('mod', plan('unhelpful')));
  await assertSucceeds(run('ana', plan('unhelpful')));
});

// ---------- Denunciar (CA-C4) ----------

test('denúncia de post: o lote do app passa, o post some para outros e segue visível ao autor e ao moderador', async () => {
  await seed(env, base({
    'posts/p1': stored(),
    'memberships/carol': baseScenario()['memberships/ana'],
    'profiles/carol': { nickname: 'carol_ok', joinedAt: past(3600) },
  }));
  await assertSucceeds(run('bob', plan('reportPost')));
  await assertFails(getDoc(doc(db('carol'), 'posts/p1')));
  await assertFails(getDoc(doc(db('bob'), 'posts/p1'))); // nem o denunciante
  await assertSucceeds(getDoc(doc(db('ana'), 'posts/p1')));
  await assertSucceeds(getDoc(doc(db('mod'), 'posts/p1')));
  // A mesma pessoa não denuncia duas vezes (nem sem esconder).
  await assertFails(run('bob', plan('reportPostNoHide')));
  await assertFails(run('bob', plan('reportPost')));
});

test('denúncia de resposta: o lote do app passa e a resposta vira pending', async () => {
  await seed(env, base({ 'posts/p1': stored(), 'replies/r1': storedReply() }));
  await assertSucceeds(run('ana', mutated('reportReply', (p) => {
    find(p, 'reports/r1_bob').path = 'reports/r1_ana';
    find(p, 'reports/r1_ana').data.reporterUid = 'ana';
  })));
  await assertFails(getDoc(doc(db('ana'), 'replies/r1')));
  await assertSucceeds(getDoc(doc(db('bob'), 'replies/r1'))); // o autor segue vendo
  await assertSucceeds(getDoc(doc(db('mod'), 'replies/r1')));
});

test('denúncia: alvo já em análise (pending) grava só a denúncia; esconder de novo, nega (decisão hideTarget)', async () => {
  await seed(env, base({
    'posts/p1': stored({ status: 'pending' }),
    'reports/p1_ana': storedReport({ reporterUid: 'ana' }),
  }));
  // Lote com update visible->pending, como se o app tivesse mandado hide=true: nega.
  await assertFails(run('bob', plan('reportPost')));
  // Lote do app com hide=false: passa e o post continua pending.
  await assertSucceeds(run('bob', plan('reportPostNoHide')));
  let status;
  await env.withSecurityRulesDisabled(async (ctx) => {
    status = (await getDoc(doc(ctx.firestore(), 'posts/p1'))).data().status;
  });
  if (status !== 'pending') throw new Error('status mudou');
});

test('denúncia: alvo oculto (hidden) grava só a denúncia; com update, nega', async () => {
  await seed(env, base({ 'posts/p1': stored({ status: 'hidden', moderationReason: 'spam' }) }));
  await assertFails(run('bob', plan('reportPost')));
  await assertSucceeds(run('bob', plan('reportPostNoHide')));
});

test('denúncia: variações proibidas (motivo, detalhes, id, status, autor falso, não membro, lote sem relatório)', async () => {
  await seed(env, base({ 'posts/p1': stored() }));
  const rp = (p) => find(p, 'reports/p1_bob').data;
  await assertFails(run('bob', mutated('reportPost', (p) => (rp(p).reason = 'chato'))));
  await assertFails(run('bob', mutated('reportPost', (p) => (rp(p).details = 'x'.repeat(501)))));
  await assertFails(run('bob', mutated('reportPost', (p) => (rp(p).status = 'resolved'))));
  await assertFails(run('bob', mutated('reportPost', (p) => (rp(p).reporterUid = 'ana'))));
  await assertFails(run('bob', mutated('reportPost', (p) => (rp(p).postId = 'p2'))));
  await assertFails(run('bob', mutated('reportPost', (p) => (rp(p).extra = 1))));
  await assertFails(run('bob', mutated('reportPost', (p) => (rp(p).targetType = 'reply'))));
  await assertFails(run('bob', mutated('reportPost', (p) => (find(p, 'reports/p1_bob').path = 'reports/p1_ana'))));
  await assertFails(run('estranho', mutated('reportPost', (p) => {
    rp(p).reporterUid = 'estranho';
    find(p, 'reports/p1_bob').path = 'reports/p1_estranho';
  })));
  await assertFails(run('bob', mutated('reportPost', (p) => (find(p, 'posts/p1').data.title = 'Novo título'))));
  await assertSucceeds(run('bob', mutated('reportPost', (p) => (rp(p).details = 'x'.repeat(500)))));
});

test('denúncia: details vazio e todos os motivos do app são aceitos (membros distintos)', async () => {
  const reasons = ['offensive', 'harassment', 'personal_data', 'sexual_or_minor', 'copyright', 'spam', 'other'];
  const extra = { 'posts/p1': stored() };
  for (const i of reasons.keys()) {
    extra[`memberships/u${i}`] = baseScenario()['memberships/ana'];
    extra[`profiles/u${i}`] = { nickname: `usuario${i}`, joinedAt: past(3600) };
  }
  await seed(env, base(extra));
  for (const [i, reason] of reasons.entries()) {
    const w = mutated('reportPostNoHide', (p) => {
      find(p, 'reports/p1_bob').path = `reports/p1_u${i}`;
      find(p, `reports/p1_u${i}`).data.reporterUid = `u${i}`;
      find(p, `reports/p1_u${i}`).data.reason = reason;
    });
    if (find(w, `reports/p1_u${i}`).data.details !== '') throw new Error('details deveria ser vazio');
    await assertSucceeds(run(`u${i}`, w));
  }
});

test('denúncia: o lote sem o update do alvo também é aceito (esconder é escolha do cliente, não da regra)', async () => {
  await seed(env, base({ 'posts/p1': stored() }));
  await assertSucceeds(run('bob', plan('reportPostNoHide')));
  const s = await getDoc(doc(db('ana'), 'posts/p1'));
  if (s.data().status !== 'visible') throw new Error('status mudou');
});

// ---------- Moderar (CA-C5) ----------

test('moderação: restaurar, ocultar e ocultar+banir, com os lotes do app, em post', async () => {
  await seed(env, base({
    'posts/p1': stored({ status: 'pending' }),
    'reports/p1_bob': storedReport(),
  }));
  await assertSucceeds(run('mod', plan('resolveHidePost')));
  const o = await getDoc(doc(db('ana'), 'posts/p1'));
  if (o.data().status !== 'hidden' || o.data().moderationReason !== 'spam') throw new Error('oculto sem motivo');
  // Restaurar apaga o motivo (FieldValue.delete) e volta a ser visível aos outros.
  await assertSucceeds(run('mod', plan('resolveRestorePost')));
  const r = await getDoc(doc(db('bob'), 'posts/p1'));
  if (r.data().status !== 'visible' || 'moderationReason' in r.data()) throw new Error('restauração incompleta');
  const rep = await getDoc(doc(db('mod'), 'reports/p1_bob'));
  if (rep.data().status !== 'resolved') throw new Error('denúncia não resolvida');
});

test('moderação: ocultar e banir cria o ban; o banido não posta, mas apaga e lê o que é seu', async () => {
  await seed(env, base({
    'posts/p1': stored({ status: 'pending' }),
    'reports/p1_bob': storedReport(),
  }));
  await assertSucceeds(run('mod', plan('resolveBanPost')));
  await assertFails(run('ana', plan('post')));
  await assertSucceeds(getDoc(doc(db('ana'), 'bans/ana')));
  await assertSucceeds(getDoc(doc(db('ana'), 'posts/p1'))); // o autor vê o motivo
  await assertSucceeds(deleteDoc(doc(db('ana'), 'posts/p1')));
});

test('moderação: em resposta (ocultar e restaurar)', async () => {
  await seed(env, base({
    'posts/p1': stored(),
    'replies/r1': storedReply({ status: 'pending' }),
    'reports/r1_bob': storedReport({ targetType: 'reply', targetId: 'r1' }),
  }));
  await assertSucceeds(run('mod', plan('resolveHideReply')));
  await assertSucceeds(run('mod', plan('resolveRestoreReply')));
});

test('moderação: denúncia de conteúdo apagado é dispensada só pelo moderador', async () => {
  await seed(env, base({ 'reports/p1_bob': storedReport() }));
  await assertFails(run('bob', plan('resolveDeletedTarget')));
  await assertSucceeds(run('mod', plan('resolveDeletedTarget')));
  const rep = await getDoc(doc(db('mod'), 'reports/p1_bob'));
  if (rep.data().status !== 'resolved' || rep.data().decision !== 'targetDeleted') throw new Error('denúncia não dispensada');
});

test('moderação: membro comum não executa nenhum lote de decisão; o moderador sem decisão válida não bane', async () => {
  await seed(env, base({
    'posts/p1': stored({ status: 'pending' }),
    'replies/r1': storedReply({ status: 'pending' }),
    'reports/p1_bob': storedReport(),
    'reports/r1_bob': storedReport({ targetType: 'reply', targetId: 'r1' }),
  }));
  for (const name of ['resolveRestorePost', 'resolveHidePost', 'resolveBanPost']) {
    await assertFails(run('ana', plan(name)));
    await assertFails(run('bob', plan(name)));
  }
  for (const name of ['resolveHideReply', 'resolveRestoreReply']) await assertFails(run('ana', plan(name)));
  // Moderador não passa status pending nem muda outros campos do post.
  await assertFails(run('mod', mutated('resolveHidePost', (p) => (find(p, 'posts/p1').data.status = 'pending'))));
  await assertFails(run('mod', mutated('resolveHidePost', (p) => (find(p, 'posts/p1').data.title = 'Reescrito'))));
});

// ---------- Leituras que o repositório faz ----------

async function seedRead() {
  await seed(env, base({
    'posts/pv': stored({ createdAt: past(300) }),
    'posts/pp': stored({ status: 'pending', createdAt: past(200) }),
    'posts/pb': stored({ authorUid: 'bob', authorNickname: 'bob_ok', createdAt: past(100) }),
    'replies/rv': storedReply({ postId: 'pv' }),
    'replies/rp': storedReply({ postId: 'pv', authorUid: 'ana', authorNickname: 'ana_ok', status: 'pending' }),
    'helpfulVotes/rv_ana': { replyId: 'rv', postId: 'pv', authorUid: 'bob', voterUid: 'ana', createdAt: past(5) },
    'reports/pv_bob': storedReport({ targetId: 'pv', postId: 'pv' }),
  }));
}

test('leituras: as consultas do repositório (posts, respostas, votos, reputação) passam para membro', async () => {
  await seedRead();
  const ana = db('ana');
  const posts = await assertSucceeds(
    getDocs(
      query(
        collection(ana, 'posts'),
        where('communityId', '==', 'matematica'),
        where('status', '==', 'visible'),
        orderBy('createdAt', 'desc'),
      ),
    ),
  );
  if (posts.size !== 2) throw new Error(`esperava 2 posts visíveis, veio ${posts.size}`);
  const mine = await assertSucceeds(
    getDocs(query(collection(ana, 'posts'), where('authorUid', '==', 'ana'), where('communityId', '==', 'matematica'))),
  );
  if (mine.size !== 2) throw new Error('consulta do autor');
  await assertSucceeds(
    getDocs(
      query(collection(ana, 'replies'), where('postId', '==', 'pv'), where('status', '==', 'visible'), orderBy('createdAt')),
    ),
  );
  await assertSucceeds(
    getDocs(query(collection(ana, 'replies'), where('postId', '==', 'pv'), where('authorUid', '==', 'ana'))),
  );
  await assertSucceeds(
    getDocs(query(collection(ana, 'helpfulVotes'), where('voterUid', '==', 'ana'), where('postId', '==', 'pv'))),
  );
  await assertSucceeds(getDocs(query(collection(ana, 'helpfulVotes'), where('postId', '==', 'pv'))));
  await assertSucceeds(getCountFromServer(query(collection(ana, 'helpfulVotes'), where('replyId', '==', 'rv'))));
  const mineVotes = await assertSucceeds(
    getCountFromServer(query(collection(ana, 'helpfulVotes'), where('authorUid', '==', 'bob'))),
  );
  if (mineVotes.data().count !== 1) throw new Error('contagem de ajudas');
  await assertSucceeds(getCountFromServer(collection(ana, 'helpfulVotes')));
  const profiles = await assertSucceeds(getCountFromServer(collection(ana, 'profiles')));
  if (profiles.data().count !== 3) throw new Error('perfis');
});

test('leituras: não membro e banido não leem posts, votos nem perfis; o moderador lê a fila de abertas', async () => {
  await seedRead();
  await seed(env, { 'bans/bob': { at: past(5), reason: 'x' } });
  for (const uid of ['estranho', 'bob']) {
    const d = db(uid);
    await assertFails(
      getDocs(query(collection(d, 'posts'), where('communityId', '==', 'matematica'), where('status', '==', 'visible'))),
    );
    await assertFails(getCountFromServer(collection(d, 'helpfulVotes')));
    await assertFails(getCountFromServer(collection(d, 'profiles')));
  }
  const mod = db('mod');
  const open = await assertSucceeds(
    getDocs(query(collection(mod, 'reports'), where('status', '==', 'open'), orderBy('createdAt'), )),
  );
  if (open.size !== 1) throw new Error('fila');
  // Membro comum não lê a fila; lê as próprias denúncias (checagem de duplicidade do app).
  await assertFails(getDocs(query(collection(db('ana'), 'reports'), where('status', '==', 'open'))));
  await assertSucceeds(
    getDocs(query(collection(db('ana'), 'reports'), where('reporterUid', '==', 'ana'), where('targetId', '==', 'pv'))),
  );
});

// ---------- CA-T7: myFootprint cobre tudo e a cascata passa pelas regras ----------

test('CA-T7: as consultas do myFootprint acham todos os documentos de ana, antes e depois de sair', async () => {
  await seed(env, base({
    'posts/p1': stored({ status: 'hidden', moderationReason: 'x' }),
    'posts/p2': stored(),
    'replies/r1': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok', postId: 'p9' }),
    'replies/r2': storedReply({ authorUid: 'ana', authorNickname: 'ana_ok', status: 'pending', postId: 'p9' }),
    'helpfulVotes/r1_bob': { replyId: 'r1', postId: 'p9', authorUid: 'ana', voterUid: 'bob', createdAt: past(5) },
    'helpfulVotes/r7_ana': { replyId: 'r7', postId: 'p9', authorUid: 'bob', voterUid: 'ana', createdAt: past(5) },
    'reports/p9_ana': storedReport({ reporterUid: 'ana', targetId: 'p9', postId: 'p9' }),
    'reports/p8_ana': storedReport({ reporterUid: 'ana', targetId: 'p8', postId: 'p8', status: 'resolved' }),
    'conectaLimits/ana': { lastWriteAt: past(100) },
  }));
  const footprint = async (d) => ({
    posts: (await getDocs(query(collection(d, 'posts'), where('authorUid', '==', 'ana')))).size,
    replies: (await getDocs(query(collection(d, 'replies'), where('authorUid', '==', 'ana')))).size,
    given: (await getDocs(query(collection(d, 'helpfulVotes'), where('voterUid', '==', 'ana')))).size,
    received: (await getDocs(query(collection(d, 'helpfulVotes'), where('authorUid', '==', 'ana')))).size,
    reports: (await getDocs(query(collection(d, 'reports'), where('reporterUid', '==', 'ana')))).size,
  });
  const esperado = { posts: 2, replies: 2, given: 1, received: 1, reports: 2 };
  const antes = await assertSucceeds(footprint(db('ana')));
  if (JSON.stringify(antes) !== JSON.stringify(esperado)) throw new Error(`antes: ${JSON.stringify(antes)}`);

  // Cascata: tudo o que o footprint lista, menos a denúncia aberta (exceção documentada); depois o lote de saída.
  const ana = db('ana');
  for (const p of ['posts/p1', 'posts/p2', 'replies/r1', 'replies/r2', 'helpfulVotes/r1_bob', 'helpfulVotes/r7_ana', 'reports/p8_ana']) {
    await assertSucceeds(deleteDoc(doc(ana, p)));
  }
  await assertFails(deleteDoc(doc(ana, 'reports/p9_ana'))); // aberta: só o moderador
  const batch = writeBatch(ana);
  batch.delete(doc(ana, 'conectaLimits/ana'));
  batch.delete(doc(ana, 'memberships/ana'));
  batch.delete(doc(ana, 'profiles/ana'));
  await assertSucceeds(batch.commit());

  // Já sem membership, as consultas do footprint ainda passam e só sobra a denúncia aberta.
  const depois = await assertSucceeds(footprint(db('ana')));
  if (JSON.stringify(depois) !== JSON.stringify({ posts: 0, replies: 0, given: 0, received: 0, reports: 1 })) {
    throw new Error(`depois: ${JSON.stringify(depois)}`);
  }
});

test('CA-T7: banido tem o footprint legível e consegue apagar tudo', async () => {
  await seed(env, base({
    'bans/ana': { at: past(5), reason: 'x' },
    'posts/p1': stored(),
    'helpfulVotes/r1_bob': { replyId: 'r1', postId: 'p9', authorUid: 'ana', voterUid: 'bob', createdAt: past(5) },
  }));
  const ana = db('ana');
  await assertSucceeds(getDocs(query(collection(ana, 'posts'), where('authorUid', '==', 'ana'))));
  await assertSucceeds(getDocs(query(collection(ana, 'helpfulVotes'), where('authorUid', '==', 'ana'))));
  await assertSucceeds(deleteDoc(doc(ana, 'posts/p1')));
  await assertSucceeds(deleteDoc(doc(ana, 'helpfulVotes/r1_bob')));
});
