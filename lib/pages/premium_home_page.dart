import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/tutorial_provider.dart';
import 'upload_video_page.dart';
import 'social/social_account_details_page.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'scheduled_posts_page.dart';
import 'scheduled_post_details_page.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'trends_page.dart';
import 'community_page.dart';
import 'package:lottie/lottie.dart';
import '../widgets/notification_permission_dialog.dart';
import '../services/notification_permission_service.dart';

class PremiumHomePage extends StatefulWidget {
  const PremiumHomePage({Key? key}) : super(key: key);

  @override
  PremiumHomePageState createState() => PremiumHomePageState();
}

class PremiumHomePageState extends State<PremiumHomePage> with TickerProviderStateMixin {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  bool _hasConnectedAccounts = false;
  bool _hasUploadedVideo = false;
  List<Map<String, dynamic>> _videos = [];
  List<Map<String, dynamic>> _socialAccounts = [];
  List<Map<String, dynamic>> _upcomingScheduledPosts = [];
  bool _isLoading = true;

  // Global keys for tutorial targets
  final GlobalKey _connectAccountsKey = GlobalKey(debugLabel: 'connectAccounts');
  final GlobalKey _uploadVideoKey = GlobalKey(debugLabel: 'uploadVideo');
  final GlobalKey _statsKey = GlobalKey(debugLabel: 'stats');

  int _userCredits = 0; // Per compatibilità con la ruota
  int _displayedCredits = 0;
  bool _isPremium = true; // Sempre true per questa pagina
  
  // Variable to track notification permission status
  bool? _pushNotificationsEnabled;
  bool _notificationDialogShown = false;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _loadSocialAccounts();
    _loadUpcomingScheduledPosts();
    _checkUserProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupTutorialKeys();
    });
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        _loadUpcomingScheduledPosts();
      } else {
        timer.cancel();
      }
    });
  }

  void _setupTutorialKeys() {
    if (!mounted) return;
    final tutorialProvider = Provider.of<TutorialProvider>(context, listen: false);
    tutorialProvider.setTargetKey(1, _connectAccountsKey);
    tutorialProvider.setTargetKey(2, _uploadVideoKey);
    tutorialProvider.setTargetKey(3, _statsKey);
  }

  Future<void> _checkUserProgress() async {
    if (_currentUser == null || !mounted) return;
    try {
      bool hasConnectedAccounts = false;
      final accountsSnapshot1 = await _database
          .child('users')
          .child(_currentUser.uid)
          .child('social_accounts')
          .get();
      if (!mounted) return;
      if (accountsSnapshot1.exists) {
        final accounts = accountsSnapshot1.value as Map<dynamic, dynamic>;
        hasConnectedAccounts = accounts.isNotEmpty;
      }
      if (!hasConnectedAccounts) {
        final accountsSnapshot2 = await _database
            .child('users')
            .child('users')
            .child(_currentUser.uid)
            .child('social_accounts')
            .get();
        if (!mounted) return;
        if (accountsSnapshot2.exists) {
          final accounts = accountsSnapshot2.value as Map<dynamic, dynamic>;
          hasConnectedAccounts = accounts.isNotEmpty;
        }
      }
      setState(() {
        _hasConnectedAccounts = hasConnectedAccounts;
      });
      final videosSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser.uid)
          .child('videos')
          .get();
      if (!mounted) return;
      bool hasPublishedVideo = false;
      if (videosSnapshot.exists) {
        final videos = videosSnapshot.value as Map<dynamic, dynamic>;
        if (videos.isNotEmpty) {
          videos.forEach((key, value) {
            if (value is Map && (value['status'] == 'published' || 
                (value['status'] == 'scheduled' && value['published_at'] != null))) {
              hasPublishedVideo = true;
            }
          });
        }
        setState(() {
          _hasUploadedVideo = hasPublishedVideo;
        });
      }
      
      // Check push notifications status
      try {
        final pushNotificationsSnapshot = await _database
            .child('users')
            .child('users')
            .child(_currentUser.uid)
            .child('push_notifications_enabled')
            .get();
            
        if (mounted) {
          bool? pushNotificationsEnabled;
          if (pushNotificationsSnapshot.exists) {
            pushNotificationsEnabled = (pushNotificationsSnapshot.value as bool?) ?? false;
          }
          
          setState(() {
            _pushNotificationsEnabled = pushNotificationsEnabled;
          });
          
          // Check for notification permission dialog
          _checkNotificationPermission();
        }
      } catch (e) {
        print('Error checking push notifications status: $e');
      }
    } catch (e) {
      print('Error checking user progress: $e');
    }
  }

  Future<void> _loadVideos() async {
    if (_currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final videosSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser.uid)
          .child('videos')
          .get();
      if (!mounted) return;
      if (videosSnapshot.exists) {
        final data = videosSnapshot.value as Map<dynamic, dynamic>;
        setState(() {
          _videos = data.entries.map((entry) {
            final videoData = entry.value as Map<dynamic, dynamic>;
            return {
              'id': entry.key,
              'title': videoData['title'] ?? '',
              'description': videoData['description'] ?? '',
              'duration': videoData['duration'] ?? '0:00',
              'uploadDate': _formatTimestamp(DateTime.fromMillisecondsSinceEpoch(videoData['timestamp'] ?? 0)),
              'status': videoData['status'] ?? 'published',
              'video_path': videoData['video_path'] ?? '',
              'thumbnail_path': videoData['thumbnail_path'] ?? '',
              'timestamp': videoData['timestamp'] ?? 0,
            };
          }).toList()
            ..sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
          _isLoading = false;
        });
      } else {
        setState(() {
          _videos = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading videos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadUpcomingScheduledPosts() async {
    if (_currentUser == null || !mounted) return;
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fifteenMinutesFromNow = now + (15 * 60 * 1000);
      final snapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .child('videos')
          .get();
      if (!snapshot.exists || !mounted) return;
      final data = snapshot.value as Map<dynamic, dynamic>;
      final upcomingPosts = data.entries.map((entry) {
        final post = entry.value as Map<dynamic, dynamic>;
        if (post['status'] != 'scheduled') return null;
        if (post['published_at'] != null) return null;
        final scheduledTime = post['scheduled_time'] as int?;
        if (scheduledTime == null || scheduledTime < now || scheduledTime > fifteenMinutesFromNow) return null;
        return {
          'id': entry.key.toString(),
          'scheduledTime': scheduledTime,
          'description': post['description']?.toString() ?? '',
          'title': post['title']?.toString() ?? '',
          'platforms': (post['platforms'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
          'thumbnail_path': post['thumbnail_path']?.toString() ?? '',
          'video_path': post['video_path']?.toString() ?? '',
          'accounts': Map<String, dynamic>.from(post['accounts'] as Map<dynamic, dynamic>? ?? {}),
          'status': 'scheduled',
          'timestamp': post['timestamp'] ?? DateTime.now().millisecondsSinceEpoch,
        };
      })
      .where((post) => post != null)
      .cast<Map<String, dynamic>>()
      .toList();
      upcomingPosts.sort((a, b) {
        final aTime = a['scheduledTime'] as int;
        final bTime = b['scheduledTime'] as int;
        return aTime.compareTo(bTime);
      });
      if (mounted) {
        setState(() {
          _upcomingScheduledPosts = upcomingPosts;
        });
      }
    } catch (e) {
      print('Error loading upcoming scheduled posts: $e');
    }
  }

  Future<void> _loadSocialAccounts() async {
    if (_currentUser == null || !mounted) return;

    try {
      // IMPORTANT: Twitter accounts are loaded ONLY from users/users/{uid}/social_accounts/twitter
      // to avoid duplicates from other paths, exactly like Threads
      List<Map<String, dynamic>> accountsList = [];
      Set<String> loadedAccountIds = {}; // Track loaded account IDs to prevent duplicates
      
      // STEP 1: Check direct structure under users/{uid}
      final userAccountsSnapshot = await _database
          .child('users')
          .child(_currentUser!.uid)
          .get();
          
      if (!mounted) return;
          
      if (userAccountsSnapshot.exists && userAccountsSnapshot.value is Map) {
        final userData = userAccountsSnapshot.value as Map<dynamic, dynamic>;
        
        // Extract Facebook accounts
        if (userData.containsKey('facebook') && userData['facebook'] is Map) {
          final accounts = userData['facebook'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            String uniqueId = 'facebook_$accountId';
            if (accountData is Map && 
                accountData['status'] == 'active' && 
                !loadedAccountIds.contains(uniqueId) &&
                accountData['profile_image_url'] != null &&
                accountData['profile_image_url'].toString().isNotEmpty) {
              
              loadedAccountIds.add(uniqueId);
              accountsList.add({
                'id': accountId,
                'platform': 'facebook',
                'display_name': accountData['name'] ?? accountData['display_name'] ?? '',
                'username': accountData['username'] ?? accountData['name'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
        }
        
        // Extract Instagram accounts
        if (userData.containsKey('instagram') && userData['instagram'] is Map) {
          final accounts = userData['instagram'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              accountsList.add({
                'id': accountId,
                'platform': 'instagram',
                'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                'username': accountData['username'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
        }
        
        // Extract Twitter accounts - REMOVED to avoid duplicates
        // Twitter accounts will be loaded ONLY from users/users/{uid}/social_accounts/twitter
        
        // Extract YouTube accounts
        if (userData.containsKey('youtube') && userData['youtube'] is Map) {
          final accounts = userData['youtube'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              accountsList.add({
                'id': accountId,
                'platform': 'youtube',
                'display_name': accountData['channel_name'] ?? '',
                'username': accountData['channel_name'] ?? '',
                'profile_image_url': accountData['thumbnail_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['subscriber_count'] ?? 0,
              });
            }
          });
        }
        
        // Extract Threads accounts
        if (userData.containsKey('threads') && userData['threads'] is Map) {
          final accounts = userData['threads'] as Map<dynamic, dynamic>;
          print('Found Threads accounts for user ${_currentUser!.uid}');
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              accountsList.add({
                'id': accountId,
                'platform': 'threads',
                'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                'username': accountData['username'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
          print('Loaded ${accounts.length} Threads accounts');
        }
        
        // Extract TikTok accounts (users/{uid}/tiktok)
        if (userData.containsKey('tiktok') && userData['tiktok'] is Map) {
          final accounts = userData['tiktok'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              accountsList.add({
                'id': accountId,
                'platform': 'tiktok',
                'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                'username': accountData['username'] ?? '',
                'profile_image_url': accountData['profile_image_url'] ?? '',
                'status': accountData['status'] ?? 'active',
                'followers_count': accountData['followers_count'] ?? 0,
              });
            }
          });
        }
      }
      
      // STEP 2: Check the nested 'users/users/uid' structure from the database
      final nestedUserSnapshot = await _database
          .child('users')
          .child('users')
          .child(_currentUser!.uid)
          .get();
          
      if (nestedUserSnapshot.exists && nestedUserSnapshot.value is Map) {
        final userData = nestedUserSnapshot.value as Map<dynamic, dynamic>;
        
        // REMOVED: User profile from users/users/{uid}/profile is no longer displayed
        // to avoid showing profile as a social account
        
        // Check for social_accounts node
        if (userData.containsKey('social_accounts') && userData['social_accounts'] is Map) {
          final socialAccounts = userData['social_accounts'] as Map<dynamic, dynamic>;
          
          // Process platform-specific accounts (excluding Twitter to avoid duplicates)
          ['facebook', 'instagram', 'youtube', 'threads', 'tiktok'].forEach((platform) {
            if (socialAccounts.containsKey(platform) && socialAccounts[platform] is Map) {
              final accounts = socialAccounts[platform] as Map<dynamic, dynamic>;
              accounts.forEach((accountId, accountData) {
                if (accountData is Map && accountData['status'] != 'inactive') {
                  // Check if this account is already in the list
                  bool alreadyExists = accountsList.any((existing) => 
                    existing['platform'] == platform && 
                    (existing['id'] == accountId || existing['username'] == accountData['username']));
                  
                  if (!alreadyExists) {
                  accountsList.add({
                    'id': accountId,
                    'platform': platform,
                    'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                    'username': accountData['username'] ?? '',
                    'profile_image_url': accountData['profile_image_url'] ?? '',
                    'status': accountData['status'] ?? 'active',
                    'followers_count': accountData['followers_count'] ?? 0,
                  });
                  }
                }
              });
            }
          });
          
          // Load Twitter accounts ONLY from users/users/{uid}/social_accounts/twitter (same as Threads)
          if (socialAccounts.containsKey('twitter') && socialAccounts['twitter'] is Map) {
            final twitterAccounts = socialAccounts['twitter'] as Map<dynamic, dynamic>;
            print('Found Twitter accounts in social_accounts for user ${_currentUser!.uid}');
            twitterAccounts.forEach((accountId, accountData) {
              if (accountData is Map && accountData['status'] == 'active') {
                // Check if this Twitter account is already in the list
                bool alreadyExists = accountsList.any((existing) => 
                  existing['platform'] == 'twitter' && 
                  (existing['id'] == accountId || existing['username'] == accountData['username']));
                
                if (!alreadyExists) {
                  accountsList.add({
                    'id': accountId,
                    'platform': 'twitter',
                    'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                    'username': accountData['username'] ?? '',
                    'profile_image_url': accountData['profile_image_url'] ?? '',
                    'status': accountData['status'] ?? 'active',
                    'followers_count': accountData['followers_count'] ?? 0,
                  });
                }
              }
            });
            print('Loaded ${twitterAccounts.length} Twitter accounts from social_accounts');
          }
        }
        
        // Also check platform-specific nodes (excluding Twitter to avoid duplicates)
        ['facebook', 'instagram', 'youtube', 'threads', 'tiktok'].forEach((platform) {
          if (userData.containsKey(platform) && userData[platform] is Map) {
            final accounts = userData[platform] as Map<dynamic, dynamic>;
              accounts.forEach((accountId, accountData) {
                if (accountData is Map && accountData['status'] != 'inactive') {
                // Check if this account is already in the list
                bool alreadyExists = accountsList.any((existing) => 
                  existing['platform'] == platform && 
                  (existing['id'] == accountId || existing['username'] == (accountData['username'] ?? '')));
                
                  if (!alreadyExists) {
                  Map<String, dynamic> newAccount = {
                      'id': accountId,
                      'platform': platform,
                    'status': accountData['status'] ?? 'active',
                  };
                  
                  // Platform-specific fields
                  if (platform == 'youtube') {
                    newAccount['display_name'] = accountData['channel_name'] ?? '';
                    newAccount['username'] = accountData['channel_name'] ?? '';
                    newAccount['profile_image_url'] = accountData['thumbnail_url'] ?? '';
                    newAccount['followers_count'] = accountData['subscriber_count'] ?? 0;
                  } else {
                    newAccount['display_name'] = accountData['display_name'] ?? accountData['username'] ?? '';
                    newAccount['username'] = accountData['username'] ?? '';
                    newAccount['profile_image_url'] = accountData['profile_image_url'] ?? '';
                    newAccount['followers_count'] = accountData['followers_count'] ?? 0;
                  }
                  
                  accountsList.add(newAccount);
                }
              }
            });
          }
        });
        
        // Extract TikTok accounts (users/users/{uid}/tiktok)
        if (userData.containsKey('tiktok') && userData['tiktok'] is Map) {
          final accounts = userData['tiktok'] as Map<dynamic, dynamic>;
          accounts.forEach((accountId, accountData) {
            if (accountData is Map && accountData['status'] == 'active') {
              // Check if this account is already in the list
              bool alreadyExists = accountsList.any((existing) =>
                existing['platform'] == 'tiktok' &&
                (existing['id'] == accountId || existing['username'] == (accountData['username'] ?? '')));
              if (!alreadyExists) {
                accountsList.add({
                  'id': accountId,
                  'platform': 'tiktok',
                      'display_name': accountData['display_name'] ?? accountData['username'] ?? '',
                      'username': accountData['username'] ?? '',
                      'profile_image_url': accountData['profile_image_url'] ?? '',
                      'status': accountData['status'] ?? 'active',
                      'followers_count': accountData['followers_count'] ?? 0,
                    });
                  }
                }
              });
            }
      }
      
      // STEP 3: Check social_accounts_index from databasefirebase.json (excluding Twitter to avoid duplicates)
      final indexSnapshot = await _database
          .child('social_accounts_index')
          .get();
      
      if (!mounted) return;
      
      if (indexSnapshot.exists && indexSnapshot.value is Map) {
        final indexData = indexSnapshot.value as Map<dynamic, dynamic>;
        
        // Process Threads accounts from the index structure (Twitter removed to avoid duplicates)
        if (indexData.containsKey('threads') && indexData['threads'] is Map) {
          // Similar implementation as Twitter could be added here...
        }
      }

      // Final filter to remove any accounts without required fields
      accountsList = accountsList.where((account) => 
        account['profile_image_url'] != null &&
        account['profile_image_url'].toString().isNotEmpty &&
        account['display_name'] != null &&
        account['display_name'].toString().isNotEmpty
      ).toList();

      // Custom sorting to prioritize Twitter and YouTube accounts
      accountsList.sort((a, b) {
        String platformA = (a['platform'] as String).toLowerCase();
        String platformB = (b['platform'] as String).toLowerCase();
        
        // Define priority order: Twitter, YouTube, TikTok, poi altri
        Map<String, int> priorityOrder = {
          'twitter': 1,
          'youtube': 2,
          'tiktok': 3,
          'instagram': 4,
          'facebook': 5,
          'threads': 6,
        };
        
        int priorityA = priorityOrder[platformA] ?? 999;
        int priorityB = priorityOrder[platformB] ?? 999;
        
        return priorityA.compareTo(priorityB);
      });

      if (mounted) {
        setState(() {
          _socialAccounts = accountsList;
        });
      }
      
      // Print debug info about accounts found
      print('Loaded ${accountsList.length} social accounts');
      for (var account in accountsList) {
        print('Account: ${account['platform']} - ${account['username']} (${account['display_name']})');
      }
      
    } catch (e) {
      print('Error loading social accounts: $e');
      if (mounted) {
        setState(() {
          _socialAccounts = [];
        });
      }
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else {
      return '${difference.inMinutes} minutes ago';
    }
  }

  // Method to check and show notification permission dialog
  void _checkNotificationPermission() {
    // Use the centralized service to check if we should show the dialog
    if (!NotificationPermissionService.shouldShowPermissionDialog(_pushNotificationsEnabled, _notificationDialogShown)) {
      // For testing, always show the dialog if not already shown
      if (!_notificationDialogShown) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _showNotificationPermissionDialog();
          }
        });
      }
      return;
    }
    
    // Show dialog after a delay to avoid conflicts with other popups
    // For testing, reduced delay to 500ms
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && NotificationPermissionService.shouldShowPermissionDialog(_pushNotificationsEnabled, _notificationDialogShown)) {
        _showNotificationPermissionDialog();
      }
    });
  }

  // Method to show the notification permission dialog
  void _showNotificationPermissionDialog() {
    if (_notificationDialogShown) return;
    
    setState(() {
      _notificationDialogShown = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return NotificationPermissionDialog();
      },
    ).then((permissionGranted) {
      // Update local state based on the result
      if (permissionGranted == true) {
        setState(() {
          _pushNotificationsEnabled = true;
        });
        print('Notification permission granted');
      } else {
        print('Notification permission skipped or denied');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: Theme.of(context).copyWith(
        brightness: theme.brightness,
        scaffoldBackgroundColor: theme.brightness == Brightness.dark 
            ? Color(0xFF121212) 
            : Colors.white,
        cardColor: theme.brightness == Brightness.dark 
            ? Color(0xFF1E1E1E) 
            : Colors.white,
        colorScheme: Theme.of(context).colorScheme.copyWith(
          background: theme.brightness == Brightness.dark 
              ? Color(0xFF121212) 
              : Colors.white,
          surface: theme.brightness == Brightness.dark 
              ? Color(0xFF1E1E1E) 
              : Colors.white,
        ),
      ),
      child: Scaffold(
        backgroundColor: theme.brightness == Brightness.dark 
            ? Color(0xFF121212) 
            : Colors.white,
        body: Stack(
          children: [
            SafeArea(
              child: _isLoading
                  ? Center(
                      child: Lottie.asset(
                        'assets/animations/MainScene.json',
                        width: 200,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                    )
                  : _videos.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildVideosTab(theme),
            ),
            

          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).size.height * 0.08, // 8% dell'altezza dello schermo
          ),
          sliver: SliverToBoxAdapter(
            child: _buildSocialAccountsStories(theme),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 20.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildUpcomingScheduledPosts(theme),
              _buildCreditsIndicator(theme),
              _buildTrendsCard(theme),
              _buildCommunityCard(theme),
              const SizedBox(height: 34),
              _buildOnboardingList(theme),
              const SizedBox(height: 116), // Aumentato di 2 cm (76px)
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildVideosTab(ThemeData theme) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).size.height * 0.08, // 8% dell'altezza dello schermo
          ),
          sliver: SliverToBoxAdapter(
            child: _buildSocialAccountsStories(theme),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 20.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildUpcomingScheduledPosts(theme),
              _buildCreditsIndicator(theme),
              _buildTrendsCard(theme),
              _buildCommunityCard(theme),
              const SizedBox(height: 34),
              _buildOnboardingList(theme),
              const SizedBox(height: 116), // Aumentato di 2 cm (76px)
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildOnboardingList(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    // Hide the section if all steps are completed
    if (_hasConnectedAccounts && _hasUploadedVideo) {
      return const SizedBox.shrink();
    }
    final List<Map<String, dynamic>> steps = [
      {
        'number': 1,
        'title': 'Connect Your Social Accounts',
        'description': 'Link your social media accounts to start sharing content',
        'isCompleted': _hasConnectedAccounts,
        'onTap': () {
          Navigator.pushNamed(context, '/accounts').then((_) {
            _loadSocialAccounts();
            _checkUserProgress();
          });
        },
        'key': _connectAccountsKey,
        'icon': Icons.link,
      },
      {
        'number': 2,
        'title': 'Upload Your First Video',
        'description': 'Create and share your first video across your connected platforms',
        'isCompleted': _hasUploadedVideo,
        'onTap': () {
          Navigator.pushNamed(context, '/upload').then((_) {
            _loadVideos();
            _checkUserProgress();
          });
        },
        'key': _uploadVideoKey,
        'icon': Icons.video_library,
      },
      {
        'number': 3,
        'title': 'Premium Active',
        'description': 'Enjoy unlimited uploads and premium features',
        'isCompleted': true,
        'onTap': () {},
        'key': null,
        'icon': Icons.star,
      },
    ];
    int completedSteps = steps.where((step) => step['isCompleted'] as bool).length;
    int totalSteps = steps.length;
    int currentStep = completedSteps < totalSteps ? completedSteps + 1 : totalSteps;
    List<Widget> stepWidgets = [];
    stepWidgets.add(
      Container(
        margin: EdgeInsets.only(left: 22.5),
        width: 3,
        height: 15,
        decoration: BoxDecoration(
          gradient: steps[0]['isCompleted'] as bool 
              ? LinearGradient(
                  colors: [
                    Color(0xFF667eea),
                    Color(0xFF764ba2),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  transform: GradientRotation(135 * 3.14159 / 180),
                )
              : null,
          color: steps[0]['isCompleted'] as bool ? null : Colors.grey.shade300,
        ),
      ),
    );
    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      final isActive = (i + 1) <= currentStep;
      final isCompleted = step['isCompleted'] as bool;
      stepWidgets.add(
        _buildStepItem(
          theme,
          number: step['number'] as int,
          title: step['title'] as String,
          description: step['description'] as String,
          isActive: isActive,
          isCompleted: isCompleted,
          icon: step['icon'] as IconData,
          onTap: step['onTap'] as VoidCallback,
          key: step['key'] as Key?,
        ),
      );
      if (i < steps.length - 1) {
        stepWidgets.add(
          Container(
            margin: EdgeInsets.only(left: 22.5),
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  isCompleted 
                      ? Color(0xFF667eea)
                      : Colors.grey.shade300,
                  i + 1 < currentStep 
                      ? Color(0xFF764ba2)
                      : Colors.grey.shade300,
                ],
                transform: GradientRotation(135 * 3.14159 / 180),
              ),
            ),
          ),
        );
      } else {
        stepWidgets.add(
          Container(
            margin: EdgeInsets.only(left: 22.5),
            width: 3,
            height: 15,
            decoration: BoxDecoration(
              gradient: isCompleted 
                  ? LinearGradient(
                      colors: [
                        Color(0xFF667eea),
                        Color(0xFF764ba2),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    )
                  : null,
              color: isCompleted ? null : Colors.grey.shade300,
            ),
          ),
        );
      }
    }
    return Container(
      margin: const EdgeInsets.only(top: 18, bottom: 10),
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        // Bordo con effetto vetro più sottile
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        // Ombra per effetto profondità e vetro
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: isDark ? 25 : 20,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          // Ombra interna per effetto vetro
          BoxShadow(
            color: isDark 
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.6),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
        // Gradiente più sottile per effetto vetro
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark 
              ? [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.1),
                ]
              : [
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.2),
                ],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFF667eea),
                      Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ).createShader(bounds);
                },
                child: Text(
                  'Getting Started',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Color(0xFF667eea).withOpacity(0.1),
                      Color(0xFF764ba2).withOpacity(0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    transform: GradientRotation(135 * 3.14159 / 180),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      colors: [
                        Color(0xFF667eea),
                        Color(0xFF764ba2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ).createShader(bounds);
                  },
                  child: Text(
                    '$completedSteps/$totalSteps Steps',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Add all the step widgets
          ...stepWidgets,
        ],
      ),
    );
  }

  Widget _buildStepItem(
    ThemeData theme, {
    required int number,
    required String title,
    required String description,
    required bool isActive,
    required bool isCompleted,
    required IconData icon,
    required VoidCallback onTap,
    Key? key,
  }) {
    final Color accentColor = isCompleted 
        ? Color(0xFF667eea)
        : isActive 
            ? Color(0xFF667eea)
            : Colors.grey.shade400;
            
    final Color backgroundColor = isCompleted 
        ? Color(0xFF667eea).withOpacity(0.1)
        : isActive 
            ? Color(0xFF667eea).withOpacity(0.05)
            : theme.colorScheme.surfaceVariant;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          key: key,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          margin: EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isActive ? theme.cardColor : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: (isActive || isCompleted)
                ? Border.all(
                    color: Color(0xFF667eea).withOpacity(0.6), 
                    width: 2
                  )
                : null,
            boxShadow: (isActive || isCompleted)
                ? [
                    BoxShadow(
                      color: Color(0xFF667eea).withOpacity(0.15),
                      blurRadius: 12,
                      spreadRadius: 1,
                      offset: Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: backgroundColor,
                  border: Border.all(
                    color: accentColor,
                    width: theme.brightness == Brightness.dark && isActive ? 3 : 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.brightness == Brightness.dark && isActive 
                          ? Color(0xFF6C63FF).withOpacity(0.3)
                          : accentColor.withOpacity(0.15),
                      blurRadius: theme.brightness == Brightness.dark && isActive ? 12 : 8,
                      spreadRadius: theme.brightness == Brightness.dark && isActive ? 3 : 2,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: isCompleted
                      ? Icon(
                          Icons.check,
                          color: theme.brightness == Brightness.dark ? Color(0xFF6C63FF) : accentColor,
                          size: 22,
                        )
                      : Text(
                          number.toString(),
                          style: TextStyle(
                            color: isActive ? const Color(0xFF6C63FF) : accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isActive ? theme.textTheme.bodyLarge?.color : Colors.grey.shade500,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            icon,
                            color: isCompleted && theme.brightness == Brightness.dark ? Color(0xFF6C63FF) : accentColor,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: isActive ? Colors.grey.shade600 : Colors.grey.shade400,
                        fontSize: 14,
                      ),
                    ),
                    if (isActive && !isCompleted) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isActive ? const Color(0xFF6C63FF).withOpacity(0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Start this step',
                          style: TextStyle(
                            color: isActive ? const Color(0xFF6C63FF) : Colors.grey.shade400,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    if (isCompleted) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: theme.brightness == Brightness.dark ? Color(0xFF6C63FF) : theme.primaryColor,
                            size: 14,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Completed',
                            style: TextStyle(
                              color: theme.brightness == Brightness.dark ? Color(0xFF6C63FF) : theme.primaryColor,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialAccountsStories(ThemeData theme, {bool showTabs = false}) {
    return Container(
      color: theme.brightness == Brightness.dark 
          ? Color(0xFF121212) 
          : Colors.white,
      child: SizedBox(
        height: 140,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
          scrollDirection: Axis.horizontal,
          itemCount: _socialAccounts.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildStoryCircle(
                theme,
                isAddButton: true,
                onTap: () {
                  Navigator.pushNamed(context, '/accounts');
                },
              );
            }
            final account = _socialAccounts[index - 1];
            return _buildStoryCircle(
              theme,
              imageUrl: account['profile_image_url'],
              platform: account['platform'],
              displayName: account['display_name'] ?? account['username'] ?? 'Account',
              accountData: account,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SocialAccountDetailsPage(
                      account: {
                        'id': account['id'],
                        'username': account['username'],
                        'displayName': account['display_name'],
                        'profileImageUrl': account['profile_image_url'],
                        'followersCount': account['followers_count'],
                        'status': account['status'],
                      },
                      platform: account['platform'],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildStoryCircle(
    ThemeData theme, {
    String? imageUrl,
    String? platform,
    String? displayName,
    Map<String, dynamic>? accountData,
    bool isAddButton = false,
    required VoidCallback onTap,
  }) {
    Map<String, List<Color>> platformColors = {
      'twitter': [const Color(0xFF1DA1F2), const Color(0xFF0D8ECF)],
      'instagram': [const Color(0xFFC13584), const Color(0xFFF56040), const Color(0xFFFFDC80)],
      'facebook': [const Color(0xFF3B5998), const Color(0xFF2C4270)],
      'youtube': [const Color(0xFFFF0000), const Color(0xFFCC0000)],
      'threads': [const Color(0xFF000000), const Color(0xFF333333)],
    };
    IconData getPlatformIcon(String? platform) {
      switch (platform?.toLowerCase()) {
        case 'twitter':
          return Icons.short_text;
        case 'instagram':
          return Icons.camera_alt;
        case 'facebook':
          return Icons.facebook;
        case 'youtube':
          return Icons.play_arrow;
        case 'threads':
          return Icons.label;
        default:
          return Icons.account_circle;
      }
    }
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              width: 85,
              height: 85,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isAddButton
                    ? LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.2),
                          Colors.white.withOpacity(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: platformColors[platform?.toLowerCase()] ?? 
                            [theme.primaryColor, theme.primaryColorLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: isAddButton ? null : null,
                border: isAddButton
                    ? Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1,
                      )
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: isAddButton
                        ? Colors.black.withOpacity(0.2)
                        : Colors.black.withOpacity(0.05),
                    blurRadius: isAddButton ? 15 : 3,
                    spreadRadius: isAddButton ? 1 : 0,
                    offset: const Offset(0, 4),
                  ),
                  if (isAddButton)
                    BoxShadow(
                      color: Colors.white.withOpacity(0.3),
                      blurRadius: 2,
                      spreadRadius: -2,
                      offset: const Offset(0, 2),
                    ),
                ],
              ),
              padding: const EdgeInsets.all(3.5),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.cardColor,
                  image: !isAddButton && imageUrl != null && imageUrl.isNotEmpty
                      ? DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                          onError: (exception, stackTrace) {
                            print('Error loading image: $exception');
                            print('Image URL: $imageUrl');
                          },
                        )
                      : null,
                ),
                child: isAddButton
                    ? ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return LinearGradient(
                            colors: [
                              Color(0xFF667eea),
                              Color(0xFF764ba2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * 3.14159 / 180),
                          ).createShader(bounds);
                        },
                        child: Icon(
                          Icons.add,
                          color: Colors.white,
                          size: 40,
                        ),
                      )
                    : (imageUrl == null || imageUrl.isEmpty)
                        ? Icon(
                            getPlatformIcon(platform),
                            color: platformColors[platform?.toLowerCase()]?[0] ?? theme.primaryColor,
                            size: 38,
                          )
                        : null,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Flexible(
            child: Text(
              isAddButton ? 'Add' : (displayName ?? ''),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodyMedium?.color,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToScheduledPostsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ScheduledPostsPage(),
      ),
    ).then((_) {
      _loadUpcomingScheduledPosts();
    });
  }

  Widget _buildUpcomingScheduledPosts(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    if (_upcomingScheduledPosts.isEmpty) {
      return SizedBox();
    }
    List<Widget> postWidgets = [];
    for (int i = 0; i < _upcomingScheduledPosts.length; i++) {
      final post = _upcomingScheduledPosts[i];
      postWidgets.add(
        _buildUpcomingPostItem(theme, post),
      );
      if (i < _upcomingScheduledPosts.length - 1) {
        postWidgets.add(
          Divider(
            height: 16,
            thickness: 1,
            color: Colors.grey.shade200,
          ),
        );
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Upcoming',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timer,
                      size: 14,
                      color: theme.primaryColor,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Next 15 min',
                      style: TextStyle(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          ...postWidgets,
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _navigateToScheduledPostsPage,
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See all',
                    style: TextStyle(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 12,
                    color: theme.primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpcomingPostItem(ThemeData theme, Map<String, dynamic> post) {
    final scheduledTime = post['scheduledTime'] as int;
    final dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
    final now = DateTime.now();
    final difference = dateTime.difference(now);
    String timeRemaining;
    if (difference.inMinutes <= 0) {
      timeRemaining = 'Publishing now';
    } else if (difference.inMinutes == 1) {
      timeRemaining = '1 minute left';
    } else {
      timeRemaining = '${difference.inMinutes} minutes left';
    }
    final formattedTime = DateFormat('HH:mm').format(dateTime);
    List<Widget> platformBadges = (post['platforms'] as List<String>).map((platform) {
      return Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: _getPlatformColor(platform).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getPlatformIcon(platform),
              size: 14,
              color: _getPlatformColor(platform),
            ),
            SizedBox(width: 4),
            Text(
              platform,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _getPlatformColor(platform),
              ),
            ),
          ],
        ),
      );
    }).toList();
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ScheduledPostDetailsPage(post: post),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                      image: post['thumbnail_path'] != null && post['thumbnail_path'].isNotEmpty
                          ? DecorationImage(
                              image: FileImage(File(post['thumbnail_path'])),
                              fit: BoxFit.cover,
                              onError: (error, stackTrace) {},
                            )
                          : null,
                    ),
                    child: post['thumbnail_path'] == null || post['thumbnail_path'].isEmpty
                        ? Center(
                            child: Icon(
                              Icons.video_library,
                              size: 28,
                              color: theme.primaryColor.withOpacity(0.6),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post['title']?.isNotEmpty == true
                          ? post['title']
                          : (post['description']?.isNotEmpty == true
                              ? post['description']
                              : 'Scheduled post'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Today at $formattedTime',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        Spacer(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: (post['platforms'] as List<String>).map((platform) {
                            return Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.all(3),
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                color: _getPlatformColor(platform).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: _getPlatformWidget(platform, 10),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    Container(
                      margin: EdgeInsets.only(top: 6),
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer,
                            size: 12,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            timeRemaining,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.grey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'TikTok': return Icons.music_note;
      case 'YouTube': return Icons.play_arrow;
      case 'Instagram': return Icons.camera_alt;
      case 'Facebook': return Icons.facebook;
      case 'Twitter': return Icons.chat;
      case 'Threads': return Icons.chat_outlined;
      default: return Icons.share;
    }
  }

  Color _getPlatformColor(String platform) {
    switch (platform) {
      case 'TikTok':
        return Colors.black;
      case 'YouTube':
        return Colors.red;
      case 'Instagram':
        return Color(0xFFE1306C);
      case 'Facebook':
        return Color(0xFF1877F2);
      case 'Twitter':
        return Color(0xFF1DA1F2);
      case 'Threads':
        return Color(0xFF000000);
      default:
        return Colors.grey;
    }
  }

  Widget _getPlatformWidget(String platform, double size) {
    switch (platform) {
      case 'YouTube':
        return Icon(
          Icons.play_arrow,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'TikTok':
        return Icon(
          Icons.music_note,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'Instagram':
        return Icon(
          Icons.camera_alt,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'Facebook':
        return Icon(
          Icons.facebook,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'Twitter':
        return Icon(
          Icons.chat,
          size: size,
          color: _getPlatformColor(platform),
        );
      case 'Threads':
        return Icon(
          Icons.chat_outlined,
          size: size,
          color: _getPlatformColor(platform),
        );
      default:
        return Icon(
          Icons.share,
          size: size,
          color: _getPlatformColor(platform),
        );
    }
  }

  Widget _buildCreditsIndicator(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    
    // Gradiente lineare a 135 gradi per la ruota dei crediti
    const List<Color> creditsGradient = [
      Color(0xFF667eea), // Blu violaceo al 0%
      Color(0xFF764ba2), // Viola al 100%
    ];
    
    return Container(
      decoration: BoxDecoration(
        // Effetto vetro semi-trasparente opaco
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(20),
        // Bordo con effetto vetro più sottile
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        // Ombra per effetto profondità e vetro
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: isDark ? 25 : 20,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          // Ombra interna per effetto vetro
          BoxShadow(
            color: isDark 
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.6),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
        // Gradiente più sottile per effetto vetro
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark 
              ? [
                  Colors.white.withOpacity(0.2),
                  Colors.white.withOpacity(0.1),
                ]
              : [
                  Colors.white.withOpacity(0.3),
                  Colors.white.withOpacity(0.2),
                ],
        ),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          
          // Centered circular progress indicator
          Center(
            child: Column(
              children: [
                Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: creditsGradient[0].withOpacity(0.15),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Circular progress indicator background
                      Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.surfaceVariant,
                        ),
                      ),
                      // Circular progress indicator with gradient - Custom implementation
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: CustomPaint(
                          painter: GradientCircularProgressPainter(
                            progress: 1.0, // Always full for premium
                            strokeWidth: 20,
                            backgroundColor: theme.colorScheme.surfaceVariant,
                            gradient: LinearGradient(
                              colors: creditsGradient,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180),
                            ),
                          ),
                        ),
                      ),
                      
                      // White circle in center
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.cardColor,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.withOpacity(0.1),
                              blurRadius: 5,
                              spreadRadius: 1,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      
                      // Gradient overlay for nicer visual effect
                      Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white,
                              Colors.white.withOpacity(0.95),
                            ],
                            stops: const [0.7, 1.0],
                          ),
                        ),
                      ),
                      
                      // Credit amount with stacked text for effect (solo il numero con gradiente)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Main text with gradient
                          ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return LinearGradient(
                                colors: creditsGradient,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                transform: GradientRotation(135 * 3.14159 / 180),
                              ).createShader(bounds);
                            },
                            child: Text(
                              '∞',
                              style: TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 0.9,
                              ),
                            ),
                          ),
                          Text(
                            'Premium',
                            style: TextStyle(
                              fontSize: 16,
                              color: theme.brightness == Brightness.dark ? Color(0xFF6C63FF).withOpacity(0.7) : theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Badge premium
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: creditsGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          transform: GradientRotation(135 * 3.14159 / 180),
                        ),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.white,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: creditsGradient[0].withOpacity(0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.verified, color: Colors.white, size: 24),
                          SizedBox(width: 10),
                          Text(
                            'Premium Active',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const TrendsPage(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          margin: const EdgeInsets.only(top: 18, bottom: 10),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            // Effetto vetro semi-trasparente opaco
            color: isDark 
                ? Colors.white.withOpacity(0.15) 
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(24),
            // Bordo con effetto vetro più sottile
            border: Border.all(
              color: isDark 
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.4),
              width: 1,
            ),
            // Ombra per effetto profondità e vetro
            boxShadow: [
              BoxShadow(
                color: isDark 
                    ? Colors.black.withOpacity(0.4)
                    : Colors.black.withOpacity(0.15),
                blurRadius: isDark ? 25 : 20,
                spreadRadius: isDark ? 1 : 0,
                offset: const Offset(0, 10),
              ),
              // Ombra interna per effetto vetro
              BoxShadow(
                color: isDark 
                    ? Colors.white.withOpacity(0.1)
                    : Colors.white.withOpacity(0.6),
                blurRadius: 2,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
            ],
            // Gradiente più sottile per effetto vetro
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                  ? [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.1),
                    ]
                  : [
                      Colors.white.withOpacity(0.3),
                      Colors.white.withOpacity(0.2),
                    ],
            ),
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header con icona e titolo
                  Row(
                    children: [
                      // Icona AI senza container circolare
                      Lottie.asset(
                        'assets/animations/analizeAI.json',
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                      const SizedBox(width: 8),
                      
                      // Titolo
                      Expanded(
                        child: ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: [
                                Color(0xFF667eea), // Blu violaceo al 0%
                                Color(0xFF764ba2), // Viola al 100%
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              transform: GradientRotation(135 * 3.14159 / 180),
                            ).createShader(bounds);
                          },
                          child: Text(
                            'AI-Trends Finder',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontSize: 16,
                              letterSpacing: -0.5,
                              fontFamily: 'Ethnocentric',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Descrizione migliorata
                  Text(
                    'Discover trending content across TikTok, Instagram, YouTube & more with real-time AI analysis',
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark 
                          ? Colors.white.withOpacity(0.7)
                          : Color(0xFF1A1A1A).withOpacity(0.7),
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  
                  // Footer con feature e freccia
                  Row(
                    children: [
                      // Feature badge con gradiente
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF667eea),
                              Color(0xFF764ba2),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            transform: GradientRotation(135 * 3.14159 / 180),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0xFF667eea).withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 0,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_awesome,
                              size: 14,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Real-time AI',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Freccia più elegante
                      Padding(
                        padding: const EdgeInsets.only(right: 20),
                        child: Icon(
                          Icons.arrow_forward_ios,
                          color: isDark 
                              ? Colors.white.withOpacity(0.7)
                              : Color(0xFF1A1A1A).withOpacity(0.6),
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              

            ],
          ),
        ),
      ),
    );
  }

  // Card per navigare alla pagina community
  Widget _buildCommunityCard(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CommunityPage(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.only(top: 18, bottom: 10),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            // Effetto vetro semi-trasparente opaco
            color: isDark 
                ? Colors.white.withOpacity(0.15) 
                : Colors.white.withOpacity(0.25),
            borderRadius: BorderRadius.circular(20),
            // Bordo con effetto vetro più sottile
            border: Border.all(
              color: isDark 
                  ? Colors.white.withOpacity(0.2)
                  : Colors.white.withOpacity(0.4),
              width: 1,
            ),
            // Ombra per effetto profondità e vetro
            boxShadow: [
              BoxShadow(
                color: isDark 
                    ? Colors.black.withOpacity(0.4)
                    : Colors.black.withOpacity(0.15),
                blurRadius: isDark ? 25 : 20,
                spreadRadius: isDark ? 1 : 0,
                offset: const Offset(0, 10),
              ),
              // Ombra interna per effetto vetro
              BoxShadow(
                color: isDark 
                    ? Colors.white.withOpacity(0.1)
                    : Colors.white.withOpacity(0.6),
                blurRadius: 2,
                spreadRadius: -2,
                offset: const Offset(0, 2),
              ),
            ],
            // Gradiente più sottile per effetto vetro
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark 
                  ? [
                      Colors.white.withOpacity(0.2),
                      Colors.white.withOpacity(0.1),
                    ]
                  : [
                      Colors.white.withOpacity(0.3),
                      Colors.white.withOpacity(0.2),
                    ],
            ),
          ),
          child: Row(
            children: [
              Container(
                margin: const EdgeInsets.only(left: 8, right: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  // Icona con effetto vetro semi-trasparente
                  color: isDark 
                      ? Colors.white.withOpacity(0.2)
                      : Colors.white.withOpacity(0.3),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark 
                        ? Colors.white.withOpacity(0.3)
                        : Colors.white.withOpacity(0.5),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: isDark 
                        ? Colors.black.withOpacity(0.3)
                        : Colors.black.withOpacity(0.15),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                    BoxShadow(
                      color: isDark 
                        ? Colors.white.withOpacity(0.1)
                        : Colors.white.withOpacity(0.4),
                      blurRadius: 1,
                      spreadRadius: -1,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      colors: [
                        const Color(0xFF667eea),
                        const Color(0xFF764ba2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds);
                  },
                  child: Icon(
                    Icons.people, 
                    color: Colors.white, 
                    size: 22
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: [
                                const Color(0xFF667eea),
                                const Color(0xFF764ba2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds);
                          },
                          child: Text(
                            'Community',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark 
                                ? Colors.white.withOpacity(0.2)
                                : Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark 
                                  ? Colors.white.withOpacity(0.3)
                                  : Colors.white.withOpacity(0.5),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isDark 
                                    ? Colors.black.withOpacity(0.2)
                                    : Colors.black.withOpacity(0.1),
                                blurRadius: 5,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return LinearGradient(
                                colors: [
                                  const Color(0xFF667eea),
                                  const Color(0xFF764ba2),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ).createShader(bounds);
                            },
                            child: Text(
                              'NEW',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Connect with creators, share your Fluzar score & compete with friends',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark 
                            ? Colors.white.withOpacity(0.7)
                            : theme.textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: [
                                const Color(0xFF667eea),
                                const Color(0xFF764ba2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds);
                          },
                          child: Icon(
                            Icons.star,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        ShaderMask(
                          shaderCallback: (Rect bounds) {
                            return LinearGradient(
                              colors: [
                                const Color(0xFF667eea),
                                const Color(0xFF764ba2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ).createShader(bounds);
                          },
                          child: Text(
                            'Fluzar Score & Leaderboards',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      const Color(0xFF667eea),
                      const Color(0xFF764ba2),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds);
                },
                child: Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white,
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom painter for gradient circular progress indicator
class GradientCircularProgressPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color backgroundColor;
  final LinearGradient gradient;

  GradientCircularProgressPainter({
    required this.progress,
    required this.strokeWidth,
    required this.backgroundColor,
    required this.gradient,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    // Draw background circle
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Draw progress arc with gradient
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    // Create gradient shader
    final rect = Rect.fromCircle(center: center, radius: radius);
    final shader = gradient.createShader(rect);
    progressPaint.shader = shader;

    // Draw the progress arc
    final sweepAngle = 2 * 3.14159 * progress;
    canvas.drawArc(
      rect,
      -3.14159 / 2, // Start from top
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
