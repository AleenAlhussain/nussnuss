import React, { useMemo, useState } from 'react';
import { Pressable, View } from 'react-native';
import { useStore, uid } from '../store';
import { useNav } from '../nav';
import { Button, Chip, Confirm, Field, Row, Screen, T, useUI, useToast } from '../ui';
import { CurrencyButton, CurrencyPicker } from '../components';
import { radius, space } from '../theme';
import type { Member } from '../types';

const EMOJIS = ['🏝️', '🏕️', '✈️', '🏠', '🍽️', '☕', '🎉', '⚽', '🚗', '🛒', '🎓', '💼'];

function guessCurrency(lang: string): string {
  try {
    const region = Intl.DateTimeFormat().resolvedOptions().locale.split('-')[1];
    const map: Record<string, string> = { AE: 'AED', SA: 'SAR', KW: 'KWD', QA: 'QAR', BH: 'BHD', OM: 'OMR', EG: 'EGP', JO: 'JOD', MA: 'MAD', GB: 'GBP', US: 'USD', IN: 'INR', TR: 'TRY' };
    if (region && map[region]) return map[region];
  } catch {}
  return lang === 'ar' ? 'AED' : 'USD';
}

export default function GroupEdit({ id }: { id?: string }) {
  const store = useStore();
  const nav = useNav();
  const toast = useToast();
  const { t, c, lang } = useUI();
  const existing = store.groups.find((g) => g.id === id);

  const [name, setName] = useState(existing?.name ?? '');
  const [emoji, setEmoji] = useState(existing?.emoji ?? EMOJIS[0]);
  const [cur, setCur] = useState(existing?.currency ?? guessCurrency(lang));
  const [members, setMembers] = useState<Member[]>(existing?.members ?? (store.settings.name ? [{ id: uid(), name: store.settings.name }] : []));
  const [newName, setNewName] = useState('');
  const [pick, setPick] = useState(false);
  const [confirmDel, setConfirmDel] = useState(false);
  const [errors, setErrors] = useState<{ name?: string; members?: string }>({});

  const used = useMemo(() => {
    const s = new Set<string>();
    existing?.expenses.forEach((e) => {
      s.add(e.paidBy);
      e.items.forEach((i) => i.value > 0 && s.add(i.memberId));
    });
    existing?.payments.forEach((p) => {
      s.add(p.from);
      s.add(p.to);
    });
    return s;
  }, [existing]);

  const addMember = () => {
    const n = newName.trim().slice(0, 40);
    if (!n) return;
    if (members.some((m) => m.name.trim().toLowerCase() === n.toLowerCase())) {
      setErrors((e) => ({ ...e, members: t('err_dupName') }));
      return;
    }
    setMembers((ms) => [...ms, { id: uid(), name: n }]);
    setNewName('');
    setErrors((e) => ({ ...e, members: undefined }));
  };

  const save = () => {
    const pending = newName.trim();
    const all = pending && !members.some((m) => m.name.toLowerCase() === pending.toLowerCase()) ? [...members, { id: uid(), name: pending.slice(0, 40) }] : members;
    const e: typeof errors = {};
    if (!name.trim()) e.name = t('err_groupName');
    if (all.length < 2) e.members = t('err_members');
    const names = all.map((m) => m.name.trim().toLowerCase());
    if (new Set(names).size !== names.length) e.members = t('err_dupName');
    setErrors(e);
    if (e.name || e.members) return;
    const data = { name: name.trim().slice(0, 60), emoji, currency: cur, members: all };
    if (existing) {
      store.updateGroup(existing.id, data);
      nav.back();
    } else {
      const gid = store.createGroup(data);
      nav.replace({ name: 'group', id: gid });
    }
  };

  return (
    <Screen
      testID="screen-group-edit"
      title={existing ? t('editGroup') : t('newGroup')}
      onBack={nav.back}
      footer={<Button label={t('save')} onPress={save} testID="save-group" icon="check" />}
    >
      <Field label={t('groupName')} placeholder={t('groupNamePh')} value={name} onChangeText={(v) => { setName(v); setErrors((e) => ({ ...e, name: undefined })); }} maxLength={60} error={errors.name} testID="group-name" autoFocus={!existing} />
      <View style={{ gap: space[2] }}>
        <Row wrap gap={space[2]}>
          {EMOJIS.map((e) => (
            <Pressable
              key={e}
              onPress={() => setEmoji(e)}
              accessibilityRole="button"
              accessibilityLabel={e}
              accessibilityState={{ selected: e === emoji }}
              style={{ width: 44, height: 44, borderRadius: radius.md, alignItems: 'center', justifyContent: 'center', backgroundColor: e === emoji ? c.accentSoft : c.surface, borderWidth: e === emoji ? 2 : 1, borderColor: e === emoji ? c.accent : c.border }}
            >
              <T v="title">{e}</T>
            </Pressable>
          ))}
        </Row>
      </View>
      <View style={{ gap: space[1] }}>
        <T v="label">{t('currency')}</T>
        <CurrencyButton code={cur} onPress={() => setPick(true)} testID="group-currency" />
      </View>
      <View style={{ gap: space[2] }}>
        <T v="label">{t('members')}</T>
        <Row wrap gap={space[2]}>
          {members.map((m) => (
            <Chip
              key={m.id}
              label={m.name}
              testID="member-chip"
              removeLabel={`${t('delete')} ${m.name}`}
              onRemove={used.has(m.id) ? undefined : () => setMembers((ms) => ms.filter((x) => x.id !== m.id))}
            />
          ))}
        </Row>
        <Row gap={space[2]} align="flex-start">
          <Field
            style={{ flex: 1 }}
            placeholder={t('memberPh')}
            value={newName}
            onChangeText={(v) => {
              setNewName(v);
              setErrors((e) => ({ ...e, members: undefined }));
            }}
            onSubmitEditing={addMember}
            blurOnSubmit={false}
            returnKeyType="done"
            maxLength={40}
            testID="member-name"
            accessibilityLabel={t('addMember')}
          />
          <Button label={t('addMember')} onPress={addMember} variant="secondary" icon="user-plus" full={false} testID="add-member" />
        </Row>
        {errors.members ? (
          <T v="small" color={c.danger}>
            {errors.members}
          </T>
        ) : null}
      </View>
      {existing ? <Button label={t('deleteGroup')} variant="danger" icon="trash-2" onPress={() => setConfirmDel(true)} testID="delete-group" /> : null}
      <CurrencyPicker visible={pick} onClose={() => setPick(false)} onPick={setCur} selected={cur} />
      <Confirm
        visible={confirmDel}
        message={t('deleteGroupQ')}
        confirmLabel={t('delete')}
        onCancel={() => setConfirmDel(false)}
        onConfirm={() => {
          setConfirmDel(false);
          if (existing) store.deleteGroup(existing.id);
          toast(t('delete') + ' ✓');
          nav.reset([{ name: 'home' }]);
        }}
      />
    </Screen>
  );
}
