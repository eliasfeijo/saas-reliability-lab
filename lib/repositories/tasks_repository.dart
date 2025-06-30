import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:todo_flutter/models/task.dart';

abstract class TasksRepository {
  Future<List<TaskModel>> loadTasks();
  Future<void> saveTasks(List<TaskModel> tasks);
  Future<void> clearTasks();
}

class TasksSharedPreferencesRepository implements TasksRepository {
  static const String _key = 'tasks';

  final Future<SharedPreferencesWithCache> _prefs =
      SharedPreferencesWithCache.create(
        cacheOptions: const SharedPreferencesWithCacheOptions(
          // This cache will only accept the key 'tasks'.
          allowList: <String>{_key},
        ),
      );

  @override
  Future<List<TaskModel>> loadTasks() async {
    final SharedPreferencesWithCache prefs = await _prefs;
    final tasksJson = prefs.getStringList(_key) ?? [];
    return tasksJson
        .map((jsonString) => TaskModel.fromJson(json.decode(jsonString)))
        // Filter out tasks that are marked as deleted
        .where((task) => task.syncStatus != SyncStatus.deleted)
        .toList();
  }

  @override
  Future<void> saveTasks(List<TaskModel> tasks) async {
    final SharedPreferencesWithCache prefs = await _prefs;
    final tasksJson = tasks.map((task) => json.encode(task.toJson())).toList();
    await prefs.setStringList(_key, tasksJson);
  }

  @override
  Future<void> clearTasks() async {
    final SharedPreferencesWithCache prefs = await _prefs;
    await prefs.remove(_key);
  }
}
