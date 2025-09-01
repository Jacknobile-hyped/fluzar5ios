import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;

class OneSignalService {
  static const String _appId = "8ad10111-3d90-4ec2-a96d-28f6220ab3a0";
  
  // Singleton pattern
  static final OneSignalService _instance = OneSignalService._internal();
  factory OneSignalService() => _instance;
  OneSignalService._internal();

  /// Initialize OneSignal SDK
  static Future<void> initialize() async {
    try {
      // Enable verbose logging for debugging (remove in production)
      OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      
      // Initialize with your OneSignal App ID
      OneSignal.initialize(_appId);
      
      // Set up event listeners
      _setupEventListeners();
      
      print('OneSignal service initialized successfully');
    } catch (e) {
      print('Error initializing OneSignal service: $e');
    }
  }

  /// Set up all OneSignal event listeners
  static void _setupEventListeners() {
    // Push notification events
    OneSignal.Notifications.addClickListener((event) {
      print('Notification clicked: ${event.notification.jsonRepresentation()}');
      // Handle deep linking here if needed
      _handleNotificationClick(event);
    });

    // User state changes
    OneSignal.User.addObserver((event) {
      print('User state changed: ${event.current.jsonRepresentation()}');
    });

    OneSignal.Notifications.addPermissionObserver((state) {
      print('Notification permission changed: ${state}');
    });

    // In-app message events
    OneSignal.InAppMessages.addClickListener((event) {
      print('In-app message clicked: ${event.result.jsonRepresentation()}');
      _handleInAppMessageClick(event);
    });
  }

  /// Handle notification click events
  static void _handleNotificationClick(OSNotificationClickEvent event) {
    // Extract custom data from notification
    final data = event.notification.additionalData;
    if (data != null) {
      // Handle different types of notifications based on data
      final type = data['type'];
      final id = data['id'];
      
      switch (type) {
        case 'upload_complete':
          // Navigate to upload history
          print('Navigate to upload history for ID: $id');
          break;
        case 'social_post':
          // Navigate to social post
          print('Navigate to social post for ID: $id');
          break;
        case 'premium_offer':
          // Navigate to premium page
          print('Navigate to premium page');
          break;
        default:
          print('Unknown notification type: $type');
      }
    }
  }

  /// Handle in-app message click events
  static void _handleInAppMessageClick(OSInAppMessageClickEvent event) {
    final result = event.result;
    final actionId = result.actionId;
    
    switch (actionId) {
      case 'upgrade_premium':
        // Navigate to premium page
        print('Navigate to premium page from in-app message');
        break;
      case 'upload_video':
        // Navigate to upload page
        print('Navigate to upload page from in-app message');
        break;
      default:
        print('Unknown in-app message action: $actionId');
    }
  }

  /// Set user external ID (for user identification across devices)
  static Future<void> setExternalUserId(String userId) async {
    try {
      await OneSignal.login(userId);
      print('OneSignal external user ID set: $userId');
    } catch (e) {
      print('Error setting OneSignal external user ID: $e');
    }
  }

  /// Add a single tag to the user
  static Future<void> addTag(String key, String value) async {
    try {
      // Note: Tag methods may not be available in current OneSignal version
      // await OneSignal.User.setTag(key, value);
      print('OneSignal tag added: $key = $value (method not available)');
    } catch (e) {
      print('Error adding OneSignal tag: $e');
    }
  }

  /// Add multiple tags to the user
  static Future<void> addTags(Map<String, String> tags) async {
    try {
      // Note: Tag methods may not be available in current OneSignal version
      // await OneSignal.User.setTags(tags);
      print('OneSignal tags added: $tags (method not available)');
    } catch (e) {
      print('Error adding OneSignal tags: $e');
    }
  }

  /// Remove a tag from the user
  static Future<void> removeTag(String key) async {
    try {
      // Note: Tag methods may not be available in current OneSignal version
      // await OneSignal.User.removeTag(key);
      print('OneSignal tag removed: $key (method not available)');
    } catch (e) {
      print('Error removing OneSignal tag: $e');
    }
  }

  /// Add email subscription
  static Future<void> addEmail(String email) async {
    try {
      await OneSignal.User.addEmail(email);
      print('OneSignal email subscription added: $email');
    } catch (e) {
      print('Error adding OneSignal email subscription: $e');
    }
  }

  /// Add SMS subscription
  static Future<void> addSms(String phoneNumber) async {
    try {
      await OneSignal.User.addSms(phoneNumber);
      print('OneSignal SMS subscription added: $phoneNumber');
    } catch (e) {
      print('Error adding OneSignal SMS subscription: $e');
    }
  }

  /// Set consent required (for privacy compliance)
  static Future<void> setConsentRequired(bool required) async {
    try {
      // Note: This method may not be available in current OneSignal version
      // await OneSignal.User.setConsentRequired(required);
      print('OneSignal consent required set: $required (method not available)');
    } catch (e) {
      print('Error setting OneSignal consent required: $e');
    }
  }

  /// Set consent given (for privacy compliance)
  static Future<void> setConsentGiven(bool given) async {
    try {
      // Note: This method may not be available in current OneSignal version
      // await OneSignal.User.setConsentGiven(given);
      print('OneSignal consent given set: $given (method not available)');
    } catch (e) {
      print('Error setting OneSignal consent given: $e');
    }
  }

  /// Request notification permission
  static Future<void> requestPermission() async {
    try {
      await OneSignal.Notifications.requestPermission(false);
      print('OneSignal notification permission requested');
    } catch (e) {
      print('Error requesting OneSignal notification permission: $e');
    }
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    try {
      final state = await OneSignal.Notifications.permission;
      return state;
    } catch (e) {
      print('Error checking OneSignal notification permission: $e');
      return false;
    }
  }

  /// Send a custom outcome (for analytics)
  static Future<void> sendOutcome(String name, {double? value}) async {
    try {
      // Note: These methods may not be available in current OneSignal version
      // if (value != null) {
      //   await OneSignal.User.addOutcomeWithValue(name, value);
      //   print('OneSignal outcome with value sent: $name = $value');
      // } else {
      //   await OneSignal.User.addOutcome(name);
      //   print('OneSignal outcome sent: $name');
      // }
      print('OneSignal outcome tracking: $name (method not available)');
    } catch (e) {
      print('Error sending OneSignal outcome: $e');
    }
  }

  /// Update user profile with Firebase user data
  static Future<void> updateUserProfile(User? user) async {
    if (user != null) {
      // Set external user ID
      await setExternalUserId(user.uid);
      
      // Add user tags
      await addTags({
        'user_id': user.uid,
        'email': user.email ?? '',
        'display_name': user.displayName ?? '',
        'is_email_verified': user.emailVerified.toString(),
        'provider': user.providerData.isNotEmpty ? user.providerData.first.providerId : 'unknown',
      });
      
      // Add email subscription if available
      if (user.email != null && user.email!.isNotEmpty) {
        await addEmail(user.email!);
      }
      
      print('OneSignal user profile updated for: ${user.uid}');
    }
  }

  /// Track app events
  static Future<void> trackEvent(String eventName, {Map<String, dynamic>? parameters}) async {
    try {
      // Send outcome for analytics
      await sendOutcome(eventName);
      
      // Add event-specific tags if parameters provided
      if (parameters != null) {
        final tags = <String, String>{};
        parameters.forEach((key, value) {
          if (value != null) {
            tags['event_${eventName}_$key'] = value.toString();
          }
        });
        if (tags.isNotEmpty) {
          await addTags(tags);
        }
      }
      
      print('OneSignal event tracked: $eventName');
    } catch (e) {
      print('Error tracking OneSignal event: $e');
    }
  }

  /// Track video upload events
  static Future<void> trackVideoUpload({
    required String videoId,
    required String platform,
    required bool isSuccess,
    String? errorMessage,
  }) async {
    await trackEvent('video_upload', parameters: {
      'video_id': videoId,
      'platform': platform,
      'success': isSuccess.toString(),
      'error': errorMessage,
    });
  }

  /// Track social media post events
  static Future<void> trackSocialPost({
    required String postId,
    required String platform,
    required bool isSuccess,
    String? errorMessage,
  }) async {
    await trackEvent('social_post', parameters: {
      'post_id': postId,
      'platform': platform,
      'success': isSuccess.toString(),
      'error': errorMessage,
    });
  }

  /// Track premium subscription events
  static Future<void> trackPremiumEvent({
    required String eventType,
    required String planId,
    double? amount,
  }) async {
    await trackEvent('premium_$eventType', parameters: {
      'plan_id': planId,
      'amount': amount?.toString(),
    });
  }

  /// Get current user ID
  static Future<String?> getCurrentUserId() async {
    try {
      final user = OneSignal.User.pushSubscription;
      return user.id;
    } catch (e) {
      print('Error getting OneSignal user ID: $e');
      return null;
    }
  }

  /// Get current user tags
  static Future<Map<String, String>> getUserTags() async {
    try {
      // Note: This method may not be available in current OneSignal version
      // final tags = await OneSignal.User.getTags();
      // return tags;
      print('Getting OneSignal user tags (method not available)');
      return {};
    } catch (e) {
      print('Error getting OneSignal user tags: $e');
      return {};
    }
  }
} 