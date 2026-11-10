# Demonstração do IaGo (MVP)

Roteiro para a entrega do MVP, em **27/11/2026**. A conta do Pedro volta ao estado original a cada entrada. Quase tudo funciona **sem internet**, porque a demo usa dados guardados no próprio aparelho.

- **Quem opera:** de preferência quem não está falando.
- **Onde:** no celular (APK ou link web) ou no notebook (Chrome).
- **Duração:** a medir no ensaio. O roteiro do beta, de menos de 2 minutos, está em [Regressão do beta](#regressão-do-beta-até-a-o2).
- **Dados:** o Pedro tem 40 questões originais e 2 listas. Onde algo é simulado, a tela diz isso.
- **Passos marcados "(depende do P2a)"** usam IA real. Até o P2a e as tarefas I3 e DI3, mostram só o caminho sem IA ou o exemplo simulado.

## Instalar (uma vez, antes da apresentação)

Até a publicação de 26/11, o site e o APK são do beta. Depois, o site passa a ser o MVP, e o APK do MVP sai na release `v0.2.0`, depois do teste no celular (Q2).

1. **Web:** abra [iago-beta.web.app](https://iago-beta.web.app), no celular ou no notebook. Não precisa instalar nada.
2. **APK:** o link atual é do beta, [IaGo-Beta-0.1.apk](https://github.com/FredECI/IaGo/releases/download/v0.1.0-beta/IaGo-Beta-0.1.apk), com cerca de 20 MB (prefira o Wi-Fi). Se o Android pedir, permita **instalar apps desconhecidos** para o navegador ou o gerenciador de arquivos. Quem instalou a versão de 03/11 precisa desinstalá-la antes; as seguintes instalam por cima.
3. Abra o IaGo, toque em **Entrar como Pedro (demonstração)** e teste uma vez em modo avião.

## Antes de começar: copie os textos

No passo 2 e no passo 3, os textos são **colados**. Deixe-os copiados no aparelho que vai operar (no celular, mande para você mesmo no WhatsApp e copie de lá).

Texto 1, para o passo 2:

```
Considere a função f(x) = 4x - 3. O valor de f(5) é:
A) 12
B) 15
C) 17
D) 20
E) 23
```

Texto 2, para o passo 3 (duas questões):

```
Questão 1
Qual é o valor de 3 + 4?
A) 5
B) 6
C) 7
D) 8
E) 9

Questão 2
Qual é o valor de 5 + 5?
A) 8
B) 9
C) 10
D) 11
E) 12
```

## Roteiro passo a passo

Os passos seguem os blocos do canvas: **Persona → Jornadas → Funcionalidades → Métricas**.

### 1. Persona e Painel (20 s)

- **Clicar:** **Entrar como Pedro (demonstração)**. O Painel abre sozinho.
- **Mostra:** o resumo da semana, sempre comparado com a anterior ("8 questões salvas nos últimos 7 dias, 3 a mais que nos 7 dias anteriores"). Logo abaixo, o card **Próxima etapa (simulada)**, do Direciona, e o card **Conecta**, com comunidades simuladas.
- **Falar:** "Este é o Pedro, 18 anos, vestibulando. Ele dá aula de reforço e tem pouco tempo. Nada de número solto: tudo é comparado com a semana anterior. O IaGo tem três pilares: **Agrega**, que organiza as questões; **Direciona**, que diz o que estudar; e **Conecta**, a comunidade, que aqui aparece em versão simulada."

### 2. Salvar uma questão colando o texto (30 s)

1. Tocar em **Salvar questão**.
2. Tocar no campo do enunciado e **colar** o Texto 1. Aparece "5 alternativas separadas do texto colado", e os campos A–E se preenchem sozinhos.
3. Tocar em **Matemática** (a matéria entra sozinha) e, logo abaixo, na sugestão **Funções**.
4. Na plataforma de origem, tocar na sugestão **Site de questões**.
5. Tocar em **Salvar**.

- **Falar:** "Ele cola o texto que já tem, sem scraping, e o IaGo separa as alternativas. *Questão salva em poucos segundos, meta: menos de 30 s.* E o painel já mostra **4 a mais** que nos 7 dias anteriores."

### 3. Importar várias questões de uma vez (40 s)

1. Em **Questões**, tocar em **Importar**.
2. Na seção **Colar texto**, colar o Texto 2 e tocar em **Separar questões**. O app mostra quantas questões separou.
3. Na revisão, conferir as duas. Digitar a plataforma (por exemplo, "Apostila") e tocar em **Aplicar a todas**.
4. Tocar em **Salvar 2 questões**.

- **Falar:** "Colar funciona sem internet e sem IA. Nada é salvo antes de tocar em Salvar: a revisão vem primeiro." Depois, sobre a seção **Prints e PDF**: "Para quem está no piloto, o arquivo vai para a IA, depois de um aviso de privacidade. A IA só copia o texto; você revisa. Isso é (depende do P2a) e, na demo, aparece como exemplo simulado."

### 4. Acervo: buscar, abrir e montar lista (60 s)

1. Em **Questões**, tocar em **Acervo**.
2. Digitar **função** na busca e filtrar por **Matemática**. O contador mostra o total do acervo e quantas questões o filtro trouxe.
3. Abrir uma questão. Mostrar **Origem e crédito** e o link **Conferir na fonte oficial**.
4. Tocar em **Salvar em Minhas questões**. O botão vira **Já salva**.
5. Voltar à busca, tocar em **Montar lista com estas N** (até 30 questões) e criar **Reforço — Funções**. Exportar o PDF, como no roteiro do beta.
6. Opcional: abrir **Avaliações da comunidade** e avaliar a dificuldade e a qualidade. Com menos de 3 avaliações, a tela diz "Poucas avaliações ainda"; na demo, o selo é **Dados simulados**.

- **Falar:** "É um banco de questões do ENEM: só leitura, sem gabarito e sem imagens, com crédito e link para a prova oficial. O IaGo não mostra a alternativa certa nem corrige. Quem está no piloto pode avaliar a dificuldade, e a média só aparece quando há avaliações suficientes."

### 5. Direciona: as etapas do dia (40 s)

1. No Painel, tocar em **Próxima etapa (simulada)**.
2. Mostrar a etapa: ação, matéria, quantidade, prazo e o motivo. Tocar em **Concluir** e conferir a frase de comparação, que sempre traz os últimos 14 dias e os 14 anteriores.
3. Tocar em **Adiar 2 dias**. Só dá para adiar uma vez.
4. Tocar em **Adicionar à agenda**, que abre o link para a agenda.

- **Falar:** "O prazo vem de fora, como na tese do produto: o estudante aceita ou adia uma vez, mas não escolhe a data. A etapa diz o que fazer; ela não ensina." Sobre a origem da proposta: "Sem IA, a etapa diz **Proposta automática**, pelas regras. Com IA, diz **Proposta pela IA** (depende do P2a e da DI3)."
- **Para um objetivo novo:** em **Definir objetivo**, informar a prova, a data (opcional) e as horas por semana, e tocar em **Salvar e receber etapas**.

### 6. Conecta: comunidade e moderação (50 s)

Na demo, o Conecta é simulado. Para contas reais, ele só abre para membros, depois que o grupo definir os moderadores.

1. Tocar no card **Conecta** e abrir uma das comunidades.
2. Tocar em **Escrever post**, escrever uma dúvida e tocar em **Publicar**. Se o texto tiver telefone, e-mail ou CPF, aparece um aviso antes da publicação (**Revisar** ou **Publicar mesmo assim**).
3. Abrir um post e tocar em **Ajudou** numa resposta. A reputação aparece como número de ajudas, ao lado da média do grupo.
4. Tocar em **Denunciar** num post de outra pessoa.
5. Voltar ao Conecta, ligar **Ver como moderador (demonstração)** e abrir **Moderação**. Mostrar **Restaurar**, **Ocultar** e **Ocultar e banir**.

- **Falar:** "É só texto. Não há mensagem direta, nem imagem, nem link clicável, e o apelido aparece no lugar do nome. A denúncia tira o conteúdo da vista até a revisão, e quem modera decide com um motivo. O interruptor de moderador existe só na demonstração."

### 7. Métricas H1 a H6 (30 s)

- **Clicar:** **Conta** e depois **Métricas do piloto**.
- **Falar:** "Cada hipótese do canvas vira um número ao lado da meta, calculado na hora. Aqui são **dados simulados** de 20 usuários fictícios, só para mostrar o cálculo. Repare que nem tudo bate a meta: a retenção e as listas por semana ficam abaixo, de propósito. H5 e H6 têm meta provisória, e a H2 usa a linha de base de 30 minutos, também provisória."
- **Hipóteses:** H1 (centralizar as questões), H2 (centralizar economiza tempo), H3 (ajuda quem dá aulas de reforço), H4 (grátis e boca a boca), H5 (prazo de fora aumenta a constância) e H6 (alunos se ajudam sem dinheiro).

## Perguntas prováveis

- **"De onde vêm as questões do acervo?"** Do ENEM, publicado pelo INEP. Os textos vêm com a formatação ajustada, com crédito e link para a prova oficial, e não têm gabarito nem imagens. Não afirmamos a licença das provas: estamos pedindo a confirmação, e a tela **Fontes e licenças** traz o canal para pedir a remoção de um texto.
- **"Vocês copiaram questões de algum site?"** Não. O acervo vem do ENEM, por uma API de terceiros usada só na preparação, e o app não acessa essa API. O IaGo não faz scraping. As questões do Pedro foram escritas para o protótipo.
- **"Tem gabarito? Corrige?"** Não, e é proposital: o IaGo organiza; não ensina, não corrige e não cria questões.
- **"A IA lê o que eu envio? Quem vê?"** (depende do P2a) Só para quem está no piloto, depois de um aviso. O arquivo vai para o Google, na camada gratuita, que pode usá-lo para melhorar produtos, e pessoas podem revisá-lo. Por isso o aviso pede para não enviar dados pessoais. O IaGo não guarda o arquivo: só o texto que você revisa vai para a sua conta.
- **"Os dados ficam seguros?"** Cada usuário só lê e escreve os próprios dados, garantido pelas regras do banco e testado. Dá para excluir a conta e tudo o que ela salvou (LGPD).
- **"E sem internet?"** A demo não usa rede, e o acervo abre sem internet. Numa conta real, as alterações ficam guardadas e sincronizam quando a conexão volta.
- **"Essas métricas são reais?"** Na demo, não: a tela diz "DADOS SIMULADOS". As métricas reais aparecem para os administradores quando o piloto começar.
- **"Qualquer pessoa pode entrar no Conecta?"** Não. No piloto, a entrada é para maiores de 18 anos com convite, e o Conecta só abre depois que o grupo define os moderadores.

## Plano B

1. **Vídeo e capturas:** em `docs/demo/`, são do beta. Serão regenerados com `drive.js` e `RECORD_VIDEO` depois da IA (tarefa O2).
2. **PDF:** `docs/demo/reforco-funcoes.pdf`, do beta, para mostrar a lista pronta mesmo se o app falhar.
3. **Sem Wi-Fi:**
   - APK instalado no celular, em modo avião;
   - ou o build web servido pelo próprio notebook, que não precisa de internet:
     ```
     flutter build web --release --no-web-resources-cdn
     python -m http.server 8765 --directory build/web
     ```
     e abrir `http://localhost:8765`.
   - O link publicado ([iago-beta.web.app](https://iago-beta.web.app)) precisa de internet para carregar a primeira vez. Abram com antecedência.

## Checklist antes da apresentação

- [ ] Ensaiar o roteiro do MVP com cronômetro e anotar a duração real.
- [ ] Textos 1 e 2 copiados no aparelho.
- [ ] Confirmar se o APK do MVP foi testado no celular (Q2). Se não, usar a web.
- [ ] Se for mostrar a IA: conferir antes que o P2a está feito e que a IA responde. Se não, mostrar só a colagem e as regras.
- [ ] Testar uma vez **em modo avião** (APK) ou com o Wi-Fi desligado (build local).
- [ ] Se for usar o link web: abrir antes, com internet, e deixar a aba aberta.
- [ ] Tela sempre acesa, notificações silenciadas (modo "Não perturbe") e celular carregado.
- [ ] Combinar quem opera e quem fala.
- [ ] Na hora: tocar em **Entrar como Pedro** só no início. Os dados voltam ao original a cada entrada.

## Regressão do beta (até a O2)

Roteiro do Beta 0.1, de menos de 2 minutos, mantido como teste de regressão até a tarefa O2 fechar. Os números abaixo vêm da seed e dos testes atuais (`test/data/demo_seed_test.dart` e `test/widget/questions_flow_test.dart`).

1. **Entrar** como Pedro (15 s).
2. **Painel:** "8 questões salvas nos últimos 7 dias, 3 a mais que nos 7 dias anteriores". Os cards "Em breve" saíram: agora há os cards Direciona e Conecta.
3. **Salvar a questão** do Texto 1 (Matemática → Funções → Site de questões → Salvar). O painel passa a mostrar **4 a mais** que nos 7 dias anteriores.
4. **Buscar "função"** em **Questões**: o contador mostra **13 de 40 questões**. Tocar em **Matemática** (11) e em **Objetiva** (9). Com a questão salva ao vivo, o total vira 41, e a busca com os mesmos filtros traz **10**.
5. **Montar a lista** "Reforço — Funções" com as questões do filtro (tocar em **Montar lista com estas N questões**), exportar o PDF e abrir. Sem a questão salva, a lista tem 9; com ela, 10.
6. **Métricas:** **Conta** → **Métricas do piloto**. Com dados simulados, H1 a H6.

Obs.: no roteiro do beta, a busca dava 14 de 41, 12 e 10. Esses números são antigos e não valem mais.

## Notas para o ensaio

- Os números são os das seções acima, conferidos nos testes. Se a seed mudar, atualize este arquivo e os testes juntos.
- Não usar "Entrar como Pedro" no meio da demo: ela zera os dados.
