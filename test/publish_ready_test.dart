import 'package:flutter_test/flutter_test.dart';
import 'package:iago/core/app_info.dart';
import 'package:iago/features/auth/terms_page.dart';
import 'package:iago/features/bank/bank_sources_page.dart';
import 'package:iago/features/community/community_state.dart';

/// Pronto para publicar: pendências que bloqueiam a publicação de 26/11.
void main() {
  test(
    'o e-mail do projeto não é mais um marcador (CA-B7, CA-C11, termos)',
    // pendente: e-mail do projeto (D6/P4), obrigatório antes da publicação de
    // 26/11. Tirar o skip quando AppInfo.projectContactEmail for o real.
    skip: true,
    () {
      expect(AppInfo.projectContactEmail, isNot(contains('<')));
    },
  );

  test('os três pontos de uso apontam para a mesma constante', () {
    expect(communityContactEmail, AppInfo.projectContactEmail);
    expect(bankRemovalContact, AppInfo.projectContactEmail);
    expect(projectEmailPlaceholder, AppInfo.projectContactEmail);
  });
}
