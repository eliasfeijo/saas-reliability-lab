import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_flutter/models/outbox_entry.dart';

class OutboxStorageState {
  const OutboxStorageState({
    this.isInitialized = false,
    this.activeEntries = const <OutboxEntry>[],
    this.recentAcknowledgements = const <OutboxEntry>[],
  });

  final bool isInitialized;
  final List<OutboxEntry> activeEntries;
  final List<OutboxEntry> recentAcknowledgements;

  OutboxStorageState copyWith({
    bool? isInitialized,
    List<OutboxEntry>? activeEntries,
    List<OutboxEntry>? recentAcknowledgements,
  }) {
    return OutboxStorageState(
      isInitialized: isInitialized ?? this.isInitialized,
      activeEntries: activeEntries ?? this.activeEntries,
      recentAcknowledgements:
          recentAcknowledgements ?? this.recentAcknowledgements,
    );
  }
}

abstract class OutboxRepository {
  Future<OutboxStorageState> loadState();
  Future<void> saveState(OutboxStorageState state);
  Future<void> clearState();
}

class SharedPreferencesOutboxRepository implements OutboxRepository {
  static const String _initializedKey = 'outbox_initialized';
  static const String _activeEntriesKey = 'outbox_active_entries';
  static const String _recentAcknowledgementsKey =
      'outbox_recent_acknowledgements';

  final Future<SharedPreferencesWithCache> _prefs =
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          allowList: <String>{
            _initializedKey,
            _activeEntriesKey,
            _recentAcknowledgementsKey,
          },
        ),
      );

  @override
  Future<void> clearState() async {
    final prefs = await _prefs;
    await prefs.remove(_initializedKey);
    await prefs.remove(_activeEntriesKey);
    await prefs.remove(_recentAcknowledgementsKey);
  }

  @override
  Future<OutboxStorageState> loadState() async {
    final prefs = await _prefs;

    return OutboxStorageState(
      isInitialized: prefs.getBool(_initializedKey) ?? false,
      activeEntries: _decodeEntries(prefs.getStringList(_activeEntriesKey)),
      recentAcknowledgements: _decodeEntries(
        prefs.getStringList(_recentAcknowledgementsKey),
      ),
    );
  }

  @override
  Future<void> saveState(OutboxStorageState state) async {
    final prefs = await _prefs;

    await prefs.setBool(_initializedKey, state.isInitialized);
    await prefs.setStringList(
      _activeEntriesKey,
      _encodeEntries(state.activeEntries),
    );
    await prefs.setStringList(
      _recentAcknowledgementsKey,
      _encodeEntries(state.recentAcknowledgements),
    );
  }

  List<OutboxEntry> _decodeEntries(List<String>? rawEntries) {
    if (rawEntries == null || rawEntries.isEmpty) {
      return const <OutboxEntry>[];
    }

    return rawEntries
        .map(
          (entry) => OutboxEntry.fromJson(
            Map<String, dynamic>.from(json.decode(entry) as Map),
          ),
        )
        .toList(growable: false);
  }

  List<String> _encodeEntries(List<OutboxEntry> entries) {
    return entries
        .map((entry) => json.encode(entry.toJson()))
        .toList(growable: false);
  }
}
