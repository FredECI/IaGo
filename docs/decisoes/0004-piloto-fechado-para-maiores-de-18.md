# 0004. Piloto fechado para maiores de 18 anos

**Status:** aceita em 07/11/2026 (D1 aprovada pelo Fred), com a condição de que seja fácil de desfazer, porque uma versão mais avançada vai precisar atender menores de 18 anos. **Não é parecer jurídico:** a leitura legal deste ADR foi feita por ferramenta, sem conferência humana. Detalhes na [spec](../specs/mvp-27-11.md). Esta decisão muda o público do produto.

## Contexto

O público do IaGo são vestibulandos, e muitos têm menos de 18 anos. O MVP traz dois elementos que mudam o cenário:

- **IA:** os [termos da Gemini API](https://aistudio.google.com/docs/terms) exigem 18 anos ou mais e proíbem usar a API em serviço direcionado a menores de 18 ou de provável acesso por eles. A regra vale para os serviços gratuitos e pagos.
- **Conecta:** a [Lei 15.211/2025](https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2025/lei/l15211.htm) (ECA Digital), em vigor desde 17/03/2026, alcança serviços de acesso provável por crianças e adolescentes. Em rede social, ela exige vínculo com responsável para contas de até 16 anos. Também pede canal de notificação, remoção e contestação. Não há exceção para projeto acadêmico. A ANPD modula as obrigações por natureza, porte e risco, mas a autodeclaração do fornecedor não resolve por si só.

## Decisão

1. **Contas reais são para quem tem a idade mínima dos termos** (hoje, 18 anos), com declaração no cadastro e nos termos. O modo demo continua aberto, sem coleta de dados.
2. **IA e Conecta só para membros do piloto**: e-mail verificado, código de convite, declaração da idade mínima da política e aceite das regras da comunidade.
3. **Recrutamento só de adultos.** O convite reduz a facilidade de acesso, um dos critérios legais de acesso provável.
4. **Proteções por padrão:** sem mensagem direta, sem imagem, sem link clicável e com apelido em vez de nome.
5. **Tudo isso mora na política de acesso** (`AccessPolicy` e as funções nomeadas das regras), nunca espalhado por telas. Veja o [ADR 0005](0005-limitacoes-reversiveis.md).

## Alternativas descartadas

- **Aberto a menores, sem IA para eles:** exige checagem de idade confiável, vínculo com responsável e moderação mais forte. Não cabe em 3 semanas. Além disso, com o Gemini no app, abrir as contas a menores fere os termos do Google, mesmo com a IA só para adultos (veja a saída).
- **Aberto a todos, só com aviso de idade:** não atende aos termos do Gemini, e a ANPD diz que aviso e declaração não bastam por si sós.
- **Sem IA e sem Conecta:** seria o caminho de menor risco, mas tira as funcionalidades que o grupo decidiu entregar.

## Consequências

- O piloto perde parte do público natural. Quem tem 16 ou 17 anos, comum entre vestibulandos, fica de fora enquanto essa regra valer.
- A métrica H4 (indicação) fica distorcida, porque o grupo recruta as pessoas. A spec prevê ajuste.
- **Isto reduz o risco, mas não o elimina.** A declaração é autodeclaração, e o app continua público na internet. Não é parecer jurídico. A spec pede consulta ao professor ou à UFRJ (D7).
- Abrir para menores no futuro depende de fora do código: termos do provedor de IA e lei. A seção seguinte mostra o caminho e o custo.

## Saída: como abrir para menores no futuro

Pesquisa de 07/11/2026, em fonte primária, lida por uma ferramenta que resume páginas, sem conferência humana. Confira o trecho original antes de citar em documento formal. **Não é parecer jurídico.** Só a costura no código é fácil de desfazer; abrir para menores continua caro e depende de terceiros e da lei.

### Lido em fonte primária, sem conferência humana

**IA**

1. **Gemini Developer API:** exige 18 anos ou mais e proíbe usar os serviços em site, app ou serviço "directed towards or is likely to be accessed by individuals under the age of 18". Não há exceção para educação nem para o plano pago. Vigência: 23/03/2026. [Gemini API Additional Terms](https://aistudio.google.com/docs/terms).
2. **Vertex AI (Agent Platform):** a seção 20(d), "Age Restrictions", dos termos de IA generativa do Google Cloud tem a mesma restrição, sem exceção no texto. **Trocar a Developer API pelo Vertex AI não resolve a idade.** [Google Cloud Service Specific Terms](https://cloud.google.com/terms/service-terms).
3. **Firebase AI Logic** só aceita modelos Gemini, pela Gemini Developer API ou pela Agent Platform Gemini API (antes Vertex AI). Outro provedor exige sair do AI Logic e, para não expor a chave no cliente, um servidor. [Firebase AI Logic: modelos](https://firebase.google.com/docs/ai-logic/models).
4. **OpenAI:** o guia oficial para menores admite organizações que atendem menores de 18 pela API, com condições: não processar dados pessoais de menores de 13 sem ativar retenção zero na API; manter o conteúdo adequado à idade, com filtros; usar aferição de idade quando cabível; cumprir as leis de proteção e privacidade (cita a COPPA); e aceitar auditoria, com advertência e suspensão em caso de descumprimento. [Under 18 API Guidance](https://developers.openai.com/api/docs/guides/safety-checks/under-18-api-guidance).
5. **Anthropic:** a política de uso diz que produtos para menores devem seguir diretrizes adicionais e todas as leis aplicáveis. As diretrizes (16/03/2026) listam salvaguardas, como aferição de idade, moderação e monitoramento, e obrigam a cumprir as leis de proteção e privacidade e a avisar que o usuário fala com uma IA. Também preveem auditoria e suspensão. [Usage Policy](https://www.anthropic.com/legal/aup), com vigência indicada em 12/11/2026, e [diretrizes para organizações que atendem menores](https://support.claude.com/en/articles/9307344).
6. **Gemma** (modelo aberto do Google, para rodar no aparelho): os termos não fixam idade mínima numérica, só "idade suficiente para consentir", e exigem repassar as restrições de uso. Última modificação: 01/04/2026. [Gemma Terms of Use](https://ai.google.dev/gemma/terms).

**Conecta e contas** ([Lei 15.211/2025](https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2025/lei/l15211.htm), em vigor desde 17/03/2026)

7. **Art. 7º:** configuração mais protetiva disponível, por padrão, em privacidade e dados pessoais.
8. **Art. 10:** serviços direcionados a crianças e adolescentes, ou de acesso provável por eles, devem proporcionar experiências adequadas à idade.
9. **Art. 17:** supervisão parental, com ferramentas fáceis de usar, informação aos pais, aviso visível quando a supervisão estiver ativa e meios de limitar e monitorar o tempo de uso.
10. **Art. 24, no capítulo "Das redes sociais":** contas de até 16 anos vinculadas à conta de um responsável. Com indícios de que a conta é de alguém abaixo da idade mínima, suspender e abrir um procedimento de contestação. Sem conta do responsável, é proibido baixar a proteção abaixo do padrão.
11. **Art. 9º:** aferição de idade confiável a cada acesso, sem autodeclaração, **mas só para conteúdo impróprio para menores**, como pornografia.
12. **Arts. 22 e 26:** proibido usar perfilamento para direcionar publicidade a crianças e adolescentes. O IaGo não tem publicidade.
13. **ANPD:** o Decreto 12.880/2026 regulamenta a lei. As orientações sobre aferição de idade são preliminares (março de 2026); uma proposta de guia definitivo passou por tomada de subsídios e está em consolidação. A fiscalização começa em janeiro de 2027, mas a ANPD pode agir antes, com base em denúncia ou em risco alto. [Página do ECA Digital na ANPD](https://www.gov.br/anpd/pt-br/assuntos/eca-digital).
14. **LGPD, art. 14:** dado de criança exige consentimento específico de um dos pais; o de adolescente exige observar o melhor interesse (já na spec, com o Enunciado CD/ANPD 1/2023).

### Não confirmado

- **Termos gerais da OpenAI** ([Services Agreement](https://openai.com/policies/services-agreement/)): a página recusou a ferramenta (erro 403). Não sei se trazem regra de idade além do guia.
- **IA só para contas adultas num app aberto a menores:** há uma pergunta pública no [fórum de desenvolvedores do Google](https://discuss.ai.google.dev/t/age-restrictions-in-gemini-api-terms-general-audience-app-rated-3-with-an-adult-only-ai-feature/179916) sobre um caso parecido; não li a íntegra nem achei resposta oficial. A leitura conservadora, adotada aqui, é que não atende, porque a regra fala do serviço como um todo.
- **Gemini no Google Workspace for Education:** fontes secundárias dizem que estudantes menores usam o app do próprio Google. Não é uma API para terceiros, então não é caminho para o IaGo.
- **Se a autodeclaração basta para um fórum educativo:** as orientações da ANPD são preliminares, e não li a íntegra.
- **Se o Conecta conta como rede social** (art. 2º, III): depende de interpretação. Se contar, o art. 24 se aplica.
- **Texto do Decreto 12.880/2026:** não li.
- **Preço e camada gratuita das APIs da OpenAI e da Anthropic:** não verificados.
- **Modelo aberto no aparelho:** viabilidade técnica não avaliada (tamanho do modelo, desempenho em celular barato e na web, download sem CDN).

### Custo estimado de desfazer o limite de 18 anos

Estimativas minhas, em horas equivalentes de um desenvolvedor.

| Parte | O que muda | Custo | Depende de fora |
| --- | --- | --- | --- |
| IA | Novo adaptador das portas `QuestionExtractor` e `StepProposer` para um provedor que aceite menores; função no servidor para guardar a chave; salvaguardas do provedor (filtros, aferição de idade quando cabível, retenção zero para menores de 13 na OpenAI); termos novos e reaceite. Alternativa: modelo aberto no aparelho, depois de um spike | De 25 a 40 h, mais o custo da API e o plano Blaze | Termos do provedor, dinheiro (cartão e Blaze), D7 |
| Contas e Conecta | **Acrescentar** fluxos: aferição de idade, vínculo da conta de quem tem até 16 anos à de um responsável, supervisão parental e limite de tempo de uso; nova versão dos termos. O Conecta em si não muda | De 30 a 50 h, mais um serviço de aferição de idade (custo não pesquisado) | Lei (ECA Digital, LGPD e orientações definitivas da ANPD), D7, moderação reforçada |
| O que já serve | Política de acesso, proteções do Conecta (apelido, sem mensagem direta, sem imagem, sem link clicável), denúncia, fila, banimento, exclusão em cascata e termos versionados | Nenhum | — |

**Ordem segura para abrir:** primeiro trocar ou desligar a IA do Google (`canUseAi` já desliga sozinha se a idade das contas cair abaixo de 18), depois os fluxos de responsável e de aferição, depois os termos novos, e só então baixar `termsMinAge` no código e nas regras.

## Como desfazer

Resumo da saída acima: a política de acesso concentra a regra, e baixar a idade é uma mudança de código pequena e deliberada (`AppInfo.termsMinAge`, `termsMinAge()` nas regras e termos novos). O custo de verdade está em atender as condições de fora: termos do provedor de IA e lei. Para o convite, basta `inviteRequired=false` no console, decidido junto com a D7.
