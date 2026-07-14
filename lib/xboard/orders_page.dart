// 原生「我的订单」页 —— 替代原来会崩的 webview。模式对齐 account_page/agent_center_page:
// ConsumerStatefulWidget + xboardAuthProvider + initState 调 XboardApi + loading/error/empty/list。
// 接口:GET /api/v1/user/order/fetch(金额单位=分,时间 unix 秒)。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_api.dart';
import 'xboard_auth.dart';

const Color _kIndigo = Color(0xFF2B2F77);
const Color _kAmber = Color(0xFFE9B949);

class OrdersPage extends ConsumerStatefulWidget {
  const OrdersPage({super.key});

  @override
  ConsumerState<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends ConsumerState<OrdersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _orders = const [];

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
      final list = await XboardApi(auth.panelUrl).fetchOrders(token);
      if (!mounted) return;
      setState(() {
        _orders = list;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的订单'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _errorView(_error!);
    if (_orders.isEmpty) return _emptyView('暂无订单');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _orderCard(_orders[i]),
      ),
    );
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final theme = Theme.of(context);
    final plan = o['plan'];
    final planName = plan is Map ? (plan['name']?.toString() ?? '套餐') : '套餐';
    final amount = ((o['total_amount'] as num?)?.toDouble() ?? 0) / 100; // 分->元
    final s = ((o['status'] as num?)?.toInt() ?? 0).clamp(0, 4);
    final labels = ['待支付', '开通中', '已取消', '已完成', '已折抵'];
    final colors = [Colors.orange, _kIndigo, Colors.grey, Colors.green, Colors.green];

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _kAmber.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    size: 19, color: _kAmber),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(planName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors[s].withOpacity(0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(labels[s],
                    style: TextStyle(
                        color: colors[s],
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const Divider(height: 20),
          _kv('订单号', '${o['trade_no'] ?? '—'}'),
          _kv('金额', '¥${amount.toStringAsFixed(2)}'),
          _kv('下单时间', _date(o['created_at'])),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k,
                style:
                    TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
            Flexible(
              child: Text(v,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );

  Widget _errorView(String msg) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(msg, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );

  Widget _emptyView(String msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 40, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(msg, style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      );

  String _date(dynamic ts) {
    final t = (ts as num?)?.toInt() ?? 0;
    if (t == 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}
