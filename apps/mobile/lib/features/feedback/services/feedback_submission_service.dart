import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/config/app_config.dart';
import '../models/feedback_report.dart';

class FeedbackSubmissionResult {
  final bool isSuccess;
  final bool isTransientFailure;
  final String? issueNumber;
  final String? issueUrl;
  final String? errorMessage;

  const FeedbackSubmissionResult({
    required this.isSuccess,
    this.isTransientFailure = false,
    this.issueNumber,
    this.issueUrl,
    this.errorMessage,
  });
}

class FeedbackSubmissionService {
  final Dio _dio;

  static const int _maxRetries = 2;
  static const Duration _baseRetryDelay = Duration(seconds: 1);

  FeedbackSubmissionService({Dio? dio}) : _dio = dio ?? Dio();

  String deriveIssueTitle(String text, String screenContext) {
    final clean = text.replaceAll('\n', ' ').trim();
    if (clean.isEmpty) return '[Feedback] User report on $screenContext';

    final firstSentenceEnd = clean.indexOf(RegExp(r'[.!?]'));
    String summary = firstSentenceEnd != -1
        ? clean.substring(0, firstSentenceEnd + 1).trim()
        : clean;

    const prefix = '[Feedback] ';
    const maxTotalLength = 75;
    const maxSummaryLength = maxTotalLength - prefix.length;

    if (summary.length > maxSummaryLength) {
      summary = '${summary.substring(0, maxSummaryLength - 3)}...';
    }
    return '$prefix$summary';
  }

  String formatMarkdownBody(FeedbackReport report) {
    final buffer = StringBuffer();
    buffer.writeln('### 📝 User Feedback');
    buffer.writeln();
    buffer.writeln(report.text.trim());
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln('### 📍 Context');
    buffer.writeln('- **Screen:** `${report.screenContext}`');
    buffer.writeln('- **Route:** `${report.route}`');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln('### 📱 Diagnostics');
    buffer.writeln('| Property | Value |');
    buffer.writeln('| :--- | :--- |');
    report.diagnostics.forEach((key, value) {
      buffer.writeln('| **$key** | `$value` |');
    });
    buffer.writeln(
        '| **Timestamp** | `${report.timestamp.toUtc().toIso8601String()}` |');
    return buffer.toString();
  }

  Future<FeedbackSubmissionResult> submitFeedback(FeedbackReport report) async {
    final title = deriveIssueTitle(report.text, report.screenContext);
    final body = formatMarkdownBody(report);

    final token = AppConfig.githubFeedbackToken;
    final repo = AppConfig.feedbackRepo;

    if (token != null && token.isNotEmpty) {
      final result = await _submitToGitHub(title, body, token, repo);
      if (result.isSuccess) return result;
      // Fall back to the backend proxy only for transient failures
      // (network/5xx). A definitive 401/403/422 from GitHub means the
      // credentials or payload are wrong — surfacing that error beats
      // silently routing to a fallback that will record nothing.
      if (!result.isTransientFailure) return result;
      debugPrint(
          'FeedbackSubmissionService: direct GitHub failed, trying backend');
    }

    return _submitToBackend(title, body, report);
  }

  Future<FeedbackSubmissionResult> _submitToGitHub(
    String title,
    String body,
    String token,
    String repo,
  ) async {
    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      if (attempt > 0) {
        final delay = _baseRetryDelay * math.pow(2, attempt - 1);
        debugPrint(
            'FeedbackSubmissionService: retry $attempt/$_maxRetries after ${delay.inSeconds}s');
        await Future<void>.delayed(delay);
      }

      try {
        final response = await _dio.post(
          'https://api.github.com/repos/$repo/issues',
          data: {
            'title': title,
            'body': body,
            'labels': ['user-feedback'],
          },
          options: Options(
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'ChristianApp',
              'Content-Type': 'application/json',
            },
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final data = response.data is Map<String, dynamic>
              ? response.data as Map<String, dynamic>
              : (response.data is String ? jsonDecode(response.data) : {});
          return FeedbackSubmissionResult(
            isSuccess: true,
            issueNumber: data['number']?.toString(),
            issueUrl: data['html_url'] as String?,
          );
        }

        if (response.statusCode == 403 || response.statusCode == 422) {
          final msg = _extractGitHubError(response);
          debugPrint(
              'FeedbackSubmissionService: GitHub ${response.statusCode}: $msg');
          return FeedbackSubmissionResult(
            isSuccess: false,
            isTransientFailure: false,
            errorMessage: 'GitHub API error ${response.statusCode}: $msg',
          );
        }

        debugPrint(
            'FeedbackSubmissionService: GitHub ${response.statusCode}, attempt ${attempt + 1}');
      } on DioException catch (e) {
        debugPrint(
            'FeedbackSubmissionService: GitHub DioException attempt ${attempt + 1}: ${e.message}');
        if (attempt == _maxRetries) {
          return FeedbackSubmissionResult(
            isSuccess: false,
            isTransientFailure: true,
            errorMessage: 'GitHub API connection failed: ${e.message}',
          );
        }
      }
    }

    return const FeedbackSubmissionResult(
      isSuccess: false,
      isTransientFailure: true,
      errorMessage: 'GitHub API submission failed after retries',
    );
  }

  Future<FeedbackSubmissionResult> _submitToBackend(
    String title,
    String body,
    FeedbackReport report,
  ) async {
    try {
      final response = await _dio.post(
        '${AppConfig.apiBaseUrl}/api/feedback',
        data: {
          'title': title,
          'body': body,
          'screenContext': report.screenContext,
          'route': report.route,
          'diagnostics': report.diagnostics,
          'rawText': report.text,
        },
        options: Options(
          headers: {'Content-Type': 'application/json'},
          sendTimeout: const Duration(seconds: 12),
          receiveTimeout: const Duration(seconds: 12),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : (response.data is String ? jsonDecode(response.data) : {});

        final isSuccess = data['success'] == true || data['isSuccess'] == true;

        return FeedbackSubmissionResult(
          isSuccess: isSuccess,
          issueNumber: data['issueNumber']?.toString(),
          issueUrl: data['issueUrl'] as String?,
          errorMessage: isSuccess
              ? null
              : (data['message']?.toString() ?? 'Server reported failure'),
        );
      } else {
        return FeedbackSubmissionResult(
          isSuccess: false,
          errorMessage: 'Server responded with status ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('FeedbackSubmissionService: backend error: $e');
      return const FeedbackSubmissionResult(
        isSuccess: false,
        errorMessage: 'Unable to submit feedback. Please check your connection.',
      );
    }
  }

  String _extractGitHubError(Response response) {
    try {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data['message']?.toString() ?? 'Unknown error';
      }
    } catch (_) {}
    return 'Request failed';
  }
}
