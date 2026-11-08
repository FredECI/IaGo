// Ataques extras da validação de QA (F3): tentativas de burlar as regras que os
// testes de cada área não cobrem. Testes com nome "regressão:" descrevem o
// comportamento correto e FALHAM hoje; viram regressão quando a regra for corrigida.
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { Bytes, deleteDoc, doc, getDoc, setDoc, updateDoc, writeBatch } from 'firebase/firestore';

import { baseScenario, enter, leave, newEnv, past, seed, ts } from './helpers.mjs';

let env;
before(async () => (env = await newEnv('demo-iago-attacks')));
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
const storedPost = (over = {}) => ({ ...postData(over), createdAt: past(600) });
const join = (over = {}) => ({
  nickname: 'novato',
  inviteCode: 'turma1',
  declaredMinAge: 18,
  rulesVersion: '1',
  joinedAt: ts(),
  ...over,
});

// ---------- Questões do usuário com os campos novos da F2 ----------

test('F2: questão com os campos novos (origin, bankId, myDifficulty, myQuality, nulos) é aceita pelo dono', async () => {
  const pedro = db('pedro');
  const full = {
    statement: 'Enunciado',
    type: 'objective',
    alternatives: ['a', 'b', 'c', 'd', 'e'],
    area: 'mathematics',
    subject: 'Matemática',
    topic: '',
    platform: 'ENEM 2022',
    sourceUrl: null,
    notes: null,
    hasImage: false,
    createdAt: new Date(),
    updatedAt: new Date(),
    origin: 'bank',
    bankId: 'enem-2022-136',
    myDifficulty: 2,
    myQuality: null,
  };
  await assertSucceeds(setDoc(doc(pedro, 'users/pedro/questions/bank_enem-2022-136'), full));
  await assertSucceeds(
    setDoc(doc(pedro, 'users/pedro/questions/imp1'), { ...full, origin: 'import', bankId: null }),
  );
  // Salvar de novo (mesmo id) é uma gravação sobre o mesmo documento.
  await assertSucceeds(setDoc(doc(pedro, 'users/pedro/questions/bank_enem-2022-136'), full));
  // Outro usuário continua sem acesso.
  await assertFails(getDoc(doc(db('ana'), 'users/pedro/questions/bank_enem-2022-136')));
  await assertFails(setDoc(doc(db('ana'), 'users/pedro/questions/bank_x'), full));
});

// ---------- Política de idade e convite: tipos estranhos no runtime ----------

test('minAge com tipo estranho (decimal, bool, nulo, negativo) vale o piso de 18', async () => {
  for (const [i, bad] of [21.5, true, null, -5, 0, [21], { v: 21 }].entries()) {
    await env.clearFirestore();
    await seed(env, { 'invites/turma1': { ok: true }, 'appConfig/runtime': { minAge: bad } });
    await assertFails(
      enter(doc(db(`u17_${i}`), `memberships/u17_${i}`), join({ declaredMinAge: 17 })),
    );
    await assertSucceeds(
      enter(doc(db(`u18_${i}`), `memberships/u18_${i}`), join({ declaredMinAge: 18 })),
    );
  }
});

test('declaredMinAge com tipo estranho (bool, nulo, lista, negativo, ausente), nega', async () => {
  await seed(env, { 'invites/turma1': { ok: true }, 'appConfig/runtime': {} });
  const { declaredMinAge, ...semIdade } = join();
  await assertFails(enter(doc(db('a'), 'memberships/a'), semIdade));
  for (const [i, bad] of [true, null, [18], -1, 1e12 + 0.5, 'dezoito'].entries()) {
    await assertFails(enter(doc(db(`b${i}`), `memberships/b${i}`), join({ declaredMinAge: bad })));
  }
  // Idade acima do piso é aceita (o piso é mínimo, não valor exato).
  await assertSucceeds(enter(doc(db('c'), 'memberships/c'), join({ declaredMinAge: 30 })));
});

test('inviteRequired com tipo estranho (nulo, 0, texto) continua exigindo convite', async () => {
  for (const [i, bad] of [null, 0, 'false', [false]].entries()) {
    await env.clearFirestore();
    await seed(env, { 'invites/turma1': { ok: true }, 'appConfig/runtime': { inviteRequired: bad } });
    const { inviteCode, ...semConvite } = join();
    await assertFails(enter(doc(db(`u${i}`), `memberships/u${i}`), semConvite));
  }
});

test('convite: código com barra ou ponto não aponta para outro documento (injeção de caminho)', async () => {
  await seed(env, {
    'invites/turma1': { ok: true },
    'appConfig/runtime': {},
    'admins/fred': { since: 1 },
    'moderators/mod': { ok: true },
  });
  const codes = [
    '../admins/fred',
    '../moderators/mod',
    'turma1/',
    '/turma1',
    'turma1/x',
    '..',
    '.',
    'turma1 ',
    'TURMA1',
    '',
  ];
  for (const [i, code] of codes.entries()) {
    await assertFails(
      enter(doc(db(`u${i}`), `memberships/u${i}`), join({ inviteCode: code })),
    );
  }
});

test('só o dono entra na própria membership, mesmo com convite válido (id alheio, update disfarçado de create)', async () => {
  await seed(env, { 'invites/turma1': { ok: true }, 'appConfig/runtime': {} });
  await assertFails(enter(doc(db('a'), 'memberships/b'), join()));
  await assertSucceeds(enter(doc(db('a'), 'memberships/a'), join()));
  // Regravar por cima (vira update) não pode trocar a idade nem o convite.
  await assertFails(enter(doc(db('a'), 'memberships/a'), join({ declaredMinAge: 99 })));
  await assertFails(enter(doc(db('a'), 'memberships/a'), join({ nickname: 'novo_nome' })));
});

// ---------- Banimento ----------

test('banido não recria a membership para se livrar do banimento nem escreve depois de sair e entrar', async () => {
  await seed(env, {
    ...baseScenario(),
    'bans/bob': { at: 1, reason: 'spam' },
    'conectaLimits/bob': { lastWriteAt: past(100) },
  });
  const bob = db('bob');
  await assertSucceeds(leave(bob, 'bob'));
  await assertSucceeds(enter(doc(bob, 'memberships/bob'), join({ nickname: 'bob_volta' })));
  const batch = writeBatch(bob);
  batch.set(doc(bob, 'posts/pb'), postData({ authorUid: 'bob', authorNickname: 'bob_volta' }));
  batch.set(doc(bob, 'conectaLimits/bob'), { lastWriteAt: ts(), lastDocPath: 'posts/pb' });
  await assertFails(batch.commit());
});

test('banido não se desbane nem lê a fila de moderação', async () => {
  await seed(env, { ...baseScenario(), 'bans/bob': { at: 1, reason: 'spam' } });
  await assertFails(deleteDoc(doc(db('bob'), 'bans/bob')));
  await assertFails(setDoc(doc(db('bob'), 'bans/bob'), { at: 2 }));
  await assertFails(setDoc(doc(db('ana'), 'bans/ana'), { at: 2 }));
});

// ---------- Moderador ----------

test('moderador não lê nem grava dados privados de outro usuário, nem eventos e imagens', async () => {
  await seed(env, {
    ...baseScenario(),
    'users/pedro': { name: 'Pedro', email: 'p@x.com' },
    'users/pedro/lists/l1': { name: 'Reforço' },
    'users/pedro/events/e1': { type: 'active' },
    'users/pedro/questionImages/q1': { bytes: Bytes.fromUint8Array(new Uint8Array([1])) },
  });
  const mod = db('mod');
  for (const path of [
    'users/pedro',
    'users/pedro/lists/l1',
    'users/pedro/events/e1',
    'users/pedro/questionImages/q1',
  ]) {
    await assertFails(getDoc(doc(mod, path)));
  }
  await assertFails(setDoc(doc(mod, 'users/pedro/questions/qx'), { statement: 'x' }));
  await assertFails(deleteDoc(doc(mod, 'users/pedro/lists/l1')));
  await assertFails(setDoc(doc(mod, 'admins/mod'), { ok: true }));
});

test('moderador só altera status, motivo e data; não edita texto nem autor de post alheio', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': storedPost() });
  const mod = db('mod');
  await assertFails(updateDoc(doc(mod, 'posts/p1'), { body: 'editado' }));
  await assertFails(updateDoc(doc(mod, 'posts/p1'), { authorUid: 'mod' }));
  await assertFails(updateDoc(doc(mod, 'posts/p1'), { status: 'pending' }));
  await assertFails(updateDoc(doc(mod, 'posts/p1'), { status: 'qualquer' }));
  await assertSucceeds(
    updateDoc(doc(mod, 'posts/p1'), { status: 'hidden', moderationReason: 'spam', moderatedAt: ts() }),
  );
});

test('membro comum não se promove: nem moderators, nem bans, nem admins', async () => {
  await seed(env, baseScenario());
  await assertFails(setDoc(doc(db('ana'), 'moderators/ana'), { ok: true }));
  await assertFails(setDoc(doc(db('ana'), 'admins/ana'), { ok: true }));
  await assertFails(setDoc(doc(db('ana'), 'bans/bob'), { at: 1 }));
  await assertFails(updateDoc(doc(db('ana'), 'posts/p1'), { status: 'hidden' }));
});

// ---------- Posts ----------

test('post: autor falso, apelido de outra pessoa e apelido do moderador, nega', async () => {
  await seed(env, baseScenario());
  const ana = db('ana');
  const tenta = async (over) => {
    const batch = writeBatch(ana);
    batch.set(doc(ana, 'posts/px'), postData(over));
    batch.set(doc(ana, 'conectaLimits/ana'), { lastWriteAt: ts(), lastDocPath: 'posts/px' });
    return batch.commit();
  };
  await assertFails(tenta({ authorUid: 'bob' }));
  await assertFails(tenta({ authorNickname: 'moderadora' }));
  await assertFails(tenta({ authorNickname: 'bob_ok' }));
  await assertFails(tenta({ extra: 'x' }));
  await assertFails(tenta({ moderationReason: 'oculto' }));
  await assertFails(tenta({ status: 'pending' }));
  await assertSucceeds(tenta({}));
});

test('regressão: post com várias criações no mesmo lote não burla o intervalo de 30 s', async () => {
  // Hoje cooldownOk() só olha o estado ANTES do lote; um lote com N posts e uma
  // atualização de conectaLimits passa em todos. Esperado: no máximo 1 escrita por lote.
  await seed(env, baseScenario());
  const ana = db('ana');
  const batch = writeBatch(ana);
  batch.set(doc(ana, 'posts/a1'), postData());
  batch.set(doc(ana, 'posts/a2'), postData());
  batch.set(doc(ana, 'posts/a3'), postData());
  batch.set(doc(ana, 'conectaLimits/ana'), { lastWriteAt: ts(), lastDocPath: 'posts/a1' });
  await assertFails(batch.commit());
  // Cada documento sozinho, com o limite apontando para ele, passa.
  const um = writeBatch(ana);
  um.set(doc(ana, 'posts/a1'), postData());
  um.set(doc(ana, 'conectaLimits/ana'), { lastWriteAt: ts(), lastDocPath: 'posts/a1' });
  await assertSucceeds(um.commit());
});

test('regressão: post com bankId de tipo e tamanho livres (mapa, número, 10 KB) deveria ser negado', async () => {
  // A spec usa bankId só para citar o acervo; deve ser string no padrão fonte-resto.
  await seed(env, baseScenario());
  const ana = db('ana');
  for (const [i, bad] of [{ a: 1 }, 42, 'x'.repeat(10_000), ['a']].entries()) {
    await env.clearFirestore();
    await seed(env, baseScenario());
    const batch = writeBatch(ana);
    batch.set(doc(ana, `posts/b${i}`), postData({ bankId: bad }));
    batch.set(doc(ana, 'conectaLimits/ana'), { lastWriteAt: ts(), lastDocPath: `posts/b${i}` });
    await assertFails(batch.commit());
  }
  // bankId ausente ou no padrão fonte-resto passa.
  for (const [i, ok] of [undefined, 'enem-2022-136'].entries()) {
    await env.clearFirestore();
    await seed(env, baseScenario());
    const batch = writeBatch(ana);
    batch.set(doc(ana, `posts/c${i}`), postData(ok === undefined ? {} : { bankId: ok }));
    batch.set(doc(ana, 'conectaLimits/ana'), { lastWriteAt: ts(), lastDocPath: `posts/c${i}` });
    await assertSucceeds(batch.commit());
  }
});

// ---------- Denúncia ----------

test('regressão: denúncia antiga não autoriza esconder de novo o mesmo conteúdo sem nova denúncia', async () => {
  // O moderador restaurou o post, mas o relatório reports/p1_bob continua existindo.
  // reportedNow() usa existsAfter(), que vê o relatório antigo: bob volta a pôr
  // o post em pending sozinho, quantas vezes quiser. Esperado: negar.
  await seed(env, {
    ...baseScenario(),
    'posts/p1': storedPost(),
    'reports/p1_bob': {
      targetType: 'post',
      targetId: 'p1',
      postId: 'p1',
      reason: 'spam',
      details: '',
      reporterUid: 'bob',
      status: 'resolved',
      createdAt: past(300),
    },
  });
  await assertFails(updateDoc(doc(db('bob'), 'posts/p1'), { status: 'pending' }));
});

test('denúncia: quem denuncia não consegue ocultar (hidden) nem restaurar; autor não restaura o próprio', async () => {
  await seed(env, { ...baseScenario(), 'posts/p1': storedPost({ status: 'pending' }) });
  await assertFails(updateDoc(doc(db('ana'), 'posts/p1'), { status: 'visible' }));
  await assertFails(updateDoc(doc(db('bob'), 'posts/p1'), { status: 'visible' }));
  await assertSucceeds(updateDoc(doc(db('mod'), 'posts/p1'), { status: 'visible' }));
});

// ---------- Ajudou ----------

test('ajudou: voto na própria resposta, em nome de outro e com resposta inexistente, nega', async () => {
  await seed(env, {
    ...baseScenario(),
    'posts/p1': storedPost(),
    'replies/r1': {
      postId: 'p1',
      authorUid: 'ana',
      authorNickname: 'ana_ok',
      body: 'Resposta',
      status: 'visible',
      createdAt: past(300),
    },
  });
  const vote = (over = {}) => ({
    replyId: 'r1',
    postId: 'p1',
    authorUid: 'ana',
    voterUid: 'bob',
    createdAt: ts(),
    ...over,
  });
  await assertFails(setDoc(doc(db('ana'), 'helpfulVotes/r1_ana'), vote({ voterUid: 'ana' })));
  await assertFails(setDoc(doc(db('bob'), 'helpfulVotes/r1_ana'), vote({ voterUid: 'ana' })));
  await assertFails(setDoc(doc(db('bob'), 'helpfulVotes/r9_bob'), vote({ replyId: 'r9' })));
  await assertFails(setDoc(doc(db('bob'), 'helpfulVotes/r1_bob'), vote({ authorUid: 'bob' })));
  await assertFails(setDoc(doc(db('bob'), 'helpfulVotes/r1_bob'), vote({ createdAt: new Date() })));
  await assertSucceeds(setDoc(doc(db('bob'), 'helpfulVotes/r1_bob'), vote()));
  // O voto não pode ser alterado depois (troca de autor para inflar outra pessoa).
  await assertFails(updateDoc(doc(db('bob'), 'helpfulVotes/r1_bob'), { authorUid: 'bob' }));
});

// ---------- Membership: update ----------

test('regressão: atualizar a membership não valida o tipo de rulesVersion (aceita número ou mapa)', async () => {
  // Na criação, rulesVersion precisa ser string; no update, não. O reaceite das
  // regras da comunidade (CA-R6) depende desse valor.
  await seed(env, baseScenario());
  const ana = db('ana');
  await assertFails(updateDoc(doc(ana, 'memberships/ana'), { rulesVersion: 5 }));
  await assertFails(updateDoc(doc(ana, 'memberships/ana'), { rulesVersion: { a: 1 } }));
  await assertSucceeds(updateDoc(doc(ana, 'memberships/ana'), { rulesVersion: '2' }));
});

// ---------- Avaliações ----------

test('avaliação: quem não é membro não apaga a de outro; área e matéria extras são só campos conhecidos', async () => {
  await seed(env, baseScenario());
  const rating = (uid, over = {}) => ({
    bankId: 'enem-2022-136',
    uid,
    area: 'mathematics',
    subject: 'Matemática',
    difficulty: 2,
    quality: 3,
    updatedAt: ts(),
    ...over,
  });
  await assertSucceeds(setDoc(doc(db('ana'), 'questionRatings/enem-2022-136_ana'), rating('ana')));
  await assertFails(deleteDoc(doc(db('bob'), 'questionRatings/enem-2022-136_ana')));
  await assertFails(deleteDoc(doc(db('estranho'), 'questionRatings/enem-2022-136_ana')));
  // Avaliação "em nome" de outra pessoa trocando só o uid do documento existente.
  await assertFails(updateDoc(doc(db('bob'), 'questionRatings/enem-2022-136_ana'), { difficulty: 1 }));
  await assertFails(updateDoc(doc(db('ana'), 'questionRatings/enem-2022-136_ana'), { uid: 'bob' }));
});

test('regressão: avaliação com area e subject de tipo e tamanho livres (mapa, 100 KB) deveria ser negada', async () => {
  // O resumo compara com a média da matéria; sem validar, uma conta grava lixo.
  await seed(env, baseScenario());
  await assertFails(
    setDoc(doc(db('ana'), 'questionRatings/enem-2022-136_ana'), {
      bankId: 'enem-2022-136',
      uid: 'ana',
      difficulty: 2,
      quality: 3,
      updatedAt: ts(),
      area: { x: 1 },
      subject: 'x'.repeat(100_000),
    }),
  );
});

test('regressão: avaliação sem area e subject deveria ser negada (sujaria a comparação com a matéria)', async () => {
  await seed(env, baseScenario());
  await assertFails(
    setDoc(doc(db('ana'), 'questionRatings/enem-2022-136_ana'), {
      bankId: 'enem-2022-136',
      uid: 'ana',
      difficulty: 2,
      quality: 3,
      updatedAt: ts(),
    }),
  );
});
