import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/policy_providers.dart';
import '../../data/providers.dart';
import '../../domain/ai_ports.dart';
import '../community/community_access.dart';
import 'import_models.dart';

/// Escolhe arquivos para a IA. Injetável: os testes trocam por uma lista fixa.
typedef PickFiles = Future<List<ImportFile>> Function();

/// Padrão: só prints, pelo `image_picker` (já no projeto). PDF fica para a
/// F5b, que acrescenta um seletor de arquivos de verdade; trocar é só
/// sobrescrever este provider.
final pickFilesProvider = Provider<PickFiles>((ref) => pickImageFiles);

Future<List<ImportFile>> pickImageFiles() async {
  final picked = await ImagePicker().pickMultiImage(limit: maxImportFiles);
  final files = <ImportFile>[];
  for (final x in picked) {
    // Grande demais: não lê os bytes; segue com um arquivo vazio, que a
    // checagem de limites recusa pelo tipo/tamanho sem custo de memória.
    final tooBig = await x.length() > maxImportFileBytes;
    files.add(
      ImportFile(
        name: x.name,
        mimeType: x.mimeType ?? '',
        bytes: tooBig
            ? Uint8List(maxImportFileBytes + 1)
            : await x.readAsBytes(),
      ),
    );
  }
  return files;
}

/// Versão do aviso de privacidade da IA aceita nesta sessão (CA-I12).
/// A gravação no perfil (`aiNoticeVersion`) depende do campo no perfil (F6).
class AiNoticeAccepted extends Notifier<String?> {
  @override
  String? build() {
    // Outra sessão (sair/entrar) pede o aceite de novo.
    ref.watch(sessionProvider);
    return null;
  }

  void accept() => state = aiNoticeVersion;
}

final aiNoticeAcceptedProvider = NotifierProvider<AiNoticeAccepted, String?>(
  AiNoticeAccepted.new,
);

/// Modo da IA para a tela de importação.
final importAiModeProvider = Provider<ImportAiMode>((ref) {
  final session = ref.watch(sessionProvider);
  return resolveImportAiMode(
    isDemo: session?.isDemo ?? false,
    extractor: ref.watch(questionExtractorProvider),
    policy: ref.watch(accessPolicyProvider),
    isMember: ref.watch(isMemberProvider),
  );
});
