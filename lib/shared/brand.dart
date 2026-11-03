import 'package:material_ui/material_ui.dart';

import '../app/theme.dart';
import '../core/app_info.dart';

/// Marca do IaGo: quadrado arredondado com degradê e um livro aberto.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Logotipo do ${AppInfo.name}',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.brandGradient,
          ),
        ),
        child: Icon(
          Icons.auto_stories_rounded,
          color: Colors.white,
          size: size * 0.56,
        ),
      ),
    );
  }
}

/// Selo "Beta 0.1", sempre visível nas telas principais.
class BetaBadge extends StatelessWidget {
  const BetaBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.betaBackground(theme.brightness),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        AppInfo.versionLabel,
        style: theme.textTheme.labelSmall?.copyWith(
          color: AppColors.betaForeground,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Título de página com o selo Beta ao lado.
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.showBrand = false});

  final String title;
  final bool showBrand;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showBrand) ...[
          const BrandMark(size: 30),
          const SizedBox(width: 10),
        ],
        Flexible(child: Text(title, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        const BetaBadge(),
      ],
    );
  }
}
