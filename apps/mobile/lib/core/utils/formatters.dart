import 'package:intl/intl.dart';
import 'package:timeago/timeago.dart' as timeago;

class Formatters {
  static String formatViews(int views) {
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M';
    } else if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)}K';
    }
    return views.toString();
  }

  static String formatSubscribers(dynamic count) {
    if (count == null) return '0';
    int val = 0;
    if (count is int) {
      val = count;
    } else {
      val = int.tryParse(count.toString()) ?? 0;
    }

    if (val >= 1000000) {
      return '${(val / 1000000).toStringAsFixed(1)}M';
    } else if (val >= 1000) {
      return '${(val / 1000).toStringAsFixed(1)}K';
    }
    return val.toString();
  }

  static String formatTimeAgo(DateTime dateTime) {
    return timeago.format(dateTime);
  }

  static String formatDate(DateTime dateTime) {
    return DateFormat.yMMMMd().format(dateTime);
  }

  static String formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '$minutes:${twoDigits(seconds)}';
  }
}
