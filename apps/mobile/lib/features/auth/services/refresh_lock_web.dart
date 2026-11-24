// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

typedef ExternalAuthEventCallback = void Function(String eventType);

Future<T> runWithCrossTabLock<T>(
  String lockName,
  Future<T> Function() action,
) async {
  try {
    final nav = globalContext.getProperty<JSObject?>('navigator'.toJS);
    final locks = nav?.getProperty<JSObject?>('locks'.toJS);
    if (locks != null && locks.hasProperty('request'.toJS).toDart) {
      late T result;
      final cb = (() {
        return () async {
          result = await action();
        }()
            .toJS;
      }).toJS;
      final promise = locks.callMethod<JSPromise<JSAny?>>(
        'request'.toJS,
        lockName.toJS,
        cb,
      );
      await promise.toDart;
      return result;
    }
  } catch (_) {
    // Fallback when Navigator.locks is unavailable
  }
  return action();
}

void broadcastAuthEvent(String eventType) {
  try {
    final channel = html.BroadcastChannel('auth');
    channel.postMessage(eventType);
    channel.close();
  } catch (_) {}
}

void Function() subscribeExternalAuthEvents(
  ExternalAuthEventCallback onEvent,
) {
  html.BroadcastChannel? channel;
  StreamSubscription<html.MessageEvent>? msgSub;
  StreamSubscription<html.StorageEvent>? storageSub;

  try {
    channel = html.BroadcastChannel('auth');
    msgSub = channel.onMessage.listen((event) {
      final data = event.data;
      if (data is String && data.isNotEmpty) {
        onEvent(data);
      }
    });
  } catch (_) {}

  storageSub = html.window.onStorage.listen((event) {
    final key = event.key;
    if (key == 'flutter.auth_access_token' ||
        key == 'flutter.auth_session_expired' ||
        key == 'flutter.current_user' ||
        key == null) {
      onEvent('storage_changed');
    }
  });

  return () {
    msgSub?.cancel();
    storageSub?.cancel();
    try {
      channel?.close();
    } catch (_) {}
  };
}
