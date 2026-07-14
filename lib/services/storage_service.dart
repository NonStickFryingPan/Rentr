import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';

class StorageService {
  Directory? _docsDir;
  Directory? _notesDir;
  File? _indexFile;

  // Mutex lock to serialize all operations reading/writing index.json
  Future<void>? _indexLock;

  Future<T> _synchronized<T>(Future<T> Function() action) async {
    final previous = _indexLock;
    final completer = Completer<void>();
    _indexLock = completer.future;

    if (previous != null) {
      try {
        await previous;
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  // Initialize directory paths and folders
  Future<void> init() async {
    _docsDir = await getApplicationDocumentsDirectory();
    _notesDir = Directory('${_docsDir!.path}/notes');
    if (!await _notesDir!.exists()) {
      await _notesDir!.create(recursive: true);
    }
    _indexFile = File('${_docsDir!.path}/index.json');
  }

  // Sanitizes the URL slug to prevent directory traversal attacks (../)
  File _safeFile(String url) {
    final cleanUrl = url.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '');
    return File('${_notesDir!.path}/$cleanUrl.txt');
  }

  // Private raw getter for index list (used inside synchronized blocks to avoid deadlocks)
  Future<List<Note>> _getNotesRaw() async {
    if (_indexFile == null) await init();
    
    if (!await _indexFile!.exists()) {
      return [];
    }
    
    try {
      final jsonString = await _indexFile!.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      final List<Note> loadedNotes = [];
      for (final item in jsonList) {
        try {
          loadedNotes.add(Note.fromJson(item));
        } catch (e) {
          debugPrint('StorageService: Skipping corrupt index entry: $e');
        }
      }
      return loadedNotes;
    } catch (e) {
      // In case of corrupt or invalid JSON file, return empty and allow overwrite
      return [];
    }
  }

  // Private raw saver for index list (used inside synchronized blocks to avoid deadlocks)
  Future<void> _saveNotesIndexRaw(List<Note> notes) async {
    if (_indexFile == null) await init();
    final jsonList = notes.map((n) => n.toJson()).toList();
    await _indexFile!.writeAsString(jsonEncode(jsonList));
  }

  // Private raw saver for note body (isolated write)
  Future<void> _saveNoteContentOnlyRaw(Note note, String content) async {
    if (_notesDir == null) await init();
    final contentFile = _safeFile(note.url);
    await contentFile.writeAsString(content);
  }

  // Load the index of note metadata from index.json
  Future<List<Note>> getNotes() async {
    return await _synchronized(() => _getNotesRaw());
  }

  // Read note markdown body from its corresponding .txt file
  Future<String> getNoteContent(String url) async {
    if (_notesDir == null) await init();
    
    final file = _safeFile(url);
    if (await file.exists()) {
      return await file.readAsString();
    }
    return '';
  }

  // Save note metadata to index.json and content to a .txt file
  Future<void> saveNote(Note note, String content) async {
    await _synchronized(() async {
      // 1. Write the content text to notes/{url}.txt
      await _saveNoteContentOnlyRaw(note, content);

      // 2. Read the existing notes list, update or add the note metadata
      final notes = await _getNotesRaw();
      final index = notes.indexWhere((n) => n.url == note.url);

      if (index >= 0) {
        notes[index] = note;
      } else {
        notes.add(note);
      }

      // 3. Save notes list back to index.json
      await _saveNotesIndexRaw(notes);
    });
  }

  // Write the note body content only to notes/{url}.txt
  Future<void> saveNoteContentOnly(Note note, String content) async {
    await _saveNoteContentOnlyRaw(note, content);
  }

  // Save the entire list of notes to index.json in a single batch write
  Future<void> saveNotesIndex(List<Note> notes) async {
    await _synchronized(() => _saveNotesIndexRaw(notes));
  }

  // Delete note metadata and its .txt content file
  Future<void> deleteNote(String url) async {
    await _synchronized(() async {
      // 1. Delete notes/{url}.txt content file
      final contentFile = _safeFile(url);
      if (await contentFile.exists()) {
        await contentFile.delete();
      }

      // 2. Remove the note metadata from index and update index.json
      final notes = await _getNotesRaw();
      notes.removeWhere((n) => n.url == url);

      await _saveNotesIndexRaw(notes);
    });
  }
}
