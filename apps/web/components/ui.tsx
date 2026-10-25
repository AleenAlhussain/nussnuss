'use client';

import { motion } from 'motion/react';
import { forwardRef, useEffect, useId, useRef, type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactNode } from 'react';
import { haptic, shake, spring } from '@/lib/feel';

const cx = (...c: (string | false | null | undefined)[]) => c.filter(Boolean).join(' ');

type Variant = 'primary' | 'secondary' | 'plain' | 'danger';
export const Button = forwardRef<HTMLButtonElement, ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant; block?: boolean; icon?: ReactNode }>(
  function Button({ variant = 'primary', block, icon, className, children, onClick, ...rest }, ref) {
    const styles: Record<Variant, string> = {
      primary: 'bg-accent text-on-accent',
      secondary: 'bg-accent-soft text-on-accent-soft',
      plain: 'text-accent',
      danger: 'bg-danger-soft text-danger',
    };
    return (
      <button
        ref={ref}
        type="button"
        className={cx(
          'tap press focus-ring inline-flex items-center justify-center gap-2 rounded-full px-5 t-headline disabled:opacity-40',
          styles[variant],
          block && 'w-full',
          className,
        )}
        // No haptic on solid buttons: the light tap is for glass buttons (bar, tab, add), and the
        // action itself answers with success or error.
        onClick={onClick}
        {...rest}
      >
        {icon}
        {children}
      </button>
    );
  },
);

export function Field({
  label,
  hint,
  error,
  className,
  ...rest
}: InputHTMLAttributes<HTMLInputElement> & { label: string; hint?: string; error?: string | null }) {
  const id = useId();
  const input = useRef<HTMLInputElement>(null);
  // A new error shakes the field and gives the error haptic, so it is felt as well as seen.
  useEffect(() => {
    if (!error) return;
    shake(input.current);
    haptic('error');
  }, [error]);
  return (
    <div className={cx('flex flex-col gap-1.5', className)}>
      <label htmlFor={id} className="t-footnote font-medium text-text-2 ps-1">
        {label}
      </label>
      <input
        ref={input}
        id={id}
        aria-invalid={!!error}
        aria-describedby={error || hint ? `${id}-d` : undefined}
        className={cx(
          'focus-ring h-12 rounded-control bg-surface px-4 t-body text-text placeholder:text-text-3',
          error ? 'ring-2 ring-danger' : 'ring-1 ring-separator',
        )}
        {...rest}
      />
      {error || hint ? (
        <p id={`${id}-d`} className={cx('t-footnote ps-1', error ? 'text-danger' : 'text-text-2')}>
          {error ?? hint}
        </p>
      ) : null}
    </div>
  );
}

/** A checkmark that draws itself in 300 ms (done, paid). With Reduce Motion it is simply there. */
export function DrawCheck({ size = 18, className }: { size?: number; className?: string }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden className={className} data-testid="draw-check">
      <path d="M5 12.5l4.5 4.5L19 7.5" pathLength={24} fill="none" stroke="currentColor" strokeWidth={2.75} strokeLinecap="round" strokeLinejoin="round" className="draw-check" />
    </svg>
  );
}

/**
 * An error line under a form. Each new message (or a new `nonce`, for the same message again) shakes it
 * and gives the error haptic.
 */
export function ErrorText({ children, nonce, testId, className }: { children: ReactNode; nonce?: number; testId?: string; className?: string }) {
  const el = useRef<HTMLParagraphElement>(null);
  useEffect(() => {
    if (!children) return;
    shake(el.current);
    haptic('error');
  }, [children, nonce]);
  if (!children) return null;
  return (
    <p ref={el} className={cx('text-center t-footnote text-danger', className)} role="alert" data-testid={testId}>
      {children}
    </p>
  );
}

/** Content-layer segmented control (solid, never glass). The selected pill slides with a spring. */
export function Segmented<K extends string>({
  options,
  value,
  onChange,
  label,
  testId,
}: {
  options: { key: K; label: string }[];
  value: K;
  onChange: (k: K) => void;
  label: string;
  testId?: string;
}) {
  const group = useId();
  return (
    <div role="tablist" aria-label={label} className="flex rounded-control bg-surface-2 p-1" data-testid={testId}>
      {options.map((o) => {
        const on = o.key === value;
        return (
          <button
            key={o.key}
            role="tab"
            type="button"
            aria-selected={on}
            data-testid={testId ? `${testId}-${o.key}` : undefined}
            onClick={() => {
              if (!on) haptic('selection');
              onChange(o.key);
            }}
            className="focus-ring relative h-9 flex-1 rounded-[9px] t-subhead font-semibold"
          >
            {on && (
              <motion.span
                layoutId={`seg-${group}`}
                transition={spring}
                className="absolute inset-0 rounded-[9px] bg-surface shadow-[0_1px_3px_rgba(0,0,0,0.12)]"
              />
            )}
            <span className={cx('relative', on ? 'text-text' : 'text-text-2')}>{o.label}</span>
          </button>
        );
      })}
    </div>
  );
}

const TONES = ['#4F3BD6', '#B0265A', '#0B5FA5', '#9A5B00', '#0F7B4A', '#6B4E9E', '#B93A0E', '#2F6F73'];
export function Avatar({ name, index = 0, size = 36 }: { name: string; index?: number; size?: number }) {
  const initials = name.trim().split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase() || '?';
  return (
    <span
      aria-hidden
      className="inline-grid shrink-0 place-items-center rounded-full font-semibold text-white"
      style={{ width: size, height: size, fontSize: size * 0.38, background: TONES[index % TONES.length] }}
    >
      {initials}
    </span>
  );
}

export function Chip({ selected, onClick, children, testId }: { selected?: boolean; onClick?: () => void; children: ReactNode; testId?: string }) {
  return (
    <button
      type="button"
      aria-pressed={selected}
      data-testid={testId}
      onClick={() => {
        haptic('selection');
        onClick?.();
      }}
      className={cx(
        'focus-ring inline-flex h-11 items-center gap-2 rounded-full px-4 t-subhead font-medium transition-colors',
        selected ? 'bg-accent text-on-accent' : 'bg-surface text-text ring-1 ring-separator',
      )}
    >
      {children}
    </button>
  );
}

export function Empty({ icon, title, body, children }: { icon: ReactNode; title: string; body: string; children?: ReactNode }) {
  return (
    <div className="flex flex-col items-center gap-3 px-6 py-16 text-center">
      <div className="grid h-20 w-20 place-items-center rounded-full bg-accent-soft text-on-accent-soft">{icon}</div>
      <h2 className="t-title-3 text-text">{title}</h2>
      <p className="max-w-xs t-subhead text-text-2">{body}</p>
      {children ? <div className="mt-3 flex w-full max-w-xs flex-col gap-2">{children}</div> : null}
    </div>
  );
}

/** Grouped list section, like an inset table in iOS. Content layer: a solid surface, no glass. */
export function Section({ title, children, footer }: { title?: string; children: ReactNode; footer?: string }) {
  return (
    <section className="flex flex-col gap-2">
      {title ? <h2 className="t-subhead font-semibold text-text-2 ps-4">{title}</h2> : null}
      <div className="overflow-hidden rounded-card bg-surface">{children}</div>
      {footer ? <p className="t-footnote text-text-2 px-4">{footer}</p> : null}
    </section>
  );
}

export { cx };
