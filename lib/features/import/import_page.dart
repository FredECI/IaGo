import 'package:material_ui/material_ui.dart';

import '../../shared/placeholder_page.dart';

/// Provisória: a tela de verdade é a I4.
class ImportPage extends StatelessWidget {
  const ImportPage({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderPage(
    title: 'Importar questões',
    message: 'Importar várias questões de uma vez, em breve nesta tela.',
    icon: Icons.upload_file_outlined,
  );
}
