import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../auth/controller/auth_controller.dart';
import '../../voice/controller/wake_word.dart';
import '../controller/settings_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authControllerProvider.notifier).logout();
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Container(
        decoration: const BoxDecoration(gradient: Ds.pageGradient),
        child: ListView(
          padding: const EdgeInsets.all(Ds.s4),
          children: [
            _Section(
              title: 'Account',
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: Text(auth.email.isEmpty ? 'Signed in' : auth.email),
                  subtitle: auth.cmpAbbr.isEmpty ? null : Text('Company ${auth.cmpAbbr}'),
                ),
              ],
            ),
            const SizedBox(height: Ds.s4),
            _Section(
              title: 'Voice',
              footer: 'The language you speak in. Automatic follows the phone.',
              children: [
                RadioGroup<VoiceLang>(
                  groupValue: settings.voiceLang,
                  onChanged: (v) {
                    if (v != null) ctrl.setVoiceLang(v);
                  },
                  child: Column(
                    children: [
                      for (final v in VoiceLang.values)
                        RadioListTile<VoiceLang>(value: v, title: Text(v.label)),
                    ],
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: const Text('Keep listening after a reply'),
                  subtitle: const Text('Ask a follow-up without tapping'),
                  value: settings.followUp,
                  onChanged: ctrl.setFollowUp,
                ),
                SwitchListTile(
                  title: const Text('Interrupt by speaking'),
                  subtitle: const Text('Talk over a reply to stop it and ask something else'),
                  value: settings.bargeIn,
                  onChanged: ctrl.setBargeIn,
                ),
                SwitchListTile(
                  title: const Text('Phone voice for replies'),
                  subtitle: const Text('Free and offline. Off uses the DocSync server voice'),
                  value: settings.deviceVoice,
                  onChanged: ctrl.setDeviceVoice,
                ),
                SwitchListTile(
                  title: const Text('Understand speech on the phone'),
                  subtitle: const Text('Offline and private. Off uses the DocSync server, which is better with Hinglish'),
                  value: settings.deviceStt,
                  onChanged: ctrl.setDeviceStt,
                ),
              ],
            ),
            const SizedBox(height: Ds.s4),
            const _WakeSection(),
            const SizedBox(height: Ds.s6),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Ds.red,
                  side: BorderSide(color: Ds.red.withValues(alpha: 0.4)),
                ),
                onPressed: () => _confirmLogout(context, ref),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ),
            const SizedBox(height: Ds.s4),
            Center(child: Text('DocSync AI', style: theme.textTheme.bodySmall)),
          ],
        ),
      ),
    );
  }
}

class _WakeSection extends ConsumerWidget {
  const _WakeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final wake = ref.watch(wakeWordProvider);
    final status = switch (wake.status) {
      WakeWordStatus.off => 'Off',
      WakeWordStatus.paused => 'Listens while the Voice tab is open',
      WakeWordStatus.starting => 'Starting…',
      WakeWordStatus.listening => 'Listening for “${wake.phrase}”',
      WakeWordStatus.unavailable => 'Not available on this phone — tap the orb instead',
    };
    return _Section(
      title: 'Wake word',
      footer: 'Only while DocSync is open on the Voice tab. Detection runs on the phone; '
          'nothing is sent until you have said the phrase.',
      children: [
        SwitchListTile(
          title: Text('Say “${wake.phrase}” to start'),
          subtitle: Text(status),
          value: settings.wakeWord,
          onChanged: ctrl.setWakeWord,
        ),
        if (settings.wakeWord)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const Text('Sensitivity'),
                Expanded(
                  child: Slider(
                    value: settings.wakeSensitivity,
                    divisions: 10,
                    label: settings.wakeSensitivity < 0.35
                        ? 'Strict'
                        : settings.wakeSensitivity > 0.65
                            ? 'Eager'
                            : 'Balanced',
                    onChanged: ctrl.setWakeSensitivity,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.footer});
  final String title;
  final List<Widget> children;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: Ds.s2),
          child: Text(title.toUpperCase(),
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ),
        Container(
          decoration: Ds.card(radius: Ds.rChip + 2),
          clipBehavior: Clip.antiAlias,
          child: Material(type: MaterialType.transparency, child: Column(children: children)),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, Ds.s2, 4, 0),
            child: Text(footer!, style: theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}
