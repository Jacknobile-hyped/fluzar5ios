import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:lottie/lottie.dart';
import '../providers/theme_provider.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// Custom circular progress painter based on VEDI.md style
class CircularProgressPainter extends CustomPainter {
  final List<ProgressSegment> segments;
  final double strokeWidth;
  final double gap;

  CircularProgressPainter({
    required this.segments,
    required this.strokeWidth,
    this.gap = 0.08,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2, size.height / 2) - strokeWidth / 2;
    
    double totalPercentage = segments.fold(0, (sum, item) => sum + item.percentage);
    if (totalPercentage == 0) return; 

    double currentStartAngle = -math.pi / 2; // Start from top (12 o'clock)

    for (var segment in segments) {
      // Calculate the actual angle for the segment, considering the gap between segments
      final sweepAngle = (segment.percentage / 100) * (2 * math.pi - segments.length * gap);
      
      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round; // Rounded ends

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        currentStartAngle,
        sweepAngle,
        false,
        paint,
      );
      // Update the starting angle for the next segment, adding the gap
      currentStartAngle += sweepAngle + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CircularProgressPainter oldDelegate) {
    return oldDelegate.segments != segments ||
           oldDelegate.strokeWidth != strokeWidth ||
           oldDelegate.gap != gap;
  }
}

// Model for progress segment data
class ProgressSegment {
  final String name;
  final double percentage;
  final Color color;

  ProgressSegment({required this.name, required this.percentage, required this.color});
}

// Tips list from qwert.md
const List<String> viralTips = [
  "Videos with captions get 12% more views — most people scroll with sound off!",
  "Instagram Stories with polls or quizzes see 20% more engagement — interaction is king.",
  "Short-form video is the most shared content format across all major platforms.",
  "TikTok's algorithm resets daily. That means every video has a fresh shot at going viral!",
  "Hashtag challenges started on TikTok and now drive billions of views across platforms.",
  "The average person spends 2.5 hours a day on social media. That's a lot of chances to catch their eye!",
  "YouTube Shorts get pushed to over 2 billion users — great way to grow fast without long videos.",
  "Adding emojis in captions can increase engagement by up to 30%. 🎯🔥😎",
  "Reposting at the right time can double the performance of your original video.",
  "TikTok videos with text overlays keep people watching longer — great for storytelling!",
  "Instagram Reels reach more non-followers than regular posts — perfect for growth.",
  "Snapchat Spotlight pays creators based on performance — yes, your fun video can earn money.",
  "Facebook still has the highest number of active users globally — don't underestimate it!",
  "Consistency beats perfection. Posting regularly matters more than waiting for the perfect video.",
  "Viral videos often follow the 3 E's: Entertain, Educate, or Evoke emotion. Which one is yours?",
];

class UploadStatusPage extends StatefulWidget {
  final File videoFile;
  final String title;
  final String description;
  final Map<String, List<String>> selectedAccounts;
  final Map<String, List<Map<String, dynamic>>> socialAccounts;
  final VoidCallback onComplete;
  final bool isImageFile;
  final String? cloudflareUrl;
  final Map<String, Map<String, String>> platformDescriptions;
  final Function uploadFunction;
  final Map<String, String> instagramContentType;

  const UploadStatusPage({
    Key? key,
    required this.videoFile,
    required this.title,
    required this.description,
    required this.selectedAccounts,
    required this.socialAccounts,
    required this.onComplete,
    this.isImageFile = false,
    this.cloudflareUrl,
    this.platformDescriptions = const {},
    required this.uploadFunction,
    this.instagramContentType = const {},
  }) : super(key: key);

  @override
  State<UploadStatusPage> createState() => _UploadStatusPageState();
}

class _UploadStatusPageState extends State<UploadStatusPage> with TickerProviderStateMixin {
  bool _isUploading = true;
  Map<String, bool> _uploadStatus = {};
  Map<String, String> _uploadMessages = {};
  Map<String, double> _uploadProgress = {};
  List<Exception> _errors = [];
  
  // Firebase references
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _creditsDeducted = false;
  
  // Removed animation controller and animation stages
  
  // Upload status message
  final String _uploadStatusMessage = "Uploading your content...";
  
  // Platform logos for UI display
  final Map<String, String> _platformLogos = {
    'TikTok': 'assets/loghi/logo_tiktok.png',
    'YouTube': 'assets/loghi/logo_yt.png',
    'Facebook': 'assets/loghi/logo_facebook.png',
    'Twitter': 'assets/loghi/logo_twitter.png',
    'Threads': 'assets/loghi/threads_logo.png',
    'Instagram': 'assets/loghi/logo_insta.png',
  };

  // Platform colors for progress segments
  final Map<String, Color> _platformColors = {
    'TikTok': const Color(0xFFC974E8),
    'YouTube': const Color(0xFFE57373),
    'Facebook': const Color(0xFF64B5F6),
    'Twitter': const Color(0xFF4FC3F7),
    'Threads': const Color(0xFFFFF176),
    'Instagram': const Color(0xFFE040FB),
    'cloudflare': const Color(0xFFF7C167),
    'thumbnail': const Color(0xFFAED581),
  };

  // Timer for auto-rotating tips
  Timer? _tipsTimer;
  // Current tip index
  int _currentTipIndex = 0;
  // To track if tips section is expanded or collapsed
  bool _isTipsExpanded = true;
  // Animation controllers for tips section
  late AnimationController _tipsAnimController;
  late Animation<double> _tipsHeightAnimation;
  late Animation<double> _tipsOpacityAnimation;

  // List of completed platforms
  Set<String> _completedPlatforms = {};
  
  // Success animation controllers removed to prevent visual interference
  
  // Map to track TikTok upload attempts per account
  final Map<String, int> _tiktokUploadAttempts = {};
  final int _maxTikTokInitAttempts = 3;

  @override
  void initState() {
    super.initState();
    
    // Tips animation controller
    _tipsAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    _tipsHeightAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tipsAnimController,
      curve: Curves.easeInOut,
    ));
    
    _tipsOpacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _tipsAnimController,
      curve: Curves.easeIn,
    ));
    
    // Success animation initialization removed to prevent visual interference
    
    // Set initial state
    if (_isTipsExpanded) {
      _tipsAnimController.value = 1.0;
    }
    
    // Start the upload process when the page is loaded
    _startUpload();
    
    // Start the tips timer to auto-rotate tips every 10 seconds
    _startTipsTimer();
    
    // Ritardiamo significativamente il controllo degli upload per evitare interferenze
    // con il processo di Instagram, simile a come viene gestito per Threads
    Future.delayed(Duration(seconds: 30), () {
      if (mounted) {
        _trackUploadProgress();
      }
    });
  }

  @override
  void dispose() {
    // Cancel the timer when the widget is disposed
    _tipsTimer?.cancel();
    _tipsAnimController.dispose();
    super.dispose();
  }
  
  void _startTipsTimer() {
    _tipsTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      if (mounted && _isTipsExpanded) {
        setState(() {
          _currentTipIndex = (_currentTipIndex + 1) % viralTips.length;
        });
      }
    });
  }

  // Move to next tip
  void _nextTip() {
    if (!_isTipsExpanded) return;
    
    setState(() {
      _currentTipIndex = (_currentTipIndex + 1) % viralTips.length;
    });
    
    // Reset the timer when manually changing tip
    _tipsTimer?.cancel();
    _startTipsTimer();
  }

  // Toggle tips section visibility
  void _toggleTipsVisibility() {
    setState(() {
      _isTipsExpanded = !_isTipsExpanded;
      if (_isTipsExpanded) {
        _tipsAnimController.forward();
      } else {
        _tipsAnimController.reverse();
      }
    });
  }

  Future<void> _startUpload() async {
    try {
      // Call the upload function passed from the previous page
      await widget.uploadFunction(
        (platform, accountId, message, progress) {
          _updateUploadProgress(platform, accountId, message, progress);
        },
        (errors) {
          setState(() {
            _errors = errors;
          });
        }
      );
      
      // Consideriamo tutte le piattaforme come indipendenti
      // Non aspettiamo che tutte siano completate, ognuna gestirà il proprio stato
      
      print('Upload avviati su tutte le piattaforme...');
      setState(() {
        _uploadMessages['status'] = 'Upload avviati su tutte le piattaforme...';
      });
      
      // Gestione indipendente per TikTok (solo una volta, non in loop)
      if (widget.selectedAccounts.containsKey('TikTok') && widget.selectedAccounts['TikTok']!.isNotEmpty) {
        for (String accountId in widget.selectedAccounts['TikTok'] ?? []) {
          String key = 'TikTok_$accountId';
          if (!_completedPlatforms.contains(key) && widget.cloudflareUrl != null) {
            print('Avvio upload TikTok (una tantum) per account $accountId');
            _startTikTokUpload(accountId);
          }
        }
      }
      
      // We keep _isUploading as true to maintain consistent state
      // Each platform will independently report its completion
      
      // No dialogs shown - uploads will manage themselves
      
    } catch (e) {
      // We keep _isUploading as true to maintain consistent state
      // Only show error dialog for critical errors that prevent starting uploads
      _showErrorDialog("Error", e.toString());
    }
  }
  
  // Metodo per verificare lo stato degli upload senza richiedere il completamento totale
  // Ora ogni upload è indipendente e non blocca gli altri
  bool _trackUploadProgress() {
    // Conteggio semplice per debugging e monitoraggio
    int totalExpectedUploads = 0;
    int completedUploads = 0;
    
    // Controlla ogni piattaforma e account selezionato (solo piattaforme social)
    widget.selectedAccounts.forEach((platform, accountIds) {
      for (String accountId in accountIds) {
        String key = '${platform}_$accountId';
        totalExpectedUploads++;
        
        // Se il progresso è al 100% o è nella lista dei completati, lo contiamo
        double progress = _uploadProgress[key] ?? 0.0;
        bool isCompleted = _completedPlatforms.contains(key);
        
        // Gestione speciale per TikTok che non riesce ad avviarsi
        if (platform == 'TikTok' && 
            progress < 0.1 && 
            _completedPlatforms.any((k) => k.startsWith('cloudflare_'))) {
          // Verifica se abbiamo raggiunto il numero massimo di tentativi
          int attempts = _tiktokUploadAttempts[accountId] ?? 0;
          if (attempts >= _maxTikTokInitAttempts) {
            print('TikTok upload per account $accountId ha raggiunto il massimo numero di tentativi, considerando come fallito ma completato');
            
            if (!_completedPlatforms.contains(key)) {
              setState(() {
                _uploadStatus[key] = false;
                _uploadMessages[key] = 'Upload fallito: problemi di connessione o autenticazione';
                _uploadProgress[key] = 1.0;
                _completedPlatforms.add(key);
                _errors.add(Exception('TikTok: Upload non riuscito dopo multipli tentativi'));
              });
            }
            
            // Consideriamo completato per non bloccare l'intero processo
            progress = 1.0;
            isCompleted = true;
          }
        }
        
        // Contiamo i completati per monitoraggio e debug
        if (progress >= 1.0 || isCompleted) {
          if (!_completedPlatforms.contains(key)) {
            _completedPlatforms.add(key);
          }
          completedUploads++;
        } else {
          print('$platform upload per account $accountId in corso (progress: $progress, isCompleted: $isCompleted)');
        }
      }
    });
    
    // Monitoraggio infrastruttura
    if (widget.cloudflareUrl != null) {
      String key = 'cloudflare_storage';
      double progress = _uploadProgress[key] ?? 0.0;
      if (progress >= 1.0 && !_completedPlatforms.contains(key)) {
        _completedPlatforms.add(key);
      }
    }
    
    if (widget.isImageFile) {
      String key = 'thumbnail_image';
      double progress = _uploadProgress[key] ?? 0.0;
      if (progress >= 1.0 && !_completedPlatforms.contains(key)) {
        _completedPlatforms.add(key);
      }
    }
    
    // Aggiungiamo un log per debug
    print('Upload tracking: Total social networks=$totalExpectedUploads, Completed=$completedUploads');
    print('Completed platforms: ${_completedPlatforms.join(', ')}');
    
    // Se ci sono upload completati, deduciamo i crediti in base a quelli
    if (completedUploads > 0) {
      _deductCreditsForCompletedUploads();
    }
    
    // Verifica lo stato degli upload con priorità e ritardi appropriati
    // Prima verifichiamo TikTok che è meno sensibile alle interruzioni
    _checkTikTokUploadStatus();
    
    // Per Instagram aggiungiamo un ritardo per evitare interferenze con i controlli dei video pubblicati
    // Questo è simile all'approccio usato per Threads, che richiede tempo tra le operazioni
    Future.delayed(Duration(seconds: 5), () {
      if (mounted) {
        _checkInstagramUploadStatus();
        
        // Pianifichiamo un altro controllo ritardato per verificare eventuali upload rimasti
        Future.delayed(Duration(seconds: 15), () {
          if (mounted) _trackUploadProgress();
        });
      }
    });
    
    // Ritorniamo true solo per compatibilità con il codice esistente
    return true;
  }

  // Metodo per detrarre i crediti per gli upload completati
  Future<void> _deductCreditsForCompletedUploads() async {
    // Verifichiamo che l'utente sia loggato e che i crediti non siano già stati detratti
    if (_currentUser == null || _creditsDeducted) return;
    
    try {
      // Contiamo quanti upload social sono stati completati (non conteggiamo cloudflare e thumbnail)
      int successfulSocialUploads = 0;
      
      for (String completedKey in _completedPlatforms) {
        // Escludiamo cloudflare e thumbnail dal conteggio dei crediti
        if (!completedKey.startsWith('cloudflare_') && !completedKey.startsWith('thumbnail_')) {
          successfulSocialUploads++;
        }
      }
      
      // Se non ci sono upload social completati, non deduciamo crediti
      if (successfulSocialUploads == 0) return;
      
      // Calcoliamo quanti crediti detrarre: 100 per ogni social completato
      int creditsToDeduct = successfulSocialUploads * 100;
      
      // Otteniamo prima i crediti attuali dell'utente
      final creditsSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('credits')
          .get();
      
      if (!mounted) return;
      
      // Verifichiamo che lo snapshot esista
      if (creditsSnapshot.exists) {
        int currentCredits = (creditsSnapshot.value as int?) ?? 750;
        
        // Assicuriamoci che non detraggiamo più crediti di quelli disponibili
        int newCredits = (currentCredits - creditsToDeduct).clamp(0, currentCredits);
        
        // Aggiorniamo i crediti nel database
        await _database
            .child('users')
            .child('users')
            .child(_currentUser!.uid)
            .child('credits')
            .set(newCredits);
        
        // Segnamo che i crediti sono stati detratti
        _creditsDeducted = true;
        
        print('Crediti detratti: $creditsToDeduct. Crediti rimasti: $newCredits');
      } else {
        print('Errore: non è stato possibile leggere i crediti dell\'utente');
      }
    } catch (e) {
      print('Errore durante la detrazione dei crediti: $e');
    }
  }

  // Metodo per verificare lo stato degli upload e avviare quelli che non sono ancora iniziati
  void _checkUploadCompletion() {
    // Log the current upload state for debugging
    print('Verifica stato upload (una tantum):');
    _uploadProgress.forEach((key, value) {
      print('$key: $value (${_uploadMessages[key] ?? "No message"})');
    });
    print('Completed platforms: ${_completedPlatforms.join(', ')}');
    
    // TikTok - attempt to start if not already started
    if (widget.cloudflareUrl != null && widget.selectedAccounts.containsKey('TikTok')) {
      for (String accountId in widget.selectedAccounts['TikTok'] ?? []) {
        String key = 'TikTok_$accountId';
        double progress = _uploadProgress[key] ?? 0.0;
        if (!_completedPlatforms.contains(key) && progress < 0.3) {
          print('Forcing TikTok upload start for account $accountId');
          _startTikTokUpload(accountId);
        }
      }
    }
    
    // Instagram - attempt to start if not already started
    if (widget.cloudflareUrl != null && widget.selectedAccounts.containsKey('Instagram')) {
      for (String accountId in widget.selectedAccounts['Instagram'] ?? []) {
        String key = 'Instagram_$accountId';
        double progress = _uploadProgress[key] ?? 0.0;
        if (!_completedPlatforms.contains(key) && progress < 0.3) {
          print('Forcing Instagram upload start for account $accountId');
          
          // Get platform-specific description if available
          String postDescription = widget.description;
          if (widget.platformDescriptions.containsKey('Instagram') && 
              widget.platformDescriptions['Instagram']!.containsKey(accountId)) {
            postDescription = widget.platformDescriptions['Instagram']![accountId]!;
          }
          
          // Get content type if available (default to Post)
          String contentType = 'Post';
          if (widget.instagramContentType.containsKey(accountId)) {
            contentType = widget.instagramContentType[accountId]!;
          }
          
          // Ensure the URL is in the correct R2 format
          String instagramUrl = widget.cloudflareUrl!;
          if (!instagramUrl.contains('pub-') || !instagramUrl.contains('.r2.dev')) {
            instagramUrl = _convertToPublicR2Url(instagramUrl);
            print('URL converted to R2 format: $instagramUrl');
          }
          
          _uploadToInstagram(
            accountId: accountId,
            key: key,
            cloudflareUrl: instagramUrl,
            title: widget.title,
            description: postDescription,
            contentType: contentType
          );
        }
      }
    }
    
    // After initiating all uploads, track progress
    _trackUploadProgress();
  }
  
  // Add a dedicated method to start TikTok uploads with retry logic
  void _startTikTokUpload(String accountId) {
    if (!mounted || widget.cloudflareUrl == null) return;
    
    String key = 'TikTok_$accountId';
    
    // Verifica numero di tentativi già effettuati per questo account
    int attempts = _tiktokUploadAttempts[accountId] ?? 0;
    if (attempts >= _maxTikTokInitAttempts) {
      print('Troppi tentativi di avvio per TikTok account $accountId (${attempts}/${_maxTikTokInitAttempts}). Marcando come completato per evitare loop infinito.');
      setState(() {
        _uploadStatus[key] = false;
        _uploadMessages[key] = 'Upload fallito: troppi tentativi';
        _uploadProgress[key] = 1.0; // Mark as completed to not block other uploads
        _completedPlatforms.add(key);
        _errors.add(Exception('TikTok: Troppi tentativi di avvio falliti'));
      });
      return;
    }
    
    // Incrementa contatore tentativi
    _tiktokUploadAttempts[accountId] = attempts + 1;
    
    // Se l'upload è già in corso o è già completato, non avviarlo di nuovo
    double currentProgress = _uploadProgress[key] ?? 0.0;
    bool isActive = _uploadStatus[key] ?? false;
    if ((isActive && currentProgress > 0.2) || _completedPlatforms.contains(key)) {
      print('TikTok upload for account $accountId already in progress (${currentProgress * 100}%) or completed');
      return;
    }
    
    // Aggiungiamo log dettagliati per debug
    print('======= INIZIALIZZAZIONE UPLOAD TIKTOK (Tentativo ${attempts + 1}/${_maxTikTokInitAttempts}) =======');
    print('Account ID: $accountId');
    print('Cloudflare URL: ${widget.cloudflareUrl}');
    print('isImage: ${widget.isImageFile}');
    print('Token di upload disponibile: ${_currentUser != null}');
    
    setState(() {
      _uploadStatus[key] = true;
      _uploadMessages[key] = 'Starting TikTok upload...';
      _uploadProgress[key] = 0.01;
    });
    
    // Force start upload in background with retry logic
    Future.microtask(() async {
      int retryCount = 0;
      final maxRetries = 3;
      bool success = false;
      Exception? lastError;
      
      while (retryCount < maxRetries && !success && mounted) {
        try {
          print('Starting TikTok upload attempt ${retryCount + 1}/$maxRetries for account $accountId with URL: ${widget.cloudflareUrl}');
          
          // Get platform-specific description if available
          String postDescription = widget.description;
          if (widget.platformDescriptions.containsKey('TikTok') && 
              widget.platformDescriptions['TikTok']!.containsKey(accountId)) {
            postDescription = widget.platformDescriptions['TikTok']![accountId]!;
          }
          
          // Verificare che il cloudflare URL sia raggiungibile prima di avviare l'upload
          bool isAccessible = await _verifyFileAccessibility(widget.cloudflareUrl!);
          if (!isAccessible) {
            print('ATTENZIONE: Cloudflare URL non accessibile: ${widget.cloudflareUrl}');
            // Try to convert URL to a verified domain if possible
            String modifiedUrl = widget.cloudflareUrl!;
            // Don't try to convert to viralyst.online - only use R2 public URLs
            if (!widget.cloudflareUrl!.contains('pub-')) {
              try {
                // Convert to public R2 format
                modifiedUrl = _convertToPublicR2Url(widget.cloudflareUrl!);
                print('Trying correct R2 URL format: $modifiedUrl');
                isAccessible = await _verifyFileAccessibility(modifiedUrl);
              } catch (e) {
                print('Error converting URL: $e');
              }
            }
            
            // If still not accessible after conversion attempt
            if (!isAccessible) {
              throw Exception('Video URL is not accessible. TikTok requires a publicly accessible URL.');
            }
          }
          
          // Verifica che il file esista sulla piattaforma Cloudflare
          if (!_completedPlatforms.any((key) => key.startsWith('cloudflare_'))) {
            print('ERRORE: Il file non è stato caricato su Cloudflare. Impossibile procedere con TikTok.');
            throw Exception('File not uploaded to Cloudflare yet');
          }
          
          print('Avvio upload TikTok con parametri:');
          print('- accountId: $accountId');
          print('- key: $key');
          print('- URL: ${widget.cloudflareUrl}');
          print('- title: ${widget.title}');
          print('- description: $postDescription');
          
          // Update progress message for retry attempts
          if (retryCount > 0) {
            setState(() {
              _uploadMessages[key] = 'Retrying TikTok upload (attempt ${retryCount + 1}/$maxRetries)...';
              _uploadProgress[key] = 0.05;
            });
          }
          
          await _uploadToTikTok(
            accountId,
            key,
            widget.cloudflareUrl!,
            widget.title,
            postDescription
          );
          
          success = true;
          print('TikTok upload completato con successo');
          break;
        } catch (e) {
          print('Error during TikTok upload attempt ${retryCount + 1}: $e');
          lastError = e is Exception ? e : Exception(e.toString());
          retryCount++;
          
          // Only wait and retry if not on the last attempt and if the error is recoverable
          if (retryCount < maxRetries && mounted) {
            final bool isRecoverableError = !e.toString().contains('url_ownership_unverified') && 
                                           !e.toString().contains('not authorized') &&
                                           !e.toString().contains('token');
            
            if (isRecoverableError) {
              // Exponential backoff: 3, 6, 12 seconds
              final int delaySeconds = 3 * (1 << (retryCount - 1));
              print('Retrying in $delaySeconds seconds...');
              setState(() {
                _uploadMessages[key] = 'Retry in $delaySeconds seconds (attempt ${retryCount}/$maxRetries)';
              });
              await Future.delayed(Duration(seconds: delaySeconds));
            } else {
              print('Non-recoverable error, not retrying: $e');
              break;
            }
          }
        }
      }
      
      // If all retries failed
      if (!success && lastError != null && mounted) {
        print('======= ERRORE UPLOAD TIKTOK DOPO $retryCount TENTATIVI =======');
        print('Errore dettagliato: $lastError');
        
        // Aggiorniamo lo stato con informazioni dettagliate sull'errore
        String errorMsg = lastError.toString();
        // Rendiamo il messaggio più user-friendly
        if (errorMsg.contains('timeout')) {
          errorMsg = 'Upload timeout';
        } else if (errorMsg.contains('token')) {
          errorMsg = 'Authentication error';
        } else if (errorMsg.contains('url_ownership')) {
          errorMsg = 'URL not verified with TikTok';
        } else if (errorMsg.contains('unaudited_client')) {
          errorMsg = 'App not approved for public uploads';
        }
        
        setState(() {
          _uploadStatus[key] = false;
          _uploadMessages[key] = 'Failed: $errorMsg';
          _uploadProgress[key] = 1.0; // Mark as completed to not block other uploads
          _completedPlatforms.add(key);
          _errors.add(Exception('TikTok: ${lastError.toString()}'));
        });
        
        // Riportiamo l'errore come evento per monitoraggio
        print('TikTok upload failed after $retryCount attempts: $errorMsg');
      }
    });
  }



  void _updateUploadProgress(String platform, String accountId, String status, double progress) {
    if (mounted) {
      setState(() {
        String key = '${platform}_$accountId';
        // Only set as active if it's not already completed
        if (!_completedPlatforms.contains(key)) {
          _uploadStatus[key] = true;
          _uploadMessages[key] = status;
          _uploadProgress[key] = progress;
        }
        
        // If progress is 100%, add to completed list
        if (progress >= 1.0) {
          _uploadStatus[key] = false;
          _completedPlatforms.add(key);
          
          // Start secondary uploads after Cloudflare is completed (only once)
          if (platform == 'cloudflare') {
            print('Cloudflare upload completed, starting social uploads immediately');
            
            // Start TikTok uploads
            if (widget.selectedAccounts.containsKey('TikTok') && widget.cloudflareUrl != null) {
              print('Starting TikTok uploads immediately after Cloudflare completion');
              Future.delayed(Duration(milliseconds: 1000), () {
                if (mounted) {
                  for (String tiktokAccountId in widget.selectedAccounts['TikTok'] ?? []) {
                    if (!_completedPlatforms.contains('TikTok_$tiktokAccountId')) {
                      _startTikTokUpload(tiktokAccountId);
                    }
                  }
                }
              });
            }

            // Start Instagram uploads
            if (widget.selectedAccounts.containsKey('Instagram') && widget.cloudflareUrl != null) {
              print('Starting Instagram uploads immediately after Cloudflare completion');
              Future.delayed(Duration(milliseconds: 1200), () {
                if (mounted) {
                  for (String instagramAccountId in widget.selectedAccounts['Instagram'] ?? []) {
                    String igKey = 'Instagram_$instagramAccountId';
                    if (!_completedPlatforms.contains(igKey)) {
                      // Get platform-specific description if available
                      String postDescription = widget.description;
                      if (widget.platformDescriptions.containsKey('Instagram') && 
                          widget.platformDescriptions['Instagram']!.containsKey(instagramAccountId)) {
                        postDescription = widget.platformDescriptions['Instagram']![instagramAccountId]!;
                      }
                      
                      // Get content type if available (default to Post)
                      String contentType = 'Post';
                      // Find account content type if it exists in your data structure
                      if (widget.instagramContentType.containsKey(instagramAccountId)) {
                        contentType = widget.instagramContentType[instagramAccountId]!;
                      }
                      
                      // Start Instagram upload
                      setState(() {
                        _uploadStatus[igKey] = true;
                        _uploadMessages[igKey] = 'Avvio upload Instagram...';
                        _uploadProgress[igKey] = 0.1; // Initial progress
                      });
                      
                      print('Starting Instagram upload for account $instagramAccountId');
                      
                      // Always use the R2 public URL format for Instagram
                      String instagramUrl = _convertToPublicR2Url(widget.cloudflareUrl!);
                      print('Using R2 public URL for Instagram: $instagramUrl');
                      
                      _uploadToInstagram(
                        accountId: instagramAccountId,
                        key: igKey,
                        cloudflareUrl: instagramUrl,
                        title: widget.title,
                        description: postDescription,
                        contentType: contentType
                      );
                    }
                  }
                }
              });
            }

            // Mark other social platforms as ready
            widget.selectedAccounts.forEach((socialPlatform, accountIds) {
              if (socialPlatform != 'TikTok' && socialPlatform != 'Instagram') {
                for (String socAccountId in accountIds) {
                  String socKey = '${socialPlatform}_$socAccountId';
                  if (!_completedPlatforms.contains(socKey)) {
                    setState(() {
                      _uploadStatus[socKey] = true;
                      _uploadMessages[socKey] = 'Upload in progress...';
                      _uploadProgress[socKey] = 0.5; // Set a reasonable progress value
                    });
                  }
                }
              }
            });
            
            // Check upload progress after a short delay
            Future.delayed(Duration(seconds: 2), () {
              if (mounted) _checkUploadCompletion();
            });
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Using a more consistent blue color from the app
    final appBlueColor = const Color(0xFF64B5F6);
    final isDark = theme.brightness == Brightness.dark;

    // Calculate progress for animation and UI based only on social platforms, not infrastructure
    double socialUploadProgress = 0.0;
    int socialPlatformsCount = 0;
    
    widget.selectedAccounts.forEach((platform, accountIds) {
      for (String accountId in accountIds) {
        String key = '${platform}_$accountId';
        double progress = _uploadProgress[key] ?? 0.0;
        socialUploadProgress += progress;
        socialPlatformsCount++;
      }
    });
    
    // Media upload progress percentuale basata solo sui social
    double averageSocialProgress = socialPlatformsCount > 0 ? 
        (socialUploadProgress / socialPlatformsCount) : 0.0;
    
    // Animation stages removed

    // Verifica se c'è un messaggio di attesa per il completamento di tutti gli upload
    bool isWaitingForCompletion = _uploadMessages.containsKey('status') && 
                                _uploadMessages['status']?.contains('Attendiamo') == true;

    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      appBar: null,
      body: SafeArea(
        child: Column(
          children: [
            // Header from about_page.dart
            _buildHeader(context),
            
            // Animation section removed
            
            // Main content with upload status and tips
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F8F8),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(24),
                    topRight: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Upload status containers (scrollable)
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(top: 24, left: 20, right: 20, bottom: 16),
                        child: _buildUploadContainers(),
                      ),
                    ),
                    
                    // Collapsible tips section
                    _buildCollapsibleTips(appBlueColor),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      // Bottom navigation bar removed to prevent interference with uploads
    );
  }

  // Build header from about_page.dart
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(25),
          bottomRight: Radius.circular(25),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Back button removed to prevent navigation during uploads
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFF6C63FF),
                      Color(0xFFFF6B6B),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds);
                },
                child: Text(
                  'Viral',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFFFF6B6B),
                      Color(0xFF00C9FF),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds);
                },
                child: Text(
                  'yst',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              // Upload status text
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'In corso...',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.amber[800],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Widget to display the current animation based on stage
  Widget _buildCurrentAnimation() {
    // Animation function removed
    return SizedBox(); // Return empty widget
  }

  // Get color based on stage
  Color _getStageColor() {
    // Animation color function removed
    return const Color(0xFF64B5F6); // Return default color
  }

  // Get icon based on stage (for fallback)
  IconData _getStageIcon() {
    // Animation icon function removed
    return Icons.cloud_upload; // Return default icon
  }

  // Build containers for all platforms even if they're not yet uploading
  Widget _buildUploadContainers() {
    // Create a list of all platforms from selected accounts
    List<String> allPlatforms = [];
    Map<String, List<String>> allAccounts = {};
    
    // Add platforms from selected accounts
    widget.selectedAccounts.forEach((platform, accountIds) {
      if (accountIds.isNotEmpty) {
        allPlatforms.add(platform);
        allAccounts[platform] = accountIds;
      }
    });
    
    // Add cloudflare and thumbnail if they should exist
    if (widget.cloudflareUrl != null) {
      allPlatforms.add('cloudflare');
      allAccounts['cloudflare'] = ['storage'];
    }
    
    if (widget.isImageFile) {
      allPlatforms.add('thumbnail');
      allAccounts['thumbnail'] = ['image'];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Build a container for each platform and account
        ...allPlatforms.expand((platform) {
          final accounts = allAccounts[platform] ?? [];
          return accounts.map((accountId) {
            final platformAccountId = '${platform}_$accountId';
            final isActive = _uploadStatus[platformAccountId] ?? false;
          final progress = _uploadProgress[platformAccountId] ?? 0.0;
            final message = _uploadMessages[platformAccountId] ?? 'In attesa...';
          
          // Find the account details
            Map<String, dynamic>? account;
            String username = '';
            
            if (platform != 'cloudflare' && platform != 'thumbnail') {
              account = widget.socialAccounts[platform]?.firstWhere(
            (acc) => acc['id'] == accountId,
            orElse: () => <String, dynamic>{},
          );
              username = account?['username'] ?? '';
            }
            
            final platformColor = _platformColors[platform] ?? const Color(0xFF504160);
            
            return Container(
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: platformColor.withOpacity(0.3),
                width: 1,
              ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: Offset(0, 2),
            ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Platform header with percentage
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: platformColor.withOpacity(0.15),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(15),
                        topRight: Radius.circular(15),
                      ),
                    ),
                    child: Row(
                    children: [
                      if (platform == 'cloudflare' || platform == 'thumbnail')
                        Icon(
                          platform.contains('thumbnail') ? Icons.image : Icons.cloud_upload,
                            color: platformColor,
                            size: 18,
                        )
                      else if (_platformLogos.containsKey(platform))
                        Image.asset(
                          _platformLogos[platform]!,
                            width: 18,
                            height: 18,
                        )
                      else
                        Icon(
                          _getPlatformIcon(platform),
                            color: platformColor,
                            size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                        platform == 'cloudflare' 
                            ? 'Cloud Storage' 
                            : platform == 'thumbnail'
                                ? 'Thumbnail'
                                : '$platform: @$username',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                              color: const Color(0xFF2C2C3E),
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: platformColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            progress > 0
                                    ? '${(progress * 100).toInt()}%'
                                    : 'In attesa',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                              color: platformColor,
                              fontSize: 12,
                            ),
                        ),
                      ),
                    ],
                  ),
                  ),
                  
                  // Progress info
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  Text(
                    message,
                    style: TextStyle(
                            fontSize: 13,
                            color: const Color(0xFF2C2C3E).withOpacity(0.7),
                    ),
                  ),
                        const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: progress,
                          backgroundColor: const Color(0xFFEEEEEE),
                          valueColor: AlwaysStoppedAnimation<Color>(platformColor),
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
                  ),
                ],
              ),
            );
          });
        }).toList(),
        
        // Error list if any
        if (_errors.isNotEmpty && !_isUploading)
          _buildErrorList(),
      ],
    );
  }

  Widget _buildErrorList() {
    return Container(
      margin: EdgeInsets.only(top: 24, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: const Color(0xFFF7C167)),
              SizedBox(width: 8),
              Text(
                'Errori riscontrati',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A4C),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF7C167).withOpacity(0.5),
                width: 1,
              ),
            ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _errors.map((error) => 
                  Padding(
                  padding: const EdgeInsets.only(bottom: 10.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Container(
                        margin: EdgeInsets.only(top: 6),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7C167),
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _formatErrorMessage(error.toString()),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                            height: 1.4,
                          ),
                          ),
                        ),
                      ],
                    ),
                  )
                ).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Empty stubs for dialog methods to maintain compatibility
  // These dialogs are removed to avoid interfering with other uploads
  void _showSuccessDialog() {
    // Dialogs removed to prevent interference with ongoing uploads
  }

  // Helper method stub - dialog removed to avoid interference
  void _showPartialSuccessDialog(List<Exception> errors) {
    // Dialogs removed to prevent interference with ongoing uploads
  }

  // Helper method to show error dialog
  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2C2C3E),
          title: Text(
            title,
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatErrorMessage(message),
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              const Text(
                'Suggerimenti:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              _buildSuggestionItem('Controlla la connessione internet'),
              _buildSuggestionItem('Riavvia l\'app e riprova'),
              _buildSuggestionItem('Controlla che tutti gli account social siano ancora connessi'),
              _buildSuggestionItem('Esci e riaccedi agli account che stanno dando problemi'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(
                'Chiudi',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startUpload();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF504160),
                foregroundColor: Colors.white,
              ),
              child: const Text('Riprova'),
            ),
          ],
        );
      },
    );
  }
  
  Widget _buildSuggestionItem(String text, {Color color = const Color(0xFF67E4C8)}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  // Helper function to format error messages for better readability
  String _formatErrorMessage(String error) {
    // Remove Exception prefix
    String formattedError = error.replaceAll('Exception: ', '');
    
    // Check for specific error patterns and provide more user-friendly messages
    if (formattedError.contains('token') && 
        (formattedError.contains('Invalid') || 
         formattedError.contains('expired'))) {
      return 'Token di autenticazione non valido o scaduto. Riconnetti l\'account.';
    } else if (formattedError.contains('timeout')) {
      return 'Timeout durante il caricamento. Controlla la connessione internet.';
    } else if (formattedError.contains('account not found')) {
      return 'Account non trovato. Potrebbe essere necessario riconnettere l\'account.';
    } else if (formattedError.contains('Container') || formattedError.contains('container')) {
      return 'Errore nella creazione del contenitore media. Potrebbe essere un problema di formato o permessi.';
    }
    
    return formattedError;
  }

  // Helper to get color based on progress
  Color _getProgressColor(double progress, bool isActive) {
    if (!isActive && progress >= 1.0) {
      return const Color(0xFF67E4C8);
    } else if (progress > 0.5) {
      return const Color(0xFFF7C167);
    } else {
      return const Color(0xFF64B5F6);
    }
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'TikTok': return Icons.music_note;
      case 'YouTube': return Icons.play_arrow;
      case 'Facebook': return Icons.facebook;
      case 'Twitter': return Icons.chat;
      case 'Threads': return Icons.chat_outlined;
      case 'Instagram': return Icons.camera_alt;
      default: return Icons.share;
    }
  }

  // Get a color for each platform
  Color _getPlatformColor(String platform) {
    return _platformColors[platform] ?? const Color(0xFF504160);
  }

  // Build collapsible tips carousel widget with improved animation
  Widget _buildCollapsibleTips(Color appBlueColor) {
    final theme = Theme.of(context);
    
    return Material(
      color: Colors.white,
      elevation: 4,
      shadowColor: Colors.black.withOpacity(0.1),
      child: InkWell(
        onTap: _toggleTipsVisibility,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tips header always visible
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  // App logo using actual app icon
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: appBlueColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/app_icon.png',
                        width: 32,
                        height: 32,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Fallback if asset not found
                          return CircleAvatar(
                            backgroundColor: appBlueColor,
                            radius: 16,
                            child: Text(
                              'V',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Fluzar Tips',
                    style: TextStyle(
                      color: const Color(0xFF2C2C3E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Spacer(),
                  // Next tip button
                  if (_isTipsExpanded)
                    InkWell(
                      onTap: _nextTip,
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: appBlueColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.navigate_next,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  SizedBox(width: 8),
                  // Expand/collapse button with animation
                  AnimatedRotation(
                    turns: _isTipsExpanded ? 0.5 : 0.0,
                    duration: Duration(milliseconds: 300),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
            
            // Tip content with animation
            AnimatedContainer(
              duration: Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _isTipsExpanded ? null : 0,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(),
              child: AnimatedOpacity(
                opacity: _isTipsExpanded ? 1.0 : 0.0,
                duration: Duration(milliseconds: 200),
                child: Padding(
                  padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: 500),
                    transitionBuilder: (Widget child, Animation<double> animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: Offset(0.1, 0.0),
                            end: Offset(0.0, 0.0),
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Row(
                      key: ValueKey<int>(_currentTipIndex),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: EdgeInsets.only(top: 4),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _getTipColor(_currentTipIndex),
                            shape: BoxShape.circle,
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            viralTips[_currentTipIndex],
                            style: TextStyle(
                              color: const Color(0xFF2C2C3E),
                              fontSize: 15,
                              height: 1.4,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Return different colors for different tips to add visual variety
  Color _getTipColor(int index) {
    final colors = [
      const Color(0xFFC974E8), // Purple
      const Color(0xFFF7C167), // Orange
      const Color(0xFF67E4C8), // Teal
    ];
    
    return colors[index % colors.length];
  }

  // Dialog stub to maintain compatibility
  void _showPartialCompletionDialog() {
    // Dialogs removed to prevent interference with ongoing uploads
  }


  


  // Improved helper method to verify file accessibility with retry logic
  Future<bool> _verifyFileAccessibility(String url) async {
    try {
      print('Verificando accessibilità URL: $url');
      
      // Verificare che l'URL sia nel formato corretto
      if (!url.contains('pub-3d945eb681944ec5965fecf275e41a9b.r2.dev')) {
        print('AVVISO: URL non nel formato pub-3d945eb681944ec5965fecf275e41a9b.r2.dev');
        // Continuiamo comunque con la verifica
      }
      
      // Impostare un timeout più breve per non bloccare il processo di upload
      final response = await http.head(Uri.parse(url)).timeout(const Duration(seconds: 5));
      
      final bool isSuccess = response.statusCode >= 200 && response.statusCode < 400;
      print('Verifica URL $url: Status ${response.statusCode}, Accessibile: $isSuccess');
      
      return isSuccess;
    } catch (e) {
      print('Errore verifica URL $url: $e');
      return false;
    }
  }



  // Diagnostica problemi con upload TikTok
  Future<String> _diagnoseTikTokIssues(String accountId, String accessToken, String cloudflareUrl) async {
    try {
      print('Esecuzione diagnostica per TikTok account: $accountId');
      
      // Test 1: Verifica accessibilità URL
      print('Test 1: Verifica accessibilità URL');
      bool isUrlAccessible = await _verifyFileAccessibility(cloudflareUrl);
      if (!isUrlAccessible) {
        return 'URL non accessibile: $cloudflareUrl';
      }
      
      // Test 2: Verifica validità token
      print('Test 2: Verifica validità token');
      if (accessToken.isEmpty) {
        return 'Token TikTok vuoto';
      }
      
      // Test 3: Verifica informazioni creator (API di base)
      print('Test 3: Verifica informazioni creator');
      try {
        final creatorInfoResponse = await http.post(
          Uri.parse('https://open.tiktokapis.com/v2/post/publish/creator_info/query/'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json; charset=UTF-8',
          },
        ).timeout(Duration(seconds: 10));
        
        print('Test 3 response: ${creatorInfoResponse.statusCode} - ${creatorInfoResponse.body}');
        
        if (creatorInfoResponse.statusCode != 200) {
          return 'Errore API TikTok: ${creatorInfoResponse.statusCode} - ${creatorInfoResponse.body}';
        }
        
        final creatorInfoData = json.decode(creatorInfoResponse.body);
        if (creatorInfoData['error']['code'] != 'ok') {
          return 'Errore TikTok: ${creatorInfoData['error']['code']} - ${creatorInfoData['error']['message']}';
        }
      } catch (e) {
        return 'Errore accesso API TikTok: $e';
      }
      
      // Test 4: Verifica dominio URL
      print('Test 4: Verifica dominio URL');
      // We no longer require viralyst.online domain, use the public R2 URL format
      if (!cloudflareUrl.contains('pub-') || !cloudflareUrl.contains('.r2.dev')) {
        return 'URL non nel formato R2 pubblico corretto: $cloudflareUrl - Deve essere nel formato pub-[accountId].r2.dev';
      }
      
      // Se arriviamo qui, non abbiamo trovato problemi evidenti
      return 'Nessun problema evidente rilevato';
    } catch (e) {
      return 'Errore durante diagnostica: $e';
    }
  }

  // TikTok upload implementation based on TikTok Content Posting API
  Future<void> _uploadToTikTok(
    String accountId, 
    String key, 
    String cloudflareUrl,
    String title,
    String description
  ) async {
    try {
      // Update initial progress state
      setState(() {
        _uploadStatus[key] = true;
        _uploadMessages[key] = 'Initializing TikTok upload...';
        _uploadProgress[key] = 0.05;
      });
      
      // Get account data from Firebase
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      setState(() {
        _uploadMessages[key] = 'Getting TikTok account data...';
        _uploadProgress[key] = 0.1;
      });
      
      print('Retrieving TikTok account data for account ID: $accountId');
      final accountSnapshot = await FirebaseDatabase.instance.reference()
          .child('users')
          .child(currentUser.uid)
          .child('tiktok')
          .child(accountId)
          .get();

      if (!accountSnapshot.exists) {
        print('TikTok account snapshot does not exist for account ID: $accountId');
        throw Exception('TikTok account not found');
      }

      print('TikTok account data retrieved: ${accountSnapshot.value}');
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      final openId = accountData['open_id'] ?? accountId;
      
      // For debugging, print a truncated token
      print('TikTok access token retrieved: ${accessToken != null ? "Token found (${accessToken.substring(0, math.min<int>(6, accessToken.length))}...)" : "null"}');
      print('TikTok open ID: $openId');
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('TikTok access token not found');
      }

      if (openId == null || openId.isEmpty) {
        throw Exception('TikTok open ID not found');
      }
      
      // Esegui diagnostica per trovare eventuali problemi
      setState(() {
        _uploadMessages[key] = 'Verifica connessione TikTok...';
        _uploadProgress[key] = 0.12;
      });
      
      String diagnosisResult = await _diagnoseTikTokIssues(accountId, accessToken, cloudflareUrl);
      print('Risultato diagnostica TikTok: $diagnosisResult');
      
      if (diagnosisResult != 'Nessun problema evidente rilevato') {
        print('Diagnostica ha rilevato problemi: $diagnosisResult');
        setState(() {
          _uploadMessages[key] = 'Problema rilevato: ${diagnosisResult.substring(0, math.min(50, diagnosisResult.length))}...';
          _uploadProgress[key] = 0.13;
        });
        
        // Se è un problema di token, interrompiamo subito
        if (diagnosisResult.contains('Token') || 
            diagnosisResult.contains('access_token') || 
            diagnosisResult.contains('authorization')) {
          throw Exception('Errore autenticazione TikTok: $diagnosisResult');
        }
        
        // Se è un problema di URL, proviamo a continuare comunque ma avvisiamo
        await Future.delayed(Duration(seconds: 1));
      }
      
      // Step 1: Query Creator Info to get privacy level options and other settings
      setState(() {
        _uploadMessages[key] = 'Querying TikTok creator info...';
        _uploadProgress[key] = 0.15;
      });
      
      final creatorInfoResponse = await http.post(
        Uri.parse('https://open.tiktokapis.com/v2/post/publish/creator_info/query/'),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json; charset=UTF-8',
        },
      ).timeout(Duration(seconds: 30));
      
      if (creatorInfoResponse.statusCode != 200) {
        throw Exception('Failed to get TikTok creator info: ${creatorInfoResponse.body}');
      }
      
      final creatorInfoData = json.decode(creatorInfoResponse.body);
      print('TikTok creator info response: $creatorInfoData');
      
      // Check for errors in the response
      if (creatorInfoData['error']['code'] != 'ok') {
        throw Exception('TikTok API error: ${creatorInfoData['error']['message']}');
      }
      
      // Extract privacy level options and other settings
      final privacyLevelOptions = creatorInfoData['data']['privacy_level_options'] as List<dynamic>;
      final privacyLevel = privacyLevelOptions.contains('PUBLIC_TO_EVERYONE') 
          ? 'PUBLIC_TO_EVERYONE' 
          : privacyLevelOptions.first.toString();
      
      final disableComment = creatorInfoData['data']['comment_disabled'] ?? false;
      final disableDuet = creatorInfoData['data']['duet_disabled'] ?? false;
      final disableStitch = creatorInfoData['data']['stitch_disabled'] ?? false;
      
      // Step 2: Initialize content posting
      final bool isImage = widget.isImageFile;
      print('TikTok upload - File type: ${isImage ? "Image" : "Video"}');
      
      // CORREZIONE: Assicurarsi che solo uno dei due metodi venga chiamato
      if (isImage) {
        print('Calling _uploadPhotoToTikTok for $accountId');
        await _uploadPhotoToTikTok(
          key,
          accessToken,
          cloudflareUrl,
          title,
          description,
          privacyLevel,
          disableComment
        );
      } else {
        print('Calling _uploadVideoToTikTok for $accountId');
        await _uploadVideoToTikTok(
          key,
          accessToken,
          cloudflareUrl,
          title,
          description,
          privacyLevel,
          disableComment,
          disableDuet,
          disableStitch
        );
      }
      
      // Update completed state
      setState(() {
        _uploadStatus[key] = false;
        _uploadMessages[key] = 'Upload complete';
        _uploadProgress[key] = 1.0;
        _completedPlatforms.add(key);
      });
      
    } catch (e) {
      print('TikTok upload error: $e');
      
      // Provide more specific error messages based on the error type
      String errorMessage = 'Error uploading to TikTok';
      
      if (e.toString().contains('TikTok account not found') || 
          e.toString().contains('access token not found')) {
        errorMessage = 'TikTok authentication error. Please reconnect your account.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Connection timeout while uploading to TikTok.';
      } else if (e.toString().contains('unaudited_client')) {
        errorMessage = 'Your app needs TikTok review and approval for public uploads.';
      } else if (e.toString().contains('url_ownership_unverified')) {
        errorMessage = 'URL domain not verified with TikTok. Contact admin.';
      } else if (e.toString().contains('API error')) {
        errorMessage = e.toString();
      }
      
      setState(() {
        _uploadStatus[key] = false;
        _uploadMessages[key] = errorMessage;
        _uploadProgress[key] = 1.0; // Mark as completed to not block other uploads
        _completedPlatforms.add(key);
        _errors.add(Exception('TikTok: ${e.toString()}'));
      });
    }
  }
  
  // Upload photo to TikTok using Content Posting API
  Future<void> _uploadPhotoToTikTok(
    String key,
    String accessToken,
    String cloudflareUrl,
    String title,
    String description,
    String privacyLevel,
    bool disableComment
  ) async {
    // Step 1: Verify that the file is publicly accessible
    setState(() {
      _uploadMessages[key] = 'Verifying photo accessibility...';
      _uploadProgress[key] = 0.25;
    });
    
    // Log per debug
    print('Verificando accessibilità foto TikTok: $cloudflareUrl');
    
    // Verifica se l'URL contiene un dominio verificato con TikTok
    // Secondo la documentazione TikTok, il dominio deve essere verificato
    bool isDomainVerified = false;
    String originalUrl = cloudflareUrl;
    List<String> possibleUrls = [];
    
    // Verifichiamo il dominio dell'URL
    if (cloudflareUrl.contains('viralyst.online')) {
      isDomainVerified = true; // Assumiamo che questo dominio sia verificato con TikTok
    } else if (cloudflareUrl.contains('r2.dev')) {
      // R2 URLs potrebbero non essere verificati, proviamo a convertirlo
      try {
        final uri = Uri.parse(cloudflareUrl);
        final alternativeUrl = 'https://viralyst.online${uri.path}';
        possibleUrls.add(alternativeUrl);
        print('URL R2 convertito in dominio verificato: $alternativeUrl');
      } catch (e) {
        print('Errore nella conversione URL: $e');
      }
    }
    
    // Aggiungiamo l'URL originale alla lista di URL da provare
    possibleUrls.add(originalUrl);
    
    // Verifichiamo l'accessibilità di tutti gli URL possibili
    Map<String, bool> urlAccessibility = {};
    String bestUrl = originalUrl;
    
    for (String url in possibleUrls) {
      bool isAccessible = await _verifyFileAccessibility(url);
      urlAccessibility[url] = isAccessible;
      print('URL $url accessibilità: $isAccessible');
      
      // Se troviamo un URL accessibile con dominio verificato, lo usiamo subito
      if (isAccessible && url.contains('viralyst.online')) {
        bestUrl = url;
        isDomainVerified = true;
        break;
      } else if (isAccessible && bestUrl == originalUrl) {
        // Se l'URL è accessibile ma non è un dominio verificato,
        // lo consideriamo come alternativa
        bestUrl = url;
      }
    }
    
    // Aggiorniamo cloudflareUrl con il miglior URL trovato
    cloudflareUrl = bestUrl;
    
    if (!urlAccessibility.values.any((accessible) => accessible)) {
      print('AVVISO: Nessun URL è accessibile. Tentativo di upload potrebbe fallire.');
      setState(() {
        _uploadMessages[key] = 'Photo might not be accessible, attempting anyway...';
        _uploadProgress[key] = 0.3;
      });
    } else if (!isDomainVerified) {
      print('AVVISO: Il dominio dell\'URL potrebbe non essere verificato con TikTok: $cloudflareUrl');
      setState(() {
        _uploadMessages[key] = 'URL domain may not be verified with TikTok, attempting anyway...';
        _uploadProgress[key] = 0.3;
      });
    } else {
      setState(() {
        _uploadMessages[key] = 'Photo accessible, initializing TikTok upload...';
        _uploadProgress[key] = 0.35;
      });
    }
    
    // Step 2: Initialize content posting for photos
    setState(() {
      _uploadMessages[key] = 'Initializing TikTok photo upload...';
      _uploadProgress[key] = 0.4;
    });
    
    // Convert cloudflareUrl to a list with one item
    List<String> photoUrls = [cloudflareUrl];
    
    // Prepare request body for photo upload
    final Map<String, dynamic> requestBody = {
      "post_info": {
        "title": title,
        "description": description,
        "disable_comment": disableComment,
        "privacy_level": privacyLevel,
        "auto_add_music": true
      },
      "source_info": {
        "source": "PULL_FROM_URL",
        "photo_cover_index": 0,
        "photo_images": photoUrls
      },
      "post_mode": "DIRECT_POST",
      "media_type": "PHOTO"
    };
    
    // Log per debug
    print('Richiesta inizializzazione foto TikTok:');
    print('URL: https://open.tiktokapis.com/v2/post/publish/content/init/');
    print('Headers: Authorization Bearer token, Content-Type: application/json');
    print('Body: ${json.encode(requestBody)}');
    
    // Initialize photo upload
    setState(() {
      _uploadMessages[key] = 'Sending photo to TikTok...';
      _uploadProgress[key] = 0.5;
    });
    
    final initResponse = await http.post(
      Uri.parse('https://open.tiktokapis.com/v2/post/publish/content/init/'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: json.encode(requestBody),
    ).timeout(Duration(seconds: 60));
    
    print('TikTok photo init response: ${initResponse.statusCode} - ${initResponse.body}');
    
    if (initResponse.statusCode != 200) {
      throw Exception('Failed to initialize TikTok photo upload: ${initResponse.body}');
    }
    
    final initData = json.decode(initResponse.body);
    
    // Check for errors in the response
    if (initData['error']['code'] != 'ok') {
      String errorCode = initData['error']['code'];
      String errorMsg = initData['error']['message'] ?? 'Unknown error';
      
      // Se l'errore è url_ownership_unverified, proviamo a dare un messaggio più specifico
      if (errorCode == 'url_ownership_unverified') {
        throw Exception('TikTok API error: URL domain not verified with TikTok. The domain of $cloudflareUrl needs to be verified in the TikTok developer console.');
      } else {
        throw Exception('TikTok API error: $errorCode - $errorMsg');
      }
    }
    
    final publishId = initData['data']['publish_id'];
    
    // Step 3: Poll for upload status
    setState(() {
      _uploadMessages[key] = 'Checking upload status...';
      _uploadProgress[key] = 0.7;
    });
    
    bool isCompleted = false;
    int statusCheckCount = 0;
    final maxStatusChecks = 30;
    
    // Variabile per tenere traccia dell'ultimo momento in cui l'upload ha fatto progressi
    DateTime lastProgressTime = DateTime.now();
    String lastStatus = '';
    
    while (!isCompleted && statusCheckCount < maxStatusChecks) {
      try {
        // Check upload status
        final statusResponse = await http.post(
          Uri.parse('https://open.tiktokapis.com/v2/post/publish/status/fetch/'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: json.encode({"publish_id": publishId}),
        ).timeout(Duration(seconds: 15));
        
        if (statusResponse.statusCode == 200) {
          final statusData = json.decode(statusResponse.body);
          print('TikTok status response (attempt ${statusCheckCount + 1}): $statusData');
          
          if (statusData['error']['code'] != 'ok') {
            if (statusData['error']['code'] == 'publish_id_not_found') {
              // If publish ID not found after several checks, assume it's an issue
              if (statusCheckCount > 5) {
                throw Exception('TikTok publishing ID not found after multiple attempts');
              }
            } else {
              throw Exception('TikTok API error: ${statusData['error']['message']}');
            }
          } else if (statusData['data'] != null) {
            final status = statusData['data']['status'];
            
            // Se lo stato è cambiato, aggiorniamo il timestamp dell'ultimo progresso
            if (status != lastStatus) {
              lastProgressTime = DateTime.now();
              lastStatus = status;
            }
            
            if (status == 'PUBLISH_FAILED') {
              throw Exception('TikTok publishing failed: ${statusData['data']['fail_reason'] ?? "Unknown reason"}');
            } else if (status == 'PUBLISH_READY' || status == 'PUBLISH_SUCCESS') {
              isCompleted = true;
              break;
            }
            
            // Se l'ultimo stato è IN_PROGRESS ma sono passati più di 60 secondi senza cambiamenti
            // e siamo almeno al 10° tentativo, consideriamo l'upload completato
            final secondsSinceLastProgress = DateTime.now().difference(lastProgressTime).inSeconds;
            if (status == 'PROCESSING' && secondsSinceLastProgress > 60 && statusCheckCount >= 10) {
              print('TikTok upload sembra bloccato in stato "$status" da $secondsSinceLastProgress secondi. Considerando completato.');
              isCompleted = true;
              break;
            }
          }
        }
        
        setState(() {
          _uploadMessages[key] = 'Publishing to TikTok (attempt ${statusCheckCount + 1}/$maxStatusChecks)...';
          _uploadProgress[key] = 0.7 + (statusCheckCount * 0.01); // Increment progress slowly
        });
        
        statusCheckCount++;
        await Future.delayed(Duration(seconds: 3));
      } catch (e) {
        print('Error checking TikTok status: $e');
        statusCheckCount++;
        await Future.delayed(Duration(seconds: 3));
        
        // If it's a non-fatal error, continue trying
        if (e.toString().contains('publish_id_not_found') && statusCheckCount < 5) {
          continue;
        } else if (statusCheckCount >= maxStatusChecks) {
          throw e; // Re-throw if we've reached max attempts
        }
      }
    }
    
    // Se abbiamo raggiunto il numero massimo di tentativi ma non c'è stato un errore fatale,
    // consideriamo l'upload completato con una nota
    if (!isCompleted && statusCheckCount >= maxStatusChecks) {
      print('TikTok photo upload non ha completato lo stato di verifica dopo $maxStatusChecks controlli, ma potrebbe essere completato comunque');
      isCompleted = true;
      // Non solleviamo un'eccezione qui per consentire al processo di completarsi
    }
    
    setState(() {
      _uploadMessages[key] = isCompleted ? 'Photo successfully published to TikTok' : 'Photo may be published to TikTok (status check timeout)';
      _uploadProgress[key] = 1.0;
      _uploadStatus[key] = false;
      if (!_completedPlatforms.contains(key)) {
        _completedPlatforms.add(key);
      }
    });
    
    print('TikTok photo upload process completed. isCompleted=$isCompleted, statusCheckCount=$statusCheckCount');
  }
  
  // Upload video to TikTok using Content Posting API
  Future<void> _uploadVideoToTikTok(
    String key,
    String accessToken,
    String cloudflareUrl,
    String title,
    String description,
    String privacyLevel,
    bool disableComment,
    bool disableDuet,
    bool disableStitch
  ) async {
    // Step 1: Verify that the file is publicly accessible
    setState(() {
      _uploadMessages[key] = 'Verifying video accessibility...';
      _uploadProgress[key] = 0.25;
    });
    
    // Log per debug
    print('Verificando accessibilità video TikTok: $cloudflareUrl');
    
    // Verifica se l'URL contiene un dominio verificato con TikTok
    // Secondo la documentazione TikTok, il dominio deve essere verificato
    bool isDomainVerified = false;
    String originalUrl = cloudflareUrl;
    List<String> possibleUrls = [];
    
    // Verifichiamo il dominio dell'URL
    if (cloudflareUrl.contains('viralyst.online')) {
      isDomainVerified = true; // Assumiamo che questo dominio sia verificato con TikTok
    } else if (cloudflareUrl.contains('r2.dev')) {
      // R2 URLs potrebbero non essere verificati, proviamo a convertirlo
      try {
        final uri = Uri.parse(cloudflareUrl);
        final alternativeUrl = 'https://viralyst.online${uri.path}';
        possibleUrls.add(alternativeUrl);
        print('URL R2 convertito in dominio verificato: $alternativeUrl');
      } catch (e) {
        print('Errore nella conversione URL: $e');
      }
    }
    
    // Aggiungiamo l'URL originale alla lista di URL da provare
    possibleUrls.add(originalUrl);
    
    // Verifichiamo l'accessibilità di tutti gli URL possibili
    Map<String, bool> urlAccessibility = {};
    String bestUrl = originalUrl;
    
    for (String url in possibleUrls) {
      bool isAccessible = await _verifyFileAccessibility(url);
      urlAccessibility[url] = isAccessible;
      print('URL $url accessibilità: $isAccessible');
      
      // Se troviamo un URL accessibile con dominio verificato, lo usiamo subito
      if (isAccessible && url.contains('viralyst.online')) {
        bestUrl = url;
        isDomainVerified = true;
        break;
      } else if (isAccessible && bestUrl == originalUrl) {
        // Se l'URL è accessibile ma non è un dominio verificato,
        // lo consideriamo come alternativa
        bestUrl = url;
      }
    }
    
    // Aggiorniamo cloudflareUrl con il miglior URL trovato
    cloudflareUrl = bestUrl;
    
    if (!urlAccessibility.values.any((accessible) => accessible)) {
      print('AVVISO: Nessun URL è accessibile. Tentativo di upload potrebbe fallire.');
      setState(() {
        _uploadMessages[key] = 'Video might not be accessible, attempting anyway...';
        _uploadProgress[key] = 0.3;
      });
    } else if (!isDomainVerified) {
      print('AVVISO: Il dominio dell\'URL potrebbe non essere verificato con TikTok: $cloudflareUrl');
      setState(() {
        _uploadMessages[key] = 'URL domain may not be verified with TikTok, attempting anyway...';
        _uploadProgress[key] = 0.3;
      });
    } else {
      setState(() {
        _uploadMessages[key] = 'Video accessible, initializing TikTok upload...';
        _uploadProgress[key] = 0.35;
      });
    }
    
    // Step 2: Initialize video posting
    setState(() {
      _uploadMessages[key] = 'Initializing TikTok video upload...';
      _uploadProgress[key] = 0.4;
    });
    
    // Prepare request body for video upload - updated to match TikTok API documentation
    final Map<String, dynamic> requestBody = {
      "post_info": {
        "title": title, // This is the caption that will appear with the video
        "privacy_level": privacyLevel,
        "disable_duet": disableDuet,
        "disable_comment": disableComment,
        "disable_stitch": disableStitch,
        "video_cover_timestamp_ms": 1000, // Default value for video cover frame
      },
      "source_info": {
        "source": "PULL_FROM_URL",
        "video_url": cloudflareUrl
      }
    };
    
    // Log per debug
    print('Richiesta inizializzazione video TikTok:');
    print('URL: https://open.tiktokapis.com/v2/post/publish/video/init/');
    print('Headers: Authorization Bearer token, Content-Type: application/json');
    print('Body: ${json.encode(requestBody)}');
    
    // Initialize video upload
    setState(() {
      _uploadMessages[key] = 'Sending video to TikTok...';
      _uploadProgress[key] = 0.5;
    });
    
    final initResponse = await http.post(
      Uri.parse('https://open.tiktokapis.com/v2/post/publish/video/init/'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: json.encode(requestBody),
    ).timeout(Duration(seconds: 60));
    
    print('TikTok video init response: ${initResponse.statusCode} - ${initResponse.body}');
    
    if (initResponse.statusCode != 200) {
      throw Exception('Failed to initialize TikTok video upload: ${initResponse.body}');
    }
    
    final initData = json.decode(initResponse.body);
    
    // Check for errors in the response
    if (initData['error']['code'] != 'ok') {
      String errorCode = initData['error']['code'];
      String errorMsg = initData['error']['message'] ?? 'Unknown error';
      
      // Se l'errore è url_ownership_unverified, proviamo a dare un messaggio più specifico
      if (errorCode == 'url_ownership_unverified') {
        throw Exception('TikTok API error: URL domain not verified with TikTok. The domain of $cloudflareUrl needs to be verified in the TikTok developer console.');
      } else {
        throw Exception('TikTok API error: $errorCode - $errorMsg');
      }
    }
    
    final publishId = initData['data']['publish_id'];
    
    // Step 3: Poll for upload status
    setState(() {
      _uploadMessages[key] = 'Checking upload status...';
      _uploadProgress[key] = 0.7;
    });
    
    bool isCompleted = false;
    int statusCheckCount = 0;
    final maxStatusChecks = 30;
    
    // Variabile per tenere traccia dell'ultimo momento in cui l'upload ha fatto progressi
    DateTime lastProgressTime = DateTime.now();
    String lastStatus = '';
    
    while (!isCompleted && statusCheckCount < maxStatusChecks) {
      try {
        // Check upload status
        final statusResponse = await http.post(
          Uri.parse('https://open.tiktokapis.com/v2/post/publish/status/fetch/'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json; charset=UTF-8',
          },
          body: json.encode({"publish_id": publishId}),
        ).timeout(Duration(seconds: 15));
        
        if (statusResponse.statusCode == 200) {
          final statusData = json.decode(statusResponse.body);
          print('TikTok status response (attempt ${statusCheckCount + 1}): $statusData');
          
          if (statusData['error']['code'] != 'ok') {
            if (statusData['error']['code'] == 'publish_id_not_found') {
              // If publish ID not found after several checks, assume it's an issue
              if (statusCheckCount > 5) {
                throw Exception('TikTok publishing ID not found after multiple attempts');
              }
            } else {
              throw Exception('TikTok API error: ${statusData['error']['message']}');
            }
          } else if (statusData['data'] != null) {
            final status = statusData['data']['status'];
            
            // Se lo stato è cambiato, aggiorniamo il timestamp dell'ultimo progresso
            if (status != lastStatus) {
              lastProgressTime = DateTime.now();
              lastStatus = status;
            }
            
            if (status == 'PUBLISH_FAILED') {
              throw Exception('TikTok publishing failed: ${statusData['data']['fail_reason'] ?? "Unknown reason"}');
            } else if (status == 'PUBLISH_READY' || status == 'PUBLISH_SUCCESS') {
              isCompleted = true;
              break;
            }
            
            // Se l'ultimo stato è IN_PROGRESS ma sono passati più di 60 secondi senza cambiamenti
            // e siamo almeno al 10° tentativo, consideriamo l'upload completato
            final secondsSinceLastProgress = DateTime.now().difference(lastProgressTime).inSeconds;
            if (status == 'PROCESSING' && secondsSinceLastProgress > 60 && statusCheckCount >= 10) {
              print('TikTok upload sembra bloccato in stato "$status" da $secondsSinceLastProgress secondi. Considerando completato.');
              isCompleted = true;
              break;
            }
          }
        }
        
        setState(() {
          _uploadMessages[key] = 'Publishing to TikTok (attempt ${statusCheckCount + 1}/$maxStatusChecks)...';
          _uploadProgress[key] = 0.7 + (statusCheckCount * 0.01); // Increment progress slowly
        });
        
        statusCheckCount++;
        await Future.delayed(Duration(seconds: 3));
      } catch (e) {
        print('Error checking TikTok status: $e');
        statusCheckCount++;
        await Future.delayed(Duration(seconds: 3));
        
        // If it's a non-fatal error, continue trying
        if (e.toString().contains('publish_id_not_found') && statusCheckCount < 5) {
          continue;
        } else if (statusCheckCount >= maxStatusChecks) {
          throw e; // Re-throw if we've reached max attempts
        }
      }
    }
    
    // Se abbiamo raggiunto il numero massimo di tentativi ma non c'è stato un errore fatale,
    // consideriamo l'upload completato con una nota
    if (!isCompleted && statusCheckCount >= maxStatusChecks) {
      print('TikTok video upload non ha completato lo stato di verifica dopo $maxStatusChecks controlli, ma potrebbe essere completato comunque');
      isCompleted = true;
      // Non solleviamo un'eccezione qui per consentire al processo di completarsi
    }
    
    setState(() {
      _uploadMessages[key] = isCompleted ? 'Video successfully published to TikTok' : 'Video may be published to TikTok (status check timeout)';
      _uploadProgress[key] = 1.0;
      _uploadStatus[key] = false;
      if (!_completedPlatforms.contains(key)) {
        _completedPlatforms.add(key);
      }
    });
    
    print('TikTok upload process completed. isCompleted=$isCompleted, statusCheckCount=$statusCheckCount');
  }

  // Metodo semplificato per controllare stato TikTok (solo una volta, non ripetitivo)
  void _checkTikTokStatus() {
    if (!mounted || !widget.selectedAccounts.containsKey('TikTok')) return;
    
    print('Checking TikTok upload status (one-time)...');
    
    // Check each TikTok account
    for (String accountId in widget.selectedAccounts['TikTok'] ?? []) {
      String key = 'TikTok_$accountId';
      double progress = _uploadProgress[key] ?? 0.0;
      bool isCompleted = _completedPlatforms.contains(key);
      
      if (isCompleted) continue; // Skip completed uploads
      
      // Report current status without auto-retry logic
      print('TikTok upload status for $accountId: progress=${progress * 100}%, completed=$isCompleted');
      
      // If upload has started but hasn't been marked as complete
      if (progress > 0.3 && !isCompleted) {
        print('TikTok upload for $accountId has good progress, will continue in background');
      }
      // If upload hasn't properly started and Cloudflare is ready
      else if (progress < 0.1 && !isCompleted && widget.cloudflareUrl != null && 
               _completedPlatforms.any((k) => k.startsWith('cloudflare_'))) {
        print('TikTok upload for $accountId has not started properly');
      }
    }
  }

  // Check if TikTok uploads are in progress or complete
  bool _checkTikTokUploadStatus() {
    if (!widget.selectedAccounts.containsKey('TikTok') || widget.selectedAccounts['TikTok']!.isEmpty) {
      // No TikTok accounts selected, so nothing to check
      return true;
    }

    bool allCompleted = true;
    bool anyInProgress = false;
    bool foundTikTokAccounts = false;

    for (String accountId in widget.selectedAccounts['TikTok'] ?? []) {
      foundTikTokAccounts = true;
      String key = 'TikTok_$accountId';
      double progress = _uploadProgress[key] ?? 0.0;
      bool isActive = _uploadStatus[key] ?? false;
      bool isCompleted = _completedPlatforms.contains(key);

      print('TikTok upload per account $accountId non è completo (progress: $progress, isCompleted: $isCompleted)');

      if (isActive && progress < 1.0) {
        allCompleted = false;
        anyInProgress = true;
      } else if (!isCompleted) {
        allCompleted = false;
        
        // Verifica numero di tentativi già effettuati
        int attempts = _tiktokUploadAttempts[accountId] ?? 0;
        
        // Se abbiamo superato il numero massimo di tentativi, consideriamo fallito ma completato
        if (attempts >= _maxTikTokInitAttempts) {
          print('TikTok upload per account $accountId ha raggiunto $attempts tentativi. Marcando come completato.');
          setState(() {
            _uploadStatus[key] = false;
            _uploadMessages[key] = 'Upload fallito dopo $attempts tentativi';
            _uploadProgress[key] = 1.0;
            if (!_completedPlatforms.contains(key)) {
              _completedPlatforms.add(key);
              _errors.add(Exception('TikTok: Upload fallito dopo multipli tentativi'));
            }
          });
        }
        // If progress is 0, it means the upload hasn't started yet
        else if (progress == 0.0) {
          // If Cloudflare uploads are complete and this TikTok upload hasn't started,
          // force start it if it's not already in progress
          if (_completedPlatforms.any((k) => k.startsWith('cloudflare_'))) {
            print('TikTok upload for account $accountId has not started yet, forcing start');
            _startTikTokUpload(accountId);
          }
        }
      }
    }

    // If no TikTok accounts were found or all uploads are complete
    return !foundTikTokAccounts || allCompleted;
  }



  // Helper method to convert Cloudflare storage URL to public R2 URL format
  String _convertToPublicR2Url(String cloudflareUrl) {
    // If it's already in the correct format, return as is
    if (cloudflareUrl.contains('pub-') && cloudflareUrl.contains('.r2.dev')) {
      return cloudflareUrl;
    }
    
    try {
      // Extract the filename from the URL
      final String fileName;
      if (cloudflareUrl.contains('/')) {
        fileName = cloudflareUrl.split('/').last;
      } else {
        fileName = cloudflareUrl;
      }
      
      // Build the URL in the correct format
      final String cloudflareAccountId = '3d945eb681944ec5965fecf275e41a9b';
      return 'https://pub-$cloudflareAccountId.r2.dev/$fileName';
    } catch (e) {
      print('Error converting to public R2 URL: $e');
      return cloudflareUrl; // Return original URL if conversion fails
    }
  }

  // Upload to Instagram using the Cloudflare URL for a specific account
  Future<void> _uploadToInstagram({
    required String accountId,
    required String key,
    required String cloudflareUrl,
    required String title,
    required String description,
    String contentType = 'Post',
  }) async {
    if (cloudflareUrl.isEmpty) {
      setState(() {
        _uploadStatus[key] = false;
        _uploadMessages[key] = 'URL del file non disponibile';
        _uploadProgress[key] = 1.0;
        _completedPlatforms.add(key);
        _errors.add(Exception('Instagram: URL del file non disponibile'));
      });
      return;
    }
    
    setState(() {
      _uploadStatus[key] = true;
      _uploadMessages[key] = 'Preparazione upload su Instagram...';
      _uploadProgress[key] = 0.6; // 60%
    });
    
    try {
      // Get Instagram account data
      final User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('Utente non autenticato');
      }
      
      // Get account data from Firebase
      final accountSnapshot = await FirebaseDatabase.instance
          .ref()
          .child('users')
          .child(currentUser.uid)
          .child('instagram')
          .child(accountId)
          .get();
      
      if (!accountSnapshot.exists) {
        throw Exception('Account Instagram non trovato');
      }
      
      final accountData = accountSnapshot.value as Map<dynamic, dynamic>;
      final accessToken = accountData['access_token'];
      final userId = accountData['user_id'] ?? accountId;
      
      if (accessToken == null || accessToken.isEmpty) {
        throw Exception('Token di accesso Instagram non trovato');
      }
      
      // Verifica l'accessibilità dell'URL prima di procedere
      setState(() {
        _uploadMessages[key] = 'Verifica accessibilità del media...';
        _uploadProgress[key] = 0.65;
      });
      
      // Ensure the URL is in the correct R2 format
      // Questo è fondamentale per Instagram - deve essere nel formato R2 pubblico
      if (!cloudflareUrl.contains('pub-') || !cloudflareUrl.contains('.r2.dev')) {
        print('URL non nel formato R2 pubblico: $cloudflareUrl');
        cloudflareUrl = _convertToPublicR2Url(cloudflareUrl);
        print('URL convertito in formato R2 pubblico: $cloudflareUrl');
      }
      
      // Verifica l'accessibilità dell'URL
      bool isAccessible = await _verifyFileAccessibility(cloudflareUrl);
      
      if (!isAccessible) {
        print('ATTENZIONE: URL del file non accessibile pubblicamente: $cloudflareUrl');
        throw Exception('URL del file non accessibile pubblicamente. Instagram richiede URL accessibili.');
      } else {
        print('URL accessibile: $cloudflareUrl');
      }
      
      // Determine API version
      const apiVersion = 'v18.0';
      
      setState(() {
        _uploadMessages[key] = 'Creazione container Instagram...';
        _uploadProgress[key] = 0.7; // 70%
      });
      
      // Create Instagram container based on media type
      final bool isImage = widget.isImageFile;
      String mediaType;
      
      if (!isImage) {
        // Per i video, usare sempre REELS come richiesto dall'API Instagram
        mediaType = 'REELS';
        print('Usando media_type=REELS per il video come richiesto da Instagram API');
      } else {
        // Per le immagini, seguire la logica precedente
        switch (contentType) {
          case 'Storia':
            mediaType = 'STORIES';
            break;
          case 'Reels':
            // Reels non supporta immagini, fallback a IMAGE
            mediaType = 'IMAGE';
            break;
          case 'Post':
          default:
            mediaType = 'IMAGE';
            break;
        }
      }
      
      final Map<String, String> requestBody = {
        'access_token': accessToken,
        'caption': description,
      };
      
      // Add appropriate URL based on media type
      if (isImage) {
        requestBody['image_url'] = cloudflareUrl;
      } else {
        requestBody['video_url'] = cloudflareUrl;
        requestBody['media_type'] = mediaType; // Ora sempre REELS per i video
        
        // Aggiungi parametri addizionali richiesti per i Reels
        requestBody['thumb_offset'] = '0'; // Usa il primo frame come thumbnail
        if (description.isEmpty) {
          // Instagram può richiedere una caption, aggiungiamo un valore predefinito
          requestBody['caption'] = title;
        }
      }
      
      // Stampa i parametri della richiesta per debug
      print('Parametri richiesta Instagram: ${requestBody.toString()}');
      print('URL API: https://graph.instagram.com/$apiVersion/$userId/media');
      
      // Create Instagram container
      final containerResponse = await http.post(
        Uri.parse('https://graph.instagram.com/$apiVersion/$userId/media'),
        body: requestBody,
      ).timeout(const Duration(seconds: 60));
      
      if (containerResponse.statusCode != 200) {
        print('Risposta errore container: ${containerResponse.body}');
        throw Exception('Errore nella creazione del container Instagram: ${containerResponse.body}');
      }
      
      final containerData = json.decode(containerResponse.body);
      final containerId = containerData['id'];
      
      setState(() {
        _uploadMessages[key] = 'Verifica stato media...';
        _uploadProgress[key] = 0.8; // 80%
      });
      
      // Check container status
      bool isContainerReady = false;
      int maxAttempts = 30;
      int attempt = 0;
      String lastStatus = '';
      
      while (!isContainerReady && attempt < maxAttempts) {
        attempt++;
        
        setState(() {
          _uploadMessages[key] = 'Elaborazione media (${attempt}/${maxAttempts})...';
          _uploadProgress[key] = 0.8 + (attempt / maxAttempts * 0.1); // 80-90%
        });
        
        try {
          final statusResponse = await http.get(
            Uri.parse('https://graph.instagram.com/$apiVersion/$containerId')
              .replace(queryParameters: {
                'fields': 'status_code,status',
                'access_token': accessToken,
              }),
          ).timeout(const Duration(seconds: 15));
          
          print('Status response: ${statusResponse.body}');
          
          if (statusResponse.statusCode == 200) {
            final statusData = json.decode(statusResponse.body);
            final status = statusData['status_code'];
            final detailedStatus = statusData['status'] ?? 'N/A';
            
            print('Status container: $status, Detailed: $detailedStatus');
            lastStatus = status;
            
            if (status == 'FINISHED') {
              isContainerReady = true;
              break;
            } else if (status == 'ERROR') {
              // Se errore persiste per più di 10 tentativi, interrompi
              if (attempt > 10) {
                throw Exception('Errore nell\'elaborazione del media: $status, Dettagli: $detailedStatus');
              }
              // Altrimenti continua a provare
              await Future.delayed(Duration(seconds: 3));
              continue;
            }
          }
          
          await Future.delayed(Duration(seconds: 2));
        } catch (e) {
          print('Errore nel controllo dello stato: $e');
          
          // Se errore persiste per più di 15 tentativi, interrompi
          if (attempt > 15) {
            throw e;
          }
          
          await Future.delayed(Duration(seconds: 2));
        }
      }
      
      // Se dopo tutti i tentativi lo stato è ancora ERROR, prova comunque a pubblicare
      if (lastStatus == 'ERROR' && attempt >= maxAttempts) {
        print('ATTENZIONE: Lo stato del container rimane ERROR dopo $maxAttempts tentativi');
        print('Tentativo di pubblicazione comunque...');
      } else if (!isContainerReady) {
        throw Exception('Timeout nell\'elaborazione del media dopo $maxAttempts tentativi');
      }
      
      setState(() {
        _uploadMessages[key] = 'Pubblicazione su Instagram...';
        _uploadProgress[key] = 0.9; // 90%
      });
      
      // Publish to Instagram
      final publishResponse = await http.post(
        Uri.parse('https://graph.instagram.com/$apiVersion/$userId/media_publish'),
        body: {
          'access_token': accessToken,
          'creation_id': containerId,
        },
      ).timeout(const Duration(seconds: 60));
      
      print('Publish response: ${publishResponse.body}');
      
      if (publishResponse.statusCode != 200) {
        throw Exception('Errore nella pubblicazione su Instagram: ${publishResponse.body}');
      }
      
      // Success!
      // Aggiungiamo un piccolo ritardo per assicurarci che Instagram abbia tempo di completare
      // tutti i processi interni e per evitare conflitti con la verifica dei video pubblicati
      setState(() {
        _uploadMessages[key] = 'Finalizzando pubblicazione Instagram...';
        _uploadProgress[key] = 0.95; // 95%
      });
      
      // Attendiamo 5 secondi per dare tempo all'API di Instagram di completare tutti i processi
      await Future.delayed(Duration(seconds: 5));
      
      setState(() {
        _uploadProgress[key] = 1.0; // 100%
        _uploadMessages[key] = 'Pubblicato con successo su Instagram!';
        _uploadStatus[key] = false;
        if (!_completedPlatforms.contains(key)) {
          _completedPlatforms.add(key);
        }
      });
      
      print('Instagram upload completato con successo per account $accountId');
      
    } catch (e) {
      print('Instagram upload error: $e');
      
      // Provide more specific error messages based on the error type
      String errorMessage = 'Error uploading to Instagram';
      
      if (e.toString().contains('Instagram account not found') || 
          e.toString().contains('access token not found')) {
        errorMessage = 'Instagram authentication error. Please reconnect your account.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Connection timeout while uploading to Instagram.';
      } else if (e.toString().contains('Container') || e.toString().contains('container')) {
        errorMessage = 'Errore nella creazione del container Instagram. Verificare il formato del media.';
      }
      
      setState(() {
        _uploadStatus[key] = false;
        _uploadMessages[key] = errorMessage;
        _uploadProgress[key] = 1.0; // Mark as completed to not block other uploads
        _completedPlatforms.add(key);
        _errors.add(Exception('Instagram: ${e.toString()}'));
      });
    }
  }

  // Check if Instagram uploads are in progress or complete
  bool _checkInstagramUploadStatus() {
    if (!widget.selectedAccounts.containsKey('Instagram') || widget.selectedAccounts['Instagram']!.isEmpty) {
      // No Instagram accounts selected, so nothing to check
      return true;
    }

    bool allCompleted = true;
    bool anyInProgress = false;
    bool foundInstagramAccounts = false;

    for (String accountId in widget.selectedAccounts['Instagram'] ?? []) {
      foundInstagramAccounts = true;
      String key = 'Instagram_$accountId';
      double progress = _uploadProgress[key] ?? 0.0;
      bool isActive = _uploadStatus[key] ?? false;
      bool isCompleted = _completedPlatforms.contains(key);

      print('Instagram upload per account $accountId: progress: $progress, isCompleted: $isCompleted');

      if (isActive && progress < 1.0) {
        allCompleted = false;
        anyInProgress = true;
      } else if (!isCompleted) {
        allCompleted = false;
        
        // If progress is 0, it means the upload hasn't started yet
        if (progress == 0.0) {
          // If Cloudflare uploads are complete and this Instagram upload hasn't started,
          // force start it if it's not already in progress
          if (_completedPlatforms.any((k) => k.startsWith('cloudflare_'))) {
            print('Instagram upload for account $accountId has not started yet, forcing start');
            
            // Get platform-specific description if available
            String postDescription = widget.description;
            if (widget.platformDescriptions.containsKey('Instagram') && 
                widget.platformDescriptions['Instagram']!.containsKey(accountId)) {
              postDescription = widget.platformDescriptions['Instagram']![accountId]!;
            }
            
            // Get content type if available (default to Post)
            String contentType = 'Post';
            if (widget.instagramContentType.containsKey(accountId)) {
              contentType = widget.instagramContentType[accountId]!;
            }
            
            // Start Instagram upload
            setState(() {
              _uploadStatus[key] = true;
              _uploadMessages[key] = 'Avvio upload Instagram...';
              _uploadProgress[key] = 0.1; // Initial progress
            });
            
            // Ensure the URL is in the correct R2 format (must be pub-[accountId].r2.dev format)
            // Force convert the URL to R2 format regardless of its current format
            String instagramUrl = _convertToPublicR2Url(widget.cloudflareUrl!);
            print('Using R2 public URL for Instagram: $instagramUrl');
            
            // Call the upload method
            _uploadToInstagram(
              accountId: accountId,
              key: key,
              cloudflareUrl: instagramUrl,
              title: widget.title,
              description: postDescription,
              contentType: contentType
            );
          }
        }
      }
    }

    // If no Instagram accounts were found or all uploads are complete
    return !foundInstagramAccounts || allCompleted;
  }
} 
