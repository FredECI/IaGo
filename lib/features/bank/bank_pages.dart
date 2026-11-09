import 'package:material_ui/material_ui.dart';

import '../../shared/placeholder_page.dart';

/// Provisória: a tela de verdade é a A4.
class BankPage extends StatelessWidget {
  const BankPage({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Acervo',
    message: 'Questões do ENEM para consulta, em breve nesta tela.',
    icon: Icons.local_library_outlined,
  );
}

/// Provisória: o detalhe é da A4.
class BankQuestionPage extends StatelessWidget {
  const BankQuestionPage({super.key, required this.questionId});

  final String questionId;

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Questão do acervo',
    message: 'O detalhe da questão do acervo chega em breve.',
    icon: Icons.local_library_outlined,
  );
}

/// Provisória: "Fontes e licenças" é da A5.
class BankSourcesPage extends StatelessWidget {
  const BankSourcesPage({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Fontes e licenças',
    message: 'De onde vêm as questões do acervo, em breve nesta tela.',
    icon: Icons.verified_outlined,
  );
}
