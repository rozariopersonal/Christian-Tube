import 'package:flutter/gestures.dart';

/// Gives the canvas a pinch before its child scrollables can win either drag.
/// A single pointer at fit stays available for scrolling, taps and selection.
class ReaderCanvasGestureRecognizer extends OneSequenceGestureRecognizer {
  ReaderCanvasGestureRecognizer()
      : super(allowedButtonsFilter: (buttons) => buttons == kPrimaryButton);

  late bool Function() canPan;
  late void Function(Offset from, Offset to, double scale) onTransform;

  final _contacts = <int, Offset>{};
  int? _trackpad;
  double _trackpadScale = 1;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _contacts[event.pointer] = event.localPosition;
    if (_contacts.length >= 2 || canPan()) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handleNonAllowedPointer(PointerDownEvent event) {}

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    if (_trackpad != null) return;
    startTrackingPointer(event.pointer, event.transform);
    _trackpad = event.pointer;
    _trackpadScale = 1;
    if (canPan()) resolvePointer(event.pointer, GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerPanZoomEndEvent) {
      resolvePointer(event.pointer, GestureDisposition.rejected);
      _forget(event.pointer);
    } else if (event is PointerMoveEvent) {
      _moveContact(event.pointer, event.localPosition);
    } else if (event is PointerPanZoomUpdateEvent &&
        event.pointer == _trackpad) {
      final factor = event.scale / _trackpadScale;
      _trackpadScale = event.scale;
      if (factor == 1 && !canPan()) return;
      resolvePointer(event.pointer, GestureDisposition.accepted);
      final focal = event.localPosition + event.localPan;
      onTransform(focal - event.localPanDelta, focal, factor);
    }
  }

  void _moveContact(int pointer, Offset position) {
    final previous = _contacts[pointer];
    if (previous == null) return;
    final pair = _contacts.keys.take(2).toList();
    _contacts[pointer] = position;
    if (pair.length == 1) {
      if (canPan()) onTransform(previous, position, 1);
      return;
    }
    if (!pair.contains(pointer)) return;

    final other = _contacts[pair.first == pointer ? pair.last : pair.first]!;
    final span = (previous - other).distance;
    if (span > 0) {
      onTransform(
        (previous + other) / 2,
        (position + other) / 2,
        (position - other).distance / span,
      );
    }
  }

  void _forget(int pointer) {
    _contacts.remove(pointer);
    if (_trackpad == pointer) _trackpad = null;
    stopTrackingPointer(pointer);
  }

  @override
  void rejectGesture(int pointer) => _forget(pointer);

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'reader canvas zoom';
}
