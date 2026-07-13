// 账户页「我的」—— 账户名/套餐/流量/有效期 + 充值/我的订单/工单客服/代理中心/
// 官网/刷新订阅/退出登录。重新排版美化(深靛蓝 + 琥珀金,明暗自适应)。
//
// 客服 = 面板工单系统(/#/ticket 提交+查看,和后台对接),不再用 Tawk.to。
// 订单/工单/充值/官网 都通过 web_page.dart 的 openWeb(移动内嵌 WebView,桌面外部浏览器)。
// 既能作为独立页面被 push,也能作为底部导航「我的」tab 直接嵌入(自带 Scaffold)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_api.dart';
import 'xboard_auth.dart';
import 'xboard_sync.dart';
import 'web_page.dart';
import 'agent_center_page.dart';

/// 品牌配色(深靛蓝 + 琥珀金),与官网一致。
const Color _kIndigo = Color(0xFF2B2F77);
const Color _kIndigoDeep = Color(0xFF20244F);
const Color _kAmber = Color(0xFFE9B949);

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  XboardSubscribe? _info;
  String? _error;
  bool _loading = true;
  bool _refreshing = false; // 防止连点「刷新订阅」在 FlClash 里堆出重复 profile

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
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refreshSubscription() async {
    if (_refreshing) return;
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

  String _panelBase() =>
      ref.read(xboardAuthProvider).panelUrl.replaceAll(RegExp(r'/+$'), '');

  void _openPanel(String route, String title) =>
      openWeb(context, url: '${_panelBase()}$route', title: title);

  String _gb(int bytes) => (bytes / (1024 * 1024 * 1024)).toStringAsFixed(2);

  String _expire(int? unix) {
    if (unix == null) return '长期有效';
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  _sectionCard(theme, [
                    _tile(theme, Icons.add_card_outlined, _kAmber, '充值 / 购买套餐',
                        () => _openPanel('/#/plan', '充值')),
                    _divider(),
                    _tile(theme, Icons.receipt_long_outlined, _kIndigo, '我的订单',
                        () => _openPanel('/#/order', '我的订单')),
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(theme, [
                    _tile(theme, Icons.support_agent_outlined, _kAmber, '工单 / 客服',
                        () => _openPanel('/#/ticket', '工单 / 客服')),
                    _divider(),
                    _tile(theme, Icons.groups_outlined, _kIndigo, '代理中心 / 分销',
                        () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const AgentCenterPage()))),
                    _divider(),
                    _tile(theme, Icons.public_outlined, _kIndigo, '官方网站',
                        () => openWeb(context, url: _panelBase(), title: '官方网站')),
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(theme, [
                    _tile(
                      theme,
                      _refreshing ? Icons.hourglass_empty : Icons.sync_outlined,
                      _kIndigo,
                      _refreshing ? '刷新中…' : '刷新订阅',
                      _refreshing ? null : _refreshSubscription,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('退出登录'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(
                            color: theme.colorScheme.error.withOpacity(0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 顶部账户 + 用量 大卡片(渐变) ----------
  Widget _header(ThemeData theme) {
    final auth = ref.watch(xboardAuthProvider);
    final email = auth.email.isEmpty ? '(未知账号)' : auth.email;
    final initial =
        auth.email.isEmpty ? '?' : auth.email.characters.first.toUpperCase();

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 20, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kIndigo, _kIndigoDeep],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: _kAmber,
                child: Text(initial,
                    style: const TextStyle(
                        color: _kIndigoDeep,
                        fontSize: 20,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    _planBadge(),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _usageBlock(theme),
        ],
      ),
    );
  }

  Widget _planBadge() {
    final name = _info?.planName;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _kAmber.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kAmber.withOpacity(0.6)),
      ),
      child: Text(
        name == null || name.isEmpty ? '未订阅套餐' : name,
        style: const TextStyle(
            color: _kAmber, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _usageBlock(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 14),
        child: Center(
            child: SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: Colors.white70))),
      );
    }
    if (_error != null) {
      return _glassBox(
        child: Text('读取用量失败:$_error',
            style: const TextStyle(color: Colors.white, fontSize: 12)),
      );
    }
    final info = _info;
    if (info == null) return const SizedBox.shrink();

    final used = info.upload + info.download;
    final total = info.transferEnable;
    final ratio = total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
    final remain = total > used ? total - used : 0;

    return _glassBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(total > 0 ? _gb(remain) : _gb(used),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(total > 0 ? 'GB 剩余' : 'GB 已用(不限量)',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total > 0 ? ratio : null,
              minHeight: 7,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(_kAmber),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                total > 0
                    ? '已用 ${_gb(used)} / ${_gb(total)} GB'
                    : '已用 ${_gb(used)} GB',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text('到期 ${_expire(info.expiredAt)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _glassBox({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: child,
      );

  // ---------- 功能卡片 ----------
  Widget _sectionCard(ThemeData theme, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _divider() =>
      const Divider(height: 1, thickness: 1, indent: 56, endIndent: 0);

  Widget _tile(ThemeData theme, IconData icon, Color tint, String label,
      VoidCallback? onTap) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: tint.withOpacity(0.14),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 19, color: tint),
      ),
      title: Text(label,
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500)),
      trailing:
          Icon(Icons.chevron_right, size: 20, color: theme.hintColor),
      dense: false,
    );
  }
}
