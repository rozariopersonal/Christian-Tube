// ChristianApp Open Graph (og:) resolver — served as a Vercel Edge Function.
//
// Shared links such as /watch/VIDEO_ID, /shorts..., /article/.., /books/..,
// /song/.., /audio/series/.. and /bible?... are routed here. The function:
//   1. Inspects the requested path.
//   2. Builds Open Graph / Twitter meta tags (thumbnail, title, description).
//   3. Injects them into the SPA's index.html head and returns it.
//
// Real browsers still get the full Flutter SPA (GoRouter resolves the path),
// while sharing platforms (WhatsApp, Telegram, iMessage, Facebook...) which
// fetch the raw HTML head see a correct thumbnail + title preview.
//
// JSDoc: Vercel Edge Runtime exposes the Web Request/Response APIs.

const APP_NAME = 'ChristianApp';
const WEB_ORIGIN = 'https://christianapp.vercel.app';

// Branded fallback card used for content without a dedicated thumbnail.
const BRAND_IMAGE = WEB_ORIGIN + '/icons/Icon-512.png';

function prop(name, content) {
  if (!content) return '';
  const esc = String(content)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
  return (
    `<meta property="og:${name}" content="${esc}" />` +
    `<meta property="twitter:${name}" content="${esc}" />`
  );
}

// Extract a YouTube video id from an app path like /watch/ABC123?start=30.
function videoIdFromPath(path) {
  const m = /\/watch\/([A-Za-z0-9_-]+)/.exec(path);
  return m ? m[1] : null;
}

// Extract a YouTube id from /shorts (query id/videoId).
function shortsId(path) {
  const q = path.indexOf('?');
  const qs = q >= 0 ? path.slice(q + 1) : '';
  const params = new URLSearchParams(qs);
  const v = params.get('id') || params.get('videoId');
  return v || null;
}

// Resolve a video's title/author/thumbnail via YouTube's public oEmbed.
async function ytOembed(id) {
  const url =
    'https://www.youtube.com/oembed?url=' +
    encodeURIComponent('https://www.youtube.com/watch?v=' + id) +
    '&format=json';
  try {
    const res = await fetch(url, { cf: { cacheTtl: 3600 } });
    if (!res.ok) return null;
    return await res.json();
  } catch (_) {
    return null;
  }
}

async function resolveMeta(path) {
  let kind = 'app';
  let title = APP_NAME;
  let description = 'Watch high-quality Christian videos, shorts, devotions and words.';
  let image = BRAND_IMAGE;

  const videoId = videoIdFromPath(path);
  const shortId = shortsId(path);
  const targetId = videoId || shortId;

  if (targetId) {
    kind = 'video';
    const meta = await ytOembed(targetId);
    if (meta && meta.title) {
      title = meta.title;
      if (meta.author_name) description = 'Watch on ' + APP_NAME + ' · ' + meta.author_name;
      image = meta.thumbnail_url || 'https://img.youtube.com/vi/' + targetId + '/hqdefault.jpg';
    } else {
      // Derive the standard YouTube thumbnail directly from the id.
      image = 'https://img.youtube.com/vi/' + targetId + '/hqdefault.jpg';
      if (!title || title === APP_NAME) title = APP_NAME + ' — Watch this video';
    }
  } else if (/^\/article\//.test(path)) {
    title = APP_NAME + ' — Article';
    description = 'Read an article on ' + APP_NAME + '.';
  } else if (/^\/books\//.test(path)) {
    title = APP_NAME + ' — Book';
    description = 'Read a book on ' + APP_NAME + '.';
  } else if (/^\/song\//.test(path)) {
    title = APP_NAME + ' — Song';
    description = 'Listen to a song on ' + APP_NAME + '.';
  } else if (/^\/audio\//.test(path)) {
    title = APP_NAME + ' — Audio Series';
    description = 'Listen to sermons on ' + APP_NAME + '.';
  } else if (/^\/bible/.test(path)) {
    title = APP_NAME + ' — Bible';
    description = 'Read the Bible on ' + APP_NAME + '.';
  }

  return { kind, title, description, image };
}

export default async function handler(request) {
  const url = new URL(request.url);

  // The original shared path was passed as ?u= by the vercel route.
  let path = url.searchParams.get('u') || url.pathname || '/';

  const meta = await resolveMeta(path);

  // Load the SPA shell so real browsers still boot the app.
  let html = '';
  try {
    const res = await fetch(WEB_ORIGIN + '/index.html');
    html = await res.text();
  } catch (_) {
    html =
      '<!DOCTYPE html><html><head><title>' +
      APP_NAME +
      '</title></head><body><script>location.href=' +
      JSON.stringify(path) +
      ';</script></body></html>';
  }

  const headEnd = html.indexOf('</head>');
  const ogBlock =
    `<meta property="og:type" content="website" />` +
    `<meta property="og:site_name" content="${APP_NAME}" />` +
    `<meta property="og:url" content="${WEB_ORIGIN}${path}" />` +
    prop('title', meta.title) +
    prop('description', meta.description) +
    prop('image', meta.image) +
    `<meta name="twitter:card" content="summary_large_image" />`;

  const finalHtml =
    headEnd >= 0
      ? html.slice(0, headEnd) + ogBlock + html.slice(headEnd)
      : html;

  return new Response(finalHtml, {
    status: 200,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'public, max-age=0, s-maxage=3600',
    },
  });
}
