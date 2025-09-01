class CloudflareConfig {
  // Configurazione per l'API Cloudflare
  static const String apiToken = 'WqUFx6CcsU1WdzLmhiLsphw7XcRHGHo2o7xOkFIK'; // Token reale fornito
  static const String accountId = '3cd9209da4d0a20e311d486fc37f1a71'; // Account ID corretto
  static const String kvNamespaceId = 'd7d6c20e2cde409ea14edf731af17804'; // ID namespace KV Facebook
  
  // URL base per l'API Cloudflare
  static const String apiBaseUrl = 'https://api.cloudflare.com/client/v4';
  
  // Headers comuni per le richieste API
  static Map<String, String> get headers => {
    'Authorization': 'Bearer $apiToken',
    'Content-Type': 'application/json',
  };
} 