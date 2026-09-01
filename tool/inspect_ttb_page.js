const fs = require('fs');

const html = fs.readFileSync('data/books_raw/sample_ttb_study.html', 'utf8');

// Find YouTube iframe or embed
const ytMatch = html.match(/(?:youtube\.com\/(?:watch\?v=|embed\/)|youtu\.be\/)([a-zA-Z0-9_-]{11})/);
console.log('YouTube video ID:', ytMatch ? ytMatch[1] : 'None');

// Find audio MP3
const audioMatch = html.match(/https?:\/\/[^"']+\.mp3/i);
console.log('Audio MP3 URL:', audioMatch ? audioMatch[0] : 'None');

// Find study title
const titleMatch = html.match(/<div class="row-fluid text-center video-title">\s*<h2>([\s\S]*?)<\/h2>/i) ||
                   html.match(/<h2>([\s\S]*?)<\/h2>/i);
console.log('Title:', titleMatch ? titleMatch[1].replace(/<[^>]+>/g, '').trim() : 'None');

// Find all text blocks in article or main container
const fields = [...html.matchAll(/<div class="field-item even"[^>]*>([\s\S]*?)<\/div>/gi)];
console.log(`Found ${fields.length} content fields:`);
for (let i = 0; i < fields.length; i++) {
  const clean = fields[i][1].replace(/<[^>]+>/g, '').trim();
  if (clean.length > 20) {
    console.log(`[Field ${i}]:`, clean.substring(0, 150) + '...');
  }
}
