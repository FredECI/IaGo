# 0005. Limitações reversíveis: política de acesso única e portas para IA e acervo

**Status:** aceita em 07/11/2026, como condição do Fred para aprovar D1 a D5. Detalhes em [Como desfazer as limitações](../specs/mvp-27-11.md#como-desfazer-as-limitações) e nos critérios CA-R1 a CA-R7 da spec.

## Contexto

O Fred aprovou as limitações do MVP com uma condição: elas precisam ser fáceis de desfazer no futuro. Uma versão mais avançada vai precisar atender menores de 18 anos e dar acesso a mais questões.

Sem servidor, cada limitação vira uma verificação no cliente e, quando envolve dados públicos, uma regra do Firestore. Se essas verificações ficarem espalhadas por telas e repositórios, desfazer uma limitação vira uma caça a literais, com risco de esquecer o lado do servidor ou o texto dos termos.

## Decisão

1. **Política de acesso única.** Idade mínima, convite exigido, IA ligada e Conecta ligado moram em `AccessPolicy` (`lib/domain/access_policy.dart`), alimentada por `appConfig/runtime`. Campo ausente ou de tipo errado vale o padrão seguro. As regras do Firestore espelham a política com funções nomeadas (`termsMinAge()`, `minAge()`, `meetsAgePolicy()`, `inviteOk()` e `conectaOpen()`).
2. **A idade só sobe pelo console.** A idade das contas é a dos termos aceitos (`AppInfo.termsMinAge`). O console pode subir a idade dos membros, mas baixar exige nova versão dos termos, com reaceite. Assim, ninguém fica num estado em que o app admite uma idade que os termos aceitos não preveem.
3. **Portas para o que depende de terceiros.** IA: `QuestionExtractor` e `StepProposer` no domínio, com o `firebase_ai` só no adaptador `lib/data/ai/gemini/`. Acervo: `BankCatalog`, assíncrono e paginável, com ids estáveis prefixados pela fonte e um adaptador por fonte no script.
4. **Dados chaveados por ids estáveis.** Avaliações usam o id da questão no catálogo, não o lugar onde o catálogo mora.
5. **Textos legais versionados.** Termos, aviso da IA e regras da comunidade têm versão gravada no aceite. Um teste amarra a versão dos termos, a idade e o provedor de IA.
6. **Limites com nome**, definidos uma vez cada, no código e nas regras.

## Alternativas descartadas

- **Verificações diretas nas telas** (por exemplo, comparar a idade com 18 em cada tela): mais rápido hoje, mas caro e arriscado de desfazer.
- **Firebase Remote Config para os interruptores:** é gratuito, mas as regras do Firestore não o leem. O servidor perderia o espelho da política.
- **Serviço de feature flags de terceiros:** custo e mais uma dependência, sem ganho para um piloto de cerca de 20 pessoas.
- **Implementar já provedores de IA e catálogos alternativos:** não cabe no prazo. A decisão é só deixar a costura pronta.

## Consequências

- Cerca de 8 h equivalentes a mais na fundação e no acervo (F3, F5a, F6, A1 e A3).
- Uma camada a mais de indireção, coberta por testes de política, de regra e de arquitetura (imports de `lib/domain` e de `firebase_ai`).
- Ligar e desligar IA, Conecta e convite vira configuração no console, sem nova versão. Subir a idade também.
- Baixar a idade continua exigindo nova versão do app e das regras, de propósito: os termos mudam e todos aceitam de novo.
- Desfazer o limite de 18 anos depende de fora do código, nos termos do provedor de IA e na lei. Veja a saída do [ADR 0004](0004-piloto-fechado-para-maiores-de-18.md#saída-como-abrir-para-menores-no-futuro).

## Como desfazer

Esta decisão é a própria costura. Remover a indireção seria trocar a `AccessPolicy` e as portas por chamadas diretas, sem migração de dados. Não há motivo previsto para isso.
