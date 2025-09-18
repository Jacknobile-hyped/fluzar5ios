import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:ui'; // <--- AGGIUNTO per ImageFilter

class ContactSupportPage extends StatefulWidget {
  const ContactSupportPage({super.key});

  @override
  State<ContactSupportPage> createState() => _ContactSupportPageState();
}

class _ContactSupportPageState extends State<ContactSupportPage> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  String _selectedCategory = 'General Feedback';
  bool _isLoading = false;

  static const List<Map<String, dynamic>> _categories = [
    {
      'title': 'General Feedback',
      'icon': Icons.feedback_outlined,
      'color': Color(0xFF6C63FF),
    },
    {
      'title': 'Feature Request',
      'icon': Icons.lightbulb_outline,
      'color': Color(0xFFFF6B6B),
    },
    {
      'title': 'Bug Report',
      'icon': Icons.bug_report_outlined,
      'color': Color(0xFFFF6584),
    },
    {
      'title': 'App Experience',
      'icon': Icons.psychology_outlined,
      'color': Color(0xFF00C9FF),
    },
  ];

  Future<void> _sendFeedback() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final String subject = Uri.encodeComponent('[Feedback - ${_selectedCategory}] Fluzar App Feedback');
      final String body = Uri.encodeComponent('Category: $_selectedCategory\n\nFeedback:\n${_messageController.text}');
      final String mailtoLink = 'mailto:fluzar.contact@gmail.com?subject=$subject&body=$body';

      if (await canLaunchUrl(Uri.parse(mailtoLink))) {
        await launchUrl(Uri.parse(mailtoLink));
      } else {
        throw 'Could not launch email client';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
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
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      appBar: null,
      body: Stack(
        children: [
          // Main content area - no padding, content can scroll behind floating header
          SafeArea(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: EdgeInsets.only(
                      top: 70 + MediaQuery.of(context).size.height * 0.06, // Reduced by 30 pixels
                      left: 20, 
                      right: 20, 
                      bottom: 20
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildFeedbackForm(theme),
                      ],
                    ),
                  ),
          ),
          
          // Floating header
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: _buildHeader(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        // Effetto vetro sospeso
        color: isDark 
            ? Colors.white.withOpacity(0.15) 
            : Colors.white.withOpacity(0.25),
        borderRadius: BorderRadius.circular(25),
        // Bordo con effetto vetro
        border: Border.all(
          color: isDark 
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.4),
          width: 1,
        ),
        // Ombre per effetto sospeso
        boxShadow: [
          BoxShadow(
            color: isDark 
                ? Colors.black.withOpacity(0.4)
                : Colors.black.withOpacity(0.15),
            blurRadius: isDark ? 25 : 20,
            spreadRadius: isDark ? 1 : 0,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: isDark 
                ? Colors.white.withOpacity(0.1)
                : Colors.white.withOpacity(0.6),
            blurRadius: 2,
            spreadRadius: -2,
            offset: const Offset(0, 2),
          ),
        ],
        // Gradiente sottile per effetto vetro
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: theme.brightness == Brightness.dark ? Colors.white : Colors.black87,
                      size: 22,
                    ),
                    onPressed: () => Navigator.pop(context),
                  ),
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
                      'Fluzar',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        fontFamily: 'Ethnocentric',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbackForm(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    const Color iconColor = Color(0xFF667eea); // Updated to match gradient
    
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header section
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
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
                        blurRadius: 10,
                        offset: const Offset(0, 3),
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
                        transform: GradientRotation(135 * 3.14159 / 180),
                      ).createShader(bounds);
                    },
                    child: Icon(
                      Icons.feedback_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share Your Feedback',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Help us improve Fluzar with your valuable input',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isDark ? Colors.grey[300] : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // Category dropdown
            Text(
              'Feedback Category',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  icon: Icon(
                    Icons.arrow_drop_down,
                    color: iconColor,
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: InputBorder.none,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  dropdownColor: isDark ? Colors.grey[800] : Colors.white,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 16,
                  ),
                  items: _categories.map((category) {
                    return DropdownMenuItem<String>(
                      value: category['title'],
                      child: Row(
                        children: [
                          Icon(
                            category['icon'],
                            color: category['color'],
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Text(category['title']),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedCategory = newValue;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Message field
            _buildTextField(
              theme,
              controller: _messageController,
              label: 'Your Feedback',
              hint: 'Tell us what you think about Fluzar...',
              maxLines: 5,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please share your feedback';
                }
                if (value.length < 10) {
                  return 'Please provide more details (at least 10 characters)';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            
            // Submit button
            SizedBox(
              width: double.infinity,
              child: Container(
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
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isLoading ? null : _sendFeedback,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: _isLoading
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : Text(
                                'Send Feedback',
                                style: TextStyle(
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
            const SizedBox(height: 16),
            
            // Privacy note
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your feedback helps us improve Fluzar. We respect your privacy and will only use this information to enhance the app.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    ThemeData theme, {
    required TextEditingController controller,
    required String label,
    required String hint,
    IconData? prefixIcon,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    const Color iconColor = Color(0xFF667eea); // Updated to match gradient
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: isDark ? Colors.grey[500] : Colors.grey[400],
            ),
            prefixIcon: prefixIcon != null
                ? Icon(
                    prefixIcon,
                    color: iconColor,
                  )
                : null,
            fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: iconColor,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Colors.red,
              ),
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: 16,
              vertical: maxLines > 1 ? 16 : 0,
            ),
          ),
          validator: validator,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }
} 