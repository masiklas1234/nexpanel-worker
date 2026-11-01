// ZARR CHAT - Panel Admin di dalam aplikasi (tanpa browser).
// Semua hak akses tetap diputuskan server; layar ini hanya antarmuka ke /api/admin.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'util.dart';
import 'widgets.dart';

const Map<String, int> _rank = {'user': 0, 'admin': 1, 'superadmin': 2, 'developer': 3};
int _rk(dynamic role) => _rank[role?.toString()] ?? 0;

DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
String _when(dynamic v) => dateTimeText(_dt(v));
String _str(dynamic v) => v == null ? '' : v.toString();

// ------------------------------------------------------------------ dialog teks
class _TextDialog extends StatefulWidget {
  final String title;
  final String? hint;
  final String initial;
  final int maxLength;
  final int maxLines;
  final bool required;
  final String okLabel;
  const _TextDialog({
    required this.title,
    this.hint,
    this.initial = '',
    this.maxLength = 255,
    this.maxLines = 1,
    this.required = false,
    this.okLabel = 'Simpan',
  });
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = widget.required && c.text.trim().isEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: widget.maxLength,
        maxLines: widget.maxLines,
        onChanged: (_) => setState(() {}),
        decoration: neoDeco(context, hint: widget.hint),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        TextButton(onPressed: blocked ? null : () => Navigator.pop(context, c.text.trim()), child: Text(widget.okLabel)),
      ],
    );
  }
}

Future<String?> _askText(BuildContext context,
    {required String title, String? hint, String initial = '', int maxLength = 255, int maxLines = 1, bool required = false, String okLabel = 'Simpan'}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _TextDialog(title: title, hint: hint, initial: initial, maxLength: maxLength, maxLines: maxLines, required: required, okLabel: okLabel),
  );
}

// ------------------------------------------------------------------ pemuat data
class _Fetch extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(BuildContext context, Map<String, dynamic> data, Future<void> Function() reload) builder;
  const _Fetch({super.key, required this.load, required this.builder});
  @override
  State<_Fetch> createState() => _FetchState();
}

class _FetchState extends State<_Fetch> {
  Map<String, dynamic>? data;
  String? error;
  String? code;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      data = asMap(await widget.load());
      error = null;
      code = null;
    } catch (e) {
      final msg = errText(e);
      if (data != null) {
        app.toast(msg, error: true); // data lama tetap tampil
      } else {
        error = msg;
        code = e is ApiException ? e.code : null;
      }
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Spin();
    final d = data;
    if (d == null) {
      if (code == 'admin_relogin') {
        return EmptyState(
          icon: Icons.lock_clock,
          title: 'Sesi admin kedaluwarsa',
          text: error,
          action: NeoButton('Keluar lalu masuk lagi', icon: Icons.logout, onPressed: () => app.logout()),
        );
      }
      return EmptyState(icon: Icons.error_outline, title: 'Gagal memuat', text: error, action: NeoButton('Coba lagi', onPressed: () {
        setState(() => loading = true);
        reload();
      }));
    }
    return RefreshIndicator(onRefresh: reload, child: widget.builder(context, d, reload));
  }
}

const ScrollPhysics _always = AlwaysScrollableScrollPhysics();

Widget _emptyList(IconData icon, String title, String text) => ListView(
      physics: _always,
      children: [const SizedBox(height: 80), EmptyState(icon: icon, title: title, text: text)],
    );

class _Pill extends StatelessWidget {
  final String text;
  final Color? color;
  const _Pill(this.text, {this.color});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? p.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: p.line, width: 1.5),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Color(0xFF111111))),
    );
  }
}

// ------------------------------------------------------------------ halaman utama
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  static const List<String> _tabs = ['Dashboard', 'Pengguna', 'Grup', 'Saluran', 'Laporan', 'Pengumuman', 'Pengaturan', 'Audit log', 'Error sistem'];
  static const String _bcTab = 'Broadcast';

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    final me = app.me;
    if (me == null || !me.isAdmin) {
      return Scaffold(
        appBar: zAppBar(context, text: 'Panel Admin'),
        body: const EmptyState(icon: Icons.lock_outline, title: 'Akses admin', text: 'Akun Anda tidak memiliki izin admin.'),
      );
    }
    // Broadcast hanya untuk akun developer (server juga menolak akun lain).
    final dev = me.role == 'developer';
    final tabs = [..._tabs.sublist(0, 6), if (dev) _bcTab, ..._tabs.sublist(6)];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: zAppBar(context, text: 'Panel Admin (${me.role})'),
        body: Column(children: [
          Material(
            color: p.surface2,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: p.text,
              unselectedLabelColor: p.muted,
              indicatorColor: p.accent,
              labelStyle: const TextStyle(fontWeight: FontWeight.w800),
              tabs: [for (final t in tabs) Tab(text: t)],
            ),
          ),
          Expanded(
            child: TabBarView(children: [
              const _DashTab(),
              _UsersTab(me: me),
              const _VerifyTab(groups: true),
              const _VerifyTab(groups: false),
              const _ReportsTab(),
              const _AnnTab(),
              if (dev) const _BroadcastTab(),
              _SettingsTab(me: me),
              const _AuditTab(),
              const _ErrorsTab(),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------ dashboard
class _StatCard extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;
  const _StatCard({required this.width, required this.label, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: p.line, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: p.accent),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
        Text(label, style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

class _DashTab extends StatelessWidget {
  const _DashTab();
  @override
  Widget build(BuildContext context) {
    return _Fetch(
      load: () => app.api.get('/admin/stats'),
      builder: (context, d, reload) {
        final u = asMap(d['users']);
        final items = <List<dynamic>>[
          ['Akun terdaftar', u['total'], Icons.people_outline],
          ['Akun aktif', u['active'], Icons.check_circle_outline],
          ['Dinonaktifkan', u['suspended'], Icons.block],
          ['Terverifikasi', u['verified'], Icons.verified_outlined],
          ['Baru 7 hari', u['new7'], Icons.person_add_alt],
          ['Online sekarang', d['online'], Icons.circle_outlined],
          ['Pesan 24 jam', d['messages24h'], Icons.chat_bubble_outline],
          ['Laporan terbuka', d['openReports'], Icons.flag_outlined],
          ['Error 24 jam', d['errors24h'], Icons.bug_report_outlined],
        ];
        final w = (MediaQuery.of(context).size.width - 14 * 2 - 10) / 2;
        return ListView(physics: _always, padding: const EdgeInsets.all(14), children: [
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final it in items) _StatCard(width: w, label: it[0] as String, value: '${it[1] ?? 0}', icon: it[2] as IconData),
          ]),
          const SizedBox(height: 14),
          Text(
            'Administrator tidak dapat membaca isi chat atau rahasia autentikasi pengguna. Nomor telepon ditampilkan sebagian.',
            style: TextStyle(color: pal(context).muted, fontSize: 12.5),
          ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ pengguna
class _UsersTab extends StatefulWidget {
  final User me;
  const _UsersTab({required this.me});
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> {
  final TextEditingController search = TextEditingController();
  List<Map<String, dynamic>> users = [];
  String q = '';
  int page = 0;
  bool loading = true;
  bool more = false;
  bool loadingMore = false;
  String? error;
  String? code;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = true}) async {
    if (reset) page = 0;
    try {
      final r = asMap(await app.api.get('/admin/users?q=${Uri.encodeQueryComponent(q)}&page=$page'));
      final list = asList(r['users']).map((e) => asMap(e)).toList();
      users = reset ? list : [...users, ...list];
      more = list.length >= 25;
      error = null;
      code = null;
    } catch (e) {
      if (users.isEmpty || reset) {
        error = errText(e);
        code = e is ApiException ? e.code : null;
      } else {
        app.toast(errText(e), error: true);
      }
    }
    if (mounted) {
      setState(() {
        loading = false;
        loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore) return;
    setState(() => loadingMore = true);
    page++;
    await load(reset: false);
  }

  Future<void> _do(Future<dynamic> Function() run, String okMsg) async {
    try {
      await run();
      app.toast(okMsg);
      await load();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  void _pickRole(Map<String, dynamic> u, List<String> allowed) {
    final id = (u['id'] as num).toInt();
    showMenuSheet(
      context,
      [
        for (final r in allowed)
          MenuItem(Icons.badge_outlined, r, () {
            if (u['role'] == r) return;
            _do(() => app.api.post('/admin/users/$id/role', {'role': r}), 'Peran diubah menjadi $r.');
          }, checked: u['role'] == r),
      ],
      title: 'Ubah peran',
    );
  }

  void _open(Map<String, dynamic> u) {
    final me = widget.me;
    final p = pal(context);
    final id = (u['id'] as num).toInt();
    final name = _str(u['username']).isEmpty ? '(belum isi nama)' : _str(u['username']);
    final canTouch = me.id != id && _rk(me.role) > _rk(u['role']);
    final verified = u['isVerified'] == true;
    final suspended = u['status'] == 'suspended';
    final items = <MenuItem>[];
    if (canTouch) {
      items.add(MenuItem(
        verified ? Icons.cancel_outlined : Icons.verified_outlined,
        verified ? 'Cabut centang biru' : 'Beri centang biru',
        () => _do(() => app.api.post('/admin/users/$id/verify', {'verified': !verified}), verified ? 'Verifikasi dicabut.' : 'Centang biru diberikan.'),
      ));
      if (suspended) {
        items.add(MenuItem(Icons.lock_open, 'Pulihkan akun', () => _do(() => app.api.post('/admin/users/$id/suspend', {'suspended': false}), 'Akun dipulihkan.')));
      } else {
        items.add(MenuItem(Icons.block, 'Nonaktifkan akun', () async {
          final why = await _askText(context, title: 'Alasan penonaktifan', hint: 'Wajib diisi', required: true, okLabel: 'Nonaktifkan');
          if (why == null || why.isEmpty) return;
          await _do(() => app.api.post('/admin/users/$id/suspend', {'suspended': true, 'reason': why}), 'Akun dinonaktifkan.');
        }, danger: true));
      }
      final allowed = me.role == 'developer' ? <String>['user', 'admin', 'superadmin'] : (me.role == 'superadmin' ? <String>['user', 'admin'] : <String>[]);
      if (allowed.isNotEmpty && u['role'] != 'developer') {
        items.add(MenuItem(Icons.manage_accounts_outlined, 'Ubah peran…', () => _pickRole(u, allowed)));
      }
    }
    final reason = _str(u['suspendedReason']);
    showMenuSheet(
      context,
      items,
      title: name,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Nomor: ${_str(u['phone'])}'),
          Text('Peran: ${_str(u['role'])}  ·  Status: ${suspended ? 'dinonaktifkan' : 'aktif'}'),
          Text('Bergabung: ${_when(u['createdAt'])}'),
          if (u['lastSeenAt'] != null) Text('Terakhir dilihat: ${_when(u['lastSeenAt'])}'),
          if (suspended && reason.isNotEmpty) Text('Alasan: $reason', style: TextStyle(color: p.bad)),
          if (!canTouch)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Anda tidak dapat menindak akun ini.', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null && users.isEmpty) {
      body = code == 'admin_relogin'
          ? EmptyState(
              icon: Icons.lock_clock,
              title: 'Sesi admin kedaluwarsa',
              text: error,
              action: NeoButton('Keluar lalu masuk lagi', icon: Icons.logout, onPressed: () => app.logout()))
          : EmptyState(icon: Icons.error_outline, title: 'Gagal memuat', text: error, action: NeoButton('Coba lagi', onPressed: () {
              setState(() => loading = true);
              load();
            }));
    } else if (users.isEmpty) {
      body = _emptyList(Icons.person_search, 'Tidak ada pengguna', 'Coba kata kunci lain.');
    } else {
      body = ListView.builder(
        physics: _always,
        itemCount: users.length + (more ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == users.length) {
            return Padding(
              padding: const EdgeInsets.all(14),
              child: NeoButton('Muat lebih banyak', primary: false, busy: loadingMore, onPressed: _loadMore),
            );
          }
          final u = users[i];
          final nm = _str(u['username']).isEmpty ? '(belum isi nama)' : _str(u['username']);
          final suspended = u['status'] == 'suspended';
          return ListTile(
            leading: Avatar(name: nm, size: 44),
            title: Row(children: [
              Flexible(child: Text(nm, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (u['role'] == 'developer') ...[const SizedBox(width: 4), const VerifiedBadge(size: 15, rainbow: true)] else if (u['isVerified'] == true) ...[const SizedBox(width: 4), const VerifiedBadge(size: 15)],
            ]),
            subtitle: Row(children: [
              Flexible(child: Text(_str(u['phone']), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted))),
              const SizedBox(width: 8),
              _Pill(_str(u['role'])),
              if (suspended) ...[const SizedBox(width: 6), _Pill('nonaktif', color: p.bad.withAlpha(60))],
            ]),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _open(u),
          );
        },
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: neoDeco(
            context,
            hint: 'Cari nama atau nomor lengkap (+62…)',
            prefix: const Icon(Icons.search),
            suffix: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                search.clear();
                q = '';
                setState(() => loading = true);
                load();
              },
            ),
          ),
          onSubmitted: (v) {
            q = v.trim();
            setState(() => loading = true);
            load();
          },
        ),
      ),
      Expanded(child: RefreshIndicator(onRefresh: load, child: body)),
    ]);
  }
}

// ------------------------------------------------------------------ centang biru grup & saluran
/// Daftar semua grup / saluran. Centang biru hanya bisa diberikan atau dicabut dari sini (konfirmasi owner/admin).
class _VerifyTab extends StatefulWidget {
  final bool groups;
  const _VerifyTab({required this.groups});
  @override
  State<_VerifyTab> createState() => _VerifyTabState();
}

class _VerifyTabState extends State<_VerifyTab> {
  final TextEditingController search = TextEditingController();
  List<Map<String, dynamic>> items = [];
  String q = '';
  int page = 0;
  bool loading = true;
  bool more = false;
  bool loadingMore = false;
  String? error;
  String? code;

  String get kind => widget.groups ? 'groups' : 'channels';
  String get noun => widget.groups ? 'grup' : 'saluran';

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = true}) async {
    if (reset) page = 0;
    try {
      final r = asMap(await app.api.get('/admin/$kind?q=${Uri.encodeQueryComponent(q)}&page=$page'));
      final list = asList(r[kind]).map((e) => asMap(e)).toList();
      items = reset ? list : [...items, ...list];
      more = list.length >= 25;
      error = null;
      code = null;
    } catch (e) {
      if (items.isEmpty || reset) {
        error = errText(e);
        code = e is ApiException ? e.code : null;
      } else {
        app.toast(errText(e), error: true);
      }
    }
    if (mounted) {
      setState(() {
        loading = false;
        loadingMore = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore) return;
    setState(() => loadingMore = true);
    page++;
    await load(reset: false);
  }

  Future<void> _toggle(Map<String, dynamic> it) async {
    final id = (it['id'] as num).toInt();
    final verified = it['isVerified'] == true;
    final name = _str(it['name']);
    final ok = await showConfirm(
      context,
      verified ? 'Cabut centang biru?' : 'Beri centang biru?',
      verified ? 'Centang biru $noun "$name" akan dicabut.' : 'Konfirmasi: $noun "$name" akan mendapat centang biru.',
      verified ? 'Cabut' : 'Beri centang biru',
      danger: verified,
    );
    if (!ok) return;
    try {
      await app.api.post('/admin/$kind/$id/verify', {'verified': !verified});
      app.toast(verified ? 'Verifikasi dicabut.' : 'Centang biru diberikan.');
      await load();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    Widget body;
    if (loading) {
      body = const Spin();
    } else if (error != null && items.isEmpty) {
      body = code == 'admin_relogin'
          ? EmptyState(
              icon: Icons.lock_clock,
              title: 'Sesi admin kedaluwarsa',
              text: error,
              action: NeoButton('Keluar lalu masuk lagi', icon: Icons.logout, onPressed: () => app.logout()))
          : EmptyState(icon: Icons.error_outline, title: 'Gagal memuat', text: error, action: NeoButton('Coba lagi', onPressed: () {
              setState(() => loading = true);
              load();
            }));
    } else if (items.isEmpty) {
      body = _emptyList(Icons.search_off, 'Tidak ada $noun', 'Coba kata kunci lain.');
    } else {
      body = ListView.builder(
        physics: _always,
        itemCount: items.length + (more ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == items.length) {
            return Padding(
              padding: const EdgeInsets.all(14),
              child: NeoButton('Muat lebih banyak', primary: false, busy: loadingMore, onPressed: _loadMore),
            );
          }
          final it = items[i];
          final verified = it['isVerified'] == true;
          final count = widget.groups ? '${_str(it['memberCount'])} anggota' : '${_str(it['followerCount'])} pengikut';
          return ListTile(
            leading: Avatar(url: it['avatarUrl'] as String?, name: _str(it['name']), size: 44, group: true, ringStyle: (it['ringStyle'] ?? 'comic').toString()),
            title: Row(children: [
              Flexible(child: Text(_str(it['name']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
              if (verified) const Padding(padding: EdgeInsets.only(left: 4), child: VerifiedBadge(size: 15)),
            ]),
            subtitle: Text('$count  ·  Pemilik: ${_str(it['ownerName']).isEmpty ? '-' : _str(it['ownerName'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: p.muted)),
            trailing: TextButton(
              onPressed: () => _toggle(it),
              child: Text(verified ? 'Cabut' : 'Beri centang', style: TextStyle(fontWeight: FontWeight.w800, color: verified ? p.bad : p.accentText)),
            ),
            onTap: () => _toggle(it),
          );
        },
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: neoDeco(
            context,
            hint: 'Cari nama $noun',
            prefix: const Icon(Icons.search),
            suffix: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                search.clear();
                q = '';
                setState(() => loading = true);
                load();
              },
            ),
          ),
          onSubmitted: (v) {
            q = v.trim();
            setState(() => loading = true);
            load();
          },
        ),
      ),
      Expanded(child: RefreshIndicator(onRefresh: load, child: body)),
    ]);
  }
}

// ------------------------------------------------------------------ laporan
class _ReportsTab extends StatefulWidget {
  const _ReportsTab();
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  String status = 'open';
  int rev = 0;

  static const Map<String, String> _labels = {'open': 'Baru', 'resolved': 'Selesai', 'dismissed': 'Diabaikan'};

  Future<void> _resolve(int id, String st, Future<void> Function() reload) async {
    final note = await _askText(context, title: st == 'resolved' ? 'Tandai selesai' : 'Abaikan laporan', hint: 'Catatan (opsional)', okLabel: 'Kirim');
    if (note == null) return;
    try {
      await app.api.post('/admin/reports/$id/resolve', {'status': st, 'note': note});
      app.toast('Laporan diperbarui.');
      await reload();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: Wrap(spacing: 8, children: [
          for (final e in _labels.entries)
            ChoiceChip(
              label: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w800)),
              selected: status == e.key,
              onSelected: (_) => setState(() => status = e.key),
            ),
        ]),
      ),
      Expanded(
        child: _Fetch(
          key: ValueKey('$status/$rev'),
          load: () => app.api.get('/admin/reports?status=$status'),
          builder: (context, d, reload) {
            final list = asList(d['reports']).map((e) => asMap(e)).toList();
            if (list.isEmpty) return _emptyList(Icons.flag_outlined, 'Tidak ada laporan', 'Belum ada laporan pada kategori ini.');
            return ListView(physics: _always, padding: const EdgeInsets.all(12), children: [
              for (final r in list)
                NeoCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_str(r['reporterName']).isEmpty ? '?' : _str(r['reporterName'])}  →  ${_str(r['reportedName']).isEmpty ? '?' : _str(r['reportedName'])}',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text('Alasan: ${_str(r['reason'])}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (_str(r['details']).isNotEmpty) Text(_str(r['details'])),
                    if (r['snapshot'] is Map)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(10)),
                        child: Text(
                          'Pesan dilaporkan: ${_str(asMap(r['snapshot'])['body']).isEmpty ? '[${_str(asMap(r['snapshot'])['type'])}]' : _str(asMap(r['snapshot'])['body'])}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 6),
                    Text(_when(r['createdAt']), style: TextStyle(color: p.muted, fontSize: 12)),
                    if (_str(r['note']).isNotEmpty) Text('Catatan: ${_str(r['note'])}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                    if (status == 'open') ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: NeoButton('Selesai', icon: Icons.check, onPressed: () => _resolve((r['id'] as num).toInt(), 'resolved', reload))),
                        const SizedBox(width: 8),
                        Expanded(child: NeoButton('Abaikan', primary: false, onPressed: () => _resolve((r['id'] as num).toInt(), 'dismissed', reload))),
                      ]),
                    ],
                  ]),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ pengumuman
class _AnnForm extends StatefulWidget {
  final Future<void> Function() onPosted;
  const _AnnForm({required this.onPosted});
  @override
  State<_AnnForm> createState() => _AnnFormState();
}

class _AnnFormState extends State<_AnnForm> {
  final TextEditingController title = TextEditingController();
  final TextEditingController body = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final t = title.text.trim();
    final b = body.text.trim();
    if (t.isEmpty || b.isEmpty) {
      app.toast('Judul dan isi pengumuman wajib diisi.', error: true);
      return;
    }
    setState(() => busy = true);
    try {
      await app.api.post('/admin/announcements', {'title': t, 'body': b});
      title.clear();
      body.clear();
      app.toast('Pengumuman terbit.');
      await widget.onPosted();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return NeoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Pengumuman baru', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
        const SizedBox(height: 10),
        TextField(controller: title, maxLength: 100, decoration: neoDeco(context, hint: 'Judul')),
        const SizedBox(height: 8),
        TextField(controller: body, maxLength: 1000, minLines: 3, maxLines: 6, decoration: neoDeco(context, hint: 'Isi pengumuman')),
        const SizedBox(height: 8),
        NeoButton('Terbitkan pengumuman', icon: Icons.campaign_outlined, busy: busy, onPressed: _post),
      ]),
    );
  }
}

class _AnnTab extends StatelessWidget {
  const _AnnTab();

  @override
  Widget build(BuildContext context) {
    return _Fetch(
      load: () => app.api.get('/admin/announcements'),
      builder: (context, d, reload) {
        final p = pal(context);
        final list = asList(d['announcements']).map((e) => asMap(e)).toList();
        Future<void> act(Future<dynamic> Function() run) async {
          try {
            await run();
            await reload();
          } catch (e) {
            app.toast(errText(e), error: true);
          }
        }

        return ListView(physics: _always, padding: const EdgeInsets.all(12), children: [
          _AnnForm(onPosted: reload),
          if (list.isEmpty)
            Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('Belum ada pengumuman.', style: TextStyle(color: p.muted))))
          else
            for (final a in list)
              NeoCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_str(a['title']), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(_str(a['body'])),
                  const SizedBox(height: 4),
                  Text(_when(a['created_at']), style: TextStyle(color: p.muted, fontSize: 12)),
                  Row(children: [
                    const Text('Aktif', style: TextStyle(fontWeight: FontWeight.w700)),
                    Switch(
                      value: a['active'] == 1 || a['active'] == true,
                      onChanged: (v) => act(() => app.api.patch('/admin/announcements/${(a['id'] as num).toInt()}', {'active': v})),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.delete_outline, color: p.bad),
                      onPressed: () async {
                        if (await showConfirm(context, 'Hapus pengumuman?', 'Pengumuman "${_str(a['title'])}" akan dihapus permanen.', 'Hapus', danger: true)) {
                          await act(() => app.api.delete('/admin/announcements/${(a['id'] as num).toInt()}'));
                        }
                      },
                    ),
                  ]),
                ]),
              ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ broadcast (khusus developer)
class _BroadcastTab extends StatefulWidget {
  const _BroadcastTab();
  @override
  State<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends State<_BroadcastTab> {
  final TextEditingController title = TextEditingController();
  final TextEditingController body = TextEditingController();
  Timer? _poll;
  bool starting = false;
  bool loading = true;
  bool pushOn = true;
  int pushDevices = -1; // jumlah HP yang sudah mendaftarkan token push (-1 = belum diketahui)
  String pushReason = '';
  Map<String, dynamic>? cur; // broadcast yang sedang/baru dipantau
  List<Map<String, dynamic>> history = [];
  int _failPolls = 0;

  bool get running => cur != null && cur!['status'] == 'running';

  @override
  void initState() {
    super.initState();
    _loadHistory(resume: true);
  }

  @override
  void dispose() {
    _poll?.cancel();
    title.dispose();
    body.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({bool resume = false}) async {
    try {
      final r = asMap(await app.api.get('/admin/broadcast'));
      history = asList(r['items']).map((e) => asMap(e)).toList();
      final p = asMap(r['push']);
      pushOn = p['enabled'] == true;
      pushReason = _str(p['reason']);
      pushDevices = (p['devices'] as num?)?.toInt() ?? -1;
      if (resume && history.isNotEmpty && history.first['status'] == 'running') {
        cur = history.first;
        _startPolling();
      }
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => loading = false);
  }

  void _startPolling() {
    _poll?.cancel();
    _failPolls = 0;
    _poll = Timer.periodic(const Duration(milliseconds: 700), (_) => _tick());
  }

  Future<void> _tick() async {
    final id = cur?['id'];
    if (id == null) return;
    try {
      final r = asMap(await app.api.get('/admin/broadcast/$id'));
      _failPolls = 0;
      cur = asMap(r['broadcast']);
      if (cur!['status'] != 'running') {
        _poll?.cancel();
        final ok = cur!['status'] == 'done';
        app.toast(ok ? 'Broadcast selesai terkirim.' : 'Broadcast gagal: ${_str(cur!['error'])}', error: !ok);
        if (ok) body.clear();
        await _loadHistory();
      }
    } catch (_) {
      if (++_failPolls >= 6) {
        _poll?.cancel();
        app.toast('Tidak dapat memantau progres broadcast. Cek riwayat di bawah.', error: true);
        await _loadHistory();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final t = title.text.trim();
    final b = body.text.trim();
    if (b.isEmpty) {
      app.toast('Isi broadcast wajib diisi.', error: true);
      return;
    }
    final ok = await showConfirm(
      context,
      'Kirim broadcast?',
      'Pesan ini akan dikirim ke SEMUA pengguna aktif dan tidak bisa ditarik kembali.\n\n${t.isEmpty ? '📢 PENGUMUMAN RESMI' : t}\n$b',
      'Kirim',
    );
    if (!ok || !mounted) return;
    setState(() => starting = true);
    try {
      final r = asMap(await app.api.post('/admin/broadcast', {'title': t, 'body': b}));
      cur = asMap(r['broadcast']);
      _startPolling();
    } catch (e) {
      app.toast(errText(e), error: true);
    }
    if (mounted) setState(() => starting = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    final percent = cur == null ? 0 : (cur!['percent'] as num? ?? 0).toInt().clamp(0, 100);
    final status = cur == null ? '' : _str(cur!['status']);
    return ListView(physics: _always, padding: const EdgeInsets.all(12), children: [
      if (!pushOn)
        NeoCard(
          color: p.yellow,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: Color(0xFF111111)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Push FCM belum aktif di server (${pushReason.isEmpty ? 'Firebase belum diisi' : pushReason}). Broadcast tetap masuk ke daftar notifikasi di aplikasi, tetapi belum muncul sebagai notifikasi HP.',
                style: const TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ]),
        ),
      if (pushOn && pushDevices == 0)
        NeoCard(
          color: p.yellow,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, color: Color(0xFF111111)),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Server siap, tetapi belum ada HP yang terdaftar untuk menerima push. Taruh google-services.json (app com.zarr.chat) di android/app/ pada project Flutter, build ulang APK, pasang, lalu login dan buka aplikasi sekali.',
                style: TextStyle(color: Color(0xFF111111), fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ]),
        ),
      if (pushOn && pushDevices > 0)
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
          child: Text('Push aktif • $pushDevices HP terdaftar', style: TextStyle(color: p.muted, fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
      NeoCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Broadcast ke semua pengguna', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          const SizedBox(height: 4),
          Text('Muncul sebagai notifikasi di HP semua pengguna (dengan suara) dan di daftar notifikasi aplikasi.', style: TextStyle(color: p.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          TextField(controller: title, maxLength: 60, enabled: !running && !starting, decoration: neoDeco(context, hint: 'Judul (kosong = 📢 PENGUMUMAN RESMI)')),
          const SizedBox(height: 8),
          TextField(controller: body, maxLength: 500, minLines: 3, maxLines: 6, enabled: !running && !starting, decoration: neoDeco(context, hint: 'Isi pesan broadcast')),
          const SizedBox(height: 8),
          NeoButton(running ? 'Sedang mengirim…' : 'Kirim Broadcast', icon: Icons.campaign_outlined, busy: starting, onPressed: running ? null : _send),
        ]),
      ),
      if (cur != null)
        NeoCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(
                  status == 'running' ? 'Mengirim broadcast…' : (status == 'done' ? 'Broadcast selesai' : 'Broadcast gagal'),
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
              Text('$percent%', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            ]),
            const SizedBox(height: 8),
            Container(
              height: 22,
              decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.line, width: 2)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 22,
                  backgroundColor: Colors.transparent,
                  color: status == 'failed' ? p.bad : p.accent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_str(cur!['processed'])}/${_str(cur!['total'])} pengguna • push terkirim ${_str(cur!['pushSent'])}, gagal ${_str(cur!['pushFailed'])}',
              style: TextStyle(color: p.muted, fontSize: 12.5),
            ),
            if (status == 'failed' && _str(cur!['error']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_str(cur!['error']), style: TextStyle(color: p.bad, fontSize: 12.5))),
          ]),
        ),
      const NeoSection('Riwayat broadcast'),
      if (history.isEmpty)
        Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('Belum ada broadcast.', style: TextStyle(color: p.muted))))
      else
        for (final h in history)
          NeoCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_str(h['title']), style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(_str(h['body']), maxLines: 3, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                '${_when(h['createdAt'])} • ${_str(h['status']) == 'done' ? 'selesai' : (_str(h['status']) == 'running' ? 'berjalan' : 'gagal')} • ${_str(h['processed'])}/${_str(h['total'])} pengguna • push ${_str(h['pushSent'])}',
                style: TextStyle(color: p.muted, fontSize: 12),
              ),
            ]),
          ),
    ]);
  }
}

// ------------------------------------------------------------------ pengaturan
class _SettingsTab extends StatelessWidget {
  final User me;
  const _SettingsTab({required this.me});

  static const Map<String, String> _labels = {
    'registration_open': 'Pendaftaran akun baru',
    'status_ttl_hours': 'Masa berlaku status (jam, 1–48)',
    'edit_window_min': 'Batas waktu edit pesan (menit, 1–60)',
    'delete_window_min': 'Batas waktu hapus untuk semua (menit, 1–10080)',
  };

  @override
  Widget build(BuildContext context) {
    final canCfg = me.role == 'superadmin' || me.role == 'developer';
    return _Fetch(
      load: () => app.api.get('/admin/settings'),
      builder: (context, d, reload) {
        final p = pal(context);
        final settings = asMap(d['settings']);
        Future<void> save(String key, String value) async {
          try {
            await app.api.put('/admin/settings', {'key': key, 'value': value});
            app.toast('Pengaturan disimpan.');
            await reload();
          } catch (e) {
            app.toast(errText(e), error: true);
          }
        }

        return ListView(physics: _always, children: [
          if (!canCfg)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text('Hanya superadmin dan developer yang dapat mengubah pengaturan.', style: TextStyle(color: p.muted)),
            ),
          for (final e in settings.entries)
            if (e.key == 'registration_open')
              SwitchListTile(
                title: Text(_labels[e.key] ?? e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_str(e.value) == 'true' ? 'Terbuka' : 'Ditutup'),
                value: _str(e.value) == 'true',
                onChanged: canCfg ? (v) => save(e.key, v ? 'true' : 'false') : null,
              )
            else
              ListTile(
                title: Text(_labels[e.key] ?? e.key, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(_str(e.value)),
                trailing: canCfg ? const Icon(Icons.edit_outlined) : null,
                onTap: canCfg
                    ? () async {
                        final v = await _askText(context, title: _labels[e.key] ?? e.key, initial: _str(e.value), hint: 'Angka', maxLength: 6, required: true);
                        if (v != null && v.isNotEmpty && v != _str(e.value)) await save(e.key, v);
                      }
                    : null,
              ),
        ]);
      },
    );
  }
}

// ------------------------------------------------------------------ audit log
class _AuditTab extends StatefulWidget {
  const _AuditTab();
  @override
  State<_AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<_AuditTab> {
  int page = 0;

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return Column(children: [
      Expanded(
        child: _Fetch(
          key: ValueKey(page),
          load: () => app.api.get('/admin/audit?page=$page'),
          builder: (context, d, reload) {
            final logs = asList(d['logs']).map((e) => asMap(e)).toList();
            if (logs.isEmpty) return _emptyList(Icons.history, 'Tidak ada catatan', page == 0 ? 'Belum ada tindakan admin.' : 'Tidak ada data di halaman ini.');
            return ListView(physics: _always, padding: const EdgeInsets.all(12), children: [
              for (final l in logs)
                NeoCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(_str(l['action']), style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('oleh ${_str(l['actor']).isEmpty ? '(sistem)' : _str(l['actor'])}  ·  ${_str(l['target_type'])} ${_str(l['target_id'])}', style: TextStyle(color: p.muted, fontSize: 12.5)),
                    if (l['meta'] != null) Text(l['meta'] is String ? l['meta'] as String : jsonEncode(l['meta']), style: const TextStyle(fontSize: 12.5)),
                    const SizedBox(height: 2),
                    Text(_when(l['created_at']), style: TextStyle(color: p.muted, fontSize: 12)),
                  ]),
                ),
            ]);
          },
        ),
      ),
      Container(
        decoration: BoxDecoration(color: p.surface2, border: Border(top: BorderSide(color: p.line, width: 2))),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton.icon(onPressed: page == 0 ? null : () => setState(() => page--), icon: const Icon(Icons.chevron_left), label: const Text('Sebelumnya')),
          Text('Halaman ${page + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
          TextButton(
            onPressed: () => setState(() => page++),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Berikutnya'), SizedBox(width: 4), Icon(Icons.chevron_right)]),
          ),
        ]),
      ),
    ]);
  }
}

// ------------------------------------------------------------------ error sistem
class _ErrorsTab extends StatelessWidget {
  const _ErrorsTab();
  @override
  Widget build(BuildContext context) {
    return _Fetch(
      load: () => app.api.get('/admin/errors'),
      builder: (context, d, reload) {
        final p = pal(context);
        final list = asList(d['errors']).map((e) => asMap(e)).toList();
        if (list.isEmpty) return _emptyList(Icons.check_circle_outline, 'Tidak ada error', 'Belum ada error sistem yang tercatat.');
        return ListView(physics: _always, padding: const EdgeInsets.all(12), children: [
          for (final e in list)
            NeoCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_str(e['path']), style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(_str(e['message'])),
                const SizedBox(height: 2),
                Text(_when(e['created_at']), style: TextStyle(color: p.muted, fontSize: 12)),
              ]),
            ),
        ]);
      },
    );
  }
}
