// 代理中心页 —— 下线树 / 收益明细 / USDT 提现。
// 数据来自 Reseller 插件接口(见 reseller_api.dart)。认证复用 XboardAuth。
//
// 接入:在主界面/账户页放一个入口按钮 push 本页,例如:
//   IconButton(icon: const Icon(Icons.groups_outlined),
//     onPressed: () => Navigator.of(context).push(
//       MaterialPageRoute(builder: (_) => const AgentCenterPage())));
//
// import 路径按你的品牌包名改(fl_clash → 你的 name)。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'reseller_api.dart';
import 'xboard_api.dart';
import 'xboard_auth.dart';

class AgentCenterPage extends ConsumerStatefulWidget {
  const AgentCenterPage({super.key});

  @override
  ConsumerState<AgentCenterPage> createState() => _AgentCenterPageState();
}

class _AgentCenterPageState extends ConsumerState<AgentCenterPage> {
  ResellerApi? _api;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  String? _inviteLink; // 推广链接(异步获取,拿不到不影响主功能)
  bool _inviteLoading = true; // 邀请码首次加载中(初始 true,避免闪现错误态)
  String? _inviteError; // 邀请码获取失败原因(null=无错误)

  ResellerApi get api {
    final auth = ref.read(xboardAuthProvider);
    return _api ??= ResellerApi(auth.panelUrl, authData: auth.authData);
  }

  bool get isAgent => (_summary?['is_agent'] as bool?) ?? false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await api.summary();
      setState(() {
        _summary = s;
        _loading = false;
      });
      _loadInvite(); // 概览渲染后再异步取推广链接
    } on XboardApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '网络错误:$e';
        _loading = false;
      });
    }
  }

  Future<void> _loadInvite() async {
    final auth = ref.read(xboardAuthProvider);
    final token = auth.authData;
    if (token == null) {
      if (mounted) {
        setState(() {
          _inviteLoading = false;
          _inviteError = '未登录';
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _inviteLoading = true;
        _inviteError = null;
      });
    }
    try {
      final code = await XboardApi(auth.panelUrl).fetchInviteCode(token);
      final base = auth.panelUrl.replaceAll(RegExp(r'/+$'), '');
      if (mounted) {
        setState(() {
          _inviteLink = '$base/#/register?code=$code';
          _inviteLoading = false;
        });
      }
    } on XboardApiException catch (e) {
      if (mounted) {
        setState(() {
          _inviteError = e.message;
          _inviteLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _inviteError = '生成推广链接失败:$e';
          _inviteLoading = false;
        });
      }
    }
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已复制推广链接')));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 加载中 / 出错 时先返回,避免下面的 _overview() 等在 _summary 为 null 时崩溃。
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('代理中心')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _summary == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('代理中心'),
          actions: [IconButton(onPressed: _loadSummary, icon: const Icon(Icons.refresh))],
        ),
        body: _errorView(_error ?? '加载失败'),
      );
    }

    final tabs = <Tab>[
      const Tab(text: '概览'),
      const Tab(text: '下线'),
      const Tab(text: '收益'),
      if (isAgent) const Tab(text: '提现'),
    ];
    final views = <Widget>[
      _overview(),
      _DownlinesTab(api: api, isAgent: isAgent),
      _RecordsTab(api: api, isAgent: isAgent),
      if (isAgent) _WithdrawTab(api: api, summary: _summary!, onChanged: _loadSummary),
    ];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('代理中心'),
          actions: [IconButton(onPressed: _loadSummary, icon: const Icon(Icons.refresh))],
          bottom: TabBar(tabs: tabs, isScrollable: true),
        ),
        body: TabBarView(children: views),
      ),
    );
  }

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
              FilledButton(onPressed: _loadSummary, child: const Text('重试')),
            ],
          ),
        ),
      );

  Widget _overview() {
    final s = _summary!;
    final bal = (s['commission_balance_display'] as num?)?.toDouble() ?? 0;
    final pending = ((s['pending_withdraw'] as num?)?.toDouble() ?? 0) / 100;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _promoCard(),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(isAgent ? Icons.workspace_premium : Icons.person_outline,
                      color: isAgent ? Colors.amber : null),
                  const SizedBox(width: 8),
                  Text(isAgent ? '代理' : '普通用户',
                      style: Theme.of(context).textTheme.titleMedium),
                ]),
                const Divider(height: 24),
                if (isAgent) ...[
                  _kv('可提现余额', '${bal.toStringAsFixed(2)} USDT', big: true),
                  _kv('待审核提现', '${pending.toStringAsFixed(2)} USDT'),
                  _kv('累计收益', _usdt(s['total_commission'])),
                  _kv('本月收益', _usdt(s['month_commission'])),
                  _kv('直属下线', '${s['direct_count'] ?? 0} 人'),
                  _kv('全部下线', '${s['total_downline'] ?? 0} 人'),
                ] else ...[
                  _kv('直属下线', '${s['direct_count'] ?? 0} 人'),
                  _kv('累计返流量', _gb(s['total_traffic_rebate_bytes']), big: true),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 推广卡片:邀请链接 + 复制 + 二维码 + 按身份区分的返利提示。
  Widget _promoCard() {
    final theme = Theme.of(context);
    final link = _inviteLink;
    final tip = isAgent
        ? '你是【代理】:好友通过你的链接注册后,他每次充值,你都按层级比例拿【现金佣金(USDT)】,支持多级返佣,余额满额可提现。层级越深、下线越多,赚得越多。'
        : '好友通过你的链接注册后,他充值时按比例返【可用流量】给你(仅直属一级)。想改成拿【现金佣金】+ 多级返佣?联系客服升级为代理。';
    final tipColor = isAgent ? Colors.amber : theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.card_giftcard, color: Colors.amber),
              const SizedBox(width: 8),
              Text('我的推广', style: theme.textTheme.titleMedium),
            ]),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: tipColor.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tipColor.withOpacity(0.35)),
              ),
              child: Text(tip, style: theme.textTheme.bodySmall),
            ),
            const SizedBox(height: 14),
            if (link == null && _inviteLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 10),
                      Text('正在生成推广链接…'),
                    ],
                  ),
                ),
              )
            else if (link == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.link_off, color: Colors.redAccent),
                      const SizedBox(height: 8),
                      Text(_inviteError ?? '暂时无法生成推广链接',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _inviteLoading ? null : _loadInvite,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SelectableText(link,
                    style: const TextStyle(fontSize: 12.5)),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _copy(link),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('复制推广链接'),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: QrImageView(
                    data: link,
                    version: QrVersions.auto,
                    size: 168,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text('好友扫码或用链接注册,即成为你的下线',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v, {bool big = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: TextStyle(color: Theme.of(context).hintColor)),
            Text(v,
                style: big
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      );

  String _usdt(dynamic cents) {
    final c = (cents as num?)?.toDouble() ?? 0;
    return '${(c / 100).toStringAsFixed(2)} USDT';
  }

  String _gb(dynamic bytes) {
    final b = (bytes as num?)?.toDouble() ?? 0;
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }
}

// ─────────────── 下线 Tab ───────────────

class _DownlinesTab extends StatefulWidget {
  final ResellerApi api;
  final bool isAgent;
  const _DownlinesTab({required this.api, required this.isAgent});
  @override
  State<_DownlinesTab> createState() => _DownlinesTabState();
}

class _DownlinesTabState extends State<_DownlinesTab> {
  int _level = 1;
  int _page = 1;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _data;

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
    try {
      final d = await widget.api.downlines(level: _level, page: _page);
      setState(() {
        _data = d;
        _loading = false;
      });
    } on XboardApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = (_data?['list'] as List?) ?? [];
    final total = (_data?['total'] as num?)?.toInt() ?? 0;
    return Column(
      children: [
        if (widget.isAgent)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              const Text('层级 '),
              DropdownButton<int>(
                value: _level,
                items: [for (var i = 1; i <= 10; i++) DropdownMenuItem(value: i, child: Text('第 $i 层'))],
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _level = v;
                      _page = 1;
                    });
                    _load();
                  }
                },
              ),
              const Spacer(),
              Text('共 $total 人'),
            ]),
          )
        else
          const Padding(padding: EdgeInsets.all(12), child: Text('普通用户只显示直属(第 1 层)下线')),
        Expanded(child: _body(list)),
        _pager(total),
      ],
    );
  }

  Widget _body(List list) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (list.isEmpty) return const Center(child: Text('暂无下线'));
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = list[i] as Map;
        final contrib = m['contribution'] as Map?;
        final isCash = contrib?['type'] == 'cash';
        final cv = (contrib?['value'] as num?)?.toDouble() ?? 0;
        return ListTile(
          leading: CircleAvatar(child: Text('${m['level'] ?? 1}')),
          title: Text('${m['email'] ?? '—'}'),
          subtitle: Text(
              '注册 ${_date(m['created_at'])}${(m['is_agent'] == true) ? ' · 代理' : ''}'),
          trailing: Text(
            isCash ? '+${cv.toStringAsFixed(2)} USDT' : '+${cv.toStringAsFixed(2)} GB',
            style: const TextStyle(color: Colors.green),
          ),
        );
      },
    );
  }

  Widget _pager(int total) {
    final perPage = (_data?['per_page'] as num?)?.toInt() ?? 20;
    final lastPage = total == 0 ? 1 : ((total + perPage - 1) ~/ perPage);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
            onPressed: _page > 1 ? () { setState(() => _page--); _load(); } : null,
            icon: const Icon(Icons.chevron_left)),
        Text('$_page / $lastPage'),
        IconButton(
            onPressed: _page < lastPage ? () { setState(() => _page++); _load(); } : null,
            icon: const Icon(Icons.chevron_right)),
      ]),
    );
  }

  String _date(dynamic ts) {
    final t = (ts as num?)?.toInt() ?? 0;
    if (t == 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

// ─────────────── 收益 Tab ───────────────

class _RecordsTab extends StatefulWidget {
  final ResellerApi api;
  final bool isAgent;
  const _RecordsTab({required this.api, required this.isAgent});
  @override
  State<_RecordsTab> createState() => _RecordsTabState();
}

class _RecordsTabState extends State<_RecordsTab> {
  int _page = 1;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _data;
  late final String _type = widget.isAgent ? 'commission' : 'traffic';

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
    try {
      final d = await widget.api.records(type: _type, page: _page);
      setState(() {
        _data = d;
        _loading = false;
      });
    } on XboardApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = (_data?['list'] as List?) ?? [];
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (list.isEmpty) return const Center(child: Text('暂无收益记录'));
    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final m = list[i] as Map;
        final isCash = _type == 'commission';
        final val = isCash
            ? '+${((m['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} USDT'
            : '+${((m['traffic_gb'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} GB';
        return ListTile(
          title: Text('来自 ${m['from_email'] ?? '—'}'),
          subtitle: Text('第 ${m['level'] ?? 1} 层 · ${_date(m['created_at'])}'),
          trailing: Text(val, style: const TextStyle(color: Colors.green)),
        );
      },
    );
  }

  String _date(dynamic ts) {
    final t = (ts as num?)?.toInt() ?? 0;
    if (t == 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ─────────────── 提现 Tab(仅代理)───────────────

class _WithdrawTab extends StatefulWidget {
  final ResellerApi api;
  final Map<String, dynamic> summary;
  final VoidCallback onChanged;
  const _WithdrawTab({required this.api, required this.summary, required this.onChanged});
  @override
  State<_WithdrawTab> createState() => _WithdrawTabState();
}

class _WithdrawTabState extends State<_WithdrawTab> {
  final _amount = TextEditingController();
  final _address = TextEditingController();
  bool _submitting = false;
  List _history = [];
  bool _loadingHistory = true;

  @override
  void initState() {
    super.initState();
    _address.text = (widget.summary['usdt_address'] as String?) ?? '';
    _loadHistory();
  }

  @override
  void dispose() {
    _amount.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final d = await widget.api.withdrawHistory();
      setState(() {
        _history = (d['list'] as List?) ?? [];
        _loadingHistory = false;
      });
    } catch (_) {
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _submit() async {
    final amt = double.tryParse(_amount.text.trim());
    final addr = _address.text.trim();
    if (amt == null || amt <= 0) {
      _toast('请输入正确的提现金额');
      return;
    }
    if (addr.isEmpty) {
      _toast('请输入 USDT(TRC20)收款地址');
      return;
    }
    setState(() => _submitting = true);
    try {
      final r = await widget.api.submitWithdraw(amount: amt, address: addr);
      _toast(r['message']?.toString() ?? '提交成功');
      _amount.clear();
      widget.onChanged(); // 刷新余额
      await _loadHistory();
    } on XboardApiException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final bal = (widget.summary['commission_balance_display'] as num?)?.toDouble() ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('可提现余额', style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(height: 4),
              Text('${bal.toStringAsFixed(2)} USDT',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: '提现金额(USDT)', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                    labelText: 'USDT(TRC20)收款地址',
                    hintText: 'T 开头的 34 位地址',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('提交提现申请'),
              ),
              const SizedBox(height: 8),
              Text('提交后余额立即冻结,等管理员审核打款;驳回则退回余额。',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Text('提现记录', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (_loadingHistory)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else if (_history.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('暂无提现记录'))
        else
          ..._history.map(_historyTile),
      ],
    );
  }

  Widget _historyTile(dynamic item) {
    final m = item as Map;
    final status = (m['status'] as num?)?.toInt() ?? 0;
    final color = [Colors.orange, Colors.green, Colors.red][status.clamp(0, 2)];
    return Card(
      child: ListTile(
        title: Text('${((m['amount'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} USDT'),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${m['usdt_address'] ?? ''}',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          if (m['tx_hash'] != null && '${m['tx_hash']}'.isNotEmpty)
            Text('tx: ${m['tx_hash']}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
          if (m['admin_remark'] != null && '${m['admin_remark']}'.isNotEmpty)
            Text('备注: ${m['admin_remark']}', style: const TextStyle(fontSize: 11)),
        ]),
        trailing: Text('${m['status_text'] ?? ''}', style: TextStyle(color: color, fontSize: 12)),
      ),
    );
  }

  // 未用到,保留以便将来跳转区块链浏览器查看 tx。
  // ignore: unused_element
  Future<void> _openTx(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
