// Apoio dos testes de regras: cada arquivo usa um projeto próprio no emulador,
// para os arquivos rodarem em paralelo sem se atropelar.
import { readFileSync } from 'node:fs';

import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, serverTimestamp, setDoc, Timestamp, writeBatch } from 'firebase/firestore';

export async function newEnv(projectId) {
  return initializeTestEnvironment({
    projectId,
    firestore: {
      rules: readFileSync('firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8085,
    },
  });
}

export const ts = serverTimestamp;

// Grava sem passar pelas regras (preparo do cenário).
export async function seed(env, entries) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const [path, data] of Object.entries(entries)) {
      await setDoc(doc(ctx.firestore(), path), data);
    }
  });
}

export const past = (seconds) => Timestamp.fromMillis(Date.now() - seconds * 1000);

export const RUNTIME_OPEN = {
  aiEnabled: false,
  conectaEnabled: true,
  conectaWritesEnabled: true,
};

// Cenário padrão do Conecta: runtime aberto, convite, moderador e membros.
export function baseScenario() {
  const member = (nick) => ({
    nickname: nick,
    inviteCode: 'turma1',
    declaredMinAge: 18,
    rulesVersion: '1',
    joinedAt: past(3600),
  });
  return {
    'appConfig/runtime': RUNTIME_OPEN,
    'invites/turma1': { ok: true },
    'moderators/mod': { ok: true },
    'memberships/ana': member('ana_ok'),
    'memberships/bob': member('bob_ok'),
    'memberships/mod': member('moderadora'),
    'profiles/ana': { nickname: 'ana_ok', joinedAt: past(3600) },
    'profiles/bob': { nickname: 'bob_ok', joinedAt: past(3600) },
    'profiles/mod': { nickname: 'moderadora', joinedAt: past(3600) },
  };
}

// Entrada no piloto: membership privada + perfil público (só o apelido) no mesmo lote.
// `ref` é a referência da membership; o uid é o último trecho do caminho.
export function enter(ref, data) {
  const fs = ref.firestore;
  const uid = ref.path.split('/').pop();
  const batch = writeBatch(fs);
  batch.set(ref, data);
  batch.set(doc(fs, `profiles/${uid}`), { nickname: data.nickname, joinedAt: serverTimestamp() });
  return batch.commit();
}

// Saída: apaga membership e perfil no mesmo lote.
export function leave(fs, uid) {
  const batch = writeBatch(fs);
  batch.delete(doc(fs, `memberships/${uid}`));
  batch.delete(doc(fs, `profiles/${uid}`));
  return batch.commit();
}
