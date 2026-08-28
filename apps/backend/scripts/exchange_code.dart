import 'dart:convert';
import 'dart:io';

final clientId = Platform.environment['YOUTUBE_CLIENT_ID'] ?? '269717576774-fqqvlkjea27smjf105mi94a8974ibpfh.apps.googleusercontent.com';
final clientSecret = Platform.environment['YOUTUBE_CLIENT_SECRET'] ?? '';
const redirectUri = 'http://localhost:8085/oauth2callback';

void main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run exchange_code.dart "<code>" or "<full redirect url>"');
    exit(1);
  }

  String rawInput = args.join(' ').trim();
  String code = rawInput;

  if (rawInput.contains('code=')) {
    final uri = Uri.tryParse(rawInput);
    if (uri != null && uri.queryParameters['code'] != null) {
      code = uri.queryParameters['code']!;
    } else {
      final match = RegExp(r'code=([^&]+)').firstMatch(rawInput);
      if (match != null) {
        code = Uri.decodeComponent(match.group(1)!);
      }
    }
  }

  print('Exchanging authorization code with Google OAuth...');

  final client = HttpClient();
  final req = await client.postUrl(Uri.parse('https://oauth2.googleapis.com/token'));
  req.headers.contentType = ContentType.parse('application/x-www-form-urlencoded');

  final body = {
    'client_id': clientId,
    'client_secret': clientSecret,
    'code': code,
    'grant_type': 'authorization_code',
    'redirect_uri': redirectUri,
  };

  final bodyString = body.entries
      .map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');

  req.write(bodyString);
  final res = await req.close();
  final resBody = await res.transform(utf8.decoder).join();
  final dynamic json = jsonDecode(resBody);

  final refreshToken = json['refresh_token'] as String?;
  final accessToken = json['access_token'] as String?;

  if (refreshToken != null && refreshToken.isNotEmpty) {
    print('\n======================================================');
    print('🎉 SUCCESS! Refresh Token Acquired:');
    print('======================================================');
    print(refreshToken);
    print('======================================================\n');

    final envFile = File('d:/Projects/Christian-Tube/apps/backend/.env');
    if (await envFile.exists()) {
      var content = await envFile.readAsString();
      if (content.contains('YOUTUBE_REFRESH_TOKEN=')) {
        content = content.replaceAll(
          RegExp(r'YOUTUBE_REFRESH_TOKEN=.*'),
          'YOUTUBE_REFRESH_TOKEN=$refreshToken',
        );
      } else {
        content += '\nYOUTUBE_REFRESH_TOKEN=$refreshToken\n';
      }
      await envFile.writeAsString(content);
      print('✅ Automatically saved to apps/backend/.env!');
    }
  } else {
    print('Response from Google: $json');
  }
}
