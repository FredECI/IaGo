import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../domain/area.dart';

/// Ícone colorido da área do conhecimento.
class AreaAvatar extends StatelessWidget {
  const AreaAvatar(this.area, {super.key, this.size = 40});

  final Area area;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: area.label,
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: AppColors.area(area),
        child: Icon(AppIcons.area(area), color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

/// Mensagem para listas vazias (com ação opcional).
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              title,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

/// Etiqueta pequena (tipo, plataforma) usada nos cartões.
class InfoTag extends StatelessWidget {
  const InfoTag({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// Mostra um aviso rápido na parte de baixo da tela.
void showMessage(BuildContext context, String text, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), action: action));
}
