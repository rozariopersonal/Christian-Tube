export interface BookCatalogItem {
  id: string;
  title: string;
  author: string;
  subject?: string;
  categories?: string[];
  description?: string;
  coverFile?: string;
  totalPages?: number;
  lang?: string;
}

export interface BookTocChapter {
  chapterIndex: number;
  title: string;
  startPage?: number;
  endPage?: number;
}

export interface BookToc {
  id: string;
  title: string;
  author: string;
  subject?: string;
  chapters: BookTocChapter[];
}

export interface BookLine {
  line: number;
  page?: number;
  text: string;
  contentType?: string;
  isHeading?: boolean;
  headingLevel?: number;
}

export interface BookReadingProgress {
  bookId: string;
  title: string;
  author: string;
  coverFile?: string;
  chapterIndex: number;
  totalChapters: number;
  updatedAt: string;
}
