# Configurazione Cloudflare API per l'eliminazione dei post Facebook

## Panoramica
Questo sistema permette di eliminare i post di Facebook programmati dal Cloudflare KV storage per evitare la pubblicazione automatica.

## Configurazione

### 1. Ottenere il Token API di Cloudflare

1. Vai su [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Vai su "My Profile" > "API Tokens"
3. Clicca "Create Token"
4. Seleziona "Custom token"
5. Configura i permessi:
   - **Account**: Impostazioni account (Read)
   - **Account**: Archiviazione KV Workers (Edit)
   - **Zone**: Impostazioni DNS (Read)
6. Configura le risorse:
   - **Account**: Include > Specific account > `d7d6c20e2cde409ea14edf731af17804`
   - **Zone**: Include > All zones
7. Clicca "Continue to summary" e poi "Create Token"
8. Copia il token generato

### 2. Configurare il Token nel Codice

1. Apri il file `viralyst/lib/services/cloudflare_config.dart`
2. Sostituisci `YOUR_CLOUDFLARE_API_TOKEN` con il token reale ottenuto

```dart
static const String apiToken = 'il_tuo_token_reale_qui';
```

### 3. Verificare la Configurazione

- **Account ID**: `d7d6c20e2cde409ea14edf731af17804` (già configurato)
- **KV Namespace**: `SCHEDULED_FACEBOOK` (già configurato)
- **API Base URL**: `https://api.cloudflare.com/client/v4` (già configurato)

## Funzionalità

### Eliminazione per scheduled_time e userId
Il sistema cerca nel KV tutti i post e trova quello con lo stesso `scheduled_time` E `userId` del post da eliminare. Questo garantisce che:
- Non vengano eliminati post di altri utenti che potrebbero avere lo stesso timestamp
- L'eliminazione sia sicura e specifica per l'utente corrente

### Eliminazione per chiave specifica
Se conosci la chiave specifica del post nel KV, puoi usare il metodo `deleteFacebookScheduledPostByKey()`.

## Sicurezza

- Il token API ha permessi limitati solo al KV storage
- Le richieste sono autenticate tramite Bearer token
- **Protezione multi-utente**: L'eliminazione verifica sia `scheduled_time` che `userId`
- Tutti gli errori sono gestiti e loggati

## Troubleshooting

### Errore 401 - Unauthorized
- Verifica che il token API sia corretto
- Controlla che il token abbia i permessi necessari

### Errore 404 - Not Found
- Verifica che l'Account ID sia corretto
- Controlla che il KV namespace esista

### Errore di Connessione
- Verifica la connessione internet
- Controlla che l'API Cloudflare sia raggiungibile 