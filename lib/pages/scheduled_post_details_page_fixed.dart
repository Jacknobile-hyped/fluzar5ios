import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../services/youtube_service.dart';

class ScheduledPostDetailsPage extends StatefulWidget {
  final Map<String, dynamic> post;

  const ScheduledPostDetailsPage({
    super.key,
    required this.post,
  });

  @override
  State<ScheduledPostDetailsPage> createState() => _ScheduledPostDetailsPageState();
}

class _ScheduledPostDetailsPageState extends State<ScheduledPostDetailsPage> {
  bool _isLoading = false;
  bool _isDeleting = false;
  Map<String, dynamic>? _youtubeStatus;
  final YouTubeService _youtubeService = YouTubeService();
  
  // Gestione video player
  VideoPlayerController? _videoPlayerController;
  bool _isVideoInitialized = false;
  bool _isPlaying = false;
  bool _isDisposed = false;
  bool _showControls = false;
  bool _isFullScreen = false;
  Duration _currentPosition = Duration.zero;
  Duration _videoDuration = Duration.zero;
  Timer? _positionUpdateTimer;
  Timer? _autoplayTimer;
  Timer? _countdownTimer;

  final Map<String, String> _platformLogos = {
    'twitter': 'assets/loghi/logo_twitter.png',
    'youtube': 'assets/loghi/logo_yt.png',
    'tiktok': 'assets/loghi/logo_tiktok.png',
    'instagram': 'assets/loghi/logo_insta.png',
    'facebook': 'assets/loghi/logo_facebook.png',
    'threads': 'assets/loghi/threads_logo.png',
  };

  // Map to hold the remaining time values that gets updated by the timer
  Map<String, int> _timeRemaining = {
    'days': 0,
    'hours': 0,
    'minutes': 0,
    'seconds': 0,
  };
  
  // Flag to indicate if the scheduled time is in the past
  bool _isScheduledInPast = false;
  
  // Flag to indicate if we're currently calculating time
  bool _isCalculatingTime = true;

  @override
  void initState() {
    super.initState();
    // Se il post è per YouTube, verifica lo stato
    if (widget.post['platforms'] != null && 
        (widget.post['platforms'] as List<dynamic>).contains('YouTube') &&
        widget.post['youtube_video_id'] != null) {
      _checkYouTubeStatus();
    }
    
    // Inizializza il video player se c'è un video
    if (!_isImage && widget.post['video_path'] != null) {
      _initializePlayer();
      _startPositionUpdateTimer();
    }
    
    // Mostra i controlli inizialmente
    setState(() {
      _showControls = true;
    });
    
    // Initialize the countdown
    _calculateTimeRemaining();
    _startCountdownTimer();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _autoplayTimer?.cancel();
    _positionUpdateTimer?.cancel();
    _countdownTimer?.cancel();
    if (_videoPlayerController != null) {
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.dispose();
    }
    super.dispose();
  }

  // Check if the content is an image
  bool get _isImage => widget.post['is_image'] == true;

  Future<void> _checkYouTubeStatus() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final videoId = widget.post['youtube_video_id'] as String;
      final status = await _youtubeService.checkVideoStatus(videoId);
      
      if (mounted) {
        setState(() {
          _youtubeStatus = status;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Errore nel controllo dello stato di YouTube: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deletePost() async {
    if (_isDeleting) return;
    
    setState(() {
      _isDeleting = true;
    });
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      final postId = widget.post['id'] as String;
      final youtubeVideoId = widget.post['youtube_video_id'] as String?;
      final platforms = widget.post['platforms'] as List<dynamic>?;
      final hasYouTube = platforms != null && platforms.contains('YouTube');

      bool hasYouTubeError = false;
      String? youtubeErrorMessage;
      
      // Se è un video YouTube, elimina anche da YouTube
      if (hasYouTube && youtubeVideoId != null) {
        // Mostriamo un messaggio di caricamento
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Eliminazione del video YouTube in corso...'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        
        try {
          final deleted = await _youtubeService.deleteYouTubeVideo(youtubeVideoId);
          
          if (!deleted) {
            hasYouTubeError = true;
            youtubeErrorMessage = 'Il post è stato eliminato ma potrebbero esserci problemi con l\'eliminazione su YouTube';
          }
        } catch (ytError) {
          print('Errore durante l\'eliminazione del video YouTube: $ytError');
          hasYouTubeError = true;
          
          // Verifica se l'errore è dovuto a troppe richieste
          if (ytError.toString().contains('Too many attempts') || 
              ytError.toString().contains('resource-exhausted')) {
            youtubeErrorMessage = 'Troppe richieste a YouTube. Il post verrà eliminato, ma potrebbe essere necessario eliminare manualmente il video su YouTube.';
          } else {
            youtubeErrorMessage = 'Il post è stato eliminato ma potrebbero esserci problemi con l\'eliminazione su YouTube. Verifica manualmente.';
          }
        }
      }
      
      // Elimina il post dal database
      await FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .child(postId)
          .remove();
      
      if (mounted) {
        if (hasYouTubeError && youtubeErrorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(youtubeErrorMessage),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
          
          // Diamo all'utente il tempo di leggere il messaggio prima di tornare indietro
          await Future.delayed(Duration(seconds: 2));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Post eliminato con successo'),
              backgroundColor: Colors.green,
            ),
          );
        }
        
        // Torna alla pagina precedente
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        
        String errorMessage = 'Errore durante l\'eliminazione: $e';
        
        // Rendi il messaggio più leggibile
        if (e.toString().contains('Too many attempts')) {
          errorMessage = 'Troppe richieste. Riprova più tardi.';
        } else if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permesso negato. Potresti dover riautenticare il tuo account YouTube.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
  
  Future<void> _showDeleteConfirmation() async {
    final theme = Theme.of(context);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                'Elimina Post',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sei sicuro di voler eliminare questo post programmato?',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              if (widget.post['youtube_video_id'] != null)
                Text(
                  'Il video verrà eliminato anche da YouTube.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Annulla',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text('Elimina'),
              onPressed: () {
                Navigator.of(context).pop();
                _deletePost();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePostForAccount(String platform, Map<String, dynamic> accountMap) async {
    if (_isDeleting) return;
    
    setState(() {
      _isDeleting = true;
    });
    
    try {
      // Prima di tutto, mostra un messaggio di caricamento generale
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rimozione in corso...'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blue,
          ),
        );
      }
      
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');
      
      final postId = widget.post['id'] as String;
      final youtubeVideoId = widget.post['youtube_video_id'] as String?;
      final isYouTubeAccount = platform.toLowerCase() == 'youtube' && youtubeVideoId != null;
      
      // Per YouTube, elimina il video da YouTube
      bool hasYouTubeError = false;
      String? youtubeErrorMessage;
      
      if (isYouTubeAccount) {
        // Mostriamo un messaggio specifico per l'eliminazione di YouTube
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Eliminazione del video da YouTube in corso...'),
              duration: Duration(seconds: 4),
              backgroundColor: Colors.orange,
            ),
          );
        }
        
        // Utilizzo diretto di YouTubeService come in scheduled_posts_page.dart
        try {
          final youtubeService = YouTubeService();
          print('Tentativo di eliminazione del video YouTube: $youtubeVideoId');
          final deleted = await youtubeService.deleteYouTubeVideo(youtubeVideoId!);
          
          if (!deleted) {
            hasYouTubeError = true;
            youtubeErrorMessage = 'Il post è stato rimosso dall\'account ma potrebbero esserci problemi con l\'eliminazione su YouTube';
            print('Errore durante l\'eliminazione del video YouTube: video non eliminato');
          } else {
            print('Video YouTube eliminato con successo: $youtubeVideoId');
          }
        } catch (ytError) {
          print('Errore durante l\'eliminazione del video YouTube: $ytError');
          hasYouTubeError = true;
          
          // Verifica se l'errore è dovuto a troppe richieste
          if (ytError.toString().contains('Too many attempts') || 
              ytError.toString().contains('resource-exhausted')) {
            youtubeErrorMessage = 'Troppe richieste a YouTube. Il post verrà rimosso dall\'account, ma potrebbe essere necessario eliminare manualmente il video su YouTube.';
          } else {
            youtubeErrorMessage = 'Il post è stato rimosso dall\'account ma potrebbero esserci problemi con l\'eliminazione su YouTube. Verifica manualmente.';
          }
        }

        // Breve pausa per assicurarsi che il messaggio di caricamento sia visibile
        await Future.delayed(const Duration(milliseconds: 1000));
      }
      
      // Aggiorna il post nel database rimuovendo l'account selezionato
      final postRef = FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .child(postId);
      
      // Ottieni l'attuale post
      final postSnapshot = await postRef.get();
      if (!postSnapshot.exists) {
        throw Exception('Il post non esiste più');
      }
      
      final postData = postSnapshot.value as Map<dynamic, dynamic>;
      final accounts = Map<String, dynamic>.from(postData['accounts'] as Map<dynamic, dynamic>? ?? {});
      
      // Correggiamo il tipo di updatedPlatforms
      List<String> updatedPlatforms = [];
      if (postData['platforms'] != null) {
        // Converte ogni elemento esplicitamente in String
        final originalPlatforms = postData['platforms'] as List<dynamic>;
        updatedPlatforms = originalPlatforms.map((p) => p.toString()).toList();
      }
      
      // Rimuovi l'account dalla lista per questa piattaforma
      if (accounts.containsKey(platform)) {
        final platformAccounts = List<dynamic>.from(accounts[platform] as List<dynamic>? ?? []);
        
        // Rimuovi l'account che corrisponde all'ID o username
        platformAccounts.removeWhere((accItem) {
          if (accItem is! Map) return false;
          final acc = Map<String, dynamic>.from(accItem as Map<dynamic, dynamic>);
          return acc['id'] == accountMap['id'] || acc['username'] == accountMap['username'];
        });
        
        if (platformAccounts.isEmpty) {
          // Se non ci sono più account per questa piattaforma, rimuovi la piattaforma
          accounts.remove(platform);
          updatedPlatforms.remove(platform);
        } else {
          // Altrimenti aggiorna solo gli account per questa piattaforma
          accounts[platform] = platformAccounts;
        }
      }
      
      // Per YouTube, eliminiamo sempre il post completo quando viene rimosso
      if (isYouTubeAccount) {
        await postRef.remove();
        
        if (mounted) {
          if (hasYouTubeError && youtubeErrorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(youtubeErrorMessage),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Video eliminato con successo da YouTube'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
          
          // Torna alla pagina precedente
          Navigator.pop(context);
        }
      } else if (updatedPlatforms.isEmpty) {
        // Se non ci sono più piattaforme, elimina completamente il post
        await postRef.remove();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Post rimosso completamente'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
          
          // Torna alla pagina precedente
          Navigator.pop(context);
        }
      } else {
        // Altrimenti aggiorna solo le informazioni nel database
        await postRef.update({
          'accounts': accounts,
          'platforms': updatedPlatforms
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account ${accountMap['username']} rimosso dal post'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Aggiorna la visualizzazione
          setState(() {
            // Aggiorna il post locale, assicurandoci che i tipi siano corretti
            (widget.post as Map<String, dynamic>)['accounts'] = accounts;
            (widget.post as Map<String, dynamic>)['platforms'] = updatedPlatforms;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
        
        String errorMessage = 'Errore durante l\'eliminazione: $e';
        
        // Rendi il messaggio più leggibile
        if (e.toString().contains('Too many attempts')) {
          errorMessage = 'Troppe richieste. Riprova più tardi.';
        } else if (e.toString().contains('permission-denied')) {
          errorMessage = 'Permesso negato. Potresti dover riautenticare il tuo account.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }
  
  Future<void> _showDeleteAccountConfirmation(String platform, Map<String, dynamic> account) async {
    final theme = Theme.of(context);
    final isYouTubeAccount = platform.toLowerCase() == 'youtube' && widget.post['youtube_video_id'] != null;
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text(
                isYouTubeAccount ? 'Attenzione' : 'Rimuovi Account',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isYouTubeAccount
                    ? 'Rimuovendo questo account, il video sarà definitivamente eliminato da YouTube!'
                    : 'Sei sicuro di voler rimuovere questo account dalla programmazione?',
                style: TextStyle(
                  fontSize: 16,
                  color: theme.colorScheme.onSurface,
                  fontWeight: isYouTubeAccount ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: account['profile_image_url']?.isNotEmpty == true
                        ? NetworkImage(account['profile_image_url']!)
                        : null,
                    backgroundColor: theme.colorScheme.surfaceVariant,
                    radius: 16,
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
                  SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account['display_name'] ?? account['username'] ?? '',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '@${account['username']}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (isYouTubeAccount) ...[
                SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete_forever,
                        color: Colors.red,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Il video YouTube verrà eliminato definitivamente!',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: Text(
                'Annulla',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(isYouTubeAccount ? 'Elimina Video' : 'Rimuovi'),
              onPressed: () {
                Navigator.of(context).pop();
                _deletePostForAccount(platform, account);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
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
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                  size: 22,
                ),
                onPressed: () => Navigator.pop(context),
              ),
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
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.red[400],
                  size: 22,
                ),
                onPressed: _isDeleting ? null : _showDeleteConfirmation,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer(VideoPlayerController controller) {
    // Check if the video is horizontal (aspect ratio > 1)
    final bool isHorizontalVideo = controller.value.aspectRatio > 1.0;
    
    if (isHorizontalVideo) {
      // For horizontal videos, show them full screen with FittedBox
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Black background to avoid empty spaces
        child: FittedBox(
          fit: BoxFit.contain, // Scale to preserve aspect ratio
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );
    } else {
      // For vertical videos, maintain the standard AspectRatio
      return Center(
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
      );
    }
  }

  Color _getPlatformColor(String platform) {
    switch (platform.toString().toLowerCase()) {
      case 'twitter':
        return Colors.blue;
      case 'youtube':
        return Colors.red;
      case 'tiktok':
        return Colors.black;
      case 'instagram':
        return Colors.purple;
      case 'facebook':
        return Colors.blue;
      case 'threads':
        return Colors.black;
      default:
        return Colors.grey;
    }
  }

  Color _getPlatformLightColor(String platform) {
    switch (platform.toString().toLowerCase()) {
      case 'twitter':
        return Colors.blue.withOpacity(0.08);
      case 'youtube':
        return Colors.red.withOpacity(0.08);
      case 'tiktok':
        return Colors.black.withOpacity(0.05);
      case 'instagram':
        return Colors.purple.withOpacity(0.08);
      case 'facebook':
        return Colors.blue.withOpacity(0.08);
      case 'threads':
        return Colors.black.withOpacity(0.05);
      default:
        return Colors.grey.withOpacity(0.08);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaWidth = MediaQuery.of(context).size.width;
    final mediaHeight = MediaQuery.of(context).size.height;
    
    // Adjust video container size based on fullscreen mode
    final videoContainerHeight = _isFullScreen ? mediaHeight : 260.0;
    
    // Background color for video container
    final videoBackgroundColor = Color(0xFF1F2937);
    
    // Get formatted scheduled date time
    final scheduledTime = widget.post['scheduled_time'] as int? ?? widget.post['scheduledTime'] as int?;
    final dateTime = scheduledTime != null
        ? DateTime.fromMillisecondsSinceEpoch(scheduledTime)
        : null;
    final formattedDate = dateTime != null
        ? DateFormat('dd/MM/yyyy HH:mm').format(dateTime)
        : 'Date not set';
    
    // Get platforms and accounts
    final platforms = (widget.post['platforms'] as List<dynamic>?)?.cast<String>() ?? [];
    final accounts = Map<String, dynamic>.from(widget.post['accounts'] as Map<dynamic, dynamic>? ?? {});
    
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.grey[100],
      appBar: null,
      body: SafeArea(
        // Disable SafeArea when in fullscreen
        bottom: !_isFullScreen,
        top: !_isFullScreen,
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _isFullScreen
                // Simplified layout for fullscreen mode
                ? GestureDetector(
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
                    },
                    child: Container(
                      width: mediaWidth,
                      height: mediaHeight,
                      color: videoBackgroundColor,
                      child: Stack(
                        children: [
                          // Show video if initialized
                          if (_isVideoInitialized && _videoPlayerController != null)
                            Center(
                              child: _buildVideoPlayer(_videoPlayerController!),
                            ),
                          
                          // Video controls in fullscreen mode
                          AnimatedOpacity(
                            opacity: _showControls ? 1.0 : 0.0,
                            duration: Duration(milliseconds: 300),
                            child: Stack(
                              children: [
                                // Semi-transparent overlay
                                Container(
                                  width: mediaWidth,
                                  height: mediaHeight,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withOpacity(0.5),
                                        Colors.transparent,
                                        Colors.transparent,
                                        Colors.black.withOpacity(0.5),
                                      ],
                                      stops: [0.0, 0.2, 0.8, 1.0],
                                    ),
                                  ),
                                ),
                                
                                // Exit fullscreen button
                                Positioned(
                                  top: 60,
                                  left: 20,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.6),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: IconButton(
                                      icon: Icon(Icons.fullscreen_exit, color: Colors.white),
                                      onPressed: _toggleFullScreen,
                                    ),
                                  ),
                                ),
                                
                                // Play/pause button in center
                                Center(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.5),
                                      shape: BoxShape.circle,
                                    ),
                                    child: IconButton(
                                      icon: Icon(
                                        _videoPlayerController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                        color: Colors.white,
                                        size: 48,
                                      ),
                                      padding: EdgeInsets.all(12),
                                      onPressed: _toggleVideoPlayback,
                                    ),
                                  ),
                                ),
                                
                                // Progress bar
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.bottomCenter,
                                        end: Alignment.topCenter,
                                        colors: [
                                          Colors.black.withOpacity(0.7),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              _formatDuration(_currentPosition),
                                              style: TextStyle(color: Colors.white, fontSize: 14),
                                            ),
                                            Text(
                                              _formatDuration(_videoDuration),
                                              style: TextStyle(color: Colors.white, fontSize: 14),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        SliderTheme(
                                          data: SliderThemeData(
                                            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
                                            trackHeight: 4,
                                            activeTrackColor: theme.colorScheme.primary,
                                            inactiveTrackColor: Colors.white.withOpacity(0.3),
                                            thumbColor: Colors.white,
                                          ),
                                          child: Slider(
                                            value: _currentPosition.inSeconds.toDouble(),
                                            min: 0.0,
                                            max: _videoDuration.inSeconds.toDouble() > 0 
                                                ? _videoDuration.inSeconds.toDouble() 
                                                : 1.0,
                                            onChanged: (value) {
                                              _videoPlayerController?.seekTo(Duration(seconds: value.toInt()));
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                // Normal layout for non-fullscreen mode
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Show header when not in fullscreen
                      if (!_isFullScreen) _buildHeader(),
                      
                      // Video container with improved design
                      GestureDetector(
                        onTap: () {
                          if (!_isImage && (_videoPlayerController == null || !_isVideoInitialized)) {
                            _toggleVideoPlayback();
                          } else if (!_isImage && _isVideoInitialized) {
                            setState(() {
                              _showControls = !_showControls;
                            });
                          }
                        },
                        child: Container(
                          width: mediaWidth,
                          height: videoContainerHeight,
                          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: videoBackgroundColor,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.25),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                                spreadRadius: 1,
                              ),
                            ],
                            border: Border.all(
                              color: Colors.black.withOpacity(0.1),
                              width: 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            children: [
                              // If it's an image, display it directly
                              if (_isImage)
                                Center(
                                  child: widget.post['video_path'] != null && 
                                      widget.post['video_path'].toString().isNotEmpty
                                      ? _buildImagePreview(widget.post['video_path'])
                                      : _loadCloudflareImage(), // Fallback to Cloudflare directly if no path
                                )
                              // Show video player if initialized and it's not an image
                              else if (!_isImage && _isVideoInitialized && _videoPlayerController != null)
                                Stack(
                                  fit: StackFit.expand, // Ensure stack expands to fill the space
                                  children: [
                                    // Video Player
                                    GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _showControls = !_showControls; // Toggle controls visibility on tap
                                        });
                                      },
                                      child: _buildVideoPlayer(_videoPlayerController!),
                                    ),
                                    
                                    // Video Controls
                                    AnimatedOpacity(
                                      opacity: _showControls ? 1.0 : 0.0,
                                      duration: Duration(milliseconds: 300),
                                      child: LayoutBuilder(
                                        builder: (context, constraints) {
                                          // Adapt the interface based on available space
                                          final isSmallScreen = constraints.maxHeight < 300;
                                          
                                          return Stack(
                                            children: [
                                              // Semi-transparent overlay
                                              Container(
                                                width: constraints.maxWidth,
                                                height: constraints.maxHeight,
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topCenter,
                                                    end: Alignment.bottomCenter,
                                                    colors: [
                                                      Colors.black.withOpacity(0.4),
                                                      Colors.transparent,
                                                      Colors.transparent,
                                                      Colors.black.withOpacity(0.5),
                                                    ],
                                                    stops: [0.0, 0.2, 0.8, 1.0],
                                                  ),
                                                ),
                                              ),
                                              
                                              // Play/Pause button in center
                                              Center(
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.3),
                                                    shape: BoxShape.circle,
                                                    border: Border.all(
                                                      color: Colors.white.withOpacity(0.5),
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: IconButton(
                                                    icon: Icon(
                                                      _videoPlayerController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                                      color: Colors.white,
                                                      size: isSmallScreen ? 36 : 44,
                                                    ),
                                                    padding: EdgeInsets.all(isSmallScreen ? 8 : 12),
                                                    onPressed: () {
                                                      // This call is prioritized and should always work
                                                      _toggleVideoPlayback();
                                                    },
                                                  ),
                                                ),
                                              ),
                                              
                                              // Top controls (fullscreen)
                                              Positioned(
                                                top: 12,
                                                right: 12,
                                                child: Container(
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.3),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(
                                                      color: Colors.white.withOpacity(0.3),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: IconButton(
                                                    icon: Icon(
                                                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                                      color: Colors.white,
                                                      size: 24,
                                                    ),
                                                    padding: EdgeInsets.all(isSmallScreen ? 4 : 6),
                                                    constraints: BoxConstraints(minWidth: 36, minHeight: 36),
                                                    onPressed: _toggleFullScreen,
                                                  ),
                                                ),
                                              ),
                                              
                                              // Bottom controls (slider and time)
                                              Positioned(
                                                left: 0,
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  padding: EdgeInsets.only(top: 20, bottom: 8),
                                                  decoration: BoxDecoration(
                                                    gradient: LinearGradient(
                                                      begin: Alignment.bottomCenter,
                                                      end: Alignment.topCenter,
                                                      colors: [
                                                        Colors.black.withOpacity(0.7),
                                                        Colors.black.withOpacity(0.3),
                                                        Colors.transparent,
                                                      ],
                                                      stops: [0.0, 0.6, 1.0],
                                                    ),
                                                  ),
                                                  child: Column(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      // Time indicators
                                                      Padding(
                                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                                        child: Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            Text(
                                                              _formatDuration(_currentPosition),
                                                              style: TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.bold,
                                                                letterSpacing: 0.5,
                                                              ),
                                                            ),
                                                            Text(
                                                              _formatDuration(_videoDuration),
                                                              style: TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.bold,
                                                                letterSpacing: 0.5,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      
                                                      // Progress bar
                                                      SliderTheme(
                                                        data: SliderThemeData(
                                                          thumbShape: RoundSliderThumbShape(enabledThumbRadius: isSmallScreen ? 4 : 6),
                                                          trackHeight: isSmallScreen ? 2 : 3,
                                                          trackShape: RoundedRectSliderTrackShape(),
                                                          activeTrackColor: theme.colorScheme.primary,
                                                          inactiveTrackColor: Colors.white.withOpacity(0.3),
                                                          thumbColor: Colors.white,
                                                          overlayColor: theme.colorScheme.primary.withOpacity(0.3),
                                                        ),
                                                        child: Slider(
                                                          value: _currentPosition.inSeconds.toDouble(),
                                                          min: 0.0,
                                                          max: _videoDuration.inSeconds.toDouble() > 0 
                                                              ? _videoDuration.inSeconds.toDouble() 
                                                              : 1.0,
                                                          onChanged: (value) {
                                                            _videoPlayerController?.seekTo(Duration(seconds: value.toInt()));
                                                            setState(() {
                                                              _showControls = true;
                                                            });
                                                          },
                                                        ),
                                                      ),
                                                      SizedBox(height: 2),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                )
                              // Otherwise show thumbnail from Cloudflare if available
                              else if (widget.post['thumbnail_cloudflare_url'] != null &&
                                      widget.post['thumbnail_cloudflare_url'].toString().isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: Colors.black,
                                  child: Center(
                                    child: Image.network(
                                      widget.post['thumbnail_cloudflare_url'],
                                      fit: BoxFit.contain,
                                      loadingBuilder: (context, child, loadingProgress) {
                                        if (loadingProgress == null) return child;
                                        return Center(
                                          child: CircularProgressIndicator(
                                            value: loadingProgress.expectedTotalBytes != null
                                                ? loadingProgress.cumulativeBytesLoaded / 
                                                    loadingProgress.expectedTotalBytes!
                                                : null,
                                          ),
                                        );
                                      },
                                      errorBuilder: (context, url, error) => Center(
                                        child: Icon(
                                          _isImage ? Icons.image_not_supported : Icons.video_library,
                                          color: Colors.grey[400],
                                          size: 48,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              // Or show local thumbnail if available
                              else if (widget.post['thumbnail_path'] != null &&
                                      widget.post['thumbnail_path'].toString().isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  height: double.infinity,
                                  color: Colors.black,
                                  child: Center(
                                    child: Image.file(
                                      File(widget.post['thumbnail_path']),
                                      fit: BoxFit.contain,
                                      errorBuilder: (context, error, stackTrace) => Center(
                                        child: Icon(
                                          _isImage ? Icons.image_not_supported : Icons.video_library,
                                          color: Colors.grey[400],
                                          size: 48,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              // Fallback to a placeholder with play button
                              else if (!_isImage && !_isVideoInitialized)
                                Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    // Dark background
                                    Container(
                                      color: videoBackgroundColor,
                                      width: double.infinity,
                                      height: double.infinity,
                                    ),
                                    // Loading indicator or play button
                                    _videoPlayerController != null && _videoPlayerController!.value.isInitialized == false
                                      ? Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircularProgressIndicator(
                                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                              strokeWidth: 3,
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'Loading video...',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        )
                                      : GestureDetector(
                                          onTap: () {
                                            print("Tap on video placeholder");
                                            _toggleVideoPlayback();
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.all(24),
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(0.5),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white.withOpacity(0.3),
                                                width: 2,
                                              ),
                                            ),
                                            child: Icon(
                                              Icons.play_arrow,
                                              color: Colors.white,
                                              size: 48,
                                            ),
                                          ),
                                        ),
                                  ],
                                ),
                                
                              // Overlay with scheduled time information - improved styling
                              Positioned(
                                top: 16,
                                left: 16,
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.75),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: theme.colorScheme.primary.withOpacity(0.3),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.25),
                                        blurRadius: 8,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.calendar_today,
                                        color: Colors.white,
                                        size: 16,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        formattedDate,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Content below video (when not in fullscreen)
                      if (!_isFullScreen) 
                        Expanded(
                          child: Container(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                const SizedBox(height: 16),
                                
                                // Container for accounts
                                Expanded(
                                  child: Container(
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(24),
                                        topRight: Radius.circular(24),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 10,
                                          offset: Offset(0, -2),
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: SingleChildScrollView(
                                      physics: AlwaysScrollableScrollPhysics(),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Post details section
                                          Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: _buildAccountsList(accounts, theme),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
        ),
      ),
    );
  }

  void _initializePlayer() {
    print("Initialize player called");
    
    // Skip video initialization for images
    if (_isImage) {
      print('Content is an image, skipping video player initialization');
      return;
    }
    
    final videoPath = widget.post['video_path'] as String?;
    if (videoPath == null || videoPath.isEmpty) {
      print("Video path is null or empty");
      return;
    }
    
    // Check if the file exists
    final videoFile = File(videoPath);
    if (!videoFile.existsSync()) {
      print('Video file not found: $videoPath, trying cloudflare_url');
      
      // If not local, check if we have a Cloudflare URL
      final cloudflareUrl = widget.post['cloudflare_url'] as String?;
      if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
        print('Using Cloudflare URL for preview: $cloudflareUrl');
        
        setState(() {
          _isVideoInitialized = false;
        });
        
        // Show a message to the user
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Local video is no longer available. Only preview will be shown.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      } else {
        print('No video resource available (neither local nor remote)');
        return;
      }
    }
    
    // Clean up any existing controller first
    if (_videoPlayerController != null) {
      print("Disposing existing controller");
      _videoPlayerController!.removeListener(_onVideoPositionChanged);
      _videoPlayerController!.dispose();
    }
    
    setState(() {
      _isVideoInitialized = false;
      _showControls = true; // Show controls when initializing
      _isPlaying = false; // Reset playing state
    });
    
    try {
      print("Creating new video controller");
      // Initialize the controller with the local video file
      _videoPlayerController = VideoPlayerController.file(videoFile);
      
      // Add listener for player events
      _videoPlayerController!.addListener(_onVideoPositionChanged);
      
      _videoPlayerController!.initialize().then((_) {
        print("Video controller initialized successfully");
        if (!mounted || _isDisposed) return;
        
        // Determine if the video is horizontal (aspect ratio > 1)
        final bool isHorizontalVideo = _videoPlayerController!.value.aspectRatio > 1.0;
        
        print("Video aspect ratio: ${_videoPlayerController!.value.aspectRatio}");
        print("Is horizontal video: $isHorizontalVideo");
        
        setState(() {
          _isVideoInitialized = true;
          _videoDuration = _videoPlayerController!.value.duration;
          _currentPosition = Duration.zero;
          _showControls = true; // Keep controls visible
        });
        
        // Do not autoplay the video, but make it visible to the user
        
      }).catchError((error) {
        print('Error initializing video player: $error');
        
        // Handle errors properly
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to play video: ${error.toString().substring(0, min(error.toString().length, 50))}...'),
            duration: Duration(seconds: 3),
          ),
        );
      });
    } catch (e) {
      print('Exception during video controller creation: $e');
      
      setState(() {
        _isVideoInitialized = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error creating video player: ${e.toString().substring(0, min(e.toString().length, 50))}...'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }
  
  // Handle video player events
  void _onVideoPositionChanged() {
    if (_videoPlayerController != null && 
        _videoPlayerController!.value.isInitialized && 
        mounted && 
        !_isDisposed) {
      final isPlayingNow = _videoPlayerController!.value.isPlaying;
      final isAtEnd = _videoPlayerController!.value.position >= _videoPlayerController!.value.duration - Duration(milliseconds: 300);
      
      setState(() {
        _currentPosition = _videoPlayerController!.value.position;
        
        // Update isPlaying based on actual player state
        if (_isPlaying != isPlayingNow) {
          _isPlaying = isPlayingNow;
        }
      });
      
      // Show controls and update playing state when video ends
      if (isAtEnd && _isPlaying) {
        setState(() {
          _isPlaying = false;
          _showControls = true;
        });
      }
    }
  }
  
  void _toggleVideoPlayback() {
    print("Toggle video playback called");
    
    if (_videoPlayerController == null) {
      print("Controller is null, initializing");
      _initializePlayer();
      return;
    }
    
    if (!_videoPlayerController!.value.isInitialized) {
      print("Controller not initialized");
      return;
    }
    
    if (_videoPlayerController!.value.isPlaying) {
      print("Pausing video");
      _videoPlayerController!.pause();
      _autoplayTimer?.cancel();
      setState(() {
        _isPlaying = false;
        _showControls = true; // Show controls when paused
      });
    } else {
      print("Playing video");
      // Retry play if there's an error or player is at end
      if (_videoPlayerController!.value.position >= _videoPlayerController!.value.duration) {
        // Se il video è finito, riavvialo dall'inizio
        _videoPlayerController!.seekTo(Duration.zero);
      }
      
      _videoPlayerController!.play().then((_) {
        // Aggiorna lo stato solo se il play è riuscito
        if (mounted && !_isDisposed) {
          print("Play succeeded");
          setState(() {
            _isPlaying = true;
          });
        }
      }).catchError((error) {
        print('Error playing video: $error');
        // Mostra messaggio d'errore
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore nella riproduzione del video. Riprova.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
      
      setState(() {
        _isPlaying = true; // Aggiorniamo immediatamente per feedback UI
        // Hide controls after a delay
        Future.delayed(Duration(seconds: 3), () {
          if (mounted && !_isDisposed && _isPlaying) {
            setState(() {
              _showControls = false;
            });
          }
        });
      });
      
      // Auto-stop after 30 seconds to save resources
      _autoplayTimer?.cancel();
      _autoplayTimer = Timer(const Duration(seconds: 30), () {
        if (_videoPlayerController != null && !_isDisposed) {
          _videoPlayerController!.pause();
          setState(() {
            _isPlaying = false;
            _showControls = true; // Show controls when auto-paused
          });
        }
      });
    }
  }
  
  // Start a timer to update the video position periodically
  void _startPositionUpdateTimer() {
    _positionUpdateTimer?.cancel();
    _positionUpdateTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_videoPlayerController != null && 
          _videoPlayerController!.value.isInitialized && 
          mounted && 
          !_isDisposed) {
        setState(() {
          _currentPosition = _videoPlayerController!.value.position;
          _videoDuration = _videoPlayerController!.value.duration;
        });
      }
    });
  }
  
  // Function to toggle fullscreen mode
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
      // Always show controls when toggling fullscreen
      _showControls = true;
      
      // Hide controls after a delay
      if (_isFullScreen && _isPlaying) {
        Future.delayed(Duration(seconds: 3), () {
          if (mounted && !_isDisposed && _isPlaying) {
            setState(() {
              _showControls = false;
            });
          }
        });
      }
    });
  }
  
  // Helper functions for formatting time
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildAccountsList(Map<String, dynamic> accounts, ThemeData theme) {
    if (accounts.isEmpty) return const SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Countdown section
        Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                theme.colorScheme.primary.withOpacity(0.9),
                theme.colorScheme.primary,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withOpacity(0.3),
                blurRadius: 15,
                offset: Offset(0, 5),
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    child: Icon(
                      Icons.event,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Publication Date',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          _getFormattedScheduledDate(),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              Divider(
                color: Colors.white.withOpacity(0.2),
                height: 32,
                thickness: 1,
              ),
              
              // Countdown timer
              _isCalculatingTime
                  ? Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        strokeWidth: 2,
                      ),
                    )
                  : _isScheduledInPast
                      ? Container(
                          padding: EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'This post was scheduled for the past',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Time until publication',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildCountdownItem(theme, _timeRemaining['days']!, 'Days'),
                                _buildCountdownSeparator(),
                                _buildCountdownItem(theme, _timeRemaining['hours']!, 'Hours'),
                                _buildCountdownSeparator(),
                                _buildCountdownItem(theme, _timeRemaining['minutes']!, 'Min'),
                                _buildCountdownSeparator(),
                                _buildCountdownItem(theme, _timeRemaining['seconds']!, 'Sec'),
                              ],
                            ),
                          ],
                        ),
            ],
          ),
        ),

        // Platform accounts
        ...accounts.entries.map((entry) {
          final platform = entry.key;
          final platformAccounts = entry.value as List<dynamic>;
          
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 15,
                  offset: Offset(0, 5),
                ),
              ],
              border: Border.all(
                color: theme.colorScheme.surfaceVariant,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Platform header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _getPlatformLightColor(platform),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: _getPlatformColor(platform).withOpacity(0.2),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Image.asset(
                          _platformLogos[platform.toLowerCase()] ?? '',
                          width: 20,
                          height: 20,
                          fit: BoxFit.contain,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        platform.toUpperCase(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _getPlatformColor(platform),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Divider
                Divider(height: 1, thickness: 1, color: theme.colorScheme.surfaceVariant),
                
                // List of accounts for this platform
                ...platformAccounts.map((account) {
                  // Converti esplicitamente l'oggetto account in Map<String, dynamic>
                  final Map<String, dynamic> accountMap = Map<String, dynamic>.from(account as Map<dynamic, dynamic>);
                  
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundImage: accountMap['profile_image_url']?.isNotEmpty == true
                              ? NetworkImage(accountMap['profile_image_url']!)
                              : null,
                          backgroundColor: theme.colorScheme.surfaceVariant,
                          radius: 22,
                          child: accountMap['profile_image_url']?.isNotEmpty != true
                              ? Text(
                                  accountMap['username']?[0].toUpperCase() ?? '?',
                                  style: TextStyle(
                                    color: theme.colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                accountMap['display_name'] ?? accountMap['username'] ?? '',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '@${accountMap['username']}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Info button to show post details
                        IconButton(
                          icon: Icon(
                            Icons.info_outline,
                            color: _getPlatformColor(platform).withOpacity(0.7),
                            size: 20,
                          ),
                          tooltip: 'View post details',
                          onPressed: () => _showPostDetailsBottomSheet(context, accountMap, platform),
                        ),
                        // Delete button
                        IconButton(
                          icon: _isDeleting 
                            ? SizedBox(
                                height: 16, 
                                width: 16, 
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.red,
                                )
                              )
                            : Icon(
                                Icons.delete_outline,
                                color: Colors.red.withOpacity(0.7),
                                size: 20,
                              ),
                          tooltip: 'Rimuovi post per questo account',
                          onPressed: _isDeleting
                            ? null
                            : () => _showDeleteAccountConfirmation(platform, accountMap),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }
  
  // Build a countdown item widget
  Widget _buildCountdownItem(ThemeData theme, int value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value.toString().padLeft(2, '0'),
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                fontFamily: 'Roboto',
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.8),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Build separator for countdown timer
  Widget _buildCountdownSeparator() {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
          SizedBox(height: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoRow(ThemeData theme, String label, String value, IconData icon) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: theme.colorScheme.primary,
            size: 18,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScheduledTimeInfo(ThemeData theme) {
    final scheduledTime = widget.post['scheduled_time'] as int? ?? widget.post['scheduledTime'] as int?;
    if (scheduledTime != null) {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
      final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(dateTime);
      
      return _buildInfoRow(
        theme, 
        'Data Programmazione', 
        formattedDate,
        Icons.calendar_today,
      );
    }
    return const SizedBox.shrink();
  }

  // Start a countdown timer to update the time remaining
  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      if (mounted && !_isDisposed) {
        _calculateTimeRemaining();
      }
    });
  }
  
  // Calculate time remaining until scheduled post
  void _calculateTimeRemaining() {
    final scheduledTime = widget.post['scheduled_time'] as int? ?? widget.post['scheduledTime'] as int?;
    
    if (scheduledTime == null) {
      setState(() {
        _isCalculatingTime = false;
        _isScheduledInPast = true;
      });
      return;
    }
    
    final now = DateTime.now();
    final scheduledDateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
    final difference = scheduledDateTime.difference(now);
    
    // Check if scheduled time is in the past
    if (difference.isNegative) {
      setState(() {
        _isCalculatingTime = false;
        _isScheduledInPast = true;
        _timeRemaining = {
          'days': 0,
          'hours': 0,
          'minutes': 0,
          'seconds': 0,
        };
      });
      return;
    }
    
    // Calculate days, hours, minutes, and seconds
    final days = difference.inDays;
    final hours = difference.inHours.remainder(24);
    final minutes = difference.inMinutes.remainder(60);
    final seconds = difference.inSeconds.remainder(60);
    
    setState(() {
      _isCalculatingTime = false;
      _isScheduledInPast = false;
      _timeRemaining = {
        'days': days,
        'hours': hours,
        'minutes': minutes,
        'seconds': seconds,
      };
    });
  }
  
  // Show post details bottom sheet
  void _showPostDetailsBottomSheet(BuildContext context, Map<String, dynamic> account, String platform) {
    final theme = Theme.of(context);
    final platformColor = _getPlatformColor(platform);
    
    // Extract account and post data
    final username = account['username'] as String? ?? '';
    final displayName = account['display_name'] as String? ?? username;
    final profileImageUrl = account['profile_image_url'] as String?;
    
    // Get post title and description
    final title = widget.post['title'] as String? ?? '';
    final description = widget.post['description'] as String? ?? '';
    
    // Get scheduled time for better formatting
    final scheduledTime = widget.post['scheduled_time'] as int? ?? widget.post['scheduledTime'] as int?;
    final dateTime = scheduledTime != null
        ? DateTime.fromMillisecondsSinceEpoch(scheduledTime)
        : null;
    
    // Format date in different ways for better user understanding
    final formattedFullDate = dateTime != null
        ? DateFormat('EEEE, d MMMM yyyy').format(dateTime)
        : 'Date not set';
        
    final formattedTime = dateTime != null
        ? DateFormat('HH:mm').format(dateTime)
        : '--:--';
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 15,
              spreadRadius: 0,
              offset: Offset(0, -2),
            ),
          ],
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag indicator
            Center(
              child: Container(
                margin: EdgeInsets.only(top: 12, bottom: 16),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            
            // Header with platform
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.grey.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _getPlatformLightColor(platform),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: platformColor.withOpacity(0.1),
                          blurRadius: 4,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      _platformLogos[platform.toLowerCase()] ?? '',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                    ),
                  ),
                  SizedBox(width: 16),
                  Text(
                    '$platform Post Details',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: platformColor,
                      fontSize: 18,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
            ),
            
            // Publication date section - highlighted
            Container(
              margin: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.calendar_today,
                          color: theme.colorScheme.primary,
                          size: 18,
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Publication Date',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurface.withOpacity(0.6),
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              formattedFullDate,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: theme.colorScheme.primary.withOpacity(0.2),
                      ),
                      SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Time',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: theme.colorScheme.primary,
                              ),
                              SizedBox(width: 4),
                              Text(
                                formattedTime,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Profile information
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _getPlatformLightColor(platform),
                border: Border(
                  top: BorderSide(
                    color: Colors.grey.withOpacity(0.2),
                    width: 1,
                  ),
                  bottom: BorderSide(
                    color: Colors.grey.withOpacity(0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Profile image
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      backgroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                          ? NetworkImage(profileImageUrl)
                          : null,
                      child: profileImageUrl == null || profileImageUrl.isEmpty
                          ? Text(
                              username.isNotEmpty ? username[0].toUpperCase() : '',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: platformColor,
                              ),
                            )
                          : null,
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '@$username',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Post content
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty) ...[
                      Text(
                        'Title',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                    
                    Text(
                      'Description',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withOpacity(0.2),
                        ),
                      ),
                      child: Text(
                        description.isNotEmpty 
                            ? description 
                            : 'No description available',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Get formatted scheduled date
  String _getFormattedScheduledDate() {
    final scheduledTime = widget.post['scheduled_time'] as int? ?? widget.post['scheduledTime'] as int?;
    if (scheduledTime != null) {
      final dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
      
      // Get today and tomorrow dates for comparison
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(Duration(days: 1));
      final scheduledDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
      
      // If scheduled for today or tomorrow, show special format
      if (scheduledDate.isAtSameMomentAs(today)) {
        return 'Today at ${DateFormat('HH:mm').format(dateTime)}';
      } else if (scheduledDate.isAtSameMomentAs(tomorrow)) {
        return 'Tomorrow at ${DateFormat('HH:mm').format(dateTime)}';
      } else {
        // For other dates, show full date with day name
        return DateFormat('EEEE, d MMMM yyyy - HH:mm').format(dateTime);
      }
    }
    return 'Not scheduled';
  }

  Widget _buildImagePreview(String imagePath) {
    final imageFile = File(imagePath);
    
    // Check if local file exists
    if (imageFile.existsSync()) {
      return Image.file(
        imageFile,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) {
          print('Error loading local image: $error, trying Cloudflare URL');
          // If local file fails, try Cloudflare URL
          return _loadCloudflareImage();
        },
      );
    } 
    
    // Try Cloudflare URL if local file doesn't exist
    return _loadCloudflareImage();
  }

  // Helper method to load image from Cloudflare
  Widget _loadCloudflareImage() {
    // First try cloudflare_url
    final cloudflareUrl = widget.post['cloudflare_url'] as String?;
    if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
      print('Using Cloudflare URL for image: $cloudflareUrl');
      return Image.network(
        cloudflareUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, url, error) {
          // If cloudflare_url fails, try thumbnail_cloudflare_url
          final thumbnailUrl = widget.post['thumbnail_cloudflare_url'] as String?;
          if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
            return Image.network(
              thumbnailUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / 
                            loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, url, error) => Icon(
                Icons.image_not_supported,
                color: Colors.grey[400],
                size: 48,
              ),
            );
          }
          
          // If everything fails, show error icon
          return Icon(
            Icons.image_not_supported,
            color: Colors.grey[400],
            size: 48,
          );
        },
      );
    }
    
    // If no cloudflare_url, try thumbnail_cloudflare_url
    final thumbnailUrl = widget.post['thumbnail_cloudflare_url'] as String?;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      print('Using thumbnail Cloudflare URL for image: $thumbnailUrl');
      return Image.network(
        thumbnailUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded / 
                      loadingProgress.expectedTotalBytes!
                  : null,
            ),
          );
        },
        errorBuilder: (context, url, error) => Icon(
          Icons.image_not_supported,
          color: Colors.grey[400],
          size: 48,
        ),
      );
    }
    
    // Default fallback
    return Icon(
      Icons.image_not_supported,
      color: Colors.grey[400],
      size: 48,
    );
  }
} 