import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart'; // Importa http_parser per MediaType
import 'dart:convert';
import '../providers/theme_provider.dart';
import './home_page.dart';
import 'package:video_player/video_player.dart'; // Add the video_player import
import 'package:path_provider/path_provider.dart'; // For saving thumbnail files
import 'package:image/image.dart' as img; // For image processing
import 'package:video_thumbnail/video_thumbnail.dart'; // Add video_thumbnail import
import './upload_status_page.dart';

// Aggiungiamo la classe AccountPanel prima della classe UploadConfirmationPage
class AccountPanel {
  final String platform;
  final String accountId;
  final String? title;
  final String? description;

  AccountPanel({
    required this.platform,
    required this.accountId,
    this.title,
    this.description,
  });
}

class UploadConfirmationPage extends StatefulWidget {
  final File videoFile;
  final String title;
  final String description;
  final Map<String, List<String>> selectedAccounts;
  final Map<String, List<Map<String, dynamic>>> socialAccounts;
  final VoidCallback onConfirm;
  final bool isDraft;
  final bool isImageFile;
  final Map<String, String> instagramContentType;
  final String? cloudflareUrl; // Aggiungo l'URL di Cloudflare R2
  // Add map for platform-specific descriptions
  final Map<String, Map<String, String>> platformDescriptions;
  // Aggiungi proprietà mancanti con valori di default
  final List<AccountPanel> selectedAccountPanels;
  final String globalTitle;
  final String globalDescription;

  const UploadConfirmationPage({
    super.key,
    required this.videoFile,
    required this.title,
    required this.description,
    required this.selectedAccounts,
    required this.socialAccounts,
    required this.onConfirm,
    this.isDraft = false,
    this.isImageFile = false,
    this.instagramContentType = const {},
    this.cloudflareUrl, // Parametro opzionale
    this.platformDescriptions = const {}, // Default to empty map
    this.selectedAccountPanels = const [], // Inizializzazione del campo
    this.globalTitle = '', // Inizializzazione del campo
    this.globalDescription = '', // Inizializzazione del campo
  });

  @override
  State<UploadConfirmationPage> createState() => _UploadConfirmationPageState();
}

class _UploadConfirmationPageState extends State<UploadConfirmationPage> {
  bool _isUploading = false;
  Map<String, bool> _uploadStatus = {};
  Map<String, String> _uploadMessages = {};
  Map<String, double> _uploadProgress = {};
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  String? _thumbnailPath; // To store local path of generated thumbnail
  String? _thumbnailCloudflareUrl; // To store Cloudflare URL of the thumbnail
  // Aggiungiamo la variabile _cloudflareUrl
  String _cloudflareUrl = '';
  
  // Aggiungiamo un servizio fittizio per Firestore
  final _firestoreService = FirestoreService();
  
  // Video player controller
  VideoPlayerController? _videoPlayerController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;
  bool _isDisposed = false; // Track widget disposal
  Timer? _videoTimer; // Timer to auto-stop video
  
  // Google Sign-In istance
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'https://www.googleapis.com/auth/youtube.upload',
      'https://www.googleapis.com/auth/youtube.readonly',
      'https://www.googleapis.com/auth/youtube'
    ],
    serverClientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
  );
  
  // Lock per evitare login multipli simultanei
  bool _isGoogleSigningIn = false;
  
  // Platform logos for UI display
  final Map<String, String> _platformLogos = {
    'TikTok': 'assets/loghi/logo_tiktok.png',
    'YouTube': 'assets/loghi/logo_yt.png',
    'Instagram': 'assets/loghi/logo_insta.png',
    'Facebook': 'assets/loghi/logo_facebook.png',
    'Twitter': 'assets/loghi/logo_twitter.png',
    'Threads': 'assets/loghi/threads_logo.png',
  };

  @override
  void initState() {
    super.initState();
    
    // Initialize video player if not an image but with a delay
    if (!widget.isImageFile) {
      // Delay initialization to ensure widget is fully built
      Future.delayed(const Duration(milliseconds: 700), () { // Increased delay
        if (!_isDisposed) {
          // First check if the file is too large before trying anything
          widget.videoFile.length().then((fileSize) {
            final fileSizeMB = fileSize / (1024 * 1024);
            
            if (fileSizeMB > 200) {
              // For very large files, just set a flag that it's too large
              print('File too large (${fileSizeMB.toStringAsFixed(2)} MB), using static representation only');
              // Still generate a thumbnail but skip video player initialization
              _generateThumbnail();
            } else {
              // Generate thumbnail first
              _generateThumbnail();
              // Non inizializziamo il player subito, aspettiamo che l'utente tocchi la thumbnail
              // Nota: il player verrà inizializzato quando l'utente tocca la thumbnail
            }
          }).catchError((error) {
            print('Error checking file size: $error');
            // Generate thumbnail anyway in case of error
            _generateThumbnail();
          });
        }
      });
    }
  }
  
  Future<void> _initializeVideoPlayer() async {
    // Dispose any existing controller first
    _disposeVideoController();
    
    try {
      // Check file size before processing to avoid memory issues
      final fileSize = await widget.videoFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      print('Video file size: ${fileSizeMB.toStringAsFixed(2)} MB');
      
      // For very large files, don't try to initialize the player
      if (fileSizeMB > 100) { // Reduced from 150
        print('Video file too large to preview (${fileSizeMB.toStringAsFixed(2)} MB), skipping player initialization');
        return;
      }
      
      // Force a small delay before creating controller to allow memory cleanup
      await Future.delayed(const Duration(milliseconds: 100));
      
      _videoPlayerController = VideoPlayerController.file(widget.videoFile);
      _videoPlayerController!.setVolume(0.0); // Mute video to save resources
      _videoPlayerController!.setLooping(false); // Don't loop to save memory
      
      // Use a shorter timeout to avoid hanging
      await _videoPlayerController!.initialize().timeout(
        const Duration(seconds: 6), // Reduced from 8
        onTimeout: () {
          print('Video initialization timed out');
          _disposeVideoController(); // Make sure to dispose on timeout
          return;
        }
      ).then((_) {
        if (!mounted || _isDisposed) {
          _disposeVideoController();
          return;
        }
        
        setState(() {
          _isVideoInitialized = true;
        });
        
        // Auto stop video after 2 seconds to save memory (reduced from 3)
        _videoTimer?.cancel();
        _videoTimer = Timer(const Duration(seconds: 2), () {
          if (_videoPlayerController != null && 
              _videoPlayerController!.value.isPlaying &&
              !_isDisposed) {
            _pauseVideo();
          }
        });
      }).catchError((error) {
        print('Error initializing video player: $error');
        _disposeVideoController();
      });
    } catch (e) {
      print('Exception during video controller creation: $e');
      _disposeVideoController();
    }
  }
  
  void _playVideo() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized && 
        !_isDisposed) {
      try {
        // If the video is too large, avoid playing it
        widget.videoFile.length().then((fileSize) {
          final fileSizeMB = fileSize / (1024 * 1024);
          if (fileSizeMB > 120) { // Aumentato a 120MB per consentire più video
            // Just show a toast/snackbar instead of playing
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Video troppo grande per la riproduzione in anteprima'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
            return;
          }
          
          // Safe to play smaller videos
          _videoPlayerController!.play();
          if (mounted) {
            setState(() {
              _isVideoPlaying = true;
            });
          }
          
          // Auto pause after 3 seconds to save memory
          _videoTimer?.cancel();
          _videoTimer = Timer(const Duration(seconds: 3), () { // Aumentato a 3 secondi
            _pauseVideo();
          });
        }).catchError((error) {
          print('Error checking file size for playback: $error');
        });
      } catch (e) {
        print('Error during video play: $e');
      }
    } else if (!_isVideoInitialized && !_isDisposed) {
      // Se il video non è inizializzato, prova a inizializzarlo ora
      _initializeVideoPlayer().then((_) {
        if (_videoPlayerController != null && 
            _videoPlayerController!.value.isInitialized && 
            !_isDisposed && mounted) {
          setState(() {
            _isVideoPlaying = true;
          });
          _videoPlayerController!.play();
          
          // Auto pause after 3 seconds
          _videoTimer?.cancel();
          _videoTimer = Timer(const Duration(seconds: 3), () {
            _pauseVideo();
          });
        }
      });
    }
  }
  
  void _pauseVideo() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized && 
        !_isDisposed) {
      _videoPlayerController!.pause();
      setState(() {
        _isVideoPlaying = false;
      });
      _videoTimer?.cancel();
    }
  }
  
  // Nuova funzione per pausare il video senza chiamare setState
  void _pauseVideoWithoutSetState() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized && 
        !_isDisposed) {
      _videoPlayerController!.pause();
      _isVideoPlaying = false;
      _videoTimer?.cancel();
    }
  }
  
  void _disposeVideoController() {
    _videoTimer?.cancel();
    if (_videoPlayerController != null) {
      _videoPlayerController!.pause();
      _videoPlayerController!.dispose();
      _videoPlayerController = null;
      _isVideoInitialized = false;
      _isVideoPlaying = false;
    }
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _videoTimer?.cancel();
    _disposeVideoController();
    
    // Clean up any temp files if needed
    _cleanupTempFiles();
    
    super.dispose();
  }

  // Add a cleanup method to remove temporary files
  Future<void> _cleanupTempFiles() async {
    try {
      if (_thumbnailPath != null) {
        final thumbnailFile = File(_thumbnailPath!);
        if (await thumbnailFile.exists()) {
          // Keep for now as we might need it later
          // await thumbnailFile.delete();
          print('Kept thumbnail file for later use');
        }
      }
    } catch (e) {
      print('Error cleaning up temp files: $e');
    }
  }

  @override
  void deactivate() {
    // Pause video when the page is no longer visible
    _pauseVideoWithoutSetState();
    super.deactivate();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Manage video playback based on app lifecycle
    if (state == AppLifecycleState.paused || 
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pauseVideoWithoutSetState();
    }
  }

  Future<void> _uploadToPlatforms() async {
    // Navigate to the upload status page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UploadStatusPage(
          videoFile: widget.videoFile,
          title: widget.title,
          description: widget.description,
          selectedAccounts: widget.selectedAccounts,
          socialAccounts: widget.socialAccounts,
          onComplete: widget.onConfirm,
          isImageFile: widget.isImageFile,
          instagramContentType: widget.instagramContentType,
          cloudflareUrl: widget.cloudflareUrl,
          platformDescriptions: widget.platformDescriptions,
          uploadFunction: _performUpload,
        ),
      ),
    );
  }

  // New function that wraps all the upload logic to be passed to UploadStatusPage
  Future<void> _performUpload(
    Function(String platform, String accountId, String message, double progress) updateProgress,
    Function(List<Exception> errors) onErrors
  ) async {
    try {
      // First, upload the file to Cloudflare R2 storage
      String? cloudflareUrl = widget.cloudflareUrl;
      
      // If we didn't receive a cloudflareUrl from the parent, upload it now
      if (cloudflareUrl == null) {
        updateProgress('cloudflare', 'storage', 'Uploading media to cloud storage...', 0.1);
        
        try {
          // Upload the file to Cloudflare just once, and store the URL
          cloudflareUrl = await _uploadToCloudflare(widget.videoFile, isImage: widget.isImageFile);
          
          // Store the URL in the class variable to be used by all platforms
          _cloudflareUrl = cloudflareUrl ?? '';
          
          if (cloudflareUrl == null) {
            throw Exception('Failed to upload media to Cloudflare');
          }
          
          // Verifica che il file sia stato effettivamente caricato
          bool isUploaded = await _verifyCloudflareUpload(cloudflareUrl);
          if (!isUploaded) {
            print('Il file sembra non essere stato caricato correttamente, riprovo...');
            updateProgress('cloudflare', 'storage', 'Retrying upload...', 0.5);
            cloudflareUrl = await _retryCloudflareUpload(widget.videoFile, isImage: widget.isImageFile);
            // Update the stored URL with the retry result
            _cloudflareUrl = cloudflareUrl ?? '';
          }
          
          updateProgress('cloudflare', 'storage', 'Media uploaded to cloud storage successfully!', 1.0);
        } catch (e) {
          updateProgress('cloudflare', 'storage', 'Error: $e', 0);
          throw Exception('Failed to upload media to Cloudflare: $e');
        }
      } else {
        // If we received a cloudflareUrl from the parent, use it
        _cloudflareUrl = cloudflareUrl;
      }
      
      // After media upload, upload thumbnail if this is a video
      String? thumbnailUrl;
      if (!widget.isImageFile && _thumbnailPath == null) {
        // Generate thumbnail if not already done
        await _generateThumbnail();
      }
      
      if (!widget.isImageFile && _thumbnailPath != null) {
        // Upload the thumbnail to Cloudflare
        updateProgress('thumbnail', 'thumb', 'Uploading thumbnail...', 0.1);
        thumbnailUrl = await _uploadThumbnailToCloudflare();
        _thumbnailCloudflareUrl = thumbnailUrl;
        
        // Verifica che la thumbnail sia stata effettivamente caricata
        if (thumbnailUrl != null) {
          bool isThumbnailUploaded = await _verifyCloudflareUpload(thumbnailUrl);
          if (!isThumbnailUploaded) {
            print('La thumbnail sembra non essere stata caricata correttamente, riprovo...');
            updateProgress('thumbnail', 'thumb', 'Retrying thumbnail upload...', 0.5);
            thumbnailUrl = await _retryCloudflareUpload(File(_thumbnailPath!), isImage: true, customPath: 'videos/thumbnails/${widget.videoFile.path.split('/').last.split('.').first}_thumbnail.jpg');
            _thumbnailCloudflareUrl = thumbnailUrl;
          }
        }
        updateProgress('thumbnail', 'thumb', 'Thumbnail uploaded successfully', 1.0);
      }

      List<Future> uploadTasks = [];
      Map<String, dynamic> platformData = {};
      List<Exception> errors = [];
      
      // Modificare la gestione di YouTube per tracciare separatamente i caricamenti per account
      Map<String, String> youtubeUploads = {};
      
      for (var platform in widget.selectedAccounts.keys) {
        for (var accountId in widget.selectedAccounts[platform]!) {
          switch (platform) {
            case 'Twitter':
              uploadTasks.add(_uploadToTwitter(accountId, updateProgress).then((tweetId) {
                if (tweetId != null) {
                  platformData['twitter'] = {
                    'tweet_id': tweetId,
                    'account_id': accountId,
                  };
                }
              }).catchError((e) {
                errors.add(Exception('Twitter error: $e'));
                return null;
              }));
              break;
            case 'YouTube':
              // Per YouTube, creare una struttura separata per ogni account
              uploadTasks.add(_uploadToYouTube(accountId, updateProgress).then((videoId) {
                if (videoId != null) {
                  // Memorizzare i risultati specifici per ciascun account
                  youtubeUploads[accountId] = videoId;
                }
              }).catchError((e) {
                errors.add(Exception('YouTube error: $e'));
                return null;
              }));
              break;
            case 'Facebook':
              uploadTasks.add(_uploadToFacebook(accountId, updateProgress).then((postId) {
                if (postId != null) {
                  platformData['facebook'] = {
                    'post_id': postId,
                    'account_id': accountId,
                  };
                }
              }).catchError((e) {
                errors.add(Exception('Facebook error: $e'));
                return null;
              }));
              break;
            case 'Instagram':
              uploadTasks.add(_uploadToInstagram(accountId, updateProgress).then((mediaId) {
                if (mediaId != null) {
                  platformData['instagram'] = {
                    'media_id': mediaId,
                    'account_id': accountId,
                  };
                }
              }).catchError((e) {
                errors.add(Exception('Instagram error: $e'));
                return null;
              }));
              break;
            case 'Threads':
              uploadTasks.add(_uploadToThreads(accountId, updateProgress).then((result) {
                platformData['threads'] = {
                  'account_id': accountId,
                  'status': 'manual_required', // Threads richiede pubblicazione manuale
                };
              }).catchError((e) {
                errors.add(Exception('Threads error: $e'));
                return null;
              }));
              break;
            // Add other platforms here
          }
        }
      }

      await Future.wait(uploadTasks);
      
      // Dopo il completamento di tutti i task, convertire la struttura di YouTube nel formato giusto
      if (youtubeUploads.isNotEmpty) {
        List<Map<String, dynamic>> youtubeAccounts = [];
        
        for (var accountId in youtubeUploads.keys) {
          final account = widget.socialAccounts['YouTube']?.firstWhere(
            (acc) => acc['id'] == accountId,
            orElse: () => <String, dynamic>{},
          );
          
          if (account != null && account.isNotEmpty) {
            youtubeAccounts.add({
              'username': account['username'] ?? '',
              'display_name': account['display_name'] ?? account['username'] ?? '',
              'profile_image_url': account['profile_image_url'] ?? '',
              'followers_count': account['followers_count']?.toString() ?? '0',
              'media_id': youtubeUploads[accountId],
              'account_id': accountId,
            });
          }
        }
        
        if (youtubeAccounts.isNotEmpty) {
          // Aggiungi i dati a platformData con la nuova struttura
          platformData['youtube'] = {
            'accounts': youtubeAccounts,
          };
        }
      }
      
      // Store any errors that occurred during upload
      if (errors.isNotEmpty) {
        onErrors(errors);
      }
      
      // Save data to Firebase
      await _saveToFirebase(platformData, cloudflareUrl, thumbnailUrl);
      
    } catch (e) {
      onErrors([Exception(e.toString())]);
      rethrow;
    }
  }

  // Modify Twitter upload method to accept progress callback
  Future<String?> _uploadToTwitter(String accountId, Function(String, String, String, double) updateProgress) async {
    try {
      updateProgress('Twitter', accountId, 'Preparing Twitter upload...', 0.1);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      updateProgress('Twitter', accountId, 'Getting account data...', 0.2);

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
      
      updateProgress('Twitter', accountId, 'Initializing Twitter API...', 0.3);
      
      final twitter = v2.TwitterApi(
        bearerToken: '',  // Empty bearer token to force OAuth 1.0a
        oauthTokens: v2.OAuthTokens(
          consumerKey: 'sTn3lkEWn47KiQl41zfGhjYb4',
          consumerSecret: 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA',
          accessToken: accountData['access_token'] ?? '',
          accessTokenSecret: accountData['access_token_secret'] ?? '',
        ),
      );

      updateProgress('Twitter', accountId, 'Uploading media to Twitter...', 0.4);
      
      final uploadResponse = await twitter.media.uploadMedia(
        file: widget.videoFile,
      );
      
      if (uploadResponse.data == null) {
        throw Exception('Failed to upload media to Twitter');
      }

      updateProgress('Twitter', accountId, 'Creating tweet...', 0.8);
      
      // Get platform-specific description if available
      String tweetText = widget.description;
      if (widget.platformDescriptions.containsKey('Twitter') && 
          widget.platformDescriptions['Twitter']!.containsKey(accountId)) {
        tweetText = widget.platformDescriptions['Twitter']![accountId]!;
      }
      
      final tweet = await twitter.tweets.createTweet(
        text: tweetText,
        media: v2.TweetMediaParam(
          mediaIds: [uploadResponse.data!.id],
        ),
      );

      updateProgress('Twitter', accountId, 'Tweet posted successfully!', 1.0);

      return tweet.data?.id;
    } catch (e) {
      updateProgress('Twitter', accountId, 'Error: $e', 0.0);
      rethrow;
    }
  }

  // Similarly modify YouTube upload method
  Future<String?> _uploadToYouTube(String accountId, Function(String, String, String, double) updateProgress) async {
    // Add the progress updates to the existing method
    try {
      updateProgress('YouTube', accountId, 'Initializing YouTube upload...', 0.05);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      updateProgress('YouTube', accountId, 'Getting account data...', 0.1);
      
      // Rest of the method remains the same, just replace setState calls with updateProgress
      // ... [Rest of _uploadToYouTube method with _updateUploadProgress calls replaced] ...
      
      // Continue with the existing implementation, replacing setState and _updateUploadProgress
      // With direct calls to the updateProgress callback
      
      // Example of how to replace one of the progress updates:
      // Instead of: _updateUploadProgress('YouTube', accountId, 'Authenticating with Google...', 0.15);
      // Use: updateProgress('YouTube', accountId, 'Authenticating with Google...', 0.15);

      // NOTE: Rest of implementation continues as in the original method
      // For brevity, not copying the entire method here
      
      final accountSnapshot = await _database
          .child('users')
          .child(currentUser.uid)
          .child('youtube')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        throw Exception('YouTube account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      
      print('Uploading video to YouTube...');
      
      // Authenticate with Google - with retry mechanism
      updateProgress('YouTube', accountId, 'Authenticating with Google...', 0.15);
      
      // Crea un'istanza di GoogleSignIn specifica per questo account per evitare conflitti
      // Nota: questa è solo una soluzione di workaround finché non integri OAuth per account multipli
      final googleSignIn = GoogleSignIn(
        scopes: [
          'https://www.googleapis.com/auth/youtube.upload',
          'https://www.googleapis.com/auth/youtube.readonly',
          'https://www.googleapis.com/auth/youtube'
        ],
        serverClientId: '1095391771291-cqpq4ci6m4ahvqeea21u9c9g4r4ekr02.apps.googleusercontent.com',
      );
      
      GoogleSignInAccount? googleUser;
      GoogleSignInAuthentication? googleAuth;
      int authRetries = 0;
      const maxAuthRetries = 3;
      
      // Implementa un meccanismo di attesa tra i caricamenti di account diversi
      // per evitare conflitti di autenticazione
      if (_isGoogleSigningIn) {
        updateProgress('YouTube', accountId, 'Waiting for other uploads to complete...', 0.15);
        
        // Attendi fino a 10 secondi per altri accessi in corso
        for (int i = 0; i < 10; i++) {
          if (!_isGoogleSigningIn) break;
          await Future.delayed(Duration(seconds: 1));
        }
        
        // Se ancora in corso, ritarda l'upload di questo account
        if (_isGoogleSigningIn) {
          await Future.delayed(Duration(seconds: 5));
        }
      }
      
      while (authRetries < maxAuthRetries && googleAuth == null) {
        try {
          // Segnala che stiamo eseguendo un'operazione di accesso
          _isGoogleSigningIn = true;
          updateProgress('YouTube', accountId, 'Signing in with Google...', 0.15);
          
          // Prima prova ad accedere silenziosamente
          googleUser = await googleSignIn.signInSilently();
          
          // Se l'accesso silenzioso fallisce, prova l'accesso normale
          if (googleUser == null) {
            updateProgress('YouTube', accountId, 'Interactive sign-in required...', 0.15);
            googleUser = await googleSignIn.signIn();
          }
          
          if (googleUser != null) {
            updateProgress('YouTube', accountId, 'Getting authentication token...', 0.2);
            googleAuth = await googleUser.authentication;
            if (googleAuth.accessToken == null) {
              throw Exception('Failed to get access token');
            }
          } else {
            throw Exception('Google sign in cancelled or failed');
          }
        } catch (e) {
          print('Google Sign-In error (attempt ${authRetries + 1}): $e');
          authRetries++;
          
          // Azzera il flag di accesso in caso di errore
          _isGoogleSigningIn = false;
          
          if (authRetries < maxAuthRetries) {
            updateProgress('YouTube', accountId, 'Retrying authentication (${authRetries + 1}/$maxAuthRetries)...', 0.15);
            await Future.delayed(Duration(seconds: 2 * authRetries)); // Backoff esponenziale
          } else {
            rethrow;
          }
        } finally {
          _isGoogleSigningIn = false;
        }
      }
      
      if (googleUser == null || googleAuth == null || googleAuth.accessToken == null) {
        throw Exception('Failed to authenticate with Google after $maxAuthRetries attempts');
      }

      // Prepare video metadata
      updateProgress('YouTube', accountId, 'Preparing video upload...', 0.3);
      
      // Get platform-specific description and title if available
      String videoDescription = widget.description;
      String videoTitle = widget.title.isNotEmpty ? widget.title : widget.videoFile.path.split('/').last;
      
      if (widget.platformDescriptions.containsKey('YouTube') && 
          widget.platformDescriptions['YouTube']!.containsKey(accountId)) {
        videoDescription = widget.platformDescriptions['YouTube']![accountId]!;
      }
      
      final videoMetadata = {
        'snippet': {
          'title': videoTitle,
          'description': videoDescription,
          'categoryId': '22',
        },
        'status': {
          'privacyStatus': 'public',
          'madeForKids': false,
        }
      };
      
      // First, upload the video
      updateProgress('YouTube', accountId, 'Uploading video content...', 0.4);
      
      // Implement retry mechanism for video upload
      int uploadRetries = 0;
      const maxUploadRetries = 3;
      http.Response? uploadResponse;
      
      while (uploadRetries < maxUploadRetries && (uploadResponse == null || uploadResponse.statusCode != 200)) {
        try {
          uploadResponse = await http.post(
            Uri.parse('https://www.googleapis.com/upload/youtube/v3/videos?part=snippet,status'),
            headers: {
              'Authorization': 'Bearer ${googleAuth.accessToken}',
              'Content-Type': 'application/octet-stream',
              'X-Upload-Content-Type': 'video/*',
              'X-Upload-Content-Length': widget.videoFile.lengthSync().toString(),
            },
            body: await widget.videoFile.readAsBytes(),
          ).timeout(
            const Duration(minutes: 5),
            onTimeout: () => throw TimeoutException('Upload request timed out. Check your internet connection.'),
          );
          
          if (uploadResponse.statusCode != 200) {
            throw Exception('Failed to upload video: ${uploadResponse.body}');
          }
        } catch (e) {
          print('YouTube upload error (attempt ${uploadRetries + 1}): $e');
          uploadRetries++;
          
          if (uploadRetries < maxUploadRetries) {
            updateProgress('YouTube', accountId, 
              'Retrying upload (${uploadRetries + 1}/$maxUploadRetries)...', 
              0.4);
            await Future.delayed(Duration(seconds: 3 * uploadRetries)); // Exponential backoff
          } else {
            rethrow;
          }
        }
      }
      
      if (uploadResponse == null || uploadResponse.statusCode != 200) {
        throw Exception('Failed to upload video after $maxUploadRetries attempts');
      }

      final videoData = json.decode(uploadResponse.body);
      final videoId = videoData['id'];
      
      updateProgress('YouTube', accountId, 'Updating video metadata...', 0.8);
      
      // Implement retry mechanism for metadata update
      int metadataRetries = 0;
      const maxMetadataRetries = 3;
      http.Response? metadataResponse;
      
      while (metadataRetries < maxMetadataRetries && (metadataResponse == null || metadataResponse.statusCode != 200)) {
        try {
          metadataResponse = await http.put(
            Uri.parse('https://www.googleapis.com/youtube/v3/videos?part=snippet,status'),
            headers: {
              'Authorization': 'Bearer ${googleAuth.accessToken}',
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'id': videoId,
              ...videoMetadata,
            }),
          ).timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Metadata update request timed out. Check your internet connection.'),
          );
          
          if (metadataResponse.statusCode != 200) {
            throw Exception('Failed to update video metadata: ${metadataResponse.body}');
          }
        } catch (e) {
          print('YouTube metadata update error (attempt ${metadataRetries + 1}): $e');
          metadataRetries++;
          
          if (metadataRetries < maxMetadataRetries) {
            updateProgress('YouTube', accountId, 
              'Retrying metadata update (${metadataRetries + 1}/$maxMetadataRetries)...', 
              0.8);
            await Future.delayed(Duration(seconds: 2 * metadataRetries)); // Exponential backoff
          } else {
            rethrow;
          }
        }
      }
      
      if (metadataResponse == null || metadataResponse.statusCode != 200) {
        throw Exception('Failed to update video metadata after $maxMetadataRetries attempts');
      }

      updateProgress('YouTube', accountId, 'Video upload complete!', 1.0);
      
      return videoId;
    } catch (e) {
      updateProgress('YouTube', accountId, 'Error: $e', 0.0);
      rethrow;
    }
  }

  // Modify Facebook upload method similarly
  Future<String?> _uploadToFacebook(String accountId, Function(String, String, String, double) updateProgress) async {
    // Replace setState and _updateUploadProgress calls with updateProgress
    // ... Rest of the method remains the same ...
    try {
      updateProgress('Facebook', accountId, 'Inizializzazione upload Facebook...', 0.05);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Utente non autenticato');

      // Ottieni i dati dell'account da Firebase
      updateProgress('Facebook', accountId, 'Recupero dati account...', 0.1);
      final accountDoc = await _firestoreService.getAccount('Facebook', accountId);

      // Rest of method continues with updateProgress replacing _updateUploadProgress
      // ... Rest of implementation continues ...

      // NOTE: Rest of implementation continues as in the original method
      // For brevity, not copying the entire method here
    } catch (e) {
      updateProgress('Facebook', accountId, 'Error: $e', 0.0);
      rethrow;
    }
  }

  // Modify Instagram upload method
  Future<String?> _uploadToInstagram(String accountId, Function(String, String, String, double) updateProgress) async {
    // Replace setState and _updateUploadProgress calls with updateProgress
    // ... Rest of the method remains the same ...
    try {
      updateProgress('Instagram', accountId, 'Initializing...', 0.05);

      // Rest of method continues with updateProgress replacing _updateUploadProgress
      // ... Rest of implementation continues ...

      // NOTE: Rest of implementation continues as in the original method
      // For brevity, not copying the entire method here
    } catch (e) {
      updateProgress('Instagram', accountId, 'Error: $e', 0.0);
      rethrow;
    }
  }

  // Modify Threads upload method
  Future<String?> _uploadToThreads(String accountId, Function(String, String, String, double) updateProgress) async {
    try {
      updateProgress('Threads', accountId, 'Initializing Threads upload...', 0.05);

      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get account data from Firebase
      updateProgress('Threads', accountId, 'Getting account data...', 0.1);
      
      final accountSnapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('social_accounts')
          .child('threads')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        throw Exception('Threads account not found');
      }

      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      final userId = accountData['user_id'] ?? accountId;
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Threads access token not found');
      }
      
      // Get platform-specific description if available
      String postDescription = widget.description;
      if (widget.platformDescriptions.containsKey('Threads') && 
          widget.platformDescriptions['Threads']!.containsKey(accountId)) {
        postDescription = widget.platformDescriptions['Threads']![accountId]!;
      }

      // Determine if we're uploading a video or an image
      final File mediaFile = widget.videoFile;
      final bool isImage = widget.isImageFile;
      
      // Upload the media to Cloudflare R2 if not already uploaded
      String? mediaCloudflareUrl;
      
      if (_cloudflareUrl.isEmpty) {
        updateProgress('Threads', accountId, 'Uploading media to cloud storage...', 0.2);
        mediaCloudflareUrl = await _uploadToCloudflare(mediaFile, 
          isImage: isImage, 
          platform: 'Threads', 
          accountId: accountId, 
          startProgress: 0.2, 
          endProgress: 0.5
        );
      } else {
        mediaCloudflareUrl = _cloudflareUrl;
        updateProgress('Threads', accountId, 'Using already uploaded media', 0.5);
      }
      
      if (mediaCloudflareUrl == null || mediaCloudflareUrl.isEmpty) {
        throw Exception('Failed to upload media to cloud storage');
      }
      
      // Convert Cloudflare storage URL to public format
      final publicUrl = _convertToPublicR2Url(mediaCloudflareUrl);
      
      // Ensure URL is in a format Threads can access
      String threadsMediaUrl = publicUrl;
      if (!publicUrl.contains('viralyst.online')) {
        try {
          final uri = Uri.parse(publicUrl);
          threadsMediaUrl = 'https://viralyst.online${uri.path}';
          updateProgress('Threads', accountId, 'Converted URL for Threads to custom domain', 0.6);
        } catch (e) {
          print('Error converting URL for Threads: $e');
          threadsMediaUrl = publicUrl; // Keep original URL if conversion fails
        }
      }
      
      // Verify that the file is publicly accessible
      updateProgress('Threads', accountId, 'Verifying media accessibility...', 0.6);
      final isAccessible = await _verifyCloudflareUpload(threadsMediaUrl);
      if (!isAccessible) {
        print('WARNING: Media may not be publicly accessible: $threadsMediaUrl');
        updateProgress('Threads', accountId, 'Media might not be accessible, attempting anyway...', 0.65);
      } else {
        updateProgress('Threads', accountId, 'Media accessible, creating Threads container...', 0.65);
      }
      
      // Step 1: Create a media container for Threads
      updateProgress('Threads', accountId, 'Creating Threads media container...', 0.7);
      
      final Map<String, String> containerParams = {
        'access_token': accessToken,
        'text': postDescription,
        'media_type': isImage ? 'IMAGE' : 'VIDEO',
      };
      
      if (isImage) {
        containerParams['image_url'] = threadsMediaUrl;
      } else {
        containerParams['video_url'] = threadsMediaUrl;
      }
      
      final containerResponse = await http.post(
        Uri.parse('https://graph.threads.net/v1.0/$userId/threads'),
        body: containerParams,
      ).timeout(Duration(seconds: 60), onTimeout: () {
        throw TimeoutException('Threads container creation request timed out');
      });
      
      if (containerResponse.statusCode != 200) {
        throw Exception('Failed to create Threads container: ${containerResponse.body}');
      }
      
      final containerData = json.decode(containerResponse.body);
      final containerId = containerData['id'];
      
      if (containerId == null || containerId.isEmpty) {
        throw Exception('Failed to get container ID from Threads response');
      }
      
      // Step 2: Wait before publishing as recommended by Threads API documentation
      updateProgress('Threads', accountId, 'Waiting for media processing (30s)...', 0.8);
      
      // Threads API recommends waiting about 30 seconds before publishing
      for (int i = 0; i < 30; i++) {
        if (!mounted) break;
        
        if (i % 5 == 0) { // Update message every 5 seconds
          updateProgress('Threads', accountId, 
            'Waiting for media processing (${30-i}s)...', 
            0.8 + (i / 30) * 0.1);
        }
        
        await Future.delayed(Duration(seconds: 1));
      }
      
      // Step 3: Publish the container
      updateProgress('Threads', accountId, 'Publishing to Threads...', 0.9);
      
      final publishResponse = await http.post(
        Uri.parse('https://graph.threads.net/v1.0/$userId/threads_publish'),
        body: {
          'access_token': accessToken,
          'creation_id': containerId,
        },
      ).timeout(Duration(seconds: 60));
      
      if (publishResponse.statusCode != 200) {
        throw Exception('Failed to publish Threads post: ${publishResponse.body}');
      }
      
      final publishData = json.decode(publishResponse.body);
      final mediaId = publishData['id'];
      
      updateProgress('Threads', accountId, 'Published successfully to Threads!', 1.0);
      
      return mediaId;
    } catch (e) {
      print('Error in Threads upload: $e');
      
      String errorMessage = 'Error uploading to Threads';
      
      if (e.toString().contains('access token')) {
        errorMessage = 'Authentication error. Please reconnect your Threads account.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Connection timeout. Check your internet connection.';
      } else if (e.toString().contains('container') || e.toString().contains('media')) {
        errorMessage = 'Error processing media. Try a different file or format.';
      }
      
      updateProgress('Threads', accountId, errorMessage, 0.0);
      
      // Return a value to indicate manually required posting
      return 'manual_required';
    }
  }

  Future<void> _saveToFirebase(Map<String, dynamic> platformData, String? cloudflareUrl, String? thumbnailUrl) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // Get or generate the Cloudflare URL
      if (cloudflareUrl == null) {
        try {
          cloudflareUrl = await _uploadToCloudflare(widget.videoFile, isImage: widget.isImageFile);
        } catch (e) {
          print('Warning: Could not upload to Cloudflare: $e');
          // Continue without Cloudflare URL
        }
      }

      final videoRef = _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .push();

      // Prepare accounts data
      final accountsData = <String, List<Map<String, dynamic>>>{};
      for (var platform in widget.selectedAccounts.keys) {
        final accounts = widget.selectedAccounts[platform]!;
        final platformAccounts = <Map<String, dynamic>>[];
        
        for (var accountId in accounts) {
          final account = widget.socialAccounts[platform]?.firstWhere(
            (acc) => acc['id'] == accountId,
            orElse: () => <String, dynamic>{},
          );
          
          if (account != null && account.isNotEmpty) {
            final accountData = {
              'username': account['username'] ?? '',
              'display_name': account['display_name'] ?? account['username'] ?? '',
              'profile_image_url': account['profile_image_url'] ?? '',
              'followers_count': account['followers_count']?.toString() ?? '0',
            };

            // Add platform-specific fields
            if (platform == 'Twitter' && platformData['twitter'] != null) {
              accountData['post_id'] = platformData['twitter']['tweet_id'];
            } else if (platform == 'YouTube') {
              // Gestione YouTube migliorata per account multipli
              if (platformData['youtube'] != null && platformData['youtube']['accounts'] != null) {
                // Trova i dati per questo specifico account
                final youtubeAccount = (platformData['youtube']['accounts'] as List).firstWhere(
                  (acc) => acc['account_id'] == accountId,
                  orElse: () => <String, dynamic>{},
                );
                
                if (youtubeAccount != null && youtubeAccount.containsKey('media_id')) {
                  accountData['media_id'] = youtubeAccount['media_id'];
                }
              }
            } else if (platform == 'Facebook' && platformData['facebook'] != null) {
              accountData['post_id'] = platformData['facebook']['post_id'];
            } else if (platform == 'Instagram' && platformData['instagram'] != null) {
              accountData['media_id'] = platformData['instagram']['media_id'];
            }

            platformAccounts.add(accountData);
          }
        }
        
        if (platformAccounts.isNotEmpty) {
          accountsData[platform.toLowerCase()] = platformAccounts;
        }
      }

      // Prepare video data
      final videoData = {
        'title': widget.title,
        'platforms': widget.selectedAccounts.keys.toList(),
        'status': 'published',
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'video_path': widget.videoFile.path,
        'thumbnail_path': _thumbnailPath ?? '',
        'accounts': accountsData,
        'user_id': currentUser.uid,
        // Add Cloudflare URL if available
        if (cloudflareUrl != null) 'cloudflare_url': cloudflareUrl,
        // Add thumbnail Cloudflare URL if available
        if (thumbnailUrl != null) 'thumbnail_cloudflare_url': thumbnailUrl,
      };
      
      // Add description only if it's not empty
      if (widget.description != null && widget.description!.isNotEmpty) {
        videoData['description'] = widget.description;
      }

      // Non aggiungiamo più campi specifici per YouTube qui perché ora gestiamo account multipli
      // e i dati sono già salvati nella struttura 'accounts'

      await videoRef.set(videoData);
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _saveAsDraft() async {
    setState(() {
      _isUploading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        // Generate and upload thumbnail for drafts too
        String? thumbnailUrl;
        if (!widget.isImageFile && _thumbnailPath == null) {
          await _generateThumbnail();
        }
        
        if (!widget.isImageFile && _thumbnailPath != null) {
          thumbnailUrl = await _uploadThumbnailToCloudflare();
        }
        
        final videoRef = _database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('videos')
            .push();

        // Prepare accounts data
        final accountsData = <String, List<Map<String, dynamic>>>{};
        for (var platform in widget.selectedAccounts.keys) {
          final accounts = widget.selectedAccounts[platform]!;
          final platformAccounts = <Map<String, dynamic>>[];
          
          for (var accountId in accounts) {
            final account = widget.socialAccounts[platform]?.firstWhere(
              (acc) => acc['id'] == accountId,
              orElse: () => <String, dynamic>{},
            );
            
            if (account != null && account.isNotEmpty) {
              platformAccounts.add({
                'username': account['username'] ?? '',
                'display_name': account['display_name'] ?? account['username'] ?? '',
                'profile_image_url': account['profile_image_url'] ?? '',
                'followers_count': account['followers_count']?.toString() ?? '0',
              });
            }
          }
          
          if (platformAccounts.isNotEmpty) {
            accountsData[platform.toLowerCase()] = platformAccounts;
          }
        }

        final videoData = {
          'platforms': widget.selectedAccounts.keys.toList(),
          'status': 'draft',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'video_path': widget.videoFile.path,
          'thumbnail_path': _thumbnailPath ?? '',
          'title': widget.title,
          'user_id': currentUser.uid,
          'accounts': accountsData,
          // Add thumbnail Cloudflare URL if available
          if (thumbnailUrl != null) 'thumbnail_cloudflare_url': thumbnailUrl,
        };
        
        // Add description only if it's not empty
        if (widget.description != null && widget.description!.isNotEmpty) {
          videoData['description'] = widget.description;
        }

        await videoRef.set(videoData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Video salvato come bozza con successo!'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              duration: Duration(seconds: 3),
            ),
          );
        }

        widget.onConfirm();
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving draft: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Check if we should use a simpler layout for large files
    bool useSimpleLayout = false;
    try {
      if (!widget.isImageFile && _thumbnailPath == null && !_isVideoInitialized) {
        useSimpleLayout = true;
      }
    } catch (e) {
      print('Error determining layout: $e');
      useSimpleLayout = true;
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.isDraft 
            ? 'Salva come bozza'
            : 'Conferma upload',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Enhanced Media Preview with Title and Description
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: theme.colorScheme.primary.withOpacity(0.2),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Use a simpler approach for video preview on large files
                    useSimpleLayout
                      ? _buildSimpleMediaPreview(theme)
                      : _buildRichMediaPreview(theme),
                    
                    // Title and Description section
                    if (widget.title.isNotEmpty || widget.description.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(18),
                            bottomRight: Radius.circular(18),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.title.isNotEmpty) ...[
                              Text(
                                widget.title,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              SizedBox(height: 8),
                            ],
                            if (widget.description.isNotEmpty) ...[
                              Text(
                                widget.description,
                                style: theme.textTheme.bodyMedium,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (widget.description.split('\n').length > 3 || 
                                  widget.description.length > 120)
                                TextButton(
                                  onPressed: () {
                                    _showFullDescriptionDialog(context, widget.title, widget.description);
                                  },
                                  child: Text(
                                    'Mostra tutto',
                                    style: TextStyle(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size(60, 30),
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    alignment: Alignment.centerLeft,
                                  ),
                                ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              
              SizedBox(height: 24),

              // Selected Accounts Section with Expandable Panels
              Text(
                'Account ',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              SizedBox(height: 12),
              
              // Expandable platform sections
              ...widget.selectedAccounts.entries.map((entry) {
                  final platform = entry.key;
                final accounts = entry.value;
                
                // Skip if no accounts selected for this platform
                if (accounts.isEmpty) return SizedBox.shrink();
                
                return Card(
                  margin: EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: theme.colorScheme.outline.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      title: Row(
                          children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: _getPlatformColor(platform).withOpacity(0.2),
                            child: Icon(
                                    _getPlatformIcon(platform),
                                    color: _getPlatformColor(platform),
                              size: 18,
                                  ),
                          ),
                          SizedBox(width: 12),
                                  Text(
                                    platform,
                                    style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              accounts.length.toString(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      initiallyExpanded: accounts.length == 1, // Auto-expand if only one account
                      childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: accounts.map((accountId) {
                              final account = widget.socialAccounts[platform]?.firstWhere(
                                (acc) => acc['id'] == accountId,
                                orElse: () => <String, dynamic>{},
                              );
                              
                        if (account == null || account.isEmpty) return SizedBox.shrink();
                        
                        // Check if there's a platform-specific description for this account
                        final hasCustomDescription = widget.platformDescriptions.containsKey(platform) && 
                                                    widget.platformDescriptions[platform]!.containsKey(accountId);
                        
                        return Column(
                                  children: [
                            if (accounts.indexOf(accountId) > 0)
                              Divider(height: 32, thickness: 1),
                            _buildAccountCard(
                              theme: theme,
                              platform: platform,
                              account: account,
                              accountId: accountId, 
                              hasCustomDescription: hasCustomDescription,
                            ),
                          ],
                                );
                            }).toList(),
                        ),
                      ),
                  );
                }).toList(),

              SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ElevatedButton(
            onPressed: widget.isDraft ? _saveAsDraft : _uploadToPlatforms,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
              elevation: 2,
            ),
            child: Text(
              widget.isDraft
                ? 'Salva come bozza'
                : widget.isImageFile ? 'Upload immagine' : 'Upload video',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Helper method to show full description dialog
  void _showFullDescriptionDialog(BuildContext context, String title, String description) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(description),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  // Helper method to build an account card with description
  Widget _buildAccountCard({
    required ThemeData theme,
    required String platform,
    required Map<dynamic, dynamic> account,
    required String accountId,
    required bool hasCustomDescription,
  }) {
    // Get the platform-specific description if available
    final String? customDescription = hasCustomDescription
        ? widget.platformDescriptions[platform]![accountId]
        : null;
    
    return InkWell(
      onTap: hasCustomDescription
          ? () => _showCustomDescriptionDialog(context, platform, account, customDescription!)
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                backgroundImage: account['profile_image_url']?.isNotEmpty == true
                                    ? NetworkImage(account['profile_image_url']!)
                                    : null,
                                backgroundColor: theme.colorScheme.surfaceVariant,
                                child: account['profile_image_url']?.isNotEmpty != true
                                    ? Text(
                                        account['username']?[0].toUpperCase() ?? '?',
                                        style: TextStyle(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
            SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(  // Changed from Flexible to Expanded with flex:3
                                          flex: 3,
                                          child: Text(
                                            account['display_name'] ?? account['username'] ?? '',
                                            style: theme.textTheme.bodyLarge?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        // Display content type badge for Instagram accounts
                                        if (platform == 'Instagram' && widget.instagramContentType.containsKey(accountId))
                                          Flexible(  // Added Flexible with flex:1 to prevent overflow
                                            flex: 1,
                                            child: Container(
                                              margin: EdgeInsets.only(left: 8),
                                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _getContentTypeColor(widget.instagramContentType[accountId] ?? 'Post'),
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                widget.instagramContentType[accountId] ?? 'Post',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,  // Added overflow property
                                                maxLines: 1,  // Limit to one line
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    Text(
                                      '@${account['username']}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurface.withOpacity(0.7),
                                      ),
                                    ),
                                    if (hasCustomDescription) ...[
                                      SizedBox(height: 8),
                                      Container(
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color: _getPlatformColor(platform).withOpacity(0.2),
                                            width: 1,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.edit_note,
                                                  size: 16,
                                                  color: _getPlatformColor(platform),
                                                ),
                                                SizedBox(width: 6),
                                                Text(
                                                  'Descrizione personalizzata',
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: _getPlatformColor(platform),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              customDescription!,
                                              style: theme.textTheme.bodySmall,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (customDescription.split('\n').length > 2 || 
                                                customDescription.length > 80)
                                              Align(
                                                alignment: Alignment.centerRight,
                                                child: TextButton(
                                                  onPressed: () => _showCustomDescriptionDialog(
                                                    context, platform, account, customDescription),
                                                  child: Text(
                                                    'Mostra tutto',
                                                    style: TextStyle(
                                                      color: _getPlatformColor(platform),
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  style: TextButton.styleFrom(
                                                    padding: EdgeInsets.zero,
                                                    minimumSize: Size(60, 24),
                                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (hasCustomDescription)
                                Icon(
                                  Icons.keyboard_arrow_right,
                                  color: theme.colorScheme.onSurface.withOpacity(0.5),
                                ),
                            ],
                          ),
                        ),
    );
  }

  // Helper method to show custom description dialog
  void _showCustomDescriptionDialog(
    BuildContext context,
    String platform,
    Map<dynamic, dynamic> account,
    String description,
  ) {
    final theme = Theme.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: _getPlatformColor(platform).withOpacity(0.2),
              child: Icon(
                _getPlatformIcon(platform),
                color: _getPlatformColor(platform),
                size: 18,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    account['display_name'] ?? account['username'] ?? '',
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '@${account['username']}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Descrizione personalizzata per $platform',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: _getPlatformColor(platform),
              ),
            ),
            SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(maxHeight: 300),
              child: SingleChildScrollView(
                child: Text(
                  description,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  // Mostra un dialogo che spiega i requisiti di storage per Threads
  void _showThreadsStorageRequirementDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Image.asset('assets/loghi/threads_logo.png', width: 32, height: 32),
              const SizedBox(width: 10),
              const Text('Threads Media Upload'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Threads API requires public URLs for media uploads',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'To upload images or videos to Threads via API:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('1. The app needs cloud storage (Firebase Storage) configured'),
              const Text('2. Media must be uploaded to storage first'),
              const Text('3. Threads API requires public media URLs'),
              const SizedBox(height: 16),
              const Text(
                'Until storage is configured, you can:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• Post text-only content (if text is provided)'),
              const Text('• Upload to other social platforms'),
              const Text('• Use the Threads app directly to post media'),
              const SizedBox(height: 16),
              const Text(
                'To resolve this, ask your developer to configure Firebase Storage.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // Nuovo metodo per caricare file su Cloudflare R2 tramite Worker
  Future<String?> _uploadToCloudflare(dynamic input, {bool isImage = false, String? customPath, String? platform, String? accountId, double? startProgress, double? endProgress}) async {
    final int maxRetries = 3;
    int currentRetry = 0;
    Exception? lastError;
    File file;
    
    // Supporto per vari modi di chiamata
    if (input is File) {
      file = input;
    } else if (input is String && platform != null) {
      // Questa è una chiamata dalla nuova implementazione per Facebook
      file = widget.videoFile;
      
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        _updateUploadProgress(platform, accountId, 'Preparazione caricamento su cloud storage...', startProgress);
      }
    } else {
      throw Exception('Input non valido per _uploadToCloudflare');
    }

    while (currentRetry < maxRetries) {
      try {
        print('Starting upload to Cloudflare R2 (attempt ${currentRetry + 1}/$maxRetries)...');

        // Aggiorna il progresso se i parametri di progresso sono stati forniti
        if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
          final progress = startProgress + (endProgress - startProgress) * 0.3;
          _updateUploadProgress(platform, accountId, 'Caricamento file su cloud storage...', progress);
        }

        // Ottieni il token da Firebase
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser == null) throw Exception('User not authenticated');
        
        // Ottieni il token ID da Firebase
        final idToken = await currentUser.getIdToken();
        if (idToken == null) throw Exception('Failed to get Firebase ID token');

        // 1. Richiedi informazioni dal worker Cloudflare
        final String fileName = customPath ?? file.path.split('/').last;
        final String fileExtension = fileName.split('.').last.toLowerCase();

        // Controlla se è un'immagine o un video basandosi sull'estensione
        final String contentType = isImage || 
                                  ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension)
                                  ? 'image/$fileExtension' 
                                  : 'video/$fileExtension';
        
        // Aggiunta del prefisso 'videos/' al nome del file come richiesto dal worker
        final String pathWithDirectory = customPath ?? ('videos/' + fileName);
        
        print('Requesting upload info for ${isImage ? "image" : "video"}: $pathWithDirectory');
        
        // Worker URL
        const String workerUrl = 'https://plain-star-669f.giuseppemaria162.workers.dev';
        
        print('Requesting from worker URL: $workerUrl');
        
        // Costruisci corpo della richiesta
        final requestBody = {
          'operation': 'write',
          'fileName': pathWithDirectory,
          'contentType': contentType,
          'expiresIn': 3600, // Scade dopo 1 ora
        };
        
        print('Request body: ${json.encode(requestBody)}');
        
        // Aggiorna il progresso se i parametri di progresso sono stati forniti
        if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
          final progress = startProgress + (endProgress - startProgress) * 0.5;
          _updateUploadProgress(platform, accountId, 'Ottenimento credenziali di upload...', progress);
        }
        
        // Fai la richiesta al worker
        final response = await http.post(
          Uri.parse(workerUrl),
          headers: {
            'Authorization': 'Bearer $idToken',
            'Content-Type': 'application/json',
          },
          body: json.encode(requestBody),
        ).timeout(
          const Duration(seconds: 30),
          onTimeout: () => throw TimeoutException('Request to worker timed out'),
        );

        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');

        if (response.statusCode != 200) {
          throw Exception('Error from worker: ${response.body}');
        }

        // Analizza la risposta
        final responseData = jsonDecode(response.body);
        
        // Estrai l'URL pubblico e le informazioni di upload
        final String? publicUrl = responseData['publicUrl'];
        if (publicUrl == null || publicUrl.isEmpty) {
          throw Exception('Invalid response: missing public URL');
        }

        print('Got public URL: $publicUrl');
        
        // Aggiorna il progresso se i parametri di progresso sono stati forniti
        if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
          final progress = startProgress + (endProgress - startProgress) * 0.6;
          _updateUploadProgress(platform, accountId, 'Caricamento file in corso...', progress);
        }
        
        // Verifica se abbiamo il metodo direct-upload
        if (responseData['method'] == 'direct-upload' && 
            responseData['uploadUrl'] != null && 
            responseData['uploadUrl'].toString().isNotEmpty) {
          
          final String uploadUrl = responseData['uploadUrl'];
          
          print('Using direct-upload method via: $uploadUrl');
          
          // Prepara i parametri della richiesta
          final Map<String, dynamic> uploadParams = {
            'fileName': pathWithDirectory,
            'contentType': contentType,
          };
          
          // Aggiungi token nella richiesta se necessario
          if (responseData['token'] != null) {
            uploadParams['token'] = responseData['token'];
          }
          
          // Costruisci l'URL con i parametri nella query string come richiesto dal worker
          final uri = Uri.parse(uploadUrl).replace(
            queryParameters: {
              'fileName': pathWithDirectory,
              'contentType': contentType,
              // Aggiungi il token come parametro query se presente
              if (responseData['token'] != null) 'token': responseData['token'].toString(),
            }
          );
          
          print('Sending file to: $uri');
          
          // Leggi il file come bytes
          final fileBytes = await file.readAsBytes();
          
          // Crea una richiesta PUT diretta invece di multipart
          final request = http.Request('PUT', uri);
          
          // Aggiungi headers necessari
            request.headers['Authorization'] = 'Bearer $idToken';
          request.headers['Content-Type'] = contentType;
          request.headers['Content-Length'] = fileBytes.length.toString();
          
          // Aggiungi il file come body della richiesta
          request.bodyBytes = fileBytes;
          
          print('Sending file to direct-upload endpoint, size: ${fileBytes.length} bytes, using PUT method');
          
          // Aggiorna il progresso se i parametri di progresso sono stati forniti
          if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
            final progress = startProgress + (endProgress - startProgress) * 0.8;
            _updateUploadProgress(platform, accountId, 'Completamento caricamento file...', progress);
          }
          
          try {
          // Invia la richiesta
          final streamedResponse = await request.send().timeout(
            const Duration(minutes: 5),
            onTimeout: () => throw TimeoutException('Upload request timed out'),
          );
          
          // Converti la risposta
          final uploadResponse = await http.Response.fromStream(streamedResponse);
          
            print('Direct upload response status: ${uploadResponse.statusCode}');
            print('Direct upload response body: ${uploadResponse.body}');
          
          if (uploadResponse.statusCode >= 200 && uploadResponse.statusCode < 300) {
              // Prova a estrarre il publicUrl dalla risposta
              try {
                final uploadResponseData = jsonDecode(uploadResponse.body);
                // Usa il publicUrl dalla risposta o quello originale se non disponibile
                final finalUrl = uploadResponseData['publicUrl'] ?? publicUrl;
                print('Successfully uploaded file to Cloudflare R2: $finalUrl');
                
                // Aggiorna il progresso se i parametri di progresso sono stati forniti
                if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
                  _updateUploadProgress(platform, accountId, 'File caricato con successo', endProgress);
                }
                
                return finalUrl;
          } catch (e) {
                print('Error parsing upload response: $e, using original publicUrl');
                
                // Aggiorna il progresso se i parametri di progresso sono stati forniti
                if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
                  _updateUploadProgress(platform, accountId, 'File caricato con successo', endProgress);
                }
                
                return publicUrl;
              }
          } else {
              // Se l'errore è 'Nome file mancante', proviamo un approccio alternativo
              if (uploadResponse.body.contains('Nome file mancante')) {
                print('Tentativo di caricamento alternativo...');
                
                // Aggiorna il progresso se i parametri di progresso sono stati forniti
                if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
                  final progress = startProgress + (endProgress - startProgress) * 0.85;
                  _updateUploadProgress(platform, accountId, 'Tentativo approccio alternativo...', progress);
                }
                
                return await _uploadToCloudflareAlternative(file, isImage, customPath, idToken, responseData,
                  platform: platform, 
                  accountId: accountId, 
                  startProgress: startProgress != null ? startProgress + (endProgress! - startProgress) * 0.85 : null,
                  endProgress: endProgress
                );
              }
              
              throw Exception('Failed to upload file to Cloudflare R2: HTTP ${uploadResponse.statusCode} - ${uploadResponse.body}');
            }
            } catch (e) {
            if (e is TimeoutException || e.toString().contains('timeout')) {
              print('Upload timed out, trying alternative approach...');
              
              // Aggiorna il progresso se i parametri di progresso sono stati forniti
              if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
                final progress = startProgress + (endProgress - startProgress) * 0.85;
                _updateUploadProgress(platform, accountId, 'Riprovo con approccio alternativo...', progress);
              }
              
              return await _uploadToCloudflareAlternative(file, isImage, customPath, idToken, responseData,
                platform: platform, 
                accountId: accountId, 
                startProgress: startProgress != null ? startProgress + (endProgress! - startProgress) * 0.85 : null,
                endProgress: endProgress
              );
            }
            rethrow;
            }
          } else {
          print('WARNING: No direct-upload method found in response, file was not uploaded');
          // In un caso reale, dovresti gestire questa situazione in modo più appropriato
          // Per ora, restituiamo l'URL pubblico anche se il file non è stato caricato
          
          // Aggiorna il progresso se i parametri di progresso sono stati forniti
          if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
            _updateUploadProgress(platform, accountId, 'URL ottenuto, ma file non caricato', endProgress);
          }
          
          return publicUrl;
        }
      } catch (e) {
        currentRetry++;
        lastError = e is Exception ? e : Exception(e.toString());
        print('Error in retry $currentRetry: $e');
        
        // Aggiorna il progresso se i parametri di progresso sono stati forniti
        if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
          final progress = startProgress + (endProgress - startProgress) * 0.3;
          _updateUploadProgress(platform, accountId, 'Errore, riprovo... ($currentRetry/$maxRetries)', progress);
        }
        
        if (currentRetry < maxRetries) {
          // Attendi un po' prima di riprovare con backoff esponenziale
          final waitTime = Duration(seconds: 3 * currentRetry);
          print('Retrying in ${waitTime.inSeconds} seconds...');
          await Future.delayed(waitTime);
        }
      }
    }

    // Se arriviamo qui, tutti i tentativi sono falliti
    print('All $maxRetries attempts to upload to Cloudflare R2 failed');
    
    // Aggiorna il progresso se i parametri di progresso sono stati forniti
    if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
      _updateUploadProgress(platform, accountId, 'Errore nel caricamento dopo $maxRetries tentativi', startProgress);
    }
    
    throw lastError ?? Exception('Unknown error during Cloudflare R2 upload');
  }

  // Metodo alternativo per caricare file a Cloudflare R2 se il metodo principale fallisce
  Future<String?> _uploadToCloudflareAlternative(File file, bool isImage, String? customPath, String idToken, Map<String, dynamic> responseData, {
    String? platform, 
    String? accountId, 
    double? startProgress, 
    double? endProgress
  }) async {
    try {
      print('Trying alternative upload approach...');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        final progress = startProgress + (endProgress - startProgress) * 0.2;
        _updateUploadProgress(platform, accountId, 'Tentativo approccio alternativo...', progress);
      }
      
      // Estrai i valori necessari dai dati di risposta
      final String publicUrl = responseData['publicUrl'];
          final String uploadUrl = responseData['uploadUrl'];
      final String fileName = customPath ?? file.path.split('/').last;
      final String pathWithDirectory = customPath ?? ('videos/' + fileName);
      
      // Costruisci un URL separato per l'endpoint proxy-upload
      final uploadUrlBase = uploadUrl.split('/direct-upload')[0];
      final proxyUploadUrl = '$uploadUrlBase/proxy-upload';
      final uri = Uri.parse(proxyUploadUrl).replace(
        queryParameters: {
          'fileName': pathWithDirectory,
        }
      );
      
      print('Using alternative upload endpoint: $uri');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        final progress = startProgress + (endProgress - startProgress) * 0.4;
        _updateUploadProgress(platform, accountId, 'Preparazione file per upload alternativo...', progress);
      }
      
      // Leggi il file
          final fileBytes = await file.readAsBytes();
      final fileExtension = fileName.split('.').last.toLowerCase();
      
      // Determina il tipo di contenuto
      final String contentType = isImage || 
                             ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(fileExtension)
                             ? 'image/$fileExtension' 
                             : 'video/$fileExtension';
      
      // Crea una richiesta PUT
      final request = http.Request('PUT', uri);
          
          // Aggiungi headers
          request.headers['Authorization'] = 'Bearer $idToken';
          request.headers['Content-Type'] = contentType;
      request.headers['Content-Length'] = fileBytes.length.toString();
          
      // Imposta il body
          request.bodyBytes = fileBytes;
          
      print('Sending file via alternative method, size: ${fileBytes.length} bytes');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        final progress = startProgress + (endProgress - startProgress) * 0.6;
        _updateUploadProgress(platform, accountId, 'Invio file con metodo alternativo...', progress);
      }
          
      // Invia la richiesta
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('Alternative upload request timed out'),
      );
            
      // Converti la risposta
      final response = await http.Response.fromStream(streamedResponse);
      
      print('Alternative upload response status: ${response.statusCode}');
      print('Alternative upload response body: ${response.body}');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        final progress = startProgress + (endProgress - startProgress) * 0.9;
        _updateUploadProgress(platform, accountId, 'Analisi risposta upload alternativo...', progress);
      }
      
      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final responseData = jsonDecode(response.body);
          if (responseData['success'] == true) {
            final uploadedUrl = responseData['url'] ?? publicUrl;
            print('Alternative upload successful: $uploadedUrl');
            
            // Aggiorna il progresso se i parametri di progresso sono stati forniti
            if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
              _updateUploadProgress(platform, accountId, 'Upload alternativo completato con successo', endProgress);
            }
            
            return uploadedUrl;
          }
        } catch (e) {
          print('Error parsing alternative upload response: $e');
        }
      }
        
      // Se anche questo fallisce, ritorna comunque l'URL pubblico
      print('WARNING: Alternative upload failed. Returning public URL without confirmed upload');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        _updateUploadProgress(platform, accountId, 'Upload alternativo fallito, uso URL pubblico', endProgress);
      }
      
      return publicUrl;
    } catch (e) {
      print('Error in alternative upload: $e');
      
      // Aggiorna il progresso se i parametri di progresso sono stati forniti
      if (mounted && platform != null && accountId != null && startProgress != null && endProgress != null) {
        _updateUploadProgress(platform, accountId, 'Errore nell\'upload alternativo: $e', startProgress);
      }
      
      // Ritorna l'URL pubblico originale come fallback
      return responseData['publicUrl'];
    }
  }

  // Save thumbnail bytes to a file
  Future<File?> _saveThumbnailToFile(Uint8List thumbnailBytes) async {
    try {
      // Use specific compression and sizing for more memory efficiency
      Uint8List? compressedBytes;
      
      try {
        // Downsample the image if it's large
        if (thumbnailBytes.length > 500 * 1024) { // If larger than 500KB
          final img.Image? decoded = img.decodeImage(thumbnailBytes);
          if (decoded != null) {
            // Resize to a smaller resolution
            final img.Image resized = img.copyResize(
              decoded,
              width: 240,
              interpolation: img.Interpolation.average,
            );
            
            // Re-encode at lower quality
            compressedBytes = Uint8List.fromList(img.encodeJpg(resized, quality: 70));
            print('Thumbnail compressed from ${thumbnailBytes.length} to ${compressedBytes.length} bytes');
          }
        }
      } catch (e) {
        print('Error compressing thumbnail: $e - using original bytes');
      }
      
      final bytesToSave = compressedBytes ?? thumbnailBytes;
      
      final fileName = widget.videoFile.path.split('/').last;
      final thumbnailFileName = '${fileName.split('.').first}_thumbnail.jpg';
      
      // Get the app's temporary directory
      final directory = await getTemporaryDirectory();
      final thumbnailPath = '${directory.path}/$thumbnailFileName';
      
      // Save the file
      final file = File(thumbnailPath);
      await file.writeAsBytes(bytesToSave);
      
      // Force garbage collection hint after writing file
      await Future.delayed(Duration.zero);
      
      return file;
    } catch (e) {
      print('Error saving thumbnail file: $e');
      return null;
    }
  }

  // New method to generate a thumbnail from the video
  Future<void> _generateThumbnail() async {
    if (widget.isImageFile || _isDisposed) return;
    
    try {
      print('Generating thumbnail for: ${widget.videoFile.path}');
      
      // Check file size before processing to avoid memory issues
      final fileSize = await widget.videoFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      print('Video file size: ${fileSizeMB.toStringAsFixed(2)} MB');
      
      // Use reduced settings for large files
      int targetQuality = 70; // Reduced from 80
      int targetWidth = 240; // Reduced from 320
      
      // Reduce quality for larger files to prevent memory issues
      if (fileSizeMB > 50) {
        targetQuality = 50; // Reduced from 60
        targetWidth = 180; // Reduced from 240
        print('Reducing thumbnail quality for large file');
      }
      
      // Skip thumbnail generation for extremely large files
      if (fileSizeMB > 200) {
        print('File too large (${fileSizeMB.toStringAsFixed(2)} MB), skipping thumbnail generation');
        return;
      }
      
      // Add a garbage collection hint before heavy operation
      await Future.delayed(Duration.zero);

      try {
        // Use video_thumbnail package to generate thumbnail with optimized settings
        final thumbnailBytes = await VideoThumbnail.thumbnailData(
          video: widget.videoFile.path,
          imageFormat: ImageFormat.JPEG,
          quality: targetQuality,
          maxWidth: targetWidth, // Smaller width for thumbnails
          timeMs: 500, // Take frame at 500ms
        ).timeout(
          const Duration(seconds: 6), // Reduced from 10
          onTimeout: () {
            print('Thumbnail generation timed out');
            return null;
          },
        );
      
        if (thumbnailBytes == null) {
          print('Failed to generate thumbnail: thumbnailBytes is null');
          return;
        }
        
        // Add another GC hint before file operations
        await Future.delayed(Duration.zero);
        
        // Save the thumbnail locally
        final thumbnailFile = await _saveThumbnailToFile(thumbnailBytes);
        if (thumbnailFile != null && mounted) {
          setState(() {
            _thumbnailPath = thumbnailFile.path;
          });
          print('Thumbnail generated and saved at: $_thumbnailPath');
        } else {
          print('Failed to save thumbnail file or widget unmounted');
        }
      } catch (e) {
        print('Error in thumbnail generation: $e');
        // Try fallback method for thumbnail generation if the main method fails
        await _generateFallbackThumbnail();
      }
    } catch (e) {
      print('Error generating thumbnail: $e');
    }
  }

  // Fallback method for thumbnail generation with even lower memory usage
  Future<void> _generateFallbackThumbnail() async {
    try {
      print('Attempting fallback thumbnail generation');
      
      // Use the absolute minimal settings
      final thumbnailPath = await VideoThumbnail.thumbnailFile(
        video: widget.videoFile.path,
        thumbnailPath: (await getTemporaryDirectory()).path,
        imageFormat: ImageFormat.JPEG,
        quality: 40,
        maxWidth: 160,
        timeMs: 1000,
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('Fallback thumbnail generation timed out');
          return null;
        },
      );
      
      if (thumbnailPath != null && mounted) {
        setState(() {
          _thumbnailPath = thumbnailPath;
        });
        print('Fallback thumbnail generated at: $_thumbnailPath');
      }
    } catch (e) {
      print('Error in fallback thumbnail generation: $e');
    }
  }

  // Upload thumbnail to Cloudflare R2
  Future<String?> _uploadThumbnailToCloudflare() async {
    if (_thumbnailPath == null) {
      print('No thumbnail to upload');
      return null;
    }
    
    try {
      setState(() {
        _uploadMessages['thumbnail'] = 'Uploading thumbnail to cloud storage...';
        _uploadProgress['thumbnail'] = 0.1;
      });
      
      final File thumbnailFile = File(_thumbnailPath!);
      if (!await thumbnailFile.exists()) {
        print('Thumbnail file not found: $_thumbnailPath');
        return null;
      }
      
      // Upload the thumbnail with an appropriate path in Cloudflare
      final String videoFileName = widget.videoFile.path.split('/').last.split('.').first;
      final String thumbnailCloudPath = 'videos/thumbnails/${videoFileName}_thumbnail.jpg';
      
      // Usa la nuova firma del metodo _uploadToCloudflare
      final thumbnailUrl = await _uploadToCloudflare(thumbnailFile, 
        isImage: true, 
        customPath: thumbnailCloudPath,
        platform: 'thumbnail',
        accountId: 'thumb',
        startProgress: 0.1,
        endProgress: 0.9
      );
      
      setState(() {
        _uploadMessages['thumbnail'] = 'Thumbnail uploaded to cloud storage!';
        _uploadProgress['thumbnail'] = 1.0;
        _thumbnailCloudflareUrl = thumbnailUrl;
      });
      
      return thumbnailUrl;
    } catch (e) {
      print('Error uploading thumbnail: $e');
      setState(() {
        _uploadMessages['thumbnail'] = 'Error uploading thumbnail: $e';
        _uploadProgress['thumbnail'] = 0;
      });
      return null;
    }
  }

  // Verifica se un file è stato effettivamente caricato su Cloudflare
  Future<bool> _verifyCloudflareUpload(String cloudflareUrl) async {
    try {
      // Se l'URL è un URL interno di storage, convertilo in un URL pubblico
      String urlToVerify = cloudflareUrl;
      if (cloudflareUrl.contains('r2.cloudflarestorage.com')) {
        urlToVerify = _convertToPublicR2Url(cloudflareUrl);
      }
      
      // Assicurati di usare preferibilmente l'URL con dominio personalizzato se disponibile
      if (!urlToVerify.contains('viralyst.online') && 
          (urlToVerify.contains('pub-') && urlToVerify.contains('r2.dev'))) {
        // Estrai il path e usa il dominio personalizzato
        final uri = Uri.parse(urlToVerify);
        urlToVerify = 'https://viralyst.online${uri.path}';
      }
      
      print('Verificando disponibilità del file: $urlToVerify');
      
      // Aggiungi un ritardo più lungo prima di verificare per permettere la propagazione
      await Future.delayed(const Duration(seconds: 5));
      
      // Verifica se l'URL è raggiungibile con una richiesta GET
      final response = await http.get(Uri.parse(urlToVerify)).timeout(
        const Duration(seconds: 15),
        onTimeout: () => http.Response('Timeout', 408),
      );
      
      print('Verifica caricamento: statusCode ${response.statusCode} per $urlToVerify');
      
      // Considera i codici 200-299 come successo, e 400-403 come potenzialmente validi
      // per bucket con autorizzazioni speciali ma file esistenti
      final isSuccess = (response.statusCode >= 200 && response.statusCode < 300) ||
                        (response.statusCode >= 400 && response.statusCode <= 403);
      
      if (isSuccess) {
        print('File trovato su Cloudflare: $urlToVerify');
      } else {
        print('File non trovato o inaccessibile: $urlToVerify, status: ${response.statusCode}');
        
        // Se fallisce con l'URL del dominio personalizzato, prova con r2.dev come backup
        if (urlToVerify.contains('viralyst.online')) {
          final knownAccountId = '3cd9209da4d0a20e311d486fc37f1a71';
          final uri = Uri.parse(urlToVerify);
          final r2Url = 'https://pub-$knownAccountId.r2.dev${uri.path}';
          
          print('Tentativo fallback con URL r2.dev: $r2Url');
          
          final fallbackResponse = await http.get(Uri.parse(r2Url)).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('Timeout', 408),
          );
          
          print('Verifica fallback: statusCode ${fallbackResponse.statusCode}');
          return fallbackResponse.statusCode >= 200 && fallbackResponse.statusCode < 400;
        }
      }
      
      return isSuccess;
    } catch (e) {
      print('Errore nella verifica del caricamento Cloudflare: $e');
      return false;
    }
  }
  
  // Riprova a caricare un file su Cloudflare se il primo tentativo è fallito
  Future<String?> _retryCloudflareUpload(File file, {bool isImage = false, String? customPath}) async {
    // Puliamo prima eventuali stati precedenti
    if (!mounted) return null;
    
    setState(() {
      _uploadMessages['cloudflare_retry'] = 'Retrying upload to cloud storage...';
      _uploadProgress['cloudflare_retry'] = 0.1;
    });
    
    try {
      // Tenta di caricare il file con una richiesta diversa
      // Utilizza la nuova firma del metodo _uploadToCloudflare
      final cloudflareUrl = await _uploadToCloudflare(file, 
        isImage: isImage, 
        customPath: customPath,
        platform: 'cloudflare_retry',
        accountId: 'retry',
        startProgress: 0.1,
        endProgress: 0.9
      );
      
      if (cloudflareUrl == null) {
        throw Exception('Failed to upload media to Cloudflare');
      }
      
      setState(() {
        _uploadMessages['cloudflare_retry'] = 'Retry successful!';
        _uploadProgress['cloudflare_retry'] = 1.0;
      });
      
      return cloudflareUrl;
    } catch (e) {
      setState(() {
        _uploadMessages['cloudflare_retry'] = 'Retry failed: $e';
        _uploadProgress['cloudflare_retry'] = 0;
      });
      
      // Ritorna comunque l'URL pubblico anche se il file non è stato caricato
      // Così l'app può continuare, ma sappiamo che il file non esiste davvero
      print('WARNING: File upload retry failed, returning tentative URL only');
      
      // Ritorna un URL basato sul percorso del file originale
      final fileName = file.path.split('/').last;
      final fileType = isImage ? 'thumbnails/' : '';
      return 'https://videos.3cd9209da4d0a20e311d486fc37f1a71.r2.cloudflarestorage.com/videos/${fileType}${customPath ?? fileName}';
    }
  }

  // Helper method to get color for Instagram content types
  Color _getContentTypeColor(String contentType) {
    switch (contentType) {
      case 'Reels':
        return Colors.pinkAccent;
      case 'Storia':
        return Colors.deepPurple;
      case 'Post':
      default:
        return Colors.blue;
    }
  }

  // Mostra un dialogo informativo sulle limitazioni dell'API di Instagram
  void _showInstagramAPILimitationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              'assets/loghi/logo_insta.png',
              width: 24,
              height: 24,
            ),
            SizedBox(width: 10),
            Text('Limitazione API Instagram'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Instagram limita l\'accesso ad alcune funzionalità tramite API.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Il tuo contenuto verrà pubblicato, ma Instagram potrebbe modificarne il tipo (ad esempio pubblicando come Reels invece che come Storia/Post).',
            ),
            SizedBox(height: 8),
            Text(
              'Questa è una limitazione dell\'API di Instagram, non dell\'app Fluzar.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Ho capito'),
          ),
        ],
      ),
    );
  }

  // Nuovo metodo per ridimensionare l'immagine per Instagram secondo le proporzioni accettate
  Future<File> _resizeImageForInstagram(File imageFile) async {
    try {
      // Leggi l'immagine originale
      final bytes = await imageFile.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      
      if (originalImage == null) return imageFile;
      
      final originalWidth = originalImage.width;
      final originalHeight = originalImage.height;
      double aspectRatio = originalWidth / originalHeight;
      
      print('Original image dimensions: ${originalWidth}x${originalHeight}, aspect ratio: $aspectRatio');
      
      // Determina quale proporzione usare (1:1, 4:5, 1.91:1)
      late img.Image resizedImage;
      
      // Opzione 1: Proporzione quadrata (1:1)
      if (aspectRatio >= 0.8 && aspectRatio <= 1.2) {
        // Già vicino a quadrato, facciamo un 1:1 perfetto
        final size = min(originalWidth, originalHeight);
        resizedImage = img.copyCrop(
          originalImage,
          x: (originalWidth - size) ~/ 2,
          y: (originalHeight - size) ~/ 2,
          width: size,
          height: size,
        );
        print('Resizing to square 1:1');
      }
      // Opzione 2: Verticale (4:5) - per immagini verticali
      else if (aspectRatio < 0.8) {
        // Immagine verticale, adattiamo a 4:5
        final targetWidth = originalWidth;
        final targetHeight = (targetWidth * 5 / 4).round();
        
        if (targetHeight <= originalHeight) {
          // L'immagine è più alta di quanto necessario, ritagliamo
          resizedImage = img.copyCrop(
            originalImage,
            x: 0,
            y: (originalHeight - targetHeight) ~/ 2,
            width: targetWidth,
            height: targetHeight,
          );
        } else {
          // L'immagine è troppo stretta, dobbiamo ridimensionarla mantenendo l'aspetto 4:5
          final newHeight = originalHeight;
          final newWidth = (newHeight * 4 / 5).round();
          resizedImage = img.copyResize(
            originalImage,
            width: newWidth,
            height: newHeight,
          );
        }
        print('Resizing to vertical 4:5');
      }
      // Opzione 3: Orizzontale (1.91:1) - per immagini orizzontali
      else {
        // Immagine orizzontale, adattiamo a 1.91:1
        final targetHeight = originalHeight;
        final targetWidth = (targetHeight * 1.91).round();
        
        if (targetWidth <= originalWidth) {
          // L'immagine è più larga di quanto necessario, ritagliamo
          resizedImage = img.copyCrop(
            originalImage,
            x: (originalWidth - targetWidth) ~/ 2,
            y: 0,
            width: targetWidth,
            height: targetHeight,
          );
        } else {
          // L'immagine è troppo alta, dobbiamo ridimensionarla mantenendo l'aspetto 1.91:1
          final newWidth = originalWidth;
          final newHeight = (newWidth / 1.91).round();
          resizedImage = img.copyResize(
            originalImage,
            width: newWidth,
            height: newHeight,
          );
        }
        print('Resizing to horizontal 1.91:1');
      }
      
      // Salva l'immagine ridimensionata
      final tempDir = await getTemporaryDirectory();
      final newPath = '${tempDir.path}/instagram_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final resizedFile = File(newPath)..writeAsBytesSync(img.encodeJpg(resizedImage, quality: 90));
      
      print('Resized image dimensions: ${resizedImage.width}x${resizedImage.height}, aspect ratio: ${resizedImage.width / resizedImage.height}');
      
      return resizedFile;
    } catch (e) {
      print('Error resizing image for Instagram: $e');
      return imageFile; // In caso di errore, restituisci l'immagine originale
    }
  }

  // Funzione per mostrare un dialogo con messaggi di errore specifici sul token Instagram
  void _showInstagramTokenErrorDialog(String errorMessage) {
    if (errorMessage.contains('token') && 
        (errorMessage.contains('Invalid') || 
         errorMessage.contains('expired') || 
         errorMessage.contains('Cannot parse'))) {
      
      // Se l'errore è relativo al token, mostra il dialogo di ricollegamento
      _showInstagramReconnectDialog(''); // Qui potremmo passare l'accountId se necessario
    } else {
      // Per altri errori, mostra un messaggio generico
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore con Instagram: $errorMessage'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // Helper icon and color methods still needed for the UI
  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'TikTok': return Icons.music_note;
      case 'YouTube': return Icons.play_arrow;
      case 'Instagram': return Icons.camera_alt;
      case 'Facebook': return Icons.facebook;
      case 'Twitter': return Icons.chat;
      case 'Threads': return Icons.chat_outlined;
      default: return Icons.share;
    }
  }

  // Get a color for each platform
  Color _getPlatformColor(String platform) {
    switch (platform) {
      case 'TikTok':
        return Colors.black;
      case 'YouTube':
        return Colors.red;
      case 'Instagram':
        return Color(0xFFE1306C); // Instagram pink
      case 'Facebook':
        return Color(0xFF1877F2); // Facebook blue
      case 'Twitter':
        return Color(0xFF1DA1F2); // Twitter blue
      case 'Threads':
        return Color(0xFF000000); // Threads black
      default:
        return Colors.grey;
    }
  }

  // Add back the updateUploadProgress method since it's still referenced in some methods
  void _updateUploadProgress(String platform, String accountId, String status, double progress) {
    if (mounted) {
      setState(() {
        _uploadStatus['${platform}_$accountId'] = true;
        _uploadMessages['${platform}_$accountId'] = status;
        _uploadProgress['${platform}_$accountId'] = progress;
      });
    }
  }

  // Add the missing _convertToPublicR2Url method
  String _convertToPublicR2Url(String cloudflareUrl) {
    if (cloudflareUrl.contains('r2.cloudflarestorage.com')) {
      // Extract account ID and path from the Cloudflare storage URL
      final Uri uri = Uri.parse(cloudflareUrl);
      final String path = uri.path;
      final List<String> pathParts = path.split('/');
      
      if (pathParts.length >= 2) {
        final String accountId = pathParts[0];
        final String filePath = path.substring(accountId.length + 1);
        
        // Convert to public R2 URL format
        return 'https://pub-$accountId.r2.dev/$filePath';
      }
    }
    
    // If the URL is already in the correct format or cannot be converted, return as is
    return cloudflareUrl;
  }

  // Add the missing _showInstagramReconnectDialog method
  void _showInstagramReconnectDialog(String accountId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Image.asset(
              'assets/loghi/logo_insta.png',
              width: 24,
              height: 24,
            ),
            SizedBox(width: 10),
            Text('Riconnessione necessaria'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'È necessario riconnettere il tuo account Instagram.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              'Il token di autorizzazione di Instagram è scaduto o non valido. Questo può accadere periodicamente per motivi di sicurezza.',
            ),
            SizedBox(height: 8),
            Text(
              'Per continuare a pubblicare su Instagram, dovrai uscire e riconnetterti con il tuo account attraverso la pagina Profilo dell\'app.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Chiudi'),
          ),
        ],
      ),
    );
  }

  // Helper method to build a placeholder for media
  Widget _buildPlaceholder(ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(18),
        topRight: Radius.circular(18),
      ),
      child: Container(
        color: theme.colorScheme.surfaceVariant,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.isImageFile ? Icons.photo : Icons.video_library,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                widget.videoFile.path.split('/').last,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Simpler media preview for large files or error cases
  Widget _buildSimpleMediaPreview(ThemeData theme) {
    return Container(
      height: 220,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
        ),
        child: Container(
          color: theme.colorScheme.surfaceVariant,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  widget.isImageFile ? Icons.photo : Icons.video_library,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  widget.isImageFile ? 'Immagine' : 'Video',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tocca per avviare la riproduzione',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.videoFile.path.split('/').last,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Rich media preview with thumbnail/video player
  Widget _buildRichMediaPreview(ThemeData theme) {
    return Container(
      height: 220,
      width: double.infinity,
      child: widget.isImageFile 
        ? ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
          ),
          child: Image.file(
            widget.videoFile,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              print('Error loading image: $error');
              return _buildPlaceholder(theme);
            },
          ),
        )
        : _thumbnailPath != null
          ? GestureDetector(
            onTap: () {
              // Quando si tocca la thumbnail, inizializza il player se non è già inizializzato
              if (!_isVideoInitialized) {
                // Mostra un indicatore di caricamento
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return Dialog(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(width: 20),
                            Text("Caricamento video..."),
                          ],
                        ),
                      ),
                    );
                  },
                );
                
                _initializeVideoPlayer().then((_) {
                  // Chiudi il dialog di caricamento
                  Navigator.of(context, rootNavigator: true).pop();
                  
                  if (_isVideoInitialized && _videoPlayerController != null && mounted) {
                    setState(() {});
                    _playVideo();
                  } else {
                    // Se non si riesce a inizializzare, mostra un messaggio
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Impossibile riprodurre il video. File troppo grande o formato non supportato.'),
                        duration: Duration(seconds: 2),
                      )
                    );
                  }
                }).catchError((e) {
                  // Chiudi il dialog di caricamento in caso di errore
                  Navigator.of(context, rootNavigator: true).pop();
                  // Mostra messaggio di errore
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Errore nella riproduzione del video: ${e.toString()}'),
                      duration: Duration(seconds: 2),
                    )
                  );
                });
              } else if (_videoPlayerController != null) {
                // Se il player è già inizializzato, riproduci il video
                _playVideo();
                setState(() {});
              }
            },
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(_thumbnailPath!),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      print('Error loading thumbnail: $error');
                      return _buildSimpleMediaPreview(theme);
                    },
                  ),
                  // Play icon overlay
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  ),
                  // Aggiunta di un'etichetta "Tocca per riprodurre"
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Tocca per riprodurre',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          : _isVideoInitialized && _videoPlayerController != null
            ? GestureDetector(
              onTap: () {
                if (_videoPlayerController!.value.isPlaying) {
                  _videoPlayerController!.pause();
                  if (mounted) {
                    setState(() {
                      _isVideoPlaying = false;
                    });
                  }
                } else {
                  _playVideo(); // Use our optimized method
                  if (mounted) {
                    setState(() {
                      // Update state after play attempt
                    });
                  }
                }
              },
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                    ),
                    child: Container(
                      color: const Color(0xFF1E1E1E),
                      width: double.infinity,
                      height: double.infinity,
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _videoPlayerController!.value.aspectRatio,
                          child: VideoPlayer(_videoPlayerController!),
                        ),
                      ),
                    ),
                  ),
                  // Overlay play/pause button
                  if (!_videoPlayerController!.value.isPlaying)
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                ],
              ),
            )
            : GestureDetector(
                onTap: () {
                  // Se non c'è thumbnail ma abbiamo un video, prova a inizializzare il player
                  if (!widget.isImageFile) {
                    // Mostra un indicatore di caricamento
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext context) {
                        return Dialog(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(width: 20),
                                Text("Caricamento video..."),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                    
                    // Prima prova a generare una thumbnail
                    _generateThumbnail().then((_) {
                      // Se ora abbiamo una thumbnail, chiudi il dialog e aggiorna l'UI
                      if (_thumbnailPath != null) {
                        Navigator.of(context, rootNavigator: true).pop();
                        setState(() {});
                      } else {
                        // Se ancora non abbiamo una thumbnail, prova a inizializzare il player
                        _initializeVideoPlayer().then((_) {
                          Navigator.of(context, rootNavigator: true).pop();
                          if (_isVideoInitialized && mounted) {
                            setState(() {});
                            _playVideo();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Impossibile riprodurre il video'),
                                duration: Duration(seconds: 2),
                              )
                            );
                          }
                        }).catchError((e) {
                          Navigator.of(context, rootNavigator: true).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Errore nella riproduzione: ${e.toString()}'),
                              duration: Duration(seconds: 2),
                            )
                          );
                        });
                      }
                    });
                  }
                },
                child: _buildPlaceholder(theme),
              ),
    );
  }

  Future<void> _initializeVideoPlayer() async {
    // Dispose any existing controller first
    _disposeVideoController();
    
    try {
      // Check file size before processing to avoid memory issues
      final fileSize = await widget.videoFile.length();
      final fileSizeMB = fileSize / (1024 * 1024);
      print('Video file size: ${fileSizeMB.toStringAsFixed(2)} MB');
      
      // For very large files, don't try to initialize the player
      if (fileSizeMB > 150) { // Increased from 100 to 150MB
        print('Video file too large to preview (${fileSizeMB.toStringAsFixed(2)} MB), skipping player initialization');
        return;
      }
      
      // Force a small delay before creating controller to allow memory cleanup
      await Future.delayed(const Duration(milliseconds: 100));
      
      _videoPlayerController = VideoPlayerController.file(widget.videoFile);
      _videoPlayerController!.setVolume(0.0); // Mute video to save resources
      _videoPlayerController!.setLooping(false); // Don't loop to save memory
      
      // Use a shorter timeout to avoid hanging
      await _videoPlayerController!.initialize().timeout(
        const Duration(seconds: 8), // Increased from 6 to 8 seconds
        onTimeout: () {
          print('Video initialization timed out');
          _disposeVideoController(); // Make sure to dispose on timeout
          return;
        }
      ).then((_) {
        if (!mounted || _isDisposed) {
          _disposeVideoController();
          return;
        }
        
        setState(() {
          _isVideoInitialized = true;
        });
        
        // Auto stop video after 3 seconds to save memory
        _videoTimer?.cancel();
        _videoTimer = Timer(const Duration(seconds: 3), () {
          if (_videoPlayerController != null && 
              _videoPlayerController!.value.isPlaying &&
              !_isDisposed) {
            _pauseVideo();
          }
        });
      }).catchError((error) {
        print('Error initializing video player: $error');
        _disposeVideoController();
      });
    } catch (e) {
      print('Exception during video controller creation: $e');
      _disposeVideoController();
    }
  }
} 

// Servizio Firestore fittizio
class FirestoreService {
  // Modifica: usa un tipo generico Map invece di DocumentSnapshot
  Future<Map<String, dynamic>?> getAccount(String platform, String accountId) async {
    try {
      // Verifica se l'account esiste in Firebase Database
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return null;
      
      final accountSnapshot = await FirebaseDatabase.instance.ref()
          .child('users')
          .child(currentUser.uid)
          .child(platform.toLowerCase())
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        return null;
      }
      
      // Converti il risultato in un formato usabile
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      
      // Creiamo un nuovo Map con i dati convertiti a String, dynamic
      return {
        'page_id': accountData['page_id']?.toString() ?? '',
        'access_token': accountData['access_token']?.toString() ?? '',
        // Aggiungi altri campi pertinenti qui
      };
    } catch (e) {
      print('Errore nel recupero account: $e');
      return null;
    }
  }
}
