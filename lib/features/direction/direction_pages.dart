import 'package:material_ui/material_ui.dart';

import '../../shared/placeholder_page.dart';

/// Provisória: a tela de verdade é a DI4.
class DirectionPage extends StatelessWidget {
  const DirectionPage({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Direciona',
    message: 'Seu objetivo e suas próximas etapas, em breve nesta tela.',
    icon: Icons.flag_outlined,
  );
}

/// Provisória: objetivo de estudo (DI4).
class GoalPage extends StatelessWidget {
  const GoalPage({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Objetivo de estudo',
    message: 'Escolher a prova, a data e as horas por semana, em breve.',
    icon: Icons.flag_outlined,
  );
}
