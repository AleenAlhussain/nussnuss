import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/services.dart';
import '../data/session.dart';
import '../design/glass.dart';
import '../design/page.dart';
import '../design/theme.dart';
import '../design/tokens.g.dart';
import '../design/widgets.dart';
import 'account_sheets.dart';
import 'group_sheets.dart' show webUrl;
import 'paywall.dart';
import 'summary_card.dart' show originOf;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onScrollDirection});
  final ValueChanged<bool>? onScrollDirection;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Security? _security;
  int _seen = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final rev = SessionScope.of(context).revision;
    if (rev != _seen) {
      _seen = rev;
      _loadSecurity();
    }
  }

  Future<void> _loadSecurity() async {
    try {
      final sec = await SessionScope.read(context).api.security();
      if (mounted) setState(() => _security = sec);
    } on ApiException {
      // Shown as unknown; the rows still work.
    }
  }

  void _snack(String text) => showToast(context, text);

  Future<void> _delete() async {
    final session = SessionScope.read(context);
    final s = session.s;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(s.deleteAccount),
        content: Text(s.deleteAccountBody),
        actions: [
          adaptiveAction(
            ctx,
            label: s.cancel,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          adaptiveAction(
            ctx,
            label: s.deleteAccountConfirm,
            destructive: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await session.deleteAccount();
    } on ApiException catch (e) {
      if (mounted) _snack(e.offline ? s.offline : e.message);
    }
  }

  Future<void> _export(BuildContext buttonContext) async {
    final session = SessionScope.read(context);
    final origin = originOf(buttonContext);
    try {
      final json = await session.api.exportMine();
      await session.device.share(
        files: [
          SharedFile(
            utf8.encode(json),
            name: 'nussnuss-my-data.json',
            mimeType: 'application/json',
          ),
        ],
        origin: origin,
      );
    } on ApiException catch (e) {
      if (mounted) _snack(e.offline ? session.s.offline : e.message);
    }
  }

  Future<void> _endSession(DeviceSession d) async {
    final session = SessionScope.read(context);
    try {
      await session.api.endSession(d.id);
      await _loadSecurity();
    } on ApiException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  Future<void> _removePayTo(int i) async {
    final session = SessionScope.read(context);
    final list = [...?session.me?.payTo]..removeAt(i);
    try {
      await session.setPayTo(list);
    } on ApiException catch (e) {
      if (mounted) _snack(e.offline ? session.s.offline : e.message);
    }
  }

  Future<void> _pickLook(String look) async {
    final session = SessionScope.read(context);
    if (!session.plan.ownsLook(look)) {
      final ok = await showPaywall(context, look: look);
      if (!ok) return;
    }
    await session.setLook(look);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    final s = session.s;
    final p = NNTheme.of(context).palette;
    final sec = _security;
    final plan = session.plan;
    final me = session.me;
    final day = MaterialLocalizations.of(context).formatMediumDate;
    return NNPage(
      key: const ValueKey('settings'),
      title: s.settings,
      onScrollDirection: widget.onScrollDirection,
      onRefresh: () async {
        await Future.wait([_loadSecurity(), session.refreshPlan()]);
      },
      slivers: [
        SliverList.list(
          children: [
            if ((me?.name ?? '').isNotEmpty)
              NNCard(
                child: Row(
                  children: [
                    Avatar(name: me!.name, size: 48),
                    const SizedBox(width: NNSpace.sm),
                    Expanded(
                      child: Text(
                        me.name,
                        style: NNType.title3.copyWith(color: p.text),
                      ),
                    ),
                  ],
                ),
              ),

            // Keeping the account.
            SectionLabel(s.account),
            NNCard(
              key: const ValueKey('account-status'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    sec?.safe == true
                        ? Icons.verified_user_rounded
                        : Icons.shield_outlined,
                    color: sec?.safe == true ? p.success : p.accent,
                  ),
                  const SizedBox(width: NNSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sec?.safe == true ? s.accountSafe : s.accountUnsafe,
                          style: NNType.headline.copyWith(color: p.text),
                        ),
                        if (sec?.safe != true)
                          Text(
                            s.accountUnsafeBody,
                            style: NNType.footnote.copyWith(color: p.text2),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: NNSpace.xs),
            _Rows(
              children: [
                _Row(
                  key: const ValueKey('recovery'),
                  icon: Icons.key_rounded,
                  title: sec?.recoveryCode == true
                      ? s.recoveryRemake
                      : s.recoveryMake,
                  subtitle: sec?.recoveryCreatedAt == null
                      ? null
                      : s.fill(s.recoveryMadeOn, {
                          'date': day(sec!.recoveryCreatedAt!),
                        }),
                  onTap: () async {
                    await showRecoveryCodeSheet(context);
                    await _loadSecurity();
                  },
                ),
                _Row(
                  key: const ValueKey('link-device'),
                  icon: Icons.devices_rounded,
                  title: s.linkDevice,
                  onTap: () => showLinkCodeSheet(context),
                ),
                for (final i in sec?.identities ?? const <Identity>[])
                  _Row(
                    icon: Icons.link_rounded,
                    title: s.fill(s.linkedWith, {
                      'provider': i.provider == 'apple' ? 'Apple' : 'Google',
                    }),
                    subtitle: i.email,
                  ),
              ],
            ),
            if ((sec?.sessions.length ?? 0) > 1) ...[
              SectionLabel(s.devices),
              _Rows(
                children: [
                  for (final d in sec!.sessions)
                    _Row(
                      icon: d.device == 'ios' || d.device == 'android'
                          ? Icons.smartphone_rounded
                          : Icons.computer_rounded,
                      title: d.current
                          ? s.thisDevice
                          : (d.device?.isNotEmpty == true
                                ? d.device!
                                : s.otherDevice),
                      subtitle: s.fill(s.lastSeen, {'date': day(d.lastSeenAt)}),
                      trailing: d.current
                          ? null
                          : TextButton(
                              onPressed: () => _endSession(d),
                              child: Text(
                                s.signOut,
                                style: TextStyle(color: p.danger),
                              ),
                            ),
                    ),
                ],
              ),
            ],

            // Plus.
            SectionLabel(s.yourPlan),
            _Rows(
              children: [
                _Row(
                  key: const ValueKey('plan'),
                  icon: Icons.workspace_premium_rounded,
                  title: plan.plus ? s.plus : s.planFree,
                  subtitle: plan.plus && plan.plusUntil != null
                      ? s.fill(s.plusOnUntil, {'date': day(plan.plusUntil!)})
                      : s.plusTagline,
                  trailing: Text(
                    s.seePlus,
                    style: NNType.subhead.copyWith(
                      color: p.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () => showPaywall(context),
                ),
              ],
            ),

            // How friends pay me.
            SectionLabel(s.payTo),
            _Rows(
              children: [
                for (var i = 0; i < (me?.payTo.length ?? 0); i++)
                  _Row(
                    key: ValueKey('pay-to-$i'),
                    icon: Icons.account_balance_wallet_outlined,
                    title: me!.payTo[i].label?.isNotEmpty == true
                        ? me.payTo[i].label!
                        : s.raw('pay_${me.payTo[i].kind}'),
                    subtitle: me.payTo[i].value,
                    trailing: IconButton(
                      tooltip: s.remove,
                      onPressed: () => _removePayTo(i),
                      icon: Icon(Icons.close_rounded, color: p.text2),
                    ),
                  ),
                if ((me?.payTo.length ?? 0) < 5)
                  _Row(
                    key: const ValueKey('add-pay-to'),
                    icon: Icons.add_rounded,
                    title: s.payAdd,
                    onTap: () => showAddPayToSheet(context),
                  ),
              ],
            ),
            _Hint(s.payToHint),

            SectionLabel(s.language),
            Segmented<String>(
              key: const ValueKey('settings-lang'),
              values: const ['en', 'ar'],
              selected: session.lang,
              label: (l) => l == 'ar' ? 'العربية' : 'English',
              onChanged: session.setLang,
            ),
            SectionLabel(s.theme),
            Segmented<ThemePref>(
              values: ThemePref.values,
              selected: session.theme,
              label: (t) => s.raw('theme_${t.name}'),
              onChanged: session.setTheme,
            ),
            SectionLabel(s.look),
            Wrap(
              spacing: NNSpace.xs,
              runSpacing: NNSpace.xs,
              children: [
                for (final l in looks)
                  NNChip(
                    key: ValueKey('look-$l'),
                    label: s.raw('look_$l'),
                    icon: plan.ownsLook(l)
                        ? Icons.palette_outlined
                        : Icons.lock_outline_rounded,
                    selected: session.activeLook == l,
                    onTap: () => _pickLook(l),
                  ),
              ],
            ),
            _Hint(s.lookHint),
            SectionLabel(s.glass),
            Segmented<GlassPref>(
              key: const ValueKey('settings-glass'),
              values: GlassPref.values,
              selected: session.glass,
              label: (g) => switch (g) {
                GlassPref.clear => s.glassAuto,
                GlassPref.tinted => s.glassTinted,
                GlassPref.solid => s.glassSolid,
              },
              onChanged: session.setGlass,
            ),
            _Hint(s.glassHint),
            SectionLabel(s.sounds),
            NNCard(
              padding: const EdgeInsets.symmetric(
                horizontal: NNSpace.md,
                vertical: NNSpace.xxs,
              ),
              child: MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.soundsHint,
                        style: NNType.subhead.copyWith(color: p.text),
                      ),
                    ),
                    Switch.adaptive(
                      key: const ValueKey('sounds'),
                      value: session.sounds,
                      activeTrackColor: p.accent,
                      onChanged: session.setSounds,
                    ),
                  ],
                ),
              ),
            ),

            SectionLabel(s.about),
            _Rows(
              children: [
                _Row(
                  key: const ValueKey('privacy'),
                  icon: Icons.privacy_tip_outlined,
                  title: s.privacy,
                  onTap: () => session.device.open(
                    Uri.parse('${webUrl()}/privacy?lang=${session.lang}'),
                  ),
                ),
                _Row(
                  key: const ValueKey('terms'),
                  icon: Icons.description_outlined,
                  title: s.terms,
                  onTap: () => session.device.open(
                    Uri.parse('${webUrl()}/terms?lang=${session.lang}'),
                  ),
                ),
                Builder(
                  builder: (ctx) => _Row(
                    key: const ValueKey('export-mine'),
                    icon: Icons.download_rounded,
                    title: s.exportData,
                    onTap: () => _export(ctx),
                  ),
                ),
              ],
            ),
            const SizedBox(height: NNSpace.xxl),
            NNButton(
              key: const ValueKey('delete-account'),
              label: s.deleteAccount,
              kind: ButtonKind.danger,
              icon: Icons.delete_outline_rounded,
              onTap: _delete,
            ),
            Padding(
              padding: const EdgeInsets.all(NNSpace.xs),
              child: Text(
                s.deleteAccountBody,
                style: NNType.footnote.copyWith(color: p.text2),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: NNSpace.xxs,
        top: NNSpace.xs,
      ),
      child: Text(text, style: NNType.footnote.copyWith(color: p.text2)),
    );
  }
}

/// Rows grouped in one card, with hairlines between them.
class _Rows extends StatelessWidget {
  const _Rows({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    return NNCard(
      padding: const EdgeInsets.symmetric(horizontal: NNSpace.md),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 0.5,
                indent: 36,
                color: p.separator,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = NNTheme.of(context).palette;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: NNSpace.xs),
        child: Row(
          children: [
            Icon(icon, size: 22, color: p.accent),
            const SizedBox(width: NNSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: NNType.body.copyWith(color: p.text)),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: NNType.footnote.copyWith(color: p.text2),
                    ),
                ],
              ),
            ),
            ?trailing,
            if (onTap != null && trailing == null)
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                color: p.text3,
              ),
          ],
        ),
      ),
    );
    if (onTap == null) return MergeSemantics(child: content);
    return Pressable(
      onTap: onTap,
      semanticLabel: subtitle == null ? title : '$title, $subtitle',
      excludeChildSemantics: trailing == null,
      scale: 0.99,
      child: content,
    );
  }
}

/// A dialog button that looks native on each platform.
Widget adaptiveAction(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
  bool destructive = false,
}) {
  final p = NNTheme.of(context).palette;
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDestructiveAction: destructive,
      child: Text(label),
    );
  }
  return TextButton(
    onPressed: onPressed,
    child: Text(
      label,
      style: TextStyle(
        color: destructive ? p.danger : p.accent,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
