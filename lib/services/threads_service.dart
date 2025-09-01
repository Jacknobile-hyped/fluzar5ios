import 'dart:convert';
import 'package:http/http.dart' as http;

class ThreadsService {
  static const String kvNamespaceId = '469f43ea90d641abb767e1c52920331f';
  static const String accountId = '3cd9209da4d0a20e311d486fc37f1a71';
  static const String apiToken = 'WqUFx6CcsU1WdzLmhiLsphw7XcRHGHo2o7xOkFIK';
  static const String apiBaseUrl = 'https://api.cloudflare.com/client/v4';

  // Metodo per eliminare un post Threads dal KV basandosi su scheduledTime e accountId
  Future<bool> deleteThreadsScheduledPost(int scheduledTime, String threadsAccountId) async {
    try {
      print('Tentativo di eliminazione del post Threads con scheduledTime: $scheduledTime e threadsAccountId: $threadsAccountId');
      // Ottieni tutte le chiavi dal KV usando l'accountId di Cloudflare fisso
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
      
      // Cerca la chiave che corrisponde al scheduledTime e threadsAccountId
      for (final key in keys) {
        final keyName = key['name'] as String?;
        if (keyName != null && keyName.startsWith('posts:')) {
          try {
            final getResponse = await http.get(
              Uri.parse('$apiBaseUrl/accounts/$accountId/storage/kv/namespaces/$kvNamespaceId/values/$keyName'),
              headers: {
                'Authorization': 'Bearer $apiToken',
                'Content-Type': 'application/json',
              },
            );
            if (getResponse.statusCode == 200) {
              final postData = json.decode(getResponse.body);
              final postScheduledTime = postData['scheduledTime'] as int?;
              final postAccountId = postData['accountId'] as String?;
              
              if (postScheduledTime == scheduledTime && postAccountId == threadsAccountId) {
                targetKey = keyName;
                print('Chiave trovata: $targetKey');
                break;
              }
            }
          } catch (e) {
            print('Errore nel recupero del post $keyName: $e');
            continue;
          }
        }
      }
      
      if (targetKey == null) {
        print('Nessun post trovato con scheduledTime: $scheduledTime e threadsAccountId: $threadsAccountId');
        return false;
      }
      
      // Elimina il post dal KV usando l'accountId di Cloudflare fisso
      final deleteResponse = await http.delete(
        Uri.parse('$apiBaseUrl/accounts/$accountId/storage/kv/namespaces/$kvNamespaceId/values/$targetKey'),
        headers: {
          'Authorization': 'Bearer $apiToken',
          'Content-Type': 'application/json',
        },
      );
      
      if (deleteResponse.statusCode == 200) {
        print('Post Threads eliminato con successo dal KV');
        return true;
      } else {
        print('Errore nell\'eliminazione del post dal KV: ${deleteResponse.statusCode} - ${deleteResponse.body}');
        return false;
      }
    } catch (e) {
      print('Errore durante l\'eliminazione del post Threads: $e');
      return false;
    }
  }
} 