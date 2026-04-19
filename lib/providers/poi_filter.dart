// Copyright 2022-2025 Ilya Zverev
// This file is a part of Every Door, distributed under GPL v3 or later version.
// Refer to LICENSE file and https://www.gnu.org/licenses/gpl-3.0.html for details.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:every_door/models/filter.dart';

final poiFilterProvider = NotifierProvider<PoiFilterNotifier, PoiFilter>(PoiFilterNotifier.new);

class PoiFilterNotifier extends Notifier<PoiFilter> {
  @override
  PoiFilter build() => PoiFilter();

  void set(PoiFilter filter) {
    state = filter;
  }

  void reset() {
    state = PoiFilter();
  }
}
