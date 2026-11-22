import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../update_service.dart';

class UpdateDownloadState {
  const UpdateDownloadState({
    this.downloading = false,
    this.retrying = false,
    this.received = 0,
    this.total = 0,
    this.path,
    this.error,
  });
  final bool downloading, retrying;
  final int received, total;
  final String? path, error;
}

class UpdateDownloadController extends ChangeNotifier {
  UpdateDownloadState state = const UpdateDownloadState();
  CancelToken? _cancel;
  bool _disposed = false;

  void _set(UpdateDownloadState value) {
    if (_disposed) return;
    state = value;
    notifyListeners();
  }

  void start(String url, int size) {
    _cancel = CancelToken();
    _set(UpdateDownloadState(downloading: true, total: size));
    UpdateService.downloadAndInstallApkWithProgress(
      downloadUrl: url,
      cancelToken: _cancel,
      onRetryStateChange: (retrying) => _set(
        UpdateDownloadState(
          downloading: true,
          retrying: retrying,
          received: state.received,
          total: state.total,
        ),
      ),
      onProgress: (received, total) => _set(
        UpdateDownloadState(
          downloading: true,
          received: received,
          total: total > 0 ? total : size,
        ),
      ),
      onComplete: (path) => _set(UpdateDownloadState(path: path)),
      onError: (error) => _set(UpdateDownloadState(error: error)),
    );
  }

  void cancel() {
    _cancel?.cancel('Cancelled by user');
    _set(const UpdateDownloadState());
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel('Dialog disposed');
    super.dispose();
  }
}
