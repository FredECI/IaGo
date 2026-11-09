import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/bank_asset_catalog.dart';
import '../../data/bank_catalog.dart';
import '../../domain/bank_source.dart';

/// Acervo do ENEM, lido do asset (sem rede e sem Firestore). Uma instância por
/// sessão: o asset é carregado só no primeiro uso. Nos testes, sobrescreva
/// com um catálogo falso.
final bankCatalogProvider = Provider<BankCatalog>((ref) => AssetBankCatalog());

/// Fontes registradas (crédito e aviso exibidos na tela do acervo).
final bankSourcesProvider = FutureProvider<List<BankSource>>(
  (ref) => ref.watch(bankCatalogProvider).sources(),
);
