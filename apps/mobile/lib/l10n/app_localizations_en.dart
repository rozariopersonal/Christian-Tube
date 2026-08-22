import 'app_localizations.dart';
import '../core/config/app_config.dart';

class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([super.locale = 'en']);

  @override
  String get appTitle => AppConfig.appName;
  @override
  String get feed => 'Home';
  @override
  String get shorts => 'Shorts';
  @override
  String get channels => 'Channels';
  @override
  String get watchPlans => 'Watch Plans';
  @override
  String get profile => 'You';
  @override
  String get search => 'Search ${AppConfig.appName} videos...';
  @override
  String get subscriptions => 'Subscriptions';
  @override
  String get history => 'History';
  @override
  String get playlists => 'Playlists';
  @override
  String get settings => 'Settings';
  @override
  String get signInWithGoogle => 'Sign in with Google';
  @override
  String get signOut => 'Sign Out';
  @override
  String get subscribe => 'Subscribe';
  @override
  String get subscribed => 'Subscribed';
  @override
  String get share => 'Share';
  @override
  String get download => 'Download';
  @override
  String get updateAvailable => 'A new version of ${AppConfig.appName} is available!';
  @override
  String get updateNow => 'Update Now';
  @override
  String get noVideosFound => 'No videos found';
  @override
  String get retry => 'Retry';
}
