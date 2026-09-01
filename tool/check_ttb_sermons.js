async function checkSermons() {
  const url = 'https://www.cfcindia.com/sermons';
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
    const text = await res.text();
    console.log('Sermons page fetched:', text.length, 'bytes');

    // Look for Through the Bible series
    const matches = [...text.matchAll(/href=["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi)];
    const ttb = matches.filter(m => m[0].toLowerCase().includes('through'));
    for (const m of ttb) {
      console.log('Found:', m[2].replace(/<[^>]+>/g, '').trim(), '->', m[1]);
    }
  } catch (e) {
    console.error('Error fetching sermons:', e.message);
  }
}

checkSermons();
