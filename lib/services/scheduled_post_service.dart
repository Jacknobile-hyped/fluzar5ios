import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:async';

class ScheduledPostService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  Timer? _checkTimer;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  void startCheckingScheduledPosts() {
    // Check every minute
    _checkTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkAndPublishScheduledPosts();
    });
  }

  void stopCheckingScheduledPosts() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  Future<void> _checkAndPublishScheduledPosts() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) return;

      final now = DateTime.now().millisecondsSinceEpoch;
      
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .get();

      if (!snapshot.exists) return;

      final data = snapshot.value as Map<dynamic, dynamic>;
      
      for (var entry in data.entries) {
        final post = entry.value as Map<dynamic, dynamic>;
        if (post['status'] == 'scheduled' && 
            post['scheduled_time'] != null && 
            post['scheduled_time'] <= now) {
          
          // Call Cloud Function to publish the post
          try {
            final callable = _functions.httpsCallable('publishScheduledPost');
            await callable.call({
              'postId': entry.key,
              'userId': currentUser.uid,
              'postData': post,
            });

            // Verifica se il post ha un video su YouTube
            bool isYouTubePost = false;
            String? youtubeVideoId;
            
            if (post['platforms'] != null) {
              final platforms = post['platforms'] as List<dynamic>;
              isYouTubePost = platforms.contains('YouTube');
              youtubeVideoId = post['youtube_video_id'] as String?;
            }

            // Update post status to published
            final updates = {
              'status': 'published',
              'published_at': now,
              if (post['from_scheduler'] == true) 'from_scheduler': true,
            };
            
            await _database
                .child('users')
                .child('users')
                .child(currentUser.uid)
                .child('videos')
                .child(entry.key)
                .update(updates);
                
            print('Post ${entry.key} pubblicato con successo');
          } catch (e) {
            print('Error publishing scheduled post: $e');
            // Update post status to failed
            await _database
                .child('users')
                .child('users')
                .child(currentUser.uid)
                .child('videos')
                .child(entry.key)
                .update({
                  'status': 'scheduled',
                  'publish_error': e.toString(),
                  'last_publish_attempt': now,
                });
          }
        }
      }
    } catch (e) {
      print('Error checking scheduled posts: $e');
    }
  }
} 