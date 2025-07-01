import 'dart:async';

class DebounceController {
  final Duration debounceDuration;
  Timer? _debounce;

  DebounceController({this.debounceDuration = const Duration(seconds: 3)});

  void trigger(FutureOr<void> Function() action) {
    _debounce?.cancel();
    _debounce = Timer(debounceDuration, () {
      action();
      _debounce = null; // Reset debounce after action is executed
    });
  }

  void cancel() {
    _debounce?.cancel();
    _debounce = null;
  }
}
