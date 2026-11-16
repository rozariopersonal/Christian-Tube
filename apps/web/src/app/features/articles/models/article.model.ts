export interface ArticleIndexEntry {
  id: string;
  title: string;
  date: string;
  year?: number | null;
  bookNumber?: number | null;
  chapter?: number | null;
  startVerse?: number | null;
  endVerse?: number | null;
  lang: string;
}

export interface ArticleLine {
  line: number;
  text: string;
  isHeading?: boolean;
  headingLevel?: number;
}

export interface ArticleData {
  id: string;
  title: string;
  date: string;
  author: string;
  lines: ArticleLine[];
}
