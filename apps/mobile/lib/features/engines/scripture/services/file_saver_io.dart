import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> saveOrDownloadFile(Uint8List bytes, String fileName) async {
  final tempDir = await getTemporaryDirectory();
  final file = File('${tempDir.path}/$fileName');
  await file.writeAsBytes(bytes);
  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'image/png', name: fileName)],
    text: fileName,
  );
}
