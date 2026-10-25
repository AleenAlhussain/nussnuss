'use client';

/**
 * Two quiet sounds made on the fly with Web Audio (no files to download): a coin tap when something is
 * saved and a two-note chime when a group is settled. Off unless the person turns Sounds on.
 */
let ctx: AudioContext | null = null;

function audio(): AudioContext | null {
  try {
    ctx ??= new (window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext)();
    if (ctx.state === 'suspended') ctx.resume().catch(() => {});
    return ctx;
  } catch {
    return null;
  }
}

function tone(c: AudioContext, freq: number, start: number, length: number, gain: number, type: OscillatorType = 'sine') {
  const o = c.createOscillator();
  const g = c.createGain();
  o.type = type;
  o.frequency.setValueAtTime(freq, start);
  g.gain.setValueAtTime(0, start);
  g.gain.linearRampToValueAtTime(gain, start + 0.006);
  g.gain.exponentialRampToValueAtTime(0.0001, start + length);
  o.connect(g).connect(c.destination);
  o.start(start);
  o.stop(start + length + 0.02);
}

export type Sound = 'tap' | 'chime';

export function play(kind: Sound, enabled: boolean) {
  if (!enabled || typeof window === 'undefined') return;
  const c = audio();
  if (!c) return;
  const t = c.currentTime + 0.01;
  if (kind === 'tap') {
    // A small metallic tick: a bright partial over a soft body.
    tone(c, 2637, t, 0.09, 0.05, 'triangle');
    tone(c, 1319, t, 0.14, 0.04);
  } else {
    tone(c, 784, t, 0.5, 0.06);
    tone(c, 1175, t + 0.12, 0.7, 0.05);
  }
}
