// 账户页 —— 显示套餐/用量/到期,并提供 充值 / 在线客服 / 刷新订阅 / 退出登录。
// 充值和客服都通过 web_page.dart 的 openWeb(移动内嵌 WebView,桌面外部浏览器)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_api.dart';
import 'xboard_auth.dart';
import 'xboard_sync.dart';
import 'web_page.dart';

/// 你的 Tawk.to 直连聊天地址:后台 Tawk.to -> Administration -> Chat Widget -> Direct Chat Link。
/// 形如 https://tawk.to/chat/<PROPERTY_ID>/<WIDGET_ID>
const String kTawkToChatUrl =
    'https://tawk.to/chat/REPLACE_PROPERTY_ID/REPLACE_WIDGET_ID';

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  XboardSubscribe? _info;
  String? _error;
  bool _loading = true;
  bool _refreshing = false; // 防止连续点两下「刷新订阅」在 FlClash 里堆出重复 profile

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final auth = ref.read(xboardAuthProvider);
    final token = auth.authData;
    if (token == null) {
      setState(() {
        _loading = false;
        _error = '未登录';
      });
      return;
    }
    try {
      final info = await XboardApi(auth.panelUrl).getSubscribe(token);
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshSubscription() async {
    if (_refreshing) return; // 已经在刷新,忽略这一次点击
    setState(() => _refreshing = true);
    try {
      final url = await ref.read(xboardAuthProvider.notifier).refreshSubscribe();
      if (url != null) await importXboardSubscription(url);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('订阅已刷新')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('刷新失败:$e')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(xboardAuthProvider.notifier).logout();
    // 门控(XboardGate)会自动切回登录页。
  }

  String _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

  String _expire(int? unix) {
    if (unix == null) return '长期有效';
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(xboardAuthProvider);
    final theme = Theme.of(context);
    final panelBase = auth.panelUrl.replaceAll(RegExp(r'/+$'), '');

    return Scaffold(
      appBar: AppBar(
        title: const Text('账户'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              theme,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(auth.email.isEmpty ? '(未知账号)' : auth.email,
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(panelBase,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor)),
                  const Divider(height: 24),
                  if (_loading)
                    const Center(child: Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator()))
                  else if (_error != null)
                    Text('读取用量失败:$_error',
                        style: TextStyle(color: theme.colorScheme.error))
                  else if (_info != null)
                    _usage(theme, _info!),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _actionTile(theme, Icons.add_card_outlined, '充值 / 购买套餐', () {
              openWeb(context, url: '$panelBase/#/plan', title: '充值');
            }),
            _actionTile(theme, Icons.support_agent_outlined, '在线客服', () {
              openWeb(context, url: kTawkToChatUrl, title: '在线客服');
            }),
            _actionTile(
              theme,
              _refreshing ? Icons.hourglass_empty : Icons.sync_outlined,
              _refreshing ? '刷新中…' : '刷新订阅',
              _refreshing ? null : _refreshSubscription,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: const Text('退出登录'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _usage(ThemeData theme, XboardSubscribe info) {
    final used = info.upload + info.download;
    final total = info.transferEnable;
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('套餐:${info.planName ?? "-"}'),
            Text('到期:${_expire(info.expiredAt)}'),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: ratio, minHeight: 8),
        ),
        const SizedBox(height: 6),
        Text(
          total > 0
              ? '已用 ${_gb(used)} GB / 共 ${_gb(total)} GB'
              : '已用 ${_gb(used)} GB(不限量)',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
      ],
    );
  }

  Widget _card(ThemeData theme, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }

  Widget _actionTile(
      ThemeData theme, IconData icon, String label, VoidCallback? onTap) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
