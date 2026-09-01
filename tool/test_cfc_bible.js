async function test() {
  try {
    const res = await fetch('https://www.cfcindia.com/bible', { signal: AbortSignal.timeout(10000) });
    const text = await res.text();

    const regex = /<a[^>]+href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;
    let m;
    const found = [];
    while ((m = regex.exec(text)) !== null) {
      const href = m[1];
      const linkText = m[2].replace(/<[^>]+>/g, '').trim();
      if (href.includes('through-the-bible/') || href.includes('/bible/')) {
        found.push({ linkText, href });
      }
    }
    console.log(`Total links found on /bible: ${found.length}`);
    for (const f of found) {
      console.log(`  - "${f.linkText}" -> ${f.href}`);
    }
  } catch (e) {
    console.error('Error:', e.message);
  }
}

test();
