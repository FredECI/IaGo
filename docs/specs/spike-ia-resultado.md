# Resultado do spike F1 (IA na web, 10/11/2026)

Branch `feat/mvp-spike-ia` (não mesclada). Sem segredos neste arquivo: o token de depuração do App Check não foi impresso nem gravado em lugar nenhum (o log só registra o tamanho do token, 930 caracteres).

## Recomendação para o CP0

- **Seguir com a F5b: sim**, com `gemini-3.5-flash-lite` como modelo padrão (D5 confirmada pela qualidade e pela cota).
- **`gemini-3.8-flash` não serve como padrão, nem como reserva confiável hoje:** 0 chamadas bem-sucedidas em 7 tentativas registradas, mais as da execução perdida (veja abaixo). Não consegui provar sucesso nesse modelo; o critério "pelo menos 1 chamada por modelo" ficou cumprido só para o flash-lite.
- Riscos a levar para a spec: latência com cauda longa, erros 500/503 "alta demanda" e `429` com cota diária; mensagens específicas na tradução de erros da F5b.

## Como foi medido

Build web de `lib/spike/main.dart` (release, `--no-web-resources-cdn`), servido em `http://127.0.0.1`, aberto no Chrome headless por `tool/spike_ia/run_spike.js` (só `www.gstatic.com`, `googleapis.com` e `www.google.com` liberados). Projeto real `iago-beta`, `FirebaseAI.googleAI()`, App Check com `WebDebugProvider` (token de depuração), temperatura 0, `responseSchema` igual ao da spec (C.1), instrução de sistema da spec. A resposta passa por `parseExtraction` (contrato real). A exigência do App Check no AI Logic estava **ligada ("Básico: aplicado")** em todas as execuções (o Fred ligou antes da primeira chamada).

Amostras (conteúdo inventado, `tool/spike_ia/amostras/`, geradas por `make_samples.js`):

| Amostra | Conteúdo esperado |
| --- | --- |
| `print1-objetiva.png` | 1 objetiva, 5 alternativas |
| `print2-mista.png` | 1 objetiva (4 alt., letras "A)"), 1 discursiva (a, b); linha "Gabarito: 1-C, 2-B" e frase de injeção de prompt no rodapé |
| `print3-figura-dados.png` | 1 objetiva, 5 alt., gráfico de barras (figura) e cabeçalho com nome, e-mail e CPF fictícios |
| `prova.pdf` | 4 questões em 2 páginas (3 objetivas, 1 discursiva, 1 com figura) |

## Resultados, `gemini-3.5-flash-lite` (2 rodadas, 8 chamadas, todas com sucesso)

| Amostra | Rodada | Tempo | Questões (obtido/esperado) | Tipos | Alternativas | Figura | Dado pessoal | Contrato | Tokens (entrada/saída) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| print1 | 1 | 26,1 s | 1/1 | ok | ok (5) | ok | ok | válido | 1267/257 |
| print2 | 1 | 62,3 s | 2/2 | ok | ok (4) | ok | ok | válido | 1259/347 |
| print3 | 1 | 4,4 s | 1/1 | ok | ok (5) | ok (true) | ok (true) | válido | 1274/190 |
| prova.pdf | 1 | 18,2 s | 4/4 | ok | ok (5,4,5) | ok | ok | válido | 1231/724 |
| print1 | 2 | 4,0 s | 1/1 | ok | ok | ok | ok | válido | 1267/257 |
| print2 | 2 | 8,0 s | 2/2 | ok | ok | ok | ok | válido | 1259/360 |
| print3 | 2 | 2,2 s | 1/1 | ok | ok | ok | ok | válido | 1274/186 |
| prova.pdf | 2 | 9,4 s | 4/4 | ok | ok | ok | ok | válido | 1231/728 |

- 8 de 8 com saída válida sem `salvageQuestions` (nada parcial ou descartado). Nenhum aviso de item. O aviso de lote só apareceu em `print3` ("dados pessoais"), como esperado.
- Sem vazamento: o gabarito, a frase de injeção e o nome, e-mail e CPF do cabeçalho não entraram nos textos extraídos (checagem por busca de texto).
- Tokens por chamada: cerca de 1.250 de entrada (imagem e PDF custam o mesmo) e 190 a 730 de saída, sem tokens de raciocínio relatados. Abaixo da estimativa da spec para uma página (1.500 e 1.750), então o custo estimado de US$ 3 a 5 por mês fica folgado.
- Latência: as duas chamadas lentas (26 s e 62 s) foram a primeira de cada amostra (print1 e print2) na 1ª rodada. Com a chamada repetida, 2 a 9 s para prints e 9 s para o PDF. Para a F5b: spinner com texto, timeout de pelo menos 90 s e mensagem para "demorou".
- Não verifiquei a fidelidade letra a letra do texto copiado (só contagem, tipos, alternativas, figura, dado pessoal e vazamentos). Nas amostras vistas, o texto veio igual.

## Resultados, `gemini-3.8-flash` (nenhum sucesso)

| Execução | Amostra | Resultado |
| --- | --- | --- |
| 1 | print1 | timeout de 120 s no cliente |
| 1 | print2 | timeout de 120 s |
| 1 | print3 | 500 depois de 52 s: "This model is currently experiencing high demand" |
| 1 | prova.pdf | timeout de 120 s |
| 1 | print2 | timeout de 120 s |
| 3 | print1 | 503 `UNAVAILABLE` "Deadline expired before operation could complete" depois de 179 s (timeout de 240 s) |
| 3 | print3 | **429** em 1 s: `generate_content_free_tier_requests`, limite 20 por dia, `gemini-3.8-flash`; "retry in 13h" |

- A cota diária de 20 do flash acabou. Parte dela foi gasta por uma 1ª execução cujos registros se perderam (o script gravava só no fim e a execução foi interrompida pelo `timeout` do shell); ela chamou os mesmos modelos e talvez tenha gasto algumas das 20. Tentativas com 500, 503 e timeout parecem contar na cota diária. Não insisti depois do 429.
- Ou seja, o flash sofre "alta demanda" e não deve ser tratado como alternativa até repetir o teste em outro dia (a cota zera em cerca de 13 h; sugiro repetir com 2 a 3 chamadas).

## Infraestrutura

- **App Check na web:** `activate(providerWeb: WebDebugProvider(debugToken: ...))` funciona. O token foi obtido (`getToken`) em 0,8 a 1,4 s e trocado em `content-firebaseappcheck.googleapis.com/...exchangeDebugToken` (200). Com a exigência do AI Logic ligada ("Básico: aplicado"), as chamadas do flash-lite passaram. Isso prova só o caminho de **depuração** (token cadastrado). O caminho com `ReCaptchaEnterpriseProvider` real (chave de site) não foi provado, porque em localhost headless não há como cumprir o desafio do reCAPTCHA: precisa de teste no site publicado (`iago-beta.web.app`), como em CA-T14. A chave de site foi carregada (`siteKeyPresent=true`) e o script do reCAPTCHA (`recaptcha/api.js`, `anchor`) carregou com 200.
- **CORS:** sem erros. `firebasevertexai.googleapis.com/...generateContent` respondeu direto do navegador.
- **Hosts a liberar** (CSP/proxy, se houver): `www.gstatic.com` (SDK `firebasejs/13.1.0`, reCAPTCHA), `www.google.com` (reCAPTCHA), `firebaseappcheck.googleapis.com` (via `content-firebaseappcheck.googleapis.com`) e `firebasevertexai.googleapis.com`.
- **Login não é necessário:** as chamadas foram feitas sem usuário autenticado e passaram. O limite de 5 pedidos por minuto por usuário não foi testado (as chamadas ficaram espaçadas em 14 s). Para o limite valer por usuário, a F5b deve chamar com o usuário logado.
- **Tamanho do bundle web:** o SDK JS do Firebase vem do CDN gstatic (não entra no bundle). O `main.dart.js` do spike (só Firebase Core, App Check, AI e o contrato) tem 1,17 MB (cerca de 380 KB em gzip). Não medi a diferença exata sobre o app atual.
- **Faturamento:** nenhuma tela ou erro pediu o Blaze.
- **Android/APK:** fora do escopo deste spike (sem aparelho e sem workflow de APK nesta branch). D10 segue aberta.

## Mudanças em `pubspec.yaml` (a levar para a F5b)

- `firebase_ai: ^5.1.0` (resolveu 5.1.0) e `firebase_app_check: ^0.5.1` (resolveu 0.5.1, com `firebase_app_check_platform_interface` 0.5.1+3 e `firebase_app_check_web` 0.3.1+3). **Levar.** Compatíveis com `firebase_core` 5.1.0, `firebase_auth` 7.0.1 e `cloud_firestore` 7.1.0, que não mudaram no `pubspec.lock`.
- O `pubspec.lock` só ganhou esses pacotes e `web_socket` 1.0.1 e `web_socket_channel` 3.0.3 (dependências do `firebase_ai`).
- `assets: tool/spike_ia/amostras/` é só do spike: **não levar**.
- `file_selector` (previsto na F5b) não foi tocado.

## O que levar para a F5b (aprendizados)

1. Esquema, instrução de sistema e `GenerationConfig(temperature: 0, responseMimeType: 'application/json', responseSchema: ...)` da spec funcionam como estão, com `InlineDataPart('image/png' ou 'application/pdf', bytes)`. Modelo: `gemini-3.5-flash-lite`.
2. Ativação: `WebDebugProvider(debugToken: ...)` quando o define do token não está vazio; senão `ReCaptchaEnterpriseProvider(siteKey)`. Importar `firebase_app_check` e `firebase_ai` só em `lib/data/ai/gemini/` e no bootstrap (CA-R2, arquitetura).
3. Traduzir erros: o 429 chega como exceção do SDK com texto de cota (`quotaExhausted`); 500 e 503 vêm com "alta demanda" e `UNAVAILABLE` (mapear para um aviso de "tente de novo"); o tipo do erro fica minificado em release, então classificar pelo texto ou pelo tipo do pacote, não por `runtimeType.toString()`.
4. Timeout do cliente de 90 a 120 s no flash-lite (houve 62 s) e botão cancelar.
5. Tratar `containsPersonalData` (funcionou) e confiar no contrato do domínio para tipos e alternativas.
6. Lembrar do cuidado com a cota diária do flash (20) em testes automáticos: use sempre o flash-lite.

## Ressalvas

- A 1ª execução completa foi perdida (script gravava só no fim). Ela repetiu as 13 chamadas do plano e consumiu cota (flash-lite: até 8 de 500; flash: até 5 de 20). Os dados acima vêm da 2ª execução (flash-lite e flash) e da 3ª (só flash).
- Poucas amostras (4) e conteúdo inventado e limpo; não cobre fotos tortas, escaneados ruins, provas longas (30 questões) nem o limite de 10 páginas.
- Arquivos do spike: `lib/spike/main.dart`, `tool/spike_ia/{make_samples.js,run_spike.js}`, `tool/spike_ia/amostras/`, `tool/spike_ia/resultados/` (JSON das chamadas, sem token; o `rawHead` traz o texto extraído das amostras inventadas).
