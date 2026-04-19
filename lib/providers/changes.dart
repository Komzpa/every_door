// Copyright 2022-2025 Ilya Zverev
// This file is a part of Every Door, distributed under GPL v3 or later version.
// Refer to LICENSE file and https://www.gnu.org/licenses/gpl-3.0.html for details.
import 'package:every_door/models/amenity.dart';
import 'package:every_door/models/osm_element.dart';
import 'package:every_door/providers/database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:sqflite/sqflite.dart';

/// Keeps changes to OSM elements that are persisted in a separate table.
/// All changed are loaded when the app starts, to simplify processing.
/// The value is a total number of changes. Null is they haven't been loaded yet.
final changesProvider = NotifierProvider<ChangesProvider, int?>(ChangesProvider.new);

class ChangesProvider extends Notifier<int?> {
  final Map<OsmId, OsmChange> _changes = {};
  final Map<String, OsmChange> _new = {};

  static final _logger = Logger('ChangesProvider');

  @override
  int? build() => 0;

  Future<void> loadChanges() async {
    final database = await ref.read(databaseProvider).database;
    final rows = await database.rawQuery("""
      select * from ${OsmChange.kTableName} c
      left join ${OsmElement.kTableName} e on c.osmid = e.osmid
    """);
    final broken = <String>[];
    final elements = <OsmChange>[];
    for (final row in rows) {
      try {
        elements.add(OsmChange.fromJson(row));
      } on Error catch (e) {
        _logger.severe('Failed to load osm change $row', e);
        broken.add(row['id'] as String);
      } on Exception catch (e) {
        _logger.severe('Failed to load osm change $row', e);
        broken.add(row['id'] as String);
      }
    }
    if (broken.isNotEmpty) {
      // Delete these elements, since they are not restorable.
      final q = broken.map((e) => '?').join(',');
      await database.delete(OsmChange.kTableName,
          where: 'id in ($q)', whereArgs: broken);
    }
    for (final e in elements) {
      if (e.isNew)
        _new[e.databaseId] = e;
      else
        _changes[e.id] = e;
    }
    _updateLength();
  }

  void _ensureLoaded() {
    if (state == null) throw StateError("Changes were not loaded");
  }

  void _updateLength() {
    state = length;
  }

  OsmChange changeFor(OsmElement element, [bool storeNew = true]) {
    _ensureLoaded();
    OsmChange? change = _changes[element.id];
    if (change != null) {
      if (element.version > change.element!.version) {
        change = change.mergeNewElement(element);
        if (storeNew) saveChange(change);
      }
    }
    return change ?? OsmChange(element);
  }

  List<OsmChange> getNew() {
    return _new.values.toList();
  }

  int get length => _new.length + _changes.length;
  bool get haveErrors =>
      _new.values.any((e) => e.error != null) ||
      _changes.values.any((e) => e.error != null);

  OsmChange operator [](int index) => index < _new.length
      ? _new.values.elementAt(index)
      : _changes.values.elementAt(index - _new.length);

  List<OsmChange> all([bool includeErrored = true]) {
    if (includeErrored) {
      return _new.values.toList() + _changes.values.toList();
    } else {
      return _new.values.where((e) => e.error == null).toList() +
          _changes.values.where((e) => e.error == null).toList();
    }
  }

  List<OsmChange> fetch(Iterable<String> databaseIds) {
    final ids = Set.of(databaseIds);
    List<OsmChange> result = [];
    for (final el in _new.values) {
      if (ids.contains(el.databaseId)) result.add(el);
    }
    for (final el in _changes.values) {
      if (ids.contains(el.databaseId)) result.add(el);
    }
    return result;
  }

  Future<void> saveChange(OsmChange change) async {
    _logger.info('Saving $change');
    if (change.isModified) {
      await _addChange(change);
    } else {
      await deleteChange(change);
    }
  }

  Future<void> setError(OsmChange change, String? error) async {
    if (change.error != error) {
      change.error = error;
      await saveChange(change);
    }
  }

  Future<void> _addChange(OsmChange change) async {
    _ensureLoaded();
    final database = await ref.read(databaseProvider).database;
    change.updated = DateTime.now();
    if (change.isNew)
      _new[change.databaseId] = change;
    else
      _changes[change.id] = change;
    _updateLength();
    await database.insert(
      OsmChange.kTableName,
      change.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteChange(OsmChange change) async {
    _ensureLoaded();
    if (change.isNew) {
      if (!_new.containsKey(change.databaseId)) return;
      _new.remove(change.databaseId);
    } else {
      if (!_changes.containsKey(change.id)) return;
      _changes.remove(change.id);
    }
    _updateLength();

    final database = await ref.read(databaseProvider).database;
    await database.delete(
      OsmChange.kTableName,
      where: 'id = ?',
      whereArgs: [change.databaseId],
    );
  }

  Future<void> clearChanges(
      {bool includeErrored = false, List<String>? ids}) async {
    _ensureLoaded();
    if (includeErrored && ids == null) {
      _new.clear();
      _changes.clear();
    } else {
      // Keep changes with errors or not referenced.
      final idSet = Set.of(ids ?? []);
      _new.removeWhere((key, value) =>
          (includeErrored || value.error == null) &&
          (idSet.isEmpty || idSet.contains(key)));
      _changes.removeWhere((key, value) =>
          (includeErrored || value.error == null) &&
          (idSet.isEmpty || idSet.contains(key.toString())));
    }

    final database = await ref.read(databaseProvider).database;
    final keepIds =
        _changes.keys.map((e) => e.toString()).followedBy(_new.keys).toList();
    if (keepIds.isEmpty) {
      await database.delete(OsmChange.kTableName);
    } else if (keepIds.length < 999) {
      final placeholders =
          List.generate(keepIds.length, (index) => "?").join(",");
      await database.delete(
        OsmChange.kTableName,
        where: 'osmid not in ($placeholders)',
        whereArgs: keepIds,
      );
    } else {
      // The list is too long, use CTE to delete.
      final values = keepIds.map((i) => "('$i')").join(',');
      await database.rawQuery(
          "with t(i) as (values $values) delete from ${OsmChange.kTableName} where osmid not in (select i from t)");
    }

    _updateLength();
  }

  bool haveNoErrorChanges() {
    return _new.values.any((element) => element.error == null) ||
        _changes.values.any((element) => element.error == null);
  }
}
