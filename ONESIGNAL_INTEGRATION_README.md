# OneSignal Integration for Viralyst

This document describes the OneSignal push notification integration implemented in the Viralyst Flutter app.

## Overview

OneSignal has been integrated to provide push notifications, in-app messaging, and user analytics for the Viralyst app. The integration includes user identification, event tracking, and automated notification handling.

## Configuration

### App ID
- **OneSignal App ID**: `8ad10111-3d90-4ec2-a96d-28f6220ab3a0`
- This ID is configured in the OneSignal dashboard and used throughout the app

### Dependencies
- **Package**: `onesignal_flutter: ^5.1.2`
- Added to `pubspec.yaml` under dependencies

## Implementation Details

### 1. Service Layer (`lib/services/onesignal_service.dart`)

The `OneSignalService` class provides a centralized interface for all OneSignal functionality:

#### Key Features:
- **User Identification**: Links OneSignal users with Firebase user IDs
- **Event Tracking**: Tracks app events, video uploads, and social media posts
- **Tag Management**: Manages user tags for segmentation
- **Analytics**: Sends custom outcomes for analytics
- **Privacy Compliance**: Handles user consent and data collection

#### Main Methods:
- `initialize()`: Initializes OneSignal SDK with event listeners
- `updateUserProfile()`: Updates user profile with Firebase data
- `trackEvent()`: Tracks custom events with parameters
- `trackVideoUpload()`: Tracks video upload events
- `trackSocialPost()`: Tracks social media posting events
- `trackPremiumEvent()`: Tracks premium subscription events

### 2. Main App Integration (`lib/main.dart`)

OneSignal is initialized in the main app startup:

```dart
// Initialize OneSignal
try {
  await OneSignalService.initialize();
  print('OneSignal inizializzato con successo');
} catch (e) {
  print('Errore nell\'inizializzazione di OneSignal: $e');
}
```

### 3. User Authentication Integration

When users authenticate, their OneSignal profile is updated:

```dart
// In MainScreen._setupOneSignalUser()
await OneSignalService.updateUserProfile(_currentUser);
await OneSignalService.addTag('is_premium', _isPremium?.toString() ?? 'false');
```

### 4. Event Tracking

#### Video Upload Events
Tracked in `upload_confirmation_page.dart`:
- Successful uploads
- Failed uploads
- Draft saves
- Platform-specific uploads

#### Premium Subscription Events
Tracked in `payment_success_page.dart`:
- Subscription started
- Plan type
- Subscription status

#### App Usage Events
- App opens
- User interactions
- Feature usage

## Event Types Tracked

### 1. Video Upload Events
- **Event**: `video_upload`
- **Parameters**: 
  - `video_id`: Unique video identifier
  - `platform`: Target platforms (comma-separated)
  - `success`: Boolean success status
  - `error`: Error message (if failed)

### 2. Social Media Post Events
- **Event**: `social_post`
- **Parameters**:
  - `post_id`: Post identifier
  - `platform`: Social media platform
  - `success`: Boolean success status
  - `error`: Error message (if failed)

### 3. Premium Events
- **Event**: `premium_subscription_started`
- **Parameters**:
  - `plan_id`: Subscription plan type
  - `amount`: Subscription amount

### 4. App Events
- **Event**: `app_open`
- **Parameters**:
  - `user_id`: Firebase user ID
  - `is_premium`: Premium status

## User Tags

The following tags are automatically managed:

### User Profile Tags
- `user_id`: Firebase user ID
- `email`: User email address
- `display_name`: User display name
- `is_email_verified`: Email verification status
- `provider`: Authentication provider

### Subscription Tags
- `is_premium`: Premium subscription status
- `subscription_status`: Current subscription status
- `plan_type`: Subscription plan type

### Event Tags
- `event_video_upload_*`: Video upload event parameters
- `event_social_post_*`: Social post event parameters
- `event_premium_*`: Premium event parameters

## Notification Handling

### Push Notification Events
- **Click Events**: Handled for deep linking and navigation
- **Foreground Events**: Custom handling for in-app notifications
- **Permission Changes**: Tracked for analytics

### In-App Message Events
- **Click Events**: Handled for user interactions
- **Lifecycle Events**: Tracked for engagement analytics

## Privacy & Compliance

### Consent Management
- `setConsentRequired()`: Controls data collection
- `setConsentGiven()`: Enables data collection after consent

### Data Collection
- User identification data
- App usage events
- Feature interaction data
- Subscription information

## Testing

### 1. Verify Installation
1. Run the app on a physical device
2. Check console logs for "OneSignal inizializzato con successo"
3. Verify user profile is created in OneSignal dashboard

### 2. Test Event Tracking
1. Upload a video to any platform
2. Check OneSignal dashboard for `video_upload` event
3. Verify user tags are updated

### 3. Test Notifications
1. Send a test notification from OneSignal dashboard
2. Verify notification is received on device
3. Test notification click handling

## Dashboard Configuration

### 1. OneSignal Dashboard Setup
1. Log into OneSignal dashboard
2. Navigate to your app (ID: `8ad10111-3d90-4ec2-a96d-28f6220ab3a0`)
3. Configure notification settings
4. Set up segments based on user tags

### 2. Segments
Create segments based on:
- Premium users: `is_premium = true`
- Active uploaders: `event_video_upload_count > 0`
- Platform users: `event_social_post_platform = [platform]`

### 3. Automated Messages
Set up automated messages for:
- New user onboarding
- Premium feature promotion
- Upload completion notifications
- Subscription reminders

## Troubleshooting

### Common Issues

1. **OneSignal not initializing**
   - Check internet connection
   - Verify App ID is correct
   - Check console logs for errors

2. **Events not tracking**
   - Verify user is authenticated
   - Check OneSignal service is initialized
   - Review console logs for tracking errors

3. **Notifications not received**
   - Check notification permissions
   - Verify device is registered
   - Test with OneSignal dashboard

### Debug Logs
Enable verbose logging for debugging:
```dart
OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
```

## Future Enhancements

### Planned Features
1. **Advanced Segmentation**: More sophisticated user segments
2. **A/B Testing**: Test different notification strategies
3. **Personalization**: Dynamic content based on user behavior
4. **Analytics Dashboard**: Custom analytics integration
5. **Automated Workflows**: Trigger notifications based on user actions

### Integration Opportunities
1. **Email Marketing**: Integrate with email campaigns
2. **CRM Integration**: Connect with customer data
3. **Analytics Platforms**: Export data to external analytics
4. **Marketing Automation**: Automated marketing workflows

## Support

For OneSignal-specific issues:
- OneSignal Documentation: https://documentation.onesignal.com/
- OneSignal Support: support@onesignal.com

For app-specific integration issues:
- Check console logs for detailed error messages
- Review this documentation for implementation details
- Test with OneSignal dashboard tools 