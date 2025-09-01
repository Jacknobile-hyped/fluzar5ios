# Sistema Notifiche Push - Viralyst

## Panoramica

Questo sistema gestisce le notifiche push per l'app Viralyst, utilizzando OneSignal come provider e Firebase per il salvataggio dello stato dei permessi.

## Componenti

### 1. NotificationPermissionDialog (`lib/widgets/notification_permission_dialog.dart`)
- Popup minimal e elegante per richiedere i permessi delle notifiche
- Design responsive con animazioni fluide
- Supporta sia modalità chiara che scura
- Pulsanti "Enable" e "Maybe Later"

### 2. NotificationPermissionService (`lib/services/notification_permission_service.dart`)
- Servizio centralizzato per gestire i permessi delle notifiche
- Metodi per richiedere, controllare e aggiornare i permessi
- Integrazione con OneSignal e Firebase
- Logica per determinare quando mostrare il popup

### 3. Integrazione nelle Pagine
- **HomePage**: Mostra il popup per utenti non premium
- **PremiumHomePage**: Mostra il popup per utenti premium
- Controllo automatico dello stato `push_notifications_enabled` in Firebase

## Funzionalità

### Controllo Automatico
- Il popup si mostra automaticamente quando `push_notifications_enabled` è `false` o `null`
- Evita di mostrare il popup se già visualizzato o se i permessi sono già concessi
- Delay di 500ms per evitare conflitti con altri popup

### Gestione Permessi
- Richiesta permessi tramite OneSignal (mostra popup di sistema iOS/Android)
- Aggiornamento automatico del database Firebase
- Gestione degli errori e fallback

### UI/UX
- Design minimal e moderno con effetto glass opaco
- Effetto vetro semi-trasparente con BackdropFilter
- Animazioni fluide (fade in, scale)
- Supporto per tema chiaro/scuro
- Messaggi chiari e persuasivi
- Stile coerente con la top bar della AboutPage

## Configurazione

### iOS (Info.plist)
```xml
<key>NSUserNotificationUsageDescription</key>
<string>This app needs notification access to send you updates about your content performance, engagement metrics, and trending opportunities.</string>
```

### Android (AndroidManifest.xml)
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.VIBRATE" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

## Flusso di Funzionamento

1. **Caricamento Pagina**: Controlla lo stato `push_notifications_enabled` in Firebase
2. **Controllo Condizioni**: Verifica se mostrare il popup (non mostrato + permessi negati/null)
3. **Mostra Popup**: Popup personalizzato con messaggio persuasivo
4. **Richiesta Permessi**: Se l'utente clicca "Enable", richiede permessi tramite OneSignal
5. **Aggiornamento Database**: Aggiorna Firebase con il nuovo stato
6. **Gestione Risultato**: Aggiorna l'UI in base al risultato

## Messaggi

### Titolo
"Stay Updated!"

### Descrizione
"Enable push notifications to get real-time updates about your content performance, engagement metrics, and trending opportunities."

### Pulsanti
- **Enable**: Richiede i permessi e aggiorna Firebase
- **Maybe Later**: Chiude il popup senza richiedere permessi

## Testing

### Modalità Test
- Delay ridotto a 500ms per testing rapido
- Popup sempre visibile per utenti premium (per testing)
- Log dettagliati per debugging

### Verifica
1. Avvia l'app con utente nuovo (senza `push_notifications_enabled` in Firebase)
2. Naviga alla HomePage o PremiumHomePage
3. Il popup dovrebbe apparire dopo 500ms
4. Clicca "Enable" per testare la richiesta permessi
5. Verifica l'aggiornamento in Firebase

## Note Tecniche

- Utilizza OneSignal per la gestione delle notifiche push
- Firebase Realtime Database per il salvataggio dello stato
- Animazioni personalizzate con `AnimationController`
- Gestione dello stato con `setState`
- Controlli di sicurezza per evitare popup multipli

## Effetto Glass

### Caratteristiche
- **BackdropFilter**: Blur di 10px per effetto vetro smerigliato
- **Colori semi-trasparenti**: Bianco con opacità variabile (0.15-0.25)
- **Bordi sottili**: Bianco con opacità 0.2-0.4
- **Ombre multiple**: Ombra esterna per profondità + ombra interna per vetro
- **Gradiente sottile**: Transizione di opacità per effetto tridimensionale

### Implementazione
```dart
ClipRRect(
  borderRadius: BorderRadius.circular(24),
  child: BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
    child: Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        border: Border.all(color: Colors.white.withOpacity(0.2)),
        boxShadow: [/* ombre multiple */],
        gradient: LinearGradient(/* gradiente sottile */),
      ),
    ),
  ),
)
```

## Troubleshooting

### Popup non si mostra
- Verifica che `push_notifications_enabled` sia `false` o `null` in Firebase
- Controlla che `_notificationDialogShown` sia `false`
- Verifica i log per errori

### Errore richiesta permessi
- Controlla la configurazione OneSignal
- Verifica i permessi nel manifest/Info.plist
- Controlla i log per dettagli sull'errore

### Aggiornamento Firebase fallisce
- Verifica la connessione a Firebase
- Controlla i permessi dell'utente
- Verifica la struttura del database
