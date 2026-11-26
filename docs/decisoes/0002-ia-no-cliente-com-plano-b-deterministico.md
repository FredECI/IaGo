# 0002. IA no cliente, com plano B determinístico

**Status:** aceita em 07/11/2026 (D2 e D5 aprovadas pelo Fred), com a condição de que a limitação seja fácil de desfazer. O spike de 10/11 (CP0) confirma a parte técnica. Detalhes em [`docs/specs/mvp-27-11.md`](../specs/mvp-27-11.md).

## Contexto

Direciona e importação por print ou PDF usam IA. A decisão é manter R$ 0, no plano Spark, sem Cloud Functions. Os fatos que restringem o desenho:

- A cota gratuita do Gemini é por projeto e pequena. Fontes não oficiais indicam 500 pedidos por dia no `gemini-3.5-flash-lite` e 20 no `gemini-3.8-flash`.
- O App Check é obrigatório no Firebase AI Logic desde 02/11/2026.
- Na camada gratuita, o conteúdo enviado pode ser usado para melhorar produtos e revisado por pessoas.
- Os modelos mudam com frequência, e um APK antigo continua nas mãos dos usuários.

## Decisão

1. **A chamada sai do cliente**, pelo Firebase AI Logic (`FirebaseAI.googleAI()`), com App Check: reCAPTCHA Enterprise na web e, se o spike aprovar, no Android.
2. **Portas no domínio, SDK só no adaptador.** `QuestionExtractor` e `StepProposer` ficam em `lib/domain/ai_ports.dart`, só com tipos do domínio. O `firebase_ai` aparece só em `lib/data/ai/gemini/`, onde o `AiGateway` concentra App Check, tempo limite e tradução de erros. Nenhuma tela importa `firebase_ai`.
3. **A IA nunca é o único caminho.** O Direciona tem um planejador por regras, e a importação tem colagem local. O plano B funciona offline e no modo demo.
4. **Saída sempre estruturada e validada.** Esquema JSON na chamada e função pura de validação no cliente. Nada é salvo sem revisão ou sem passar pelo validador.
5. **Sem conversa.** Não há campo de pergunta livre. O Direciona envia só números, sem nome, e-mail, uid ou enunciado.
6. **Configuração sem nova versão:** `appConfig/runtime` traz o modelo e os interruptores, editados no console.

## Alternativas descartadas

- **Cloud Function com a chave:** dá limite real por usuário, mas exige Blaze e cartão.
- **Chave do usuário:** inviável para o público.
- **Só regras, sem IA:** mais simples, mas o produto promete que a IA propõe. Fica como corte, avisando o grupo.
- **OCR no aparelho:** resolveria parte da privacidade, mas não há solução simples para web e Android sem depender de CDN.

## Consequências

- Com rede e cota, a experiência é boa; sem elas, continua funcionando, com outro rótulo.
- O limite por usuário é só suave, no aparelho. Um usuário mal-intencionado com o app autenticado pode gastar a cota do dia, o que degrada o serviço, mas não gera cobrança, porque não há faturamento.
- O site passa a carregar o script do reCAPTCHA em contas reais. A demo não depende dele.
- Migrar para Cloud Function custaria de 8 a 12 h, já que as telas só conhecem as portas.

## Como desfazer

- **Trocar o modelo:** `appConfig/runtime.aiModel` no console, sem nova versão. Leva 2 min.
- **Plano pago, em que os dados não são usados para melhorar produtos:** vincular faturamento (1 h de console e cerca de US$ 3 a 5 por mês no uso estimado). Depende de cartão e do OK do Fred (D2).
- **Vertex AI (Agent Platform):** uma linha no adaptador e plano Blaze, de 1 a 2 h. Não muda a regra de idade: os termos do Google Cloud têm a mesma restrição (veja o ADR 0004).
- **Outro provedor:** um adaptador novo das duas portas, mais um servidor para guardar a chave, porque o Firebase AI Logic só aceita modelos Gemini. São de 6 a 10 h no adaptador e de 8 a 12 h na função, no Blaze. Domínio e telas não mudam.
- **IA no APK:** P2b no console, a chave `FIREBASE_APPCHECK_ANDROID_SITE_KEY` no secret e um novo build. Sem a chave, a IA fica indisponível no APK.
- **Menores de 18:** veja a saída do [ADR 0004](0004-piloto-fechado-para-maiores-de-18.md#saída-como-abrir-para-menores-no-futuro).
