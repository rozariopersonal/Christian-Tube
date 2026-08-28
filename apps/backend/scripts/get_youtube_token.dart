import 'dart:convert';
import 'dart:io';

final clientId = Platform.environment['YOUTUBE_CLIENT_ID'] ?? '269717576774-fqqvlkjea27smjf105mi94a8974ibpfh.apps.googleusercontent.com';
final clientSecret = Platform.environment['YOUTUBE_CLIENT_SECRET'] ?? '';
const redirectUri = 'http://localhost:8085/oauth2callback';
const port = 8085;

void main() async {
  final scopes = [
    'https://www.googleapis.com/auth/youtube.upload',
    'https://www.googleapis.com/auth/youtube',
    'https://www.googleapis.com/auth/youtube.readonly',
  ].join(' ');

  final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': scopes,
    'access_type': 'offline',
    'prompt': 'consent',
  });

  print('\n======================================================');
  print('🎬 YouTube Channel OAuth Token Generator');
  print('======================================================\n');
  print('1. Starting local listener on http://localhost:$port...');

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);

  print('2. Please open this URL in your browser to authorize your YouTube Channel:');
  print('\n👉 $authUrl\n');

  // Attempt to launch browser automatically on Windows
  if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', authUrl.toString()]);
  }

  await for (HttpRequest request in server) {
    final uri = request.uri;
    if (uri.path == '/oauth2callback') {
      final code = uri.queryParameters['code'];
      final error = uri.queryParameters['error'];

      if (error != null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.html
          ..write('<h1>❌ Authorization Error: $error</h1>');
        await request.response.close();
        await server.close();
        print('Authorization failed with error: $error');
        exit(1);
      }

      if (code != null) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('''
            <html>
              <body style="font-family: sans-serif; text-align: center; padding-top: 50px; background: #0F172A; color: white;">
                <h1 style="color: #10B981;">✅ Authorization Successful!</h1>
                <p>Your YouTube Refresh Token has been acquired and saved to Christian-Tube.</p>
                <p>You can close this tab now.</p>
              </body>
            </html>
          ''');
        await request.response.close();
        await server.close();

        print('3. Exchanging authorization code for permanent Refresh Token...');

        final client = HttpClient();
        final tokenReq = await client.postUrl(Uri.parse('https://oauth2.googleapis.com/token'));
        tokenReq.headers.contentType = ContentType.parse('application/x-www-form-urlencoded');

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

        tokenReq.write(bodyString);
        final tokenRes = await tokenReq.close();
        final resBody = await tokenRes.transform(utf8.decoder).join();
        final json = jsonDecode(resBody);

        final refreshToken = json['refresh_token'] as String?;
        final accessToken = json['access_token'] as String?;

        if (refreshToken != null && refreshToken.isNotEmpty) {
          print('\n======================================================');
          print('🎉 SUCCESS! Refresh Token Acquired:');
          print('======================================================');
          print(refreshToken);
          print('======================================================\n');

          // Automatically update apps/backend/.env
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
          print('⚠️ Warning: No refresh token returned. (Already authorized? Response: $json)');
        }
        exit(0);
      }
    }
  }
}
