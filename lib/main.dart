import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:todo_flutter/helpers/app_mode_helper.dart';
import 'package:todo_flutter/keys.dart';
import 'package:todo_flutter/providers/agenda_provider.dart';
import 'package:todo_flutter/repositories/tasks_repository.dart';
import 'package:todo_flutter/screens/task_list.dart';
import 'package:todo_flutter/services/push_notification_service.dart';
import 'package:todo_flutter/services/task_sync_service.dart';
import 'package:todo_flutter/services/user_session_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // App mode detection
  configureAppModeInterop();

  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: "https://<your-project-ref>.supabase.co",
  );

  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: "<your-anon-key>",
  );

  // debugPrint('Supabase URL: $supabaseUrl');
  // debugPrint('Supabase Anon Key: $supabaseAnonKey');

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    // Initialize the tasks repository
    final tasksRepository = TasksSharedPreferencesRepository();
    return ChangeNotifierProvider(
      create: (context) => AgendaProvider(
        tasksRepository,
        TaskSyncService(tasksRepository, Supabase.instance.client),
        PushNotificationService(Supabase.instance.client),
        UserSessionService(),
      ),
      child: MaterialApp(
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        title: 'Agenda',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const TaskList(),
      ),
    );
  }
}
