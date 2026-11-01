// ZARR CHAT - kerangka utama dengan navigasi bawah.
import 'package:flutter/material.dart';

import 'calls.dart';
import 'chats_tab.dart';
import 'settings.dart';
import 'state.dart';
import 'status.dart';
import 'theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int tab = 0;
  final PageController _pc = PageController();
  bool _animating = false; // true saat pindah tab lewat tombol bawah: abaikan onPageChanged perantara
  // Tab dibuat sekali supaya posisi gulir dan pencarian tidak hilang saat berpindah.
  final List<Widget> pages = const [ChatsTab(), StatusTab(), CallsTab(), SettingsTab()];

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == tab && !_pc.hasClients) return;
    final changed = i != tab;
    setState(() => tab = i);
    if (changed && i == 1) app.pokeEvent('tab:status'); // buka tab Pembaruan: muat status terbaru
    if (!_pc.hasClients) return;
    _animating = true;
    _pc
        .animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic)
        .whenComplete(() => _animating = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final unread = app.totalUnread;
        return Scaffold(
          body: Column(children: [
            if (app.offlineBanner)
              Material(
                color: p.accent,
                child: SafeArea(
                  bottom: false,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: const Text('Menyambungkan ulang…',
                        textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            Expanded(
              // Geser kiri/kanan di layar untuk pindah tab (seperti WhatsApp).
              child: PageView(
                controller: _pc,
                onPageChanged: (i) {
                  if (_animating || i == tab) return;
                  setState(() => tab = i);
                  if (i == 1) app.pokeEvent('tab:status');
                },
                children: [for (final w in pages) _KeepAlive(child: w)],
              ),
            ),
          ]),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: p.line, width: 3))),
            child: NavigationBar(
              selectedIndex: tab,
              backgroundColor: p.surface,
              indicatorColor: p.yellow,
              onDestinationSelected: _select,
              destinations: [
                NavigationDestination(
                  icon: Badge(label: Text(unread > 99 ? '99+' : '$unread'), isLabelVisible: unread > 0, child: const Icon(Icons.chat_bubble_outline)),
                  selectedIcon: const Icon(Icons.chat_bubble, color: Color(0xFF111111)),
                  label: 'Chat',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.donut_large_outlined),
                  selectedIcon: Icon(Icons.donut_large, color: Color(0xFF111111)),
                  label: 'Pembaruan',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.call_outlined),
                  selectedIcon: Icon(Icons.call, color: Color(0xFF111111)),
                  label: 'Panggilan',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings, color: Color(0xFF111111)),
                  label: 'Pengaturan',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Menjaga tiap tab tetap hidup di dalam PageView supaya posisi gulir & pencarian tidak hilang.
class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
