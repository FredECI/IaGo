import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'common_widgets.dart';

/// Página provisória das telas do MVP ainda não construídas (F7): título, uma
/// frase e "Voltar". Cada trilha troca a sua pela tela de verdade.
class PlaceholderPage extends StatelessWidget {
  const PlaceholderPage({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.construction_outlined,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: PageTitle(title)),
      body: EmptyState(
        icon: icon,
        title: title,
        message: message,
        action: OutlinedButton(
          key: const Key('placeholder-back'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/painel'),
          child: const Text('Voltar'),
        ),
      ),
    );
  }
}
