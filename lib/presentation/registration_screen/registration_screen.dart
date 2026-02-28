import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sizer/sizer.dart';

import '../../core/app_export.dart';
import '../../widgets/custom_app_bar.dart';
import './widgets/device_id_field_widget.dart';
import './widgets/referral_code_field_widget.dart';
import './widgets/registration_button_widget.dart';
import './widgets/terms_acceptance_widget.dart';

/// Registration screen for new users to join the 180-day token earning game
/// Implements device-based authentication with optional referral code input
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen>
    with SingleTickerProviderStateMixin {
  // Form controllers
  final TextEditingController _referralCodeController = TextEditingController();

  // State variables
  String _deviceId = '';
  bool _isTermsAccepted = false;
  bool _isLoading = false;
  bool _isReferralCodeValid = false;
  bool _showReferralValidation = false;

  // Animation controller for success celebration
  late AnimationController _celebrationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeCelebrationAnimation();
    _generateDeviceId();
    _checkDeepLinkReferral();
  }

  @override
  void dispose() {
    _referralCodeController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  /// Initialize celebration animation for successful registration
  void _initializeCelebrationAnimation() {
    _celebrationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _celebrationController, curve: Curves.elasticOut),
    );
  }

  /// Generate unique device ID using device_info_plus
  Future<void> _generateDeviceId() async {
    try {
      // Simulated device ID generation
      // In production, use device_info_plus package
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final deviceId = 'DEV${timestamp.toString().substring(5)}';

      setState(() {
        _deviceId = deviceId;
      });
    } catch (e) {
      setState(() {
        _deviceId = 'DEV${DateTime.now().millisecondsSinceEpoch}';
      });
    }
  }

  /// Check for deep link referral code
  Future<void> _checkDeepLinkReferral() async {
    // In production, implement deep link handling
    // For now, this is a placeholder for the functionality
    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Validate referral code format and availability
  Future<void> _validateReferralCode(String code) async {
    if (code.isEmpty) {
      setState(() {
        _showReferralValidation = false;
        _isReferralCodeValid = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _showReferralValidation = false;
    });

    try {
      // Simulate API call to validate referral code
      await Future.delayed(const Duration(milliseconds: 800));

      // Mock validation: codes starting with 'REF' are valid
      final isValid = code.toUpperCase().startsWith('REF') && code.length >= 8;

      setState(() {
        _isReferralCodeValid = isValid;
        _showReferralValidation = true;
        _isLoading = false;
      });

      if (isValid) {
        _showSuccessFeedback();
      }
    } catch (e) {
      setState(() {
        _isReferralCodeValid = false;
        _showReferralValidation = true;
        _isLoading = false;
      });
      _showErrorMessage('Failed to validate referral code. Please try again.');
    }
  }

  /// Show success feedback with haptic
  void _showSuccessFeedback() {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Valid referral code!'),
        backgroundColor: Theme.of(context).colorScheme.tertiary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Show error message
  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Handle registration process
  Future<void> _handleRegistration() async {
    if (!_isTermsAccepted) {
      _showErrorMessage('Please accept the terms and conditions to continue');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // Simulate registration API call
      await Future.delayed(const Duration(seconds: 2));

      // Mock registration success
      final registrationSuccess = true;

      if (registrationSuccess) {
        // Show celebration animation
        await _celebrationController.forward();

        // Navigate to onboarding/dashboard
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/dashboard-screen');
        }
      } else {
        throw Exception('Registration failed');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      if (e.toString().contains('duplicate')) {
        _showErrorMessage(
          'This device is already registered. Please login instead.',
        );
      } else if (e.toString().contains('network')) {
        _showErrorMessage(
          'Network error. Please check your connection and try again.',
        );
      } else {
        _showErrorMessage('Registration failed. Please try again later.');
      }
    }
  }

  /// Copy device ID to clipboard
  void _copyDeviceId() {
    Clipboard.setData(ClipboardData(text: _deviceId));
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Device ID copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Open terms of service in browser
  void _openTermsOfService() {
    // In production, use url_launcher package
    _showErrorMessage('Terms of Service will open in browser');
  }

  /// Open privacy policy in browser
  void _openPrivacyPolicy() {
    // In production, use url_launcher package
    _showErrorMessage('Privacy Policy will open in browser');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: CustomAppBar(
        title: 'Create Account',
        variant: AppBarVariant.withBack,
        onLeadingPressed: () {
          Navigator.pop(context);
        },
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Main content
            SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: 2.h),

                  // App Logo and Welcome Message
                  _buildLogoSection(theme),

                  SizedBox(height: 4.h),

                  // Device ID field
                  DeviceIdFieldWidget(
                    deviceId: _deviceId,
                    onCopy: _copyDeviceId,
                  ),

                  SizedBox(height: 3.h),

                  // Referral code field
                  ReferralCodeFieldWidget(
                    controller: _referralCodeController,
                    isValid: _isReferralCodeValid,
                    showValidation: _showReferralValidation,
                    onChanged: (value) {
                      if (value.length >= 8) {
                        _validateReferralCode(value);
                      } else {
                        setState(() {
                          _showReferralValidation = false;
                        });
                      }
                    },
                    onPaste: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _referralCodeController.text = data!.text!;
                        _validateReferralCode(data.text!);
                      }
                    },
                  ),

                  SizedBox(height: 4.h),

                  // Terms acceptance
                  TermsAcceptanceWidget(
                    isAccepted: _isTermsAccepted,
                    onChanged: (value) {
                      setState(() {
                        _isTermsAccepted = value ?? false;
                      });
                    },
                    onTermsTap: _openTermsOfService,
                    onPrivacyTap: _openPrivacyPolicy,
                  ),

                  SizedBox(height: 4.h),

                  // Registration button
                  RegistrationButtonWidget(
                    isEnabled: _isTermsAccepted && !_isLoading,
                    isLoading: _isLoading,
                    onPressed: _handleRegistration,
                  ),

                  SizedBox(height: 3.h),

                  // Login link
                  _buildLoginLink(theme),

                  SizedBox(height: 2.h),
                ],
              ),
            ),

            // Celebration overlay
            if (_celebrationController.isAnimating)
              _buildCelebrationOverlay(theme),
          ],
        ),
      ),
    );
  }

  /// Build app logo
  Widget _buildLogoSection(ThemeData theme) {
    return Column(
      children: [
        // Logo container with shadow for better visibility
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                blurRadius: 20,
                spreadRadius: 2,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.2),
              width: 3,
            ),
          ),
          padding: const EdgeInsets.all(15),
          child: CustomImageWidget(
            imageUrl: 'assets/images/SQUARE-1767596263038.png',
            fit: BoxFit.contain,
            semanticLabel: 'NAVA PEACE Logo',
          ),
        ),
        SizedBox(height: 2.h),
        GestureDetector(
          onTap: () {
            Navigator.pushNamed(context, AppRoutes.pitchScreen);
          },
          child: Text(
            'Join the Peace Movement',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: theme.colorScheme.primary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          'Start your 180-day token earning journey',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Build welcome message
  Widget _buildWelcomeMessage(ThemeData theme) {
    return Column(
      children: [
        GestureDetector(
          onTap: () {
            Navigator.pushNamed(context, AppRoutes.pitchScreen);
          },
          child: Text(
            'Join the Peace Movement',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(height: 1.h),
        Text(
          'Create your secure device ID to start earning daily tokens',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  /// Build login link
  Widget _buildLoginLink(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        GestureDetector(
          onTap: () {
            Navigator.pushReplacementNamed(context, '/login-screen');
          },
          child: Text(
            'Login',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// Build celebration overlay
  Widget _buildCelebrationOverlay(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface.withValues(alpha: 0.95),
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30.w,
                height: 30.w,
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: CustomIconWidget(
                    iconName: 'check_circle',
                    size: 15.w,
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ),
              SizedBox(height: 3.h),
              Text(
                'Welcome Aboard!',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 1.h),
              Text(
                'Your earning journey begins now',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
