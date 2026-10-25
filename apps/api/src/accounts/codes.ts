import { randomInt } from 'node:crypto';

/** Crockford base32: no I, L, O or U, so codes survive being read aloud or copied by hand. */
const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

export function randomCode(length: number): string {
  let s = '';
  for (let i = 0; i < length; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return s;
}

/** "K7QX2-9MFHT-3RVZB-8PWNA": 20 characters, about 100 bits. */
export const recoveryCode = () => randomCode(20).match(/.{5}/g)!.join('-');

/** "4F7K-9QX2": 8 characters, short-lived. */
export const linkCode = () => randomCode(8).match(/.{4}/g)!.join('-');

/** Case, spaces, dashes and look-alike letters do not matter when typing a code back. */
export const normalizeCode = (s: string) =>
  s
    .toUpperCase()
    .replace(/[\s-]/g, '')
    .replace(/O/g, '0')
    .replace(/[IL]/g, '1');
