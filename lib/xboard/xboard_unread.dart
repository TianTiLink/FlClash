// 客服未读数:后台每 15 秒轮询工单,统计「客服已回复且比上次看到更新」的条数;进客服页清零。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fl_clash/providers/app.dart'; // currentPageLabelProvider
import 'package:fl_clash/enum/enum.dart'; // PageLabel

import 'xboard_api.dart';
import 'xboard_auth.dart';

final xboardUnreadProvider =
    NotifierProvider<XboardUnread, int>(XboardUnread.new);

class XboardUnread extends Notifier<int> {
  static const _storage = FlutterSecureStorage();
  static const _kSeen = 'xboard_ticket_seen';
  Timer? _timer;
  int _lastSeen = 0;

  @override
  int build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(currentPageLabelProvider, (prev, next) {
      if (next == PageLabel.service) markSeen();
    });
    _init();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _poll());
    return 0;
  }

  Future<void> _init() async {
    final v = await _storage.read(key: _kSeen);
    _lastSeen = int.tryParse(v ?? '') ?? 0;
    await _poll();
  }

  Future<void> _poll() async {
    final auth = ref.read(xboardAuthProvider);
    final token = auth.authData;
    if (token == null) {
      state = 0;
      return;
    }
    try {
      final list = await XboardApi(auth.panelUrl).fetchTickets(token);
      var n = 0;
      for (final t in list) {
        final replied = ((t['reply_status'] as num?)?.toInt() ?? 0) == 1;
        final ts = (t['updated_at'] as num?)?.toInt() ??
            (t['created_at'] as num?)?.toInt() ??
            0;
        if (replied && ts > _lastSeen) n++;
      }
      state = n;
    } catch (_) {}
  }

  void markSeen() {
    _lastSeen = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _storage.write(key: _kSeen, value: '$_lastSeen');
    if (state != 0) state = 0;
  }
}
