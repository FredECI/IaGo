import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../core/app_info.dart';
import '../features/auth/terms_gate.dart';
import 'router.dart';
import 'theme.dart';
import 'theme_mode_controller.dart';

class IagoApp extends ConsumerWidget {
  const IagoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: '${AppInfo.name} · ${AppInfo.versionLabel}',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Termos novos: a conta em versão antiga só vê o novo aceite (CA-T8).
      builder: (context, child) =>
          TermsGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
