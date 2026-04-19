// Copyright 2022-2025 Ilya Zverev
// This file is a part of Every Door, distributed under GPL v3 or later version.
// Refer to LICENSE file and https://www.gnu.org/licenses/gpl-3.0.html for details.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

final needMapUpdateProvider = NotifierProvider(NeedMapUpdateProvider.new);

/// Simple provider to notify the POI list that it needs to be updated.
class NeedMapUpdateProvider extends Notifier<bool> {
  @override
  bool build() => false;

  /// Calls notifyListeners().
  void trigger() {
    ref.notifyListeners();
  }
}