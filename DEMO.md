# Demonstração do IaGo Beta 0.1

Roteiro para a apresentação de **sexta, 06/11/2026**. A demonstração dura **menos de 2 minutos** e funciona **com ou sem internet**, porque o modo demonstração usa dados guardados no próprio aparelho.

- **Quem opera:** de preferência quem não está falando.
- **Onde:** no celular (APK ou link web) ou no notebook (Chrome).
- **Dados:** a conta demo do Pedro volta ao estado original a cada entrada. Se algo der errado no meio, é só sair e entrar de novo.

## Instalar o app no celular (uma vez, antes da aula)

1. No celular, abra **[iago-beta.web.app/IaGo-Beta-0.1.apk](https://iago-beta.web.app/IaGo-Beta-0.1.apk)**. São cerca de 20 MB, então prefira o Wi-Fi.
2. Abra o arquivo. Se o Android pedir, permita **instalar apps desconhecidos** para o navegador ou para o gerenciador de arquivos.
3. Abra o IaGo, toque em **Entrar como Pedro (demonstração)** e teste uma vez em modo avião.

Sem instalar nada, a versão web abre em **[iago-beta.web.app](https://iago-beta.web.app)**, no celular ou no notebook.

- Para trocar de versão do APK, desinstale a anterior antes de instalar a nova.
- Baixem o APK antes de sexta: o plano gratuito do site tem cota diária de tráfego.

## Antes de começar: copie o texto da questão

No passo 3 a questão é **colada**. Deixe este texto copiado no aparelho que vai operar (no celular, mande para você mesmo no WhatsApp e copie de lá):

```
Considere a função f(x) = 4x - 3. O valor de f(5) é:
A) 12
B) 15
C) 17
D) 20
E) 23
```

## Roteiro passo a passo

Os passos seguem os blocos do canvas: **Persona → Jornadas → Funcionalidades → Métricas**.

### 1. Persona: entrar como Pedro (15 s)

- **Clicar:** abrir o app e tocar em **Entrar como Pedro (demonstração)**.
- **Falar:** "Este é o Pedro, 18 anos, vestibulando de escola particular. Ele dá aula de reforço para ajudar em casa: tem pouco tempo, pouco dinheiro e pouca energia. As questões dele estão espalhadas em apostila, sites, apps e listas de professor."
- **Mostra:** o cadastro gratuito com entrada em um toque (preço zero na porta de entrada).

### 2. Jornada 3, organizar a rotina: o painel (20 s)

- **Clicar:** nada; o painel abre sozinho. Se der tempo, rolar até os cards "Em breve".
- **Falar:** "Nada de número solto. O painel diz *8 questões salvas nos últimos 7 dias, 3 a mais que nos 7 dias anteriores*. E o roteiro do produto está aqui: **Direciona** (metas e prazos) e **Conecta** (comunidades) chegam depois. Este beta é o pilar **Agrega**."
- **Captura:** `docs/demo/02-painel.png` e `03-em-breve.png`.

### 3. Funcionalidades: salvar uma questão de qualquer plataforma (30 s)

1. Tocar em **Salvar questão**.
2. Tocar no campo do enunciado e **colar**. Aparece "5 alternativas separadas do texto colado", e os campos A–E se preenchem sozinhos.
3. Tocar em **Matemática** (a matéria entra sozinha) e, logo abaixo, na sugestão **Funções**.
4. Na plataforma de origem, tocar na sugestão **Site de questões**.
5. Tocar em **Salvar**.

- **Falar:** "Ele cola o texto que já tem, sem scraping, e o IaGo separa as alternativas. Escolhe área, matéria e assunto, e informa de onde veio. *Questão salva em poucos segundos, meta: menos de 30 s.* E o painel já mostra 9, **4 a mais** que na semana anterior."
- **Captura:** `04-questao-colada.png`, `05-categoria.png` e `06-questao-salva.png`.

### 4. Jornada 1, estudar em casa: buscar e filtrar (20 s)

1. Tocar em **Questões** e digitar **função** na busca. O contador mostra **14 de 41**, com questões também de Biologia e Linguagens.
2. Tocar em **Matemática** (12) e em **Objetiva** (10).

- **Falar:** "Tudo num lugar só, organizado por conteúdo. Cada filtro mostra quantas questões vai trazer. Ficaram **10** objetivas de funções."
- **Captura:** `07-busca-e-filtros.png`.

### 5. Jornada 2, preparar o reforço: montar a lista e baixar o PDF (30 s)

1. Tocar em **Montar lista com estas 10 questões**.
2. Digitar **Reforço — Funções** e tocar em **Criar lista**. No editor dá para arrastar para reordenar e tirar questões.
3. Tocar em **Exportar PDF** e depois em **Abrir PDF**. Na web, o PDF abre numa nova aba; no Android, na tela de visualização.

- **Falar:** "A lista sai pronta para imprimir: nome, numeração, campo de nome e data, **sem gabarito** e com linhas de resposta nas discursivas. O PDF é gerado na hora, no aparelho, e não fica guardado no servidor."
- **Captura:** `08-nome-da-lista.png`, `09-editor-da-lista.png` e `10-exportar-pdf.png`. O PDF de exemplo está em `docs/demo/reforco-funcoes.pdf`.

### 6. Métricas: como vamos validar H1–H4 (20 s)

- **Clicar:** **Conta** e depois **Métricas do piloto**.
- **Falar:** "Cada hipótese do canvas vira um número ao lado da sua meta. Atenção: aqui são **dados simulados** de 20 usuários fictícios, só para mostrar o cálculo. Repare que nem tudo bate a meta: a retenção e as listas por semana ficam abaixo. É isso que o piloto vai medir de verdade com os ~20 vestibulandos."
- **Captura:** `11-metricas-do-piloto.png`.

## Perguntas prováveis

- **"Vocês copiaram questões de algum site?"** Não. As 40 questões de exemplo foram escritas para o protótipo, e o estudante cola o que ele mesmo já tem. O IaGo não faz scraping.
- **"Tem gabarito? Corrige?"** Não, e é proposital: o IaGo organiza; não ensina, não corrige e não cria questões.
- **"Os dados ficam seguros?"** Cada usuário só lê e escreve os próprios dados; isso é garantido pelas regras do banco e foi testado. Dá para excluir a conta e tudo o que ela salvou (LGPD).
- **"E sem internet?"** O modo demonstração não usa rede. Uma conta real guarda as alterações e sincroniza quando a conexão volta.
- **"Essas métricas são reais?"** Na demonstração, não: a tela diz "DADOS SIMULADOS". As métricas reais aparecem para os administradores quando o piloto começar.

## Plano B

1. **Vídeo:** `docs/demo/roteiro-demo.webm` tem o roteiro inteiro gravado automaticamente, sem áudio. Abre no Chrome ou no VLC. Se der tempo, gravem também um vídeo próprio narrado: no Windows, Win+Alt+R (Xbox Game Bar); no Android, "Gravar tela" no menu rápido.
2. **Capturas:** `docs/demo/01-entrada.png` a `11-metricas-do-piloto.png`, na ordem do roteiro. Dá para apresentar como slides.
3. **PDF:** `docs/demo/reforco-funcoes.pdf`, para mostrar a lista pronta mesmo se o app falhar.
4. **Sem Wi-Fi:**
   - APK instalado no celular, em modo avião;
   - ou o build web servido pelo próprio notebook, que não precisa de internet:
     ```
     flutter build web --release --no-web-resources-cdn
     python -m http.server 8765 --directory build/web
     ```
     e abrir `http://localhost:8765`.
   - O link publicado ([iago-beta.web.app](https://iago-beta.web.app)) precisa de internet para carregar a primeira vez. Abram com antecedência.

## Checklist antes da aula

- [ ] Ensaiar o roteiro inteiro com cronômetro (meta: menos de 2 min) no aparelho que vai operar.
- [ ] Texto da questão do passo 3 copiado no aparelho.
- [ ] Tela sempre acesa (desligar o bloqueio automático) e brilho no máximo.
- [ ] Notificações silenciadas (modo "Não perturbe").
- [ ] Celular carregado e carregador por perto.
- [ ] APK instalado no celular que vai operar (veja [Instalar o app](#instalar-o-app-no-celular-uma-vez-antes-da-aula)).
- [ ] Testar uma vez **em modo avião** (APK) ou com o Wi-Fi desligado (build local).
- [ ] Se for usar o link web ([iago-beta.web.app](https://iago-beta.web.app)): abrir antes da aula, com internet, e deixar a aba aberta.
- [ ] Vídeo e capturas do plano B no pen drive e na nuvem.
- [ ] Combinar quem opera e quem fala, e a frase de passagem entre os dois.
- [ ] Na hora: tocar em **Entrar como Pedro** só no início da demo. Os dados voltam ao original a cada entrada.
