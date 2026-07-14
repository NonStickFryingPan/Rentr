import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/note.dart';

class StorageService {
  Directory? _docsDir;
  Directory? _notesDir;
  File? _indexFile;

  // Initialize directory paths and folders
  Future<void> init() async {
    _docsDir = await getApplicationDocumentsDirectory();
    _notesDir = Directory('${_docsDir!.path}/notes');
    if (!await _notesDir!.exists()) {
      await _notesDir!.create(recursive: true);
    }
    _indexFile = File('${_docsDir!.path}/index.json');
  }

  // Load the index of note metadata from index.json
  Future<List<Note>> getNotes() async {
    if (_indexFile == null) await init();
    
    if (!await _indexFile!.exists()) {
      return [];
    }
    
    try {
      final jsonString = await _indexFile!.readAsString();
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((item) => Note.fromJson(item)).toList();
    } catch (e) {
      // In case of corrupt or invalid JSON, return empty and allow overwrite
      return [];
    }
  }

  // Read note markdown body from its corresponding .txt file
  Future<String> getNoteContent(String url) async {
    if (_notesDir == null) await init();
    
    final file = File('${_notesDir!.path}/$url.txt');
    if (await file.exists()) {
      return await file.readAsString();
    }
    return '';
  }

  // Save note metadata to index.json and content to a .txt file
  Future<void> saveNote(Note note, String content) async {
    if (_indexFile == null) await init();

    // 1. Write the content text to notes/{url}.txt
    await saveNoteContentOnly(note, content);

    // 2. Read the existing notes list, update or add the note metadata
    final notes = await getNotes();
    final index = notes.indexWhere((n) => n.url == note.url);

    if (index >= 0) {
      notes[index] = note;
    } else {
      notes.add(note);
    }

    // 3. Save notes list back to index.json
    await saveNotesIndex(notes);
  }

  // Write the note body content only to notes/{url}.txt
  Future<void> saveNoteContentOnly(Note note, String content) async {
    if (_notesDir == null) await init();
    final contentFile = File('${_notesDir!.path}/${note.url}.txt');
    await contentFile.writeAsString(content);
  }

  // Save the entire list of notes to index.json in a single batch write
  Future<void> saveNotesIndex(List<Note> notes) async {
    if (_indexFile == null) await init();
    final jsonList = notes.map((n) => n.toJson()).toList();
    await _indexFile!.writeAsString(jsonEncode(jsonList));
  }

  // Delete note metadata and its .txt content file
  Future<void> deleteNote(String url) async {
    if (_indexFile == null) await init();

    // 1. Delete notes/{url}.txt content file
    final contentFile = File('${_notesDir!.path}/$url.txt');
    if (await contentFile.exists()) {
      await contentFile.delete();
    }

    // 2. Remove the note metadata from index and update index.json
    final notes = await getNotes();
    notes.removeWhere((n) => n.url == url);

    final jsonList = notes.map((n) => n.toJson()).toList();
    await _indexFile!.writeAsString(jsonEncode(jsonList));
  }
}
