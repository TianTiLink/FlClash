// 原生「充值 / 购买套餐」—— 替代原来会崩的 webview。
// 流程:列套餐 → 选周期 → 下单(order/save 得 trade_no)→ 选支付方式(getPaymentMethod)
//       → 结账(order/checkout)→ 按返回 type 处理:
//         type=1 外部支付URL → 系统浏览器打开(易支付/yzf 收银台,网关拒绝内嵌 webview,必须外部)
//         type=0 二维码串    → 原生 QR 显示(手机扫码支付)
//         type=-1 免费/已抵扣 → 直接成功
//       → 轮询 order/check 到账 → 刷新订阅 → 返回。
//
// 依赖:qr_flutter(已用于代理中心,pubspec 已有)。openExternal 来自 web_page.dart。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'xboard_api.dart';
import 'xboard_auth.dart';
import 'xboard_sync.dart';
import 'web_page.dart'; // openExternal

const Color _kIndigo = Color(0xFF2B2F77);
const Color _kIndigoDeep = Color(0xFF20244F);
const Color _kAmber = Color(0xFFE9B949);

/// 周期价格键 -> 中文;顺序即展示顺序。
const List<(String, String)> _periods = [
  ('month_price', '月付'),
  ('quarter_price', '季付'),
  ('half_year_price', '半年付'),
  ('year_price', '年付'),
  ('two_year_price', '两年付'),
  ('three_year_price', '三年付'),
  ('onetime_price', '一次性'),
];

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

class PlansPage extends ConsumerStatefulWidget {
  const PlansPage({super.key});

  @override
  ConsumerState<PlansPage> createState() => _PlansPageState();
}

class _PlansPageState extends ConsumerState<PlansPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _plans = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  ({String url, String token})? _auth() {
    final auth = ref.read(xboardAuthProvider);
    final t = auth.authData;
    if (t == null) return null;
    return (url: auth.panelUrl, token: t);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final a = _auth();
    if (a == null) {
      setState(() {
        _loading = false;
        _error = '未登录';
      });
      return;
    }
    try {
      final list = await XboardApi(a.url).fetchPlans(a.token);
      if (!mounted) return;
      setState(() {
        _plans = list;
        _loading = false;
      });
    } on XboardApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '网络错误:$e';
        _loading = false;
      });
    }
  }

  // ---------- 购买流程 ----------

  Future<void> _buy(
      Map<String, dynamic> plan, String periodKey, int priceCents) async {
    final a = _auth();
    if (a == null) return;
    final api = XboardApi(a.url);
    final planId = _toInt(plan['id']);
    final planName = plan['name']?.toString() ?? '套餐';
    final periodLabel =
        _periods.firstWhere((p) => p.$1 == periodKey, orElse: () => (periodKey, periodKey)).$2;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认购买'),
        content: Text('$planName · $periodLabel\n金额:¥${(priceCents / 100).toStringAsFixed(2)}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _kIndigo, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('去支付')),
        ],
      ),
    );
    if (confirm != true) return;

    _showBlockingLoader('正在创建订单…');
    String tradeNo;
    try {
      tradeNo = await api.createOrder(a.token, planId: planId, period: periodKey);
    } on XboardApiException catch (e) {
      _dismissLoader();
      _snack(e.message); // 常见:已有未支付订单 → 提示去「我的订单」
      return;
    } catch (e) {
      _dismissLoader();
      _snack('创建订单失败:$e');
      return;
    }

    // 选支付方式
    int method;
    try {
      final methods = await api.getPaymentMethods(a.token);
      _dismissLoader();
      if (methods.isEmpty) {
        _snack('后台未启用任何支付方式,请联系管理员');
        return;
      }
      if (methods.length == 1) {
        method = _toInt(methods.first['id']);
      } else {
        final picked = await _pickMethod(methods);
        if (picked == null) return; // 用户取消
        method = picked;
      }
    } catch (e) {
      _dismissLoader();
      _snack('获取支付方式失败:$e');
      return;
    }

    // 结账
    _showBlockingLoader('正在发起支付…');
    ({int type, String data}) res;
    try {
      res = await api.checkout(a.token, tradeNo, method);
      _dismissLoader();
    } on XboardApiException catch (e) {
      _dismissLoader();
      _snack(e.message);
      return;
    } catch (e) {
      _dismissLoader();
      _snack('发起支付失败:$e');
      return;
    }

    if (res.type == -1) {
      // 免费 / 余额已抵扣,直接成功
      await _onPaid();
      return;
    }
    // type 1 外部URL / type 0 二维码 → 进等待页轮询
    if (!mounted) return;
    final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => _PayWaitPage(
        panelUrl: a.url,
        token: a.token,
        tradeNo: tradeNo,
        payType: res.type,
        payData: res.data,
      ),
    ));
    if (paid == true) await _onPaid();
  }

  Future<int?> _pickMethod(List<Map<String, dynamic>> methods) {
    return showDialog<int>(
      context: context,
        builder: (ctx) => SimpleDialog(
        title: const Text('选择支付方式'),
        children: [
          for (final m in methods)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, _toInt(m['id'])),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(m['name']?.toString() ?? '支付'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _onPaid() async {
    // 支付成功:刷新订阅让新套餐生效,然后回账户页。
    _showBlockingLoader('支付成功,正在更新订阅…');
    try {
      final url = await ref.read(xboardAuthProvider.notifier).refreshSubscribe();
      if (url != null) await importXboardSubscription(url);
    } catch (_) {}
    _dismissLoader();
    if (!mounted) return;
    _snack('购买成功,套餐已生效');
    Navigator.of(context).pop(); // 回账户页
  }

  // ---------- loader / snack ----------

  bool _loaderShown = false;
  void _showBlockingLoader(String text) {
    if (_loaderShown) return;
    _loaderShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4)),
                  const SizedBox(width: 16),
                  Text(text),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _dismissLoader() {
    if (!_loaderShown) return;
    _loaderShown = false;
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
  }

  void _snack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('充值 / 购买套餐'),
        actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_plans.isEmpty) {
      return Center(
        child: Text('暂无可购套餐',
            style: TextStyle(color: Theme.of(context).hintColor)),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _plans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, i) => _planCard(_plans[i]),
      ),
    );
  }

  Widget _planCard(Map<String, dynamic> plan) {
    final theme = Theme.of(context);
    final name = plan['name']?.toString() ?? '套餐';
    final transferGb = _toInt(plan['transfer_enable']).toDouble();
    final desc = _stripHtml(plan['content']?.toString() ?? '');

    // 可购周期(价格非空的)
    final available = <(String, String, int)>[];
    for (final p in _periods) {
      final v = plan[p.$1];
      if (v != null) available.add((p.$1, p.$2, _toInt(v)));
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kIndigo, _kIndigoDeep],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  color: _kAmber, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(name,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold)),
              ),
              if (transferGb > 0)
                Text('${transferGb.toStringAsFixed(0)} GB',
                    style: const TextStyle(color: _kAmber, fontWeight: FontWeight.w600)),
            ],
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(desc,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
          ],
          const SizedBox(height: 14),
          if (available.isEmpty)
            const Text('该套餐暂未开放购买',
                style: TextStyle(color: Colors.white54, fontSize: 12))
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final a in available)
                  _periodButton(plan, a.$1, a.$2, a.$3),
              ],
            ),
        ],
      ),
    );
  }

  Widget _periodButton(
      Map<String, dynamic> plan, String key, String label, int cents) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _buy(plan, key, cents),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _kAmber.withOpacity(0.55)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 2),
            Text('¥${(cents / 100).toStringAsFixed(2)}',
                style: const TextStyle(
                    color: _kAmber, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  String _stripHtml(String s) =>
      s.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ============================ 支付等待页(轮询到账) ============================

class _PayWaitPage extends ConsumerStatefulWidget {
  final String panelUrl;
  final String token;
  final String tradeNo;
  final int payType; // 1 外部URL / 0 二维码
  final String payData;

  const _PayWaitPage({
    required this.panelUrl,
    required this.token,
    required this.tradeNo,
    required this.payType,
    required this.payData,
  });

  @override
  ConsumerState<_PayWaitPage> createState() => _PayWaitPageState();
}

class _PayWaitPageState extends ConsumerState<_PayWaitPage> {
  bool _checking = false;
  bool _autoStopped = false;
  int _tries = 0;

  @override
  void initState() {
    super.initState();
    if (widget.payType == 1) {
      // 外部支付:自动拉起系统浏览器
      WidgetsBinding.instance.addPostFrameCallback((_) => _openPay());
    }
    _autoPoll();
  }

  Future<void> _openPay() => openExternal(widget.payData);

  // 每 3 秒自动查一次,最多 ~40 次(2 分钟);也可手动点「我已支付」。
  Future<void> _autoPoll() async {
    while (mounted && !_autoStopped && _tries < 40) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || _autoStopped) return;
      _tries++;
      final paid = await _checkOnce(silent: true);
      if (paid) return;
    }
  }

  Future<bool> _checkOnce({bool silent = false}) async {
    if (_checking) return false;
    if (!silent) setState(() => _checking = true);
    try {
      final status =
          await XboardApi(widget.panelUrl).checkOrderStatus(widget.token, widget.tradeNo);
      // 0 待支付 / 1 开通中 / 2 已取消 / 3 已完成 / 4 已折抵
      if (status == 1 || status == 3 || status == 4) {
        _autoStopped = true;
        if (mounted) Navigator.of(context).pop(true); // 成功
        return true;
      }
      if (status == 2) {
        _autoStopped = true;
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('订单已取消')));
          Navigator.of(context).pop(false);
        }
        return true;
      }
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('尚未收到支付,请完成支付后再试')));
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('查询失败:$e')));
      }
    } finally {
      if (!silent && mounted) setState(() => _checking = false);
    }
    return false;
  }

  @override
  void dispose() {
    _autoStopped = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('完成支付')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.payType == 0) ...[
                const Text('请用支付宝/微信扫码支付',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(data: widget.payData, size: 220),
                ),
              ] else ...[
                const Icon(Icons.open_in_browser, size: 48, color: _kIndigo),
                const SizedBox(height: 16),
                const Text('已在浏览器打开收银台,请完成支付',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: _openPay,
                  icon: const Icon(Icons.refresh),
                  label: const Text('没弹出?再次打开支付页'),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Text('正在等待支付结果…',
                      style: TextStyle(color: theme.hintColor, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: _kIndigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _checking ? null : () => _checkOnce(),
                  child: _checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('我已完成支付'),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text('稍后支付(去我的订单)',
                    style: TextStyle(color: theme.hintColor)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
