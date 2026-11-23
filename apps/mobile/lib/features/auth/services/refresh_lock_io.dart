typedef ExternalAuthEventCallback = void Function(String eventType);

Future<T> runWithCrossTabLock<T>(
  String lockName,
  Future<T> Function() action,
) {
  return action();
}

void broadcastAuthEvent(String eventType) {}

void Function() subscribeExternalAuthEvents(
  ExternalAuthEventCallback onEvent,
) {
  return () {};
}
