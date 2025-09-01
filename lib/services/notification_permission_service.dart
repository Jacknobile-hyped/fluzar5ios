import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationPermissionService {
  static final NotificationPermissionService _instance = NotificationPermissionService._internal();
  factory NotificationPermissionService() => _instance;
  NotificationPermissionService._internal();

  /// Check if push notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    try {
      final state = await OneSignal.Notifications.permission;
      return state;
    } catch (e) {
      print('Error checking OneSignal notification permission: $e');
      return false;
    }
  }

  /// Request notification permission and update Firebase
  static Future<bool> requestPermission() async {
    try {
      // Request permission from OneSignal
      await OneSignal.Notifications.requestPermission(true);
      
      // Get the current permission status
      final currentStatus = await OneSignal.Notifications.permission;
      
      // Update Firebase database
      await _updateNotificationPermissionInFirebase(currentStatus);
      
      return currentStatus;
    } catch (e) {
      print('Error requesting notification permission: $e');
      return false;
    }
  }

  /// Update notification permission status in Firebase
  static Future<void> _updateNotificationPermissionInFirebase(bool enabled) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance;
        final userRef = database
            .ref()
            .child('users')
            .child('users')
            .child(user.uid);
        
        // Update the database
        await userRef.update({
          'push_notifications_enabled': enabled,
        });
        
        print('Updated notification permission in Firebase: $enabled');
      }
    } catch (e) {
      print('Error updating Firebase: $e');
    }
  }

  /// Get notification permission status from Firebase
  static Future<bool?> getNotificationPermissionFromFirebase() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance;
        final userRef = database
            .ref()
            .child('users')
            .child('users')
            .child(user.uid);
        
        final snapshot = await userRef.child('push_notifications_enabled').get();
        
        if (snapshot.exists) {
          return (snapshot.value as bool?) ?? false;
        }
      }
      return null;
    } catch (e) {
      print('Error getting notification permission from Firebase: $e');
      return null;
    }
  }

  /// Check if we should show the permission dialog
  static bool shouldShowPermissionDialog(bool? firebaseStatus, bool dialogAlreadyShown) {
    // Don't show if already shown or if user has already granted permission
    if (dialogAlreadyShown || firebaseStatus == true) return false;
    
    // Show if status is explicitly false (user denied) or null (not set)
    return firebaseStatus == false || firebaseStatus == null;
  }
}
