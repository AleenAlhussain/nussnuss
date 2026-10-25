'use client';

/**
 * Text whose digits roll like a counter when it changes (a balance, a total). Each digit keeps its real
 * glyph in place (transparent, so width, copy-paste and screen readers see the plain number) and a drum
 * of 0–9 drawn by CSS rolls over it. Reduce Motion makes the digits change in place.
 * Only the number runs are laid out left to right, so "45.00 د.إ" still reads naturally in Arabic.
 */
export function Rolling({ text, className, testId }: { text: string; className?: string; testId?: string }) {
  const parts = text.split(/(\d[\d.,]*)/);
  let run = 0;
  return (
    <span className={className} data-testid={testId}>
      {parts.map((p, i) => {
        if (!/^\d/.test(p)) return p ? <span key={`t${i}`}>{p}</span> : null;
        const chars = [...p];
        const r = run++;
        return (
          <span key={`n${r}`} dir="ltr" className="inline-flex whitespace-pre">
            {chars.map((c, j) => {
              // Keyed from the right, so the units stay on the same drum when the number grows a digit.
              const key = chars.length - j;
              return /\d/.test(c) ? (
                <span key={`d${key}`} className="drum-cell">
                  <span className="text-transparent">{c}</span>
                  <span aria-hidden className="drum" style={{ ['--d' as string]: Number(c) }} />
                </span>
              ) : (
                <span key={`c${key}`}>{c}</span>
              );
            })}
          </span>
        );
      })}
    </span>
  );
}
