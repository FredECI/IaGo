# IaGo — Beta 0.1

**IaGo** (Inteligência Artificial de Gerenciamento e Organização de Estudos) reúne num só lugar as questões que o estudante encontra em várias plataformas. Ele organiza tudo por conteúdo e tipo e monta listas em PDF para estudar ou levar à aula de reforço.

Este beta implementa o pilar **Agrega**, com registro manual. **Direciona** (metas e prazos) e **Conecta** (comunidades) aparecem como "Em breve".

Projeto acadêmico de Caio Peixoto, Fred, João Ricardo, Luiz e Nicolas (UFRJ).

## Requisitos

- Flutter 3.47.x stable (Dart 3.13)
- Chrome, para a web
- Para Android: JDK 17+ e Android SDK com as licenças aceitas

## Rodar

```bash
flutter pub get
flutter run -d chrome
```

Na tela inicial, toque em **Entrar como Pedro (demonstração)**. A conta demo traz 40 questões de exemplo e 2 listas, guardadas só no aparelho e funcionando sem internet. Os dados voltam ao estado original a cada entrada.

## Testar

```bash
flutter analyze   # deve terminar com "No issues found!"
flutter test
```

## Gerar os builds

```bash
# Web (com CanvasKit embutido: funciona sem CDN)
flutter build web --release --no-web-resources-cdn

# Servir o build localmente
python -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

## Capturas de tela

O roteiro `tool/screenshots/drive.js` abre o build web no Chrome a 360 px e bloqueia qualquer pedido fora do localhost. Assim ele também prova que o app roda offline.

```bash
cd tool/screenshots
npm install
node drive.js http://127.0.0.1:8765/ shots "shot:entrada" "click:Entrar como Pedro" "shot:painel"
```

## Estrutura

```
lib/
  app/        tema, rotas (go_router), inicialização
  core/       utilitários (normalização de texto, datas, ids)
  domain/     modelos e regras puras (questão, lista, filtros, leitura de texto colado)
  data/       repositórios (interfaces) e implementação local da demo
  features/   telas: entrada, painel, questões, listas, conta
  shared/     widgets comuns e marca
test/         testes unitários e de widget
tool/         geração das fontes e roteiro de capturas
```

## Fontes e licenças

A fonte [Inter](https://github.com/rsms/inter) está sob a SIL Open Font License (`assets/fonts/OFL.txt`). As questões de exemplo foram escritas para este protótipo e não vêm de plataformas comerciais.
