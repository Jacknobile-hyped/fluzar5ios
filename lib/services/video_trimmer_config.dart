class VideoTrimmerConfig {
  // URL del server di produzione
  static const String baseUrl = 'https://trimmer-zv8c.onrender.com';
  
  // Timeout per le richieste
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration processingTimeout = Duration(minutes: 10);
  
  // Limiti di dimensione file
  static const int maxFileSizeBytes = 500 * 1024 * 1024; // 500MB
  
  // Endpoints
  static const String healthEndpoint = '/health';
  static const String ffmpegInfoEndpoint = '/ffmpeg-info';
  static const String trimVideoEndpoint = '/trim-video';
  
  // URL completi
  static String get healthUrl => '$baseUrl$healthEndpoint';
  static String get ffmpegInfoUrl => '$baseUrl$ffmpegInfoEndpoint';
  static String get trimVideoUrl => '$baseUrl$trimVideoEndpoint';
  
  // Configurazione per debug
  static bool get isDebugMode => const bool.fromEnvironment('dart.vm.product') == false;
  
  // Logging
  static bool get enableLogging => isDebugMode;
} 