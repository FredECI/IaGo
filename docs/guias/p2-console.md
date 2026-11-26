# Guia P2: console do Firebase, Google Cloud e AI Studio

Para o Fred fazer sozinho, na ordem. Projeto: `iago-beta` (nº 958140378539), plano Spark. Escrito em 07/11/2026.

## Resumo

| Parte | Quando | Tempo | Para quê |
| --- | --- | --- | --- |
| **P2a** | Agora | cerca de 50 min | Destrava o spike de IA na web |
| **P2b** | Só se o spike seguir para o APK | cerca de 15 min | App Check no Android |
| **P2c** | Só antes da publicação de 26/11 | cerca de 20 min | Restringir as chaves de API |

**Pré-requisitos**

- Login, no navegador, na conta dona do `iago-beta` (a mesma do Firebase CLI desta máquina). Ela precisa ter 18 anos ou mais, porque os termos do Gemini exigem isso de quem os aceita.
- Nenhum cartão. Se qualquer tela pedir para "vincular faturamento" ou "atualizar para Blaze", **pare e não aceite**: volte e avise o Claude.
- Terminal aberto em `C:\IaGo`.

**O beta publicado não é afetado.** O site e o APK não enviam token do App Check, e este guia só liga a exigência do App Check para o **Firebase AI Logic**, que o beta não usa. **Nunca** ative a exigência para Firestore, Authentication nem Storage: isso derrubaria o beta.

**Regras de segredo**

- O **token de depuração** do App Check é segredo. Gere você mesmo, grave só no arquivo local `env/appcheck-debug.json` e nunca cole no chat, no GitHub nem no secret.
- As **chaves de site do reCAPTCHA** são públicas, mas também ficam só em `env/firebase.json` e no secret `FIREBASE_ENV_JSON`.
- Ao copiar valores do console, não cole nada disso na conversa com o Claude. Veja a lista abaixo.

## O que mandar de volta ao Claude (sem segredos)

Copie e preencha:

```
P2a feito: sim/não (se não, em qual passo parou e a mensagem da tela)
Cotas no AI Studio (por projeto iago-beta):
  gemini-3.5-flash-lite: RPM = __, TPM = __, RPD = __
  gemini-3.8-flash:      RPM = __, TPM = __, RPD = __
Limite por usuário do AI Logic: 5 por minuto aplicado: sim/não/pendente
App Check: AI Logic = Enforced; Firestore/Auth = Unenforced: sim/não
Beta conferido (https://iago-beta.web.app abre e a demo entra): sim/não
Secret FIREBASE_ENV_JSON atualizado: sim/não
env/firebase.json tem FIREBASE_APPCHECK_WEB_SITE_KEY: sim/não
env/appcheck-debug.json criado: sim/não
```

Não mande: chaves, tokens, o conteúdo de `env/*.json` nem capturas de tela que mostrem esses valores.

---

## P2a: agora (cerca de 50 min)

### Passo 1: ativar o Firebase AI Logic com a Gemini Developer API (5 min)

1. Abra https://console.firebase.google.com/project/iago-beta/ailogic
2. Clique em **Get started**.
3. Quando perguntar o provedor, escolha **Gemini Developer API** (a opção gratuita). **Não** escolha a "Agent Platform" (antes Vertex AI), que exige faturamento.
4. Se pedir para registrar um app, escolha o app **Web** já existente. Continue até o fim.
5. O assistente liga sozinho a exigência do App Check **para o AI Logic**. É o esperado e é o que queremos.

**Conferir:** a página do AI Logic abre sem pedir faturamento, e o provedor mostrado é "Gemini Developer API". Se aparecer o botão "Upgrade" ou um pedido de cartão, pare.

Fonte: https://firebase.google.com/docs/ai-logic/get-started

### Passo 2: conferir as cotas no AI Studio (5 min)

1. Abra https://aistudio.google.com/rate-limit
2. No seletor de projeto, escolha `iago-beta`. Se ele não aparecer, vá em https://aistudio.google.com/projects e importe o projeto `iago-beta` (o botão exato para importar **não foi confirmado**; procure "Import projects"). Depois volte à página de limites.
3. Procure as linhas `gemini-3.5-flash-lite` e `gemini-3.8-flash` e anote, para cada uma, **RPM** (pedidos por minuto), **TPM** (tokens por minuto) e **RPD** (pedidos por dia).

**Conferir:** você tem 6 números. A spec supõe, por fonte não oficial, 500 RPD no flash-lite e 20 RPD no flash. Se o RPD do `gemini-3.5-flash-lite` for **menor que 100**, avise o Claude antes de seguir (a IA para 20 pessoas pode não caber).

Se o projeto não aparecer no AI Studio ou os modelos não estiverem na lista, anote isso: não invente números.

Fontes: https://aistudio.google.com/docs/rate-limits e https://aistudio.google.com/docs/pricing

### Passo 3: criar a chave reCAPTCHA Enterprise para web (7 min)

1. Abra https://console.cloud.google.com/security/recaptcha?project=iago-beta (a página aparece como "Fraud Defense"). Confirme que o projeto no topo é `iago-beta`.
2. Se pedir, clique em **Enable** na API **reCAPTCHA Enterprise**.
3. Clique em criar chave (**Create key**). Preencha:
   - Nome de exibição: `iago-web`
   - Tipo de plataforma: **Web**
   - Domínios: `iago-beta.web.app` e `iago-beta.firebaseapp.com`
   - **Não** adicione `localhost` (qualquer pessoa rodaria o app local com a sua chave).
   - Deixe **desmarcada** a opção "Use checkbox challenge" (a chave fica por pontuação, sem desafio visível).
4. Salve e copie o **ID da chave** (texto de cerca de 40 caracteres).

**Conferir:** a chave aparece na lista com tipo "Web" e os dois domínios. Guarde o ID para o passo 8.

Fonte: https://firebase.google.com/docs/app-check/web/recaptcha-enterprise-provider

### Passo 4: registrar o app web no App Check e conferir a exigência (8 min)

1. Abra https://console.firebase.google.com/project/iago-beta/appcheck
2. Aba **Apps**: no app **Web**, clique para registrar e escolha o provedor **reCAPTCHA Enterprise**. Cole o ID da chave do passo 3.
3. TTL do token: **24 horas** (a spec, risco R6, pede isso para poupar a cota grátis de 10 mil avaliações por mês do reCAPTCHA; acima dela, a IA para até o mês seguinte). Limite de pontuação: deixe **0,5** (padrão). Clique em **Save**.
4. Aba **APIs**: confira as linhas.
   - **Firebase AI Logic**: deve estar **Enforced**.
   - **Cloud Firestore**, **Authentication** e **Cloud Storage**: devem estar **Unenforced**. Se alguma estiver diferente, **não clique em nada** e avise o Claude.
5. Se o AI Logic estiver "Unenforced": clique na linha, depois em **Set up**; em "Baseline protection" escolha **Enforced** e **Continue**; em "Replay protection" escolha **Disabled** e **Continue**; confirme.

**Conferir:** Apps mostra o app Web com "reCAPTCHA Enterprise". Em APIs, só o AI Logic está Enforced. Abra https://iago-beta.web.app, toque em "Entrar como Pedro (demonstração)" e veja o Painel: o beta segue normal.

Fonte: https://firebase.google.com/docs/ai-logic/app-check

### Passo 5: token de depuração do App Check, para testar em localhost (7 min)

Em localhost não há reCAPTCHA (o domínio não está na chave), então o teste local usa um token de depuração. Gere o seu e mantenha-o em segredo.

1. No PowerShell, gere um UUID e **copie sem colar em chat**:
   ```powershell
   [guid]::NewGuid().ToString()
   ```
2. Abra https://console.firebase.google.com/project/iago-beta/appcheck, aba **Apps**. No app **Web**, abra o menu de três pontos e escolha **Manage debug tokens**.
3. Adicione um token com o nome `fred-localhost` e cole o UUID. Se a tela só **gerar** o token (sem aceitar o seu), use o que ela gerar. O texto exato dos botões **não foi confirmado**; siga as instruções da tela.
4. Grave o valor em um arquivo **separado**, fora do git (a regra `/env/*.json` do `.gitignore` já o ignora):
   ```powershell
   notepad C:\IaGo\env\appcheck-debug.json
   ```
   Conteúdo:
   ```json
   {
     "FIREBASE_APPCHECK_DEBUG_TOKEN": "COLE-O-UUID-AQUI"
   }
   ```
   Por que um arquivo à parte: o secret `FIREBASE_ENV_JSON` é copiado para o build do site público, e um token de depuração ali ficaria exposto a todo mundo. O Claude vai rodar o app local com os dois arquivos: `--dart-define-from-file=env/firebase.json --dart-define-from-file=env/appcheck-debug.json`.

**Conferir:** o token aparece na lista de depuração do app Web (só o nome e a data; o valor fica oculto). No PowerShell, `git status` **não** deve listar `env/appcheck-debug.json`.

Se o token vazar: volte em **Manage debug tokens** e apague-o.

Fonte: https://firebase.google.com/docs/app-check/web/debug-provider

### Passo 6: criar `appConfig/runtime` (5 min)

1. Abra https://console.firebase.google.com/project/iago-beta/firestore/databases/-default-/data
2. Clique em **Start collection**. ID da coleção: `appConfig`. ID do documento: `runtime` (digite, não use o automático).
3. Campos, com estes tipos e valores:

   | Campo | Tipo | Valor |
   | --- | --- | --- |
   | `aiEnabled` | boolean | `false` |
   | `aiModel` | string | `gemini-3.5-flash-lite` |
   | `aiDailyPerUser` | number | `12` |
   | `conectaEnabled` | boolean | `false` |
   | `conectaWritesEnabled` | boolean | `false` |

4. Clique em **Save**.

**Conferir:** o documento `appConfig/runtime` aparece com os 5 campos e os tipos certos (boolean e number, não string).

Sobre `aiEnabled`: começa em `false` (seguro). Se o spike precisar da IA ligada de verdade, o Claude vai pedir; aí você edita o campo no console para `true`, testa e **volta para `false`** no fim. Pelas regras atuais do Firestore, o beta não lê esse documento, então ele não muda nada para o site e o APK publicados. As regras novas (tarefa F3) vão permitir só leitura por usuário autenticado e nenhuma escrita pelo app; o Claude confere isso nos testes de regras antes de pedir para ligar `aiEnabled`.

### Passo 7: baixar o limite por usuário do AI Logic para 5 por minuto (7 min)

1. Abra https://console.cloud.google.com/apis/api/firebasevertexai.googleapis.com/quotas?project=iago-beta (a API do Firebase AI Logic). Se a página não abrir, abra https://console.cloud.google.com/apis/library?project=iago-beta, procure "Firebase AI Logic API" e clique em **Manage**.
2. Aba **Quotas & System Limits**. Filtre por "Generate content requests".
3. Procure a linha da cota **por usuário, por minuto** (padrão: 100). Use o filtro, não cole texto de exemplo; a linha "(default)" não vale para o AI Logic.
4. Marque a caixa da linha, abra o menu da linha e clique em **Edit quota**.
5. Em **New value**, digite `5`. Clique em **Done** e depois em **Submit request**.
6. Se houver mais de uma linha dessa cota (uma por região), repita para cada uma.

**Conferir:** a coluna do limite mostra `5` (pode levar alguns minutos) ou o pedido aparece como aprovado. Se o pedido ficar "pendente de análise", anote isso; a IA segue funcionando, só com o limite maior.

Requer permissão `serviceusage.quotas.update`, que o Owner já tem. O limite é o mesmo para todos os usuários do projeto, não individual. O menu exato e a possibilidade de baixar abaixo do padrão **não foram confirmados em tela**.

Fonte: https://firebase.google.com/docs/ai-logic/quotas

### Passo 8: gravar a chave no `env/firebase.json` e atualizar o secret (7 min)

1. Abra o arquivo (só você vê o conteúdo):
   ```powershell
   notepad C:\IaGo\env\firebase.json
   ```
2. Acrescente, antes do último `}` (com vírgula na linha anterior), esta linha com o ID da chave do passo 3:
   ```json
   "FIREBASE_APPCHECK_WEB_SITE_KEY": "COLE-O-ID-DA-CHAVE-WEB"
   ```
   O modelo está em `env/firebase.example.json`. **Não** coloque o token de depuração aqui. Deixe `FIREBASE_APPCHECK_ANDROID_SITE_KEY` de fora até o P2b.
3. Salve. Confira que o JSON é válido e que não há token de depuração:
   ```powershell
   Get-Content C:\IaGo\env\firebase.json -Raw | ConvertFrom-Json | Out-Null; "JSON ok"
   (Select-String -Path C:\IaGo\env\firebase.json -Pattern 'DEBUG').Count
   ```
   O segundo comando deve imprimir `0`.
4. Grave o secret **pelo Git Bash** (o pipe do PowerShell acrescenta BOM e quebras de linha):
   ```bash
   cd /c/IaGo && gh secret set FIREBASE_ENV_JSON < env/firebase.json
   ```
5. Confira:
   ```bash
   gh secret list | grep FIREBASE_ENV_JSON
   ```

**Conferir:** `JSON ok`, contagem `0`, e o `gh secret list` mostra `FIREBASE_ENV_JSON` com a data de hoje. O site publicado não muda, porque o secret só entra no próximo build do CI.

**Terminou o P2a?** Responda ao Claude com o bloco "O que mandar de volta".

---

## P2b: depois, só se o spike seguir para o APK (cerca de 15 min)

O APK é instalado fora da Play Store, então o Play Integrity não serve. A alternativa é o reCAPTCHA Enterprise no Android, que está em **preview** (sem SLA, pode mudar sem aviso). Ele **não foi provado** em APK fora da loja: o spike é que vai dizer. Só faça o P2b quando o Claude pedir.

1. Abra https://console.cloud.google.com/security/recaptcha?project=iago-beta e clique em criar chave:
   - Nome: `iago-android`
   - Plataforma: **Android**
   - Pacote: `br.ufrj.iago` (exatamente assim, maiúsculas e minúsculas contam). Cada pacote só pode ter uma chave do App Check.
2. Salve e copie o ID da chave.
3. Em https://console.firebase.google.com/project/iago-beta/appcheck, aba **Apps**, registre o app **Android** com o provedor **reCAPTCHA Enterprise** e o ID. TTL 24 horas, pontuação 0,5. **Save**.
4. Acrescente a `env/firebase.json`: `"FIREBASE_APPCHECK_ANDROID_SITE_KEY": "COLE-O-ID"`. Valide o JSON e regrave o secret como no passo 8 do P2a.
5. Para testar o APK de depuração em aparelho, o token de depuração do Android é outro: o Claude explica na hora, se for o caso.

**Conferir:** Apps mostra o app Android com "reCAPTCHA Enterprise". Em APIs, a exigência continua só no AI Logic.

Fontes: https://firebase.google.com/docs/app-check/android/recaptcha-enterprise-provider e https://firebase.google.com/docs/app-check/android/play-integrity-provider

---

## P2c: só antes da publicação de 26/11 (cerca de 20 min)

Restringir chaves **antes de testar** quebra o app; por isso fica por último, depois do teste completo.

1. Abra https://console.cloud.google.com/apis/credentials?project=iago-beta
2. Chave do navegador (a "Browser key" / web API key do Firebase):
   - **Application restrictions**: **Websites**, com `https://iago-beta.web.app/*` e `https://iago-beta.firebaseapp.com/*`.
   - **API restrictions**: **Restrict key**, só com as APIs que o app usa. A lista obrigatória do Firebase está em https://firebase.google.com/docs/projects/api-keys. Precisa incluir **Firebase AI Logic API** (`firebasevertexai.googleapis.com`) e **Firebase App Check API**; a lista completa **não foi confirmada aqui**, confira na página citada.
   - Para continuar testando em localhost depois de restringir, o site da chave também precisaria aceitar `http://localhost:*/*`. Decida com o Claude: a alternativa é testar só no site publicado.
3. Chave do Android:
   - **Application restrictions**: **Android apps**, pacote `br.ufrj.iago` e a impressão digital SHA-1 da chave de assinatura do APK. Para ver a SHA-1 da chave de debug (não é segredo):
     ```powershell
     keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android | Select-String 'SHA1'
     ```
   - **API restrictions**: as mesmas APIs.
4. Se existir uma chave da Gemini API criada pelo assistente do AI Logic (não confirmado): não a use no app e restrinja-a à API da Gemini. O app chama o modelo pelo Firebase AI Logic, que não pede essa chave.
5. Teste depois: https://iago-beta.web.app (demo, cadastro, login) e o APK.

**Conferir:** as duas chaves mostram "Restricted"; login e salvar questão funcionam no site e no aparelho.

Fonte: https://firebase.google.com/docs/ai-logic/security-checklist

---

## Hosts para o `drive.js` (testar contas e IA com as capturas)

O `drive.js` bloqueia tudo que não é local. Para contas reais, libere por `ALLOW_HOSTS` (casa por final do host, separados por vírgula):

```powershell
$env:ALLOW_HOSTS = 'www.gstatic.com,googleapis.com,www.google.com'
```

| Host | Para quê |
| --- | --- |
| `www.gstatic.com` | SDK do Firebase e arquivos do reCAPTCHA |
| `googleapis.com` | Auth, Firestore, `firebasevertexai.googleapis.com` (AI Logic), `firebaseappcheck.googleapis.com` (troca de token) e `recaptchaenterprise.googleapis.com` |
| `www.google.com` | Script `recaptcha/enterprise.js` (só aparece no site publicado, onde o reCAPTCHA está ativo; em localhost o App Check usa o token de depuração) |

Lista exata de hosts por pedido: **não confirmada**; se alguma chamada ainda falhar com `blocked`, o `drive.js` lista as URLs bloqueadas. Sem `ALLOW_HOSTS`, a prova de offline continua valendo.

## Fontes

- Firebase AI Logic: https://firebase.google.com/docs/ai-logic/get-started, /app-check, /quotas, /security-checklist
- App Check: https://firebase.google.com/docs/app-check/web/recaptcha-enterprise-provider, /web/debug-provider, /android/recaptcha-enterprise-provider
- AI Studio: https://aistudio.google.com/docs/rate-limits
- Spec: `docs/specs/mvp-27-11.md` (tarefa P2, riscos R3 a R6)
- Lidas em 07/11/2026 por uma ferramenta que resume páginas. Nomes de botões não citados entre aspas acima podem diferir na tela; na dúvida, siga a tela e avise o Claude.
