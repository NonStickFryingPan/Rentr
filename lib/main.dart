import 'package:flutter/material.dart';
import 'services/rentry_client.dart';
import 'services/storage_service.dart';
import 'services/settings_service.dart';
import 'services/notes_notifier.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize storage and settings services
  await SettingsService.init();
  final storageService = StorageService();
  await storageService.init();
  final rentryClient = RentryClient();
  
  // Initialize state notifier and load existing cached notes
  final notesNotifier = NotesNotifier(storageService, rentryClient);
  await notesNotifier.loadNotes();

  runApp(RentryApp(notesNotifier: notesNotifier));
}

class RentryApp extends StatelessWidget {
  final NotesNotifier notesNotifier;

  const RentryApp({super.key, required this.notesNotifier});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rentr',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF90CAF9),
          surface: const Color(0xFFF8FAFC),
        ),
        fontFamily: 'sans-serif',
      ),
      home: HomeScreen(notesNotifier: notesNotifier),
    );
  }
}
