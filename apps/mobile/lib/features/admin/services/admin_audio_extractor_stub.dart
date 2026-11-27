import '../models/audio_processor_models.dart';
import 'admin_audio_job_store.dart';
import 'admin_audio_processor_api.dart';

class AudioExtractionOutcome {
  final String status; // completed | short | skipped | failed
  final String? error;
  final bool isExtractorError;

  const AudioExtractionOutcome({
    required this.status,
    this.error,
    this.isExtractorError = false,
  });
}

Future<void> sweepOrphanedAudioTempFiles() async {}

Future<AudioExtractionOutcome> extractAndUploadVideo({
  required PendingAudioVideo video,
  required AdminAudioProcessorApi api,
  required AdminAudioJobStore jobStore,
}) async {
  return const AudioExtractionOutcome(
    status: 'skipped',
    error: 'Background YouTube audio extraction is only supported on Android.',
  );
}
