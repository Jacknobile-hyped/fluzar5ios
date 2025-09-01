import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'video_trimmer_config.dart';

class VideoTrimmerService {
  
  /// Verifica se il server è disponibile
  static Future<bool> isServerAvailable() async {
    try {
      final response = await http.get(Uri.parse(VideoTrimmerConfig.healthUrl))
          .timeout(VideoTrimmerConfig.requestTimeout);
      return response.statusCode == 200;
    } catch (e) {
      if (VideoTrimmerConfig.enableLogging) {
        print('Server non disponibile: $e');
      }
      return false;
    }
  }
  
  /// Ottiene informazioni su FFmpeg dal server
  static Future<Map<String, dynamic>?> getFfmpegInfo() async {
    try {
      final response = await http.get(Uri.parse(VideoTrimmerConfig.ffmpegInfoUrl))
          .timeout(VideoTrimmerConfig.requestTimeout);
      
      if (response.statusCode == 200) {
        return {
          'ffmpegVersion': response.body.split('"ffmpegVersion":"')[1].split('"')[0],
          'path': response.body.split('"path":"')[1].split('"')[0],
        };
      }
      return null;
    } catch (e) {
      if (VideoTrimmerConfig.enableLogging) {
        print('Errore nel recupero info FFmpeg: $e');
      }
      return null;
    }
  }
  
  /// Invia un video al server per il trimming
  static Future<File?> trimVideo({
    required File videoFile,
    required String ffmpegCommand,
    Function(double)? onProgress,
  }) async {
    try {
      // Verifica la dimensione del file
      final fileSize = await videoFile.length();
      if (fileSize > VideoTrimmerConfig.maxFileSizeBytes) {
        throw Exception('File troppo grande. Dimensione massima: ${VideoTrimmerConfig.maxFileSizeBytes ~/ (1024 * 1024)}MB');
      }
      
      // Verifica che il server sia disponibile
      if (!await isServerAvailable()) {
        throw Exception('Server di trimming non disponibile');
      }
      
      // Prepara la richiesta multipart
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(VideoTrimmerConfig.trimVideoUrl),
      );
      
      // Aggiungi il file video
      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          videoFile.path,
        ),
      );
      
      // Aggiungi il comando FFmpeg
      request.fields['ffmpegCommand'] = ffmpegCommand;
      
      // Simula progresso
      onProgress?.call(0.1);
      
      // Invia la richiesta
      final streamedResponse = await request.send().timeout(VideoTrimmerConfig.processingTimeout);
      
      onProgress?.call(0.5);
      
      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        if (VideoTrimmerConfig.enableLogging) {
          print('Errore server: ${streamedResponse.statusCode}');
          print('Risposta server: $errorBody');
        }
        throw Exception('Errore server: ${streamedResponse.statusCode} - $errorBody');
      }
      
      onProgress?.call(0.8);
      
      // Salva il file di risposta
      final tempDir = Directory.systemTemp;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputFileName = 'trimmed_video_$timestamp.mp4';
      final outputFile = File(path.join(tempDir.path, outputFileName));
      
      final fileStream = outputFile.openWrite();
      await streamedResponse.stream.pipe(fileStream);
      await fileStream.close();
      
      onProgress?.call(1.0);
      
      return outputFile;
      
    } catch (e) {
      if (VideoTrimmerConfig.enableLogging) {
        print('Errore durante il trimming del video: $e');
      }
      rethrow;
    }
  }
  
  /// Genera un comando FFmpeg per il trimming basato sui parametri del video editor
  static String generateTrimCommand({
    required Duration startTime,
    required Duration endTime,
    required Duration videoDuration,
    String? outputFormat = 'mp4',
  }) {
    final startSeconds = startTime.inMilliseconds / 1000.0;
    final durationSeconds = (endTime - startTime).inMilliseconds / 1000.0;
    
    // Comando base per il trimming
    return '-i INPUT_PATH -ss $startSeconds -t $durationSeconds -c copy OUTPUT_PATH';
  }
  
  /// Genera un comando FFmpeg per l'esportazione con effetti
  static String generateExportCommand({
    required Duration startTime,
    required Duration endTime,
    required Duration videoDuration,
    String? outputFormat = 'mp4',
    Map<String, dynamic>? effects,
  }) {
    final startSeconds = startTime.inMilliseconds / 1000.0;
    final durationSeconds = (endTime - startTime).inMilliseconds / 1000.0;
    
    String command = '-i INPUT_PATH -ss $startSeconds -t $durationSeconds';
    
    // Aggiungi effetti se specificati
    if (effects != null) {
      if (effects['rotation'] != null) {
        final rotation = effects['rotation'] as int;
        if (rotation == 90) {
          command += ' -vf "transpose=1"';
        } else if (rotation == 180) {
          command += ' -vf "transpose=1,transpose=1"';
        } else if (rotation == 270) {
          command += ' -vf "transpose=2"';
        }
      }
      
      if (effects['scale'] != null) {
        final scale = effects['scale'] as double;
        command += ' -vf "scale=iw*$scale:ih*$scale"';
      }
    }
    
    command += ' -c:v libx264 -preset fast -crf 23 OUTPUT_PATH';
    
    return command;
  }
  

} 