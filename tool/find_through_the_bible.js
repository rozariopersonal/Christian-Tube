const fs = require('fs');

async function searchLinks() {
  const contentPath = 'C:/Users/Arul Rozario/.gemini/antigravity-ide/brain/7c68c2f5-2e54-424d-b350-6c3f08feead0/.system_generated/steps/79/content.md';
  const html = fs.readFileSync(contentPath, 'utf8');

  const links = [];
  const regex = /<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
  let m;
  while ((m = regex.exec(html)) !== null) {
    const url = m[1];
    const text = m[2].replace(/<[^>]+>/g, '').trim();
    if (url.includes('bible') || text.toLowerCase().includes('bible') || text.toLowerCase().includes('through')) {
      links.push({ text, url });
    }
  }
  console.log('Found', links.length, 'Bible-related links:');
  for (const l of links) {
    console.log(`- "${l.text}" -> ${l.url}`);
  }
}

searchLinks();
