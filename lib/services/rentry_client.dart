import 'dart:convert';
import 'package:http/http.dart' as http;

class RentryClient {
  static const String baseUrl = 'https://rentry.co';
  
  String? _csrfToken;
  
  // Fetch a fresh CSRF token from the rentry.co homepage
  Future<String> _fetchCsrfToken() async {
    final response = await http.get(Uri.parse(baseUrl));
    if (response.statusCode != 200) {
      throw Exception('Failed to load rentry.co to fetch CSRF token');
    }
    
    final setCookie = response.headers['set-cookie'];
    if (setCookie == null) {
      throw Exception('Set-Cookie header missing from rentry.co response');
    }
    
    final regex = RegExp(r'csrftoken=([^;]+)');
    final match = regex.firstMatch(setCookie);
    final token = match?.group(1);
    
    if (token == null) {
      throw Exception('csrftoken not found in cookies');
    }
    
    _csrfToken = token;
    return token;
  }
  
  // Get active cached token or fetch if none or if forced
  Future<String> getCsrfToken({bool forceRefresh = false}) async {
    if (_csrfToken == null || forceRefresh) {
      await _fetchCsrfToken();
    }
    return _csrfToken!;
  }
  
  // Check if a URL name is available (returns true if available/404, false if taken/200)
  Future<bool> checkUrlAvailability(String url) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/$url'));
      return response.statusCode == 404;
    } catch (_) {
      // In case of network errors, we'll bubble up or return false
      return false;
    }
  }

  // Fetch raw markdown content and metadata of an existing note by scraping the edit page textareas
  Future<Map<String, String>> fetchRawContent(String url) async {
    final response = await http.get(
      Uri.parse('$baseUrl/$url/edit'),
      headers: {'Referer': baseUrl},
    );

    if (response.statusCode == 200) {
      final body = response.body;
      // Extract the raw text from the form textarea using Regex
      final contentMatch = RegExp(r'<textarea[^>]*id="id_text"[^>]*>([\s\S]*?)<\/textarea>').firstMatch(body);
      final metadataMatch = RegExp(r'<textarea[^>]*id="metadata_text"[^>]*>([\s\S]*?)<\/textarea>').firstMatch(body);
      
      if (contentMatch != null) {
        final rawText = contentMatch.group(1) ?? '';
        final rawMetadata = metadataMatch?.group(1) ?? '';
        return {
          'content': _unescapeHtml(rawText),
          'metadata': _unescapeHtml(rawMetadata),
        };
      }
      throw Exception('Failed to parse text from Rentry editor page.');
    } else if (response.statusCode == 404) {
      throw Exception('Note not found on Rentry (404)');
    } else {
      throw Exception('Failed to fetch content: ${response.statusCode}');
    }
  }

  // Helper to decode HTML entities (including standard, decimal, and hexadecimal codes)
  String _unescapeHtml(String html) {
    var result = html
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");

    // Decode decimal entities (e.g. &#39;)
    result = result.replaceAllMapped(RegExp(r'&#(\d+);'), (match) {
      final code = int.parse(match.group(1)!);
      return String.fromCharCode(code);
    });

    // Decode hexadecimal entities (e.g. &#x27;)
    result = result.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (match) {
      final code = int.parse(match.group(1)!, radix: 16);
      return String.fromCharCode(code);
    });

    return result;
  }
  
  // Edit an existing note (passing metadata back to Rentry to prevent losing ownership/settings)
  Future<void> editNote(String url, String editCode, String content, String metadata) async {
    await _executeWithTokenFallback((token) async {
      final response = await http.post(
        Uri.parse('$baseUrl/api/edit/$url'),
        headers: {
          'Referer': baseUrl,
          'Cookie': 'csrftoken=$token',
        },
        body: {
          'csrfmiddlewaretoken': token,
          'edit_code': editCode,
          'text': content,
          'metadata': metadata,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '200' || data['status'] == 200) {
          return;
        } else {
          final errorMsg = data['errors'] ?? data['content'] ?? 'Unknown API error';
          throw Exception(errorMsg);
        }
      } else {
        throw Exception('Server returned status code: ${response.statusCode}');
      }
    });
  }

  // Create a new note
  // Returns the edit_code associated with the note
  Future<String> createNote(String url, String editCode, String content, String metadata) async {
    return await _executeWithTokenFallback<String>((token) async {
      final response = await http.post(
        Uri.parse('$baseUrl/api/new'),
        headers: {
          'Referer': baseUrl,
          'Cookie': 'csrftoken=$token',
        },
        body: {
          'csrfmiddlewaretoken': token,
          'url': url,
          'edit_code': editCode,
          'text': content,
          'metadata': metadata,
        },
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == '200' || data['status'] == 200) {
          return data['edit_code'] as String;
        } else {
          final errorMsg = data['errors'] ?? data['content'] ?? 'Unknown API error';
          throw Exception(errorMsg);
        }
      } else {
        throw Exception('Server returned status code: ${response.statusCode}');
      }
    });
  }
  
  // Execute operation and retry with fresh CSRF token if error looks CSRF-related
  Future<T> _executeWithTokenFallback<T>(Future<T> Function(String token) action) async {
    var token = await getCsrfToken();
    try {
      return await action(token);
    } catch (e) {
      final errorStr = e.toString();
      if (errorStr.contains('403') || errorStr.contains('csrf') || errorStr.contains('CSRF')) {
        token = await getCsrfToken(forceRefresh: true);
        return await action(token);
      }
      rethrow;
    }
  }
}
