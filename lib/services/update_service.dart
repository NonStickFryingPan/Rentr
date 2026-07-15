import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdateService {
  static const String repoUrl = 'https://api.github.com/repos/NonStickFryingPan/Rentr/releases/latest';
  static const String webReleaseUrl = 'https://github.com/NonStickFryingPan/Rentr/releases/latest';

  // Fetch package version dynamically from the platform
  static Future<String> getCurrentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '1.3.0';
    }
  }

  // Check for updates and show dialog if a new version is available
  static Future<void> checkForUpdates(BuildContext context, {bool showFeedback = false}) async {
    // Clean up any old downloaded APK first
    await cleanUpTempApk();

    if (showFeedback && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Checking for updates...')),
      );
    }

    try {
      final response = await http.get(
        Uri.parse(repoUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final latestTag = data['tag_name'] as String? ?? '';
        final currentVer = await getCurrentVersion();
        
        if (latestTag.isNotEmpty && _isNewer(currentVer, latestTag)) {
          // Find APK asset URL if it exists
          String downloadUrl = webReleaseUrl;
          final assets = data['assets'] as List<dynamic>? ?? [];
          for (final asset in assets) {
            final name = asset['name'] as String? ?? '';
            if (name.endsWith('.apk')) {
              downloadUrl = asset['browser_download_url'] as String? ?? webReleaseUrl;
              break;
            }
          }

          if (context.mounted) {
            if (showFeedback) ScaffoldMessenger.of(context).clearSnackBars();
            _showUpdateDialog(context, latestTag, downloadUrl);
          }
        } else {
          if (showFeedback && context.mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Rentr is up to date!')),
            );
          }
        }
      } else {
        if (showFeedback && context.mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to check for updates: Server error ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      debugPrint('UpdateCheck failed: $e');
      if (showFeedback && context.mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to check for updates. Please check your connection.')),
        );
      }
    }
  }

  // Safe SemVer version comparison helper
  static bool _isNewer(String current, String latest) {
    try {
      final currentClean = current.replaceAll('v', '').trim();
      final latestClean = latest.replaceAll('v', '').trim();
      
      final currentParts = currentClean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      final latestParts = latestClean.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      
      final maxLength = currentParts.length > latestParts.length ? currentParts.length : latestParts.length;
      for (var i = 0; i < maxLength; i++) {
        final currentVal = i < currentParts.length ? currentParts[i] : 0;
        final latestVal = i < latestParts.length ? latestParts[i] : 0;
        
        if (latestVal > currentVal) {
          return true;
        } else if (latestVal < currentVal) {
          return false;
        }
      }
    } catch (_) {}
    return false;
  }

  static void _showUpdateDialog(BuildContext context, String version, String downloadUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.system_update_alt, color: Color(0xFF0F172A)),
            const SizedBox(width: 12),
            const Text('Update Available'),
          ],
        ),
        content: Text(
          'A new version of Rentr ($version) is available. Would you like to download and install the update?',
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performBackgroundUpdate(context, downloadUrl);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // Download APK in the background and trigger the package installer channel
  static Future<void> _performBackgroundUpdate(BuildContext context, String downloadUrl) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 16),
            Text('Downloading update in the background...'),
          ],
        ),
        duration: Duration(days: 1), // Indefinite until manual check finishes
      ),
    );

    try {
      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode == 200) {
        scaffoldMessenger.hideCurrentSnackBar();
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Download complete. Launching installer...')),
        );

        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/rentr.apk');
        await file.writeAsBytes(response.bodyBytes);

        const platform = MethodChannel('com.luqmanmalik.rentry/install');
        await platform.invokeMethod('installApk', file.path);
      } else {
        throw Exception('Download failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Background update failed: $e');
      scaffoldMessenger.hideCurrentSnackBar();
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Failed to download update: ${e.toString()}')),
      );
    }
  }

  // Clean up the downloaded APK from the temporary directory
  static Future<void> cleanUpTempApk() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/rentr.apk');
      if (await file.exists()) {
        await file.delete();
        debugPrint('Cleaned up downloaded update APK.');
      }
    } catch (e) {
      debugPrint('Failed to clean up temp APK: $e');
    }
  }
}
