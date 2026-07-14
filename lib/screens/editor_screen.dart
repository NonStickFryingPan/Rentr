import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/note.dart';
import '../services/notes_notifier.dart';

class EditorScreen extends StatefulWidget {
  final Note note;
  final NotesNotifier notesNotifier;

  const EditorScreen({
    super.key,
    required this.note,
    required this.notesNotifier,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _editScrollController = ScrollController();
  final ScrollController _previewScrollController = ScrollController();
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSyncing = false;
  bool _isPreviewMode = false;
  bool _isFloatingPanelVisible = true;

  Timer? _autosaveTimer;
  Timer? _visibilityTimer;
  String _initialContent = '';
  late Note _currentNoteState;
  bool _isSaveInProgress = false;
  bool _needsAutosave = false;

  @override
  void initState() {
    super.initState();
    _currentNoteState = widget.note;
    _loadContent();
    _textController.addListener(_onTextChanged);
    _textController.addListener(_onUserInteraction);
    _editScrollController.addListener(_onUserInteraction);
    _previewScrollController.addListener(_onUserInteraction);
    
    // Start initial visibility timer
    _onUserInteraction();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _visibilityTimer?.cancel();
    _textController.removeListener(_onTextChanged);
    _textController.removeListener(_onUserInteraction);
    _editScrollController.dispose();
    _previewScrollController.dispose();
    _textController.dispose();
    super.dispose();
  }

  // Monitor user interaction to show/hide the floating button
  void _onUserInteraction() {
    if (!mounted) return;
    
    if (!_isFloatingPanelVisible) {
      setState(() {
        _isFloatingPanelVisible = true;
      });
    }

    _visibilityTimer?.cancel();
    _visibilityTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isFloatingPanelVisible = false;
        });
      }
    });
  }

  // Load the note content from disk
  Future<void> _loadContent() async {
    try {
      final content = await widget.notesNotifier.getNoteContent(widget.note.url);
      if (mounted) {
        setState(() {
          _textController.text = content;
          _initialContent = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('EditorScreen: Failed to load content: $e');
      if (mounted) {
        setState(() {
          _textController.text = '';
          _initialContent = '';
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load note content: $e')),
        );
      }
    }
  }

  // Handle typing changes with debounced 1-second autosave
  void _onTextChanged() {
    if (_textController.text == _initialContent) return;

    if (_autosaveTimer?.isActive ?? false) _autosaveTimer!.cancel();
    
    _autosaveTimer = Timer(const Duration(milliseconds: 1000), () {
      _triggerAutosave();
    });
  }

  Future<void> _triggerAutosave() async {
    if (!mounted) return;
    if (_isSaveInProgress) {
      _needsAutosave = true;
      return;
    }

    _isSaveInProgress = true;
    if (mounted) {
      setState(() {
        _isSaving = true;
      });
    }

    try {
      await widget.notesNotifier.saveNoteOffline(_currentNoteState, _textController.text);
      
      // Retrieve the updated Note state from notifier list (e.g. title changed)
      final notes = widget.notesNotifier.value;
      final index = notes.indexWhere((n) => n.url == _currentNoteState.url);
      if (index != -1 && mounted) {
        setState(() {
          _currentNoteState = notes[index];
        });
      }
      _initialContent = _textController.text;
    } catch (e) {
      debugPrint('Autosave error: $e');
    } finally {
      _isSaveInProgress = false;
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
      if (_needsAutosave) {
        _needsAutosave = false;
        _triggerAutosave();
      }
    }
  }

  // POST local changes to Rentry.co
  Future<void> _postToRentry() async {
    _onUserInteraction();

    if (_autosaveTimer?.isActive ?? false) {
      _autosaveTimer!.cancel();
      await widget.notesNotifier.saveNoteOffline(_currentNoteState, _textController.text);
      _initialContent = _textController.text;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      final index = widget.notesNotifier.value.indexWhere((n) => n.url == _currentNoteState.url);
      if (index == -1) {
        await widget.notesNotifier.saveNoteOffline(_currentNoteState, _textController.text);
      }

      await widget.notesNotifier.postNote(_currentNoteState.url);

      final notes = widget.notesNotifier.value;
      final newIndex = notes.indexWhere((n) => n.url == _currentNoteState.url);
      if (newIndex != -1) {
        setState(() {
          _currentNoteState = notes[newIndex];
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Note posted successfully to Rentry.co!')),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Post Failed'),
            content: Text(e.toString().replaceAll('Exception: ', '')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              )
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  // Pull latest content from Rentry.co
  Future<void> _pullFromRentry() async {
    _onUserInteraction();
    
    final hasUnsavedChanges = _textController.text != _initialContent;
    
    if (hasUnsavedChanges) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard Local Draft?'),
          content: const Text(
            'Pulling from Rentry will overwrite your unsaved local modifications with the version currently online. Are you sure you want to proceed?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Pull & Overwrite', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;
    }

    setState(() {
      _isSyncing = true;
    });

    try {
      await widget.notesNotifier.pullNote(_currentNoteState.url);
      await _loadContent();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pulled latest version from Rentry.co!')),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pull Failed'),
            content: Text(e.toString().replaceAll('Exception: ', '')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              )
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnsavedChanges = _textController.text != _initialContent;
    final isSynced = _currentNoteState.isSynced && !hasUnsavedChanges;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF0F172A)),
          onPressed: () async {
            if (hasUnsavedChanges) {
              _autosaveTimer?.cancel();
              await widget.notesNotifier.saveNoteOffline(_currentNoteState, _textController.text);
            }
            if (context.mounted) {
              Navigator.pop(context);
            }
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'rentry.co/${_currentNoteState.url}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSynced
                        ? Colors.green
                        : _isSaving
                            ? Colors.blue
                            : Colors.orange,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  isSynced
                      ? 'Synced'
                      : _isSaving
                          ? 'Saving locally...'
                          : 'Unsaved local draft',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.only(right: 20.0),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // sliding Segment Write/Preview Toggle Tab
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2F6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isPreviewMode = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: !_isPreviewMode ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: !_isPreviewMode
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Text(
                                'Write',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: !_isPreviewMode ? const Color(0xFF0F172A) : Colors.grey[500],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _isPreviewMode = true;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              decoration: BoxDecoration(
                                color: _isPreviewMode ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: _isPreviewMode
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.04),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              child: Text(
                                'Preview',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: _isPreviewMode ? const Color(0xFF0F172A) : Colors.grey[500],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Editor or Preview Area
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: !_isPreviewMode
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20.0),
                            child: TextField(
                              controller: _textController,
                              scrollController: _editScrollController,
                              maxLines: null,
                              expands: true,
                              keyboardType: TextInputType.multiline,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 16,
                                height: 1.5,
                                color: Color(0xFF1E293B),
                              ),
                              decoration: const InputDecoration(
                                hintText: 'Start typing markdown here...',
                                border: InputBorder.none,
                              ),
                            ),
                          )
                        : Markdown(
                            controller: _previewScrollController,
                            data: _textController.text.isEmpty
                                ? '*No content to preview*'
                                : _textController.text,
                            selectable: true,
                            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                              p: const TextStyle(fontSize: 16, height: 1.6, color: Color(0xFF334155)),
                              code: const TextStyle(
                                backgroundColor: Color(0xFFEEF2F6),
                                fontFamily: 'monospace',
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                            ),
                            onTapLink: (text, href, title) {
                              if (href != null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Opening Link: $href')),
                                );
                              }
                            },
                          ),
                  ),
                ),
              ],
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _isLoading
          ? null
          : AnimatedOpacity(
              opacity: _isFloatingPanelVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 300),
              child: IgnorePointer(
                ignoring: !_isFloatingPanelVisible,
                child: Container(
                  height: 54,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(27),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // POST button
                      InkWell(
                        onTap: _isSyncing ? null : _postToRentry,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(27),
                          bottomLeft: Radius.circular(27),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _isSyncing
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Icon(Icons.publish, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              const Text(
                                'POST',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 24,
                        color: Colors.white24,
                      ),
                      // Pull Dropdown Menu
                      Theme(
                        data: Theme.of(context).copyWith(
                          popupMenuTheme: const PopupMenuThemeData(
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        child: PopupMenuButton<String>(
                          color: const Color(0xFF0F172A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          icon: const Icon(Icons.arrow_drop_up, color: Colors.white, size: 24),
                          tooltip: 'More actions',
                          offset: const Offset(0, -96), // Adjusted to pop up safely above
                          onSelected: (value) {
                            if (value == 'sync') {
                              _pullFromRentry();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem<String>(
                              value: 'sync',
                              child: Row(
                                children: [
                                  Icon(Icons.sync, color: Colors.white, size: 18),
                                  SizedBox(width: 8),
                                  Text(
                                    'Sync (Pull)',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
