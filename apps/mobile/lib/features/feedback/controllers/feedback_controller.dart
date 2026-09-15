import 'package:flutter/material.dart';
import '../models/feedback_report.dart';
import '../services/feedback_submission_service.dart';
import '../services/speech_recognition_service.dart';

enum FeedbackSubmitState {
  idle,
  submitting,
  success,
  error,
}

class FeedbackController extends ChangeNotifier {
  final SpeechRecognitionService _speechService;
  final FeedbackSubmissionService _submissionService;

  String _text = '';
  bool _isListening = false;
  double _soundLevel = 0.0;
  String _screenContext = 'General';
  String _route = '/';
  Map<String, dynamic> _diagnostics = {};
  FeedbackSubmitState _submitState = FeedbackSubmitState.idle;
  String? _errorMessage;
  String? _submittedIssueNumber;
  String? _submittedIssueUrl;

  FeedbackController({
    SpeechRecognitionService? speechService,
    FeedbackSubmissionService? submissionService,
  })  : _speechService = speechService ?? SpeechRecognitionService(),
        _submissionService = submissionService ?? FeedbackSubmissionService();

  String get text => _text;
  bool get isListening => _isListening;
  double get soundLevel => _soundLevel;
  String get screenContext => _screenContext;
  FeedbackSubmitState get submitState => _submitState;
  String? get errorMessage => _errorMessage;
  String? get submittedIssueNumber => _submittedIssueNumber;
  String? get submittedIssueUrl => _submittedIssueUrl;

  bool get canSubmit =>
      _text.trim().isNotEmpty &&
      _submitState != FeedbackSubmitState.submitting;

  void initializeContext({
    required String screenContext,
    required String route,
    required Map<String, dynamic> diagnostics,
  }) {
    _screenContext = screenContext;
    _route = route;
    _diagnostics = diagnostics;
    notifyListeners();
  }

  void updateText(String newText) {
    _text = newText;
    notifyListeners();
  }

  void resetToIdle() {
    _submitState = FeedbackSubmitState.idle;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> startListening({String? localeId}) async {
    _isListening = true;
    notifyListeners();

    await _speechService.startListening(
      localeId: localeId,
      onResult: (recognizedWords, isFinal) {
        if (recognizedWords.isNotEmpty) {
          _text = recognizedWords;
          notifyListeners();
        }
        if (isFinal) {
          _isListening = false;
          _soundLevel = 0.0;
          notifyListeners();
        }
      },
      onSoundLevelChange: (level) {
        _soundLevel = level;
        notifyListeners();
      },
    );
  }

  Future<void> stopListening() async {
    await _speechService.stopListening();
    _isListening = false;
    _soundLevel = 0.0;
    notifyListeners();
  }

  Future<void> toggleListening({String? localeId}) async {
    if (_isListening) {
      await stopListening();
    } else {
      await startListening(localeId: localeId);
    }
  }

  Future<bool> submit() async {
    if (!canSubmit) return false;

    if (_isListening) {
      await stopListening();
    }

    _submitState = FeedbackSubmitState.submitting;
    _errorMessage = null;
    notifyListeners();

    final report = FeedbackReport(
      text: _text,
      screenContext: _screenContext,
      route: _route,
      diagnostics: _diagnostics,
    );

    final result = await _submissionService.submitFeedback(report);

    if (result.isSuccess) {
      _submitState = FeedbackSubmitState.success;
      _submittedIssueNumber = result.issueNumber;
      _submittedIssueUrl = result.issueUrl;
      notifyListeners();
      return true;
    } else {
      _submitState = FeedbackSubmitState.error;
      _errorMessage = result.errorMessage ?? 'Submission failed';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _speechService.cancelListening();
    super.dispose();
  }
}
