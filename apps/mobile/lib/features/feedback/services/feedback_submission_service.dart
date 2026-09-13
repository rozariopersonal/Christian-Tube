import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../core/config/app_config.dart';
import '../models/feedback_report.dart';

class FeedbackSubmissionResult {
  final bool isSuccess;
  final String? issueNumber;
  final String? issueUrl;
  final String? errorMessage;

  const FeedbackSubmissionResult({
    required this.isSuccess,
    this.issueNumber,
    this.issueUrl,
    this.errorMessage,
  });
}

class FeedbackSubmissionService {
  final Dio _dio;

  FeedbackSubmissionService({Dio? dio}) : _dio = dio ?? Dio();

  /// Derives an issue title from the first sentence or first 60 characters.
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

  /// Formats the markdown body with feedback text, context badge, and diagnostics.
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
    buffer.writeln('| **Timestamp** | `${report.timestamp.toUtc().toIso8601String()}` |');
    return buffer.toString();
  }

  /// Submits the feedback directly to GitHub Issues (or backend proxy fallback).
  Future<FeedbackSubmissionResult> submitFeedback(FeedbackReport report) async {
    final title = deriveIssueTitle(report.text, report.screenContext);
    final body = formatMarkdownBody(report);

    final token = AppConfig.githubFeedbackToken;
    final repo = AppConfig.feedbackRepo;

    // 1. Direct GitHub Issues API
    if (token != null && token.isNotEmpty) {
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
            sendTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 12),
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
      } catch (e) {
        debugPrint('FeedbackSubmissionService: direct GitHub API error: $e');
        // Proceed to backend fallback if direct GitHub request failed
      }
    }

    // 2. Backend API fallback
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
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : (response.data is String ? jsonDecode(response.data) : {});
        return FeedbackSubmissionResult(
          isSuccess: true,
          issueNumber: data['issueNumber']?.toString(),
          issueUrl: data['issueUrl'] as String?,
        );
      } else {
        return FeedbackSubmissionResult(
          isSuccess: false,
          errorMessage: 'Server responded with status ${response.statusCode}',
        );
      }
    } catch (e) {
      debugPrint('FeedbackSubmissionService: fallback error: $e');
      return const FeedbackSubmissionResult(
        isSuccess: false,
        errorMessage: 'Unable to submit feedback. Please check your connection.',
      );
    }
  }
}
