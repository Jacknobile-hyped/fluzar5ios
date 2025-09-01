import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';
import 'dart:io';
import '../../pages/settings_page.dart';
import '../../pages/profile_page.dart';
import '../../pages/scheduled_post_details_page.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';

class SocialAccountDetailsPage extends StatefulWidget {
  final Map<String, dynamic> account;
  final String platform;

  const SocialAccountDetailsPage({
    super.key,
    required this.account,
    required this.platform,
  });

  @override
  State<SocialAccountDetailsPage> createState() => _SocialAccountDetailsPageState();
}

class _SocialAccountDetailsPageState extends State<SocialAccountDetailsPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _videosSubscription;
  List<Map<String, dynamic>> _videos = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showInfo = false;
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  Map<String, String?> _postUrls = {};
  bool _isLoadingUrls = true;
  final PageController _fullscreenPageController = PageController();

  // Define platform logo paths
  final Map<String, String> _platformLogos = {
    'twitter': 'assets/loghi/logo_twitter.png',
    'youtube': 'assets/loghi/logo_yt.png',
    'tiktok': 'assets/loghi/logo_tiktok.png',
    'instagram': 'assets/loghi/logo_insta.png',
    'facebook': 'assets/loghi/logo_facebook.png',
    'threads': 'assets/loghi/threads_logo.png',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeVideosListener();
  }

  @override
  void dispose() {
    _videosSubscription?.cancel();
    _searchController.dispose();
    _tabController.dispose();
    _fullscreenPageController.dispose();
    super.dispose();
  }

  void _initializeVideosListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final videosRef = _database
        .child('users')
        .child('users')
        .child(currentUser.uid)
        .child('videos');

    _videosSubscription = videosRef.onValue.listen((event) {
      if (!mounted) return;
      
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        if (mounted) {
          setState(() {
            _videos = data.entries.map((entry) {
              final videoData = entry.value as Map<dynamic, dynamic>;
              
              // Verifica la struttura corretta degli account per la piattaforma
              final accounts = videoData['accounts'] as Map<dynamic, dynamic>? ?? {};
              final platformAccounts = accounts[widget.platform.toLowerCase()] as List<dynamic>?;
              
              if (platformAccounts == null) return null;

              // Verifica se il video è associato all'account corrente
              bool isAssociatedWithAccount = platformAccounts.any((acc) => 
                acc['username'] == widget.account['username']
              );

              if (!isAssociatedWithAccount) {
                return null;
              }

              // Determina lo stato del video, considerando anche quelli precedentemente programmati
              String status = videoData['status'] ?? 'draft';
              
              // Controlla se è stato impostato published_at (pubblicato da programmazione)
              final publishedAt = videoData['published_at'] as int?;
              
              // Se il post era programmato ed è stato pubblicato, lo consideriamo pubblicato
              // ma manteniamo l'informazione che era programmato
              if (publishedAt != null && status == 'scheduled') {
                status = 'published';
              }

              // Determina il timestamp corretto per la visualizzazione
              int timestamp;
              if (publishedAt != null) {
                // Se è stato pubblicato, mostra la data di pubblicazione
                timestamp = publishedAt;
              } else if (videoData['scheduled_time'] != null && status == 'scheduled') {
                // Se è programmato, mostra la data programmata
                timestamp = videoData['scheduled_time'] as int;
              } else {
                // Altrimenti, usa il timestamp originale
                timestamp = videoData['timestamp'] ?? 0;
              }

              return {
                'id': entry.key,
                'title': videoData['title'] ?? '',
                'description': videoData['description'] ?? '',
                'platforms': List<String>.from(videoData['platforms'] ?? []),
                'status': status,
                'timestamp': timestamp,
                'video_path': videoData['video_path'] ?? '',
                'thumbnail_path': videoData['thumbnail_path'] ?? '',
                'scheduled_time': videoData['scheduled_time'],
                'published_at': publishedAt,
                'accounts': accounts,
                'youtube_video_id': videoData['youtube_video_id'],
              };
            })
            .where((video) => video != null)
            .cast<Map<String, dynamic>>()
            .toList()
            ..sort((a, b) {
              final aStatus = a['status'] as String;
              final bStatus = b['status'] as String;
              final aScheduledTime = a['scheduled_time'] as int?;
              final bScheduledTime = b['scheduled_time'] as int?;
              final aPublishedAt = a['published_at'] as int?;
              final bPublishedAt = b['published_at'] as int?;
              
              // If both are published posts (either regular or from scheduled)
              if ((aStatus == 'published') && (bStatus == 'published')) {
                // Sort by published_at or timestamp (most recent first)
                final aTime = aPublishedAt ?? a['timestamp'] as int;
                final bTime = bPublishedAt ?? b['timestamp'] as int;
                return bTime.compareTo(aTime); // Descending order
              }
              
              // If one is published and the other is scheduled
              if (aStatus == 'published' && bStatus == 'scheduled') {
                return -1; // Published comes first
              }
              if (aStatus == 'scheduled' && bStatus == 'published') {
                return 1; // Published comes first
              }
              
              // Both are scheduled posts
              if (aStatus == 'scheduled' && bStatus == 'scheduled') {
                // Sort by scheduled_time (nearest first)
                final aTime = aScheduledTime ?? a['timestamp'] as int;
                final bTime = bScheduledTime ?? b['timestamp'] as int;
                return aTime.compareTo(bTime); // Ascending order for scheduled
              }
              
              // Default sort by timestamp
              return (b['timestamp'] as int).compareTo(a['timestamp'] as int);
            });
            _isLoading = false;
          });
        }
      } else if (mounted) {
        setState(() {
          _videos = [];
          _isLoading = false;
        });
      }
    }, onError: (error) {
      print('Error loading videos: $error');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading videos: $error')),
        );
      }
    });
  }

  void _updatePostUrl(Map<dynamic, dynamic>? accounts, String videoId) {
    if (accounts == null) return;

    accounts.forEach((platform, platformAccounts) {
      if (platformAccounts is List) {
        for (var account in platformAccounts) {
          if (account is Map) {
            final username = account['username']?.toString();
            final postId = account['post_id']?.toString();
            final mediaId = account['media_id']?.toString();

            if (username != null) {
              String? url;
              if (platform.toString().toLowerCase() == 'twitter' && postId != null) {
                url = 'https://twitter.com/i/status/$postId';
              } else if (platform.toString().toLowerCase() == 'youtube' && (postId != null || mediaId != null)) {
                final videoId = postId ?? mediaId;
                url = 'https://www.youtube.com/watch?v=$videoId';
              } else if (platform.toString().toLowerCase() == 'facebook' && postId != null) {
                url = 'https://facebook.com/$username/posts/$postId';
              } else if (platform.toString().toLowerCase() == 'instagram' && mediaId != null) {
                url = 'https://instagram.com/p/$mediaId';
              } else if (platform.toString().toLowerCase() == 'tiktok' && mediaId != null) {
                url = 'https://tiktok.com/@$username/video/$mediaId';
              }

              if (url != null) {
                setState(() {
                  _postUrls['${platform.toString().toLowerCase()}_${username}_$videoId'] = url;
                });
              }
            }
          }
        }
      }
    });
  }

  Future<void> _refreshVideos() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      await _videosSubscription?.cancel();
      _initializeVideosListener();
      await Future.delayed(const Duration(milliseconds: 500));
    } catch (e) {
      print('Error refreshing videos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error refreshing videos: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildHeader() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.arrow_back,
                  color: Colors.black87,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFF6C63FF),
                      Color(0xFFFF6B6B),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds);
                },
                child: Text(
                  'Viral',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
              ShaderMask(
                shaderCallback: (Rect bounds) {
                  return LinearGradient(
                    colors: [
                      Color(0xFFFF6B6B),
                      Color(0xFF00C9FF),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ).createShader(bounds);
                },
                child: Text(
                  'yst',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    letterSpacing: -0.5,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  Icons.settings_outlined,
                  color: Colors.black87,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              Stack(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.notifications_outlined,
                      color: Colors.black87,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints(),
                    onPressed: () {
                      // TODO: Implement notifications
                    },
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfilePage(),
                    ),
                  );
                },
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: _currentUser?.photoURL != null
                        ? DecorationImage(
                            image: NetworkImage(_currentUser!.photoURL!),
                            fit: BoxFit.cover,
                          )
                        : null,
                    color: theme.primaryColor.withOpacity(0.1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: _currentUser?.photoURL == null
                      ? Icon(
                          Icons.person,
                          color: theme.primaryColor,
                          size: 16,
                        )
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection() {
    final theme = Theme.of(context);
    final account = widget.account;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.05),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Upper section with profile image and info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Larger profile image with nicer border
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white, 
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: (account['profileImageUrl']?.isNotEmpty ?? false)
                      ? Image.network(
                          account['profileImageUrl'],
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 2,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: theme.colorScheme.primary.withOpacity(0.2),
                              child: Center(
                                child: Text(
                                  (account['displayName'] ?? '?')[0].toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          color: theme.colorScheme.primary.withOpacity(0.2),
                          child: Center(
                            child: Text(
                              (account['displayName'] ?? '?')[0].toUpperCase(),
                              style: TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: 20),
                // Name and username with improved styling
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        account['displayName'] ?? '',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      if (account['username']?.isNotEmpty ?? false)
                        Text(
                          '@${account['username']}',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (account['location']?.isNotEmpty ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                account['location'] ?? '',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // Open profile button with improved styling
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: _openProfileUrl,
                    child: Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.open_in_new,
                        color: theme.colorScheme.primary,
                        size: 20,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Bio section - only if present
          if (account['bio']?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  account['bio'] ?? '',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[800],
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          
          // Stats section with larger numbers
          Padding(
            padding: const EdgeInsets.fromLTRB(15, 0, 15, 25),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Videos count
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 6),
                            Text(
                              '${_videos.length}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Videos',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Divider
                  Container(
                    height: 40,
                    width: 1,
                    color: Colors.grey[200],
                  ),
                  
                  // Followers count
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          NumberFormat.compact().format(account['followersCount'] ?? 0),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Followers',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // Divider
                  Container(
                    height: 40,
                    width: 1,
                    color: Colors.grey[200],
                  ),
                  
                  // Following count
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          NumberFormat.compact().format(account['followingCount'] ?? 0),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Following',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoList(bool isPublished) {
    final theme = Theme.of(context);
    
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
          strokeWidth: 3,
        ),
      );
    }

    var filteredVideos = List<Map<String, dynamic>>.from(_videos);
    
    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filteredVideos = filteredVideos.where((video) {
        final title = (video['title'] as String? ?? '').toLowerCase();
        final description = (video['description'] as String? ?? '').toLowerCase();
        final status = (video['status'] as String? ?? '').toLowerCase();
        return title.contains(query) ||
               description.contains(query) || 
               status.contains(query);
      }).toList();
    }

    // Filter by status
    filteredVideos = filteredVideos.where((video) {
      final status = video['status'] as String? ?? '';
      final publishedAt = video['published_at'] as int?;
      
      if (isPublished) {
        // Show in Published tab if:
        // 1. Status is 'published', OR
        // 2. Status is 'scheduled' but has 'published_at' timestamp (was a scheduled post that's been published)
        return status == 'published' || (status == 'scheduled' && publishedAt != null);
      } else {
        // Show in Scheduled tab only if:
        // 1. Status is 'scheduled' AND
        // 2. No 'published_at' timestamp exists (not yet published)
        return status == 'scheduled' && publishedAt == null;
      }
    }).toList();

    // Sort videos
    if (isPublished) {
      // Published videos: most recent first (descending)
      filteredVideos.sort((a, b) => (b['timestamp'] as int).compareTo(a['timestamp'] as int));
    } else {
      // Scheduled videos: nearest scheduled time first (ascending)
      filteredVideos.sort((a, b) {
        final aTime = a['scheduled_time'] as int? ?? a['timestamp'] as int;
        final bTime = b['scheduled_time'] as int? ?? b['timestamp'] as int;
        return aTime.compareTo(bTime);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_showInfo) _buildInfoDropdown(),
        
        Expanded(
          child: filteredVideos.isEmpty
              ? _buildEmptyState(isPublished)
              : RefreshIndicator(
                  onRefresh: _refreshVideos,
                  color: theme.colorScheme.primary,
                  backgroundColor: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Calculate item size based on available width
                        final availableWidth = constraints.maxWidth;
                        // Divide by 3 for 3 equal columns with a little gap
                        final normalSize = (availableWidth - 16) / 3;
                        // Size for large items (2x2)
                        final largeSize = normalSize * 2 + 4;
                        
                        // Build the grid with pattern repeating every 5 items
                        return GridView.custom(
                          gridDelegate: SliverQuiltedGridDelegate(
                            crossAxisCount: 3, 
                            mainAxisSpacing: 4,
                            crossAxisSpacing: 4,
                            repeatPattern: QuiltedGridRepeatPattern.inverted,
                            pattern: [
                              // First row: 3 normal items
                              QuiltedGridTile(1, 1), // index 0
                              QuiltedGridTile(1, 1), // index 1
                              QuiltedGridTile(1, 1), // index 2
                              
                              // Second row: 1 large item (starting) + 1 normal
                              QuiltedGridTile(2, 2), // index 3 (large)
                              QuiltedGridTile(1, 1), // index 4
                              
                              // Third row: (large item continues) + 1 normal
                              // The large item is handled by the 2x2 above
                              QuiltedGridTile(1, 1), // index 5
                            ],
                          ),
                          childrenDelegate: SliverChildBuilderDelegate(
                            (context, index) {
                              if (index >= filteredVideos.length) return null;
                              
                              // Check if this is a large item (every 4th item)
                              bool isLargeItem = index % 6 == 3;
                              
                        return _buildGridThumbnail(
                          theme, 
                          filteredVideos[index], 
                          isLargeItem,
                          () => _openFullscreenPostView(filteredVideos, index, isPublished)
                        );
                      },
                            childCount: filteredVideos.length,
                          ),
                        );
                      }
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  // Updated thumbnail builder for the new grid pattern
  Widget _buildGridThumbnail(
    ThemeData theme, 
    Map<String, dynamic> video, 
    bool isLargeItem,
    VoidCallback onTap
  ) {
    final status = video['status'] as String? ?? '';
    final publishedAt = video['published_at'] as int?;
    final isScheduled = status == 'scheduled' && publishedAt == null;
    final thumbnailPath = video['thumbnail_path'] as String?;
    final thumbnailCloudflareUrl = video['thumbnail_cloudflare_url'] as String?;
    final cloudflareUrl = video['cloudflare_url'] as String?;
    
    // Determine which platform this video is for based on the current account
    final platform = widget.platform.toLowerCase();
    final logoPath = _platformLogos[platform] ?? '';
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
      onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Thumbnail with better loading state
              _buildThumbnailImage(thumbnailCloudflareUrl, thumbnailPath, cloudflareUrl, theme),
                  
              // Dark gradient overlay for better text visibility
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.7),
                        Colors.black.withOpacity(0.3),
                        Colors.transparent,
                      ],
                      stops: [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
              
              // Platform and date info
              Positioned(
                bottom: 6,
                left: 6,
                right: 6,
                child: Row(
                  children: [
                    // Logo from assets with white background
                    Container(
                      width: isLargeItem ? 20 : 16, 
                      height: isLargeItem ? 20 : 16,
                      padding: EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 2,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      child: logoPath.isNotEmpty
                        ? Image.asset(
                            logoPath,
                            fit: BoxFit.contain,
                          )
                        : Icon(
                            Icons.public,
                            color: theme.colorScheme.primary,
                            size: isLargeItem ? 10 : 8,
                          ),
                    ),
                        SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _formatPostDate(video),
                            style: TextStyle(
                              color: Colors.white,
                          fontSize: isLargeItem ? 10 : 9,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    
                    // Status indicator for scheduled posts
                    if (isScheduled)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Scheduled',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isLargeItem ? 8 : 7,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build thumbnail image prioritizing Cloudflare URLs
  Widget _buildThumbnailImage(String? thumbnailCloudflareUrl, String? thumbnailPath, String? cloudflareUrl, ThemeData theme) {
    // First try thumbnail from Cloudflare
    if (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumbnailCloudflareUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Center(
          child: CircularProgressIndicator(
            value: null,
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
        errorWidget: (context, url, error) {
          // Try cloudflare video URL as thumbnail
          if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
            return CachedNetworkImage(
              imageUrl: cloudflareUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) => Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              errorWidget: (context, url, error) => _buildLocalThumbnail(thumbnailPath, theme),
              memCacheHeight: 300, // Smaller cache for grid items
            );
          }
          return _buildLocalThumbnail(thumbnailPath, theme);
        },
        memCacheHeight: 300, // Smaller cache for grid items
      );
    }
    
    // Then try cloudflare video URL as thumbnail
    if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: cloudflareUrl,
        fit: BoxFit.cover,
        placeholder: (context, url) => Center(
          child: CircularProgressIndicator(
            value: null,
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
        errorWidget: (context, url, error) => _buildLocalThumbnail(thumbnailPath, theme),
        memCacheHeight: 300, // Smaller cache for grid items
      );
    }
    
    // Fallback to local thumbnail
    return _buildLocalThumbnail(thumbnailPath, theme);
  }
  
  // Helper to build local thumbnail with fallback
  Widget _buildLocalThumbnail(String? thumbnailPath, ThemeData theme) {
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      return Image.file(
        File(thumbnailPath),
        fit: BoxFit.cover,
        cacheHeight: 300, // Limit memory usage
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: theme.colorScheme.surface.withOpacity(0.8),
            child: Center(
              child: Icon(
                Icons.image_not_supported_outlined,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
          );
        },
      );
    }
    
    return Container(
      color: theme.colorScheme.surface.withOpacity(0.8),
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 32,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
  
  // Helper per formattare la data del post
  String _formatPostDate(Map<String, dynamic> video) {
    final publishedAt = video['published_at'] as int?;
    final scheduledTime = video['scheduled_time'] as int?;
    final timestamp = video['timestamp'] as int;
    
    DateTime dateTime;
    if (publishedAt != null) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(publishedAt);
    } else if (scheduledTime != null) {
      dateTime = DateTime.fromMillisecondsSinceEpoch(scheduledTime);
    } else {
      dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    
    // Formato breve: "25 May" o "Today, 14:30"
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final postDate = DateTime(dateTime.year, dateTime.month, dateTime.day);
    
    if (postDate == today) {
      // Oggi, mostra solo l'ora
      return "Today, ${DateFormat('HH:mm').format(dateTime)}";
    } else {
      // Altro giorno, mostra giorno e mese
      return DateFormat('dd MMM').format(dateTime);
    }
  }
  
  String _formatTimestamp(DateTime timestamp, bool isScheduled) {
    if (isScheduled) {
      return DateFormat('dd/MM/yyyy HH:mm').format(timestamp);
    }
    
    final difference = DateTime.now().difference(timestamp);
    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} ${(difference.inDays / 365).floor() == 1 ? 'year' : 'years'} ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} ${(difference.inDays / 30).floor() == 1 ? 'month' : 'months'} ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} ${difference.inDays == 1 ? 'day' : 'days'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} ${difference.inHours == 1 ? 'hour' : 'hours'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} ${difference.inMinutes == 1 ? 'minute' : 'minutes'} ago';
    } else {
      return 'Just now';
    }
  }
  
  // Helper per ottenere l'icona della piattaforma
  Widget _getPlatformIcon() {
    IconData iconData;
    Color iconColor;
    
    switch (widget.platform.toLowerCase()) {
      case 'twitter':
        iconData = Icons.chat;
        iconColor = Colors.blue;
        break;
      case 'instagram':
        iconData = Icons.camera_alt;
        iconColor = Colors.purple;
        break;
      case 'facebook':
        iconData = Icons.facebook;
        iconColor = Colors.blue;
        break;
      case 'youtube':
        iconData = Icons.play_circle_outline;
        iconColor = Colors.red;
        break;
      case 'tiktok':
        iconData = Icons.music_note;
        iconColor = Colors.black;
        break;
      default:
        iconData = Icons.public;
        iconColor = Colors.grey;
        break;
    }
    
    return Icon(
      iconData,
      size: 12,
      color: iconColor,
    );
  }
  
  // Nuovo metodo per aprire la visualizzazione a schermo intero
  void _openFullscreenPostView(List<Map<String, dynamic>> videos, int initialIndex, bool isPublished) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _FullscreenPostView(
          videos: videos,
          initialIndex: initialIndex,
          platform: widget.platform,
          onOpenPost: _openSocialMedia,
          getPostUrl: _getPostUrl,
          formatTimestamp: _formatTimestamp,
          formatPostDate: _formatPostDate,
          getPlatformIcon: _getPlatformIcon,
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isPublished) {
    final theme = Theme.of(context);
    
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 48,
                color: theme.colorScheme.primary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try different keywords',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
              icon: Icon(Icons.refresh_rounded, size: 18),
              label: Text('Clear search'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
            isPublished ? Icons.video_library : Icons.schedule,
              size: 50,
              color: theme.colorScheme.primary.withOpacity(0.7),
          ),
          ),
          const SizedBox(height: 20),
          Text(
            isPublished ? 'No published videos' : 'No scheduled videos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              isPublished 
                ? 'Videos you publish will appear here'
                : 'Videos scheduled for future posting will appear here',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoDropdown() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              SizedBox(width: 12),
              Text(
                'About Account Details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoItem(
            'Content Overview',
            'View all published and scheduled content for this social account.',
            Icons.visibility,
          ),
          _buildInfoItem(
            'Real-time Updates',
            'Track your content status and engagement metrics in real-time.',
            Icons.update,
          ),
          _buildInfoItem(
            'Content Management',
            'Easily manage and monitor your social media content from one place.',
            Icons.manage_accounts,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String title, String description, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openSocialMedia(String url) async {
    print('Attempting to open URL: $url');
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        print('Could not launch URL: $url');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open the link. URL: $url')),
          );
        }
      }
    } catch (e) {
      print('Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening the link: $e')),
        );
      }
    }
  }

  String? _getPostUrl(Map<String, dynamic> video) {
    // Check either if it's a published post or a scheduled post that has been published
    final status = video['status'] as String? ?? '';
    final publishedAt = video['published_at'] as int?;
    
    if (!(status == 'published' || (status == 'scheduled' && publishedAt != null))) {
      return null;
    }

    final accounts = video['accounts'] as Map<dynamic, dynamic>?;
    if (accounts == null) return null;

    final platform = widget.platform.toLowerCase();
    final platformAccounts = accounts[platform] as List<dynamic>?;
    
    if (platformAccounts == null || platformAccounts.isEmpty) return null;

    // Find the matching account entry for the current account
    final currentUsername = widget.account['username']?.toString();
    if (currentUsername == null) return null;
    
    // Find the account data in the video's accounts list that matches the current account
    Map<dynamic, dynamic>? accountData;
    for (var account in platformAccounts) {
      if (account is Map && account['username']?.toString() == currentUsername) {
        accountData = account;
        break;
      }
    }
    
    if (accountData == null) return null;
    
    final username = accountData['username']?.toString();
    final postId = accountData['post_id']?.toString();
    final mediaId = accountData['media_id']?.toString();
    final scheduledTweetId = accountData['scheduled_tweet_id']?.toString();

    if (username != null) {
      if (platform == 'twitter' && (postId != null || scheduledTweetId != null)) {
        final tweetId = postId ?? scheduledTweetId;
        return 'https://twitter.com/i/status/$tweetId';
      } else if (platform == 'youtube' && (postId != null || mediaId != null)) {
        final videoId = postId ?? mediaId;
        return 'https://www.youtube.com/watch?v=$videoId';
      } else if (platform == 'facebook' && postId != null) {
        return 'https://facebook.com/$username/posts/$postId';
      } else if (platform == 'instagram' && mediaId != null) {
        return 'https://instagram.com/p/$mediaId';
      } else if (platform == 'tiktok' && mediaId != null) {
        return 'https://tiktok.com/@$username/video/$mediaId';
      }
    }
    return null;
  }

  Future<void> _openProfileUrl() async {
    final account = widget.account;
    String? profileUrl;

    switch (widget.platform.toLowerCase()) {
      case 'twitter':
        profileUrl = 'https://twitter.com/${account['username']}';
        break;
      case 'instagram':
        profileUrl = 'https://instagram.com/${account['username']}';
        break;
      case 'facebook':
        profileUrl = 'https://facebook.com/${account['username']}';
        break;
      case 'youtube':
        profileUrl = 'https://youtube.com/channel/${account['id']}';
        break;
      case 'tiktok':
        profileUrl = 'https://tiktok.com/@${account['username']}';
        break;
    }

    if (profileUrl != null) {
      final uri = Uri.parse(profileUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshVideos,
          color: theme.colorScheme.primary,
          backgroundColor: Colors.white,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _buildHeader(),
              ),
              SliverToBoxAdapter(
                child: _buildProfileSection(),
              ),
              SliverPersistentHeader(
                delegate: _SliverTabBarDelegate(
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TabBar(
                    controller: _tabController,
                    labelColor: theme.colorScheme.primary,
                        unselectedLabelColor: Colors.grey[400],
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                    indicatorColor: theme.colorScheme.primary,
                        indicatorWeight: 3,
                        indicatorSize: TabBarIndicatorSize.label,
                        dividerColor: Colors.transparent,
                    tabs: const [
                      Tab(text: 'Published'),
                      Tab(text: 'Scheduled'),
                    ],
                      ),
                    ),
                  ),
                ),
                pinned: true,
              ),
              SliverFillRemaining(
                child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(
                        color: theme.colorScheme.primary,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildVideoList(true),
                        _buildVideoList(false),
                      ],
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Delegate per rendere persistente la TabBar quando si scrolla
class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  
  _SliverTabBarDelegate(this.child);
  
  @override
  double get minExtent => 48;
  
  @override
  double get maxExtent => 48;
  
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return child;
  }
  
  @override
  bool shouldRebuild(_SliverTabBarDelegate oldDelegate) {
    return true;
  }
}

// Nuova classe per la visualizzazione a schermo intero in stile social media
class _FullscreenPostView extends StatefulWidget {
  final List<Map<String, dynamic>> videos;
  final int initialIndex;
  final String platform;
  final Function(String) onOpenPost;
  final String? Function(Map<String, dynamic>) getPostUrl;
  final String Function(DateTime, bool) formatTimestamp;
  final String Function(Map<String, dynamic>) formatPostDate;
  final Widget Function() getPlatformIcon;

  const _FullscreenPostView({
    required this.videos,
    required this.initialIndex,
    required this.platform,
    required this.onOpenPost,
    required this.getPostUrl,
    required this.formatTimestamp,
    required this.formatPostDate,
    required this.getPlatformIcon,
  });

  // Define platform logo paths
  Map<String, String> getPlatformLogos() {
    return {
      'twitter': 'assets/loghi/logo_twitter.png',
      'youtube': 'assets/loghi/logo_yt.png',
      'tiktok': 'assets/loghi/logo_tiktok.png',
      'instagram': 'assets/loghi/logo_insta.png',
      'facebook': 'assets/loghi/logo_facebook.png',
      'threads': 'assets/loghi/threads_logo.png',
    };
  }

  @override
  _FullscreenPostViewState createState() => _FullscreenPostViewState();
}

class _FullscreenPostViewState extends State<_FullscreenPostView> with SingleTickerProviderStateMixin {
  late PageController _pageController;
  int _currentIndex = 0;
  Map<int, bool> _expandedDescriptions = {};
  Map<int, VideoPlayerController?> _videoControllers = {};
  bool _isVideoLoading = false;
  Map<int, bool> _isVideoPlaying = {};
  // Added variables for progress bar
  Map<int, Duration> _currentPositions = {};
  Map<int, Duration> _durations = {};
  bool _isDraggingProgressBar = false;
  // Added variable for accounts section visibility
  Map<int, bool> _showAccountsSection = {};
  
  // Animation for description expansion
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _initializeVideoController(widget.initialIndex);
    
    // Initialize animation controller with faster duration
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _disposeAllVideoControllers();
    _animationController.dispose();
    super.dispose();
  }

  void _disposeAllVideoControllers() {
    for (var controller in _videoControllers.values) {
      controller?.dispose();
    }
    _videoControllers.clear();
  }

  Future<void> _initializeVideoController(int index) async {
    // Dispose any controller that's not the current one or adjacent to conserve memory
    _disposeNonVisibleControllers(index);
    
    if (_videoControllers.containsKey(index) && _videoControllers[index] != null) {
      // Controller already exists, just play it
      try {
        await _videoControllers[index]!.play();
        setState(() {
          _isVideoPlaying[index] = true;
        });
      } catch (e) {
        print('Error playing existing video: $e');
      }
      return;
    }

    final video = widget.videos[index];
    
    // Prioritize Cloudflare URL over local file to avoid memory issues
    final cloudflareUrl = video['cloudflare_url'] as String?;
    final videoPath = video['video_path'] as String?;
    
    if (cloudflareUrl == null || cloudflareUrl.isEmpty) {
      if (videoPath == null || videoPath.isEmpty) {
        _videoControllers[index] = null;
        return;
      }
      
      // Check if local file exists before trying to use it
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) {
        _videoControllers[index] = null;
        return;
      }
    }

    setState(() {
      _isVideoLoading = true;
    });

    try {
      VideoPlayerController controller;
      
      // Prioritize Cloudflare URL
      if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(cloudflareUrl),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
      } else {
        controller = VideoPlayerController.file(
          File(videoPath!),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
        );
      }
      
      _videoControllers[index] = controller;
      
      // Add listener for position updates
      controller.addListener(() {
        if (mounted && !_isDraggingProgressBar) {
          setState(() {
            _currentPositions[index] = controller.value.position;
            _durations[index] = controller.value.duration;
          });
        }
      });
      
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _isVideoPlaying[index] = true;
          _currentPositions[index] = controller.value.position;
          _durations[index] = controller.value.duration;
        });
      }
    } catch (e) {
      print('Error initializing video controller: $e');
      _videoControllers[index] = null;
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
          _isVideoPlaying[index] = false;
        });
      }
    }
  }

  // Dispose controllers that are not needed anymore to free memory
  void _disposeNonVisibleControllers(int currentIndex) {
    // Keep only the current controller and adjacent ones
    final keysToKeep = [currentIndex - 1, currentIndex, currentIndex + 1];
    
    for (var entry in _videoControllers.entries.toList()) {
      if (!keysToKeep.contains(entry.key)) {
        try {
          entry.value?.pause();
          entry.value?.dispose();
          _videoControllers.remove(entry.key);
        } catch (e) {
          print('Error disposing controller: $e');
        }
      }
    }
  }

  void _toggleDescription(int index) {
    setState(() {
      _expandedDescriptions[index] = !(_expandedDescriptions[index] ?? false);
      
      // Animate the fade in/out
      if (_expandedDescriptions[index] ?? false) {
        _animationController.forward();
      } else {
        _animationController.reverse();
      }
    });
  }

  // Toggle video play/pause when tapping screen
  void _togglePlayPause(int index) {
    final controller = _videoControllers[index];
    if (controller != null) {
      setState(() {
        if (controller.value.isPlaying) {
          controller.pause();
          _isVideoPlaying[index] = false;
        } else {
          controller.play();
          _isVideoPlaying[index] = true;
        }
      });
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.videos.length,
          onPageChanged: (index) {
            setState(() {
              _currentIndex = index;
            });
            
            // Pause all videos
            for (var controller in _videoControllers.values) {
              if (controller != null && controller.value.isPlaying) {
                controller.pause();
              }
            }
            
            // Initialize and play the new video
            _initializeVideoController(index);
          },
          scrollDirection: Axis.vertical,
          itemBuilder: (context, index) {
            final video = widget.videos[index];
            final title = video['title'] as String? ?? '';
            final description = video['description'] as String? ?? '';
            final status = video['status'] as String? ?? '';
            final publishedAt = video['published_at'] as int?;
            final isScheduled = status == 'scheduled' && publishedAt == null;
            final isExpanded = _expandedDescriptions[index] ?? false;
            final postUrl = widget.getPostUrl(video);
            final videoController = _videoControllers[index];
            final hasVideo = videoController != null && videoController.value.isInitialized;
            final isPlaying = _isVideoPlaying[index] ?? false;
            
            // Get current position and duration for progress bar
            final currentPosition = _currentPositions[index] ?? Duration.zero;
            final duration = _durations[index] ?? Duration.zero;
            
            return GestureDetector(
              onTap: () {
                // Toggle video playback on tap
                if (hasVideo) {
                  _togglePlayPause(index);
                }
              },
              child: Stack(
              fit: StackFit.expand,
              children: [
                // Video or Thumbnail with GestureDetector for play/pause
                  Container(
                    color: Colors.black,
                    child: hasVideo
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: videoController.value.aspectRatio,
                            child: VideoPlayer(videoController),
                          ),
                        )
                      : _buildMediaPreview(video)
                ),
                
                // Loading indicator for video
                if (_isVideoLoading && index == _currentIndex)
                  Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ),
                
                // Overlay gradient for better text visibility
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.5),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                        stops: [0.0, 0.2, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
                
                // Play/Pause indicator when tapped
                if (!_isVideoLoading && hasVideo)
                  AnimatedOpacity(
                    opacity: !isPlaying ? 1.0 : 0.0,
                    duration: Duration(milliseconds: 300),
                    child: Center(
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          !isPlaying ? Icons.play_arrow : Icons.pause,
                          color: Colors.white,
                          size: 50,
                        ),
                      ),
                    ),
                  ),
                
                // Content overlay - directly on video in social media style
                Positioned(
                  left: 16,
                  right: 16,
                    bottom: 95, // Increased to make more space for the button below
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Platform and date info
                      Row(
                        children: [
                          _buildPlatformLogo(widget.platform),
                          SizedBox(width: 10),
                          Text(
                            widget.formatTimestamp(
                              DateTime.fromMillisecondsSinceEpoch(
                                publishedAt ?? video['timestamp'] as int
                              ),
                              false
                            ),
                            style: TextStyle(
                              color: Colors.white,
                          fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Spacer(),
                          if (isScheduled)
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Scheduled',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      
                      SizedBox(height: 12),
                      
                      // Title with shadow for better readability
                      if (title.isNotEmpty)
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                offset: Offset(1, 1),
                                blurRadius: 3,
                                color: Colors.black.withOpacity(0.5),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      
                      SizedBox(height: 10),
                      
                        // Description with shadow and animated fade
                      if (description.isNotEmpty)
                        GestureDetector(
                          onTap: () => _toggleDescription(index),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                AnimatedCrossFade(
                                  firstChild: Text(
                                description,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1, 1),
                                      blurRadius: 3,
                                      color: Colors.black.withOpacity(0.5),
                                    ),
                                  ],
                                ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  secondChild: Text(
                                    description,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(1, 1),
                                          blurRadius: 3,
                                          color: Colors.black.withOpacity(0.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  crossFadeState: isExpanded 
                                      ? CrossFadeState.showSecond 
                                      : CrossFadeState.showFirst,
                                  duration: Duration(milliseconds: 200),
                              ),
                              if (description.split('\n').length > 2 || description.length > 100)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                  child: Text(
                                    isExpanded ? 'Show less' : 'Show more',
                                    style: TextStyle(
                                          color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 14,
                                      shadows: [
                                        Shadow(
                                          offset: Offset(1, 1),
                                          blurRadius: 3,
                                          color: Colors.black.withOpacity(0.5),
                                        ),
                                      ],
                                        ),
                                    ),
                                    ),
                                  ),
                              ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      
                      SizedBox(height: 12),
                      
                      // Accounts section toggle button
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _showAccountsSection[index] = !(_showAccountsSection[index] ?? false);
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.account_circle_outlined,
                                color: Colors.white,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Account Details',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                _showAccountsSection[index] ?? false 
                                    ? Icons.keyboard_arrow_up 
                                    : Icons.keyboard_arrow_down,
                                color: Colors.white,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                      // Accounts section
                      if (_showAccountsSection[index] ?? false)
                        Container(
                          margin: EdgeInsets.only(top: 12),
                          child: _buildAccountsList(video['accounts'] as Map<String, dynamic>? ?? {}, Theme.of(context)),
                        ),
                  ],
                ),
              ),
              ],
              ),
            );
          },
        ),
      ),
    );
  }
  
  Widget _buildPlatformLogo(String platform) {
    String logoPath;
    
    switch (platform.toLowerCase()) {
      case 'twitter':
        logoPath = 'assets/loghi/logo_twitter.png';
        break;
      case 'instagram':
        logoPath = 'assets/loghi/logo_insta.png';
        break;
      case 'facebook':
        logoPath = 'assets/loghi/logo_facebook.png';
        break;
      case 'youtube':
        logoPath = 'assets/loghi/logo_yt.png';
        break;
      case 'tiktok':
        logoPath = 'assets/loghi/logo_tiktok.png';
        break;
      default:
        logoPath = '';
        break;
    }
    
    if (logoPath.isNotEmpty) {
      return Container(
        width: 24,
        height: 24,
        padding: EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Image.asset(
          logoPath,
          fit: BoxFit.contain,
        ),
      );
    } else {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.public,
          color: Theme.of(context).colorScheme.primary,
          size: 14,
        ),
      );
    }
  }

  // Helper method to load media from Cloudflare or local file
  Widget _buildMediaPreview(Map<String, dynamic> video) {
    final cloudflareUrl = video['cloudflare_url'] as String?;
    final thumbnailCloudflareUrl = video['thumbnail_cloudflare_url'] as String?;
    final thumbnailPath = video['thumbnail_path'] as String?;
    
    // First try cloudflare video URL
    if (cloudflareUrl != null && cloudflareUrl.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: thumbnailCloudflareUrl ?? cloudflareUrl,
            fit: BoxFit.contain,
            placeholder: (context, url) => Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: Colors.black,
              child: Center(
                child: Icon(
                  Icons.video_library,
                  color: Colors.white.withOpacity(0.5),
                  size: 64,
                ),
              ),
            ),
            memCacheHeight: 720, // Limit memory cache size
          ),
          Center(
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow,
                color: Colors.white,
                size: 48,
              ),
            ),
          ),
        ],
      );
    }
    
    // Then try thumbnail from Cloudflare
    if (thumbnailCloudflareUrl != null && thumbnailCloudflareUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumbnailCloudflareUrl,
        fit: BoxFit.contain,
        placeholder: (context, url) => Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
        errorWidget: (context, url, error) {
          // Try local thumbnail as fallback
          if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
            final file = File(thumbnailPath);
            if (file.existsSync()) {
              return Image.file(
                file,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => _buildDefaultMediaPlaceholder(),
              );
            }
          }
          return _buildDefaultMediaPlaceholder();
        },
        memCacheHeight: 720, // Limit memory cache size
      );
    }
    
    // Then try local thumbnail
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      final file = File(thumbnailPath);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.contain,
          cacheHeight: 720, // Limit memory usage for local images too
          errorBuilder: (context, error, stackTrace) => _buildDefaultMediaPlaceholder(),
        );
      }
    }
    
    // Fallback
    return _buildDefaultMediaPlaceholder();
  }
  
  Widget _buildDefaultMediaPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Icon(
          Icons.image,
          color: Colors.white.withOpacity(0.5),
          size: 64,
        ),
      ),
    );
  }

  // Function to handle video play/pause on tap
  void _toggleVideoPlayback() {
    if (_videoControllers[_currentIndex] != null &&
        _videoControllers[_currentIndex]!.value.isInitialized) {
      setState(() {
        if (_videoControllers[_currentIndex]!.value.isPlaying) {
          _videoControllers[_currentIndex]!.pause();
          _isVideoPlaying[_currentIndex] = false;
        } else {
          _videoControllers[_currentIndex]!.play();
          _isVideoPlaying[_currentIndex] = true;
        }
      });
    }
  }

  // Helper function to get platform colors
  Color _getPlatformColor(String platform) {
    switch (platform.toLowerCase()) {
      case 'twitter':
        return Colors.blue;
      case 'youtube':
        return Colors.red;
      case 'tiktok':
        return Colors.black;
      case 'instagram':
        return Colors.purple;
      case 'facebook':
        return Colors.blue.shade800;
      case 'threads':
        return Colors.black87;
      default:
        return Colors.grey;
    }
  }

  // Helper function to get light platform colors
  Color _getPlatformLightColor(String platform) {
    switch (platform.toString().toLowerCase()) {
      case 'twitter':
        return Colors.blue.withOpacity(0.08);
      case 'youtube':
        return Colors.red.withOpacity(0.08);
      case 'tiktok':
        return Colors.black.withOpacity(0.05);
      case 'instagram':
        return Colors.purple.withOpacity(0.08);
      case 'facebook':
        return Colors.blue.shade800.withOpacity(0.08);
      case 'threads':
        return Colors.black87.withOpacity(0.05);
      default:
        return Colors.grey.withOpacity(0.08);
    }
  }

  Widget _buildAccountsList(Map<String, dynamic> accounts, ThemeData theme) {
    try {
      final platform = widget.platform.toLowerCase();
      final platformAccounts = accounts[platform] as List<dynamic>?;
      
      if (platformAccounts == null || platformAccounts.isEmpty) {
        return const SizedBox.shrink();
      }

      // Find the current account in the platform accounts
      final currentUsername = widget.account['username']?.toString();
      Map<dynamic, dynamic>? currentAccountData;
      
      for (var account in platformAccounts) {
        if (account is Map && account['username']?.toString() == currentUsername) {
          currentAccountData = account;
          break;
        }
      }

      if (currentAccountData == null) {
        return const SizedBox.shrink();
      }

      final username = currentAccountData['username']?.toString() ?? '';
      final displayName = currentAccountData['display_name']?.toString() ?? username;
      final profileImageUrl = currentAccountData['profile_image_url']?.toString();

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              offset: Offset(0, 5),
            ),
          ],
          border: Border.all(
            color: Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Platform header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _getPlatformLightColor(platform),
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: _getPlatformColor(platform).withOpacity(0.2),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      widget.getPlatformLogos()[platform] ?? '',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    platform.toUpperCase(),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _getPlatformColor(platform),
                    ),
                  ),
                ],
              ),
            ),
            
            // Divider
            Divider(height: 1, thickness: 1, color: theme.colorScheme.surfaceVariant),
            
            // Current account
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  // Profile image with shadow and border
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 5,
                          spreadRadius: 1,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: theme.colorScheme.surface,
                      backgroundImage: profileImageUrl?.isNotEmpty == true
                          ? NetworkImage(profileImageUrl)
                          : null,
                      child: profileImageUrl?.isNotEmpty != true
                          ? Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _getPlatformColor(platform).withOpacity(0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  (username.isNotEmpty ? username[0] : '?').toUpperCase(),
                                  style: TextStyle(
                                    color: _getPlatformColor(platform),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Account details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2),
                        Text(
                          '@$username',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  
                  // Remove account button
                  IconButton(
                    onPressed: () => _showRemoveAccountConfirmation(currentAccountData, platform),
                    icon: Icon(Icons.remove_circle_outline, size: 20),
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.red,
                      backgroundColor: Colors.red.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    tooltip: 'Remove account',
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('Error building accounts list: $e');
      return const SizedBox.shrink();
    }
  }

  Future<void> _showRemoveAccountConfirmation(Map<dynamic, dynamic> account, String platform) async {
    final theme = Theme.of(context);
    final username = account['username']?.toString() ?? '';
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: theme.brightness == Brightness.dark ? Colors.grey[900] : Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Remove Account',
                style: TextStyle(
                  color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to remove @$username from this post?',
                style: TextStyle(
                  color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This account will no longer be associated with this post.',
                style: TextStyle(
                  color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: theme.brightness == Brightness.dark ? Colors.grey[300] : Colors.grey[700],
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _removeAccountFromPost(account, platform);
              },
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _removeAccountFromPost(Map<dynamic, dynamic> account, String platform) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      // Get the current video being viewed
      final currentVideo = widget.videos[_currentIndex];
      final videoId = currentVideo['id'] as String;
      
      // Get the current accounts data
      final accounts = currentVideo['accounts'] as Map<dynamic, dynamic>? ?? {};
      final platformAccounts = accounts[platform] as List<dynamic>? ?? [];
      
      // Remove the account from the platform accounts list
      final updatedPlatformAccounts = platformAccounts.where((acc) => 
        acc['username'] != account['username']
      ).toList();
      
      // Update the accounts data
      final updatedAccounts = Map<String, dynamic>.from(accounts);
      updatedAccounts[platform] = updatedPlatformAccounts;
      
      // Update the video in Firebase
      await FirebaseDatabase.instance.ref()
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('videos')
          .child(videoId)
          .update({
        'accounts': updatedAccounts,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Account removed successfully'),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 8),
                Text('Error removing account: $e'),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }
} 