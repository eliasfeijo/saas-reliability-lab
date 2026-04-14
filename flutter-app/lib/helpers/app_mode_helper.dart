import 'dart:js_interop';

import 'package:flutter/foundation.dart';

// This file is used to configure the app mode for interop with JavaScript.
// It is used to determine the correct service worker to register based on the app mode (debug or release).

@JS()
external set isReleaseMode(JSBoolean value);

void configureAppModeInterop() {
  isReleaseMode = kReleaseMode.toJS;
}
