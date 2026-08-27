import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppConfig {
  static String instanceId = 'christian_tube';
  static String appName = 'ChristianApp';
  static String applicationId = 'org.rozario.christiantube.mobile';
  static String version = '1.28.0';
  static int versionCode = 45;
  static String apiBaseUrl = 'https://christianapp-zjdh.onrender.com';
  static String releasesRepo = 'rozariopersonal/Christian-Tube-Releases';
  static String apkFileName = 'christian-app.apk';
  static String? googleClientId;

  static Color primaryColor = const Color(0xFF2563EB);
  static Color accentColor = const Color(0xFFF59E0B);
  static Color darkBackground = const Color(0xFF0F172A);
  static Color lightBackground = const Color(0xFFFFFFFF);

  static List<String> defaultCategories = const [
    'All',
    'Worship',
    'Sermons',
    'Testimonies',
    'Bible Study',
    'Youth',
    'Gospel Music',
    'Kids',
  ];

  // Micro-Feed Configuration
  static bool microFeedEnabled = false;
  static String microFeedEngine = 'scripture';
  static String microFeedTabTitle = 'Micro Feeds';
  static String microFeedTabIcon = 'auto_awesome_outlined';
  static String microFeedDefaultVersion = 'NASB';

  static Color _parseColor(String? hexString, Color fallback) {
    if (hexString == null || hexString.isEmpty) return fallback;
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> initialize() async {
    try {
      final configString = await rootBundle.loadString('assets/app_config.json');
      final Map<String, dynamic> json = jsonDecode(configString);

      instanceId = json['instanceId'] ?? instanceId;
      appName = json['appName'] ?? appName;
      applicationId = json['applicationId'] ?? applicationId;
      version = json['version'] ?? version;
      versionCode = json['versionCode'] ?? versionCode;
      apiBaseUrl = json['apiBaseUrl'] ?? apiBaseUrl;
      releasesRepo = json['releasesRepo'] ?? releasesRepo;
      apkFileName = json['apkFileName'] ?? apkFileName;
      googleClientId = json['googleClientId'];

      if (json['microFeed'] != null && json['microFeed'] is Map) {
        final mf = json['microFeed'] as Map<String, dynamic>;
        microFeedEnabled = mf['enabled'] == true;
        microFeedEngine = mf['engine'] ?? microFeedEngine;
        microFeedTabTitle = mf['tabTitle'] ?? microFeedTabTitle;
        microFeedTabIcon = mf['tabIcon'] ?? microFeedTabIcon;
        microFeedDefaultVersion = mf['defaultBibleVersion'] ?? microFeedDefaultVersion;
      }

      if (json['theme'] != null) {
        primaryColor = _parseColor(json['theme']['primaryColor'], primaryColor);
        accentColor = _parseColor(json['theme']['accentColor'], accentColor);
        darkBackground = _parseColor(json['theme']['darkBackground'], darkBackground);
        lightBackground = _parseColor(json['theme']['lightBackground'], lightBackground);
      }

      if (json['defaultCategories'] != null && json['defaultCategories'] is List) {
        defaultCategories = List<String>.from(json['defaultCategories']);
      }
    } catch (e) {
      debugPrint('AppConfig loaded default fallback config: $e');
    }
  }
}
