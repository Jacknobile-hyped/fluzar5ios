import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EmailService {
  static const String _resendApiKey = 're_7du3UXn5_4CNyFBLpGDnZHb9JgFADH2wz';
  static const String _fromEmail = 'no-reply@fluzar.com';
  static const String _resendApiUrl = 'https://api.resend.com/emails';

  /// Crea una chiave sicura per Firebase usando base64
  static String _createSafeKey(String email) {
    return base64Url.encode(utf8.encode(email)).replaceAll('=', '');
  }

  /// Genera un codice di verifica a 6 cifre
  static String generateVerificationCode() {
    final random = Random();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }

  /// Salva il codice di verifica nel database Firebase
  static Future<void> saveVerificationCode(String email, String code) async {
    try {
      final database = FirebaseDatabase.instance;
      final now = DateTime.now();
      final expiresAt = now.add(Duration(minutes: 10)); // Il codice scade dopo 10 minuti
      final emailKey = _createSafeKey(email);
      
      print('DEBUG: Tentativo di salvare codice per email: $email');
      print('DEBUG: Email key generata: $emailKey');
      print('DEBUG: Codice generato: $code');
      
      // Verifica lo stato di autenticazione
      final currentUser = FirebaseAuth.instance.currentUser;
      print('DEBUG: Utente autenticato: ${currentUser != null}');
      if (currentUser != null) {
        print('DEBUG: UID utente: ${currentUser.uid}');
      }
      
      final verificationData = {
        'code': code,
        'email': email,
        'created_at': now.millisecondsSinceEpoch,
        'expires_at': expiresAt.millisecondsSinceEpoch,
        'used': false,
      };
      
      print('DEBUG: Dati da salvare: $verificationData');
      
      await database
          .ref()
          .child('verification_codes')
          .child(emailKey)
          .set(verificationData);

      print('Codice di verifica salvato con successo per: $email');
    } catch (e) {
      print('Errore dettagliato nel salvare il codice di verifica: $e');
      print('Stack trace: ${StackTrace.current}');
      throw Exception('Errore nel salvare il codice di verifica: $e');
    }
  }

  /// Invia email di verifica tramite Resend
  static Future<bool> sendVerificationEmail(String email, String code) async {
    try {
      final response = await http.post(
        Uri.parse(_resendApiUrl),
        headers: {
          'Authorization': 'Bearer $_resendApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from': 'Fluzar <$_fromEmail>',
          'to': [email],
          'subject': 'Code: $code - Verify your Fluzar account',
          'html': _buildVerificationEmailHtml(code),
        }),
      );

      if (response.statusCode == 200) {
        print('Email di verifica inviata con successo a: $email');
        return true;
      } else {
        print('Errore nell\'invio email: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Errore nell\'invio email di verifica: $e');
      return false;
    }
  }

  /// Verifica il codice inserito dall'utente
  static Future<bool> verifyCode(String email, String code) async {
    try {
      final database = FirebaseDatabase.instance;
      final emailKey = _createSafeKey(email);
      
      final snapshot = await database
          .ref()
          .child('verification_codes')
          .child(emailKey)
          .get();

      if (!snapshot.exists) {
        print('Nessun codice trovato per: $email');
        return false;
      }

      final data = snapshot.value as Map<dynamic, dynamic>;
      final savedCode = data['code'] as String?;
      final expiresAt = data['expires_at'] as int?;
      final used = data['used'] as bool? ?? false;

      if (used) {
        print('Codice già utilizzato per: $email');
        return false;
      }

      if (expiresAt != null && DateTime.now().millisecondsSinceEpoch > expiresAt) {
        print('Codice scaduto per: $email');
        return false;
      }

      if (savedCode == code) {
        // Marca il codice come utilizzato
        await database
            .ref()
            .child('verification_codes')
            .child(emailKey)
            .update({'used': true});
        
        print('Codice verificato con successo per: $email');
        return true;
      } else {
        print('Codice non valido per: $email');
        return false;
      }
    } catch (e) {
      print('Errore nella verifica del codice: $e');
      return false;
    }
  }

  /// Rimuove il codice di verifica dal database
  static Future<void> removeVerificationCode(String email) async {
    try {
      final database = FirebaseDatabase.instance;
      final emailKey = _createSafeKey(email);
      
      await database
          .ref()
          .child('verification_codes')
          .child(emailKey)
          .remove();
      
      print('Codice di verifica rimosso per: $email');
    } catch (e) {
      print('Errore nella rimozione del codice: $e');
    }
  }

  /// Genera e invia il codice di verifica
  static Future<bool> generateAndSendVerificationCode(String email) async {
    try {
      final code = generateVerificationCode();
      await saveVerificationCode(email, code);
      return await sendVerificationEmail(email, code);
    } catch (e) {
      print('Errore nella generazione e invio del codice: $e');
      return false;
    }
  }

  /// Verifica se un'email è già registrata
  static Future<bool> isEmailRegistered(String email) async {
    try {
      final database = FirebaseDatabase.instance;
      final emailKey = _createSafeKey(email);
      
      final snapshot = await database
          .ref()
          .child('registered_emails')
          .child(emailKey)
          .get();

      return snapshot.exists;
    } catch (e) {
      print('Errore nella verifica dell\'email registrata: $e');
      return false;
    }
  }

  /// Salva le informazioni dell'utente registrato
  static Future<void> saveRegisteredUser(String email, String uid, Map<String, dynamic> userData) async {
    try {
      final database = FirebaseDatabase.instance;
      final emailKey = _createSafeKey(email);
      final now = DateTime.now();
      
      await database
          .ref()
          .child('registered_emails')
          .child(emailKey)
          .set({
        'email': email,
        'uid': uid,
        'registered_at': now.millisecondsSinceEpoch,
        'is_verified': true,
      });

      print('Utente registrato salvato per: $email');
    } catch (e) {
      print('Errore nel salvare l\'utente registrato: $e');
      throw Exception('Errore nel salvare l\'utente registrato');
    }
  }

  /// Ottiene le informazioni di un utente registrato
  static Future<Map<String, dynamic>?> getRegisteredUser(String email) async {
    try {
      final database = FirebaseDatabase.instance;
      final emailKey = _createSafeKey(email);
      
      final snapshot = await database
          .ref()
          .child('registered_emails')
          .child(emailKey)
          .get();

      if (snapshot.exists) {
        return Map<String, dynamic>.from(snapshot.value as Map);
      }
      return null;
    } catch (e) {
      print('Errore nel recuperare l\'utente registrato: $e');
      return null;
    }
  }

  /// Verifica se un'email è già registrata e verificata
  static Future<bool> isEmailVerified(String email) async {
    try {
      final userData = await getRegisteredUser(email);
      if (userData != null) {
        return userData['is_verified'] == true;
      }
      return false;
    } catch (e) {
      print('Errore nella verifica dello stato dell\'email: $e');
      return false;
    }
  }

  /// Invia email di benvenuto tramite Resend
  static Future<bool> sendWelcomeEmail(String email, String userName) async {
    try {
      final response = await http.post(
        Uri.parse(_resendApiUrl),
        headers: {
          'Authorization': 'Bearer $_resendApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'from': 'Fluzar <$_fromEmail>',
          'to': [email],
          'subject': 'Welcome to Fluzar! 🎉',
          'html': _buildWelcomeEmailHtml(userName),
        }),
      );

      if (response.statusCode == 200) {
        print('Email di benvenuto inviata con successo a: $email');
        return true;
      } else {
        print('Errore nell\'invio email di benvenuto: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Errore nell\'invio email di benvenuto: $e');
      return false;
    }
  }

  /// Template HTML per l'email di benvenuto
  static String _buildWelcomeEmailHtml(String userName) {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Welcome to Fluzar!</title>
        <style>
            @import url('https://fonts.googleapis.com/css2?family=Ethnocentric&display=swap');
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                margin: 0;
                padding: 0;
                background-color: #f4f4f4;
            }
            .container {
                max-width: 600px;
                margin: 0 auto;
                background-color: #ffffff;
                border-radius: 10px;
                overflow: hidden;
                box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            }
            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                padding: 40px 20px;
                text-align: center;
                color: white;
            }
            .header h1 {
                margin: 0;
                font-size: 28px;
                font-weight: bold;
            }
            .content {
                padding: 40px 30px;
                text-align: center;
            }
            .welcome-message {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                font-size: 24px;
                font-weight: bold;
                padding: 20px;
                border-radius: 10px;
                margin: 30px 0;
                text-align: center;
            }
            .message {
                color: #333;
                font-size: 16px;
                line-height: 1.6;
                margin-bottom: 20px;
            }
            .features {
                background-color: #f8f9fa;
                border-radius: 8px;
                padding: 20px;
                margin: 20px 0;
                text-align: left;
            }
            .feature-item {
                display: flex;
                align-items: center;
                margin-bottom: 15px;
                color: #333;
                font-size: 14px;
            }
            .feature-icon {
                margin-right: 12px;
                font-size: 18px;
            }
            .cta-button {
                display: inline-block;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                text-decoration: none;
                padding: 15px 30px;
                border-radius: 25px;
                font-weight: bold;
                font-size: 16px;
                margin: 20px 0;
                transition: transform 0.2s ease;
            }
            .cta-button:hover {
                transform: translateY(-2px);
            }
            .footer {
                background-color: #f8f9fa;
                padding: 20px;
                text-align: center;
                color: #666;
                font-size: 12px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1 style="font-family: 'Ethnocentric', Arial, sans-serif; font-size: 24px;">Fluzar</h1>
                <p>Welcome aboard! 🚀</p>
            </div>
            <div class="content">
                <h2 style="color: #333; margin-bottom: 20px;">Welcome to Fluzar!</h2>
                <div class="welcome-message">
                    Hello ${userName.isNotEmpty ? userName : 'there'}! 👋
                </div>
                <p class="message">
                    Thank you for joining Fluzar! You're now part of a community of creators 
                    who are revolutionizing the way content is shared across social media platforms.
                </p>
                <p class="message">
                    Get ready to discover amazing features that will help you grow your online presence 
                    and reach more people with your content.
                </p>
                
                <div class="features">
                    <h3 style="color: #333; margin-bottom: 15px;">What you can do with Fluzar:</h3>
                    <div class="feature-item">
                        <span class="feature-icon">✅</span>
                        <span>Upload and share videos across multiple social platforms</span>
                    </div>
                    <div class="feature-item">
                        <span class="feature-icon">✅</span>
                        <span>Schedule posts for optimal engagement times</span>
                    </div>
                    <div class="feature-item">
                        <span class="feature-icon">✅</span>
                        <span>Track your content performance and analytics</span>
                    </div>
                    <div class="feature-item">
                        <span class="feature-icon">✅</span>
                        <span>Connect all your social media accounts in one place</span>
                        </div>
                    <div class="feature-item">
                        <span class="feature-icon">✅</span>
                        <span>Earn credits and rewards for your activity</span>
                    </div>
                </div>
                
                <p class="message">
                    Start exploring Fluzar today and take your content to the next level!
                </p>
                
                <a href="https://fluzar.com/deep-redirect.html" class="cta-button" style="color: white; text-decoration: none;">
                    Start Creating Now! 🎬
                </a>
                
                <p class="message" style="font-size: 14px; color: #666;">
                    If you have any questions or need help getting started, 
                    don't hesitate to reach out to our support team.
                </p>
            </div>
            <div class="footer">
                <p>Welcome to the Fluzar family! We're excited to see what you'll create.</p>
                <p>&copy; 2025 Fluzar. All rights reserved.</p>
            </div>
        </div>
    </body>
    </html>
    ''';
  }

  /// Template HTML per l'email di verifica
  static String _buildVerificationEmailHtml(String code) {
    return '''
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Verify your Fluzar account</title>
        <style>
            @import url('https://fonts.googleapis.com/css2?family=Ethnocentric&display=swap');
            body {
                font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                margin: 0;
                padding: 0;
                background-color: #f4f4f4;
            }
            .container {
                max-width: 600px;
                margin: 0 auto;
                background-color: #ffffff;
                border-radius: 10px;
                overflow: hidden;
                box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            }
            .header {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                padding: 40px 20px;
                text-align: center;
                color: white;
            }
            .header h1 {
                margin: 0;
                font-size: 28px;
                font-weight: bold;
            }
            .content {
                padding: 40px 30px;
                text-align: center;
            }
            .verification-code {
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                color: white;
                font-size: 32px;
                font-weight: bold;
                padding: 20px;
                border-radius: 10px;
                margin: 30px 0;
                letter-spacing: 8px;
                text-align: center;
                cursor: pointer;
                user-select: all;
                transition: transform 0.2s ease;
            }
            .verification-code:hover {
                transform: scale(1.02);
            }
            .verification-code:active {
                transform: scale(0.98);
            }
            .message {
                color: #333;
                font-size: 16px;
                line-height: 1.6;
                margin-bottom: 20px;
            }
            .warning {
                background-color: #fff3cd;
                border: 1px solid #ffeaa7;
                border-radius: 8px;
                padding: 15px;
                margin: 20px 0;
                color: #856404;
                font-size: 14px;
            }
            .footer {
                background-color: #f8f9fa;
                padding: 20px;
                text-align: center;
                color: #666;
                font-size: 12px;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header">
                <h1 style="font-family: 'Ethnocentric', Arial, sans-serif; font-size: 24px;">Fluzar</h1>
                <p>Verify your account</p>
            </div>
            <div class="content">
                <h2 style="color: #333; margin-bottom: 20px;">Welcome to Fluzar!</h2>
                <p class="message">
                    Thank you for signing up! To complete your registration, 
                    enter the following verification code in the app:
                </p>
                <div class="verification-code" onclick="copyToClipboard()" title="Click to copy">
                    $code
                </div>
                <p class="message">
                    This code will expire in 10 minutes for security reasons.
                </p>
                <div class="warning">
                    <strong>Important:</strong> Do not share this code with anyone. 
                    The Fluzar team will never ask you to provide this code.
                </div>
            </div>
            <div class="footer">
                <p>If you didn't request this code, please ignore this email.</p>
                <p>&copy; 2025 Fluzar. All rights reserved.</p>
            </div>
        </div>
        
        <script>
            function copyToClipboard() {
                const codeElement = document.querySelector('.verification-code');
                const text = codeElement.textContent.trim();
                
                if (navigator.clipboard && window.isSecureContext) {
                    navigator.clipboard.writeText(text).then(() => {
                        showCopyFeedback();
                    }).catch(err => {
                        fallbackCopyTextToClipboard(text);
                    });
                } else {
                    fallbackCopyTextToClipboard(text);
                }
            }
            
            function fallbackCopyTextToClipboard(text) {
                const textArea = document.createElement("textarea");
                textArea.value = text;
                textArea.style.top = "0";
                textArea.style.left = "0";
                textArea.style.position = "fixed";
                document.body.appendChild(textArea);
                textArea.focus();
                textArea.select();
                
                try {
                    const successful = document.execCommand('copy');
                    if (successful) {
                        showCopyFeedback();
                    }
                } catch (err) {
                    console.error('Fallback: Oops, unable to copy', err);
                }
                
                document.body.removeChild(textArea);
            }
            
            function showCopyFeedback() {
                const codeElement = document.querySelector('.verification-code');
                const originalText = codeElement.textContent;
                const originalBackground = codeElement.style.background;
                
                codeElement.textContent = 'Copied!';
                codeElement.style.background = '#28a745';
                
                setTimeout(() => {
                    codeElement.textContent = originalText;
                    codeElement.style.background = originalBackground;
                }, 1000);
            }
        </script>
    </body>
    </html>
    ''';
  }
} 