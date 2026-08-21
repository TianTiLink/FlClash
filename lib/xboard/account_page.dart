// 账户页「我的」—— 账户名/套餐/流量/有效期 + 充值/我的订单/工单客服/代理中心/
// 官网/刷新订阅/退出登录。重新排版美化(深靛蓝 + 琥珀金,明暗自适应)。
//
// 充值/我的订单/工单 都是【原生页面】(plans_page/orders_page/tickets_page,直接调 Xboard API),
// 不再用 webview——flutter_inappwebview 在 Windows 上会卡死。只有「官方网站」用系统浏览器打开。
// 既能作为独立页面被 push,也能作为底部导航「我的」tab 直接嵌入(自带 Scaffold)。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_api.dart';
import 'xboard_auth.dart';
import 'xboard_sync.dart';
import 'xboard_endpoint.dart';
import 'web_page.dart'; // 只用 openExternal(官网)
import 'agent_center_page.dart';
import 'orders_page.dart';
import 'tickets_page.dart';
import 'plans_page.dart';
import 'package:fl_clash/views/theme.dart'; // 主题设置整页(FlClash 自带)
import 'package:fl_clash/views/about.dart'; // 关于页(FlClash 自带,含开源许可)

/// 品牌配色(深靛蓝 + 琥珀金),与官网一致。
const Color _kIndigo = Color(0xFF2B2F77);
const Color _kIndigoDeep = Color(0xFF20244F);
const Color _kAmber = Color(0xFFE9B949);
const Color _kExpired = Color(0xFFFF8A80);

class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  XboardSubscribe? _info;
  XboardRegistrationTrial? _registrationTrial;
  bool _claimingRegistrationTrial = false;
  String? _telegramGroupUrl;
  String? _error;
  bool _loading = true;
  bool _refreshing = false; // 防止连点「刷新订阅」在 FlClash 里堆出重复 profile

  // 推广链接(首页展示,无二维码)
  String? _inviteLink;
  bool _inviteLoading = true;
  String? _inviteError;

  @override
  void initState() {
    super.initState();
    _reload();
    _loadInvite();
  }

  Future<void> _reload() async {
    await Future.wait<void>([_load(), _loadTelegramGroup(), _loadRegistrationTrial()]);
  }

  Future<void> _loadRegistrationTrial() async {
    final auth = ref.read(xboardAuthProvider);
    final token = auth.authData;
    if (token == null) return;
    try {
      final trial = await XboardApi(auth.panelUrl).fetchRegistrationTrial(token);
      if (mounted) setState(() => _registrationTrial = trial);
    } catch (_) {}
  }

  Future<void> _claimRegistrationTrial() async {
    if (_claimingRegistrationTrial) return;
    final auth = ref.read(xboardAuthProvider);
    final token = auth.authData;
    if (token == null) return;
    setState(() => _claimingRegistrationTrial = true);
    try {
      final claimed = await XboardApi(
        auth.panelUrl,
      ).claimRegistrationTrial(token);
      final url = await ref.read(xboardAuthProvider.notifier).refreshSubscribe();
      if (url != null) await importXboardSubscription(url);
      await _load();
      if (!mounted) return;
      setState(() => _registrationTrial = claimed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('注册试用 ${_trialDays(claimed.durationDays)} 已到账')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _claimingRegistrationTrial = false);
    }
  }

  String _trialDays(double days) =>
      days == days.roundToDouble() ? '${days.toInt()}天' : '${days.toStringAsFixed(1)}天';

  Widget _freeBenefitsCard(ThemeData theme) {
    final trial = _registrationTrial;
    final showTrial = trial != null && (trial.enabled || trial.claimed);
    final showTelegram = _telegramGroupUrl != null;
    if (!showTrial && !showTelegram) {
      return const SizedBox.shrink();
    }
    final title = showTrial && showTelegram ? '两种免费权益' : '免费权益';
    final copy = showTrial && showTelegram
        ? '加TG群领取7天VPN；客户端“我的”直接领取试用套餐${_trialDays(trial!.durationDays)}。'
        : showTelegram
        ? '加TG群领取7天VPN，点击下方按钮直接进入官方群。'
        : '客户端“我的”直接领取试用套餐${_trialDays(trial!.durationDays)}。';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kIndigo.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kIndigo.withOpacity(0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            copy,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          if (showTelegram) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFF229ED9),
                  foregroundColor: Colors.white,
                  child: Icon(Icons.send_rounded),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '加TG群领取7天VPN',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      SizedBox(height: 3),
                      Text('点击直接进入TG官方群，加群后按群内指引确认领取'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => openExternal(_telegramGroupUrl!),
                  child: const Text('进入TG群'),
                ),
              ],
            ),
          ],
          if (showTelegram && showTrial) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: theme.dividerColor),
          ],
          if (showTrial) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: _kIndigo,
                  foregroundColor: Colors.white,
                  child: Icon(Icons.redeem_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trial!.claimed
                            ? '试用套餐${_trialDays(trial!.durationDays)}已领取'
                            : '直接领取试用套餐${_trialDays(trial!.durationDays)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        trial!.claimed
                            ? '每个账号限领一次'
                            : '天数按后台设置，可与加群权益叠加',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: trial!.claimed || _claimingRegistrationTrial
                      ? null
                      : _claimRegistrationTrial,
                  child: Text(
                    trial!.claimed
                        ? '已领取'
                        : (_claimingRegistrationTrial ? '领取中…' : '直接领取'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadTelegramGroup() async {
    final auth = ref.read(xboardAuthProvider);
    String? groupUrl;
    try {
      groupUrl = await XboardApi(auth.panelUrl).getTelegramGroupUrl();
    } catch (_) {
      groupUrl = null;
    }
    if (!mounted) return;
    setState(() => _telegramGroupUrl = groupUrl);
  }

  Future<void> _loadInvite() async {
    final auth = ref.read(xboardAuthProvider);
    final token = auth.authData;
    if (token == null) {
      if (mounted)
        setState(() {
          _inviteLoading = false;
          _inviteError = '未登录';
        });
      return;
    }
    if (mounted)
      setState(() {
        _inviteLoading = true;
        _inviteError = null;
      });
    try {
      final code = await XboardApi(auth.panelUrl).fetchInviteCode(token);
      // 邀请链接用官网落地主地址展示,不用会变的通信地址(auth.panelUrl)。
      final base = await officialSiteBase();
      if (mounted)
        setState(() {
          _inviteLink = '$base/#/register?code=$code';
          _inviteLoading = false;
        });
    } on XboardApiException catch (e) {
      if (mounted)
        setState(() {
          _inviteError = e.message;
          _inviteLoading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _inviteError = '生成推广链接失败:$e';
          _inviteLoading = false;
        });
    }
  }

  void _copyInvite(String link) {
    Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已复制推广链接')));
    }
  }

  Widget _promoHomeCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kAmber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kAmber.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.card_giftcard, color: _kAmber, size: 20),
              const SizedBox(width: 8),
              const Text(
                '邀请好友返利',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AgentCenterPage()),
                ),
                child: const Text('收益明细'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_inviteLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('正在生成推广链接…'),
                ],
              ),
            )
          else if (_inviteLink == null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    _inviteError ?? '暂时无法生成推广链接',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
                TextButton(onPressed: _loadInvite, child: const Text('重试')),
              ],
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor),
              ),
              child: SelectableText(
                _inviteLink!,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kIndigo,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => _copyInvite(_inviteLink!),
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('复制推广链接'),
              ),
            ),
          ],
        ],
      ),
    );
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
    final previousSubscription = auth.subscribeUrl;
    try {
      final info = await XboardApi(auth.panelUrl).getSubscribe(token);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } on XboardNoSubscriptionException {
      try {
        await ref.read(xboardAuthProvider.notifier).clearSubscription();
        await clearTianTiSubscriptionProfiles(
          subscribeUrl: previousSubscription,
        );
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _info = null;
        _error = null;
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
    final previousSubscription = ref.read(xboardAuthProvider).subscribeUrl;
    try {
      final url = await ref
          .read(xboardAuthProvider.notifier)
          .refreshSubscribe();
      if (url == null) throw '未登录或获取节点失败';
      // importXboardSubscription 现在会在重下/校验失败时抛异常(不再吞),
      // 能走到下面的成功提示 = 真正重下最新节点并重新应用成功了。
      await importXboardSubscription(url);
      await _reload();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('节点已刷新')));
      }
    } on XboardNoSubscriptionException {
      final removed = await clearTianTiSubscriptionProfiles(
        subscribeUrl: previousSubscription,
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              removed > 0 ? '当前账号没有有效套餐，已清除旧节点。请先购买套餐。' : '当前账号没有有效套餐，请先购买套餐。',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('网络连接失败，当前节点已保留：$e')));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _logout() async {
    final subscription = ref.read(xboardAuthProvider).subscribeUrl;
    await clearTianTiSubscriptionProfiles(subscribeUrl: subscription);
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
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _header(theme),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                children: [
                  _freeBenefitsCard(theme),
                  if (_telegramGroupUrl != null ||
                      (_registrationTrial != null &&
                          (_registrationTrial!.enabled ||
                              _registrationTrial!.claimed)))
                    const SizedBox(height: 14),
                  _promoHomeCard(theme),
                  const SizedBox(height: 14),
                  _sectionCard(theme, [
                    _tile(
                      theme,
                      Icons.add_card_outlined,
                      _kAmber,
                      '充值 / 购买套餐',
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PlansPage()),
                      ),
                    ),
                    _divider(),
                    _tile(
                      theme,
                      Icons.receipt_long_outlined,
                      _kIndigo,
                      '我的订单',
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const OrdersPage()),
                      ),
                    ),
                    _divider(),
                    _tile(
                      theme,
                      Icons.support_agent_outlined,
                      _kIndigo,
                      '我的工单',
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const TicketsPage()),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(theme, [
                    _tile(
                      theme,
                      Icons.groups_outlined,
                      _kIndigo,
                      '代理中心 / 分销',
                      () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AgentCenterPage(),
                        ),
                      ),
                    ),
                    if (_telegramGroupUrl != null) ...[
                      _divider(),
                      _tile(
                        theme,
                        Icons.send_rounded,
                        const Color(0xFF229ED9),
                        'Telegram 官方群',
                        () => openExternal(_telegramGroupUrl!),
                      ),
                    ],
                    _divider(),
                    _tile(
                      theme,
                      Icons.public_outlined,
                      _kIndigo,
                      '官方网站',
                      () async => openExternal(await officialSiteBase()),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _sectionCard(theme, [
                    _tile(
                      theme,
                      Icons.palette_outlined,
                      _kAmber,
                      '主题',
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ThemeView()),
                      ),
                    ),
                    _divider(),
                    _tile(
                      theme,
                      Icons.info_outline,
                      _kIndigo,
                      '关于',
                      () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AboutView()),
                      ),
                    ),
                    _divider(),
                    _tile(
                      theme,
                      _refreshing ? Icons.hourglass_empty : Icons.sync_outlined,
                      _kIndigo,
                      _refreshing ? '刷新中…' : '刷新节点',
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
                          color: theme.colorScheme.error.withOpacity(0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
    final initial = auth.email.isEmpty
        ? '?'
        : auth.email.characters.first.toUpperCase();

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 20,
        20,
        22,
      ),
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
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _kIndigoDeep,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _planBadge(),
                  ],
                ),
              ),
              IconButton(
                tooltip: '刷新',
                onPressed: _loading ? null : _reload,
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
    final info = _info;
    final name = info?.planName;
    final expired = info?.isExpiredAt(DateTime.now()) ?? false;
    final badgeColor = expired ? _kExpired : _kAmber;
    final label = _planBadgeLabel(name, expired);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withOpacity(0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _planBadgeLabel(String? name, bool expired) {
    if (name == null || name.isEmpty) return '未订阅套餐';
    if (expired) return '已到期 · $name';
    return name;
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
              strokeWidth: 2.4,
              color: Colors.white70,
            ),
          ),
        ),
      );
    }
    if (_error != null) {
      return _glassBox(
        child: Text(
          '读取用量失败:$_error',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      );
    }
    final info = _info;
    if (info == null) return const SizedBox.shrink();
    if (info.isExpiredAt(DateTime.now())) {
      return _expiredBlock(info);
    }

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
              Text(
                total > 0 ? _gb(remain) : _gb(used),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  total > 0 ? 'GB 剩余' : 'GB 已用(不限量)',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
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
              Text(
                '到期 ${_expire(info.expiredAt)}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _expiredBlock(XboardSubscribe info) {
    return _glassBox(
      accentColor: _kExpired,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy_rounded, color: _kExpired, size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '套餐已到期',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '到期时间 ${_expire(info.expiredAt)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            '请续费套餐后继续使用，续费成功后下拉刷新即可。',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kExpired,
                foregroundColor: _kIndigoDeep,
              ),
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PlansPage())),
              icon: const Icon(Icons.add_card_outlined, size: 18),
              label: const Text('立即续费'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassBox({required Widget child, Color? accentColor}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: (accentColor ?? Colors.white).withOpacity(
        accentColor == null ? 0.10 : 0.12,
      ),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: (accentColor ?? Colors.white).withOpacity(
          accentColor == null ? 0.15 : 0.55,
        ),
      ),
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

  Widget _tile(
    ThemeData theme,
    IconData icon,
    Color tint,
    String label,
    VoidCallback? onTap,
  ) {
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
      title: Text(
        label,
        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
      ),
      trailing: Icon(Icons.chevron_right, size: 20, color: theme.hintColor),
      dense: false,
    );
  }
}
