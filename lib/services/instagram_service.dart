import 'dart:convert';
import 'dart:io';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'dart:math' as math;
import 'package:firebase_storage/firebase_storage.dart';

class InstagramService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  
  // Cloudflare worker endpoint for scheduling posts
  final String _schedulerWorkerUrl = 'https://wandering-queen-520b.giuseppemaria162.workers.dev/api/schedule';
  
  // Aggiungiamo la costante mancante
  final String instagramSchedulerWorkerUrl = 'https://wandering-queen-520b.giuseppemaria162.workers.dev';
  
  /// Get the current Firebase authentication token
  Future<String?> getFirebaseAuthToken() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      return await currentUser.getIdToken();
    } catch (e) {
      print('Error getting Firebase auth token: $e');
      return null;
    }
  }
  
  // Verifica se la data programmata è valida per Instagram (non ci sono limiti specifici documentati)
  bool isValidPublishDate(DateTime publishDate) {
    final now = DateTime.now();
    final minTime = now.add(Duration(minutes: 15));
    
    return publishDate.isAfter(minTime);
  }
  
  // Ottiene i dati dell'account Instagram dal database
  Future<Map<String, dynamic>?> getInstagramApiFromAccount(String accountId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      print('Getting Instagram account data for ID: $accountId');
      
      // Prova tutti i possibili percorsi dove l'account Instagram potrebbe essere memorizzato
      Map<String, dynamic>? accountData;
      
      // 1. Percorso diretto in "instagram" collezione
      var snapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('instagram')
          .child(accountId)
          .get();
          
      if (snapshot.exists) {
        print('Found Instagram account in users/{uid}/instagram path');
        accountData = Map<String, dynamic>.from(snapshot.value as Map);
      }
      
      // 2. Percorso users/users/{uid}/instagram/{accountId}
      if (accountData == null) {
        snapshot = await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('instagram')
            .child(accountId)
            .get();
        
        if (snapshot.exists) {
          print('Found Instagram account in users/users/{uid}/instagram path');
          accountData = Map<String, dynamic>.from(snapshot.value as Map);
        }
      }
      
      // 3. Percorso users/{uid}/social_accounts/Instagram/{accountId}
      if (accountData == null) {
        snapshot = await _database
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('Instagram')
            .child(accountId)
            .get();
        
        if (snapshot.exists) {
          print('Found Instagram account in users/{uid}/social_accounts/Instagram path');
          accountData = Map<String, dynamic>.from(snapshot.value as Map);
        }
      }
      
      // 4. Percorso users/users/{uid}/social_accounts/Instagram/{accountId}
      if (accountData == null) {
        snapshot = await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('Instagram')
            .child(accountId)
            .get();
        
        if (snapshot.exists) {
          print('Found Instagram account in users/users/{uid}/social_accounts/Instagram path');
          accountData = Map<String, dynamic>.from(snapshot.value as Map);
        }
      }
      
      // 5. Percorso users/{uid}/social_accounts/instagram/{accountId} (con 'i' minuscola)
      if (accountData == null) {
        snapshot = await _database
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('instagram')
            .child(accountId)
            .get();
        
        if (snapshot.exists) {
          print('Found Instagram account in users/{uid}/social_accounts/instagram path');
          accountData = Map<String, dynamic>.from(snapshot.value as Map);
        }
      }
      
      // 6. Percorso users/users/{uid}/social_accounts/instagram/{accountId} (con 'i' minuscola)
      if (accountData == null) {
        snapshot = await _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('instagram')
            .child(accountId)
            .get();
        
        if (snapshot.exists) {
          print('Found Instagram account in users/users/{uid}/social_accounts/instagram path');
          accountData = Map<String, dynamic>.from(snapshot.value as Map);
        }
      }
      
      // Se non abbiamo trovato i dati dell'account, restituiamo null
      if (accountData == null) {
        print('Instagram account not found: $accountId for user ${currentUser.uid}');
        return null;
      }
      
      // Estrai ed elabora il token correttamente
      String? accessToken = accountData['access_token'];
      
      // Verifica ulteriormente il token
      if (accessToken == null || accessToken.isEmpty) {
        print('Warning: Instagram access_token is missing or empty');
        return null;
      }
      
      // Sanitizza il token
      accessToken = _sanitizeToken(accessToken);
      
      // Verifica formato token
      if (accessToken.isEmpty) {
        print('Warning: Instagram token is empty after sanitization');
        return null;
      }
      
      return {
        'access_token': accessToken,
        'user_id': accountData['user_id'] ?? accountId,
        'username': accountData['username'] ?? '',
      };
    } catch (e) {
      print('Error getting Instagram account data: $e');
      return null;
    }
  }
  
  // Sanitizza il token Instagram
  String _sanitizeToken(String? token) {
    if (token == null || token.isEmpty) {
      print('Warning: Instagram token is null or empty');
      return '';
    }
    
    // Mostra la lunghezza del token per debug
    print('Token ricevuto - lunghezza: ${token.length}, inizia con: ${token.substring(0, math.min(8, token.length))}...');
    
    // Special handling for Instagram tokens that start with "IG"
    if (token.startsWith('IG')) {
      print('Instagram token detected (starts with IG) - treating with special care');
      // For Instagram tokens, only trim whitespace and remove control characters
      // Do not modify the token format otherwise
      String sanitized = token.trim();
      sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x1F]'), '');
      
      if (sanitized != token) {
        print('Instagram token sanitized - removed only whitespace and control chars');
      } else {
        print('Instagram token unchanged after sanitization');
      }
      
      return sanitized;
    }
    
    // Standard handling for other tokens
    // IMPORTANTE: Preserviamo il token esattamente come lo riceviamo, rimuovendo solo spazi e caratteri di controllo
    String sanitized = token.trim();
    
    // Rimuovi SOLO caratteri di controllo invisibili, mantenendo tutti i caratteri speciali
    sanitized = sanitized.replaceAll(RegExp(r'[\x00-\x1F]'), '');
    
    // Salva l'originale per test
    final String originalToken = sanitized;
    
    // Verifica la lunghezza del token
    if (sanitized.length < 50) {
      print('ATTENZIONE: Token Instagram troppo corto (${sanitized.length} caratteri). I token validi sono generalmente più lunghi.');
    }
    
    return sanitized;
  }
  
  // Codifica il token in Base64 se necessario
  String _encodeTokenIfNeeded(String token) {
    try {
      // Se è già in base64, restituisci il token originale
      if (token.length > 100 && RegExp(r'^[A-Za-z0-9+/=]+$').hasMatch(token)) {
        return token;
      }
      
      // Altrimenti, codificalo
      final base64Token = base64Encode(utf8.encode(token));
      print('Encoded token to base64 - original length: ${token.length}, encoded length: ${base64Token.length}');
      return base64Token;
    } catch (e) {
      print('Error encoding token to base64: $e');
      return token;
    }
  }
  
  // Crea un container per il media Instagram
  Future<String?> createMediaContainer({
    required String accountId,
    required String mediaType,
    required String mediaUrl,
    String? caption,
    List<Map<String, String>>? locationInfo,
    List<Map<String, String>>? userTags,
    bool isCarouselItem = false,
  }) async {
    try {
      final apiData = await getInstagramApiFromAccount(accountId);
      if (apiData == null) {
        throw Exception('Account data not found');
      }
      
      final accessToken = apiData['access_token'];
      final userId = apiData['user_id'];
      
      print('Creating Instagram media container for user ID: $userId');
      
      // Prepara la richiesta per creare il container
      final Map<String, dynamic> body = {
        'access_token': accessToken,
        'media_type': mediaType, // IMAGE, VIDEO, REELS, STORIES, CAROUSEL
      };
      
      // Aggiungi URL dell'immagine o del video
      if (mediaType == 'IMAGE' || mediaType == 'STORIES' && mediaUrl.toLowerCase().endsWith('.jpg')) {
        body['image_url'] = mediaUrl;
      } else if (mediaType == 'VIDEO' || mediaType == 'REELS' || (mediaType == 'STORIES' && mediaUrl.toLowerCase().endsWith('.mp4'))) {
        body['video_url'] = mediaUrl;
      }
      
      // Aggiungi caption se fornita
      if (caption != null && caption.isNotEmpty) {
        body['caption'] = caption;
      }
      
      // Aggiungi tag utente se forniti
      if (userTags != null && userTags.isNotEmpty) {
        body['user_tags'] = json.encode(userTags);
      }
      
      // Aggiungi tag location se forniti
      if (locationInfo != null && locationInfo.isNotEmpty) {
        body['location_id'] = locationInfo[0]['id'];
      }
      
      // Se è un elemento di un carosello
      if (isCarouselItem) {
        body['is_carousel_item'] = 'true';
      }
      
      final response = await http.post(
        Uri.parse('https://graph.facebook.com/v22.0/$userId/media'),
        body: body,
      );
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('Successfully created Instagram media container with ID: ${result['id']}');
        return result['id'];
      } else {
        print('Instagram API error: ${response.body}');
        throw Exception('Failed to create Instagram media container: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error creating Instagram media container: $e');
      return null;
    }
  }
  
  // Crea un container per un carosello
  Future<String?> createCarouselContainer({
    required String accountId,
    required List<String> childrenIds,
    String? caption,
  }) async {
    try {
      final apiData = await getInstagramApiFromAccount(accountId);
      if (apiData == null) {
        throw Exception('Account data not found');
      }
      
      final accessToken = apiData['access_token'];
      final userId = apiData['user_id'];
      
      print('Creating Instagram carousel container for user ID: $userId');
      
      // Prepara la richiesta per creare il container carosello
      final Map<String, dynamic> body = {
        'access_token': accessToken,
        'media_type': 'CAROUSEL',
        'children': childrenIds.join(','),
      };
      
      // Aggiungi caption se fornita
      if (caption != null && caption.isNotEmpty) {
        body['caption'] = caption;
      }
      
      final response = await http.post(
        Uri.parse('https://graph.facebook.com/v22.0/$userId/media'),
        body: body,
      );
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('Successfully created Instagram carousel container with ID: ${result['id']}');
        return result['id'];
      } else {
        print('Instagram API error: ${response.body}');
        throw Exception('Failed to create Instagram carousel container: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error creating Instagram carousel container: $e');
      return null;
    }
  }
  
  // Pubblica un container di media
  Future<String?> publishMediaContainer({
    required String accountId,
    required String containerId,
  }) async {
    try {
      final apiData = await getInstagramApiFromAccount(accountId);
      if (apiData == null) {
        throw Exception('Account data not found');
      }
      
      final accessToken = apiData['access_token'];
      final userId = apiData['user_id'];
      
      print('Publishing Instagram media container: $containerId for user ID: $userId');
      
      // Controlla lo stato del container prima di pubblicare
      bool isReady = await checkMediaContainerStatus(accountId, containerId);
      if (!isReady) {
        throw Exception('Media container is not ready for publishing');
      }
      
      // Pubblica il container
      final response = await http.post(
        Uri.parse('https://graph.facebook.com/v22.0/$userId/media_publish'),
        body: {
          'access_token': accessToken,
          'creation_id': containerId,
        },
      );
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        print('Successfully published Instagram media with ID: ${result['id']}');
        return result['id'];
      } else {
        print('Instagram API error: ${response.body}');
        throw Exception('Failed to publish Instagram media: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error publishing Instagram media: $e');
      return null;
    }
  }
  
  // Verifica lo stato di un container con gestione errori migliorata
  Future<bool> checkMediaContainerStatus(String accountId, String containerId) async {
    try {
      final apiData = await getInstagramApiFromAccount(accountId);
      if (apiData == null) return false;
      
      final accessToken = apiData['access_token'];
      
      // Prima prova con token normale
      print('Checking container status with regular token');
      var statusResponse = await http.get(
        Uri.parse('https://graph.facebook.com/v22.0/$containerId?fields=status_code&access_token=$accessToken'),
      );
      
      // Se fallisce, prova con token base64 encoded
      if (statusResponse.statusCode != 200) {
        print('First attempt failed, trying with Base64 encoded token');
        final encodedToken = _encodeTokenIfNeeded(accessToken);
        
        if (encodedToken != accessToken) {
          statusResponse = await http.get(
            Uri.parse('https://graph.facebook.com/v22.0/$containerId?fields=status_code&access_token=$encodedToken'),
          );
        }
      }
      
      if (statusResponse.statusCode == 200) {
        final result = json.decode(statusResponse.body);
        final statusCode = result['status_code'];
        
        print('Instagram media container status: $statusCode');
        
        // Ritorna true solo se lo stato è FINISHED
        return statusCode == 'FINISHED';
      } else {
        print('Error checking media container status: ${statusResponse.body}');
        
        // Controlla errori specifici
        try {
          final errorData = json.decode(statusResponse.body);
          if (errorData['error'] != null && 
              errorData['error']['message'] != null && 
              errorData['error']['message'].contains('Cannot parse access token')) {
            print('Token parsing error detected, will attempt Base64 encoding in future requests');
          }
        } catch (e) {
          // Ignora errori di parsing
        }
        
        return false;
      }
    } catch (e) {
      print('Error checking media container status: $e');
      return false;
    }
  }
  
  // Metodo per verificare che un URL sia accessibile
  Future<bool> _verifyMediaUrl(String url) async {
    try {
      print('Verifying media URL: $url');
      
      // Prova diverse varianti dell'URL se necessario
      List<String> urlVariants = [url];
      
      // Se l'URL è su cloudflarestorage.com, aggiungi una variante con dominio viralyst.online
      if (url.contains('cloudflarestorage.com') && url.contains('videos/')) {
        try {
          // Estrai il percorso del file
          final filePath = url.split('videos/').last;
          urlVariants.add('https://viralyst.online/videos/$filePath');
        } catch (e) {
          print('Error creating URL variant: $e');
        }
      }
      
      // Prova tutti gli URL varianti
      for (final urlToTry in urlVariants) {
        try {
          final response = await http.head(Uri.parse(urlToTry)).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('Timeout', 408),
          );
          
          if (response.statusCode >= 200 && response.statusCode < 400) {
            print('URL is accessible: $urlToTry');
            return true;
          }
        } catch (e) {
          print('Error checking URL variant: $e');
          // Continua con la prossima variante
        }
      }
      
      // Se arriviamo qui, nessun URL era accessibile
      return false;
    } catch (e) {
      print('Error verifying media URL: $e');
      return false;
    }
  }
  
  // Nuovo metodo per recuperare un token base64 archiviato
  Future<String?> _getStoredBase64Token(String accountId, String originalToken) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      // Calcola lo stesso hash usato per salvare il token
      final String tokenHash = originalToken.substring(0, math.min(20, originalToken.length)).hashCode.toString();
      
      // Cerca il token archiviato
      final snapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('instagram_tokens')
          .child(tokenHash)
          .get();
      
      if (!snapshot.exists) {
        print('Nessun token base64 trovato, ne creiamo uno nuovo');
        // Crea e archivia un nuovo token base64
        return await _createAndStoreBase64Token(accountId, originalToken);
      }
      
      // Estrai il token
      final data = snapshot.value as Map<dynamic, dynamic>;
      final base64Token = data['base64Token'] as String?;
      
      if (base64Token == null || base64Token.isEmpty) {
        print('Token base64 trovato ma vuoto, ne creiamo uno nuovo');
        return await _createAndStoreBase64Token(accountId, originalToken);
      }
      
      print('Trovato token base64 archiviato: ${base64Token.substring(0, math.min(10, base64Token.length))}... (${base64Token.length} caratteri)');
      return base64Token;
    } catch (e) {
      print('Errore nel recupero del token base64: $e');
      // In caso di errore, creiamo un nuovo token base64
      return await _createAndStoreBase64Token(accountId, originalToken);
    }
  }
  
  // Nuovo metodo per programmare un post tramite il Cloudflare Worker
  Future<Map<String, dynamic>?> schedulePostViaWorker({
    required String accountId,
    required File mediaFile,
    required String mediaType, // IMAGE, VIDEO, REELS, CAROUSEL
    required String caption,
    required DateTime scheduledTime,
    List<Map<String, String>>? locationInfo,
    List<Map<String, String>>? userTags,
  }) async {
    try {
      print('Scheduling Instagram ${mediaType.toLowerCase()} for account: $accountId at ${scheduledTime.toIso8601String()}');
      
      // Validare la data di pubblicazione
      if (!isValidPublishDate(scheduledTime)) {
        throw Exception('Scheduled time must be at least 15 minutes in the future');
      }
      
      // Prima otteniamo i dati dell'account Instagram
      final token = await getInstagramApiFromAccount(accountId);
      if (token == null || token['access_token'] == null || token['access_token'].isEmpty) {
        throw Exception('Instagram access token not found');
      }
      
      final String accessToken = token['access_token'];
      final bool isInstagramToken = accessToken.startsWith('IG');
      
      print('Instagram token retrieved for account: $accountId');
      if (isInstagramToken) {
        print('Token is in Instagram format (starts with IG)');
      } else {
        print('Token is in standard format, may need base64 encoding');
      }
      
      // Ottieni sia il token normale che quello in base64 (da precedenti salvataggi)
      String? base64Token;
      if (!isInstagramToken) {
        // Only get base64 token for non-Instagram tokens
        base64Token = await _getStoredBase64Token(accountId, accessToken);
        if (base64Token != null && base64Token.isNotEmpty) {
          print('Got base64 encoded token (length: ${base64Token.length})');
        }
      }
      
      // Verifica se il token è valido con una richiesta di test
      try {
        await verifyInstagramToken(accountId);
        print('Instagram token verified successfully');
      } catch (e) {
        print('Error checking token: $e');
        // Continua comunque, poiché il worker proverà diversi formati del token
      }
      
      // Upload del file su Cloudflare
      final cloudflareUrl = await _uploadMediaToStorage(mediaFile);
      
      print('Cloudflare URL for Instagram scheduling: $cloudflareUrl');
      
      // Prepara i dati per la richiesta
      final Map<String, dynamic> requestData = {
        'accountId': accountId,
        'mediaUrl': cloudflareUrl,
        'cloudflareUrl': cloudflareUrl, // Invia entrambi per compatibilità
        'caption': caption,
        'scheduledTime': scheduledTime.millisecondsSinceEpoch,
        'mediaType': mediaType,
        'accessToken': _sanitizeToken(accessToken), // Token originale
      };
      
      // Aggiungi il token base64 se disponibile e se non è un token IG
      if (!isInstagramToken && base64Token != null && base64Token.isNotEmpty) {
        requestData['base64Token'] = base64Token;
        print('Including base64 token in request (length: ${base64Token.length})');
      }
      
      // Aggiungi userId se disponibile
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        requestData['userId'] = currentUser.uid;
      }
      
      // Aggiungi campi opzionali se forniti
      if (locationInfo != null && locationInfo.isNotEmpty) {
        requestData['locationInfo'] = locationInfo;
      }
      
      if (userTags != null && userTags.isNotEmpty) {
        requestData['userTags'] = userTags;
      }
      
      // URL del worker
      final workerUrl = '$instagramSchedulerWorkerUrl/api/schedule';
      print('Preparing to call Instagram scheduler worker at: $workerUrl');
      
      // Nascondi token per il logging
      final Map<String, dynamic> logData = Map.from(requestData);
      if (logData.containsKey('accessToken')) logData['accessToken'] = '***';
      if (logData.containsKey('base64Token')) logData['base64Token'] = '***';
      print('Instagram scheduler request data prepared (excluding sensitive data)');
      
      // Invia la richiesta al worker
      final response = await http.post(
        Uri.parse(workerUrl),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(requestData),
      );
      
      print('Instagram scheduler worker response: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        print('Error response from Instagram scheduler: ${response.statusCode} - ${response.body}');
        
        // Try to parse the error for more details
        try {
          final errorData = jsonDecode(response.body);
          if (errorData['error'] != null) {
            final errorMsg = errorData['error'];
            
            // Check for specific token issues
            if (errorMsg.contains('access token') || errorMsg.contains('token')) {
              print('Token error detected: $errorMsg');
              
              // Log token format for debugging
              if (isInstagramToken) {
                print('Was using Instagram token format (IG prefix)');
              } else if (base64Token != null) {
                print('Was using both standard and base64 token formats');
              } else {
                print('Was using only standard token format');
              }
            }
          }
        } catch (e) {
          // Unable to parse error JSON
          print('Error parsing error response: $e');
        }
        
        throw Exception('Failed to schedule Instagram post: ${response.body}');
      }
      
      // Analizza risposta
      final responseData = jsonDecode(response.body);
      
      print('Instagram scheduler success: ${responseData['success']}');
      
      if (responseData['success'] == true) {
        return responseData;
      } else {
        throw Exception('Failed to schedule Instagram post: ${responseData['error']}');
      }
    } catch (e) {
      print('Error scheduling Instagram post: $e');
      rethrow;
    }
  }
  
  // Upload media to Firebase Storage with enhanced error handling
  Future<String> _uploadMediaToStorage(File mediaFile) async {
    int attempts = 0;
    final maxAttempts = 3;
    
    while (attempts < maxAttempts) {
      try {
        attempts++;
        final fileName = path.basename(mediaFile.path);
        final extension = path.extension(fileName).toLowerCase();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final newFileName = 'instagram_${timestamp}_$fileName';
        
        // Determine content type
        String contentType;
        if (['.jpg', '.jpeg', '.png'].contains(extension)) {
          contentType = 'image/${extension.substring(1)}';
        } else if (['.mp4', '.mov'].contains(extension)) {
          contentType = 'video/${extension.substring(1)}';
        } else {
          contentType = 'application/octet-stream';
        }
        
        print('Uploading file to Firebase Storage (attempt $attempts/$maxAttempts): $newFileName');
        
        // Upload to Firebase Storage
        final storageRef = FirebaseStorage.instance.ref().child('instagram_media').child(newFileName);
        
        final uploadTask = storageRef.putFile(
          mediaFile,
          SettableMetadata(contentType: contentType),
        );
        
        final snapshot = await uploadTask.timeout(Duration(minutes: 5));
        
        // Get download URL
        final downloadUrl = await snapshot.ref.getDownloadURL();
        print('Media uploaded to Firebase Storage: $downloadUrl');
        
        return downloadUrl;
      } catch (e) {
        print('Error uploading media to Firebase Storage (attempt $attempts): $e');
        
        if (attempts >= maxAttempts) {
          print('Maximum upload attempts reached, giving up');
          throw Exception('Failed to upload media after multiple attempts: $e');
        }
        
        // Wait before retrying
        await Future.delayed(Duration(seconds: 3));
      }
    }
    
    throw Exception('Failed to upload media to storage');
  }
  
  // Metodo principale per schedulare un post su Instagram
  Future<Map<String, dynamic>?> scheduleInstagramPost({
    required String accountId,
    required File mediaFile,
    required String mediaType, // IMAGE, VIDEO, REELS, STORIES, CAROUSEL
    required String caption,
    DateTime? scheduledTime,
    List<Map<String, String>>? locationInfo,
    List<Map<String, String>>? userTags,
  }) async {
    try {
      // Se è specificata una data di programmazione, usa il worker
      if (scheduledTime != null) {
        return await schedulePostViaWorker(
          accountId: accountId,
          mediaFile: mediaFile,
          mediaType: mediaType,
          caption: caption,
          scheduledTime: scheduledTime,
          locationInfo: locationInfo,
          userTags: userTags,
        );
      }
      
      try {
        // Altrimenti, pubblica direttamente (comportamento esistente)
        // 1. Carica il file su un server pubblico (es. Cloudflare R2 o altro)
        final String publicUrl = await _uploadMediaToStorage(mediaFile);
        
        // 2. Crea il container per il media
        final containerId = await createMediaContainer(
          accountId: accountId,
          mediaType: mediaType,
          mediaUrl: publicUrl,
          caption: caption,
          locationInfo: locationInfo,
          userTags: userTags,
        );
        
        if (containerId == null) {
          throw Exception('Failed to create media container');
        }
        
        // 3. Verifica se il container è pronto per la pubblicazione
        int attempts = 0;
        bool isReady = false;
        
        while (attempts < 5 && !isReady) {
          isReady = await checkMediaContainerStatus(accountId, containerId);
          if (!isReady) {
            // Attendi prima di riprovare
            await Future.delayed(Duration(seconds: 60));
            attempts++;
          }
        }
        
        if (!isReady) {
          throw Exception('Media container not ready for publishing after multiple attempts');
        }
        
        // 4. Pubblica immediatamente o restituisci i dati per pubblicazione programmata futura
        final mediaId = await publishMediaContainer(
          accountId: accountId,
          containerId: containerId,
        );
        
        if (mediaId == null) {
          throw Exception('Failed to publish media');
        }
        
        return {
          'success': true,
          'id': mediaId,
          'container_id': containerId,
          'media_url': publicUrl,
        };
      } catch (e) {
        print('Error publishing Instagram post directly: $e');
        throw e;
      }
    } catch (e) {
      print('Error scheduling Instagram post: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
  
  // Controlla il limite di pubblicazione
  Future<int> checkPublishingLimit(String accountId) async {
    try {
      final apiData = await getInstagramApiFromAccount(accountId);
      if (apiData == null) return 0;
      
      final accessToken = apiData['access_token'];
      final userId = apiData['user_id'];
      
      final response = await http.get(
        Uri.parse('https://graph.facebook.com/v22.0/$userId/content_publishing_limit?fields=config,quota_usage&access_token=$accessToken'),
      );
      
      if (response.statusCode == 200) {
        final result = json.decode(response.body);
        final quotaUsage = result['data'][0]['quota_usage'];
        return quotaUsage as int;
      } else {
        print('Error checking publishing limit: ${response.body}');
        return 0;
      }
    } catch (e) {
      print('Error checking publishing limit: $e');
      return 0;
    }
  }

  // Verifica il token Instagram con una chiamata di test all'API
  Future<bool> verifyInstagramToken(String accountId) async {
    try {
      // Otteniamo il token
      final accountData = await getInstagramApiFromAccount(accountId);
      if (accountData == null || accountData['access_token'] == null) {
        print('Token Instagram non trovato per account: $accountId');
        return false;
      }
      
      final token = _sanitizeToken(accountData['access_token']);
      if (token.isEmpty) {
        print('Token Instagram vuoto per account: $accountId');
        return false;
      }
      
      // Verifichiamo lo stato dell'account usando l'API di test
      final response = await http.get(
        Uri.parse('https://graph.instagram.com/me?fields=id,username&access_token=$token'),
        headers: {'Accept': 'application/json'},
      );
      
      if (response.statusCode != 200) {
        // Analizza l'errore per dettagli
        print('Errore di verifica token Instagram: ${response.statusCode} - ${response.body}');
        
        // Verifica se il problema è "Cannot parse access token"
        if (response.body.contains('Cannot parse access token')) {
          print('Errore "Cannot parse access token" - il token è nel formato sbagliato');
          
          // Prova a codificare il token in base64 e salvarlo
          await _createAndStoreBase64Token(accountId, token);
        }
        
        return false;
      }
      
      // Decodifica la risposta
      final responseJson = jsonDecode(response.body);
      if (responseJson['id'] != null) {
        print('Token Instagram valido per account: $accountId (id: ${responseJson['id']})');
        
        // Se valido, archivia una versione base64 per uso futuro
        await _createAndStoreBase64Token(accountId, token);
        
        return true;
      }
      
      return false;
    } catch (e) {
      print('Errore durante la verifica del token Instagram: $e');
      return false;
    }
  }
  
  // Crea e archivia un token base64 per uso futuro
  Future<String?> _createAndStoreBase64Token(String accountId, String originalToken) async {
    try {
      // Crea versione base64 del token
      final base64Token = base64Encode(utf8.encode(originalToken));
      print('Creata versione base64 del token: ${base64Token.substring(0, math.min(10, base64Token.length))}... (${base64Token.length} caratteri)');
      
      // Salva il token per uso futuro
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      // Usa un hash del token originale come chiave
      final String tokenHash = originalToken.substring(0, math.min(20, originalToken.length)).hashCode.toString();
      
      await _database
          .child('users')
          .child(currentUser.uid)
          .child('instagram_tokens')
          .child(tokenHash)
          .set({
        'base64Token': base64Token,
        'createdAt': ServerValue.timestamp,
        'accountId': accountId
      });
      
      print('Token base64 archiviato con successo in Firebase');
      return base64Token;
    } catch (e) {
      print('Errore nella creazione e archiviazione del token base64: $e');
      return null;
    }
  }

  // Metodo per eliminare un post Instagram dal KV basandosi su scheduledTime e userId
  Future<bool> deleteInstagramScheduledPost(int scheduledTime, String userId) async {
    const String kvNamespaceId = '40b7c1c068a94aa6b6425a0bccc17bdf';
    try {
      print('Tentativo di eliminazione del post Instagram con scheduledTime: $scheduledTime e userId: $userId');
      // Ottieni tutte le chiavi dal KV
      final listResponse = await http.get(
        Uri.parse('https://api.cloudflare.com/client/v4/accounts/3cd9209da4d0a20e311d486fc37f1a71/storage/kv/namespaces/$kvNamespaceId/keys'),
        headers: {
          'Authorization': 'Bearer WqUFx6CcsU1WdzLmhiLsphw7XcRHGHo2o7xOkFIK',
          'Content-Type': 'application/json',
        },
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
          Uri.parse('https://api.cloudflare.com/client/v4/accounts/3cd9209da4d0a20e311d486fc37f1a71/storage/kv/namespaces/$kvNamespaceId/values/$keyName'),
          headers: {
            'Authorization': 'Bearer WqUFx6CcsU1WdzLmhiLsphw7XcRHGHo2o7xOkFIK',
            'Content-Type': 'application/json',
          },
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
        print('Nessun post Instagram trovato con scheduledTime: $scheduledTime e userId: $userId');
        return false;
      }
      // Elimina la chiave trovata
      final deleteResponse = await http.delete(
        Uri.parse('https://api.cloudflare.com/client/v4/accounts/3cd9209da4d0a20e311d486fc37f1a71/storage/kv/namespaces/$kvNamespaceId/values/$targetKey'),
        headers: {
          'Authorization': 'Bearer WqUFx6CcsU1WdzLmhiLsphw7XcRHGHo2o7xOkFIK',
          'Content-Type': 'application/json',
        },
      );
      if (deleteResponse.statusCode == 200) {
        print('Post Instagram eliminato con successo dal KV: $targetKey');
        return true;
      } else {
        print('Errore durante l\'eliminazione della chiave $targetKey: ${deleteResponse.statusCode} - ${deleteResponse.body}');
        return false;
      }
    } catch (e) {
      print('Eccezione durante l\'eliminazione del post Instagram: $e');
      return false;
    }
  }
} 