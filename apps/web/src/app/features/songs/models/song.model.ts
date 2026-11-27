export interface Song {
  id: string;
  title: string;
  titleRoman?: string;
  author?: string;
  album?: string;
  collection?: string;
  language: string;
  category?: string;
  verses: string[];
  versesRoman: string[];
  audioUrl?: string;
}

export function songHasTransliteration(song: Song): boolean {
  return (
    Boolean(song.titleRoman?.trim()) ||
    song.versesRoman.some((v) => v.trim().length > 0)
  );
}
