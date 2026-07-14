import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/note.dart';
import '../services/notes_notifier.dart';
import '../services/settings_service.dart';
import 'editor_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/update_service.dart';
import '../services/error_helper.dart';

class HomeScreen extends StatefulWidget {
  final NotesNotifier notesNotifier;

  const HomeScreen({super.key, required this.notesNotifier});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _appVersion = '1.3.0';

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    // Pull updates from Rentry.co automatically on app startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.notesNotifier.pullAllNotes().catchError((e) {
        debugPrint('HomeScreen: Startup pull failed: $e');
      });
      // Check for updates off of GitHub releases
      UpdateService.checkForUpdates(context);
    });
  }

  Future<void> _loadAppVersion() async {
    final version = await UpdateService.getCurrentVersion();
    if (mounted) {
      setState(() {
        _appVersion = version;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Open the markdown editor for a note (whether new or existing)
  void _openEditor(Note note) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EditorScreen(
          note: note,
          notesNotifier: widget.notesNotifier,
        ),
      ),
    );
  }

  // Delete a note locally after user confirmation
  void _deleteNote(Note note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Note'),
        content: Text('Are you sure you want to delete "${note.title}" locally? This does not delete it from Rentry.co.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final rootContext = context;
              Navigator.of(context).pop();
              await widget.notesNotifier.deleteNote(note.url);
              if (rootContext.mounted) {
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  const SnackBar(content: Text('Note deleted locally')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Manually post (push) an unsynced note to Rentry.co
  Future<void> _postNote(Note note) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Posting "${note.url}" to Rentry.co...')),
    );
    try {
      await widget.notesNotifier.postNote(note.url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${note.title}" posted successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Post Error'),
            content: Text(cleanErrorMessage(e)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              )
            ],
          ),
        );
      }
    }
  }

  // Show bottom sheet to configure default edit code
  void _showSettingsBottomSheet() {
    final controller = TextEditingController(text: SettingsService.getDefaultEditCode());
    final rootContext = context;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 24,
          right: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                )
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Default Edit Code',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Enter default edit code for new notes',
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                await SettingsService.setDefaultEditCode(controller.text);
                if (context.mounted) {
                  Navigator.pop(context);
                }
                if (rootContext.mounted) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    const SnackBar(content: Text('Settings saved successfully')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
             const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'App Version & Updates',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54),
                ),
                 Text(
                  'v$_appVersion',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Check for Updates Row
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.refresh, color: Color(0xFF0F172A)),
              ),
              title: const Text('Check for Updates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Check GitHub for latest release versions', style: TextStyle(fontSize: 12)),
              onTap: () {
                Navigator.pop(context); // Dismiss the sheet first
                UpdateService.checkForUpdates(rootContext, showFeedback: true);
              },
            ),
            // GitHub Releases Row
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.open_in_browser, color: Color(0xFF0F172A)),
              ),
              title: const Text('View GitHub Releases', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Open repository releases in system browser', style: TextStyle(fontSize: 12)),
              onTap: () async {
                Navigator.pop(context); // Dismiss the sheet first
                final uri = Uri.parse(UpdateService.webReleaseUrl);
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (e) {
                  debugPrint('Failed to launch URL: $e');
                  if (rootContext.mounted) {
                    ScaffoldMessenger.of(rootContext).showSnackBar(
                      const SnackBar(content: Text('Could not open releases in browser.')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Open Dialog for importing or creating notes
  void _showAddNotesDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Add Note',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.add_circle_outline, color: Colors.blue),
              ),
              title: const Text('Create New Note', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Claim a new URL slug and edit code'),
              onTap: () {
                Navigator.pop(context);
                _showCreateNoteDialog();
              },
            ),
            const Divider(height: 24),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud_download_outlined, color: Colors.green),
              ),
              title: const Text('Import Existing Note', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Load note from Rentry using its slug'),
              onTap: () {
                Navigator.pop(context);
                _showImportNoteDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  // Dialog for creating a new note (with real-time availability check)
  void _showCreateNoteDialog() {
    final urlController = TextEditingController();
    final editCodeController = TextEditingController(text: SettingsService.getDefaultEditCode());
    
    bool? isAvailable;
    bool isChecking = false;
    Timer? debounce;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            void checkUrl(String url) {
              if (debounce?.isActive ?? false) debounce!.cancel();
              if (url.trim().isEmpty) {
                setState(() {
                  isAvailable = null;
                  isChecking = false;
                });
                return;
              }

              setState(() {
                isChecking = true;
              });

               final currentText = url.trim();
              debounce = Timer(const Duration(milliseconds: 500), () async {
                try {
                  final result = await widget.notesNotifier.checkUrlAvailability(currentText);
                  if (context.mounted && urlController.text.trim() == currentText) {
                    setState(() {
                      isChecking = false;
                      isAvailable = result;
                    });
                  }
                } catch (e) {
                  debugPrint('URL check error: $e');
                  if (context.mounted && urlController.text.trim() == currentText) {
                    setState(() {
                      isChecking = false;
                      isAvailable = null;
                    });
                  }
                }
              });
            }

            return AlertDialog(
              title: const Text('Create New Note'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: urlController,
                    onChanged: checkUrl,
                    decoration: InputDecoration(
                      labelText: 'URL Slug',
                      hintText: 'e.g. my-private-note',
                      suffixIcon: isChecking
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : isAvailable == null
                              ? null
                              : isAvailable!
                                  ? const Icon(Icons.check_circle, color: Colors.green)
                                  : const Icon(Icons.cancel, color: Colors.red),
                    ),
                  ),
                  if (isAvailable != null && !isChecking)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        isAvailable! ? '✓ URL is available' : '✗ URL is already taken',
                        style: TextStyle(
                          color: isAvailable! ? Colors.green : Colors.red,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: editCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Edit Code (Password)',
                      hintText: 'Keep it safe',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    debounce?.cancel();
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (isAvailable == true && !isChecking)
                      ? () {
                          Navigator.pop(context);
                          final newNote = Note(
                            url: urlController.text.trim(),
                            editCode: editCodeController.text.trim(),
                            title: 'New Note',
                            updatedAt: DateTime.now(),
                            isSynced: false,
                            colorValue: NotesNotifier.cardColors[
                                DateTime.now().millisecond % NotesNotifier.cardColors.length],
                            metadata: '',
                          );
                          _openEditor(newNote);
                        }
                      : null,
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Dialog for importing an existing note
  void _showImportNoteDialog() {
    final urlController = TextEditingController();
    final editCodeController = TextEditingController(text: SettingsService.getDefaultEditCode());
    bool isImporting = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Import Note from Rentry'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlController,
                    decoration: const InputDecoration(
                      labelText: 'Rentry URL Slug',
                      hintText: 'e.g. some-custom-slug',
                    ),
                    enabled: !isImporting,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: editCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Edit Code',
                      hintText: 'Passcode (Optional to read, required to save)',
                    ),
                    enabled: !isImporting,
                  ),
                  if (isImporting)
                    const Padding(
                      padding: EdgeInsets.only(top: 16.0),
                      child: CircularProgressIndicator(),
                    )
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isImporting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isImporting
                      ? null
                      : () async {
                          final slug = urlController.text.trim();
                          if (slug.isEmpty) return;
                          
                          setState(() {
                            isImporting = true;
                          });

                          try {
                            await widget.notesNotifier.importExistingNote(
                              slug,
                              editCodeController.text.trim(),
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Note "$slug" imported successfully')),
                              );
                            }
                          } catch (e) {
                            setState(() {
                              isImporting = false;
                            });
                            if (context.mounted) {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Import Error'),
                                  content: Text(cleanErrorMessage(e)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('OK'),
                                    )
                                  ],
                                ),
                              );
                            }
                          }
                        },
                  child: const Text('Import'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Format date time beautifully
  String _formatDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} $hour:$minute $ampm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Custom Dashboard Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Notes',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Manage your Rentry notes',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[500],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _showSettingsBottomSheet,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: const Icon(
                        Icons.settings_outlined,
                        color: Color(0xFF0F172A),
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Premium Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim().toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search notes...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14.0),
                  ),
                ),
              ),
            ),

            // Scrollable List of Notes with Overlapping Cascading Cards (Option A)
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  await widget.notesNotifier.pullAllNotes();
                },
                child: ValueListenableBuilder<List<Note>>(
                  valueListenable: widget.notesNotifier,
                  builder: (context, notes, child) {
                    final filteredNotes = notes.where((note) {
                      return note.title.toLowerCase().contains(_searchQuery) ||
                          note.url.toLowerCase().contains(_searchQuery);
                    }).toList();
  
                    if (filteredNotes.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _searchQuery.isEmpty ? Icons.note_alt_outlined : Icons.search_off_outlined,
                                    size: 72,
                                    color: Colors.grey[300],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isEmpty
                                        ? 'No notes yet. Tap + to add one.'
                                        : 'No matching notes found.',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey[500],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }
  
                    return ListView.builder(
                      padding: const EdgeInsets.only(
                        left: 24,
                        right: 24,
                        top: 16,
                        bottom: 120, // Bottom padding to accommodate FAB and shingle layout bounds
                      ),
                      itemCount: filteredNotes.length,
                      itemBuilder: (context, index) {
                      final note = filteredNotes[index];
                      
                      // Using Align with heightFactor to create the overlapping Bottom-over-Top shingle cascade
                      return Align(
                        alignment: Alignment.topCenter,
                        heightFactor: 0.76, 
                        child: GestureDetector(
                          onTap: () => _openEditor(note),
                          onLongPress: () {
                            final link = 'https://rentry.co/${note.url}';
                            Clipboard.setData(ClipboardData(text: link));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied link: $link'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Container(
                            height: 140, // Uniform card height for consistent cascading alignment
                            margin: const EdgeInsets.only(bottom: 16),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Color(note.colorValue),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 16,
                                  offset: const Offset(0, 8),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Card Top Metadata Row
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDate(note.updatedAt),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black.withOpacity(0.4),
                                      ),
                                    ),
                                    // Sync State Icon Indicator
                                    Row(
                                      children: [
                                        if (!note.isSynced)
                                          GestureDetector(
                                            onTap: () => _postNote(note),
                                            child: Container(
                                              margin: const EdgeInsets.only(right: 8),
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.orange[800]!.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Row(
                                                children: [
                                                  Icon(Icons.publish, color: Colors.orange[800], size: 12),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'POST',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: Colors.orange[800],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        Icon(
                                          note.isSynced ? Icons.cloud_done : Icons.cloud_off,
                                          color: note.isSynced
                                              ? Colors.black.withOpacity(0.4)
                                              : Colors.orange[800],
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                
                                // Card Middle Main Title
                                Text(
                                  note.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.5,
                                  ),
                                ),

                                // Card Bottom Action bar
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    // URL slug tag
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'rentry.co/${note.url}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                    ),
                                    // Quick action buttons
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, size: 20),
                                          color: Colors.black.withOpacity(0.5),
                                          onPressed: () => _deleteNote(note),
                                        ),
                                      ],
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.large(
        onPressed: _showAddNotesDialog,
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: const Icon(Icons.add, size: 36),
      ),
    );
  }
}


