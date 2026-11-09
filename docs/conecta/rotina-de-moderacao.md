# Rotina de moderação do Conecta

Para o grupo de moderadores. Escrita em 08/11/2026, junto com as [regras da comunidade](regras-da-comunidade.md), que valem a versão `2026-11-08`.

> **Rascunho.** Esta rotina só vale em conta real depois da D6 (quem modera, prazo e e-mail) e do CA-C11 (pelo menos 2 moderadores com documento criado e e-mail ativo). Os itens entre `<...>` ainda não existem e precisam ser preenchidos antes.

## 1. Papéis e escala

- **Quem modera:** pessoas do grupo, com um documento `moderators/{uid}` criado **no console do Firestore**. Ninguém se torna moderador pelo app.
- **Mínimo:** 2 pessoas por semana, na escala: `<escala de moderadores>`.
- **Prazo:** revisar a fila **uma vez por dia**, com cada denúncia resolvida em **até 24 horas** depois de feita.
- **Contato:** `<e-mail do projeto>`, que deve estar ativo e ser lido por quem está na escala.
- **Quem responde pelo projeto:** `<responsável pelo projeto, a definir na D7>`.

**Se a escala falhar:** avise o grupo no mesmo dia. Se a fila passar de 24 horas, o Conecta deixa de ser aberto a novas contas até a escala voltar. Essa decisão é do responsável pelo projeto.

## 2. Antes de começar

- **Não decida sobre conteúdo de quem você conhece bem** (amigo, colega de aula ou parente). Passe o caso para outro moderador da escala.
- **Não copie, não baixe e não encaminhe** conteúdo sexual, de assédio ou de dado pessoal. Para decidir, basta ver o conteúdo no app. Se precisar registrar algo, registre os identificadores (veja a seção 5).
- A denúncia pode ter até 500 caracteres de detalhe. Leia o detalhe, mas não repasse o texto fora da moderação.

## 3. Como abrir a fila

No console do Firestore, na coleção `reports`:

1. Filtre `status` igual a `open`.
2. Ordene por `createdAt`, do mais antigo para o mais recente. É a ordem de quem está esperando há mais tempo.

Cada documento tem `targetType` (`post` ou `reply`), `targetId`, `postId`, `reason`, `details`, `reporterUid` e `createdAt`.

Para ver o conteúdo, abra `posts/{targetId}` ou `replies/{targetId}`. Como moderador, você lê posts e respostas mesmo sem ser membro.

**Várias denúncias sobre o mesmo conteúdo:** cada pessoa tem o seu documento. Decida o conteúdo uma vez e resolva **todas** as denúncias abertas dele juntas (seção 6).

## 4. Estados do conteúdo

| `status` | Quem vê | Quando |
| --- | --- | --- |
| `visible` | Membros, autor e moderação | Normal |
| `pending` | Só o autor e a moderação | Alguém denunciou. É automático, feito pelo app no mesmo passo da denúncia |
| `hidden` | Só o autor e a moderação | Você ocultou (seção 5) |

Não existe mais "pending" depois da sua decisão: ele vira `visible` (restaurar) ou `hidden` (ocultar).

## 5. As decisões

Escolha **uma** decisão por conteúdo. Ao decidir, sempre registre `moderatedAt` com a data e a hora.

### 5.1 Restaurar

- `status` do post ou da resposta volta para `visible`.
- Não é preciso motivo.
- Resolva as denúncias abertas dele (seção 6), com a decisão `restaurar`.

### 5.2 Ocultar com motivo

- `status` vai para `hidden`.
- **Motivo obrigatório** em `moderationReason`, em uma frase curta e neutra. O autor vê esse texto. Exemplo: "Contém ofensa a outro membro." Não escreva dados pessoais no motivo.
- Resolva as denúncias abertas dele, com a decisão `ocultar`.

### 5.3 Ocultar e banir

1. Oculte o conteúdo, como em 5.2.
2. Crie `bans/{uid}`, com o `uid` da pessoa autora, `at` (data e hora) e `reason` (o mesmo motivo).
3. Resolva as denúncias abertas dele, com a decisão `ocultar e banir`.

Efeito: a pessoa não publica, não responde, não marca "Ajudou" e não denuncia. Os posts dela continuam escondidos enquanto você não decidir de outro jeito. **Não esqueça de ocultar o conteúdo na mesma hora.**

### 5.4 Desfazer um banimento

Só depois de uma contestação aceita (seção 8). Apague o documento `bans/{uid}`. Se o conteúdo também estava oculto, restaure-o (5.1).

## 6. Fechar a denúncia

Ao decidir, feche **todas** as denúncias abertas do mesmo conteúdo:

1. Marque a denúncia como `status: resolved`, com `decision` (`restaurar`, `ocultar` ou `ocultar e banir`), `resolvedBy` (o seu `uid`) e `resolvedAt` (data e hora).
2. **Não apague.** A denúncia resolvida fica guardada até a pessoa que denunciou excluir a conta. Ela continua valendo como registro para uma contestação, e a mesma pessoa não consegue denunciar o mesmo conteúdo de novo.

**Por que guardar:** a denúncia resolvida é o registro da decisão. Sem ela, a contestação não tem o que conferir, e a pessoa poderia denunciar de novo para esconder o conteúdo outra vez.

## 7. Motivos de denúncia

| Motivo | O que fazer |
| --- | --- |
| `offensive` (ofensivo) | Ler o contexto. Se for ofensa ou discurso de ódio, ocultar com motivo. Se for só uma crítica dura, restaurar |
| `harassment` (assédio) | Ocultar com motivo. Se houver repetição de uma mesma pessoa contra outra, ocultar e banir |
| `personal_data` (dado pessoal) | Ocultar com motivo, sem repetir o dado no motivo. Se a pessoa do dado pedir remoção, trate pelo e-mail do projeto |
| `sexual_or_minor` (sexual ou envolvendo menor) | **Protocolo da seção 7.1.** Não espere a fila do dia |
| `copyright` (direitos autorais) | Ver seção 7.2 |
| `spam` (spam ou propaganda) | Ocultar com motivo. Se for propaganda de conta repetida, ocultar e banir |
| `other` (outro) | Ler o detalhe e decidir pelas regras. Na dúvida, ocultar com motivo e registrar o caso para o grupo |

### 7.1 Conteúdo sexual envolvendo menores, aliciamento ou ameaça

Este caso tem prioridade sobre a fila. Siga esta ordem:

1. **Ocultar na hora** (`status: hidden`, com motivo). Não apague o conteúdo: apagar antes de registrar perde a prova.
2. **Registrar** os identificadores: `targetType`, `targetId`, `postId`, o `uid` da pessoa autora, a data e a hora da denúncia e da sua ação. Não copie o conteúdo.
3. **Banir** a pessoa autora (`bans/{uid}`), se ela foi identificada.
4. **Avisar** o responsável pelo projeto, `<responsável pelo projeto>`, no mesmo dia.
5. **Comunicar às autoridades** pelo canal oficial: `<canal oficial de comunicação às autoridades, a confirmar com o professor>`. Essa comunicação é feita pelo responsável pelo projeto, com os registros do passo 2.
6. Só depois disso, apague o conteúdo, se o responsável pelo projeto autorizar.

Em risco imediato à vida de alguém, acione a emergência (190) antes de qualquer registro.

### 7.2 Direitos autorais

- Se a denúncia for de **cópia de questão de plataforma paga, livro ou site de questões**, oculte com motivo ("Possível cópia de material com direitos autorais") e avise o responsável pelo projeto.
- Se a denúncia for sobre uma **questão do acervo ENEM**, citada pelo `bankId`: a comunidade não remove o acervo. Passe o caso para `<e-mail do projeto>`, e o responsável pelo projeto decide a remoção fora do app. Enquanto isso, o post que cita a questão segue a regra normal (ocultar ou restaurar).
- Se o autor contestar, a análise segue a seção 8.

## 8. Contestação

A pessoa autora contesta pelo e-mail `<e-mail do projeto>`. Ao receber:

1. **Registre** a data de recebimento e o caso na fila.
2. **Confira** a decisão original: o conteúdo, o motivo gravado e as denúncias.
3. **Quem responde** deve ser um moderador que **não** tomou a decisão original, quando houver outro na escala.
4. **Decida:** manter ou desfazer a decisão (restaurar o conteúdo e, se for o caso, desfazer o banimento, seção 5.4).
5. **Responda por e-mail**, com a decisão e o motivo, em até `<prazo de resposta, a definir na D6>`.

A contestação é o único caminho de volta para quem foi escondido ou banido. A resposta não pode ser só "mantido", sem motivo.

## 9. Exclusão de conta durante uma denúncia

- Se quem denunciou excluir a conta, a denúncia **aberta continua** até você resolvê-la, e a decisão vale do mesmo jeito.
- Se quem escreveu o conteúdo excluir a conta, os posts e as respostas dela são apagados pelo app. Se ainda houver denúncias abertas sobre esses conteúdos, feche-as com `decision: conteúdo excluído pelo autor`, sem apagar (seção 6). O app não define esse caso; a regra é uma sugestão a confirmar pelo grupo.
- O banimento fica registrado mesmo depois da exclusão da conta.

## 10. O que guardar

- **Denúncias abertas:** ficam na fila até a decisão. **Denúncias resolvidas:** ficam guardadas, com `status: resolved`, `decision`, `resolvedBy` e `resolvedAt`, até a pessoa que denunciou excluir a conta. Nesse caso, o próprio app as apaga (decisão do coordenador, 08/11).
- **Motivos e registros do passo 2 da seção 7.1:** guarde o mínimo necessário, somente com o responsável pelo projeto.
- **Contestações:** ficam na caixa de e-mail `<e-mail do projeto>`.

## 11. Checklist diário

- [ ] Abri a fila de `reports` com `status` igual a `open` e vi o que chegou desde ontem.
- [ ] Denúncias de conteúdo sexual envolvendo menor, aliciamento ou ameaça: tratei na hora (seção 7.1).
- [ ] Cada denúncia tem uma decisão, e o motivo de cada ocultação está preenchido.
- [ ] Denúncias do conteúdo decidido marcadas como `resolved`, todas, inclusive as duplicadas, e não apagadas.
- [ ] Banimentos com `bans/{uid}` criado e `at`, `reason` preenchidos.
- [ ] Contestações recebidas no e-mail do projeto respondidas ou com prazo marcado.
- [ ] Nada de conteúdo copiado para fora do app.

## 12. Pendências antes de ligar o Conecta

| Item | Onde é definido |
| --- | --- |
| Nomes dos moderadores e escala semanal | `<escala de moderadores>` (D6) |
| E-mail do projeto, ativo e lido | `<e-mail do projeto>` (P4) |
| Prazo de resposta à contestação | `<prazo de resposta>` (D6) |
| Responsável pelo projeto e termo de consentimento, se necessário | `<responsável pelo projeto>` (D7) |
| Canal oficial de comunicação às autoridades | `<canal oficial>`, a confirmar com o professor (D7) |
| Ajustar o app para apagar denúncias resolvidas só na exclusão de conta | Já decidido (seção 10); o C2 e o C5 seguem isso |
