import { type Avatar, type CoverTone, isCoverTone, toneFor } from '@nussnuss/core';
import type { AvatarSetting } from '../db/schema.js';
import { sha256 } from './http.js';

/** How a person looks to friends. Unclaimed names get their initial on a tone picked from the name. */
export function avatarView(setting: AvatarSetting | null | undefined, name: string): Avatar {
  const tone: CoverTone = setting?.tone && isCoverTone(setting.tone) ? setting.tone : toneFor(name);
  if (setting?.kind === 'emoji') return { kind: 'emoji', value: setting.value, tone };
  if (setting?.kind === 'photo') return { kind: 'photo', url: `/avatars/${setting.id}`, tone };
  return { kind: 'initial', tone };
}

/** The signed-in person, as every endpoint that returns "me" shows them. */
export const meView = (u: { id: string; displayName: string; locale: string; payTo?: unknown; avatar?: AvatarSetting | null }) => ({
  id: u.id,
  name: u.displayName,
  locale: u.locale,
  payTo: u.payTo ?? [],
  avatar: avatarView(u.avatar, u.displayName),
});

/**
 * A stable id for a person across groups that never reveals their account id. Someone who joined is
 * known by their account; a name nobody has claimed is known by the name.
 */
export const userPersonKey = (userId: string) => `u${sha256(`person:${userId}`).slice(0, 20)}`;
export const namePersonKey = (nameKey: string) => `n${sha256(`name:${nameKey}`).slice(0, 20)}`;
