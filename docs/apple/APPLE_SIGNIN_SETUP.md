# Configurazione Apple Sign In per Flutter

## Prerequisiti

1. **Apple Developer Account**: Devi essere membro del programma Apple Developer
2. **Firebase Project**: Il progetto Firebase deve essere configurato
3. **iOS App**: L'app deve essere configurata per iOS

## Configurazione Apple Developer Console

### 1. Abilitare Sign in with Apple

1. Vai su [Apple Developer Console](https://developer.apple.com/account/)
2. Vai su "Certificates, Identifiers & Profiles"
3. Seleziona "Identifiers" e poi la tua App ID
4. Abilita "Sign In with Apple" capability
5. Salva le modifiche

### 2. Configurare Service ID

1. Vai su "Identifiers" e crea un nuovo "Services ID"
2. Inserisci un identificatore (es: `com.yourapp.signin`)
3. Abilita "Sign In with Apple"
4. Configura i domini e URL di ritorno:
   - **Primary App ID**: Seleziona la tua App ID
   - **Website URLs**: Aggiungi il tuo dominio
   - **Return URLs**: `https://YOUR_FIREBASE_PROJECT_ID.firebaseapp.com/__/auth/handler`

### 3. Creare Private Key

1. Vai su "Keys" e crea una nuova chiave
2. Abilita "Sign In with Apple"
3. Scarica il file `.p8` (lo userai in Firebase)
4. Annota il **Key ID** e il **Team ID**

## Configurazione Firebase Console

### 1. Abilitare Apple Provider

1. Vai su [Firebase Console](https://console.firebase.google.com/)
2. Seleziona il tuo progetto
3. Vai su "Authentication" > "Sign-in method"
4. Abilita "Apple" provider
5. Inserisci i dati richiesti:
   - **Service ID**: L'identificatore del Service ID creato
   - **Apple Team ID**: Il Team ID dal tuo account Apple Developer
   - **Key ID**: L'ID della chiave privata
   - **Private Key**: Il contenuto del file `.p8` (senza header/footer)

### 2. Configurare OAuth Code Flow

1. Nella sezione "OAuth Code Flow Configuration"
2. Inserisci:
   - **Apple Team ID**: Il tuo Team ID
   - **Private Key**: Il contenuto del file `.p8`
   - **Key ID**: L'ID della chiave privata

## Configurazione iOS (Info.plist)

Aggiungi al file `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>REVERSED_CLIENT_ID</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

## Configurazione Android (opzionale)

Per Android, aggiungi al file `android/app/build.gradle`:

```gradle
android {
    compileSdkVersion 34
    
    defaultConfig {
        minSdkVersion 21
        targetSdkVersion 34
    }
}
```

## Test dell'Implementazione

### Requisiti per il Test

1. **Dispositivo iOS fisico** (non simulatore)
2. **Account Apple con 2FA abilitato**
3. **Utente loggato in iCloud**

### Test Steps

1. Avvia l'app su dispositivo iOS
2. Tocca "Continue with Apple"
3. Completa il flusso di autenticazione Apple
4. Verifica che l'utente sia creato in Firebase
5. Verifica che l'utente possa accedere all'app

## Gestione Errori

### Errori Comuni

1. **`AuthorizationErrorCode.canceled`**: L'utente ha annullato l'accesso
2. **`AuthorizationErrorCode.failed`**: Errore durante l'autenticazione
3. **`AuthorizationErrorCode.invalidResponse`**: Risposta non valida da Apple
4. **`AuthorizationErrorCode.notHandled`**: L'accesso non è stato gestito
5. **`AuthorizationErrorCode.unknown`**: Errore sconosciuto

### Errori Firebase

1. **`invalid-credential`**: Credenziali Apple non valide
2. **`network-request-failed`**: Errore di rete
3. **`user-disabled`**: Account utente disabilitato

## Note Importanti

1. **Email Anonima**: Apple può fornire email anonime (`@privaterelay.appleid.com`)
2. **Nome Utente**: Apple fornisce il nome completo solo al primo accesso
3. **Privacy**: Rispetta le policy Apple per i dati anonimi
4. **Testing**: I test devono essere fatti su dispositivi fisici iOS

## Troubleshooting

### Problema: "Sign in with Apple not available"

**Soluzione**: Verifica che:
- L'app sia configurata correttamente in Apple Developer Console
- Il Service ID sia configurato correttamente
- Firebase sia configurato con i dati corretti

### Problema: "Invalid credentials"

**Soluzione**: Verifica che:
- La chiave privata sia corretta
- Il Key ID sia corretto
- Il Team ID sia corretto
- Il Service ID sia corretto

### Problema: App crash durante l'accesso

**Soluzione**: Verifica che:
- Il dispositivo sia fisico (non simulatore)
- L'utente sia loggato in iCloud
- L'app abbia le capability corrette
