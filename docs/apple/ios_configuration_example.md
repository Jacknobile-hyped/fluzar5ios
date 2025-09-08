# Configurazione iOS per Apple Sign In

## Info.plist Configuration

Aggiungi questa configurazione al file `ios/Runner/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Existing configurations -->
    
    <!-- URL Schemes for Apple Sign In -->
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
    
    <!-- Apple Sign In Capability -->
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>
    
    <!-- Other existing keys -->
</dict>
</plist>
```

## Entitlements Configuration

Crea o modifica il file `ios/Runner/Runner.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>
</dict>
</plist>
```

## Xcode Project Configuration

### 1. Aggiungere Capability

1. Apri il progetto in Xcode
2. Seleziona il target "Runner"
3. Vai su "Signing & Capabilities"
4. Clicca "+ Capability"
5. Aggiungi "Sign In with Apple"

### 2. Configurare Bundle Identifier

Assicurati che il Bundle Identifier sia:
- Identico a quello configurato in Apple Developer Console
- Identico a quello configurato in Firebase Console

### 3. Configurare Team

1. Seleziona il Team corretto
2. Verifica che il provisioning profile sia valido
3. Assicurati che l'app sia registrata in Apple Developer Console

## Firebase Configuration

### google-services.json (Android)

```json
{
  "project_info": {
    "project_number": "YOUR_PROJECT_NUMBER",
    "project_id": "YOUR_PROJECT_ID"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "YOUR_MOBILE_SDK_APP_ID",
        "android_client_info": {
          "package_name": "com.yourapp.package"
        }
      },
      "oauth_client": [
        {
          "client_id": "YOUR_WEB_CLIENT_ID",
          "client_type": 3
        }
      ]
    }
  ]
}
```

### GoogleService-Info.plist (iOS)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CLIENT_ID</key>
    <string>YOUR_IOS_CLIENT_ID</string>
    <key>REVERSED_CLIENT_ID</key>
    <string>YOUR_REVERSED_CLIENT_ID</string>
    <key>API_KEY</key>
    <string>YOUR_API_KEY</string>
    <key>GCM_SENDER_ID</key>
    <string>YOUR_SENDER_ID</string>
    <key>PLIST_VERSION</key>
    <string>1</string>
    <key>BUNDLE_ID</key>
    <string>com.yourapp.bundle</string>
    <key>PROJECT_ID</key>
    <string>YOUR_PROJECT_ID</string>
    <key>STORAGE_BUCKET</key>
    <string>YOUR_STORAGE_BUCKET</string>
    <key>IS_ADS_ENABLED</key>
    <false/>
    <key>IS_ANALYTICS_ENABLED</key>
    <false/>
    <key>IS_APPINVITE_ENABLED</key>
    <true/>
    <key>IS_GCM_ENABLED</key>
    <true/>
    <key>IS_SIGNIN_ENABLED</key>
    <true/>
    <key>GOOGLE_APP_ID</key>
    <string>YOUR_GOOGLE_APP_ID</string>
</dict>
</plist>
```

## Testing Checklist

### Pre-Test Requirements

- [ ] Dispositivo iOS fisico (non simulatore)
- [ ] Account Apple con 2FA abilitato
- [ ] Utente loggato in iCloud
- [ ] App configurata correttamente in Apple Developer Console
- [ ] Firebase configurato con Apple provider
- [ ] Bundle ID corretto in tutti i file di configurazione

### Test Steps

1. [ ] Avvia l'app su dispositivo iOS
2. [ ] Naviga alla schermata di login
3. [ ] Tocca "Continue with Apple"
4. [ ] Completa il flusso di autenticazione Apple
5. [ ] Verifica che l'utente sia creato in Firebase Console
6. [ ] Verifica che l'utente possa accedere all'app
7. [ ] Testa il logout e nuovo accesso

### Error Scenarios

1. [ ] Test con utente che cancella l'accesso
2. [ ] Test con utente che non ha 2FA abilitato
3. [ ] Test con utente non loggato in iCloud
4. [ ] Test con connessione di rete instabile

## Common Issues and Solutions

### Issue: "Sign in with Apple not available"

**Possible Causes:**
- App not properly configured in Apple Developer Console
- Service ID not configured correctly
- Firebase not configured with correct Apple provider settings

**Solutions:**
1. Verify app configuration in Apple Developer Console
2. Check Service ID configuration
3. Verify Firebase Apple provider settings
4. Ensure all certificates and provisioning profiles are valid

### Issue: "Invalid credentials"

**Possible Causes:**
- Incorrect private key
- Wrong Key ID
- Wrong Team ID
- Wrong Service ID

**Solutions:**
1. Verify private key content (should be without header/footer)
2. Check Key ID matches the one in Apple Developer Console
3. Verify Team ID is correct
4. Ensure Service ID matches Firebase configuration

### Issue: App crashes during sign in

**Possible Causes:**
- Running on simulator instead of physical device
- User not logged into iCloud
- Missing entitlements
- Incorrect bundle identifier

**Solutions:**
1. Test on physical iOS device
2. Ensure user is logged into iCloud
3. Verify entitlements are properly configured
4. Check bundle identifier matches Apple Developer Console
