import React, { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Animated,
  Modal,
  Platform,
  Pressable,
  ScrollView,
  StyleProp,
  StyleSheet,
  Text,
  TextInput,
  TextInputProps,
  TextStyle,
  useColorScheme,
  View,
  ViewStyle,
  KeyboardAvoidingView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import Feather from '@expo/vector-icons/Feather';
import { palette, Palette, radius, space, fontSize, layout } from './theme';
import { translate, TKey } from './i18n';
import type { Lang, ThemePref } from './types';

// ---------- context ----------

interface UI {
  c: Palette;
  lang: Lang;
  rtl: boolean;
  scheme: 'light' | 'dark';
  t: (k: TKey, p?: Record<string, string | number>) => string;
}

const UICtx = createContext<UI | null>(null);

export function UIProvider({ lang, theme, accent, children }: { lang: Lang; theme: ThemePref; accent: string; children: React.ReactNode }) {
  const sys = useColorScheme();
  const scheme: 'light' | 'dark' = theme === 'system' ? (sys === 'dark' ? 'dark' : 'light') : theme;
  const value = useMemo<UI>(
    () => ({
      c: palette(scheme, accent),
      lang,
      rtl: lang === 'ar',
      scheme,
      t: (k, p) => translate(lang, k, p),
    }),
    [scheme, accent, lang],
  );
  useEffect(() => {
    if (Platform.OS === 'web' && typeof document !== 'undefined') {
      document.documentElement.lang = lang;
      document.body.style.backgroundColor = value.c.bg;
    }
  }, [lang, value.c.bg]);
  return <UICtx.Provider value={value}>{children}</UICtx.Provider>;
}

export function useUI(): UI {
  const v = useContext(UICtx);
  if (!v) throw new Error('UIProvider missing');
  return v;
}

// ---------- text ----------

type Variant = 'display' | 'title' | 'h2' | 'body' | 'muted' | 'small' | 'label' | 'amount';

const variantStyle: Record<Variant, TextStyle> = {
  display: { fontSize: fontSize.xl, fontWeight: '700', lineHeight: 36 },
  title: { fontSize: fontSize.lg, fontWeight: '700', lineHeight: 26 },
  h2: { fontSize: fontSize.md, fontWeight: '600', lineHeight: 22 },
  body: { fontSize: fontSize.md, fontWeight: '400', lineHeight: 22 },
  muted: { fontSize: fontSize.sm, fontWeight: '400', lineHeight: 20 },
  small: { fontSize: fontSize.xs, fontWeight: '500', lineHeight: 16 },
  label: { fontSize: fontSize.sm, fontWeight: '600', lineHeight: 20 },
  amount: { fontSize: fontSize.md, fontWeight: '700', lineHeight: 22, fontVariant: ['tabular-nums'] },
};

export function T({
  v = 'body',
  color,
  center,
  style,
  children,
  lines,
  testID,
  role,
}: {
  v?: Variant;
  color?: string;
  center?: boolean;
  style?: StyleProp<TextStyle>;
  children: React.ReactNode;
  lines?: number;
  testID?: string;
  role?: 'header';
}) {
  const { c, rtl } = useUI();
  const col = color ?? (v === 'muted' || v === 'small' ? c.textMuted : c.text);
  return (
    <Text
      testID={testID}
      numberOfLines={lines}
      accessibilityRole={role}
      style={[
        variantStyle[v],
        { color: col, textAlign: center ? 'center' : rtl ? 'right' : 'left', writingDirection: rtl ? 'rtl' : 'ltr' },
        style,
      ]}
    >
      {children}
    </Text>
  );
}

// ---------- layout ----------

export function Row({
  children,
  gap = space[2],
  align = 'center',
  justify,
  style,
  wrap,
}: {
  children: React.ReactNode;
  gap?: number;
  align?: ViewStyle['alignItems'];
  justify?: ViewStyle['justifyContent'];
  style?: StyleProp<ViewStyle>;
  wrap?: boolean;
}) {
  const { rtl } = useUI();
  return (
    <View style={[{ flexDirection: rtl ? 'row-reverse' : 'row', alignItems: align, justifyContent: justify, gap, flexWrap: wrap ? 'wrap' : 'nowrap' }, style]}>
      {children}
    </View>
  );
}

const DIRECTIONAL = new Set(['chevron-right', 'chevron-left', 'arrow-right', 'arrow-left']);

export function Icon({ name, size = 20, color }: { name: React.ComponentProps<typeof Feather>['name']; size?: number; color?: string }) {
  const { c, rtl } = useUI();
  let n = name;
  if (rtl && DIRECTIONAL.has(name)) n = (name.includes('right') ? name.replace('right', 'left') : name.replace('left', 'right')) as typeof name;
  return <Feather name={n} size={size} color={color ?? c.text} />;
}

export function Screen({
  title,
  onBack,
  right,
  children,
  footer,
  scroll = true,
  testID,
}: {
  title?: string;
  onBack?: () => void;
  right?: React.ReactNode;
  children: React.ReactNode;
  footer?: React.ReactNode;
  scroll?: boolean;
  testID?: string;
}) {
  const { c, t } = useUI();
  const body = (
    <View style={styles.inner}>
      {children}
    </View>
  );
  return (
    <SafeAreaView style={{ flex: 1, backgroundColor: c.bg }} edges={['top', 'left', 'right']} testID={testID}>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        {(title !== undefined || onBack) && (
          <View style={[styles.header, { borderBottomColor: c.border, backgroundColor: c.bg }]}>
            <Row justify="space-between" style={styles.headerRow}>
              <Row gap={space[1]} style={{ flex: 1 }}>
                {onBack ? (
                  <Pressable
                    onPress={onBack}
                    accessibilityRole="button"
                    accessibilityLabel={t('back')}
                    hitSlop={10}
                    style={({ pressed }) => [styles.iconBtn, pressed && { backgroundColor: c.surface2 }]}
                  >
                    <Icon name="arrow-left" size={22} />
                  </Pressable>
                ) : null}
                {title ? (
                  <T v="title" lines={1} role="header" style={{ flex: 1 }}>
                    {title}
                  </T>
                ) : null}
              </Row>
              {right}
            </Row>
          </View>
        )}
        {scroll ? (
          <ScrollView style={{ flex: 1 }} contentContainerStyle={{ paddingBottom: space[9] * 2 }} keyboardShouldPersistTaps="handled">
            {body}
          </ScrollView>
        ) : (
          <View style={{ flex: 1 }}>{body}</View>
        )}
        {footer ? (
          <SafeAreaView edges={['bottom']} style={[styles.footer, { backgroundColor: c.bg, borderTopColor: c.border }]}>
            <View style={styles.footerInner}>{footer}</View>
          </SafeAreaView>
        ) : null}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

export function Card({ children, onPress, style, testID, label }: { children: React.ReactNode; onPress?: () => void; style?: StyleProp<ViewStyle>; testID?: string; label?: string }) {
  const { c } = useUI();
  const base = [styles.card, { backgroundColor: c.surface, borderColor: c.border }, style];
  if (!onPress) return <View style={base} testID={testID}>{children}</View>;
  return (
    <Pressable
      onPress={onPress}
      testID={testID}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={({ pressed }) => [base, pressed && { backgroundColor: c.surface2 }]}
    >
      {children}
    </Pressable>
  );
}

export function Divider() {
  const { c } = useUI();
  return <View style={{ height: StyleSheet.hairlineWidth, backgroundColor: c.border, marginVertical: space[1] }} />;
}

// ---------- controls ----------

type BtnVariant = 'primary' | 'secondary' | 'ghost' | 'danger';

export function Button({
  label,
  onPress,
  variant = 'primary',
  icon,
  disabled,
  loading,
  small,
  testID,
  full = true,
}: {
  label: string;
  onPress: () => void;
  variant?: BtnVariant;
  icon?: React.ComponentProps<typeof Feather>['name'];
  disabled?: boolean;
  loading?: boolean;
  small?: boolean;
  testID?: string;
  full?: boolean;
}) {
  const { c } = useUI();
  const bg = { primary: c.accent, secondary: c.accentSoft, ghost: 'transparent', danger: c.dangerSoft }[variant];
  const fg = { primary: c.onAccent, secondary: c.onAccentSoft, ghost: c.accent, danger: c.danger }[variant];
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled || loading}
      testID={testID}
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled: !!(disabled || loading), busy: !!loading }}
      style={({ pressed }) => [
        styles.btn,
        { backgroundColor: bg, minHeight: small ? 36 : 48, paddingHorizontal: small ? space[3] : space[5], alignSelf: full ? 'stretch' : 'flex-start' },
        variant === 'ghost' && { paddingHorizontal: space[2] },
        (disabled || loading) && { opacity: 0.5 },
        pressed && { opacity: 0.85, transform: [{ scale: 0.99 }] },
      ]}
    >
      <Row gap={space[2]} justify="center">
        {loading ? <ActivityIndicator color={fg} /> : icon ? <Icon name={icon} size={small ? 16 : 18} color={fg} /> : null}
        <Text style={{ color: fg, fontSize: small ? fontSize.sm : fontSize.md, fontWeight: '600' }}>{label}</Text>
      </Row>
    </Pressable>
  );
}

export function IconButton({ name, onPress, label, testID, color }: { name: React.ComponentProps<typeof Feather>['name']; onPress: () => void; label: string; testID?: string; color?: string }) {
  const { c } = useUI();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityLabel={label}
      testID={testID}
      hitSlop={8}
      style={({ pressed }) => [styles.iconBtn, pressed && { backgroundColor: c.surface2 }]}
    >
      <Icon name={name} size={22} color={color} />
    </Pressable>
  );
}

export function Field({
  label,
  hint,
  error,
  style,
  inputStyle,
  big,
  ...rest
}: TextInputProps & { label?: string; hint?: string; error?: string | null; big?: boolean; inputStyle?: StyleProp<TextStyle> }) {
  const { c, rtl } = useUI();
  const [focus, setFocus] = useState(false);
  return (
    <View style={[{ gap: space[1] }, style as StyleProp<ViewStyle>]}>
      {label ? <T v="label">{label}</T> : null}
      <TextInput
        placeholderTextColor={c.textMuted}
        accessibilityLabel={label ?? rest.placeholder}
        {...rest}
        onFocus={(e) => {
          setFocus(true);
          rest.onFocus?.(e);
        }}
        onBlur={(e) => {
          setFocus(false);
          rest.onBlur?.(e);
        }}
        style={[
          styles.input,
          {
            color: c.text,
            backgroundColor: c.surface,
            borderColor: error ? c.danger : focus ? c.focus : c.borderInput,
            borderWidth: focus || error ? 2 : 1,
            textAlign: rtl ? 'right' : 'left',
            writingDirection: rtl ? 'rtl' : 'ltr',
            fontSize: big ? fontSize.xl : fontSize.md,
            fontWeight: big ? '700' : '400',
            minHeight: big ? 64 : 48,
          },
          Platform.OS === 'web' ? ({ outlineStyle: 'none' } as unknown as TextStyle) : null,
          inputStyle,
        ]}
      />
      {error ? (
        <T v="small" color={c.danger}>
          {error}
        </T>
      ) : hint ? (
        <T v="small">{hint}</T>
      ) : null}
    </View>
  );
}

export function Chip({
  label,
  selected,
  onPress,
  onRemove,
  testID,
  removeLabel,
}: {
  label: string;
  selected?: boolean;
  onPress?: () => void;
  onRemove?: () => void;
  testID?: string;
  removeLabel?: string;
}) {
  const { c } = useUI();
  return (
    <Pressable
      onPress={onPress}
      disabled={!onPress}
      testID={testID}
      accessibilityRole={onPress ? 'button' : 'text'}
      accessibilityState={{ selected: !!selected }}
      accessibilityLabel={label}
      style={({ pressed }) => [
        styles.chip,
        { backgroundColor: selected ? c.accent : c.surface, borderColor: selected ? c.accent : c.border },
        pressed && { opacity: 0.8 },
      ]}
    >
      <Row gap={space[1]}>
        <Text style={{ color: selected ? c.onAccent : c.text, fontSize: fontSize.sm, fontWeight: '600' }}>{label}</Text>
        {onRemove ? (
          <Pressable onPress={onRemove} hitSlop={8} accessibilityRole="button" accessibilityLabel={removeLabel ?? label}>
            <Icon name="x" size={14} color={selected ? c.onAccent : c.textMuted} />
          </Pressable>
        ) : null}
      </Row>
    </Pressable>
  );
}

export function Segmented<K extends string>({ options, value, onChange, testID }: { options: { key: K; label: string }[]; value: K; onChange: (k: K) => void; testID?: string }) {
  const { c, rtl } = useUI();
  return (
    <View accessibilityRole="tablist" style={[styles.seg, { backgroundColor: c.surface2, flexDirection: rtl ? 'row-reverse' : 'row', gap: space[1] }]}>
      {options.map((o) => {
        const on = o.key === value;
        return (
          <Pressable
            key={o.key}
            onPress={() => onChange(o.key)}
            testID={testID ? `${testID}-${o.key}` : undefined}
            accessibilityRole="tab"
            accessibilityState={{ selected: on }}
            accessibilityLabel={o.label}
            style={[styles.segItem, on && { backgroundColor: c.surface, ...shadow }]}
          >
            <Text style={{ color: on ? c.text : c.textMuted, fontWeight: on ? '700' : '500', fontSize: fontSize.sm }} numberOfLines={1}>
              {o.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const AVATAR_TONES = ['#4F3BD6', '#B0265A', '#0B5FA5', '#9A5B00', '#0F7B4A', '#6B4E9E', '#B93A0E', '#2F6F73'];

export function Avatar({ name, index = 0, size = 36 }: { name: string; index?: number; size?: number }) {
  const initials = name.trim().split(/\s+/).map((p) => p[0]).slice(0, 2).join('').toUpperCase() || '?';
  return (
    <View
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
      style={{ width: size, height: size, borderRadius: size / 2, backgroundColor: AVATAR_TONES[index % AVATAR_TONES.length], alignItems: 'center', justifyContent: 'center' }}
    >
      <Text style={{ color: '#FFFFFF', fontWeight: '700', fontSize: size * 0.4 }}>{initials}</Text>
    </View>
  );
}

export function Empty({ icon, title, body, children }: { icon: React.ComponentProps<typeof Feather>['name']; title: string; body: string; children?: React.ReactNode }) {
  const { c } = useUI();
  return (
    <View style={{ alignItems: 'center', paddingVertical: space[8], paddingHorizontal: space[4], gap: space[3] }}>
      <View style={{ width: 72, height: 72, borderRadius: 36, backgroundColor: c.accentSoft, alignItems: 'center', justifyContent: 'center' }}>
        <Icon name={icon} size={32} color={c.onAccentSoft} />
      </View>
      <T v="title" center>
        {title}
      </T>
      <T v="muted" center style={{ maxWidth: 320 }}>
        {body}
      </T>
      {children ? <View style={{ alignSelf: 'stretch', gap: space[2], marginTop: space[2] }}>{children}</View> : null}
    </View>
  );
}

export function PlusBadge() {
  const { c, t } = useUI();
  return (
    <View style={{ backgroundColor: c.highlight, borderRadius: radius.pill, paddingHorizontal: space[2], paddingVertical: 2 }}>
      <Text style={{ color: c.onHighlight, fontSize: 11, fontWeight: '800', letterSpacing: 0.5 }}>{t('plusBadge')}</Text>
    </View>
  );
}

// ---------- sheet (modal) ----------

export function Sheet({ visible, onClose, title, children, testID }: { visible: boolean; onClose: () => void; title?: string; children: React.ReactNode; testID?: string }) {
  const { c, t } = useUI();
  return (
    <Modal visible={visible} transparent animationType="fade" onRequestClose={onClose}>
      <Pressable style={styles.backdrop} onPress={onClose} accessibilityLabel={t('cancel')} accessibilityRole="button" />
      <View style={styles.sheetWrap} pointerEvents="box-none">
        <View style={[styles.sheet, { backgroundColor: c.surface, borderColor: c.border }]} testID={testID} accessibilityViewIsModal>
          {title ? (
            <Row justify="space-between" style={{ marginBottom: space[3] }}>
              <T v="title" style={{ flex: 1 }}>
                {title}
              </T>
              <IconButton name="x" onPress={onClose} label={t('cancel')} />
            </Row>
          ) : null}
          <ScrollView style={{ maxHeight: 520 }} keyboardShouldPersistTaps="handled">
            {children}
          </ScrollView>
        </View>
      </View>
    </Modal>
  );
}

export function Confirm({
  visible,
  message,
  confirmLabel,
  onConfirm,
  onCancel,
}: {
  visible: boolean;
  message: string;
  confirmLabel: string;
  onConfirm: () => void;
  onCancel: () => void;
}) {
  const { t } = useUI();
  return (
    <Sheet visible={visible} onClose={onCancel} testID="confirm">
      <T v="h2" style={{ marginBottom: space[4] }}>
        {message}
      </T>
      <View style={{ gap: space[2] }}>
        <Button label={confirmLabel} variant="danger" onPress={onConfirm} testID="confirm-yes" />
        <Button label={t('cancel')} variant="ghost" onPress={onCancel} />
      </View>
    </Sheet>
  );
}

// ---------- toast ----------

interface ToastMsg {
  id: number;
  text: string;
  action?: { label: string; onPress: () => void };
}
const ToastCtx = createContext<(text: string, action?: ToastMsg['action']) => void>(() => {});
export const useToast = () => useContext(ToastCtx);

export function ToastProvider({ children }: { children: React.ReactNode }) {
  const [msg, setMsg] = useState<ToastMsg | null>(null);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const show = useCallback((text: string, action?: ToastMsg['action']) => {
    if (timer.current) clearTimeout(timer.current);
    setMsg({ id: Date.now(), text, action });
    timer.current = setTimeout(() => setMsg(null), action ? 5000 : 2500);
  }, []);
  return (
    <ToastCtx.Provider value={show}>
      {children}
      {msg ? <ToastView key={msg.id} msg={msg} onDone={() => setMsg(null)} /> : null}
    </ToastCtx.Provider>
  );
}

function ToastView({ msg, onDone }: { msg: ToastMsg; onDone: () => void }) {
  const { c } = useUI();
  const a = useRef(new Animated.Value(0)).current;
  useEffect(() => {
    Animated.timing(a, { toValue: 1, duration: 180, useNativeDriver: Platform.OS !== 'web' }).start();
  }, [a]);
  return (
    <SafeAreaView edges={['bottom']} style={styles.toastWrap} pointerEvents="box-none">
      <Animated.View
        accessibilityLiveRegion="polite"
        accessibilityRole="alert"
        testID="toast"
        style={[styles.toast, { backgroundColor: c.text, opacity: a, transform: [{ translateY: a.interpolate({ inputRange: [0, 1], outputRange: [12, 0] }) }] }]}
      >
        <Row justify="space-between" gap={space[3]}>
          <Text style={{ color: c.bg, fontSize: fontSize.sm, fontWeight: '600', flexShrink: 1 }}>{msg.text}</Text>
          {msg.action ? (
            <Pressable
              onPress={() => {
                msg.action!.onPress();
                onDone();
              }}
              accessibilityRole="button"
              hitSlop={8}
            >
              <Text style={{ color: c.highlight, fontWeight: '800', fontSize: fontSize.sm }}>{msg.action.label}</Text>
            </Pressable>
          ) : null}
        </Row>
      </Animated.View>
    </SafeAreaView>
  );
}

// ---------- styles ----------

const shadow: ViewStyle = Platform.select({
  web: { boxShadow: '0 1px 3px rgba(27,23,48,0.12)' } as ViewStyle,
  default: { shadowColor: '#1B1730', shadowOpacity: 0.08, shadowRadius: 4, shadowOffset: { width: 0, height: 1 }, elevation: 1 },
})!;

const styles = StyleSheet.create({
  inner: { width: '100%', maxWidth: layout.maxWidth, alignSelf: 'center', paddingHorizontal: space[4], paddingTop: space[4], gap: space[4] },
  header: { borderBottomWidth: StyleSheet.hairlineWidth },
  headerRow: { width: '100%', maxWidth: layout.maxWidth, alignSelf: 'center', minHeight: layout.header, paddingHorizontal: space[2] },
  footer: { borderTopWidth: StyleSheet.hairlineWidth },
  footerInner: { width: '100%', maxWidth: layout.maxWidth, alignSelf: 'center', padding: space[3], gap: space[2] },
  iconBtn: { width: layout.tap, height: layout.tap, borderRadius: layout.tap / 2, alignItems: 'center', justifyContent: 'center' },
  card: { borderRadius: radius.lg, borderWidth: StyleSheet.hairlineWidth, padding: space[4], gap: space[2] },
  btn: { borderRadius: radius.md, alignItems: 'center', justifyContent: 'center' },
  input: { borderRadius: radius.md, paddingHorizontal: space[3], paddingVertical: space[2] },
  chip: { borderRadius: radius.pill, borderWidth: 1, paddingHorizontal: space[3], minHeight: 36, justifyContent: 'center' },
  seg: { borderRadius: radius.md, padding: 4 },
  segItem: { flex: 1, minHeight: 36, borderRadius: radius.sm, alignItems: 'center', justifyContent: 'center', paddingHorizontal: space[2] },
  backdrop: { position: 'absolute', top: 0, left: 0, right: 0, bottom: 0, backgroundColor: 'rgba(15,13,26,0.5)' },
  sheetWrap: { flex: 1, justifyContent: 'center', padding: space[4] },
  sheet: { width: '100%', maxWidth: 480, alignSelf: 'center', borderRadius: radius.lg, borderWidth: StyleSheet.hairlineWidth, padding: space[4] },
  toastWrap: { position: 'absolute', left: 0, right: 0, bottom: 0, alignItems: 'center', padding: space[4] },
  toast: { maxWidth: 520, width: '100%', borderRadius: radius.md, paddingHorizontal: space[4], paddingVertical: space[3] },
});
