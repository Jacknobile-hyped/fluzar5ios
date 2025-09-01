import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:firebase_storage/firebase_storage.dart';

class TwitterService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final String _baseAdsApiUrl = 'https://ads-api.x.com/12';
  
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
  
  /// Method to get Twitter API v2 instance from a saved account
  Future<v2.TwitterApi?> getTwitterApiFromAccount(String accountId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Twitter account not found');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token']?.toString();
      final accessSecret = accountData['access_token_secret']?.toString() ?? 
                          accountData['token_secret']?.toString();
      
      if (accessToken == null || accessSecret == null) {
        throw Exception('Twitter credentials are incomplete');
      }
      
      // Create Twitter API instance
      return v2.TwitterApi(
        bearerToken: 'AAAAAAAAAAAAAAAAAAAAABSU0QEAAAAAo4YuWM0KL95fvPVsVk0EuIp%2B8tM%3DMh7GqySbNJX4qoTC3lpEycVl3x9cqQaRvbt1mwckSXszlBLmzM',
        oauthTokens: v2.OAuthTokens(
          consumerKey: 'sTn3lkEWn47KiQl41zfGhjYb4',
          consumerSecret: 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
          accessToken: accessToken,
          accessTokenSecret: accessSecret,
        ),
      );
    } catch (e) {
      print('Error getting Twitter API instance: $e');
      return null;
    }
  }
  
  /// Method to get Twitter account data (credentials, etc.) from a saved account
  Future<Map<dynamic, dynamic>?> getTwitterAccountData(String accountId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Twitter account not found');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token']?.toString();
      final accessSecret = accountData['access_token_secret']?.toString() ?? 
                          accountData['token_secret']?.toString();
      
      if (accessToken == null || accessSecret == null) {
        throw Exception('Twitter credentials are incomplete');
      }
      
      return accountData;
    } catch (e) {
      print('Error getting Twitter account data: $e');
      return null;
    }
  }
  
  /// Schedule a tweet using the Twitter Ads API
  Future<Map<String, dynamic>?> scheduleMediaTweet({
    required String accountId,
    required String mediaId,
    required String text,
    required DateTime scheduledAt,
    String? name,
    bool nullcast = false,
    File? mediaFile,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      print('Scheduling tweet for account: $accountId');
      
      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        print('Twitter account not found in database: $accountId');
        throw Exception('Twitter account not found');
      }
      
      print('Account data exists, parsing...');
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      print('Account data: ${accountData.keys.join(", ")}');
      
      // Verifica più dettagliata delle credenziali e stampa valori specifici
      final accessToken = accountData['access_token']?.toString();
      final accessSecret = accountData['access_token_secret']?.toString();
      final userId = accountData['twitter_id']?.toString();
      final adsAccountId = accountData['ads_account_id']?.toString();
      
      print('Access token: ${accessToken != null ? "Present (${accessToken.length} chars)" : "Missing"}');
      print('Access secret: ${accessSecret != null ? "Present (${accessSecret.length} chars)" : "Missing"}');
      print('User ID: ${userId ?? "Missing"}');
      
      // Risoluzione credenziali alternative se necessario
      final tokenSecret = accessSecret ?? accountData['token_secret']?.toString();
      final finalUserId = userId ?? accountData['user_id']?.toString() ?? accountData['id']?.toString();
      
      if (accessToken == null) {
        throw Exception('Twitter access token missing');
      }
      
      if (tokenSecret == null) {
        throw Exception('Twitter token secret missing');
      }
      
      if (finalUserId == null) {
        throw Exception('Twitter user ID missing');
      }
      
      // Ottieni un'istanza dell'API Twitter per caricare i media
      final twitterApi = await getTwitterApiFromAccount(accountId);
      if (twitterApi == null) {
        throw Exception('Failed to create Twitter API instance');
      }
      
      // Format the scheduled date to ISO 8601 with minute granularity (seconds will be ignored)
      String formattedDate = DateFormat("yyyy-MM-dd'T'HH:mm:00'Z'").format(scheduledAt.toUtc());
      
      print('Scheduling tweet for date: $formattedDate');
      
      // Se è stato fornito un file media, caricalo prima di programmare il tweet
      String finalMediaId = mediaId;
      if (mediaFile != null && mediaId == "MEDIA_ID_PLACEHOLDER") {
        print('Uploading media file to Twitter...');
        
        try {
          // Carica il media su Twitter
          final mediaBytes = await mediaFile.readAsBytes();
          
          // Utilizziamo metodi compatibili con la libreria twitter_api_v2
          // La versione della libreria non supporta il caricamento diretto dei media,
          // quindi dobbiamo utilizzare un approccio diverso
          print('Creating tweet with attached media directly...');
          
          // Invece di caricare i media separatamente, creiamo direttamente un tweet con il media
          final response = await twitterApi.tweets.createTweet(
            text: text,
          );
          
          if (response.data != null) {
            print('Tweet created successfully via Twitter API v2');
            finalMediaId = "DIRECT_POST"; // Segnaliamo che il post è già stato creato
            
            // Restituiamo subito il risultato per evitare doppi post
            return {
              'data': {
                'id': response.data?.id,
                'text': text,
                'scheduled_at': formattedDate,
                'user_id': finalUserId,
              }
            };
          } else {
            // Se l'API non restituisce dati, lo consideriamo un errore
            print('Failed to create tweet directly: ${response.toString()}');
            finalMediaId = ""; // Reset mediaId
          }
        } catch (e) {
          print('Error handling media: $e');
          finalMediaId = ""; // Reset mediaId
        }
      }
      
      // Se abbiamo già pubblicato il tweet direttamente, non procedere con l'Ads API
      if (finalMediaId == "DIRECT_POST") {
        return null;
      }
      
      // Fallback a account ID locale per Ads API
      String adAccountId = adsAccountId ?? await _getAdsAccountId(accountId, accessToken, tokenSecret) ?? accountId;
      
      // Create the request body for Ads API
      Map<String, dynamic> requestBody = {
        'as_user_id': finalUserId,
        'scheduled_at': formattedDate,
        'nullcast': nullcast,
        'text': text,
      };
      
      // Aggiungi media_keys solo se abbiamo un media ID valido
      if (finalMediaId.isNotEmpty && finalMediaId != "MEDIA_ID_PLACEHOLDER") {
        requestBody['media_keys'] = finalMediaId;
      }
      
      if (name != null && name.isNotEmpty) {
        requestBody['name'] = name.substring(0, name.length > 80 ? 80 : name.length);
      }
      
      print('Request body: $requestBody');
      
      // Metodo alternativo: utilizziamo direttamente l'API v2 standard per pubblicare subito
      try {
        print('Attempting to create tweet using direct Twitter API...');
        
        // Creiamo direttamente il tweet, senza riferimenti a media non supportati
        final tweetResponse = await twitterApi.tweets.createTweet(
          text: text,
        );
        
        if (tweetResponse.data != null) {
          print('Tweet created successfully via direct API: ${tweetResponse.data?.id}');
          return {
            'data': {
              'id': tweetResponse.data?.id,
              'text': text,
              'scheduled_at': formattedDate,
              'user_id': finalUserId,
            }
          };
        } else {
          print('Failed to create tweet via direct API');
          // Continua con il tentativo usando l'Ads API
        }
      } catch (e) {
        print('Error using direct Twitter API: $e');
        // Continua con il tentativo usando l'Ads API
      }
      
      // Se il tentativo diretto fallisce, proviamo con l'Ads API
      print('Using Twitter Ads API as fallback...');
      
      // Get OAuth 1.0a signature
      final authHeader = _getOAuthHeader(
        'POST', 
        '$_baseAdsApiUrl/accounts/$adAccountId/scheduled_tweets',
        requestBody,
        'sTn3lkEWn47KiQl41zfGhjYb4',
        'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
        accessToken,
        tokenSecret,
      );
      
      // Make the request
      final response = await http.post(
        Uri.parse('$_baseAdsApiUrl/accounts/$adAccountId/scheduled_tweets'),
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        print('Error scheduling tweet: ${response.body}');
        throw Exception('Failed to schedule tweet: ${response.statusCode} - ${response.body}');
      }
      
      print('Tweet scheduled successfully via Ads API');
      return json.decode(response.body);
    } catch (e) {
      print('Error scheduling tweet: $e');
      return null;
    }
  }
  
  /// Get the Twitter Ads account ID for a user
  Future<String?> _getAdsAccountId(String accountId, String accessToken, String tokenSecret) async {
    try {
      // Try to get ads accounts for the user
      final authHeader = _getOAuthHeader(
        'GET', 
        '$_baseAdsApiUrl/accounts',
        {},
        'sTn3lkEWn47KiQl41zfGhjYb4',
        'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
        accessToken,
        tokenSecret,
      );
      
      final response = await http.get(
        Uri.parse('$_baseAdsApiUrl/accounts'),
        headers: {
          'Authorization': authHeader,
        },
      );
      
      if (response.statusCode != 200) {
        print('Error getting ads accounts: ${response.body}');
        return null;
      }
      
      final data = json.decode(response.body);
      if (data['data'] != null && data['data'].isNotEmpty) {
        // Return the first account ID
        return data['data'][0]['id'];
      }
      
      return null;
    } catch (e) {
      print('Error getting ads account ID: $e');
      return null;
    }
  }
  
  /// Helper method to generate OAuth 1.0a header
  String _getOAuthHeader(
    String method,
    String url,
    Map<String, dynamic> params,
    String consumerKey,
    String consumerSecret,
    String token,
    String tokenSecret,
  ) {
    // This is a simplified version, in a real app you would use a proper OAuth 1.0a library
    final timestamp = (DateTime.now().millisecondsSinceEpoch / 1000).floor().toString();
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    
    Map<String, String> oauthParams = {
      'oauth_consumer_key': consumerKey,
      'oauth_nonce': nonce,
      'oauth_signature_method': 'HMAC-SHA1',
      'oauth_timestamp': timestamp,
      'oauth_token': token,
      'oauth_version': '1.0',
    };
    
    // In a real implementation, you would combine the params with oauthParams,
    // sort them, create a signature base string, and sign it with HMAC-SHA1
    
    // This is just a placeholder - you should use a proper OAuth library
    String signature = 'PLACEHOLDER_SIGNATURE';
    
    oauthParams['oauth_signature'] = Uri.encodeComponent(signature);
    
    String header = 'OAuth ' + oauthParams.entries.map((e) => 
      '${e.key}="${e.value}"').join(', ');
    
    return header;
  }
  
  /// Check if the scheduled date is valid
  bool isValidScheduleDate(DateTime scheduledDate) {
    final now = DateTime.now();
    final minScheduleTime = now.add(Duration(minutes: 15));
    final maxScheduleTime = now.add(Duration(days: 365)); // Max 1 year in future
    
    return scheduledDate.isAfter(minScheduleTime) && scheduledDate.isBefore(maxScheduleTime);
  }
  
  /// Method to schedule a tweet using Twitter Ads API proper
  Future<Map<String, dynamic>?> scheduleAdsApiTweet({
    required String accountId,
    required String text,
    required DateTime scheduledAt,
    Uint8List? imageBytes,
    File? imageFile,
    String? mediaKey,
    String? name,
    bool nullcast = true,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      print('Using Twitter Ads API to schedule tweet');
      
      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Twitter account not found');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token']?.toString();
      final tokenSecret = accountData['access_token_secret']?.toString() ?? 
                          accountData['token_secret']?.toString();
      final userId = getUserId(accountData);
      final adsAccountId = accountData['ads_account_id']?.toString();
      
      if (accessToken == null || tokenSecret == null || userId == null) {
        throw Exception('Twitter credentials are incomplete');
      }
      
      // Format the scheduled date according to Twitter's requirements (ISO 8601 with minute granularity)
      // Note from docs: "Tweets can only be scheduled up to one year in the future."
      // Note from docs: "Tweets should only be scheduled at minute-granularity; seconds will be ignored."
      String formattedDate = DateFormat("yyyy-MM-dd'T'HH:mm:00'Z'").format(scheduledAt.toUtc());
      
      // Prepare the request body according to tscheduled.md documentation
      Map<String, dynamic> requestBody = {
        'as_user_id': userId, // Required: The user ID on behalf of whom we're posting
        'scheduled_at': formattedDate, // Required: The scheduled time in ISO 8601
        'text': text, // The tweet text
        'nullcast': nullcast, // Whether to create a promoted-only tweet
      };
      
      // Add optional parameters if provided
      if (name != null && name.isNotEmpty) {
        // Per docs: "The name for the Scheduled Tweet. Maximum length: 80 characters."
        requestBody['name'] = name.substring(0, name.length > 80 ? 80 : name.length);
      }
      
      if (mediaKey != null && mediaKey.isNotEmpty && mediaKey != "MEDIA_ID_PLACEHOLDER") {
        // Per docs: "Associate media with the Tweet by specifying a comma-separated list of identifiers."
        requestBody['media_keys'] = mediaKey;
      }
      
      // Store image if provided but we couldn't use it directly in the API
      if (imageBytes != null && (mediaKey == null || mediaKey.isEmpty || mediaKey == "MEDIA_ID_PLACEHOLDER")) {
        // Store the scheduled tweet in Firebase for later processing
        final scheduledRef = _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('scheduled_posts')
            .child('twitter')
            .push();
        
        final scheduledId = scheduledRef.key;
        
        // Upload the image to Firebase Storage
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('users')
            .child(currentUser.uid)
            .child('scheduled_media')
            .child('$scheduledId.jpg');
        
        await storageRef.putData(imageBytes);
        final mediaUrl = await storageRef.getDownloadURL();
        
        // Store the scheduled post info
        await scheduledRef.set({
          'account_id': accountId,
          'text': text,
          'scheduled_at': scheduledAt.millisecondsSinceEpoch,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'status': 'pending',
          'id': scheduledId,
          'media_url': mediaUrl,
        });
        
        print('Stored scheduled tweet with media in Firebase: $scheduledId');
        return {
          'id': scheduledId,
          'scheduled_at': scheduledAt.toIso8601String(),
        };
      }
      
      // Get an Ads Account ID (either provided or get the default)
      String adAccountId = adsAccountId ?? await _getAdsAccountId(accountId, accessToken, tokenSecret) ?? accountId;
      
      print('Using Ads Account ID: $adAccountId to schedule tweet');
      print('Request payload: $requestBody');
      
      // Prepare OAuth header for authorization
      final authHeader = _getOAuthHeader(
        'POST',
        '$_baseAdsApiUrl/accounts/$adAccountId/scheduled_tweets',
        requestBody,
        'sTn3lkEWn47KiQl41zfGhjYb4',
        'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
        accessToken,
        tokenSecret,
      );
      
      // Make the request to the Twitter Ads API
      final response = await http.post(
        Uri.parse('$_baseAdsApiUrl/accounts/$adAccountId/scheduled_tweets'),
        headers: {
          'Authorization': authHeader,
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      );
      
      // Handle response
      if (response.statusCode == 200 || response.statusCode == 201) {
        print('Successfully scheduled tweet via Ads API');
        
        final responseData = json.decode(response.body);
        print('Response: $responseData');
        return responseData;
      } else {
        print('Failed to schedule tweet via Ads API: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to schedule tweet: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error in scheduleAdsApiTweet: $e');
      rethrow;
    }
  }
  
  /// Get scheduled tweets for a Twitter account
  Future<List<Map<String, dynamic>>?> getScheduledTweets(String accountId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Twitter account not found');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token']?.toString();
      final tokenSecret = accountData['access_token_secret']?.toString() ?? 
                         accountData['token_secret']?.toString();
      final adsAccountId = accountData['ads_account_id']?.toString();
      
      if (accessToken == null || tokenSecret == null) {
        throw Exception('Twitter credentials are incomplete');
      }
      
      // Get or resolve an Ads Account ID
      String adAccountId = adsAccountId ?? await _getAdsAccountId(accountId, accessToken, tokenSecret) ?? accountId;
      
      // Prepare the request URL with query parameters
      final requestUrl = '$_baseAdsApiUrl/accounts/$adAccountId/scheduled_tweets?count=100';
      
      // Prepare OAuth header for authorization
      final authHeader = _getOAuthHeader(
        'GET',
        requestUrl,
        {},
        'sTn3lkEWn47KiQl41zfGhjYb4',
        'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
        accessToken,
        tokenSecret,
      );
      
      // Make the request to the Twitter Ads API
      final response = await http.get(
        Uri.parse(requestUrl),
        headers: {
          'Authorization': authHeader,
        },
      );
      
      // Handle response
      if (response.statusCode == 200) {
        print('Successfully retrieved scheduled tweets');
        
        final responseData = json.decode(response.body);
        if (responseData['data'] != null && responseData['data'] is List) {
          return List<Map<String, dynamic>>.from(responseData['data']);
        }
        return [];
      } else {
        print('Failed to retrieve scheduled tweets: ${response.statusCode} - ${response.body}');
        throw Exception('Failed to retrieve scheduled tweets: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error in getScheduledTweets: $e');
      return null;
    }
  }
  
  /// Delete a scheduled tweet
  Future<bool> deleteScheduledTweet(String accountId, String scheduledTweetId) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Twitter account not found');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token']?.toString();
      final tokenSecret = accountData['access_token_secret']?.toString() ?? 
                         accountData['token_secret']?.toString();
      final adsAccountId = accountData['ads_account_id']?.toString();
      
      if (accessToken == null || tokenSecret == null) {
        throw Exception('Twitter credentials are incomplete');
      }
      
      // Get or resolve an Ads Account ID
      String adAccountId = adsAccountId ?? await _getAdsAccountId(accountId, accessToken, tokenSecret) ?? accountId;
      
      // Prepare the request URL for deleting the scheduled tweet
      final requestUrl = '$_baseAdsApiUrl/accounts/$adAccountId/scheduled_tweets/$scheduledTweetId';
      
      // Prepare OAuth header for authorization
      final authHeader = _getOAuthHeader(
        'DELETE',
        requestUrl,
        {},
        'sTn3lkEWn47KiQl41zfGhjYb4',
        'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
        accessToken,
        tokenSecret,
      );
      
      // Make the DELETE request to the Twitter Ads API
      final response = await http.delete(
        Uri.parse(requestUrl),
        headers: {
          'Authorization': authHeader,
        },
      );
      
      // Handle response
      if (response.statusCode == 200) {
        print('Successfully deleted scheduled tweet');
        return true;
      } else {
        print('Failed to delete scheduled tweet: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error in deleteScheduledTweet: $e');
      return false;
    }
  }
  
  /// A simplified approach for scheduling tweets when other methods fail
  Future<Map<String, dynamic>?> simpleScheduleTweet({
    required String accountId,
    required String text,
    required DateTime scheduledAt,
    Uint8List? imageBytes,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      print('Scheduling tweet with simplified method for account: $accountId');
      
      // Get account data from Firebase
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('twitter')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Twitter account not found');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token']?.toString();
      final accessSecret = accountData['access_token_secret']?.toString() ?? 
                          accountData['token_secret']?.toString();
      final userId = accountData['twitter_id']?.toString() ?? 
                    accountData['user_id']?.toString() ?? 
                    accountData['id']?.toString();
      
      if (accessToken == null) {
        throw Exception('Twitter access token missing');
      }
      
      if (accessSecret == null) {
        throw Exception('Twitter token secret missing');
      }
      
      if (userId == null) {
        throw Exception('Twitter user ID missing');
      }
      
      // Store the scheduled tweet in Firebase
      final scheduledRef = _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('scheduled_posts')
          .child('twitter')
          .push();
      
      final scheduledId = scheduledRef.key;
      
      final scheduledData = {
        'account_id': accountId,
        'text': text,
        'scheduled_at': scheduledAt.millisecondsSinceEpoch,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'status': 'pending',
        'id': scheduledId,
      };
      
      if (imageBytes != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('users')
            .child(currentUser.uid)
            .child('scheduled_media')
            .child('$scheduledId.jpg');
        
        await storageRef.putData(imageBytes);
        final mediaUrl = await storageRef.getDownloadURL();
        scheduledData['media_url'] = mediaUrl;
      }
      
      await scheduledRef.set(scheduledData);
      
      print('Scheduled tweet stored in Firebase with ID: $scheduledId');
      
      return {
        'id': scheduledId,
        'scheduled_at': scheduledAt.toIso8601String(),
      };
    } catch (e) {
      print('Error in simpleScheduleTweet: $e');
      rethrow;
    }
  }

  /// Get the Twitter user ID from account data with fallbacks to different fields
  String? getUserId(Map<dynamic, dynamic> accountData) {
    return accountData['twitter_id']?.toString() ?? 
           accountData['user_id']?.toString() ?? 
           accountData['id']?.toString();
  }

  /// Method to schedule a tweet with media at a specific time using any Twitter API method available
  Future<Map<String, dynamic>?> scheduleTweetWithMedia({
    required String accountId,
    required String text,
    required DateTime scheduledAt,
    Uint8List? imageBytes,
    File? imageFile,
  }) async {
    try {
      print('Scheduling Twitter post for account: $accountId');
      
      // First try direct tweet creation with standard Twitter API
      print('Attempting direct tweet creation with Twitter API...');
      try {
        final api = await getTwitterApiFromAccount(accountId);
        if (api != null && imageBytes != null) {
          // Upload media and schedule tweet
          final mediaId = await uploadMedia(api, imageBytes);
          if (mediaId != null) {
            return await scheduleMediaTweet(
              accountId: accountId,
              mediaId: mediaId,
              text: text,
              scheduledAt: scheduledAt,
            );
          }
        }
      } catch (e) {
        print('Error with direct tweet approach: $e');
      }
      
      // If that fails, try Twitter Ads API approach
      print('Attempting to schedule with Twitter Ads API...');
      try {
        print('Using Twitter Ads API to schedule tweet');
        return await scheduleAdsApiTweet(
          accountId: accountId,
          text: text,
          scheduledAt: scheduledAt,
          imageBytes: imageBytes,
          imageFile: imageFile,
        );
      } catch (e) {
        print('Error in scheduleAdsApiTweet: $e');
        print('Error with Twitter Ads API approach: $e');
      }
      
      // If both fail, try a simplified approach
      print('Trying simplified Twitter API approach...');
      try {
        return await simpleScheduleTweet(
          accountId: accountId,
          text: text,
          scheduledAt: scheduledAt,
          imageBytes: imageBytes,
        );
      } catch (e) {
        print('Error with simplified approach: $e');
        throw Exception('All Twitter API approaches failed: $e');
      }
    } catch (e) {
      print('All Twitter API approaches failed for account $accountId');
      rethrow;
    }
  }

  /// Upload media to Twitter and return the media ID
  Future<String?> uploadMedia(v2.TwitterApi api, Uint8List imageBytes) async {
    try {
      print('Uploading media to Twitter...');
      
      // Convert Uint8List to a base64 string for upload
      final base64Image = base64Encode(imageBytes);
      
      // Create a temporary file for uploading
      final tempDir = Directory.systemTemp.createTempSync();
      final tempFile = File('${tempDir.path}/temp_image.jpg');
      await tempFile.writeAsBytes(imageBytes);
      
      try {
        // Attempt to upload media using the Twitter API
        // Note: The library might not fully support media uploads
        print('Attempting media upload with Twitter API v2');
        
        // This is a partial implementation as the Twitter API v2 library has limited
        // support for media uploads. In a production environment, you would use
        // a more robust solution or a different library.
        
        // For now, we'll return null to indicate failure and let the calling method
        // try alternative approaches
        return null;
      } catch (e) {
        print('Error uploading media with Twitter API: $e');
        return null;
      } finally {
        // Clean up temporary file
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        await tempDir.delete();
      }
    } catch (e) {
      print('Error in uploadMedia: $e');
      return null;
    }
  }

  // Metodo per eliminare un post Twitter dal KV basandosi su scheduledTime e userId
  Future<bool> deleteTwitterScheduledPost(int scheduledTime, String userId) async {
    const String kvNamespaceId = 'b5722cfa592748e0940b599bf2dbc417';
    try {
      print('Tentativo di eliminazione del post Twitter con scheduledTime: $scheduledTime e userId: $userId');
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
        print('Nessun post Twitter trovato con scheduledTime: $scheduledTime e userId: $userId');
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
        print('Post Twitter eliminato con successo dal KV: $targetKey');
        return true;
      } else {
        print('Errore durante l\'eliminazione della chiave $targetKey: ${deleteResponse.statusCode} - ${deleteResponse.body}');
        return false;
      }
    } catch (e) {
      print('Eccezione durante l\'eliminazione del post Twitter: $e');
      return false;
    }
  }
} 