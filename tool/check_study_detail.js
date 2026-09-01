async function checkStudy() {
  const url = 'https://www.cfcindia.com/through-the-bible/genesis-1';
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(10000) });
    const text = await res.text();
    console.log('Status:', res.status, 'Length:', text.length);

    // Extract title & text content
    const title = text.match(/<h1[^>]*>([\s\S]*?)<\/h1>/i)?.[1]?.replace(/<[^>]+>/g, '').trim();
    console.log('Title:', title);

    // Look for article body
    const paragraphs = [...text.matchAll(/<p(?:\s+[^>]*)?>([\s\S]*?)<\/p>/gi)]
      .map(m => m[1].replace(/<[^>]+>/g, '').trim())
      .filter(p => p.length > 50);

    console.log(`Found ${paragraphs.length} paragraphs in Genesis 1 study!`);
    console.log('Sample P1:', paragraphs[0]);
    console.log('Sample P2:', paragraphs[1]);
  } catch (e) {
    console.error(e.message);
  }
}

checkStudy();
