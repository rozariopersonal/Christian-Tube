export function computeSpreadMetrics(
  viewport: HTMLElement,
  gapPx: number,
): { totalPages: number; stepWidth: number } {
  const vw = viewport.clientWidth;
  if (vw <= 0) return { totalPages: 1, stepWidth: 0 };
  const stepWidth = vw + gapPx;
  const sw = viewport.scrollWidth;
  const totalPages = Math.max(1, Math.round((sw + gapPx) / stepWidth));
  return { totalPages, stepWidth };
}

export function scrollToSpreadPage(
  viewport: HTMLElement,
  pageOneBased: number,
  gapPx: number,
  smooth = false,
): void {
  const { totalPages, stepWidth } = computeSpreadMetrics(viewport, gapPx);
  const clamped = Math.min(totalPages, Math.max(1, pageOneBased));
  viewport.scrollTo({
    left: (clamped - 1) * stepWidth,
    top: 0,
    behavior: smooth ? 'smooth' : 'auto',
  });
}

export function scrollElementIntoSpread(
  viewport: HTMLElement,
  el: HTMLElement,
  gapPx: number,
  smooth = true,
): number {
  const { totalPages, stepWidth } = computeSpreadMetrics(viewport, gapPx);
  if (stepWidth <= 0) return 1;
  const vpRect = viewport.getBoundingClientRect();
  const elRect = el.getBoundingClientRect();
  const contentLeft = elRect.left - vpRect.left + viewport.scrollLeft;
  const page = Math.min(
    totalPages,
    Math.max(1, Math.floor(Math.max(0, contentLeft) / stepWidth) + 1),
  );
  scrollToSpreadPage(viewport, page, gapPx, smooth);
  return page;
}
