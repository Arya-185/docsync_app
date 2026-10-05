import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/tokens.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/view/chat_screen.dart';
import '../../chat/view/widgets/credits_pill.dart';
import '../../recent/view/recent_screen.dart';
import '../../search/view/search_screen.dart';
import '../../settings/view/settings_screen.dart';
import '../../voice/controller/voice_session.dart';
import '../../voice/controller/wake_word.dart';
import '../../voice/view/voice_screen.dart';

/// The signed-in app: a header (logo, DocSync wordmark, search, settings) over three tabs —
/// Voice · Chat · Recent — switched by a floating pill.
///
/// The tabs live in an [IndexedStack] so each keeps its state (a half-typed question, a
/// scroll position, a running turn) while another is on screen.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  void _go(int i) {
    if (i == _index) return;
    // Voice is for the Voice tab: leaving it releases the mic and stops any reply mid-sentence,
    // and the wake word only listens while it is on screen.
    if (_index == 0) ref.read(voiceSessionProvider.notifier).cancel();
    ref.read(voiceForegroundProvider.notifier).setTabVisible(i == 0);
    setState(() => _index = i);
  }

  void _openSearch() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Search documents')),
        body: const SearchScreen(),
      ),
    ));
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    // A dot on Recent when some conversation has an answer the user has not seen.
    final unseen = ref.watch(chatHistoryProvider
        .select((a) => a.value?.any((c) => c.unseen) ?? false));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: Ds.pageGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(onSearch: _openSearch, onSettings: _openSettings),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: [
                    VoiceScreen(onOpenChat: () => _go(1)),
                    const ChatScreen(),
                    RecentScreen(onOpened: () => _go(1)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _PillNav(
        index: _index,
        onTap: (i) {
          // Coming back to Recent should show what changed while you were away.
          if (i == 2 && _index != 2) ref.invalidate(chatHistoryProvider);
          _go(i);
        },
        recentDot: unseen,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSearch, required this.onSettings});
  final VoidCallback onSearch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Ds.s4, Ds.s2, Ds.s2, Ds.s2),
      child: Row(
        children: [
          Image.asset('assets/images/docsync_logo.png',
              height: 30, filterQuality: FilterQuality.medium),
          const SizedBox(width: 10),
          Text('DocSync',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Ds.brand,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  )),
          const Spacer(),
          const CreditsPill(), // AI credits this month; nothing for an uncapped member
          const SizedBox(width: 6),
          _RoundIcon(icon: Icons.search_rounded, tooltip: 'Search documents', onTap: onSearch),
          const SizedBox(width: 4),
          _RoundIcon(icon: Icons.settings_outlined, tooltip: 'Settings', onTap: onSettings),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Ds.inkSoft,
        shadowColor: const Color(0x140F172A),
        elevation: 2,
      ),
      icon: Icon(icon, size: 22),
    );
  }
}

class _PillNav extends StatelessWidget {
  const _PillNav({required this.index, required this.onTap, required this.recentDot});
  final int index;
  final void Function(int) onTap;
  final bool recentDot;

  static const _items = [
    (Icons.mic_none_rounded, Icons.mic_rounded, 'Voice'),
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chat'),
    (Icons.history_rounded, Icons.history_rounded, 'Recent'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(Ds.s6, 0, Ds.s6, Ds.s3),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(Ds.rPill + 4),
          boxShadow: Ds.pillShadow,
        ),
        child: Row(
          children: [
            for (var i = 0; i < _items.length; i++)
              Expanded(
                child: _PillItem(
                  icon: i == index ? _items[i].$2 : _items[i].$1,
                  label: _items[i].$3,
                  selected: i == index,
                  dot: i == 2 && recentDot,
                  onTap: () => onTap(i),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PillItem extends StatelessWidget {
  const _PillItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.dot,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Ds.blue : Ds.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(Ds.rPill),
        // The selected tint is the feedback; a grey press highlight on top reads as a second state.
        highlightColor: Colors.transparent,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Ds.tint : Colors.transparent,
            borderRadius: BorderRadius.circular(Ds.rPill),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Badge(
                isLabelVisible: dot,
                smallSize: 8,
                backgroundColor: Ds.blue,
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
