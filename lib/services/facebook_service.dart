import 'dart:convert';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'cloudflare_config.dart';

class FacebookService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  // Check if scheduled date is valid for Facebook (must be at least 10 minutes in the future, at most 30 days)
  bool isValidPublishDate(DateTime publishDate) {
    final now = DateTime.now();
    final minTime = now.add(Duration(minutes: 10));
    final maxTime = now.add(Duration(days: 30));
    
    return publishDate.isAfter(minTime) && publishDate.isBefore(maxTime);
  }
  
  // Get Facebook API client from stored account
  Future<Map<String, dynamic>?> getFacebookApiFromAccount(String accountId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      print('Getting Facebook account data for ID: $accountId');
      
      // Prova tutti i possibili percorsi dove l'account Facebook potrebbe essere memorizzato
      
      // 1. Percorso come mostrato in databasefirebase.json
      // users/WZn8hdkvlpSMisViSOsBZQpFUhJ3/facebook/612887388580338
      var snapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('facebook')
          .child(accountId)
          .get();
          
      if (snapshot.exists) {
        print('Found Facebook account in users/{uid}/facebook path');
        final data = snapshot.value as Map<dynamic, dynamic>;
        return {
          'access_token': data['access_token'],
          'page_id': data['page_id'] ?? data['id'] ?? accountId,
          'app_id': data['app_id'] ?? '248099281287621', // Fallback to default Meta app ID
        };
      }
      
      // 2. Percorso users/users/{uid}/facebook/{accountId}
      snapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('facebook')
          .child(accountId)
          .get();
      
      if (snapshot.exists) {
        print('Found Facebook account in users/users/{uid}/facebook path');
        final data = snapshot.value as Map<dynamic, dynamic>;
        return {
          'access_token': data['access_token'],
          'page_id': data['page_id'] ?? data['id'] ?? accountId,
          'app_id': data['app_id'] ?? '248099281287621', // Fallback to default Meta app ID
        };
      }
      
      // 3. Percorso users/{uid}/social_accounts/Facebook/{accountId}
      snapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('Facebook')
          .child(accountId)
          .get();
      
      if (snapshot.exists) {
        print('Found Facebook account in users/{uid}/social_accounts/Facebook path');
        final data = snapshot.value as Map<dynamic, dynamic>;
        return {
          'access_token': data['access_token'],
          'page_id': data['page_id'] ?? data['id'] ?? accountId,
          'app_id': data['app_id'] ?? '248099281287621', // Fallback to default Meta app ID
        };
      }
      
      // 4. Percorso users/users/{uid}/social_accounts/Facebook/{accountId}
      snapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('Facebook')
          .child(accountId)
          .get();
      
      if (snapshot.exists) {
        print('Found Facebook account in users/users/{uid}/social_accounts/Facebook path');
        final data = snapshot.value as Map<dynamic, dynamic>;
        return {
          'access_token': data['access_token'],
          'page_id': data['page_id'] ?? data['id'] ?? accountId,
          'app_id': data['app_id'] ?? '248099281287621', // Fallback to default Meta app ID
        };
      }
      
      // Debug: stampa tutti i percorsi verificati
      print('Checked paths:');
      print('- users/${currentUser.uid}/facebook/$accountId');
      print('- users/users/${currentUser.uid}/facebook/$accountId');
      print('- users/${currentUser.uid}/social_accounts/Facebook/$accountId');
      print('- users/users/${currentUser.uid}/social_accounts/Facebook/$accountId');
      
      print('Facebook account not found: $accountId for user ${currentUser.uid}');
      return null;
    } catch (e) {
      print('Error getting Facebook account data: $e');
      return null;
    }
  }
  
  // Schedule a post on Facebook Page
  Future<Map<String, dynamic>?> schedulePagePost({
    required String accountId,
    required String message,
    File? videoFile,
    DateTime? scheduledAt,
    String? link,
  }) async {
    try {
      final apiData = await getFacebookApiFromAccount(accountId);
      if (apiData == null) {
        throw Exception('Account data not found');
      }
      
      final accessToken = apiData['access_token'];
      final pageId = apiData['page_id'];
      
      print('Scheduling Facebook post for page ID: $pageId');
      
      // Check if we're scheduling or posting immediately
      final isScheduled = scheduledAt != null;
      final endpoint = 'https://graph.facebook.com/v22.0/$pageId/feed';
      
      // Prepare request body
      final Map<String, dynamic> body = {
        'message': message,
        'access_token': accessToken,
      };
      
      // Add link if provided
      if (link != null && link.isNotEmpty) {
        body['link'] = link;
      }
      
      // Add scheduling parameters if needed
      if (isScheduled) {
        body['published'] = 'false';
        body['scheduled_publish_time'] = (scheduledAt.millisecondsSinceEpoch / 1000).round().toString();
      }
      
      // Make API request to schedule the post
      final response = await http.post(
        Uri.parse(endpoint),
        body: body,
      );
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('Successfully scheduled Facebook post with ID: ${result['id']}');
        return {
          'id': result['id'],
          'scheduled': isScheduled,
        };
      } else {
        print('Facebook API error: ${response.body}');
        throw Exception('Failed to schedule Facebook post: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error scheduling Facebook post: $e');
      return null;
    }
  }
  
  // Upload a video to Facebook using the Resumable Upload API
  Future<String?> uploadVideoToFacebook({
    required String accountId,
    required File videoFile,
    required String title,
    required String description,
    DateTime? scheduledAt,
  }) async {
    try {
      final apiData = await getFacebookApiFromAccount(accountId);
      if (apiData == null) {
        throw Exception('Account data not found');
      }
      
      final accessToken = apiData['access_token'];
      final pageId = apiData['page_id'];
      final appId = apiData['app_id'];
      
      // Get video file information
      final fileName = path.basename(videoFile.path);
      final fileLength = await videoFile.length();
      final fileType = 'video/mp4'; // Assuming MP4 video format
      
      print('Starting Facebook video upload: $fileName (${fileLength} bytes) for page ID: $pageId');
      
      // Prima prova a usare il metodo di caricamento diretto
      try {
        print('Attempting direct video upload to Facebook');
        return await _directVideoUpload(
          pageId: pageId,
          accessToken: accessToken,
          videoFile: videoFile,
          title: title,
          description: description,
          scheduledAt: scheduledAt,
        );
      } catch (directUploadError) {
        print('Direct upload failed, trying resumable upload: $directUploadError');
        // Se fallisce, passa al metodo di caricamento resumable
      }
      
      // Verifica che l'app ID sia presente per l'upload resumable
      if (appId == null || appId.isEmpty) {
        throw Exception('Facebook App ID is required for resumable video uploads');
      }
      
      print('Using resumable upload API with app ID: $appId');
      
      // Step 1: Start an upload session
      final sessionResponse = await http.post(
        Uri.parse('https://graph.facebook.com/v22.0/$appId/uploads'),
        body: {
          'access_token': accessToken,
          'file_name': fileName,
          'file_length': fileLength.toString(),
          'file_type': fileType,
        },
      );
      
      if (sessionResponse.statusCode != 200) {
        throw Exception('Failed to start upload session: ${sessionResponse.body}');
      }
      
      final sessionData = json.decode(sessionResponse.body);
      final uploadSessionId = sessionData['id']?.toString().replaceAll('upload:', '');
      
      if (uploadSessionId == null) {
        throw Exception('Failed to get upload session ID');
      }
      
      print('Started upload session: $uploadSessionId');
      
      // Step 2: Upload the file
      final videoBytes = await videoFile.readAsBytes();
      final uploadResponse = await http.post(
        Uri.parse('https://graph.facebook.com/v22.0/upload:$uploadSessionId'),
        headers: {
          'Authorization': 'OAuth $accessToken',
          'file_offset': '0',
          'Content-Type': 'application/octet-stream',
        },
        body: videoBytes,
      );
      
      if (uploadResponse.statusCode != 200) {
        throw Exception('Failed to upload video: ${uploadResponse.body}');
      }
      
      final uploadData = json.decode(uploadResponse.body);
      final fileHandle = uploadData['h'];
      
      if (fileHandle == null) {
        throw Exception('Failed to get file handle');
      }
      
      print('Uploaded video file, received handle: $fileHandle');
      
      // Step 3: Publish the video to the Page
      final Map<String, dynamic> publishBody = {
        'access_token': accessToken,
        'description': description,
        'title': title,
        'file_url': fileHandle,
      };
      
      // Add scheduling parameters if needed
      if (scheduledAt != null) {
        publishBody['published'] = 'false';
        publishBody['scheduled_publish_time'] = (scheduledAt.millisecondsSinceEpoch / 1000).round().toString();
      }
      
      final publishResponse = await http.post(
        Uri.parse('https://graph.facebook.com/v22.0/$pageId/videos'),
        body: publishBody,
      );
      
      if (publishResponse.statusCode != 200) {
        throw Exception('Failed to publish video: ${publishResponse.body}');
      }
      
      final publishData = json.decode(publishResponse.body);
      final videoId = publishData['id'];
      
      print('Successfully published Facebook video with ID: $videoId');
      
      return videoId;
    } catch (e) {
      print('Error uploading video to Facebook: $e');
      return null;
    }
  }
  
  // Caricamento diretto del video senza usare l'API resumable
  Future<String?> _directVideoUpload({
    required String pageId,
    required String accessToken,
    required File videoFile,
    required String title,
    required String description,
    DateTime? scheduledAt,
  }) async {
    final uri = Uri.parse('https://graph.facebook.com/v22.0/$pageId/videos');
    
    // Crea un request multipart
    final request = http.MultipartRequest('POST', uri);
    
    // Aggiungi il token di accesso e i parametri
    request.fields['access_token'] = accessToken;
    request.fields['title'] = title;
    request.fields['description'] = description;
    
    // Aggiungi i parametri di scheduling se necessario
    if (scheduledAt != null) {
      request.fields['published'] = 'false';
      request.fields['scheduled_publish_time'] = (scheduledAt.millisecondsSinceEpoch / 1000).round().toString();
    }
    
    // Aggiungi il file video
    request.files.add(await http.MultipartFile.fromPath(
      'source',
      videoFile.path,
      contentType: MediaType('video', 'mp4'),
    ));
    
    print('Sending direct video upload request to Facebook');
    
    // Invia la richiesta
    final response = await request.send();
    final responseBody = await response.stream.bytesToString();
    
    if (response.statusCode != 200) {
      print('Direct upload failed with status: ${response.statusCode}, body: $responseBody');
      throw Exception('Failed to upload video directly: ${response.statusCode}');
    }
    
    final responseData = json.decode(responseBody);
    final videoId = responseData['id'];
    
    print('Successfully uploaded video directly with ID: $videoId');
    
    return videoId;
  }
  
  // Resume an interrupted upload
  Future<String?> resumeVideoUpload({
    required String accountId,
    required String uploadSessionId,
    required File videoFile,
    required int fileOffset,
  }) async {
    try {
      final apiData = await getFacebookApiFromAccount(accountId);
      if (apiData == null) {
        throw Exception('Account data not found');
      }
      
      final accessToken = apiData['access_token'];
      
      // Read the remaining part of the file
      final file = await videoFile.open();
      await file.setPosition(fileOffset);
      final remainingBytes = await file.read(await videoFile.length() - fileOffset);
      await file.close();
      
      // Upload the remaining part
      final resumeResponse = await http.post(
        Uri.parse('https://graph.facebook.com/v22.0/upload:$uploadSessionId'),
        headers: {
          'Authorization': 'OAuth $accessToken',
          'file_offset': fileOffset.toString(),
          'Content-Type': 'application/octet-stream',
        },
        body: remainingBytes,
      );
      
      if (resumeResponse.statusCode != 200) {
        throw Exception('Failed to resume upload: ${resumeResponse.body}');
      }
      
      final resumeData = json.decode(resumeResponse.body);
      return resumeData['h'];
    } catch (e) {
      print('Error resuming video upload: $e');
      return null;
    }
  }
  
  // Check upload session status
  Future<int?> checkUploadStatus(String accountId, String uploadSessionId) async {
    try {
      final apiData = await getFacebookApiFromAccount(accountId);
      if (apiData == null) return null;
      
      final accessToken = apiData['access_token'];
      
      final statusResponse = await http.get(
        Uri.parse('https://graph.facebook.com/v22.0/upload:$uploadSessionId'),
        headers: {
          'Authorization': 'OAuth $accessToken',
        },
      );
      
      if (statusResponse.statusCode != 200) return null;
      
      final statusData = json.decode(statusResponse.body);
      return statusData['file_offset'] as int?;
    } catch (e) {
      print('Error checking upload status: $e');
      return null;
    }
  }
  
  // Metodo per eliminare un post di Facebook dal KV basandosi su scheduledTime e userId
  Future<bool> deleteFacebookScheduledPost(int scheduledTime, String userId) async {
    try {
      print('Tentativo di eliminazione del post Facebook con scheduledTime: $scheduledTime e userId: $userId');
      // Ottieni tutte le chiavi dal KV
      final listResponse = await http.get(
        Uri.parse('${CloudflareConfig.apiBaseUrl}/accounts/${CloudflareConfig.accountId}/storage/kv/namespaces/${CloudflareConfig.kvNamespaceId}/keys'),
        headers: CloudflareConfig.headers,
      );
      if (listResponse.statusCode != 200) {
        print('Errore nel recupero delle chiavi KV: ${listResponse.statusCode} - ${listResponse.body}');
        return false;
      }
      final keysData = json.decode(listResponse.body);
      final keys = keysData['result'] as List<dynamic>?;
      if (keys == null || keys.isEmpty) {
        print('Nessuna chiave trovata nel KV');
        return false;
      }
      String? targetKey;
      for (final keyObj in keys) {
        final keyName = keyObj['name'] as String;
        // Scarica il valore per ogni chiave
        final valueResponse = await http.get(
          Uri.parse('${CloudflareConfig.apiBaseUrl}/accounts/${CloudflareConfig.accountId}/storage/kv/namespaces/${CloudflareConfig.kvNamespaceId}/values/$keyName'),
          headers: CloudflareConfig.headers,
        );
        if (valueResponse.statusCode != 200) {
          print('Errore nel recupero del valore per la chiave $keyName: ${valueResponse.statusCode}');
          continue;
        }
        try {
          final valueJson = json.decode(valueResponse.body);
          final postScheduledTime = valueJson['scheduledTime'];
          final postUserId = valueJson['userId'];
          print('Controllo chiave $keyName: scheduledTime=$postScheduledTime, userId=$postUserId');
          if (postScheduledTime == scheduledTime && postUserId == userId) {
            targetKey = keyName;
            print('Trovata corrispondenza: chiave $keyName');
            break;
          }
        } catch (e) {
          print('Errore parsing JSON per chiave $keyName: $e');
        }
      }
      if (targetKey == null) {
        print('Nessun post Facebook trovato con scheduledTime: $scheduledTime e userId: $userId');
        return false;
      }
      // Elimina la chiave trovata
      final deleteResponse = await http.delete(
        Uri.parse('${CloudflareConfig.apiBaseUrl}/accounts/${CloudflareConfig.accountId}/storage/kv/namespaces/${CloudflareConfig.kvNamespaceId}/values/$targetKey'),
        headers: CloudflareConfig.headers,
      );
      if (deleteResponse.statusCode == 200) {
        print('Post Facebook eliminato con successo dal KV: $targetKey');
        return true;
      } else {
        print('Errore durante l\'eliminazione della chiave $targetKey: ${deleteResponse.statusCode} - ${deleteResponse.body}');
        return false;
      }
    } catch (e) {
      print('Eccezione durante l\'eliminazione del post Facebook: $e');
      return false;
    }
  }
  
  // Metodo alternativo più efficiente se conosci la chiave specifica
  Future<bool> deleteFacebookScheduledPostByKey(String keyName) async {
    try {
      print('Tentativo di eliminazione del post Facebook con chiave: $keyName');
      
      final deleteResponse = await http.delete(
        Uri.parse('${CloudflareConfig.apiBaseUrl}/accounts/${CloudflareConfig.accountId}/storage/kv/namespaces/${CloudflareConfig.kvNamespaceId}/values/$keyName'),
        headers: {
          'Authorization': CloudflareConfig.headers['Authorization']!,
        },
      );
      
      if (deleteResponse.statusCode == 200) {
        print('Post Facebook eliminato con successo dal KV: $keyName');
        return true;
      } else {
        print('Errore nell\'eliminazione del post Facebook: ${deleteResponse.statusCode} - ${deleteResponse.body}');
        return false;
      }
      
    } catch (e) {
      print('Errore durante l\'eliminazione del post Facebook dal KV: $e');
      return false;
    }
  }
} 