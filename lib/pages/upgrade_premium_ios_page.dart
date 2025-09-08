import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'dart:io';
import 'package:in_app_purchase/in_app_purchase.dart';

class UpgradePremiumIOSPage extends StatefulWidget {
  const UpgradePremiumIOSPage({super.key, this.suppressExtraPadding = false});

  final bool suppressExtraPadding;

  @override
  State<UpgradePremiumIOSPage> createState() => _UpgradePremiumIOSPageState();
}

class _UpgradePremiumIOSPageState extends State<UpgradePremiumIOSPage> {
  bool _isAnnualPlan = true;
  final PageController _pageController = PageController(viewportFraction: 0.85);
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 0;
  int _selectedPlan = 0; // 0: Gratuito, 1: Premium
  bool _isMenuExpanded = false; // Inizialmente la tendina è abbassata
  bool _isLoading = false;
  String? _currentUserPlanType; // Piano corrente
  bool _hasUsedTrial = false; // Se l'utente ha già utilizzato il trial
  bool _isUserPremium = false; // Se l'utente è premium
  String? _subscriptionStatus; // Status dell'abbonamento
  bool _isUserPremiumFromProfile = false; // Premium dal profilo
  Map<String, dynamic>? _userLocation; // Localizzazione utente
  bool _isLocationPermissionGranted = false; // Permessi localizzazione
  bool _isLocationLoading = false; // Caricamento posizione
  // In-App Purchases (iOS)
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  bool _storeAvailable = false;
  bool _isQueryingProducts = false;
  List<ProductDetails> _products = [];
  static const Set<String> _kProductIds = {
    'com.fluzar.premium.month4.online',
    'com.fluzar.premium.annual1.online',
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentUserPlan();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    _initIAP();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    _purchaseSub?.cancel();
    super.dispose();
  }

  Future<void> _initIAP() async {
    if (!Platform.isIOS) return; // Limita agli iPhone/iPad
    try {
      final available = await _inAppPurchase.isAvailable();
      setState(() {
        _storeAvailable = available;
      });
      if (!available) {
        return;
      }

      // Ascolta gli aggiornamenti degli acquisti
      _purchaseSub = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdated,
        onError: (Object error) {
          _showErrorSnackBar('Purchase error: $error');
        },
        onDone: () {},
      );

      await _queryProducts();
    } catch (e) {
      _showErrorSnackBar('Store not available: $e');
    }
  }

  Future<void> _queryProducts() async {
    if (_isQueryingProducts) return;
    setState(() {
      _isQueryingProducts = true;
    });
    try {
      final response = await _inAppPurchase.queryProductDetails(_kProductIds);
      if (response.error != null) {
        _showErrorSnackBar('Products error: ${response.error!.message}');
      }
      if (response.productDetails.isEmpty) {
        // Alcuni ID non trovati o non approvati su App Store Connect
        if (response.notFoundIDs.isNotEmpty) {
          _showErrorSnackBar('Products not found: ${response.notFoundIDs.join(', ')}');
        }
      }
      setState(() {
        _products = response.productDetails;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to fetch products: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isQueryingProducts = false;
        });
      }
    }
  }

  ProductDetails? _productForSelectedPlan() {
    final String id = _selectedPlan == 2
        ? 'com.fluzar.premium.annual1.online'
        : _selectedPlan == 1
            ? 'com.fluzar.premium.month4.online'
            : '';
    if (id.isEmpty) return null;
    try {
      return _products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _startPurchaseForSelectedPlan() async {
    if (!Platform.isIOS) {
      _showErrorSnackBar('Available on iOS only.');
      return;
    }
    if (!_storeAvailable) {
      _showErrorSnackBar('App Store not available.');
      return;
    }
    if (_selectedPlan == 0) {
      _showErrorSnackBar('Please select a Premium plan.');
      return;
    }
    if (_products.isEmpty) {
      await _queryProducts();
      if (_products.isEmpty) {
        _showErrorSnackBar('No products available.');
        return;
      }
    }
    final product = _productForSelectedPlan();
    if (product == null) {
      _showErrorSnackBar('Product not available for the selected plan.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final purchaseParam = PurchaseParam(productDetails: product);
      // Abbonamenti e non-consumabili usano buyNonConsumable su iOS
      final success = await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
      if (!success) {
        _showErrorSnackBar('Purchase not started.');
      }
    } catch (e) {
      _showErrorSnackBar('Purchase failed: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _onPurchaseUpdated(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.pending:
          setState(() {
            _isLoading = true;
          });
          break;
        case PurchaseStatus.canceled:
          _showErrorSnackBar('Purchase cancelled.');
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          if (purchase.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.error:
          _showErrorSnackBar('Error: ${purchase.error?.message ?? 'unknown'}');
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          if (purchase.pendingCompletePurchase) {
            await _inAppPurchase.completePurchase(purchase);
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            // In produzione si dovrebbe validare la ricevuta lato server
            final product = _products.firstWhere(
              (p) => p.id == purchase.productID,
              orElse: () => _productForSelectedPlan() ?? (throw Exception('Prodotto non trovato')),
            );
            final planType = product.id.contains('annual') ? 'annual' : 'monthly';
            await _deliverPurchaseToUser(purchase, planType, product);
            if (mounted) {
              setState(() {
                _isLoading = false;
                _currentUserPlanType = planType;
                _isUserPremium = true;
                _subscriptionStatus = 'active';
              });
              _showSuccessSnackBar('Purchase successful. Premium activated.');
            }
          } catch (e) {
            _showErrorSnackBar('Failed to deliver purchase: $e');
          } finally {
            if (purchase.pendingCompletePurchase) {
              await _inAppPurchase.completePurchase(purchase);
            }
          }
          break;
      }
    }
  }

  Future<void> _deliverPurchaseToUser(
    PurchaseDetails purchase,
    String planType,
    ProductDetails product,
  ) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final ref = FirebaseDatabase.instance.ref('users/users/${user.uid}');
    final subscriptionRef = ref.child('subscription');

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    await ref.update({
      'isPremium': true,
    });

    await subscriptionRef.update({
      'isPremium': true,
      'status': 'active',
      'plan_type': planType,
      'platform': 'ios_iap',
      'product_id': product.id,
      'purchase_id': purchase.purchaseID,
      'transaction_date_ms': nowMs,
    });

    // Sincronizza UI con i nuovi dati
    await _loadCurrentUserPlan();
  }

  /// Scrolla la pagina verso il basso per mostrare i piani
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  /// Carica il piano corrente dell'utente dal database
  Future<void> _loadCurrentUserPlan() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        final userRef = database.child('users/users/${user.uid}');
        final snapshot = await userRef.get();

        if (snapshot.exists) {
          final userData = snapshot.value as Map<dynamic, dynamic>;
          setState(() {
            _hasUsedTrial = userData['has_used_trial'] == true;
            _isUserPremiumFromProfile = userData['isPremium'] == true;
          });
          // Debug
          // print('Utente ha già utilizzato il trial: $_hasUsedTrial');
          // print('Utente è premium dal profilo: $_isUserPremiumFromProfile');
        }
      }

      // Carica la localizzazione dell'utente
      if (user != null) {
        try {
          final locationSnapshot = await FirebaseDatabase.instance
              .ref()
              .child('users/users/${user.uid}/profile/location')
              .get();

          if (locationSnapshot.exists) {
            setState(() {
              _userLocation = Map<String, dynamic>.from(locationSnapshot.value as Map);
              _isLocationPermissionGranted = true;
            });
          } else {
            setState(() {
              _isLocationPermissionGranted = false;
            });
          }
        } catch (e) {
          setState(() {
            _isLocationPermissionGranted = false;
          });
        }
      }

      // Verifica stato abbonamento e piano corrente da Realtime Database
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        final subscriptionRef = database.child('users/users/${user.uid}/subscription');
        final subscriptionSnapshot = await subscriptionRef.get();

        if (subscriptionSnapshot.exists) {
          final subscriptionData = subscriptionSnapshot.value as Map<dynamic, dynamic>;
          setState(() {
            _isUserPremium = subscriptionData['isPremium'] == true;
            _subscriptionStatus = subscriptionData['status'] as String?;
            _currentUserPlanType = (subscriptionData['plan_type'] as String?)?.toLowerCase();
          });
        }
      }

      // Imposta il piano di default in base al piano corrente
      if (_currentUserPlanType == 'monthly') {
        _selectedPlan = 1;
        _currentPage = 1;
      } else if (_currentUserPlanType == 'annual') {
        _selectedPlan = 2;
        _currentPage = 2;
      }

      _isMenuExpanded = false;

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    } catch (e) {
      // print('Errore nel caricamento del piano corrente: $e');
    }
  }

  /// Gestisce i permessi di localizzazione e ottiene la posizione dell'utente
  Future<bool> _handleLocationPermission() async {
    setState(() {
      _isLocationLoading = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showErrorSnackBar('Location services are disabled. Please enable them to continue.');
        setState(() {
          _isLocationLoading = false;
        });
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorSnackBar('Location permission denied.');
          setState(() {
            _isLocationLoading = false;
          });
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showErrorSnackBar('Location permission permanently denied. Please enable it in settings.');
        setState(() {
          _isLocationLoading = false;
        });
        return false;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        _userLocation = {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'country': place.country ?? '',
          'state': place.administrativeArea ?? '',
          'city': place.locality ?? '',
          'postalCode': place.postalCode ?? '',
          'street': place.street ?? '',
          'address': '${place.street ?? ''}, ${place.locality ?? ''}, ${place.administrativeArea ?? ''}, ${place.postalCode ?? ''}, ${place.country ?? ''}'.trim(),
        };

        setState(() {
          _isLocationPermissionGranted = true;
          _isLocationLoading = false;
        });

        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            await FirebaseDatabase.instance
                .ref()
                .child('users/users/${user.uid}/profile/location')
                .set(_userLocation);
          }
        } catch (e) {
          // ignore
        }

        return true;
      } else {
        _showErrorSnackBar('Unable to get address from location.');
        setState(() {
          _isLocationLoading = false;
        });
        return false;
      }
    } catch (e) {
      _showErrorSnackBar('Error getting location: $e');
      setState(() {
        _isLocationLoading = false;
      });
      return false;
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.red[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  bool _isButtonDisabled() {
    if (_isLoading || _isLocationLoading) return true;
    return false;
  }

  bool _isCurrentPlan(int selectedPlan) {
    if (_currentUserPlanType == null) return false;
    if (selectedPlan == 1 && _currentUserPlanType == 'monthly') return true;
    if (selectedPlan == 2 && _currentUserPlanType == 'annual') return true;
    return false;
  }

  String _getButtonText(int selectedPlan) {
    if (selectedPlan == 0) {
      return 'Current plan';
    } else if (_isCurrentPlan(selectedPlan)) {
      if (_subscriptionStatus == 'cancelled') {
        return 'Select this plan';
      }
      return 'View subscription details';
    } else {
      if (_hasUsedTrial) {
        return 'Select this plan';
      } else {
        return 'Start 3-Day Free Trial';
      }
    }
  }

  Future<void> _onUpgradePressed() async {
    if (_selectedPlan == 1 || _selectedPlan == 2) {
      await _startPurchaseForSelectedPlan();
    } else {
      _showErrorSnackBar('Please select a Premium plan.');
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(message)),
            ],
          ),
          backgroundColor: Colors.green[600],
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final plans = [
      {
        'title': 'Basic',
        'price': 'Free',
        'period': '',
        'gradient': [const Color(0xFF667eea), const Color(0xFF764ba2)],
      },
      {
        'title': 'Premium',
        'price': '€6,99',
        'period': '/month',
        'gradient': [const Color(0xFFFF6B6B), const Color(0xFFEE0979)],
      },
      {
        'title': 'Premium Annual',
        'price': '€59,99',
        'period': '/year',
        'gradient': [const Color(0xFF00C9FF), const Color(0xFF92FE9D)],
      },
    ];

    final selectedGradient = plans[_selectedPlan]['gradient'] as List<Color>;

    return Scaffold(
      body: Stack(
        children: [
          // Animated background
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: selectedGradient,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
          ),
          CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverPadding(
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).size.height * 0.05,
                ),
                sliver: SliverToBoxAdapter(
                  child: _buildHeroHeader(context),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildPlansCarousel(context),
              ),
              SliverPadding(
                padding: EdgeInsets.only(
                  bottom: 180 + MediaQuery.of(context).size.height * 0.13,
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildStickyCTA(context),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 250,
      child: SafeArea(
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Unlock the full potential',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black.withOpacity(0.3),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'More power, more automation, more visibility with Fluzar pro',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlansCarousel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final plans = [
      {
        'name': 'Basic',
        'price': 'Free',
        'features': [
          {
            'text': 'Videos per day: Limited',
            'icon': Icons.video_library_outlined,
            'isAvailable': true,
          },
          {
            'text': 'Credits: Limited',
            'icon': Icons.stars_outlined,
            'isAvailable': true,
          },
          {
            'text': 'AI Analysis: Not available',
            'icon': Icons.psychology_outlined,
            'isAvailable': false,
          },
          {
            'text': 'Priority support: Not available',
            'icon': Icons.support_agent_outlined,
            'isAvailable': false,
          },
          {
            'text': 'Climate support: Not available',
            'icon': Icons.eco_outlined,
            'isAvailable': false,
          },
        ],
      },
      {
        'name': 'Premium',
        'price': '€6,99/month',
        'trial': _hasUsedTrial ? null : '3 days free trial',
        'features': [
          {
            'text': 'Videos per day: Unlimited',
            'icon': Icons.video_library,
            'isAvailable': true,
          },
          {
            'text': 'Credits: Unlimited',
            'icon': Icons.stars,
            'isAvailable': true,
          },
          {
            'text': 'AI Analysis: Unlimited',
            'icon': Icons.psychology,
            'isAvailable': true,
          },
          {
            'text': 'Priority support: Premium',
            'icon': Icons.support_agent,
            'isAvailable': true,
          },
          {
            'text': '5% for CO2 reduction',
            'icon': Icons.eco,
            'isAvailable': true,
            'hasLink': true,
            'linkText': 'see more',
            'linkUrl': 'https://fluzar.com/climate',
          },
          if (!_hasUsedTrial)
            {
              'text': '3 days free trial included',
              'icon': Icons.free_breakfast,
              'isAvailable': true,
            },
        ],
      },
      {
        'name': 'Premium Annual',
        'price': '€59,99/year',
        'trial': _hasUsedTrial ? null : '3 days free trial',
        'features': [
          {
            'text': '3 months free',
            'icon': Icons.savings,
            'isAvailable': true,
          },
          {
            'text': 'Videos per day: Unlimited',
            'icon': Icons.video_library,
            'isAvailable': true,
          },
          {
            'text': 'Credits: Unlimited',
            'icon': Icons.stars,
            'isAvailable': true,
          },
          {
            'text': 'AI Analysis: Unlimited',
            'icon': Icons.psychology,
            'isAvailable': true,
          },
          {
            'text': 'Priority support: Premium',
            'icon': Icons.support_agent,
            'isAvailable': true,
          },
          {
            'text': '5% for CO2 reduction',
            'icon': Icons.eco,
            'isAvailable': true,
            'hasLink': true,
            'linkText': 'see more',
            'linkUrl': 'https://fluzar.com/climate',
          },
          if (!_hasUsedTrial)
            {
              'text': '3 days free trial included',
              'icon': Icons.free_breakfast,
              'isAvailable': true,
            },
        ],
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 350,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
                _selectedPlan = index;
                if (_isUserPremiumFromProfile && index == 0) {
                  _isMenuExpanded = false;
                } else {
                  _isMenuExpanded = true;
                }
              });
            },
            padEnds: true,
            itemCount: plans.length,
            itemBuilder: (context, index) {
              final plan = plans[index];
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                    BoxShadow(
                      color: Colors.white.withOpacity(0.8),
                      blurRadius: 2,
                      spreadRadius: -1,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan['name'] as String,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ShaderMask(
                        shaderCallback: (Rect bounds) {
                          return const LinearGradient(
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
                          plan['price'] as String,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (plan['trial'] != null) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            plan['trial'] as String,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ...(plan['features'] as List<Map<String, dynamic>>).map((feature) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: feature['isAvailable'] as bool
                                  ? ShaderMask(
                                      shaderCallback: (Rect bounds) {
                                        return const LinearGradient(
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
                                        feature['icon'] as IconData,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    )
                                  : Icon(
                                      feature['icon'] as IconData,
                                      color: Colors.grey[400],
                                      size: 18,
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      feature['text'] as String,
                                      style: theme.textTheme.bodyMedium?.copyWith(
                                        color: feature['isAvailable'] as bool 
                                            ? Colors.grey[700] 
                                            : Colors.grey[400],
                                      ),
                                    ),
                                  ),
                                  if (feature['hasLink'] == true)
                                    GestureDetector(
                                      onTap: () async {
                                        final url = Uri.parse(feature['linkUrl'] as String);
                                        if (await canLaunchUrl(url)) {
                                          await launchUrl(url, mode: LaunchMode.externalApplication);
                                        }
                                      },
                                      child: Text(
                                        feature['linkText'] as String,
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )).toList(),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            plans.length,
            (index) => AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: _currentPage == index ? 24 : 8,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: _currentPage == index
                    ? Colors.white
                    : Colors.white.withOpacity(0.4),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyCTA(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final plans = [
      {
        'title': 'Basic',
        'price': 'Free',
        'period': '',
        'gradient': [const Color(0xFF667eea), const Color(0xFF764ba2)],
      },
      {
        'title': 'Premium',
        'price': '€6,99',
        'period': '/month',
        'gradient': [const Color(0xFFFF6B6B), const Color(0xFFEE0979)],
      },
      {
        'title': 'Premium Annual',
        'price': '€59,99',
        'period': '/year',
        'savings': 'Save 28%',
        'gradient': [const Color(0xFF00C9FF), const Color(0xFF92FE9D)],
      },
    ];

    final selectedPlan = plans[_selectedPlan];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isUserPremiumFromProfile || _selectedPlan != 0)
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (!(_isUserPremiumFromProfile && _selectedPlan == 0)) {
                      _isMenuExpanded = !_isMenuExpanded;
                    }
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: AnimatedRotation(
                    duration: const Duration(milliseconds: 300),
                    turns: _isMenuExpanded ? 0.5 : 0,
                    child: Icon(
                      Icons.keyboard_arrow_up,
                      color: isDark ? Colors.white : Colors.black87,
                      size: 20,
                    ),
                  ),
                ),
              ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 300),
              firstChild: Column(
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.10),
                ],
              ),
              secondChild: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              selectedPlan['title'] as String,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (selectedPlan['savings'] != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                selectedPlan['savings'] as String,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.primaryColor,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return const LinearGradient(
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
                              selectedPlan['price'] as String,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            selectedPlan['period'] as String,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topRight,
                          end: Alignment.bottomLeft,
                          colors: selectedPlan['gradient'] as List<Color>,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        onPressed: _isButtonDisabled() ? null : () async {
                          await _onUpgradePressed();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isLoading || _isLocationLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                _getButtonText(_selectedPlan),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                  SizedBox(height: widget.suppressExtraPadding ? 0 : MediaQuery.of(context).size.height * 0.10),
                ],
              ),
              crossFadeState: (_isMenuExpanded && (!_isUserPremiumFromProfile || _selectedPlan != 0)) ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            ),
          ],
        ),
      ),
    );
  }
}


