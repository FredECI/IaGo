import '../../domain/area.dart';
import '../../domain/question.dart';
import '../../domain/question_list.dart';

/// Dados de exemplo da conta demo do Pedro: 40 questões e 2 listas prontas.
///
/// As questões foram escritas para este protótipo (nada copiado de plataformas
/// comerciais) e não têm gabarito. As datas são relativas a "agora", para o
/// resumo semanal fazer sentido em qualquer dia da apresentação:
/// - 8 questões nos últimos 7 dias e 5 nos 7 dias anteriores;
/// - a busca "função" + Matemática + Objetiva devolve 9 questões, então a
///   questão salva ao vivo na demo completa a lista "Reforço — Funções" com 10.
class DemoSeed {
  const DemoSeed({required this.questions, required this.lists});

  final List<Question> questions;
  final List<QuestionList> lists;

  static const String demoUserName = 'Pedro';

  factory DemoSeed.build(DateTime now) {
    final questions = _questions(now);
    return DemoSeed(questions: questions, lists: _lists(now));
  }
}

// Plataformas de origem fictícias, só para mostrar a dispersão.
const String _apostila = 'Apostila do cursinho';
const String _site = 'Site de questões';
const String _app = 'App de simulados';
const String _professor = 'Lista do professor';
const String _video = 'Canal de vídeo';
const String _livro = 'Livro didático';
const String _prova = 'Prova antiga';
const String _simulado = 'Simulado impresso';

DateTime _at(DateTime now, int daysAgo, int hour, [int minute = 0]) =>
    DateTime(now.year, now.month, now.day - daysAgo, hour, minute);

Question _q(
  DateTime now, {
  required String id,
  required Area area,
  required String subject,
  required String topic,
  required QuestionType type,
  required String statement,
  List<String> alternatives = const [],
  required String platform,
  required int daysAgo,
  int hour = 19,
  String? notes,
  String? url,
}) {
  // Minutos variados, mas determinísticos (mesmos dados em todo ensaio).
  final at = _at(now, daysAgo, hour, int.parse(id.substring(1)) * 7 % 60);
  return Question(
    id: 'demo-$id',
    statement: statement,
    type: type,
    alternatives: alternatives,
    area: area,
    subject: subject,
    topic: topic,
    platform: platform,
    sourceUrl: url,
    notes: notes,
    createdAt: at,
    updatedAt: at,
  );
}

const Area _mat = Area.mathematics;
const Area _nat = Area.naturalSciences;
const Area _hum = Area.humanities;
const Area _lin = Area.languages;
const QuestionType _obj = QuestionType.objective;
const QuestionType _dis = QuestionType.discursive;

List<Question> _questions(DateTime now) => [
  // ---------------------------------------------------------------- Matemática
  _q(
    now,
    id: 'q01',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement: 'Considere a função f(x) = 3x - 4. O valor de f(5) - f(2) é:',
    alternatives: ['5', '7', '9', '11', '13'],
    platform: _apostila,
    daysAgo: 34,
    hour: 20,
  ),
  _q(
    now,
    id: 'q02',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement:
        'Em uma cidade, uma corrida de aplicativo custa R\$ 5,00 fixos mais '
        'R\$ 2,40 por quilômetro rodado. A função que expressa o valor V, em '
        'reais, de uma corrida de x quilômetros é:',
    alternatives: [
      'V(x) = 5x + 2,40',
      'V(x) = 2,40x + 5',
      'V(x) = 7,40x',
      'V(x) = 5 - 2,40x',
      'V(x) = 2,40x - 5',
    ],
    platform: _site,
    daysAgo: 33,
    hour: 21,
    url: 'https://example.com/questoes/corrida-aplicativo',
  ),
  _q(
    now,
    id: 'q03',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement:
        'O vértice da parábola que representa a função f(x) = x² - 6x + 5 é '
        'o ponto:',
    alternatives: ['(3, -4)', '(-3, 4)', '(3, 4)', '(6, 5)', '(1, 0)'],
    platform: _app,
    daysAgo: 30,
    notes: 'Revisar a fórmula do vértice: xv = -b/2a.',
  ),
  _q(
    now,
    id: 'q04',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement: 'As raízes da função f(x) = x² - 5x + 6 são:',
    alternatives: ['-2 e -3', '1 e 6', '2 e 3', '-1 e 6', '0 e 5'],
    platform: _professor,
    daysAgo: 29,
    hour: 18,
  ),
  _q(
    now,
    id: 'q05',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement:
        'A população de uma cultura de bactérias dobra a cada hora e é dada '
        'pela função N(t) = 500 · 2^t, com t em horas. Após 3 horas, a '
        'população será de:',
    alternatives: ['1.500', '3.000', '4.000', '6.000', '8.000'],
    platform: _video,
    daysAgo: 8,
    hour: 22,
  ),
  _q(
    now,
    id: 'q06',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement:
        'Seja a função f(x) = log₂ x, definida para x > 0. O valor de '
        'f(32) + f(1/4) é:',
    alternatives: ['1', '3', '5', '7', '8'],
    platform: _livro,
    daysAgo: 9,
    hour: 7,
  ),
  _q(
    now,
    id: 'q07',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement:
        'Seja f(x) = 2x + 1. O valor de x para o qual a função inversa de f '
        'vale 3, ou seja, f⁻¹(x) = 3, é:',
    alternatives: ['1', '3', '5', '7', '9'],
    platform: _apostila,
    daysAgo: 2,
    hour: 20,
  ),
  _q(
    now,
    id: 'q08',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement:
        'Dadas as funções f(x) = x + 2 e g(x) = 3x, o valor de f(g(2)) é:',
    alternatives: ['6', '8', '10', '12', '14'],
    platform: _site,
    daysAgo: 2,
    hour: 21,
  ),
  _q(
    now,
    id: 'q09',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _obj,
    statement:
        'O gráfico de uma função afim passa pelos pontos (1, 3) e (3, 7). A '
        'lei dessa função é:',
    alternatives: [
      'f(x) = x + 2',
      'f(x) = 2x + 1',
      'f(x) = 3x',
      'f(x) = 2x + 3',
      'f(x) = 4x - 1',
    ],
    platform: _prova,
    daysAgo: 1,
    hour: 19,
  ),
  _q(
    now,
    id: 'q10',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _dis,
    statement:
        'Uma pequena fábrica de bolos tem lucro mensal, em reais, dado pela '
        'função L(x) = -x² + 40x - 300, em que x é a quantidade de centenas de '
        'bolos vendidos. Determine quantas centenas de bolos maximizam o lucro '
        'e qual é esse lucro máximo. Mostre os cálculos.',
    platform: _professor,
    daysAgo: 16,
    hour: 18,
    notes: 'Boa para a aula de reforço de quinta.',
  ),
  _q(
    now,
    id: 'q11',
    area: _mat,
    subject: 'Matemática',
    topic: 'Funções',
    type: _dis,
    statement:
        'O plano A de internet móvel custa R\$ 30,00 fixos mais R\$ 0,50 por '
        'gigabyte. O plano B custa R\$ 15,00 fixos mais R\$ 1,25 por gigabyte. '
        'Escreva a função do custo de cada plano e explique a partir de quantos '
        'gigabytes o plano A passa a ser mais vantajoso.',
    platform: _simulado,
    daysAgo: 6,
    hour: 12,
  ),
  _q(
    now,
    id: 'q12',
    area: _mat,
    subject: 'Matemática',
    topic: 'Porcentagem',
    type: _obj,
    statement:
        'Uma loja aplicou um desconto de 20% no preço de um tênis e, uma '
        'semana depois, aumentou o novo preço em 20%. Em relação ao preço '
        'original, o preço final é:',
    alternatives: [
      'igual ao original',
      '4% menor',
      '4% maior',
      '2% menor',
      '20% menor',
    ],
    platform: _app,
    daysAgo: 27,
    notes: 'Pegadinha clássica de porcentagem.',
  ),
  _q(
    now,
    id: 'q13',
    area: _mat,
    subject: 'Matemática',
    topic: 'Probabilidade',
    type: _obj,
    statement:
        'Ao lançar dois dados comuns, de seis faces, a probabilidade de a soma '
        'dos resultados ser 7 é:',
    alternatives: ['1/36', '1/12', '1/9', '1/6', '7/36'],
    platform: _video,
    daysAgo: 25,
    hour: 22,
    url: 'https://example.com/video/probabilidade-dados',
  ),
  _q(
    now,
    id: 'q14',
    area: _mat,
    subject: 'Matemática',
    topic: 'Geometria plana',
    type: _obj,
    statement:
        'Uma escada de 5 m está apoiada em um muro vertical, com o pé a 3 m da '
        'base do muro. A altura, em metros, do ponto em que a escada toca o '
        'muro é:',
    alternatives: ['2', '3', '4', '4,5', '6'],
    platform: _livro,
    daysAgo: 24,
    hour: 8,
  ),
  _q(
    now,
    id: 'q15',
    area: _mat,
    subject: 'Matemática',
    topic: 'Estatística',
    type: _obj,
    statement:
        'As notas de um aluno em cinco simulados foram 6, 8, 5, 9 e 7. A média '
        'e a mediana dessas notas são, respectivamente:',
    alternatives: ['7 e 7', '7 e 6', '6 e 7', '7,5 e 7', '7 e 8'],
    platform: _professor,
    daysAgo: 3,
    hour: 17,
  ),
  _q(
    now,
    id: 'q16',
    area: _mat,
    subject: 'Matemática',
    topic: 'Progressões',
    type: _dis,
    statement:
        'Para juntar dinheiro para a inscrição do vestibular, um estudante '
        'guardou R\$ 20,00 no primeiro mês e, a cada mês seguinte, R\$ 5,00 a '
        'mais do que no mês anterior. Quanto ele terá guardado ao final de 12 '
        'meses? Explique o raciocínio usado.',
    platform: _simulado,
    daysAgo: 17,
    hour: 13,
  ),

  // ------------------------------------------------------ Ciências da Natureza
  _q(
    now,
    id: 'q17',
    area: _nat,
    subject: 'Biologia',
    topic: 'Citologia',
    type: _obj,
    statement:
        'Células musculares, que gastam muita energia, apresentam grande '
        'quantidade de uma organela cuja principal função é a respiração '
        'celular. Essa organela é:',
    alternatives: [
      'o ribossomo',
      'a mitocôndria',
      'o complexo golgiense',
      'o lisossomo',
      'o centríolo',
    ],
    platform: _site,
    daysAgo: 38,
  ),
  _q(
    now,
    id: 'q18',
    area: _nat,
    subject: 'Biologia',
    topic: 'Genética',
    type: _obj,
    statement:
        'Em uma espécie de planta, a cor púrpura das flores (A) é dominante '
        'sobre a cor branca (a). Do cruzamento entre duas plantas heterozigotas '
        '(Aa × Aa), espera-se a proporção fenotípica de:',
    alternatives: [
      '1 púrpura : 1 branca',
      '3 púrpuras : 1 branca',
      '1 púrpura : 3 brancas',
      'todas púrpuras',
      '1 : 2 : 1',
    ],
    platform: _apostila,
    daysAgo: 37,
    hour: 20,
  ),
  _q(
    now,
    id: 'q19',
    area: _nat,
    subject: 'Biologia',
    topic: 'Ecologia',
    type: _dis,
    statement:
        'Em um lago, as algas servem de alimento para pequenos crustáceos, que '
        'são comidos por peixes, que por sua vez são caçados por garças. '
        'Explique o que tende a acontecer com a população de algas se os '
        'peixes forem retirados do lago por pesca excessiva.',
    platform: _video,
    daysAgo: 36,
    hour: 21,
  ),
  _q(
    now,
    id: 'q20',
    area: _nat,
    subject: 'Biologia',
    topic: 'Imunologia',
    type: _obj,
    statement: 'As vacinas protegem o organismo porque:',
    alternatives: [
      'contêm anticorpos prontos que permanecem no sangue por toda a vida',
      'estimulam o sistema imunológico a produzir anticorpos e células de '
          'memória',
      'destroem diretamente os vírus já presentes no corpo',
      'aumentam a temperatura corporal, eliminando microrganismos',
      'substituem a ação dos glóbulos vermelhos',
    ],
    platform: _app,
    daysAgo: 35,
    hour: 18,
  ),
  _q(
    now,
    id: 'q21',
    area: _nat,
    subject: 'Física',
    topic: 'Cinemática',
    type: _obj,
    statement:
        'Um ônibus percorre 180 km entre duas cidades em 2 h 30 min. Sua '
        'velocidade média nesse trajeto é de:',
    alternatives: ['60 km/h', '72 km/h', '75 km/h', '80 km/h', '90 km/h'],
    platform: _livro,
    daysAgo: 10,
    hour: 7,
  ),
  _q(
    now,
    id: 'q22',
    area: _nat,
    subject: 'Física',
    topic: 'Eletricidade',
    type: _obj,
    statement:
        'Um chuveiro elétrico de 5.000 W é usado 30 minutos por dia. Em 30 '
        'dias, a energia consumida por ele é de:',
    alternatives: ['15 kWh', '25 kWh', '75 kWh', '150 kWh', '750 kWh'],
    platform: _prova,
    daysAgo: 4,
    hour: 22,
    notes: 'Lembrar de converter minutos em horas.',
  ),
  _q(
    now,
    id: 'q23',
    area: _nat,
    subject: 'Física',
    topic: 'Dinâmica',
    type: _dis,
    statement:
        'Quando um ônibus freia bruscamente, os passageiros em pé tendem a ser '
        'projetados para a frente. Explique esse fenômeno com base nas Leis de '
        'Newton.',
    platform: _professor,
    daysAgo: 31,
    hour: 19,
  ),
  _q(
    now,
    id: 'q24',
    area: _nat,
    subject: 'Química',
    topic: 'Estequiometria',
    type: _obj,
    statement:
        'Considerando as massas atômicas H = 1 u e O = 16 u, a massa molar da '
        'água (H₂O) e a quantidade de matéria presente em 36 g de água são, '
        'respectivamente:',
    alternatives: [
      '17 g/mol e 2 mol',
      '18 g/mol e 2 mol',
      '18 g/mol e 0,5 mol',
      '34 g/mol e 1 mol',
      '36 g/mol e 1 mol',
    ],
    platform: _apostila,
    daysAgo: 28,
    hour: 20,
  ),
  _q(
    now,
    id: 'q25',
    area: _nat,
    subject: 'Química',
    topic: 'Ácidos e bases',
    type: _obj,
    statement: 'Uma solução com pH igual a 3, a 25 °C, é classificada como:',
    alternatives: [
      'básica, pois o pH é menor que 7',
      'neutra, pois o pH é positivo',
      'ácida, pois o pH é menor que 7',
      'ácida, pois o pH é maior que 1',
      'básica, pois contém íons H⁺',
    ],
    platform: _site,
    daysAgo: 26,
    hour: 21,
    url: 'https://example.com/questoes/ph-solucoes',
  ),
  _q(
    now,
    id: 'q26',
    area: _nat,
    subject: 'Química',
    topic: 'Oxirredução',
    type: _dis,
    statement:
        'Um portão de ferro exposto à chuva enferruja com o tempo. Explique, em '
        'termos de oxidação e redução, o que acontece com o ferro e por que '
        'pintar o portão ajuda a evitar a ferrugem.',
    platform: _video,
    daysAgo: 23,
    hour: 22,
  ),

  // ---------------------------------------------------------- Ciências Humanas
  _q(
    now,
    id: 'q27',
    area: _hum,
    subject: 'História',
    topic: 'Revolução Industrial',
    type: _obj,
    statement:
        'Uma das consequências da Revolução Industrial na Inglaterra do século '
        'XVIII foi:',
    alternatives: [
      'o fim do trabalho assalariado nas cidades',
      'a intensificação da urbanização e o surgimento do operariado fabril',
      'o retorno da produção artesanal como principal forma de trabalho',
      'a redução imediata da jornada de trabalho para oito horas',
      'a diminuição do uso de carvão como fonte de energia',
    ],
    platform: _app,
    daysAgo: 22,
    hour: 19,
  ),
  _q(
    now,
    id: 'q28',
    area: _hum,
    subject: 'História',
    topic: 'Era Vargas',
    type: _obj,
    statement:
        'A Consolidação das Leis do Trabalho (CLT), de 1943, foi criada '
        'durante:',
    alternatives: [
      'o governo de Juscelino Kubitschek',
      'a República Velha',
      'o Estado Novo de Getúlio Vargas',
      'o Regime Militar',
      'o Período Regencial',
    ],
    platform: _apostila,
    daysAgo: 11,
    hour: 20,
  ),
  _q(
    now,
    id: 'q29',
    area: _hum,
    subject: 'História',
    topic: 'Brasil Império',
    type: _dis,
    statement:
        'A Lei Áurea, de 1888, aboliu a escravidão no Brasil. Explique por que, '
        'mesmo após a abolição, a população negra continuou enfrentando '
        'exclusão social, citando pelo menos dois fatores.',
    platform: _professor,
    daysAgo: 21,
    hour: 18,
    notes: 'Cai muito em vestibular estadual.',
  ),
  _q(
    now,
    id: 'q30',
    area: _hum,
    subject: 'Geografia',
    topic: 'Urbanização',
    type: _obj,
    statement:
        'O êxodo rural intenso no Brasil, principalmente entre as décadas de '
        '1950 e 1980, esteve associado:',
    alternatives: [
      'à mecanização do campo e à concentração de terras',
      'ao fim da industrialização nas grandes cidades',
      'a uma reforma agrária ampla realizada no período',
      'à diminuição da população urbana',
      'à proibição do trabalho agrícola assalariado',
    ],
    platform: _livro,
    daysAgo: 20,
    hour: 8,
  ),
  _q(
    now,
    id: 'q31',
    area: _hum,
    subject: 'Geografia',
    topic: 'Fusos horários',
    type: _obj,
    statement:
        'Cada fuso horário corresponde a 15° de longitude. Uma cidade '
        'localizada 45° a leste de outra terá, em relação a ela, horário:',
    alternatives: [
      '3 horas adiantado',
      '3 horas atrasado',
      '45 minutos adiantado',
      '4 horas e meia adiantado',
      'igual',
    ],
    platform: _site,
    daysAgo: 5,
    hour: 21,
  ),
  _q(
    now,
    id: 'q32',
    area: _hum,
    subject: 'Geografia',
    topic: 'Energia',
    type: _dis,
    statement:
        'A maior parte da energia elétrica do Brasil vem de usinas '
        'hidrelétricas. Cite uma vantagem e uma desvantagem socioambiental '
        'desse tipo de usina.',
    platform: _simulado,
    daysAgo: 19,
    hour: 12,
  ),
  _q(
    now,
    id: 'q33',
    area: _hum,
    subject: 'Filosofia',
    topic: 'Filosofia antiga',
    type: _obj,
    statement:
        'O método de Sócrates, que buscava levar o interlocutor a reconhecer a '
        'própria ignorância por meio de perguntas, ficou conhecido como:',
    alternatives: [
      'empirismo',
      'maiêutica',
      'existencialismo',
      'positivismo',
      'iluminismo',
    ],
    platform: _video,
    daysAgo: 18,
    hour: 22,
  ),
  _q(
    now,
    id: 'q34',
    area: _hum,
    subject: 'Sociologia',
    topic: 'Cidadania',
    type: _dis,
    statement:
        'Explique a diferença entre direitos civis, políticos e sociais e dê um '
        'exemplo de cada um no Brasil atual.',
    platform: _professor,
    daysAgo: 15,
    hour: 17,
  ),

  // ---------------------------------------------------------------- Linguagens
  _q(
    now,
    id: 'q35',
    area: _lin,
    subject: 'Português',
    topic: 'Funções da linguagem',
    type: _obj,
    statement:
        'Um anúncio diz: “Venha para o cursinho e garanta já a sua vaga!”. '
        'Nesse texto, predomina a função da linguagem:',
    alternatives: [
      'referencial',
      'emotiva',
      'conativa (apelativa)',
      'metalinguística',
      'fática',
    ],
    platform: _app,
    daysAgo: 39,
    hour: 20,
  ),
  _q(
    now,
    id: 'q36',
    area: _lin,
    subject: 'Português',
    topic: 'Variação linguística',
    type: _obj,
    statement:
        'Em uma conversa entre amigos, alguém diz: “A gente vamos no show '
        'amanhã”. Do ponto de vista da variação linguística, é correto '
        'afirmar que essa frase:',
    alternatives: [
      'é um erro que impede a comunicação',
      'é uma marca de registro informal, adequada a certos contextos',
      'pertence exclusivamente à escrita formal',
      'não pode ser estudada pela gramática',
      'mostra que o falante não conhece a língua portuguesa',
    ],
    platform: _livro,
    daysAgo: 40,
    hour: 9,
  ),
  _q(
    now,
    id: 'q37',
    area: _lin,
    subject: 'Português',
    topic: 'Crase',
    type: _obj,
    statement:
        'Assinale a alternativa em que o uso do acento grave indicativo de '
        'crase está correto.',
    alternatives: [
      'Fui à pé para a escola.',
      'Entreguei o trabalho à professora.',
      'Começou à chover cedo.',
      'Ela se referiu à você.',
      'Estou disposto à ajudar.',
    ],
    platform: _site,
    daysAgo: 5,
    hour: 7,
  ),
  _q(
    now,
    id: 'q38',
    area: _lin,
    subject: 'Literatura',
    topic: 'Modernismo',
    type: _obj,
    statement:
        'A Semana de Arte Moderna de 1922, realizada em São Paulo, teve como '
        'uma de suas propostas:',
    alternatives: [
      'a valorização das regras rígidas do Parnasianismo',
      'a ruptura com padrões estéticos tradicionais e a busca de uma arte '
          'brasileira',
      'o retorno aos modelos clássicos europeus',
      'a defesa da poesia com métrica e rima obrigatórias',
      'a rejeição de qualquer tema nacional',
    ],
    platform: _apostila,
    daysAgo: 32,
    hour: 21,
  ),
  _q(
    now,
    id: 'q39',
    area: _lin,
    subject: 'Inglês',
    topic: 'Interpretação de texto',
    type: _obj,
    statement:
        'Read the sentence: “Despite the heavy rain, the students arrived on '
        'time for the exam.” The word “despite” indicates:',
    alternatives: ['cause', 'contrast', 'addition', 'time', 'conclusion'],
    platform: _video,
    daysAgo: 12,
    hour: 19,
  ),
  _q(
    now,
    id: 'q40',
    area: _lin,
    subject: 'Redação',
    topic: 'Proposta de redação',
    type: _dis,
    statement:
        'Redija um texto dissertativo-argumentativo sobre o tema “Desafios para '
        'conciliar trabalho e estudos entre jovens brasileiros”. Apresente uma '
        'proposta de intervenção para o problema.',
    platform: _simulado,
    daysAgo: 15,
    hour: 10,
    notes: 'Treinar a proposta de intervenção.',
  ),
];

List<QuestionList> _lists(DateTime now) => [
  QuestionList(
    id: 'demo-l01',
    name: 'Revisão — Ciências da Natureza',
    questionIds: const [
      'demo-q17',
      'demo-q18',
      'demo-q20',
      'demo-q24',
      'demo-q25',
      'demo-q19',
      'demo-q23',
      'demo-q26',
    ],
    createdAt: _at(now, 12, 20),
    updatedAt: _at(now, 12, 20),
    exportCount: 1,
    lastExportedAt: _at(now, 11, 18),
  ),
  QuestionList(
    id: 'demo-l02',
    name: 'Aula de reforço — Matemática básica',
    questionIds: const [
      'demo-q12',
      'demo-q13',
      'demo-q14',
      'demo-q15',
      'demo-q16',
      'demo-q01',
    ],
    createdAt: _at(now, 2, 13),
    updatedAt: _at(now, 2, 13),
  ),
];
