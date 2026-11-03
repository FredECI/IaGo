import 'dart:async';

/// Valor observável em memória: cada novo ouvinte recebe o valor atual na hora
/// e, depois, todas as mudanças. Base dos repositórios locais (modo demo).
class LiveValue<T> {
  LiveValue(this._value);

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast(
    sync: true,
  );

  T get value => _value;

  set value(T next) {
    _value = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  /// Stream que começa pelo valor atual, sem janela para perder mudanças.
  Stream<T> get stream {
    late final StreamController<T> controller;
    StreamSubscription<T>? subscription;
    controller = StreamController<T>(
      onListen: () {
        controller.add(_value);
        subscription = _changes.stream.listen(controller.add);
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  Future<void> close() => _changes.close();
}
