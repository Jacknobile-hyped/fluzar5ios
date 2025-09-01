import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../pages/settings_page.dart';
import 'package:provider/provider.dart';

class TutorialProvider extends ChangeNotifier {
  bool _isTutorialComplete = false;
  int _currentStep = 0;
  bool _isInitialized = false;
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  final List<TutorialStep> _steps = [
    TutorialStep(
              title: 'Welcome to Fluzar!',
      description: 'Let\'s take a quick tour of the app to help you get started.',
      targetKey: GlobalKey(debugLabel: 'welcome'),
      position: TutorialPosition.center,
      navigationIndex: 2, // Home tab
    ),
    TutorialStep(
      title: 'Connect Your Accounts',
      description: 'Start by connecting your social media accounts to manage them all in one place.',
      targetKey: GlobalKey(debugLabel: 'accounts'),
      position: TutorialPosition.center,
      navigationIndex: 0, // Accounts tab
    ),
    TutorialStep(
      title: 'Upload Content',
      description: 'Upload your videos and share them across multiple platforms simultaneously.',
      targetKey: GlobalKey(debugLabel: 'upload'),
      position: TutorialPosition.center,
      navigationIndex: 1, // Upload tab
    ),
    TutorialStep(
      title: 'Video History',
      description: 'Keep track of all your videos here. You can view both published videos and drafts in progress.',
      targetKey: GlobalKey(debugLabel: 'history'),
      position: TutorialPosition.center,
      navigationIndex: 3, // History tab
    ),
    TutorialStep(
      title: 'Settings & Preferences',
      description: 'Customize your experience with dark mode, notifications, and other settings.',
      targetKey: GlobalKey(debugLabel: 'settings'),
      position: TutorialPosition.center,
      navigationIndex: 2,
      onStepShown: (BuildContext context) async {
        final provider = Provider.of<TutorialProvider>(context, listen: false);
        // Push to settings page and wait for it to complete
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const SettingsPage(),
            maintainState: true,
          ),
        );
        // Return to home page after completing the tutorial
        if (provider.isLastStep) {
          provider.skipTutorial();
        }
      },
    ),
  ];

  bool get isTutorialComplete => _isTutorialComplete;
  int get currentStep => _currentStep;
  List<TutorialStep> get steps => _steps;
  bool get isLastStep => _currentStep == _steps.length - 1;
  bool get isInitialized => _isInitialized;

  Future<void> init() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      _isTutorialComplete = prefs.getBool('tutorial_complete') ?? false;
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing tutorial: $e');
      _isInitialized = true;
      _isTutorialComplete = false;
      notifyListeners();
    }
  }

  void startTutorial() {
    _isTutorialComplete = false;
    _currentStep = 0;
    notifyListeners();
  }

  Future<void> nextStep() async {
    try {
      final currentStep = _steps[_currentStep];
      
      if (isLastStep) {
        // Execute onStepComplete callback if available
        if (currentStep.onStepComplete != null && navigatorKey.currentContext != null) {
          currentStep.onStepComplete!(navigatorKey.currentContext!);
        }
        _isTutorialComplete = true;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('tutorial_complete', true);
      } else {
        _currentStep++;
        // Execute onStepShown callback for the new step if available
        final nextStep = _steps[_currentStep];
        if (nextStep.onStepShown != null && navigatorKey.currentContext != null) {
          nextStep.onStepShown!(navigatorKey.currentContext!);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error advancing tutorial step: $e');
      if (!isLastStep) {
        _currentStep++;
        notifyListeners();
      }
    }
  }

  Future<void> skipTutorial() async {
    try {
      _isTutorialComplete = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tutorial_complete', true);
      
      // Return to home page
      if (navigatorKey.currentContext != null) {
        Navigator.of(navigatorKey.currentContext!).popUntil((route) => route.isFirst);
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error skipping tutorial: $e');
      _isTutorialComplete = true;
      notifyListeners();
    }
  }

  void setTargetKey(int stepIndex, GlobalKey key) {
    if (stepIndex < _steps.length) {
      _steps[stepIndex] = _steps[stepIndex].copyWith(targetKey: key);
      notifyListeners();
    }
  }

  void resetTutorial() {
    _isTutorialComplete = false;
    _currentStep = 0;
    notifyListeners();
  }

  void refreshTutorial() {
    notifyListeners();
  }
}

class TutorialStep {
  final String title;
  final String description;
  final GlobalKey targetKey;
  final TutorialPosition position;
  final int navigationIndex;
  final Function(BuildContext)? onStepShown;
  final Function(BuildContext)? onStepComplete;

  TutorialStep({
    required this.title,
    required this.description,
    required this.targetKey,
    this.position = TutorialPosition.center,
    this.navigationIndex = 2,
    this.onStepShown,
    this.onStepComplete,
  });

  TutorialStep copyWith({
    String? title,
    String? description,
    GlobalKey? targetKey,
    TutorialPosition? position,
    int? navigationIndex,
    Function(BuildContext)? onStepShown,
    Function(BuildContext)? onStepComplete,
  }) {
    return TutorialStep(
      title: title ?? this.title,
      description: description ?? this.description,
      targetKey: targetKey ?? this.targetKey,
      position: position ?? this.position,
      navigationIndex: navigationIndex ?? this.navigationIndex,
      onStepShown: onStepShown ?? this.onStepShown,
      onStepComplete: onStepComplete ?? this.onStepComplete,
    );
  }
}

enum TutorialPosition {
  center,
} 