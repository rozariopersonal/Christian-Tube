/**
 * YouTube OAuth Refresh Token Generator for Christian-Tube
 * 
 * Usage:
 *   node scripts/get-youtube-token.js
 */

const http = require('http');
const https = require('https');
const url = require('url');
const querystring = require('querystring');
const fs = require('fs');
const path = require('path');
const { exec } = require('child_process');
const readline = require('readline');

const PORT = 8085;
const REDIRECT_URI = `http://localhost:${PORT}/oauth2callback`;
const SCOPES = [
  'https://www.googleapis.com/auth/youtube.upload',
  'https://www.googleapis.com/auth/youtube',
].join(' ');

function openBrowser(targetUrl) {
  const start =
    process.platform === 'darwin'
      ? 'open'
      : process.platform === 'win32'
      ? 'start ""'
      : 'xdg-open';
  exec(`${start} "${targetUrl}"`);
}

async function main() {
  console.log('\n======================================================');
  console.log('🎥 Christian-Tube YouTube OAuth Refresh Token Setup');
  console.log('======================================================\n');

  const backendEnvPath = path.resolve(__dirname, '../apps/backend/.env');
  let clientId = process.env.YOUTUBE_CLIENT_ID || '';
  let clientSecret = process.env.YOUTUBE_CLIENT_SECRET || '';

  if (fs.existsSync(backendEnvPath)) {
    const envContent = fs.readFileSync(backendEnvPath, 'utf8');
    const idMatch = envContent.match(/^YOUTUBE_CLIENT_ID=(.*)$/m);
    const secretMatch = envContent.match(/^YOUTUBE_CLIENT_SECRET=(.*)$/m);
    if (!clientId && idMatch && idMatch[1].trim()) clientId = idMatch[1].trim();
    if (!clientSecret && secretMatch && secretMatch[1].trim()) clientSecret = secretMatch[1].trim();
  }

  if (!clientId || !clientSecret) {
    console.error('Error: YOUTUBE_CLIENT_ID and YOUTUBE_CLIENT_SECRET must be set in apps/backend/.env or process.env');
    process.exit(1);
  }

  console.log(`Using Client ID: ${clientId}`);

  const authUrl = `https://accounts.google.com/o/oauth2/v2/auth?` + querystring.stringify({
    client_id: clientId,
    redirect_uri: REDIRECT_URI,
    response_type: 'code',
    scope: SCOPES,
    access_type: 'offline',
    prompt: 'consent',
  });

  console.log('\n------------------------------------------------------');
  console.log(`🌐 Local listener running at http://localhost:${PORT}/oauth2callback`);
  console.log('------------------------------------------------------\n');

  const server = http.createServer(async (req, res) => {
    try {
      const parsedUrl = url.parse(req.url, true);

      if (parsedUrl.pathname === '/oauth2callback') {
        const code = parsedUrl.query.code;
        const error = parsedUrl.query.error;

        if (error) {
          res.writeHead(400, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(`<h2>❌ Authorization failed: ${error}</h2><p>You can close this tab and check your terminal.</p>`);
          console.error(`\n❌ Authorization failed with error: ${error}`);
          server.close();
          process.exit(1);
          return;
        }

        if (code) {
          res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
          res.end(`
            <html>
              <body style="font-family: system-ui, -apple-system, sans-serif; text-align: center; padding: 40px; background: #0F172A; color: #F8FAFC;">
                <h1 style="color: #F59E0B;">✅ Authorization Successful!</h1>
                <p>Google OAuth code received. Permanent refresh token is being generated...</p>
                <p style="color: #94A3B8;">You can now close this tab and return to Christian-Tube.</p>
              </body>
            </html>
          `);

          console.log('\n✅ OAuth authorization code captured from Google callback!');
          console.log('🔄 Requesting permanent refresh token...');

          const postData = querystring.stringify({
            code,
            client_id: clientId,
            client_secret: clientSecret,
            redirect_uri: REDIRECT_URI,
            grant_type: 'authorization_code',
          });

          const tokenReq = https.request(
            'https://oauth2.googleapis.com/token',
            {
              method: 'POST',
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Content-Length': Buffer.byteLength(postData),
              },
            },
            (tokenRes) => {
              let rawData = '';
              tokenRes.on('data', (chunk) => (rawData += chunk));
              tokenRes.on('end', () => {
                try {
                  const tokenJson = JSON.parse(rawData);
                  if (tokenJson.error) {
                    console.error('\n❌ Token exchange error:', tokenJson.error_description || tokenJson.error);
                    server.close();
                    process.exit(1);
                    return;
                  }

                  const refreshToken = tokenJson.refresh_token;

                  if (!refreshToken) {
                    console.warn('\n⚠️ Warning: No refresh token returned. (Google only returns refresh_token on prompt=consent).');
                    if (tokenJson.access_token) {
                      console.log('Access token received successfully.');
                    }
                  } else {
                    console.log('\n======================================================');
                    console.log('🎉 SUCCESS! YouTube Refresh Token generated successfully:');
                    console.log('======================================================');
                    console.log(`\nYOUTUBE_REFRESH_TOKEN=${refreshToken}\n`);

                    updateEnvFile(backendEnvPath, {
                      YOUTUBE_CLIENT_ID: clientId,
                      YOUTUBE_CLIENT_SECRET: clientSecret,
                      YOUTUBE_REFRESH_TOKEN: refreshToken,
                    });
                  }

                  server.close();
                  process.exit(0);
                } catch (e) {
                  console.error('❌ Failed to parse token response:', e);
                  server.close();
                  process.exit(1);
                }
              });
            }
          );

          tokenReq.on('error', (e) => {
            console.error('❌ Token request network error:', e);
            server.close();
            process.exit(1);
          });

          tokenReq.write(postData);
          tokenReq.end();
        }
      }
    } catch (err) {
      console.error('Error handling request:', err);
    }
  });

  server.listen(PORT, () => {
    console.log(`🔗 Opening Google OAuth Consent URL in your browser...\n`);
    console.log(`If it does not open automatically, click or copy this URL:\n`);
    console.log(authUrl);
    console.log('\n------------------------------------------------------\n');
    openBrowser(authUrl);
  });
}

function updateEnvFile(envPath, updates) {
  let content = fs.existsSync(envPath) ? fs.readFileSync(envPath, 'utf8') : '';

  for (const [key, val] of Object.entries(updates)) {
    const regex = new RegExp(`^${key}=.*$`, 'm');
    if (regex.test(content)) {
      content = content.replace(regex, `${key}=${val}`);
    } else {
      content += (content.endsWith('\n') || content.length === 0 ? '' : '\n') + `${key}=${val}\n`;
    }
  }

  fs.writeFileSync(envPath, content, 'utf8');
  console.log(`📁 Automatically saved credentials to: ${envPath}`);
}

main().catch(console.error);
