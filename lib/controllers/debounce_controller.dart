import 'dart:async';

import 'package:flutter/foundation.dart';

class DebounceController {
  final Duration debounceDuration;
  Timer? _debounce;

  DebounceController({this.debounceDuration = const Duration(seconds: 3)});

  void trigger(VoidCallback action) {
    _debounce?.cancel();
    _debounce = Timer(debounceDuration, action);
  }

  void cancel() {
    _debounce?.cancel();
    _debounce = null;
  }
}
