import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:lottie/lottie.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'dart:convert';
import '../services/swiftia_service.dart';
import 'dart:async';
import 'dart:ui'; // Added for ImageFilter

// Enum for videoclip steps
enum VideoclipStep { input, processing, shorts, render, complete }

class SwiftiaVideoclipPage extends StatefulWidget {
  const SwiftiaVideoclipPage({super.key});

  @override
  State<SwiftiaVideoclipPage> createState() => _SwiftiaVideoclipPageState();
}

class _SwiftiaVideoclipPageState extends State<SwiftiaVideoclipPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _youtubeUrlController = TextEditingController();
  final _jobNameController = TextEditingController();
  final _watermarkUrlController = TextEditingController();
  final _textColorController = TextEditingController();
  final _textSizeController = TextEditingController();
  
  String? _selectedPreset;
  String? _apiKey;
  bool _isLoading = false;
  bool _isJobCreated = false;
  bool _isJobCompleted = false;
  bool _isRendering = false;
  bool _isRenderCompleted = false;
  
  String? _currentJobId;
  String? _currentRenderId;
  List<Map<String, dynamic>> _generatedShorts = [];
  Map<String, dynamic>? _selectedShort;
  String? _renderedVideoUrl;
  double _renderProgress = 0.0;
  
  // Video duration
  String? _videoDuration;
  bool _isLoadingDuration = false;
  
  Timer? _statusCheckTimer;
  Timer? _renderProgressTimer;
  
  late AnimationController _loadingAnimationController;
  late AnimationController _successAnimationController;
  
  // Current step in the videoclip process
  VideoclipStep _currentStep = VideoclipStep.input;
  
  // PageController for horizontal swiping
  late PageController _pageController;
  
  // Page controller for shorts snapping and current index
  late PageController _shortsPageController;
  int _currentShortIndex = 0;
  
  // Video player controller for rendered video
  VideoPlayerController? _videoPlayerController;
  
  // Video controls state
  bool _showControls = false;
  bool _isFullScreen = false;
  bool _isVideoInitialized = false;
  Duration _currentPosition = Duration.zero;
  Duration _videoPlayerDuration = Duration.zero;
  
  // Firebase refs (for OneSignal player id lookup)
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  
  // Rendering customization options
  String _selectedRenderingPreset = 'DEFAULT'; // Will be synchronized with _selectedPreset
  bool _useCustomWatermark = false;
  String _watermarkUrl = '';
  String _watermarkPosition = 'bottom-right';
  double _watermarkOpacity = 0.9;
  int _maxWordsPerPage = 5;
  bool _useCustomTextStyle = false;
  String _textColor = '#ffffff';
  String _textSize = '24px';
  
  @override
  void initState() {
    super.initState();
    _loadingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    _successAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    
    // Initialize the PageController
    _pageController = PageController(initialPage: _currentStep.index);
    _shortsPageController = PageController(viewportFraction: 0.9);
    
    // Add listener to URL controller for real-time button state updates and duration calculation
    _youtubeUrlController.addListener(() {
      setState(() {});
      _checkAndGetVideoDuration();
    });
    
    // Add listeners to rendering customization controllers for real-time button state updates
    _watermarkUrlController.addListener(() {
      setState(() {});
    });
    _textColorController.addListener(() {
      setState(() {});
    });
    _textSizeController.addListener(() {
      setState(() {});
    });
    
    _loadApiKey();
    _setupInitialJobName();
    
    // Inizializza i controller con i valori di default
    _watermarkUrlController.text = _watermarkUrl;
    _textColorController.text = _textColor;
    _textSizeController.text = _textSize;
    
    // Controlla se c'è un processo in corso e riprendi il controllo
    _checkForOngoingProcess();
  }
  
  // Metodo per controllare se c'è un processo in corso
  Future<void> _checkForOngoingProcess() async {
    // Carica lo stato salvato
    await _loadProcessState();
    
    // Se c'è un job ID salvato, controlla il suo stato
    if (_currentJobId != null && _isJobCreated && !_isJobCompleted) {
      // Riprendi il controllo del processo
      _startStatusCheck();
      
      // Vai al step di processing
      setState(() {
        _currentStep = VideoclipStep.processing;
      });
      _pageController.animateToPage(
        _currentStep.index,
        duration: Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    }
  }
  
  // Metodo per salvare lo stato del processo
  Future<void> _saveProcessState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('swiftia_job_id', _currentJobId ?? '');
    await prefs.setBool('swiftia_job_created', _isJobCreated);
    await prefs.setBool('swiftia_job_completed', _isJobCompleted);
    await prefs.setString('swiftia_current_step', _currentStep.name);
  }
  
  // Metodo per caricare lo stato del processo
  Future<void> _loadProcessState() async {
    final prefs = await SharedPreferences.getInstance();
    final jobId = prefs.getString('swiftia_job_id');
    final jobCreated = prefs.getBool('swiftia_job_created') ?? false;
    final jobCompleted = prefs.getBool('swiftia_job_completed') ?? false;
    final stepName = prefs.getString('swiftia_current_step');
    
    if (jobId != null && jobId.isNotEmpty) {
      setState(() {
        _currentJobId = jobId;
        _isJobCreated = jobCreated;
        _isJobCompleted = jobCompleted;
        if (stepName != null) {
          _currentStep = VideoclipStep.values.firstWhere(
            (step) => step.name == stepName,
            orElse: () => VideoclipStep.input,
          );
        }
      });
    }
  }
  
  // Metodo per pulire lo stato salvato
  Future<void> _clearProcessState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('swiftia_job_id');
    await prefs.remove('swiftia_job_created');
    await prefs.remove('swiftia_job_completed');
    await prefs.remove('swiftia_current_step');
  }
  
  // Metodo per avviare il controllo dello stato
  void _startStatusCheck() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkJobStatus();
    });
  }
  
  @override
  void dispose() {
    _loadingAnimationController.dispose();
    _successAnimationController.dispose();
    
    // Non cancellare i timer se c'è un processo in corso
    // Questo permette al processo di continuare in background
    if (!_isJobCreated || _isJobCompleted) {
    _statusCheckTimer?.cancel();
    _renderProgressTimer?.cancel();
    }
    
    _youtubeUrlController.dispose();
    _jobNameController.dispose();
    _watermarkUrlController.dispose();
    _textColorController.dispose();
    _textSizeController.dispose();
    _pageController.dispose();
    _shortsPageController.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }
  
  Future<void> _loadApiKey() async {
    final apiKey = await SwiftiaService.getApiKey();
    setState(() {
      _apiKey = apiKey;
    });
    
    // If we have a default API key, save it to preferences for future use
    if (apiKey != null && apiKey.isNotEmpty) {
      await SwiftiaService.saveApiKey(apiKey);
    }
  }
  
  void _setupInitialJobName() {
    final now = DateTime.now();
    _jobNameController.text = 'Videoclip_${now.day}_${now.month}_${now.year}';
  }
  
  Future<void> _checkAndGetVideoDuration() async {
    final url = _youtubeUrlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _videoDuration = null;
        _isLoadingDuration = false;
      });
      return;
    }
    
    if (!SwiftiaService.isValidYouTubeUrl(url)) {
      setState(() {
        _videoDuration = null;
        _isLoadingDuration = false;
      });
      return;
    }
    
    setState(() {
      _isLoadingDuration = true;
    });
    
    try {
      final videoId = SwiftiaService.extractYouTubeVideoId(url);
      if (videoId != null) {
        final duration = await SwiftiaService.getYouTubeVideoDuration(videoId);
        setState(() {
          _videoDuration = duration;
          _isLoadingDuration = false;
        });
      }
    } catch (e) {
      print('Error getting video duration: $e');
      setState(() {
        _videoDuration = null;
        _isLoadingDuration = false;
      });
    }
  }

  // Metodo per verificare se il form di rendering è valido
  bool _isRenderFormValid() {
    // Verifica che sia stato selezionato uno short valido
    if (_selectedShort == null || !_selectedShort!.containsKey('id')) return false;
    
    // Se non ci sono opzioni personalizzate abilitate, il form è sempre valido
    if (!_useCustomWatermark && !_useCustomTextStyle && _maxWordsPerPage == 5) return true;
    
    // Verifica watermark se abilitato
    if (_useCustomWatermark) {
      if (_watermarkUrlController.text.trim().isEmpty) return false;
      if (!_isValidWatermarkUrl(_watermarkUrlController.text.trim())) return false;
    }
    
    // Verifica testo personalizzato se abilitato
    if (_useCustomTextStyle) {
      if (_textColorController.text.trim().isEmpty || _textSizeController.text.trim().isEmpty) return false;
      if (!_isValidColor(_textColorController.text.trim())) return false;
      if (!_isValidFontSize(_textSizeController.text.trim())) return false;
    }
    
    // Verifica maxWordsPerPage (deve essere un numero positivo)
    if (_maxWordsPerPage <= 0 || _maxWordsPerPage > 20) return false;
    
    return true;
  }

  // Metodo per validare il formato del colore (esadecimale CSS)
  bool _isValidColor(String color) {
    // Formato esadecimale CSS: #ffffff, #ffffffed (con alpha)
    final colorRegex = RegExp(r'^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{8})$');
    return colorRegex.hasMatch(color);
  }

  // Metodo per validare il formato della dimensione font (CSS)
  bool _isValidFontSize(String fontSize) {
    // Formato CSS: 24px, 32px, 1.5em, 2rem, ecc.
    final fontSizeRegex = RegExp(r'^\d+(\.\d+)?(px|em|rem|pt|%|vw|vh)$');
    return fontSizeRegex.hasMatch(fontSize);
  }

  // Metodo per validare l'URL del watermark
  bool _isValidWatermarkUrl(String url) {
    try {
      final uri = Uri.parse(url);
      // Verifica che sia un URL valido e che punti a un'immagine
      return uri.hasScheme && 
             (uri.scheme == 'http' || uri.scheme == 'https') &&
             uri.hasAuthority &&
             _isImageUrl(url);
    } catch (e) {
      return false;
    }
  }

  // Metodo per verificare se l'URL punta a un'immagine
  bool _isImageUrl(String url) {
    final imageExtensions = ['.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg'];
    final lowerUrl = url.toLowerCase();
    return imageExtensions.any((ext) => lowerUrl.endsWith(ext));
  }
  
  Future<void> _createJob() async {
    if (!_formKey.currentState!.validate()) return;
    
    final youtubeUrl = _youtubeUrlController.text.trim();
    final videoId = SwiftiaService.extractYouTubeVideoId(youtubeUrl);
    
    if (videoId == null) {
      _showErrorSnackBar('Invalid YouTube URL');
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      print('[UI] Creating job for YouTube ID: $videoId');
      print('[UI] Job name: ${_jobNameController.text.trim()}');
      
      final result = await SwiftiaService.createVideoShortsJob(
        youtubeVideoId: videoId,
        jobName: _jobNameController.text.trim(),
      );
      
      print('[UI] Job created successfully: $result');
      
      setState(() {
        _currentJobId = result['jobId'];
        _isJobCreated = true;
        _isLoading = false;
        _currentStep = VideoclipStep.processing;
      });
      
      // Salva lo stato del processo
      await _saveProcessState();
      
      _startStatusChecking();
      
      // Navigate to processing step
      _pageController.animateToPage(
        _currentStep.index,
        duration: Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      
    } catch (e) {
      print('[UI] Error creating job: $e');
      setState(() {
        _isLoading = false;
      });
      
      // Parse error message for better user experience
      String errorMessage = 'Error creating job: $e';
      if (e.toString().contains('201')) {
        errorMessage = 'Job created with warning. Please check the job status.';
        // Even with warning, we might have a job ID
        if (e.toString().contains('jobId')) {
          // Try to extract job ID from error message
          final match = RegExp(r'jobId[:\s]+([a-zA-Z0-9_-]+)').firstMatch(e.toString());
          if (match != null) {
            final extractedJobId = match.group(1);
            setState(() {
              _currentJobId = extractedJobId;
              _isJobCreated = true;
            });
            _startStatusChecking();
            return;
          }
        }
      }
      
      _showErrorSnackBar(errorMessage);
    }
  }
  
  void _startStatusChecking() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _checkJobStatus();
    });
  }
  
  Future<void> _checkJobStatus() async {
    if (_currentJobId == null) return;
    
    try {
      final status = await SwiftiaService.getJobStatus(_currentJobId!);
      
      if (status['status'] == 'COMPLETED') {
        _statusCheckTimer?.cancel();
        setState(() {
          _isJobCompleted = true;
          _generatedShorts = List<Map<String, dynamic>>.from(status['data']['shorts'] ?? []);
          _currentStep = VideoclipStep.shorts;
        });
        
        if (_generatedShorts.isNotEmpty) {
          _selectedShort = _generatedShorts.first;
        }
        
        // Salva lo stato del processo completato
        await _saveProcessState();
        
        // Invia una notifica push tramite OneSignal all'utente corrente
        await _sendAnalysisCompletedNotification();
        
        // Salva le informazioni di completamento dell'analisi in Firebase
        await _saveAnalysisCompletionToFirebase();
        
        _showSuccessSnackBar('Job completed! ${_generatedShorts.length} shorts generated.');
        
        // Navigate to shorts step
        _pageController.animateToPage(
          _currentStep.index,
          duration: Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        
      } else if (status['status'] == 'FAILED') {
        _statusCheckTimer?.cancel();
        _showErrorSnackBar('Job failed: ${status['error']?['message'] ?? 'Unknown error'}');
      }
      // If still processing, continue checking
      
    } catch (e) {
      print('Error checking job status: $e');
    }
  }
  
  Future<void> _renderVideo() async {
    if (_selectedShort == null || _currentJobId == null) return;
    
    // Verify that the selected short has a valid ID
    if (!_selectedShort!.containsKey('id')) {
      _showErrorSnackBar('Selected short is missing ID. Please select a short again.');
      return;
    }
    
    // Validate form fields if custom options are enabled
    if (_formKey.currentState != null && !_formKey.currentState!.validate()) return;
    
    setState(() {
      _isRendering = true;
    });
    
    try {
      // Extract the short ID from the selected short
      print('[UI] Selected short data: $_selectedShort');
      print('[UI] Generated shorts: $_generatedShorts');
      
      final shortId = _selectedShort!['id'] as int?;
      if (shortId == null) {
        throw Exception('Selected short does not have a valid ID. Short data: $_selectedShort');
      }
      
      print('[UI] Starting render for short ID: $shortId');
      
      // Build rendering options based on user customization
      Map<String, dynamic>? renderOptions;
      
      if (_useCustomWatermark || _useCustomTextStyle || _maxWordsPerPage != 5) {
        renderOptions = {};
        
        // Add watermark options if enabled
        if (_useCustomWatermark && _watermarkUrl.isNotEmpty) {
          renderOptions['waterMark'] = {
            'waterMarkUrl': _watermarkUrl,
            'left': _getWatermarkPosition(_watermarkPosition),
            'bottom': '80%',
            'blendMode': 'normal',
            'opacity': _watermarkOpacity.toString(),
            'width': '400px'
          };
        }
        
        // Add text style options if enabled
        if (_useCustomTextStyle) {
          renderOptions['style'] = [
            {
              'property': 'color',
              'value': _textColor,
              'active': {
                'value': _textColor,
                'duration': 0.3,
              },
              'past': {
                'value': _textColor,
                'duration': 0.7,
              },
            },
            {
              'property': 'font-size',
              'value': _textSize,
              'active': {
                'value': _textSize,
                'duration': 0.3,
              },
            },
          ];
        }
        
        // Add words per page option
        if (_maxWordsPerPage != 5) {
          renderOptions['maxWordsInPage'] = _maxWordsPerPage;
        }
      }
      
      final result = await SwiftiaService.renderVideo(
        jobId: _currentJobId!,
        target: shortId,  // Use the actual short ID from the API response
        preset: _selectedPreset, // Use the preset selected in step 1
        options: renderOptions,
      );
      
      print('[UI] Render started successfully: $result');
      
      setState(() {
        _currentRenderId = result['renderId'];
        _isRendering = false;
        _currentStep = VideoclipStep.render;
      });
      
      _startRenderProgressChecking();
      
      // Navigate to render step
      _pageController.animateToPage(
        _currentStep.index,
        duration: Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      
      // Verify that we have a valid selected short for rendering
      if (_selectedShort == null || !_selectedShort!.containsKey('id')) {
        print('[UI] Warning: No valid short selected for rendering');
        _showErrorSnackBar('Please select a valid short before rendering');
        // Go back to shorts step
        setState(() {
          _currentStep = VideoclipStep.shorts;
        });
        _pageController.animateToPage(
          _currentStep.index,
          duration: Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        return;
      }
      
    } catch (e) {
      print('[UI] Error starting render: $e');
      setState(() {
        _isRendering = false;
      });
      _showErrorSnackBar('Error starting render: $e');
    }
  }
  
  void _startRenderProgressChecking() {
    _renderProgressTimer?.cancel();
    _renderProgressTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _checkRenderStatus();
    });
  }
  
  Future<void> _checkRenderStatus() async {
    if (_currentRenderId == null) return;
    
    try {
      final status = await SwiftiaService.getRenderStatus(_currentRenderId!);
      
      if (status['type'] == 'progress') {
        setState(() {
          _renderProgress = status['progress'] ?? 0.0;
        });
      } else if (status['type'] == 'done') {
        _renderProgressTimer?.cancel();
        setState(() {
          _isRendering = false;
          _isRenderCompleted = true;
          _renderedVideoUrl = status['url'];
          _currentStep = VideoclipStep.complete;
        });
        
        // Inizializza il video player per il video renderizzato
        await _initializeVideoPlayer();
        
        // Pulisci lo stato salvato quando il processo è completamente completato
        await _clearProcessState();
        
        _showSuccessSnackBar('Video rendered successfully!');
        
        // Navigate to complete step
        _pageController.animateToPage(
          _currentStep.index,
          duration: Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
        
      } else if (status['type'] == 'failed') {
        _renderProgressTimer?.cancel();
        setState(() {
          _isRendering = false;
        });
        _showErrorSnackBar('Render failed: ${status['message'] ?? 'Unknown error'}');
      }
      
    } catch (e) {
      print('Error checking render status: $e');
    }
  }
  
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  
  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  

  
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Color(0xFF121212) : Colors.white,
      appBar: null,
      body: Stack(
        children: [
          // Main content area with PageView for horizontal swiping
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.15),
            child: PageView(
              controller: _pageController,
              physics: NeverScrollableScrollPhysics(), // Disable horizontal swiping
              onPageChanged: (index) {
                setState(() {
                  _currentStep = VideoclipStep.values[index];
                });
              },
                      children: [
                // Step 1: Input Form
                _buildInputStep(theme),
                
                // Step 2: Processing
                _buildProcessingStep(theme),
                
                // Step 3: Generated Shorts
                _buildShortsStep(theme),
                
                // Step 4: Render
                _buildRenderStep(theme),
                
                // Step 5: Complete
                _buildCompleteStep(theme),
              ],
                  ),
          ),
          
          // Floating header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _buildFloatingHeader(context),
            ),
          ),
          
          // Step indicator
          Positioned(
            top: MediaQuery.of(context).size.height * 0.08 + 50,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: _buildStepIndicator(context),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildInputStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // Main content area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with AI animation
                _buildHeader(theme),
                const SizedBox(height: 30),
                
                // Main Form
                if (_apiKey != null) ...[
                  _buildMainForm(theme),
                ] else ...[
                  _buildApiKeyPrompt(theme),
                ],
              ],
            ),
          ),
        ),
        
        // Fixed bottom button
        Container(
          width: double.infinity,
      padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(0),
              bottomRight: Radius.circular(0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
                colors: (_youtubeUrlController.text.trim().isNotEmpty && SwiftiaService.isValidYouTubeUrl(_youtubeUrlController.text.trim()))
                    ? [
                        Color(0xFF667eea),
                        Color(0xFF764ba2),
                      ]
                    : [
                        Colors.grey.withOpacity(0.3),
                        Colors.grey.withOpacity(0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: (_youtubeUrlController.text.trim().isNotEmpty && SwiftiaService.isValidYouTubeUrl(_youtubeUrlController.text.trim()))
                  ? [
                      BoxShadow(
                        color: Color(0xFF667eea).withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: ElevatedButton(
              onPressed: (_isLoading || _youtubeUrlController.text.trim().isEmpty || !SwiftiaService.isValidYouTubeUrl(_youtubeUrlController.text.trim())) ? null : _createJob,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 16), 
                        Text(
                          'Creating Job...',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, size: 28),
                        const SizedBox(width: 12),
                        Text(
                          'Create AI Videoclips',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(24),
        // Bordo con effetto vetro più sottile
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        // Ombra per effetto profondità e vetro
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: isDark ? 25 : 20,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          // Ombra interna per effetto vetro
          BoxShadow(
            color: isDark 
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.6),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
        // Gradiente più sottile per effetto vetro
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark 
              ? [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.1),
                ]
              : [
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.2),
                ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Dynamic content based on current step
          if (_currentStep == VideoclipStep.input) ...[
            // Step 1: Input - Original design
          ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                colors: [
                  Color(0xFF667eea),
                  Color(0xFF764ba2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(135 * 3.14159 / 180),
              ).createShader(bounds);
            },
            child: Text(
              'AI Video Shorts Creator',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Save 90% of your time, create video shorts from a YouTube video',
            style: TextStyle(
              color: isDark 
                  ? Colors.white.withOpacity(0.7)
                  : theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          ] else if (_currentStep == VideoclipStep.processing) ...[
            // Step 2: Processing - Shorts creation step
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180),
                ).createShader(bounds);
              },
              child: Text(
                'Creating AI Video Shorts',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180),
                ).createShader(bounds);
              },
              child: Text(
                _isJobCompleted 
                    ? 'AI analyzed the video and created your personalized shorts.'
                    : 'AI is analyzing your video and generating personalized shorts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            
            // Show additional info when analysis is in progress
            if (_isJobCreated && !_isJobCompleted) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.blue.withOpacity(0.2)
                      : Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isDark 
                        ? Colors.blue.withOpacity(0.4)
                        : Colors.blue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  'You can navigate away or minimize the app while processing continues.',
                  style: TextStyle(
                    color: isDark 
                        ? Colors.blue[200]
                        : Colors.blue[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ] else if (_currentStep == VideoclipStep.shorts) ...[
            // Step 3: Shorts - Generated content
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180),
                ).createShader(bounds);
              },
              child: Text(
                'Select Your Short',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Select your preferred short and customize style, watermark, and text settings',
              style: TextStyle(
                color: isDark 
                    ? Colors.white.withOpacity(0.7)
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ] else if (_currentStep == VideoclipStep.render) ...[
            // Step 4: Render - Video rendering
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180),
                ).createShader(bounds);
              },
              child: Text(
                'Rendering Video',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Render your video with the selected       preset and settings',
              style: TextStyle(
                color: isDark 
                    ? Colors.white.withOpacity(0.7)
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ] else if (_currentStep == VideoclipStep.complete) ...[
            // Step 5: Complete - Final result
            ShaderMask(
              shaderCallback: (Rect bounds) {
                return LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  transform: GradientRotation(135 * 3.14159 / 180),
                ).createShader(bounds);
              },
              child: Text(
                'Video Ready!',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your AI-generated video short is ready for download and sharing',
              style: TextStyle(
                color: isDark 
                    ? Colors.white.withOpacity(0.7)
                    : theme.textTheme.bodyMedium?.color?.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildApiKeyStatus(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _apiKey != null ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _apiKey != null ? Colors.green : Colors.orange,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _apiKey != null ? Icons.check_circle : Icons.warning,
            color: _apiKey != null ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _apiKey != null 
                  ? 'API Key configured ✓ (Default)'
                  : 'API Key required to use Swiftia AI',
              style: TextStyle(
                color: _apiKey != null ? Colors.green[700] : Colors.orange[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),

        ],
      ),
    );
  }
  
  Widget _buildProcessingStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // Main content area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with AI animation
                _buildHeader(theme),
                const SizedBox(height: 30),
                
                // Job Status
                if (_isJobCreated) _buildJobStatus(theme),
              ],
            ),
          ),
        ),
        
        // Fixed bottom button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(0),
              bottomRight: Radius.circular(0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              
              // Next button (only if job is completed)
              if (_isJobCompleted)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                        colors: [
                          Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                          Color(0xFF764ba2), // Colore finale: viola al 100%
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667eea).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          setState(() {
                            _currentStep = VideoclipStep.shorts;
                          });
                          _pageController.animateToPage(
                            _currentStep.index,
                            duration: Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Next',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                // Show high usage message when job is not completed
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark 
                          ? Colors.white.withOpacity(0.15) 
                          : Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark 
                            ? Colors.white.withOpacity(0.4)
                            : Colors.grey.withOpacity(0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark 
                              ? Colors.black.withOpacity(0.2)
                              : Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                        child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                              children: [
                           
                                Text(
                              'We are currently experiencing high usage levels. You will be notified when ready.',
                                  style: TextStyle(
                                color: isDark ? Colors.white.withOpacity(0.8) : Colors.black87.withOpacity(0.7),
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                              ),
                              textAlign: TextAlign.center,
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
      ],
    );
  }

  Widget _buildShortsStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // Main content area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with AI animation
                _buildHeader(theme),
                const SizedBox(height: 30),
                
                // Generated Shorts
                if (_isJobCompleted && _generatedShorts.isNotEmpty) ...[
                  _buildGeneratedShorts(theme),
                ],
              ],
            ),
          ),
        ),
        
        // Fixed bottom button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(0),
              bottomRight: Radius.circular(0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Previous button
              Container(
                width: 48,
                height: 48,
                margin: EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.white.withOpacity(0.15) 
                      : Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark 
                        ? Colors.white.withOpacity(0.4)
                        : Colors.grey.withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark 
                          ? Colors.black.withOpacity(0.2)
                          : Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        _currentStep = VideoclipStep.processing;
                      });
                      _pageController.animateToPage(
                        _currentStep.index,
                        duration: Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Center(
                      child: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Next button (only if short is selected)
              if (_selectedShort != null)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                        colors: [
                          Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                          Color(0xFF764ba2), // Colore finale: viola al 100%
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667eea).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          setState(() {
                            _currentStep = VideoclipStep.render;
                          });
                          _pageController.animateToPage(
                            _currentStep.index,
                            duration: Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Next',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                // Show "Select Short" message when no short is selected
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark 
                          ? Colors.white.withOpacity(0.15) 
                          : Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark 
                            ? Colors.white.withOpacity(0.4)
                            : Colors.grey.withOpacity(0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark 
                              ? Colors.black.withOpacity(0.2)
                              : Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.info, size: 20, color: isDark ? Colors.white : Colors.black87),
                            const SizedBox(width: 8),
                            Text(
                              'Select a Short First',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
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
      ],
    );
  }

  Widget _buildRenderStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // Main content area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with AI animation
                _buildHeader(theme),
                const SizedBox(height: 30),
                
                // Render Section
                if (_selectedShort != null) ...[
                  _buildRenderSection(theme),
                  
                  // Rendering customization options
                  _buildRenderingCustomization(theme),
                ],
              ],
            ),
          ),
        ),
        
        // Fixed bottom button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(0),
              bottomRight: Radius.circular(0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Previous button
              Container(
                width: 48,
                height: 48,
                margin: EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.white.withOpacity(0.15) 
                      : Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark 
                        ? Colors.white.withOpacity(0.4)
                        : Colors.grey.withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark 
                          ? Colors.black.withOpacity(0.2)
                          : Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        _currentStep = VideoclipStep.shorts;
                      });
                      _pageController.animateToPage(
                        _currentStep.index,
                        duration: Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Center(
                      child: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Next button (only if render is completed)
              if (_isRenderCompleted)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                        colors: [
                          Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                          Color(0xFF764ba2), // Colore finale: viola al 100%
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667eea).withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          setState(() {
                            _currentStep = VideoclipStep.complete;
                          });
                          _pageController.animateToPage(
                            _currentStep.index,
                            duration: Duration(milliseconds: 400),
                            curve: Curves.easeInOut,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Next',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Icon(Icons.arrow_forward, color: Colors.white, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else
                // Show "Render Video" button when render is not started
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180),
                                              colors: _isRendering
                          ? [
                              Color(0xFF667eea).withOpacity(0.7),
                              Color(0xFF764ba2).withOpacity(0.7),
                            ]
                          : _isRenderFormValid() 
                              ? [
                                  Color(0xFF667eea),
                                  Color(0xFF764ba2),
                                ]
                              : [
                                  Color(0xFF667eea).withOpacity(0.5),
                                  Color(0xFF764ba2).withOpacity(0.5),
                                ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                                                  color: _isRendering
                            ? const Color(0xFF667eea).withOpacity(0.2)
                            : _isRenderFormValid() 
                                ? const Color(0xFF667eea).withOpacity(0.3)
                                : const Color(0xFF667eea).withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: (_isRenderFormValid() && !_isRendering) ? _renderVideo : null,
                        splashColor: (_isRenderFormValid() && !_isRendering) ? Colors.white.withOpacity(0.3) : Colors.transparent,
                        highlightColor: (_isRenderFormValid() && !_isRendering) ? Colors.white.withOpacity(0.1) : Colors.transparent,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                            child: _isRendering
                                ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Rendering...',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.play_arrow, 
                                        color: _isRenderFormValid() ? Colors.white : Colors.white.withOpacity(0.5), 
                                        size: 20
                                      ),
                            const SizedBox(width: 8),
                            Text(
                                        _selectedShort == null || !_selectedShort!.containsKey('id')
                                            ? 'Select a Short First'
                                            : 'Render Video',
                              style: TextStyle(
                                          color: _isRenderFormValid() ? Colors.white : Colors.white.withOpacity(0.5),
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompleteStep(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Column(
      children: [
        // Main content area
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 70, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with AI animation
                _buildHeader(theme),
                const SizedBox(height: 30),
                
                // Final Video
                if (_isRenderCompleted && _renderedVideoUrl != null) ...[
                  _buildFinalVideo(theme),
                ],
              ],
            ),
          ),
        ),
        
        // Fixed bottom button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(0),
              bottomRight: Radius.circular(0),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Previous button
              Container(
                width: 48,
                height: 48,
                margin: EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark 
                      ? Colors.white.withOpacity(0.15) 
                      : Colors.white.withOpacity(0.25),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark 
                        ? Colors.white.withOpacity(0.4)
                        : Colors.grey.withOpacity(0.6),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark 
                          ? Colors.black.withOpacity(0.2)
                          : Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      setState(() {
                        _currentStep = VideoclipStep.render;
                      });
                      _pageController.animateToPage(
                        _currentStep.index,
                        duration: Duration(milliseconds: 400),
                        curve: Curves.easeInOut,
                      );
                    },
                    child: Center(
                      child: Icon(
                        Icons.arrow_back,
                        color: isDark ? Colors.white : Colors.black87,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // Restart button
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                      colors: [
                        Colors.green[600]!, // Colore iniziale: verde al 0%
                        Colors.green[700]!, // Colore finale: verde scuro al 100%
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.green.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () async {
                        if (_renderedVideoUrl != null) {
                          final uri = Uri.parse(_renderedVideoUrl!);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF667eea), // #667eea (blu violaceo) al 0%
                              Color(0xFF764ba2), // #764ba2 (viola) al 100%
                            ],
                            transform: GradientRotation(135 * 3.14159 / 180), // 135 gradi
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.download, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Download Video',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildApiKeyPrompt(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.blue.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.key,
            size: 48,
            color: Colors.blue[600],
          ),
          const SizedBox(height: 16),
          Text(
            'API Key Required',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blue[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your Swiftia API key is already configured by default! You can start using the AI videoclip features immediately.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.blue[600],
            ),
          ),
          const SizedBox(height: 20),

        ],
      ),
    );
  }
  
  Widget _buildMainForm(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 24,
            spreadRadius: 0,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          Form(
            key: _formKey,
            child: Column(
              children: [
                // YouTube URL Input
                TextFormField(
                  controller: _youtubeUrlController,
                  decoration: InputDecoration(
                    labelText: 'YouTube Video URL',
                    hintText: 'https://www.youtube.com/watch?v=...',
                    prefixIcon: Icon(
                        Icons.link,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 22,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Color(0xFF667eea),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a YouTube URL';
                    }
                    if (!SwiftiaService.isValidYouTubeUrl(value.trim())) {
                      return 'Please enter a valid YouTube URL';
                    }
                    return null;
                  },
                ),
                
                // Video Duration Display
                if (_isLoadingDuration) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Getting video duration...',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ] else if (_videoDuration != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Color(0xFF667eea).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Color(0xFF667eea).withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: Color(0xFF667eea),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Duration: $_videoDuration',
                          style: TextStyle(
                            color: Color(0xFF667eea),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 20),
                
                // Job Name Input
                TextFormField(
                  controller: _jobNameController,
                  decoration: InputDecoration(
                    labelText: 'Job Name (Optional)',
                    hintText: 'My Videoclip',
                    prefixIcon: Icon(
                        Icons.edit,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 22,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: Color(0xFF667eea),
                        width: 2,
                      ),
                    ),
                    filled: true,
                    fillColor: isDark ? Colors.grey[800] : Colors.grey[50],
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Preset Selection
                GestureDetector(
                  onTap: _showPresetPicker,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                      border: Border.all(
                        color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      color: isDark ? Colors.grey[800] : Colors.grey[50],
                    ),
                    child: Row(
                      children: [
                        Icon(
                        Icons.style,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          size: 22,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Style Preset (Optional)',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _selectedPreset ?? 'Select Style Preset',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          size: 24,
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
    );
  }

  Widget _buildStepIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.white.withOpacity(0.15)
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark 
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.4),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark 
                    ? Colors.black.withOpacity(0.4)
                    : Colors.black.withOpacity(0.15),
                blurRadius: isDark ? 25 : 20,
                spreadRadius: isDark ? 1 : 0,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: isDark 
                    ? Colors.white.withOpacity(0.1)
                    : Colors.white.withOpacity(0.6),
                blurRadius: 2,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
            ],
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                  ? [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.1),
                    ]
                  : [
                      Colors.white.withOpacity(0.3),
                      Colors.white.withOpacity(0.2),
                    ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final isActive = index == _currentStep.index;
              final isCompleted = index < _currentStep.index;
              return Row(
                children: [
                  // Circle indicator
                  GestureDetector(
                    onTap: () {
                      // Allow navigation to completed steps, current step, or next available step
                      bool canNavigate = false;
                      
                      if (isCompleted || isActive) {
                        canNavigate = true;
                      } else if (index == 1 && _isJobCreated) {
                        canNavigate = true; // Can go to processing if job is created
                      } else if (index == 2 && _isJobCompleted) {
                        canNavigate = true; // Can go to shorts if job is completed
                      } else if (index == 3 && _selectedShort != null) {
                        canNavigate = true; // Can go to render if short is selected
                      } else if (index == 4 && _isRenderCompleted) {
                        canNavigate = true; // Can go to complete if render is completed
                      }
                      
                      if (canNavigate) {
                    setState(() {
                          _currentStep = VideoclipStep.values[index];
                        });
                        _pageController.animateToPage(
                          index,
                          duration: Duration(milliseconds: 400),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        // Show message about what needs to be completed first
                        String message = _getStepPrerequisiteMessage(index);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              message,
                              style: TextStyle(color: Colors.black),
                            ),
                            backgroundColor: Colors.white,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isActive 
                            ? null
                            : isCompleted 
                                ? null
                                : Colors.grey.withOpacity(0.3),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive 
                              ? Colors.transparent
                              : isCompleted 
                                  ? Colors.transparent
                                  : Colors.grey.withOpacity(0.4),
                          width: 2,
                        ),
                        gradient: (isActive || isCompleted) ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                          colors: [
                            Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                            Color(0xFF764ba2), // Colore finale: viola al 100%
                          ],
                        ) : null,
                      ),
                      child: Icon(
                        isCompleted 
                            ? Icons.check
                            : _getStepIcon(index),
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  
                  // Line connector (except for last item)
                  if (index < 4)
                Container(
                      width: 20,
                      height: 2,
                      margin: EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                        color: isCompleted 
                            ? null
                            : Colors.grey.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(1),
                        gradient: isCompleted ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                          colors: [
                            Color(0xFF667eea), // Colore iniziale: blu violaceo al 0%
                            Color(0xFF764ba2), // Colore finale: viola al 100%
                          ],
                        ) : null,
                      ),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  IconData _getStepIcon(int stepIndex) {
    switch (stepIndex) {
      case 0: return Icons.input;
      case 1: return Icons.sync;
      case 2: return Icons.video_library;
      case 3: return Icons.movie_creation;
      case 4: return Icons.check_circle;
      default: return Icons.circle;
    }
  }

  String _getStepPrerequisiteMessage(int stepIndex) {
    switch (stepIndex) {
      case 1: return 'Complete the input form first';
      case 2: return 'Wait for the job to complete processing';
      case 3: return 'Select a generated short first';
      case 4: return 'Complete the render process first';
      default: return 'Complete previous steps first';
    }
  }



  void _showPresetPicker() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Get available presets
    final availablePresets = SwiftiaService.getAvailablePresets();
    final currentIndex = _selectedPreset != null ? availablePresets.indexOf(_selectedPreset!) : 0;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, -2),
                      ),
                    ],
                  ),
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ).createShader(bounds);
                },
                child: Text(
                  'Select Style Preset',
                                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                height: 180,
                child: CupertinoPicker(
                  backgroundColor: Colors.transparent,
                  itemExtent: 40,
                  scrollController: FixedExtentScrollController(
                    initialItem: currentIndex >= 0 ? currentIndex : 0,
                  ),
                                      onSelectedItemChanged: (int index) {
                      final preset = availablePresets[index];
                      setState(() {
                        _selectedPreset = preset;
                      });
                    },
                                    children: availablePresets.map((preset) => Center(
                    child: Text(
                      preset,
                      style: TextStyle(
                        fontSize: 18,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(
                    color: Color(0xFF667eea),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
        );
      },
    );
  }

  Widget _buildFloatingHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        // Effetto vetro sospeso
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(25),
        // Bordo con effetto vetro
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        // Ombre per effetto sospeso
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: isDark ? 25 : 20,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: isDark 
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.6),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
        // Gradiente sottile per effetto vetro
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark 
              ? [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.1),
                ]
              : [
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.2),
                ],
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
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
                    onPressed: () {
                      // Se c'è un processo in corso, mostra un messaggio invece di chiudere
                      if (_isJobCreated && !_isJobCompleted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.white),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Process is running in background. You will be notified when ready.',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                            backgroundColor: Colors.blue,
                            duration: Duration(seconds: 3),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                  ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        colors: [
                          Color(0xFF667eea),
                          Color(0xFF764ba2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180),
                      ).createShader(bounds);
                    },
                    child: Text(
                      'Fluzar',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        fontFamily: 'Ethnocentric',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildJobStatus(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(24),
        // Bordo con effetto vetro più sottile
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        // Ombra per effetto profondità e vetro
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: isDark ? 25 : 20,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          // Ombra interna per effetto vetro
          BoxShadow(
            color: isDark 
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.6),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
        // Gradiente più sottile per effetto vetro
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark 
              ? [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.1),
                ]
              : [
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.2),
                ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (!_isJobCompleted) ...[
            // AI Analysis Icon and Text
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Video analysis in progress...',
                    style: TextStyle(
                      color: isDark 
                          ? Colors.white.withOpacity(0.8)
                          : Color(0xFF667eea),
                      fontStyle: FontStyle.italic,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            // Robot Animation
            Center(
              child: Container(
                width: 180,
                height: 180,
                child: Lottie.asset(
                  'assets/animations/RobotFuturisticAianimated.json',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ] else ...[
            // Completion message
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
              
                const SizedBox(width: 16),
                Expanded(
                  child: ShaderMask(
                    shaderCallback: (Rect bounds) {
                      return LinearGradient(
                        colors: [
                          Color(0xFF667eea),
                          Color(0xFF764ba2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180),
                      ).createShader(bounds);
                    },
                    child: Text(
                      'Analysis completed successfully!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Additional completion info
            Text(
              'Your video has been analyzed and ${_generatedShorts.length} shorts have been generated.',
              style: TextStyle(
                color: isDark 
                    ? Colors.white.withOpacity(0.7)
                    : Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // Success icon
            Center(
              child: Container(
                width: 120,
                height: 120,
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      colors: [
                        Color(0xFF667eea),
                        Color(0xFF764ba2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ).createShader(bounds);
                  },
                  child: Icon(
                    Icons.video_library,
                    color: Colors.white,
                    size: 80,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  Widget _buildGeneratedShorts(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        SizedBox(
          height: 320, // Aumentata da 220 a 280 per mostrare tutta la descrizione
          child: PageView.builder(
            controller: _shortsPageController,
          itemCount: _generatedShorts.length,
            onPageChanged: (index) {
              setState(() {
                _currentShortIndex = index;
                _selectedShort = _generatedShorts[index];
              });
            },
          itemBuilder: (context, index) {
            final short = _generatedShorts[index];
            final isSelected = _selectedShort == short;
            return Container(
                margin: EdgeInsets.only(right: 12, left: 4),
              decoration: BoxDecoration(
                  // Effetto vetro semi-trasparente opaco come le card AI
                  color: isDark 
                      ? const Color(0xFF1A1A1A).withOpacity(0.95)
                      : const Color(0xFFFAFAFA).withOpacity(0.95),
                  borderRadius: BorderRadius.circular(20),
                  // Bordo con effetto vetro più sottile
                border: Border.all(
                    color: isSelected 
                        ? Color(0xFF667eea).withOpacity(0.6)
                        : (isDark 
                            ? Colors.white.withOpacity(0.08)
                            : Colors.black.withOpacity(0.06)),
                  width: isSelected ? 2 : 1,
                ),
                  // Ombra per effetto profondità e vetro
                  boxShadow: [
                    BoxShadow(
                      color: isDark 
                          ? Colors.black.withOpacity(0.3)
                          : Colors.black.withOpacity(0.08),
                      blurRadius: 20,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                    if (!isDark)
                      BoxShadow(
                        color: Colors.white.withOpacity(0.8),
                        blurRadius: 1,
                        spreadRadius: -1,
                        offset: const Offset(0, 1),
                      ),
                  ],
                  // Gradiente sottile per effetto vetro
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark 
                        ? [
                            const Color(0xFF2A2A2A).withOpacity(0.3),
                            const Color(0xFF1A1A1A).withOpacity(0.1),
                          ]
                        : [
                            Colors.white.withOpacity(0.4),
                            Colors.white.withOpacity(0.2),
                          ],
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      setState(() {
                        _selectedShort = short;
                      });
                    },
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row with title and radio button
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                  short['title'] ?? 'Short ${short['id']}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Radio<String>(
                                value: short['id'].toString(),
                                groupValue: _selectedShort?['id'].toString(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedShort = short;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Duration info
                          Row(
                  children: [
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: isDark ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                              ),
                              const SizedBox(width: 8),
                    Text(
                      'Duration: ${_formatDuration(Duration(seconds: _calculateShortDuration(short)))}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                    ),
                              ),
                            ],
                          ),
                          // AI Reason section (if present)
                    if (short['reason'] != null) ...[
                            const SizedBox(height: 10),
                            Expanded(
                              child: Container(
                                padding: EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  // Sfondo neutro che non cambia con la selezione
                                  color: isDark 
                                      ? Colors.white.withOpacity(0.05)
                                      : Colors.grey.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isDark 
                                        ? Colors.white.withOpacity(0.1)
                                        : Colors.grey.withOpacity(0.2),
                                    width: 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                      Row(
                        children: [
                                        Icon(
                                          Icons.psychology,
                                          size: 16,
                                          color: isDark ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                                        ),
                                        const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                                            'AI Analysis',
                              style: TextStyle(
                                fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: isDark ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                              ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: short['reason']));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'AI Reason copied to clipboard',
                                    style: TextStyle(color: Colors.black),
                                  ),
                                  backgroundColor: Colors.white,
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            child: Container(
                                            padding: EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isDark 
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: isDark 
                                    ? Colors.white.withOpacity(0.6)
                                    : Colors.grey[500],
                              ),
                            ),
                          ),
                        ],
                                    ),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        physics: BouncingScrollPhysics(),
                                        child: Text(
                                          short['reason'],
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontStyle: FontStyle.italic,
                                            color: isDark ? Colors.white.withOpacity(0.9) : Colors.grey[800],
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        
        // Punti di indicazione dello scorrimento orizzontale
        if (_generatedShorts.length > 1) ...[
          const SizedBox(height: 8),
          Container(
            padding: EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_generatedShorts.length, (index) {
                return Container(
                  width: 8,
                  height: 8,
                  margin: EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == _currentShortIndex 
                        ? const Color(0xFF6C63FF)
                        : theme.colorScheme.outline.withOpacity(0.3),
                  ),
                );
              }),
            ),
          ),
        ],

      ],
    );
  }
  
  /// Show watermark position picker modal
  void _showWatermarkPositionPicker() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Get available positions
    final availablePositions = [
      'bottom-right', 'bottom-left', 'top-right', 'top-left', 'center'
    ];
    final currentIndex = availablePositions.indexOf(_watermarkPosition);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ).createShader(bounds);
                },
                child: Text(
                  'Select Watermark Position',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                height: 180,
                child: CupertinoPicker(
                  backgroundColor: Colors.transparent,
                  itemExtent: 40,
                  scrollController: FixedExtentScrollController(
                    initialItem: currentIndex >= 0 ? currentIndex : 0,
                  ),
                  onSelectedItemChanged: (int index) {
                    final position = availablePositions[index];
                  setState(() {
                      _watermarkPosition = position;
                    });
                  },
                  children: availablePositions.map((position) => Center(
                    child: Text(
                      position.replaceAll('-', ' ').toUpperCase(),
                      style: TextStyle(
                        fontSize: 18,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(
                    color: Color(0xFF667eea),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
              ),
            );
          },
    );
  }

  /// Show rendering preset picker modal
  void _showRenderingPresetPicker() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // Get available presets
    final availablePresets = [
      'DEFAULT', 'VIRAL', 'GRAPES', 'BLURRY', 'FAST',
      'DEEP DIVER', 'GLOW VIOLET', '70S RADIATION', 'BILL GREEN', 'ETHEREAL UNDERLINE'
    ];
    final currentIndex = availablePresets.indexOf(_selectedPreset ?? 'DEFAULT');
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? Colors.grey[900] : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.only(top: 16, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ).createShader(bounds);
                },
                child: Text(
                  'Select Rendering Style Preset',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              SizedBox(
                height: 180,
                child: CupertinoPicker(
                  backgroundColor: Colors.transparent,
                  itemExtent: 40,
                  scrollController: FixedExtentScrollController(
                    initialItem: currentIndex >= 0 ? currentIndex : 0,
                  ),
                  onSelectedItemChanged: (int index) {
                    final preset = availablePresets[index];
                    setState(() {
                      _selectedPreset = preset;
                      _selectedRenderingPreset = preset; // Keep in sync
                    });
                  },
                  children: availablePresets.map((preset) => Center(
                    child: Text(
                      preset,
                      style: TextStyle(
                        fontSize: 18,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  )).toList(),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Close',
                  style: TextStyle(
                    color: Color(0xFF667eea),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Helper function to convert watermark position to CSS value
  String _getWatermarkPosition(String position) {
    switch (position) {
      case 'bottom-right':
        return 'calc(100% - 200px)';
      case 'bottom-left':
        return '200px';
      case 'top-right':
        return 'calc(100% - 200px)';
      case 'top-left':
        return '200px';
      case 'center':
        return 'calc(50% - 200px)';
      default:
        return 'calc(100% - 200px)';
    }
  }

  Widget _buildRenderingCustomization(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.1)
            : Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.grey.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.tune,
                color: Color(0xFF667eea),
                size: 24,
              ),
              const SizedBox(width: 12),
              Text(
                'Rendering Customization',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF667eea),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
                    // Preset Selection
          GestureDetector(
            onTap: _showRenderingPresetPicker,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                  width: 1,
                ),
                borderRadius: BorderRadius.circular(16),
                color: isDark ? Colors.grey[800] : Colors.grey[50],
              ),
              child: Row(
              children: [
                  Icon(
                    Icons.style,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 22,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        const SizedBox(height: 4),
                Text(
                          _selectedPreset ?? 'DEFAULT',
                  style: TextStyle(
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Watermark Options
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _useCustomWatermark,
                    onChanged: (value) {
                      setState(() {
                        _useCustomWatermark = value ?? false;
                      });
                    },
                    activeColor: Color(0xFF667eea),
                  ),
                  Text(
                    'Custom Watermark',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              if (_useCustomWatermark) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _watermarkUrlController,
                  decoration: InputDecoration(
                    labelText: 'Watermark URL',
                    labelStyle: TextStyle(fontSize: 12),
                    hintText: 'https://example.com/logo.png',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: isDark 
                        ? Colors.white.withOpacity(0.1)
                        : Colors.white.withOpacity(0.8),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _watermarkUrl = value;
                    });
                  },
                  onFieldSubmitted: (value) {
                    setState(() {
                      _watermarkUrl = value;
                    });
                  },
                                          validator: (value) {
                          if (_useCustomWatermark && (value == null || value.trim().isEmpty)) {
                            return 'Please enter watermark URL';
                          }
                          if (_useCustomWatermark && !_isValidWatermarkUrl(value ?? '')) {
                            return 'Please enter a valid image URL (e.g., https://example.com/logo.png)';
                          }
                          return null;
                        },
                ),
                const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
                  child: GestureDetector(
                    onTap: _showWatermarkPositionPicker,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        color: isDark ? Colors.grey[800] : Colors.grey[50],
                ),
                child: Row(
                  children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  _watermarkPosition,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: isDark ? Colors.white : Colors.black87,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                  ],
                ),
              ),
                          Icon(
                            Icons.arrow_drop_down,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Opacity slider
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Opacity',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Slider(
                      value: _watermarkOpacity,
                      min: 0.0,
                      max: 1.0,
                      divisions: 10,
                      activeColor: Color(0xFF667eea),
                      onChanged: (value) {
                        setState(() {
                          _watermarkOpacity = value;
                        });
                      },
                      onChangeEnd: (value) {
                        setState(() {
                          _watermarkOpacity = value;
                        });
                      },
                    ),
                    Text(
                      '${(_watermarkOpacity * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Text Style Options
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: _useCustomTextStyle,
                    onChanged: (value) {
                      setState(() {
                        _useCustomTextStyle = value ?? false;
                      });
                    },
                    activeColor: Color(0xFF667eea),
                  ),
                  Text(
                    'Custom Text Style',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ],
              ),
              if (_useCustomTextStyle) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _textColorController,
                        decoration: InputDecoration(
                          labelText: 'Color',
                          labelStyle: TextStyle(fontSize: 12),
                          hintText: '#ffffff',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: isDark 
                              ? Colors.white.withOpacity(0.1)
                              : Colors.white.withOpacity(0.8),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _textColor = value;
                          });
                        },
                        onFieldSubmitted: (value) {
                          setState(() {
                            _textColor = value;
                          });
                        },
                        validator: (value) {
                          if (_useCustomTextStyle && (value == null || value.trim().isEmpty)) {
                            return 'Please enter text color';
                          }
                          if (_useCustomTextStyle && !_isValidColor(value ?? '')) {
                            return 'Please enter a valid hex color (e.g., #ffffff)';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _textSizeController,
                        decoration: InputDecoration(
                          labelText: 'Size',
                          labelStyle: TextStyle(fontSize: 12),
                          hintText: '24px',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: isDark 
                              ? Colors.white.withOpacity(0.1)
                              : Colors.white.withOpacity(0.8),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _textSize = value;
                          });
                        },
                        onFieldSubmitted: (value) {
                          setState(() {
                            _textSize = value;
                          });
                        },
                        validator: (value) {
                          if (_useCustomTextStyle && (value == null || value.trim().isEmpty)) {
                            return 'Please enter text size';
                          }
                          if (_useCustomTextStyle && !_isValidFontSize(value ?? '')) {
                            return 'Please enter a valid font size (e.g., 24px, 1.5em)';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Words per page
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Words per Page',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Slider(
                value: _maxWordsPerPage.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: Color(0xFF667eea),
                onChanged: (value) {
                  setState(() {
                    _maxWordsPerPage = value.toInt();
                  });
                },
                onChangeEnd: (value) {
                  setState(() {
                    _maxWordsPerPage = value.toInt();
                  });
                },
              ),
              Text(
                '${_maxWordsPerPage} words',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildRenderSection(ThemeData theme) {
    if (!_isRendering) return SizedBox.shrink();
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.movie_creation,
              color: Color(0xFF667eea),
            ),
            const SizedBox(width: 12),
            Text(
              'Render Status',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Color(0xFF667eea),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Column(
          children: [
            LinearProgressIndicator(
              value: _renderProgress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF667eea)),
            ),
            const SizedBox(height: 8),
            Text(
              'Rendering: ${(_renderProgress * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: Color(0xFF667eea),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildFinalVideo(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: isDark ? 25 : 20,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: isDark 
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.6),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark 
              ? [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.1),
                ]
              : [
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.2),
                ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          
          // Video Player Container
          if (_renderedVideoUrl != null) ...[
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Calcola l'altezza basata sul rapporto del video
                  double videoHeight = 300; // Altezza di default
                  
                  if (_videoPlayerController?.value.isInitialized == true) {
                    final aspectRatio = _videoPlayerController!.value.aspectRatio;
                    if (aspectRatio > 0) {
                      // Calcola l'altezza basata sulla larghezza disponibile e il rapporto del video
                      videoHeight = constraints.maxWidth / aspectRatio;
                      
                      // Limita l'altezza massima e minima
                      videoHeight = videoHeight.clamp(200.0, 400.0);
                    }
                  }
                  
                  return Container(
                    height: videoHeight,
                                         child: Stack(
            children: [
                         // Video Player
                         GestureDetector(
                           onTap: () {
                             setState(() {
                               _showControls = !_showControls;
                             });
                           },
                           child: _buildVideoPlayer(),
                         ),
                         
                         // Video Controls
                         AnimatedOpacity(
                           opacity: _showControls ? 1.0 : 0.0,
                           duration: Duration(milliseconds: 300),
                           child: LayoutBuilder(
                             builder: (context, constraints) {
                               final isSmallScreen = constraints.maxHeight < 300;
                               
                               return Stack(
                                 children: [
                                   // Overlay semi-trasparente
                                   Container(
                                     width: constraints.maxWidth,
                                     height: constraints.maxHeight,
                                     decoration: BoxDecoration(
                                       gradient: LinearGradient(
                                         begin: Alignment.topCenter,
                                         end: Alignment.bottomCenter,
                                         colors: [
                                           Colors.black.withOpacity(0.3),
                                           Colors.transparent,
                                           Colors.transparent,
                                           Colors.black.withOpacity(0.4),
                                         ],
                                         stops: [0.0, 0.2, 0.8, 1.0],
                                       ),
                                     ),
                                   ),
                                   
                                   // Pulsante Play/Pause al centro
                                   Center(
                                     child: Container(
                                       decoration: BoxDecoration(
                                         color: Colors.black.withOpacity(0.2),
                                         shape: BoxShape.circle,
                                         border: Border.all(
                                           color: Colors.white.withOpacity(0.4),
                                           width: 1.5,
                                         ),
                                       ),
                                                                                child: IconButton(
                                           icon: Icon(
                                             _videoPlayerController != null && _isVideoInitialized && _videoPlayerController!.value.isPlaying
                                                 ? Icons.pause 
                                                 : Icons.play_arrow,
                                             color: Colors.white,
                                             size: isSmallScreen ? 32 : 40,
                                           ),
                                           padding: EdgeInsets.all(isSmallScreen ? 6 : 8),
                                           onPressed: () {
                                             if (_videoPlayerController != null && _isVideoInitialized) {
                                               _toggleVideoPlayback();
                                             }
                                           },
                                         ),
                                     ),
                                   ),
                                   
                                   // Controlli in alto (fullscreen)
                                   Positioned(
                                     top: 8,
                                     right: 8,
                                     child: Container(
                                       decoration: BoxDecoration(
                                         color: Colors.black.withOpacity(0.2),
                                         borderRadius: BorderRadius.circular(15),
                                       ),
                                       child: IconButton(
                                         icon: Icon(
                                           _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                           color: Colors.white,
                                           size: 24,
                                         ),
                                         padding: EdgeInsets.all(isSmallScreen ? 2 : 4),
                                         constraints: BoxConstraints(minWidth: 32, minHeight: 32),
                                         onPressed: _toggleFullScreen,
                                       ),
                                     ),
                                   ),
                                   
                                   // Controlli in basso (slider e tempo)
                                   Positioned(
                                     left: 0,
                                     right: 0,
                                     bottom: 0,
                                     child: Container(
                                       padding: EdgeInsets.only(top: 20),
                                       decoration: BoxDecoration(
                                         gradient: LinearGradient(
                                           begin: Alignment.bottomCenter,
                                           end: Alignment.topCenter,
                                           colors: [
                                             Colors.black.withOpacity(0.6),
                                             Colors.black.withOpacity(0.2),
                                             Colors.transparent,
                                           ],
                                           stops: [0.0, 0.5, 1.0],
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
                                                     fontSize: 11,
                  fontWeight: FontWeight.bold,
                                                   ),
                                                 ),
                                                 Text(
                                                   _formatDuration(_videoPlayerDuration),
                                                   style: TextStyle(
                                                     color: Colors.white,
                                                     fontSize: 11,
                                                     fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
                                           ),
                                           
                                           // Progress bar
                                           SliderTheme(
                                             data: SliderThemeData(
                                               thumbShape: RoundSliderThumbShape(enabledThumbRadius: isSmallScreen ? 3 : 5),
                                               trackHeight: isSmallScreen ? 2 : 3,
                                               trackShape: RoundedRectSliderTrackShape(),
                                               activeTrackColor: Colors.white,
                                               inactiveTrackColor: Colors.white.withOpacity(0.3),
                                               thumbColor: Colors.white,
                                               overlayColor: Color(0xFF667eea).withOpacity(0.3),
                                             ),
                                             child: Slider(
                                               value: _currentPosition.inSeconds.toDouble(),
                                               min: 0.0,
                                               max: _videoPlayerDuration.inSeconds.toDouble() > 0 
                                                   ? _videoPlayerDuration.inSeconds.toDouble() 
                                                   : 1.0,
                                               onChanged: (value) {
                                                 if (_videoPlayerController != null && _isVideoInitialized) {
                                                   _videoPlayerController!.seekTo(Duration(seconds: value.toInt()));
                                                   setState(() {
                                                     _showControls = true;
                                                   });
                                                 }
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
                     ),
                  );
                },
              ),
            ),
            
          const SizedBox(height: 16),
          
            // Video info
                      Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark 
                      ? Colors.white.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                      children: [
                        Icon(
                    Icons.info_outline,
                    size: 20,
                          color: Color(0xFF667eea),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                      'Video format: MP4',
                            style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white.withOpacity(0.8) : Colors.grey[700],
                        fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ] else ...[
            // Fallback container if video URL is not available
          Container(
            width: double.infinity,
              padding: EdgeInsets.all(24),
            decoration: BoxDecoration(
                color: isDark 
                    ? Colors.white.withOpacity(0.05)
                    : Colors.grey.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark 
                      ? Colors.white.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                        children: [
                          Icon(
                    Icons.video_file,
                    size: 48,
                    color: Color(0xFF667eea),
                  ),
                  const SizedBox(height: 16),
                          Text(
                    'Video Processing Complete',
                            style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                      Text(
                        'Your personalized video short has been successfully rendered with AI-generated captions and styling. The video is ready for download and sharing on social media platforms.',
                        style: TextStyle(
                          fontSize: 14,
                      color: isDark ? Colors.white.withOpacity(0.7) : Colors.grey[600],
                          height: 1.4,
                        ),
                    textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  // Metodo per inizializzare il video player
  Future<void> _initializeVideoPlayer() async {
    if (_renderedVideoUrl == null) return;
    
    try {
      // Dispose del controller precedente se esiste
      if (_videoPlayerController != null) {
        _videoPlayerController!.removeListener(_onVideoPositionChanged);
        _videoPlayerController!.dispose();
      }
      
      setState(() {
        _isVideoInitialized = false;
        _showControls = true;
      });
      
      print('[UI] Creating video controller for: $_renderedVideoUrl');
      
      // Crea un nuovo controller per il video renderizzato
      _videoPlayerController = VideoPlayerController.network(_renderedVideoUrl!);
      
      // Inizializza il controller
      await _videoPlayerController!.initialize();
      
      if (!mounted) return;
      
      // Imposta il loop
      _videoPlayerController!.setLooping(true);
      
      // Imposta la durata del video
      _videoPlayerDuration = _videoPlayerController!.value.duration;
      _currentPosition = Duration.zero;
      
      // Aggiungi listener per aggiornare l'UI e la posizione
      _videoPlayerController!.addListener(_onVideoPositionChanged);
      
      // Aggiorna lo stato
      setState(() {
        _isVideoInitialized = true;
        _showControls = true;
      });
      
      print('[UI] Video player initialized successfully for rendered video: $_renderedVideoUrl');
      print('[UI] Video duration: $_videoPlayerDuration');
      print('[UI] Video aspect ratio: ${_videoPlayerController!.value.aspectRatio}');
    } catch (e) {
      print('[UI] Error initializing video player: $e');
        if (mounted) {
        setState(() {
          _isVideoInitialized = false;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading video: ${e.toString().substring(0, e.toString().length > 50 ? 50 : e.toString().length)}...'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Metodo per gestire i cambiamenti di posizione del video
  void _onVideoPositionChanged() {
    if (mounted && _videoPlayerController != null) {
      setState(() {
        _currentPosition = _videoPlayerController!.value.position;
      });
    }
  }
  
  // Metodo per toggle del fullscreen
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    // Qui puoi implementare la logica per il fullscreen reale
  }
  
  // Metodo per toggle della riproduzione
  void _toggleVideoPlayback() {
    if (_videoPlayerController != null && _isVideoInitialized) {
      setState(() {
        if (_videoPlayerController!.value.isPlaying) {
          _videoPlayerController!.pause();
        } else {
          _videoPlayerController!.play();
        }
      });
    }
  }

  // Metodo per costruire il video player
  Widget _buildVideoPlayer() {
    if (_renderedVideoUrl == null) {
      return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.video_file,
                    size: 48,
              color: Colors.white.withOpacity(0.6),
                  ),
                  const SizedBox(height: 8),
                  Text(
              'Video not available',
                    style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 14,
                    ),
                  ),
                ],
              ),
      );
    }
    
    if (_videoPlayerController == null || !_isVideoInitialized) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Loading video...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    // Verify if video is horizontal (aspect ratio > 1)
    final bool isHorizontalVideo = _videoPlayerController!.value.aspectRatio > 1.0;
    
    if (isHorizontalVideo) {
      // For horizontal videos, show them full screen with FittedBox
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black, // Black background to avoid empty spaces
        child: FittedBox(
          fit: BoxFit.contain, // Scale to preserve aspect ratio
          child: SizedBox(
            width: _videoPlayerController!.value.size.width,
            height: _videoPlayerController!.value.size.height,
            child: VideoPlayer(_videoPlayerController!),
          ),
        ),
      );
                      } else {
      // For vertical videos, maintain standard AspectRatio
      return Center(
        child: AspectRatio(
          aspectRatio: _videoPlayerController!.value.aspectRatio,
          child: VideoPlayer(_videoPlayerController!),
        ),
      );
    }
  }
  
  String _formatDuration(Duration duration) {
    if (duration.inSeconds <= 0) return '0:00';
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}:${seconds.toString().padLeft(2, '0')}';
  }
  
  // Metodo helper per calcolare la durata di un short
  int _calculateShortDuration(Map<String, dynamic> short) {
    try {
      final startTime = short['startTime'];
      final endTime = short['endTime'];
      
      if (startTime == null || endTime == null) return 0;
      
      final start = startTime is int ? startTime.toDouble() : double.tryParse(startTime.toString()) ?? 0.0;
      final end = endTime is int ? endTime.toDouble() : double.tryParse(endTime.toString()) ?? 0.0;
      
      final duration = end - start;
      return duration > 0 ? duration.round() : 0;
    } catch (e) {
      print('[UI] Error calculating short duration: $e');
      return 0;
    }
  }

  /// Salva le informazioni di completamento dell'analisi in Firebase
  Future<void> _saveAnalysisCompletionToFirebase() async {
    try {
      if (_currentUser == null) return;
      
      final String userId = _currentUser!.uid;
      final String jobId = _currentJobId ?? '';
      final int shortsCount = _generatedShorts.length;
      final DateTime completionTime = DateTime.now();
      
      // Crea la struttura del database per i processi completati
      final DatabaseReference processRef = _database
          .child('users')
          .child('users')
          .child(userId)
          .child('profile')
          .child('completed_processes');
      
      // Genera una chiave unica per questo processo
      final String processKey = processRef.push().key ?? DateTime.now().millisecondsSinceEpoch.toString();
      
      // Dati del processo completato
      final Map<String, dynamic> processData = {
        'job_id': jobId,
        'shorts_count': shortsCount,
        'completion_timestamp': ServerValue.timestamp,
        'completion_date': completionTime.toIso8601String(),
        'process_type': 'video_analysis',
        'status': 'completed',
        'youtube_url': _youtubeUrlController.text.trim(),
        'job_name': _jobNameController.text.trim(),
        'preset_used': _selectedPreset ?? 'default',
      };
      
      // Salva i dati del processo
      await processRef.child(processKey).set(processData);
      
      // Aggiorna il conteggio totale dei processi completati
      final DatabaseReference totalCountRef = _database
          .child('users')
          .child('users')
          .child(userId)
          .child('profile')
          .child('process_stats');
      
      // Recupera il conteggio attuale e incrementalo
      final snapshot = await totalCountRef.child('total_completed_analyses').get();
      int currentCount = 0;
      if (snapshot.exists && snapshot.value != null) {
        currentCount = int.tryParse(snapshot.value.toString()) ?? 0;
      }
      
      final int newCount = currentCount + 1;
      
      // Aggiorna il conteggio totale
      await totalCountRef.child('total_completed_analyses').set(newCount);
      
      // Aggiorna anche l'ultima data di completamento
      await totalCountRef.child('last_analysis_completion').set(ServerValue.timestamp);
      
      print('[Firebase] Analysis completion saved for user $userId, job $jobId, shorts count: $shortsCount');
      print('[Firebase] Total completed analyses updated to: $newCount');
      
    } catch (e) {
      print('[Firebase] Error saving analysis completion: $e');
    }
  }

  /// Invia una notifica push via OneSignal quando l'analisi AI è completata
  Future<void> _sendAnalysisCompletedNotification() async {
    try {
      if (_currentUser == null) return;
      final String userId = _currentUser!.uid;
      // Recupera il OneSignal Player ID salvato per l'utente corrente
      final snap = await _database
          .child('users')
          .child('users')
          .child(userId)
          .child('onesignal_player_id')
          .get();
      if (!snap.exists || snap.value == null) {
        print('[OneSignal] No player ID for user $userId');
        return;
      }
      final String playerId = snap.value.toString();
      const String oneSignalAppId = '8ad10111-3d90-4ec2-a96d-28f6220ab3a0';
      const String oneSignalApiUrl = 'https://api.onesignal.com/notifications';
      const String restApiKey = 'NGEwMGZmMDItY2RkNy00ZDc3LWI0NzEtZGYzM2FhZWU1OGUz';
      const String title = '✅ AI Analysis Complete';
      final String content = _generatedShorts.isNotEmpty
          ? 'Your video has ${_generatedShorts.length} shorts ready to review.'
          : 'Your video analysis is complete. Shorts are ready.';
      const String clickUrl = 'https://fluzar.com/deep-redirect';
      const String largeIcon = 'https://img.onesignal.com/tmp/a74d2f7f-f359-4df4-b7ed-811437987e91/oxcPer7LSBS4aCGcVMi3_120x120%20app%20logo%20grande%20con%20sfondo%20bianco.png?_gl=1*1x2tx4r*_gcl_au*NjI1OTE1MTUyLjE3NTI0Mzk0Nzc.*_ga*MTYzNjE2MzA0MC4xNzUyNDM5NDc4*_ga_Z6LSTXWLPN*czE3NTI0NTEwMDkkbzMkZzAkdDE3NTI0NTEwMDkkajYwJGwwJGgyOTMzMzMxODk';
      final Map<String, dynamic> payload = {
        'app_id': oneSignalAppId,
        'include_player_ids': [playerId],
        'channel_for_external_user_ids': 'push',
        'headings': {'en': title},
        'contents': {'en': content},
        'url': clickUrl,
        'chrome_web_icon': largeIcon,
        'data': {
          'type': 'analysis_complete',
          'from_user_id': userId,
          'video_job_id': _currentJobId,
        }
      };
      final response = await http.post(
        Uri.parse(oneSignalApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $restApiKey',
        },
        body: jsonEncode(payload),
      );
      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        print('[OneSignal] Analysis notification sent: ${result['id']}');
      } else {
        print('[OneSignal] API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('[OneSignal] Error sending analysis notification: $e');
    }
  }
}

class _ApiKeyDialog extends StatefulWidget {
  final String initialApiKey;
  
  const _ApiKeyDialog({required this.initialApiKey});
  
  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  late TextEditingController _apiKeyController;
  bool _isVisible = false;
  
  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController(text: widget.initialApiKey);
  }
  
  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Swiftia API Settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Your API key is already configured. You can change it here if needed.',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _apiKeyController,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'Enter your Swiftia API key',
              suffixIcon: IconButton(
                icon: Icon(_isVisible ? Icons.visibility_off : Icons.visibility),
                onPressed: () {
                  setState(() {
                    _isVisible = !_isVisible;
                  });
                },
              ),
            ),
            obscureText: !_isVisible,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your API key';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Current API key: ${widget.initialApiKey.substring(0, 8)}...',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_apiKeyController.text.trim().isNotEmpty) {
              Navigator.of(context).pop(_apiKeyController.text.trim());
            }
          },
          child: Text('Save'),
        ),
      ],
    );
  }
}
