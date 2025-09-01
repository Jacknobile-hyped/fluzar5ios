import 'package:flutter/material.dart';
import '../pages/upload_video_page.dart';

class NavigationService {
  static final NavigationService _instance = NavigationService._internal();
  factory NavigationService() => _instance;
  NavigationService._internal();

  // Variabili globali per i dati del draft
  static Map<String, dynamic>? _draftData;
  static String? _draftId;

  // Metodo per impostare i dati del draft
  static void setDraftData(Map<String, dynamic>? draftData, String? draftId) {
    _draftData = draftData;
    _draftId = draftId;
  }

  // Metodo per ottenere i dati del draft
  static Map<String, dynamic>? getDraftData() {
    return _draftData;
  }

  // Metodo per ottenere l'ID del draft
  static String? getDraftId() {
    return _draftId;
  }

  // Metodo per consumare i dati del draft (da chiamare dopo l'uso)
  static void consumeDraftData() {
    _draftData = null;
    _draftId = null;
  }

  // Metodo per navigare alla pagina upload con dati del draft
  static void navigateToUploadWithDraft(BuildContext context, Map<String, dynamic>? draftData, String? draftId) {
    // Imposta i dati del draft
    setDraftData(draftData, draftId);
    
    // Naviga alla pagina upload usando la route normale
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => UploadVideoPage(
          draftData: draftData,
          draftId: draftId,
        ),
      ),
    );
  }

  // Metodo per navigare alla pagina upload normale
  static void navigateToUpload(BuildContext context) {
    Navigator.pushNamed(context, '/upload');
  }
} 