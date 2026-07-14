import 'package:flutter/foundation.dart';
import 'dart:math';
import '../models/note.dart';
import 'rentry_client.dart';
import 'storage_service.dart';

class NotesNotifier extends ValueNotifier<List<Note>> {
  final StorageService _storageService;
  final RentryClient _rentryClient;

  NotesNotifier(this._storageService, this._rentryClient) : super([]);

  // Curated elegant pastel colors for cascading cards style
  static const List<int> cardColors = [
    0xFFF48FB1, // Elegant Pink
    0xFFCE93D8, // Muted Lavender/Purple
    0xFF9FA8DA, // Soft Indigo
    0xFF90CAF9, // Sky Blue
    0xFF80DEEA, // Teal/Cyan
    0xFFA5D6A7, // Soft Green
    0xFFFFF59D, // Pastel Yellow
    0xFFFFCC80, // Soft Orange
  ];

  // Helper to extract a friendly title from markdown body
  String _extractTitle(String content) {
    if (content.trim().isEmpty) return 'Empty Note';
    final lines = content.trim().split('\n');
    for (var line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.isNotEmpty) {
        // Strip markdown heading symbols (#, ##, etc.) for title display
        return cleanLine.replaceFirst(RegExp(r'^#+\s*'), '');
      }
    }
    return 'Untitled Note';
  }

  // Choose a random color value from our palette
  int _getRandomColor() {
    final random = Random();
    return cardColors[random.nextInt(cardColors.length)];
  }

  // Load all notes from storage
  Future<void> loadNotes() async {
    final notes = await _storageService.getNotes();
    // Sort notes so that the most recently updated notes appear first or last
    // Let's sort with newest on top (as in index card layouts)
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    value = notes;
  }

  // Import an existing note from Rentry.co
  Future<void> importExistingNote(String url, String editCode) async {
    // 1. Fetch content from Rentry
    final rawData = await _rentryClient.fetchRawContent(url);
    final content = rawData['content'] ?? '';
    final metadata = rawData['metadata'] ?? '';
    
    // 2. Create note object
    final note = Note(
      url: url,
      editCode: editCode,
      title: _extractTitle(content),
      updatedAt: DateTime.now(),
      isSynced: true,
      colorValue: _getRandomColor(),
      metadata: metadata,
    );

    // 3. Save to local storage and refresh list
    await _storageService.saveNote(note, content);
    await loadNotes();
  }

  // Create a brand new note on Rentry.co
  Future<void> createNewNote(String url, String editCode, String content) async {
    // 1. Verify URL is free on Rentry.co
    final isAvailable = await _rentryClient.checkUrlAvailability(url);
    if (!isAvailable) {
      throw Exception('The URL name "$url" is already taken on Rentry.co');
    }

    // 2. Upload to Rentry.co (starts with empty metadata)
    final actualEditCode = await _rentryClient.createNote(url, editCode, content, '');

    // 3. Save metadata and content locally
    final note = Note(
      url: url,
      editCode: actualEditCode,
      title: _extractTitle(content),
      updatedAt: DateTime.now(),
      isSynced: true,
      colorValue: _getRandomColor(),
      metadata: '',
    );

    await _storageService.saveNote(note, content);
    await loadNotes();
  }

  // Save note locally (handles both updating existing and saving new local notes offline)
  Future<void> saveNoteOffline(Note note, String content) async {
    final updatedNote = note.copyWith(
      title: _extractTitle(content),
      updatedAt: DateTime.now(),
      isSynced: false,
    );
    await _storageService.saveNote(updatedNote, content);
    await loadNotes();
  }

  // Update note content locally (marks it as unsynced)
  Future<void> updateNoteOffline(String url, String content) async {
    final notes = value;
    final index = notes.indexWhere((n) => n.url == url);
    if (index == -1) throw Exception('Note not found in local index');

    final oldNote = notes[index];
    final updatedNote = oldNote.copyWith(
      title: _extractTitle(content),
      updatedAt: DateTime.now(),
      isSynced: false,
    );

    await _storageService.saveNote(updatedNote, content);
    await loadNotes();
  }

  // Post (push) local content to Rentry.co (creates note if available/new, else edits it)
  Future<void> postNote(String url) async {
    final notes = value;
    final index = notes.indexWhere((n) => n.url == url);
    if (index == -1) throw Exception('Note not found in local index');

    final note = notes[index];
    final content = await _storageService.getNoteContent(url);

    // If URL is free, it doesn't exist on Rentry, so we must CREATE it.
    // Otherwise, we EDIT it.
    final isAvailable = await _rentryClient.checkUrlAvailability(url);

    if (isAvailable) {
      // Create new note on Rentry
      await _rentryClient.createNote(url, note.editCode, content, note.metadata);
    } else {
      // Edit existing note on Rentry
      await _rentryClient.editNote(url, note.editCode, content, note.metadata);
    }

    // Update note state as synced
    final syncedNote = note.copyWith(
      updatedAt: DateTime.now(),
      isSynced: true,
    );

    await _storageService.saveNote(syncedNote, content);
    await loadNotes();
  }

  // Pull content from Rentry.co (overwrites local content and metadata with Rentry version)
  Future<void> pullNote(String url) async {
    final notes = value;
    final index = notes.indexWhere((n) => n.url == url);
    if (index == -1) throw Exception('Note not found in local index');

    final note = notes[index];
    
    // Fetch latest content and metadata from Rentry.co
    final rawData = await _rentryClient.fetchRawContent(url);
    final content = rawData['content'] ?? '';
    final metadata = rawData['metadata'] ?? '';

    // Create updated note state (synced with Rentry content)
    final pulledNote = note.copyWith(
      title: _extractTitle(content),
      updatedAt: DateTime.now(),
      isSynced: true,
      metadata: metadata,
    );

    await _storageService.saveNote(pulledNote, content);
    await loadNotes();
  }

  // Pull updates for all saved notes (used on startup or pull-to-refresh)
  Future<void> pullAllNotes() async {
    final notesCopy = List<Note>.from(value);
    
    // 1. Fetch content for all notes in parallel
    final results = await Future.wait(
      notesCopy.map((note) async {
        try {
          final rawData = await _rentryClient.fetchRawContent(note.url);
          final content = rawData['content'] ?? '';
          final metadata = rawData['metadata'] ?? '';

          final pulledNote = note.copyWith(
            title: _extractTitle(content),
            updatedAt: DateTime.now(),
            isSynced: true,
            metadata: metadata,
          );

          return _PulledNoteResult(note: pulledNote, content: content);
        } catch (e) {
          // Suppress errors for offline or deleted notes to not crash the batch pull
          debugPrint('Error pulling note ${note.url}: $e');
          return null;
        }
      }),
    );

    // 2. Filter out failed pulls and apply changes in a batch
    final successfulResults = results.whereType<_PulledNoteResult>().toList();
    if (successfulResults.isEmpty) return;

    // Save individual contents and update list index
    final updatedNotes = List<Note>.from(value);
    for (final result in successfulResults) {
      await _storageService.saveNoteContentOnly(result.note, result.content);
      
      final idx = updatedNotes.indexWhere((n) => n.url == result.note.url);
      if (idx != -1) {
        updatedNotes[idx] = result.note;
      }
    }

    // Save index once to disk, preventing race condition overwrites
    await _storageService.saveNotesIndex(updatedNotes);
    await loadNotes();
  }

  // Get contents of a note by URL
  Future<String> getNoteContent(String url) async {
    return await _storageService.getNoteContent(url);
  }

  // Delete note locally
  Future<void> deleteNote(String url) async {
    await _storageService.deleteNote(url);
    await loadNotes();
  }

  // Check URL availability on Rentry.co
  Future<bool> checkUrlAvailability(String url) async {
    return await _rentryClient.checkUrlAvailability(url);
  }
}

// Private helper to store concurrent pull results before batch saving
class _PulledNoteResult {
  final Note note;
  final String content;
  _PulledNoteResult({required this.note, required this.content});
}
