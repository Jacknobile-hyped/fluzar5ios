import 'dart:convert';
import 'package:http/http.dart' as http;

class TikTokService {
  static const String kvNamespaceId = '79900865b055482eb0d7d798a634c378';
  static const String accountId = '3cd9209da4d0a20e311d486fc37f1a71';
  static const String apiToken = 'WqUFx6CcsU1WdzLmhiLsphw7XcRHGHo2o7xOkFIK';
  static const String apiBaseUrl = 'https://api.cloudflare.com/client/v4';

  // Metodo per eliminare un post TikTok dal KV basandosi su scheduledTime e userId
  Future<bool> deleteTikTokScheduledPost(int scheduledTime, String userId) async {
    try {
      print('Tentativo di eliminazione del post TikTok con scheduledTime: $scheduledTime e userId: $userId');
      // Ottieni tutte le chiavi dal KV
      final listResponse = await http.get(
        Uri.parse('$apiBaseUrl/accounts/$accountId/storage/kv/namespaces/$kvNamespaceId/keys'),
        headers: {
          'Authorization': 'Bearer $apiToken',
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
          Uri.parse('$apiBaseUrl/accounts/$accountId/storage/kv/namespaces/$kvNamespaceId/values/$keyName'),
          headers: {
            'Authorization': 'Bearer $apiToken',
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
        print('Nessun post TikTok trovato con scheduledTime: $scheduledTime e userId: $userId');
        return false;
      }
      // Elimina la chiave trovata
      final deleteResponse = await http.delete(
        Uri.parse('$apiBaseUrl/accounts/$accountId/storage/kv/namespaces/$kvNamespaceId/values/$targetKey'),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
      );
      if (deleteResponse.statusCode == 200) {
        print('Post TikTok eliminato con successo dal KV: $targetKey');
        return true;
      } else {
        print('Errore durante l\'eliminazione della chiave $targetKey: ${deleteResponse.statusCode} - ${deleteResponse.body}');
        return false;
      }
    } catch (e) {
      print('Eccezione durante l\'eliminazione del post TikTok: $e');
      return false;
    }
  }
} 