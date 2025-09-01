import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:twitter_api_v2/twitter_api_v2.dart' as v2;
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:async';

class TwitterLoginPage extends StatefulWidget {
  const TwitterLoginPage({super.key});

  @override
  State<TwitterLoginPage> createState() => _TwitterLoginPageState();
}

class _TwitterLoginPageState extends State<TwitterLoginPage> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  // Twitter API credentials
  static const String _apiKey = 'sTn3lkEWn47KiQl41zfGhjYb4';
  static const String _apiKeySecret = 'Z5UvLwLysPoX2fzlbebCIn63cQ3yBo0uXiqxK88v1fXcz3YrYA';
  static const String _bearerToken = 'AAAAAAAAAAAAAAAAAAAAABSU0QEAAAAAo4YuWM0KL95fvPVsVk0EuIp%2B8tM%3DMh7GqySbNJX4qoTC3lpEycVl3x9cqQaRvbt1mwckSXszlBLmzM';
  static const String _accessToken = '1854892180193624064-DTblJdRTeYVNLpgAZPDomab286q7VB';
  static const String _accessTokenSecret = 'NxhkhdQifTYU7J5ek1i962RRqECPCs9CyaNDzr8YjLCMw';
  
  // Animation controller for background
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    
    // Initialize animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 20000),
    )..repeat(reverse: true);
    
    _animation = Tween<double>(begin: -0.05, end: 0.05).animate(_animationController);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Helper method to sanitize username for Firebase path
  String _sanitizeUsername(String username) {
    return username.replaceAll(RegExp(r'[@.#$\[\]]'), '').toLowerCase();
  }

  Future<void> _connectTwitterAccount() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User not authenticated');
      }

      final username = _usernameController.text.trim();
      final sanitizedUsername = _sanitizeUsername(username);
      final now = DateTime.now().millisecondsSinceEpoch;
      
      print('Connecting Twitter account: $username');
      print('Sanitized username: $sanitizedUsername');

      // Initialize Twitter API with OAuth 2.0
      final twitter = v2.TwitterApi(
        bearerToken: _bearerToken,
        oauthTokens: v2.OAuthTokens(
          consumerKey: _apiKey,
          consumerSecret: _apiKeySecret,
          accessToken: _accessToken,
          accessTokenSecret: _accessTokenSecret,
        ),
        retryConfig: v2.RetryConfig(
          maxAttempts: 3,
          onExecute: (event) => print('Retrying... ${event.retryCount} times.'),
        ),
      );

      // Get user data from Twitter API
      final response = await twitter.users.lookupByName(
        username: username,
        expansions: [
          v2.UserExpansion.pinnedTweetId,
        ],
        userFields: [
          v2.UserField.description,
          v2.UserField.location,
          v2.UserField.profileImageUrl,
          v2.UserField.publicMetrics,
        ],
      );

      if (response.data == null) {
        throw Exception('Twitter account not found');
      }

      final twitterUser = response.data!;
      final database = FirebaseDatabase.instance.ref();
      
      // Controlla se esiste già un account con lo stesso username
      String? existingAccountId;
      try {
        final existingAccountsSnapshot = await database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('twitter')
            .get();
        
        if (existingAccountsSnapshot.exists && existingAccountsSnapshot.value is Map) {
          final existingAccounts = existingAccountsSnapshot.value as Map<dynamic, dynamic>;
          for (final entry in existingAccounts.entries) {
            if (entry.value is Map) {
              final accountData = entry.value as Map<dynamic, dynamic>;
              if (accountData['username'] == twitterUser.username) {
                existingAccountId = entry.key;
                break;
              }
            }
          }
        }
      } catch (e) {
        print('Error checking existing account: $e');
      }
      
      // Prepara i dati dell'account
      final accountData = {
        'username': twitterUser.username,
        'username_key': sanitizedUsername,
        'display_name': twitterUser.name,
        'profile_image_url': twitterUser.profileImageUrl ?? '',
        'description': twitterUser.description ?? '',
        'location': twitterUser.location ?? '',
        'followers_count': twitterUser.publicMetrics?.followersCount ?? 0,
        'following_count': twitterUser.publicMetrics?.followingCount ?? 0,
        'tweet_count': twitterUser.publicMetrics?.tweetCount ?? 0,
        'twitter_id': twitterUser.id,
        'created_at': now,
        'last_sync': now,
        'status': 'active',
        'access_type': 'oauth1', // Indica che è OAuth 1 (accesso limitato)
        'bearer_token': _bearerToken,
        'api_key': _apiKey,
        'api_key_secret': _apiKeySecret,
        'access_token': _accessToken,
        'access_token_secret': _accessTokenSecret,
      };
      
      // Salva o aggiorna l'account
      if (existingAccountId != null) {
        // Aggiorna l'account esistente
        await database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('twitter')
            .child(existingAccountId)
            .update(accountData);
        print('Updated existing Twitter account: $existingAccountId');
      } else {
        // Crea nuovo account
        final accountRef = database
            .child('users')
            .child('users')
            .child(currentUser.uid)
            .child('social_accounts')
            .child('twitter')
            .push();
        print('Saving new Twitter account at path: ${accountRef.path}');
        await accountRef.set(accountData);
      }

      // Update user profile with Twitter data
      await database
          .child('users')
          .child('users')
          .child(currentUser.uid)
          .child('profile')
          .update({
        'display_name': twitterUser.name,
        'profile_image_url': twitterUser.profileImageUrl ?? '',
        'last_updated': now,
      });

      // REMOVED: No longer using social_accounts_index to avoid duplicates
      // Twitter accounts are saved ONLY in users/users/{uid}/social_accounts/twitter/{id}

      print('Twitter account connected successfully');

      if (mounted) {
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      print('Error connecting Twitter account: $e');
      if (mounted) {
        String errorMessage = 'Unable to connect Twitter account.               Make sure you enter the correct credentials.';
        
        // Check for specific error types to provide more helpful messages
        if (e.toString().contains('not found')) {
          errorMessage = 'Twitter account not found. Please check your username.';
        } else if (e.toString().contains('unauthorized') || e.toString().contains('authentication')) {
          errorMessage = 'Invalid credentials. Please check your username and password.';
        } else if (e.toString().contains('network')) {
          errorMessage = 'Network error. Please check your connection.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(child: Text(errorMessage)),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: Duration(seconds: 4),
          ),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark ? Colors.grey[900]! : Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[100]!,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back,
                        color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                  Hero(
                    tag: 'twitter_logo',
                    child: Image.asset(
                      'assets/loghi/logo_twitter.png',
                      width: 36,
                      height: 36,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 40),
              
              // Header - ridotto leggermente l'altezza
              Text(
                'Connect Your Twitter Account',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                  height: 1.1,
                ),
              ),

              
              const SizedBox(height: 60),
              
              // Form
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // Username field
                      Text(
                        'Username',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.brightness == Brightness.dark ? Colors.white : Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          hintText: 'Enter your Twitter username',
                          hintStyle: TextStyle(
                            color: theme.brightness == Brightness.dark ? Colors.grey[500] : Colors.grey[400],
                          ),
                          prefixIcon: Icon(
                            Icons.alternate_email,
                            color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                            size: 20,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          filled: true,
                          fillColor: theme.brightness == Brightness.dark ? Colors.grey[850]! : Colors.white,
                        ),
                        style: TextStyle(
                          color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your Twitter username';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 16),
                      
                      // Password field
                      Text(
                        'Password',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: theme.brightness == Brightness.dark ? Colors.white : Colors.grey[800],
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          hintText: 'Enter your Twitter password',
                          hintStyle: TextStyle(
                            color: theme.brightness == Brightness.dark ? Colors.grey[500] : Colors.grey[400],
                          ),
                          prefixIcon: Icon(
                            Icons.lock_outline,
                            color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                            size: 20,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[600],
                              size: 20,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[300]!,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                              width: 2,
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          filled: true,
                          fillColor: theme.brightness == Brightness.dark ? Colors.grey[850]! : Colors.white,
                        ),
                        style: TextStyle(
                          color: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter your password';
                          }
                          return null;
                        },
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Security notice - ridotta altezza padding
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.brightness == Brightness.dark ? Colors.grey[800]! : Colors.grey[100]!,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: theme.brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[300]!,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.security,
                              color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[700],
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Your credentials are only used for authentication. We never store your password.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[700],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Connect button
                      SizedBox(
                        width: double.infinity,
                        height: 50, // Ridotta leggermente l'altezza
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _connectTwitterAccount,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.brightness == Brightness.dark ? Colors.white : Colors.black,
                            foregroundColor: theme.brightness == Brightness.dark ? Colors.black : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      theme.brightness == Brightness.dark ? Colors.black : Colors.white
                                    ),
                                  ),
                                )
                              : const Text(
                                  'Connect Twitter Account',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Cancel button
                      SizedBox(
                        width: double.infinity,
                        height: 50, // Ridotta leggermente l'altezza
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          style: TextButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: theme.brightness == Brightness.dark ? Colors.grey[700]! : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            foregroundColor: theme.brightness == Brightness.dark ? Colors.grey[400] : Colors.grey[700],
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }
} 