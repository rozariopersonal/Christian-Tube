import 'dart:convert';
import 'dart:io';

const int port = 8080;
const String redirectUri = 'http://localhost:$port/oauth2callback';
final String clientId = Platform.environment['YOUTUBE_CLIENT_ID'] ?? '';
final String clientSecret = Platform.environment['YOUTUBE_CLIENT_SECRET'] ?? '';
const String scopes = 'https://www.googleapis.com/auth/youtube.upload https://www.googleapis.com/auth/youtube';

void main() async {
  print('\n======================================================');
  print('🎥 Christian-Tube YouTube OAuth Refresh Token Setup');
  print('======================================================\n');

  final authUri = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
    'client_id': clientId,
    'redirect_uri': redirectUri,
    'response_type': 'code',
    'scope': scopes,
    'access_type': 'offline',
    'prompt': 'consent',
  });

  print('🌐 Starting temporary local listener on $redirectUri...\n');

  HttpServer server;
  try {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  } catch (e) {
    print('❌ Could not bind to port $port: $e');
    print('\nTIP: Ensure port $port is not blocked and that "$redirectUri" is added to Authorized Redirect URIs in Google Cloud Console.\n');
    exit(1);
  }

  print('🔗 Opening Google Sign-in URL in your browser...\n');
  print('If it does not open automatically, click or copy this link:\n');
  print('$authUri\n');
  print('------------------------------------------------------\n');

  if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', '', authUri.toString()]);
  } else if (Platform.isMacOS) {
    Process.run('open', [authUri.toString()]);
  } else if (Platform.isLinux) {
    Process.run('xdg-open', [authUri.toString()]);
  }

  await for (final HttpRequest request in server) {
    if (request.uri.path == '/oauth2callback') {
      final code = request.uri.queryParameters['code'];
      final error = request.uri.queryParameters['error'];

      if (error != null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..headers.contentType = ContentType.html
          ..write('<h2>❌ Authorization failed: $error</h2><p>Check terminal.</p>');
        await request.response.close();
        print('\n❌ Authorization failed: $error');
        await server.close();
        exit(1);
      }

      if (code != null) {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('''
            <html>
              <body style="font-family: system-ui, sans-serif; text-align: center; padding: 40px; background: #0F172A; color: #F8FAFC;">
                <h1 style="color: #F59E0B;">✅ Authorization Successful!</h1>
                <p>Google OAuth code received. Generating permanent refresh token in terminal...</p>
                <p style="color: #94A3B8;">You can now close this tab.</p>
              </body>
            </html>
          ''');
        await request.response.close();

        print('✅ Authorization code received from Google!');
        print('🔄 Requesting permanent refresh token...');

        final client = HttpClient();
        final tokenRequest = await client.postUrl(Uri.parse('https://oauth2.googleapis.com/token'));
        tokenRequest.headers.contentType = ContentType.parse('application/x-www-form-urlencoded');

        final params = <String, String>{
          'code': code,
          'client_id': clientId,
          'client_secret': clientSecret,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        };
        final bodyStr = params.entries.map((e) => Uri.encodeQueryComponent(e.key) + '=' + Uri.encodeQueryComponent(e.value)).join('&');
        tokenRequest.write(bodyStr);

        final tokenResponse = await tokenRequest.close();
        final responseBody = await tokenResponse.transform(utf8.decoder).join();
        final json = jsonDecode(responseBody) as Map<String, dynamic>;

        if (json.containsKey('error')) {
          final errDesc = json['error_description'] ?? json['error'];
          print('\n❌ Error exchanging code: $errDesc');
          await server.close();
          exit(1);
        }

        final refreshToken = json['refresh_token'];
        if (refreshToken != null) {
          print('\n======================================================');
          print('🎉 SUCCESS! YouTube Refresh Token Generated:');
          print('======================================================\n');
          print('YOUTUBE_REFRESH_TOKEN=$refreshToken\n');

          _saveToEnv(refreshToken.toString());
        } else {
          print('\n⚠️ Warning: Google returned access_token but no refresh_token.');
          print('Response: $json');
        }

        await server.close();
        exit(0);
      }
    }
  }
}

void _saveToEnv(String refreshToken) {
  final envFile = File('apps/backend/.env');
  String content = envFile.existsSync() ? envFile.readAsStringSync() : '';

  final map = <String, String>{
    'YOUTUBE_CLIENT_ID': clientId,
    'YOUTUBE_CLIENT_SECRET': clientSecret,
    'YOUTUBE_REFRESH_TOKEN': refreshToken,
  };

  for (final entry in map.entries) {
    final regex = RegExp('^' + RegExp.escape(entry.key) + '=.*\$', multiLine: true);
    if (regex.hasMatch(content)) {
      content = content.replaceAll(regex, entry.key + '=' + entry.value);
    } else {
      if (content.isNotEmpty && !content.endsWith('\n')) content += '\n';
      content += entry.key + '=' + entry.value + '\n';
    }
  }

  envFile.writeAsStringSync(content);
  print('📁 Automatically saved credentials to: ' + envFile.path);
}
