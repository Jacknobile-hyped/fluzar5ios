import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/stripe_service.dart';
import '../services/onesignal_service.dart';

class PaymentSuccessPage extends StatefulWidget {
  final String? sessionId;
  final String? subscriptionId;
  final String? paymentIntentId;
  final String? planType; // Aggiungo il parametro per il tipo di piano
  final Map<String, dynamic>? subscriptionData; // Aggiungo il parametro per i dati dell'abbonamento
  
  const PaymentSuccessPage({
    super.key, 
    this.sessionId, 
    this.subscriptionId,
    this.paymentIntentId,
    this.planType, // Aggiungo il parametro
    this.subscriptionData, // Aggiungo il parametro
  });

  @override
  State<PaymentSuccessPage> createState() => _PaymentSuccessPageState();
}

class _PaymentSuccessPageState extends State<PaymentSuccessPage> {
  bool _isLoading = false;
  bool _isSuccess = true;
  String _message = 'Payment completed successfully!                 Your Premium subscription is now active.';
  Map<String, dynamic>? _subscriptionData;

  @override
  void initState() {
    super.initState();
    print('PaymentSuccessPage: Inizializzazione con subscriptionData: ${widget.subscriptionData}');
    print('PaymentSuccessPage: Customer ID ricevuto: ${widget.subscriptionData?['customer_id']}');
    _loadSubscriptionData();
  }

  Future<void> _loadSubscriptionData() async {
    try {
      // Se abbiamo i dati dell'abbonamento completi, usali
      if (widget.subscriptionData != null) {
        print('Utilizzando dati abbonamento completi: ${widget.subscriptionData}');
        await _updateUserSubscription(widget.subscriptionData!);
        
        setState(() {
          _subscriptionData = widget.subscriptionData;
        });
      } else {
        // Fallback per compatibilità: usa paymentIntentId se disponibile, altrimenti subscriptionId o sessionId
        final id = widget.paymentIntentId ?? widget.subscriptionId ?? widget.sessionId;
        
        if (id != null) {
          // Per ora, aggiorna direttamente lo stato dell'utente nel database
          // In futuro, potresti voler verificare il payment intent con Stripe
          await _updateUserSubscription({
            'id': id,
            'status': 'active',
            'current_period_end': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
            'cancel_at_period_end': false,
          });
          
          setState(() {
            _subscriptionData = {
              'id': id,
              'status': 'active',
              'current_period_end': DateTime.now().add(const Duration(days: 30)).millisecondsSinceEpoch ~/ 1000,
              'cancel_at_period_end': false,
            };
          });
        }
      }
    } catch (e) {
      print('Errore durante il caricamento dei dati: $e');
    }
  }

  Future<void> _updateUserSubscription(Map<String, dynamic> subscription) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final database = FirebaseDatabase.instance.ref();
        
        // Verifica se l'utente ha già avuto una subscription in passato
        final userRef = database.child('users/users/${user.uid}');
        final snapshot = await userRef.get();
        
        bool isFirstSubscription = true;
        if (snapshot.exists) {
          final userData = snapshot.value as Map<dynamic, dynamic>;
          // Verifica se esiste già il flag has_used_trial
          isFirstSubscription = userData['has_used_trial'] == null;
        }
        
        // Prepara i dati da aggiornare
        final updates = <String, dynamic>{
          'subscription': <String, dynamic>{
          'status': subscription['status'],
          'subscription_id': subscription['id'],
          'current_period_end': subscription['current_period_end'],
          'cancel_at_period_end': subscription['cancel_at_period_end'],
          'updated_at': ServerValue.timestamp,
          },
          'isPremium': true, // Aggiorna anche il flag premium
        };

        // Aggiungi il plan_type se disponibile
        if (widget.planType != null) {
          (updates['subscription'] as Map<String, dynamic>)['plan_type'] = widget.planType;
        }

        // Se abbiamo un customer_id, salvalo
        if (subscription['customer_id'] != null) {
          updates['stripe_customer_id'] = subscription['customer_id'];
          print('✅ Customer ID salvato in Firebase: ${subscription['customer_id']}');
        } else {
          print('⚠️ Customer ID non trovato nei dati dell\'abbonamento');
        }

        // Aggiorna il database
        await database.child('users/users/${user.uid}').update(updates);
        
        // Track premium subscription with OneSignal
        try {
          await OneSignalService.trackPremiumEvent(
            eventType: 'subscription_started',
            planId: widget.planType ?? 'premium',
          );
          
          // Update OneSignal user tags
          await OneSignalService.addTag('is_premium', 'true');
          await OneSignalService.addTag('subscription_status', subscription['status']);
          if (widget.planType != null) {
            await OneSignalService.addTag('plan_type', widget.planType!);
          }
          
          print('OneSignal tracking completed for premium subscription');
        } catch (e) {
          print('Error tracking OneSignal premium event: $e');
        }
        
        // Se è la prima subscription, salva le informazioni per il trial
        if (isFirstSubscription) {
          final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
          await userRef.update({
            'has_used_trial': true,
            'first_subscription_date': currentTimestamp,
            'trial_used_at': currentTimestamp,
          });
          print('Prima subscription dell\'utente - Trial utilizzato');
        } else {
          print('Subscription successiva - Trial già utilizzato in passato');
        }
      }
    } catch (e) {
      print('Errore durante l\'aggiornamento dell\'abbonamento: $e');
    }
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          child: ShaderMask(
            shaderCallback: (Rect bounds) {
              return LinearGradient(
                colors: [
                  const Color(0xFF667eea),
                  const Color(0xFF764ba2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                transform: GradientRotation(135 * 3.14159 / 180),
              ).createShader(bounds);
            },
            child: Icon(
              icon,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.black87,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.3,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icona di successo
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF667eea).withOpacity(0.1),
                    shape: BoxShape.circle,
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
                        transform: GradientRotation(135 * 3.14159 / 180),
                      ).createShader(bounds);
                    },
                    child: const Icon(
                      Icons.check_circle,
                      size: 60,
                      color: Colors.white,
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                // Titolo
                ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return LinearGradient(
                      colors: [
                        const Color(0xFF667eea),
                        const Color(0xFF764ba2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      transform: GradientRotation(135 * 3.14159 / 180),
                    ).createShader(bounds);
                  },
                  child: Text(
                    'Payment Completed!',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 28,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Messaggio
                Text(
                  _message,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.black54,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 32),
                
                // Card funzionalità sbloccate
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
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
                                transform: GradientRotation(135 * 3.14159 / 180),
                              ).createShader(bounds);
                            },
                            child: Icon(
                              Icons.star,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Premium Features Unlocked',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        icon: Icons.video_library_outlined,
                        title: 'Unlimited Videos',
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureItem(
                        icon: Icons.stars_outlined,
                        title: 'Unlimited Credits',
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureItem(
                        icon: Icons.psychology_outlined,
                        title: 'AI Analysis',
                      ),
                      const SizedBox(height: 12),
                      _buildFeatureItem(
                        icon: Icons.support_agent_outlined,
                        title: 'Priority Support',
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 48),
                
                // Pulsante principale
                SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF667eea),
                          const Color(0xFF764ba2),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        transform: GradientRotation(135 * 3.14159 / 180),
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF667eea).withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () async {
                          // Naviga alla home in modo sicuro
                          if (context.mounted) {
                            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: Text(
                              'Back to App',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 