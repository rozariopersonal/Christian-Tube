import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../../../core/api/api_client.dart';
import '../models/promotion_status.dart';

class ReleasePromotionService {
  final Dio _dio;

  ReleasePromotionService({ApiClient? apiClient, Dio? dio})
      : _dio = dio ?? (apiClient ?? ApiClient()).dio;

  Future<PromotionStatus> fetchStatus() async {
    try {
      final response = await _dio.get('/admin/releases/status');
      if (response.statusCode == 200 && response.data != null) {
        return PromotionStatus.fromJson(response.data as Map<String, dynamic>);
      }
      throw Exception('Invalid server response: ${response.statusCode}');
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? e.message ?? 'Network error';
      debugPrint('ReleasePromotionService.fetchStatus error: $message');
      throw Exception(message);
    }
  }

  Future<String> promoteToProduction() async {
    try {
      final response = await _dio.post('/admin/releases/promote');
      if (response.statusCode == 200 || response.statusCode == 201) {
        return response.data?['message'] as String? ??
            'Production release successfully initiated!';
      }
      throw Exception('Failed to initiate release: ${response.statusCode}');
    } on DioException catch (e) {
      final message =
          e.response?.data?['message'] ?? e.message ?? 'Network error';
      debugPrint('ReleasePromotionService.promoteToProduction error: $message');
      throw Exception(message);
    }
  }
}
