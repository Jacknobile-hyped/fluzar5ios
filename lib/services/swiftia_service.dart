import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SwiftiaService {
  static const String _baseUrl = 'https://app.swiftia.io/api';
  static const String _apiKeyKey = 'swiftia_api_key';
  
  // Rate limiting
  static const int _maxRequestsPerSecond = 2;
  static DateTime? _lastRequestTime;
  
  // Logging
  static bool _enableLogging = true;
  
  // Get API key from shared preferences or use default
  static Future<String?> getApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final savedApiKey = prefs.getString(_apiKeyKey);
    
    // If no saved API key, use the default one
    if (savedApiKey == null || savedApiKey.isEmpty) {
      _log('Using default API key');
      return 'lcl.1oL7p1e+6Ay+D9Pnwfc.l3TDV';
    }
    
    _log('Using saved API key');
    return savedApiKey;
  }
  
  // Save API key to shared preferences
  static Future<void> saveApiKey(String apiKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_apiKeyKey, apiKey);
    _log('API key saved to preferences');
  }
  
  // Rate limiting helper
  static Future<void> _handleRateLimit() async {
    if (_lastRequestTime != null) {
      final now = DateTime.now();
      final timeSinceLastRequest = now.difference(_lastRequestTime!);
      final minInterval = Duration(milliseconds: 1000 ~/ _maxRequestsPerSecond);
      
      if (timeSinceLastRequest < minInterval) {
        final waitTime = minInterval - timeSinceLastRequest;
        _log('Rate limiting: waiting ${waitTime.inMilliseconds}ms');
        await Future.delayed(waitTime);
      }
    }
    _lastRequestTime = DateTime.now();
  }
  
  // Logging helper
  static void _log(String message) {
    if (_enableLogging) {
      final timestamp = DateTime.now().toIso8601String();
      print('[SwiftiaService] [$timestamp] $message');
    }
  }
  
  // Error handling helper
  static Exception _handleApiError(http.Response response, String operation) {
    try {
      final errorData = jsonDecode(response.body);
      final statusCode = response.statusCode;
      final message = errorData['message'] ?? 'Unknown error';
      final code = errorData['code'] ?? 'UNKNOWN_CODE';
      
      _log('API Error in $operation: Status $statusCode, Code: $code, Message: $message');
      _log('Response body: ${response.body}');
      
      // Handle specific error codes
      switch (statusCode) {
        case 201:
          // 201 Created - might be a success but with warning
          _log('Warning: Received 201 status - checking response body for warnings');
          if (errorData.containsKey('warning')) {
            _log('Warning detected: ${errorData['warning']}');
          }
          return Exception('Operation completed with warning: $message (Code: $code)');
          
        case 400:
          return Exception('Invalid request: $message (Code: $code)');
          
        case 401:
          return Exception('Unauthorized: Please check your API key (Code: $code)');
          
        case 404:
          return Exception('Resource not found: $message (Code: $code)');
          
        case 429:
          return Exception('Rate limit exceeded: $message (Code: $code)');
          
        case 500:
          return Exception('Server error: $message (Code: $code)');
          
        default:
          return Exception('HTTP $statusCode: $message (Code: $code)');
      }
    } catch (e) {
      _log('Error parsing error response: $e');
      return Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }
  
  // Create a VideoShorts job
  static Future<Map<String, dynamic>> createVideoShortsJob({
    required String youtubeVideoId,
    String? jobName,
    List<Map<String, dynamic>>? predefinedShorts,
    String? webhookUrl,
  }) async {
    _log('Creating VideoShorts job for YouTube ID: $youtubeVideoId');
    _log('Job name: $jobName, Predefined shorts: ${predefinedShorts?.length ?? 0}, Webhook: $webhookUrl');
    
    await _handleRateLimit();
    
    final apiKey = await getApiKey();
    if (apiKey == null) {
      _log('Error: No API key available');
      throw Exception('API key not found. Please set your Swiftia API key first.');
    }
    
    final url = Uri.parse('$_baseUrl/jobs');
    _log('Making POST request to: $url');
    
    final body = {
      'functionName': 'VideoShorts',
      if (jobName != null) 'name': jobName,
      'youtubeVideoId': youtubeVideoId,
      if (predefinedShorts != null) 'options': {'predefinedShorts': predefinedShorts},
      if (webhookUrl != null) 'webhook': webhookUrl,
    };
    
    _log('Request body: ${jsonEncode(body)}');
    
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      
      _log('Response status: ${response.statusCode}');
      _log('Response headers: ${response.headers}');
      _log('Response body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        _log('Job created successfully: ${result['jobId'] ?? 'No job ID in response'}');
        return result;
      } else if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        final waitTime = retryAfter != null ? int.tryParse(retryAfter) ?? 1 : 1;
        _log('Rate limit hit, waiting $waitTime seconds before retry');
        await Future.delayed(Duration(seconds: waitTime));
        return createVideoShortsJob(
          youtubeVideoId: youtubeVideoId,
          jobName: jobName,
          predefinedShorts: predefinedShorts,
          webhookUrl: webhookUrl,
        );
      } else {
        throw _handleApiError(response, 'createVideoShortsJob');
      }
    } catch (e) {
      if (e is Exception) {
        _log('Exception in createVideoShortsJob: $e');
        rethrow;
      }
      _log('Network error in createVideoShortsJob: $e');
      throw Exception('Network error: $e');
    }
  }
  
  // Get job status and results
  static Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    _log('Getting job status for ID: $jobId');
    
    await _handleRateLimit();
    
    final apiKey = await getApiKey();
    if (apiKey == null) {
      _log('Error: No API key available');
      throw Exception('API key not found. Please set your Swiftia API key first.');
    }
    
    final url = Uri.parse('$_baseUrl/jobs/$jobId');
    _log('Making GET request to: $url');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );
      
      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        _log('Job status retrieved: ${result['status'] ?? 'Unknown status'}');
        return result;
      } else if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        final waitTime = retryAfter != null ? int.tryParse(retryAfter) ?? 1 : 1;
        _log('Rate limit hit, waiting $waitTime seconds before retry');
        await Future.delayed(Duration(seconds: waitTime));
        return getJobStatus(jobId);
      } else {
        throw _handleApiError(response, 'getJobStatus');
      }
    } catch (e) {
      if (e is Exception) {
        _log('Exception in getJobStatus: $e');
        rethrow;
      }
      _log('Network error in getJobStatus: $e');
      throw Exception('Network error: $e');
    }
  }
  
  // Initiate rendering for a specific short
  static Future<Map<String, dynamic>> renderVideo({
    required String jobId,
    required int target,  // Changed from String to int
    String? preset,
    Map<String, dynamic>? options,
  }) async {
    _log('Starting render for job: $jobId, target: $target, preset: $preset');
    _log('Render options: $options');
    
    await _handleRateLimit();
    
    final apiKey = await getApiKey();
    if (apiKey == null) {
      _log('Error: No API key available');
      throw Exception('API key not found. Please set your Swiftia API key first.');
    }
    
    final url = Uri.parse('$_baseUrl/render');
    _log('Making POST request to: $url');
    
    final body = {
      'id': jobId,
      'target': target,  // Now sends int instead of string
      if (preset != null) 'preset': preset,
      if (options != null) 'options': options,
    };
    
    _log('Request body: ${jsonEncode(body)}');
    
    try {
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      
      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final result = jsonDecode(response.body);
        _log('Render started successfully: ${result['renderId'] ?? 'No render ID in response'}');
        return result;
      } else if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        final waitTime = retryAfter != null ? int.tryParse(retryAfter) ?? 1 : 1;
        _log('Rate limit hit, waiting $waitTime seconds before retry');
        await Future.delayed(Duration(seconds: waitTime));
        return renderVideo(
          jobId: jobId,
          target: target,
          preset: preset,
          options: options,
        );
      } else {
        throw _handleApiError(response, 'renderVideo');
      }
    } catch (e) {
      if (e is Exception) {
        _log('Exception in renderVideo: $e');
        rethrow;
      }
      _log('Network error in renderVideo: $e');
      throw Exception('Network error: $e');
    }
  }
  
  // Get render status and result
  static Future<Map<String, dynamic>> getRenderStatus(String renderId) async {
    _log('Getting render status for ID: $renderId');
    
    await _handleRateLimit();
    
    final apiKey = await getApiKey();
    if (apiKey == null) {
      _log('Error: No API key available');
      throw Exception('API key not found. Please set your Swiftia API key first.');
    }
    
    final url = Uri.parse('$_baseUrl/render/$renderId');
    _log('Making GET request to: $url');
    
    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
      );
      
      _log('Response status: ${response.statusCode}');
      _log('Response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        _log('Render status retrieved: ${result['type'] ?? 'Unknown type'}');
        return result;
      } else if (response.statusCode == 429) {
        final retryAfter = response.headers['retry-after'];
        final waitTime = retryAfter != null ? int.tryParse(retryAfter) ?? 1 : 1;
        _log('Rate limit hit, waiting $waitTime seconds before retry');
        await Future.delayed(Duration(seconds: waitTime));
        return getRenderStatus(renderId);
      } else {
        throw _handleApiError(response, 'getRenderStatus');
      }
    } catch (e) {
      if (e is Exception) {
        _log('Exception in getRenderStatus: $e');
        rethrow;
      }
      _log('Network error in getRenderStatus: $e');
      throw Exception('Network error: $e');
    }
  }
  
  // Extract YouTube video ID from URL
  static String? extractYouTubeVideoId(String url) {
    _log('Extracting YouTube video ID from URL: $url');
    
    final regex = RegExp(
      r'(?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)([^"&?\/\s]{11})',
      caseSensitive: false,
    );
    
    final match = regex.firstMatch(url);
    final videoId = match?.group(1);
    
    if (videoId != null) {
      _log('YouTube video ID extracted: $videoId');
    } else {
      _log('Failed to extract YouTube video ID from URL');
    }
    
    return videoId;
  }
  
  // Validate YouTube URL
  static bool isValidYouTubeUrl(String url) {
    final isValid = extractYouTubeVideoId(url) != null;
    _log('YouTube URL validation: $url -> ${isValid ? 'Valid' : 'Invalid'}');
    return isValid;
  }
  
  // Get available presets
  static List<String> getAvailablePresets() {
    _log('Getting available presets');
    return [
      'DEFAULT',
      'GRAPES',
      'VIRAL',
      'BLURRY',
      'FAST',
      'DEEP DIVER',
      'GLOW VIOLET',
      '70S RADIATION',
      'BILL GREEN',
      'ETHEREAL UNDERLINE',
    ];
  }
  
  // Get YouTube video duration
  static Future<String?> getYouTubeVideoDuration(String videoId) async {
    _log('Getting YouTube video duration for ID: $videoId');
    
    try {
      // Use YouTube Data API v3 to get video details
      final url = Uri.parse('https://www.googleapis.com/youtube/v3/videos'
          '?part=contentDetails'
          '&id=$videoId'
          '&key=AIzaSyDcqQOKXVB2Y-2R73ytvlT9Hww92mD6MEg'); // Using existing API key from project
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['items'] != null && data['items'].isNotEmpty) {
          final duration = data['items'][0]['contentDetails']['duration'];
          _log('Video duration: $duration');
          return _formatDuration(duration);
        }
      }
      
      _log('Failed to get video duration: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      _log('Error getting video duration: $e');
      return null;
    }
  }
  
  // Format ISO 8601 duration to readable format
  static String _formatDuration(String isoDuration) {
    try {
      // Parse ISO 8601 duration (e.g., "PT1H2M10S")
      final regex = RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?');
      final match = regex.firstMatch(isoDuration);
      
      if (match != null) {
        final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
        final minutes = int.tryParse(match.group(2) ?? '0') ?? 0;
        final seconds = int.tryParse(match.group(3) ?? '0') ?? 0;
        
        if (hours > 0) {
          return '${hours}h ${minutes}m ${seconds}s';
        } else if (minutes > 0) {
          return '${minutes}m ${seconds}s';
        } else {
          return '${seconds}s';
        }
      }
      
      return 'Unknown duration';
    } catch (e) {
      _log('Error formatting duration: $e');
      return 'Unknown duration';
    }
  }
  
  // Enable/disable logging
  static void setLoggingEnabled(bool enabled) {
    _enableLogging = enabled;
    _log('Logging ${enabled ? 'enabled' : 'disabled'}');
  }
}
