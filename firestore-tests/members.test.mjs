// Entrada no piloto e política de acesso (CA-C1, CA-R1): idade, convite, e-mail.
import { after, before, beforeEach, test } from 'node:test';

import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc, writeBatch } from 'firebase/firestore';

import { enter, leave, newEnv, seed, ts } from './helpers.mjs';

let env;
before(async () => (env = await newEnv('demo-iago-members')));
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
const semConvite = (over = {}) => {
  const { inviteCode, ...resto } = join(over);
  return resto;
};

const base = { 'invites/turma1': { ok: true } };
const withRuntime = (runtime) => ({ ...base, 'appConfig/runtime': runtime });
const stored = (nick) => ({
  nickname: nick,
  inviteCode: 'turma1',
  declaredMinAge: 18,
  rulesVersion: '1',
  joinedAt: new Date(),
});

test('entrada: tudo certo aceita', async () => {
  await seed(env, withRuntime({}));
  await assertSucceeds(enter(doc(verified('novo'), 'memberships/novo'), join()));
});

test('entrada: sem e-mail verificado, nega', async () => {
  await seed(env, withRuntime({}));
  await assertFails(enter(doc(unverified('novo'), 'memberships/novo'), join()));
  const semClaim = env.authenticatedContext('novo').firestore();
  await assertFails(enter(doc(semClaim, 'memberships/novo'), join()));
});

test('entrada: código de convite inválido ou ausente, nega', async () => {
  await seed(env, withRuntime({}));
  const novo = verified('novo');
  await assertFails(enter(doc(novo, 'memberships/novo'), join({ inviteCode: 'falso' })));
  await assertFails(enter(doc(novo, 'memberships/novo'), join({ inviteCode: 42 })));
  await assertFails(enter(doc(novo, 'memberships/novo'), semConvite()));
});

test('entrada: apelido de 2 ou 25 caracteres, nega; 3 e 24 passam', async () => {
  await seed(env, withRuntime({}));
  await assertFails(enter(doc(verified('a'), 'memberships/a'), join({ nickname: 'ab' })));
  await assertFails(
    enter(doc(verified('b'), 'memberships/b'), join({ nickname: 'x'.repeat(25) })),
  );
  await assertFails(enter(doc(verified('c'), 'memberships/c'), join({ nickname: 7 })));
  await assertSucceeds(enter(doc(verified('d'), 'memberships/d'), join({ nickname: 'abc' })));
  await assertSucceeds(
    enter(doc(verified('e'), 'memberships/e'), join({ nickname: 'x'.repeat(24) })),
  );
});

test('entrada: id de outra pessoa, campo extra, data do cliente e rulesVersion errada, nega', async () => {
  await seed(env, withRuntime({}));
  const novo = verified('novo');
  await assertFails(enter(doc(novo, 'memberships/outro'), join()));
  await assertFails(enter(doc(novo, 'memberships/novo'), join({ extra: 1 })));
  await assertFails(enter(doc(novo, 'memberships/novo'), join({ joinedAt: new Date() })));
  await assertFails(enter(doc(novo, 'memberships/novo'), join({ rulesVersion: 1 })));
});

test('política (CA-R1): sem minAge, 17 nega e 18 aceita; valor não inteiro nega', async () => {
  await seed(env, withRuntime({ conectaWritesEnabled: true }));
  await assertFails(enter(doc(verified('u17'), 'memberships/u17'), join({ declaredMinAge: 17 })));
  await assertFails(enter(doc(verified('ux'), 'memberships/ux'), join({ declaredMinAge: '18' })));
  await assertFails(enter(doc(verified('ud'), 'memberships/ud'), join({ declaredMinAge: 18.5 })));
  await assertSucceeds(enter(doc(verified('u18'), 'memberships/u18'), join({ declaredMinAge: 18 })));
});

test('política (CA-R1): minAge=21 sobe o piso; minAge=16 não baixa dos termos; tipo errado vale 18', async () => {
  await seed(env, withRuntime({ minAge: 21 }));
  await assertFails(enter(doc(verified('a'), 'memberships/a'), join({ declaredMinAge: 18 })));
  await assertSucceeds(enter(doc(verified('b'), 'memberships/b'), join({ declaredMinAge: 21 })));
  await env.clearFirestore();

  await seed(env, withRuntime({ minAge: 16 }));
  await assertFails(enter(doc(verified('c'), 'memberships/c'), join({ declaredMinAge: 16 })));
  await assertSucceeds(enter(doc(verified('d'), 'memberships/d'), join({ declaredMinAge: 18 })));
  await env.clearFirestore();

  await seed(env, withRuntime({ minAge: '25' }));
  await assertFails(enter(doc(verified('e'), 'memberships/e'), join({ declaredMinAge: 17 })));
  await assertSucceeds(enter(doc(verified('f'), 'memberships/f'), join({ declaredMinAge: 18 })));
});

test('política (CA-R1): mudar o runtime muda o resultado da mesma entrada', async () => {
  const entrada = () => enter(doc(verified('p'), 'memberships/p'), join({ declaredMinAge: 18 }));
  await seed(env, withRuntime({ minAge: 21 }));
  await assertFails(entrada());
  await seed(env, { 'appConfig/runtime': { minAge: 18 } });
  await assertSucceeds(entrada());
});

test('política (CA-R1): convite exigido por padrão; inviteRequired=false dispensa', async () => {
  await seed(env, withRuntime({}));
  await assertFails(enter(doc(verified('a'), 'memberships/a'), semConvite()));
  await env.clearFirestore();

  await seed(env, withRuntime({ inviteRequired: true }));
  await assertFails(enter(doc(verified('b'), 'memberships/b'), semConvite()));
  await env.clearFirestore();

  await seed(env, withRuntime({ inviteRequired: false }));
  await assertSucceeds(enter(doc(verified('c'), 'memberships/c'), semConvite()));
  // Com o convite dispensado, a idade continua valendo.
  await assertFails(
    enter(doc(verified('d'), 'memberships/d'), semConvite({ declaredMinAge: 17 })),
  );
  await env.clearFirestore();

  // Tipo errado cai no padrão seguro (exigir).
  await seed(env, withRuntime({ inviteRequired: 'false' }));
  await assertFails(enter(doc(verified('e'), 'memberships/e'), semConvite()));
});

test('política: sem appConfig/runtime a entrada é negada', async () => {
  await seed(env, base);
  await assertFails(enter(doc(verified('novo'), 'memberships/novo'), join()));
});

const seedMembers = () => ({
  ...withRuntime({}),
  'memberships/ana': stored('ana_ok'),
  'memberships/bob': stored('bob_ok'),
  'profiles/ana': { nickname: 'ana_ok', joinedAt: new Date() },
  'profiles/bob': { nickname: 'bob_ok', joinedAt: new Date() },
});

test('privacidade: a membership só o dono lê; o perfil (só apelido) os membros leem', async () => {
  await seed(env, seedMembers());
  const ana = verified('ana');
  await assertSucceeds(getDoc(doc(ana, 'memberships/ana')));
  // Idade declarada e código de convite não vazam para outro membro nem para estranhos.
  await assertFails(getDoc(doc(ana, 'memberships/bob')));
  await assertFails(getDoc(doc(verified('estranho'), 'memberships/bob')));
  await assertFails(getDocs(collection(ana, 'memberships')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'memberships/ana')));
  // O perfil público traz só nickname e joinedAt.
  const perfil = await assertSucceeds(getDoc(doc(ana, 'profiles/bob')));
  if (Object.keys(perfil.data()).sort().join() !== 'joinedAt,nickname') throw new Error('perfil com campo a mais');
  await assertFails(getDoc(doc(verified('estranho'), 'profiles/bob')));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), 'profiles/bob')));
});

test('perfil: criação exige membership no mesmo lote, só com o apelido do próprio usuário', async () => {
  await seed(env, withRuntime({}));
  const novo = verified('novo');
  // Perfil sozinho, sem membership: nega.
  await assertFails(setDoc(doc(novo, 'profiles/novo'), { nickname: 'novato', joinedAt: ts() }));
  // Membership sozinha, sem perfil: nega.
  await assertFails(setDoc(doc(novo, 'memberships/novo'), join()));
  // Apelidos diferentes nos dois documentos: nega.
  const b1 = writeBatch(novo);
  b1.set(doc(novo, 'memberships/novo'), join());
  b1.set(doc(novo, 'profiles/novo'), { nickname: 'outro_nome', joinedAt: ts() });
  await assertFails(b1.commit());
  // Perfil de outra pessoa: nega.
  const b2 = writeBatch(novo);
  b2.set(doc(novo, 'memberships/novo'), join());
  b2.set(doc(novo, 'profiles/novo'), { nickname: 'novato', joinedAt: ts() });
  b2.set(doc(novo, 'profiles/ana'), { nickname: 'novato', joinedAt: ts() });
  await assertFails(b2.commit());
  // Campo a mais (idade, convite) ou data do cliente no perfil: nega.
  for (const extra of [{ declaredMinAge: 18 }, { inviteCode: 'turma1' }, { rulesVersion: '1' }]) {
    const b3 = writeBatch(novo);
    b3.set(doc(novo, 'memberships/novo'), join());
    b3.set(doc(novo, 'profiles/novo'), { nickname: 'novato', joinedAt: ts(), ...extra });
    await assertFails(b3.commit());
  }
  const b4 = writeBatch(novo);
  b4.set(doc(novo, 'memberships/novo'), join());
  b4.set(doc(novo, 'profiles/novo'), { nickname: 'novato', joinedAt: new Date() });
  await assertFails(b4.commit());
  // Tudo certo: aceita.
  const ok = writeBatch(novo);
  ok.set(doc(novo, 'memberships/novo'), join());
  ok.set(doc(novo, 'profiles/novo'), { nickname: 'novato', joinedAt: ts() });
  await assertSucceeds(ok.commit());
});

test('alteração: apelido muda nos dois documentos juntos; só apelido e rulesVersion mudam', async () => {
  await seed(env, seedMembers());
  const ana = verified('ana');
  await assertSucceeds(updateDoc(doc(ana, 'memberships/ana'), { rulesVersion: '2' }));
  // Só a membership ou só o perfil com apelido novo: nega (ficariam diferentes).
  await assertFails(updateDoc(doc(ana, 'memberships/ana'), { nickname: 'ana_nova' }));
  await assertFails(updateDoc(doc(ana, 'profiles/ana'), { nickname: 'ana_nova' }));
  const b = writeBatch(ana);
  b.update(doc(ana, 'memberships/ana'), { nickname: 'ana_nova', rulesVersion: '3' });
  b.update(doc(ana, 'profiles/ana'), { nickname: 'ana_nova' });
  await assertSucceeds(b.commit());
  const ruim = writeBatch(ana);
  ruim.update(doc(ana, 'memberships/ana'), { nickname: 'ab' });
  ruim.update(doc(ana, 'profiles/ana'), { nickname: 'ab' });
  await assertFails(ruim.commit());
  await assertFails(updateDoc(doc(ana, 'memberships/ana'), { declaredMinAge: 99 }));
  await assertFails(updateDoc(doc(ana, 'memberships/ana'), { inviteCode: 'outro' }));
  await assertFails(updateDoc(doc(ana, 'profiles/ana'), { joinedAt: ts() }));
  await assertFails(updateDoc(doc(ana, 'profiles/ana'), { declaredMinAge: 18 }));
  // Nada de mexer na membership ou no perfil de outra pessoa.
  await assertFails(updateDoc(doc(ana, 'memberships/bob'), { rulesVersion: '9' }));
  await assertFails(updateDoc(doc(ana, 'profiles/bob'), { nickname: 'invadido' }));
  await assertFails(deleteDoc(doc(ana, 'memberships/bob')));
  await assertFails(deleteDoc(doc(ana, 'profiles/bob')));
});

test('saída: membership e perfil saem juntos; apagar só a membership, nega', async () => {
  await seed(env, seedMembers());
  const ana = verified('ana');
  await assertFails(deleteDoc(doc(ana, 'memberships/ana')));
  await assertSucceeds(leave(ana, 'ana'));
  // Depois de sair, o apelido some do perfil público.
  const depois = await assertSucceeds(getDoc(doc(verified('bob'), 'profiles/ana')));
  if (depois.exists()) throw new Error('perfil ficou');
});

test('banido lê a própria membership, mas não os perfis dos outros', async () => {
  await seed(env, { ...seedMembers(), 'bans/ana': { at: 1, reason: 'x' } });
  await assertSucceeds(getDoc(doc(verified('ana'), 'memberships/ana')));
  await assertSucceeds(getDoc(doc(verified('ana'), 'profiles/ana')));
  await assertFails(getDoc(doc(verified('ana'), 'profiles/bob')));
});
