import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class DeepLinkService {
  /// Callback globale per completare il flusso OAuth2 Twitter
  static Function(String code, String? state)? twitterCallback;

  /// Gestisce i deep link ricevuti dall'app
  static void handleDeepLink(String link, BuildContext context) {
    print('[DEEP LINK SERVICE] 🔍 Deep link ricevuto: $link');
    
    if (link.startsWith('viralyst://subscription-cancelled')) {
      print('[DEEP LINK SERVICE] 📱 Gestione subscription-cancelled');
      _handleSubscriptionCancelled(context);
    } else if (link.startsWith('viralyst://subscription-updated')) {
      print('[DEEP LINK SERVICE] 📱 Gestione subscription-updated');
      _handleSubscriptionUpdated(context);
    } else if (link.startsWith('viralyst://subscription-resumed')) {
      print('[DEEP LINK SERVICE] 📱 Gestione subscription-resumed');
      _handleSubscriptionResumed(context);
    } else if (link.startsWith('viralyst://trends')) {
      print('[DEEP LINK SERVICE] 📱 Gestione trends');
      _handleTrendsDeepLink(context);
    } else if (link.startsWith('viralyst://history')) {
      print('[DEEP LINK SERVICE] 📱 Gestione history');
      _handleHistoryDeepLink(context);
    } else if (link.startsWith('viralyst://twitter-auth')) {
      print('[DEEP LINK SERVICE] 🐦 Gestione Twitter Auth deep link');
      _handleTwitterAuthDeepLink(link, context);
    } else {
      print('[DEEP LINK SERVICE] ❌ Deep link non riconosciuto: $link');
    }
  }

  /// Gestisce la cancellazione dell'abbonamento
  static void _handleSubscriptionCancelled(BuildContext context) {
    print('Abbonamento cancellato tramite Customer Portal');
    
    // Aggiorna lo stato dell'utente nel database
    _updateUserSubscriptionStatus('cancelled');
  }

  /// Gestisce l'aggiornamento dell'abbonamento
  static void _handleSubscriptionUpdated(BuildContext context) {
    print('Abbonamento aggiornato tramite Customer Portal');
    
    // Aggiorna lo stato dell'utente nel database
    _updateUserSubscriptionStatus('active');
    
    // Mostra un messaggio all'utente
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Il tuo abbonamento Premium è stato aggiornato con successo.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Gestisce la ripresa dell'abbonamento
  static void _handleSubscriptionResumed(BuildContext context) {
    print('Abbonamento ripreso tramite Customer Portal');
    
    // Aggiorna lo stato dell'utente nel database
    _updateUserSubscriptionStatus('active');
    
    // Mostra un messaggio all'utente
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Il tuo abbonamento Premium è stato riattivato con successo.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// Gestisce il deep link per la pagina trends
  static void _handleTrendsDeepLink(BuildContext context) {
    print('Deep link trends ricevuto');
    
    // Naviga alla pagina trends
    if (context.mounted) {
      Navigator.of(context).pushNamed('/trends');
    }
  }

  /// Gestisce il deep link per la pagina history
  static void _handleHistoryDeepLink(BuildContext context) {
    print('Deep link history ricevuto');
    
    // Naviga alla pagina history
    if (context.mounted) {
      Navigator.of(context).pushNamed('/history');
    }
  }

  /// Gestisce il deep link per Twitter OAuth2 callback
  static void _handleTwitterAuthDeepLink(String link, BuildContext context) {
    print('[DEEP LINK SERVICE] 🐦 Deep link Twitter Auth ricevuto: $link');
    final uri = Uri.parse(link);
    print('[DEEP LINK SERVICE] 🔍 URI parsato: $uri');
    print('[DEEP LINK SERVICE] 🔍 Query parameters: ${uri.queryParameters}');
    
    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    
    print('[DEEP LINK SERVICE] 🔍 Code estratto: ${code != null ? '${code.substring(0, 8)}...' : 'null'}');
    print('[DEEP LINK SERVICE] 🔍 State estratto: $state');
    
    if (code != null) {
      print('[DEEP LINK SERVICE] ✅ Code trovato, procedo con il callback');
      _findAndCallTwitterCallback(context, code, state);
    } else {
      print('[DEEP LINK SERVICE] ❌ Code non trovato nel deep link Twitter Auth');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nel deep link Twitter Auth: code mancante.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Cerca la TwitterPage attiva e chiama il callback OAuth2
  static void _findAndCallTwitterCallback(BuildContext context, String code, String? state) {
    print('[DEEP LINK SERVICE] 🎯 _findAndCallTwitterCallback chiamata');
    print('[DEEP LINK SERVICE] 🔍 Code: ${code.substring(0, 8)}...');
    print('[DEEP LINK SERVICE] 🔍 State: $state');
    print('[DEEP LINK SERVICE] 🔍 Callback registrato: ${twitterCallback != null ? 'SÌ' : 'NO'}');
    
    // Usa il callback globale se disponibile
    if (twitterCallback != null) {
      print('[DEEP LINK SERVICE] ✅ Chiamando callback Twitter OAuth2...');
      try {
        twitterCallback!(code, state);
        print('[DEEP LINK SERVICE] ✅ Callback Twitter OAuth2 completato con successo!');
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Account Twitter connesso con successo!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } catch (e) {
        print('[DEEP LINK SERVICE] ❌ Errore nel callback Twitter OAuth2: $e');
        print('[DEEP LINK SERVICE] ❌ Stack trace: ${StackTrace.current}');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore durante la connessione: $e'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
    } else {
      print('[DEEP LINK SERVICE] ❌ Nessun callback Twitter registrato');
      print('[DEEP LINK SERVICE] ❌ TwitterPage potrebbe non essere attiva');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Twitter Auth completato! Torna alla pagina Twitter per vedere il risultato.'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// Aggiorna lo stato dell'abbonamento nel database
  static Future<void> _updateUserSubscriptionStatus(String status) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        
        // Aggiorna lo stato dell'abbonamento
        await database.child('users/users/${user.uid}/subscription/status').set(status);
        
        // Aggiorna il flag isPremium in base allo stato
        final isPremium = status == 'active' || status == 'trialing';
        await database.child('users/users/${user.uid}/isPremium').set(isPremium);
        
        print('Stato abbonamento aggiornato nel database: $status');
      }
    } catch (e) {
      print('Errore nell\'aggiornamento dello stato abbonamento: $e');
    }
  }

  /// Verifica se l'utente ha un abbonamento attivo
  static Future<bool> isUserPremium() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        final snapshot = await database.child('users/users/${user.uid}/isPremium').get();
        
        if (snapshot.exists) {
          return snapshot.value as bool;
        }
      }
      return false;
    } catch (e) {
      print('Errore nella verifica dello stato premium: $e');
      return false;
    }
  }
} 