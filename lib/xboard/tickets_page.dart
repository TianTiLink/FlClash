// 原生「工单/客服」—— 列表 + 对话详情 + 回复 + 新建。替代原来会崩的 webview。
// 接口:
//   列表   GET  /api/v1/user/ticket/fetch            data 为数组
//   详情   GET  /api/v1/user/ticket/fetch?id=<id>    data 为对象,含 message 数组
//   新建   POST /api/v1/user/ticket/save  {subject,level,message}
//   回复   POST /api/v1/user/ticket/reply {id,message}
//   关闭   POST /api/v1/user/ticket/close {id}
// message.is_me=true 是本人发的,false 是客服回复;时间为 unix 秒。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_api.dart';
import 'xboard_auth.dart';

const Color _kIndigo = Color(0xFF2B2F77);
const Color _kAmber = Color(0xFFE9B949);

// ============================ 列表页 ============================

class TicketsPage extends ConsumerStatefulWidget {
  const TicketsPage({super.key});

  @override
  ConsumerState<TicketsPage> createState() => _TicketsPageState();
}

class _TicketsPageState extends ConsumerState<TicketsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = const [];

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
      final list = await XboardApi(a.url).fetchTickets(a.token);
      if (!mounted) return;
      setState(() {
        _tickets = list;
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

  Future<void> _newTicket() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _NewTicketSheet(),
    );
    if (ok == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('工单 / 客服'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _kIndigo,
        foregroundColor: Colors.white,
        onPressed: _newTicket,
        icon: const Icon(Icons.add),
        label: const Text('新建工单'),
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _CenterMsg.error(_error!, onRetry: _load);
    }
    if (_tickets.isEmpty) {
      return _CenterMsg.empty('暂无工单,点右下角「新建工单」联系客服');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _tickets.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _ticketCard(_tickets[i]),
      ),
    );
  }

  Widget _ticketCard(Map<String, dynamic> t) {
    final theme = Theme.of(context);
    final id = (t['id'] as num?)?.toInt() ?? 0;
    final subject = t['subject']?.toString() ?? '(无主题)';
    final closed = ((t['status'] as num?)?.toInt() ?? 0) == 1;
    final replied = ((t['reply_status'] as num?)?.toInt() ?? 0) == 1;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TicketDetailPage(id: id, subject: subject)));
        _load(); // 回来刷新状态
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.35),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: _kAmber.withOpacity(0.14),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.support_agent_outlined,
                  size: 19, color: _kAmber),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14.5)),
                  const SizedBox(height: 4),
                  Text(_date(t['created_at']),
                      style:
                          TextStyle(color: theme.hintColor, fontSize: 12)),
                ],
              ),
            ),
            _badge(
              closed ? '已关闭' : (replied ? '已回复' : '待回复'),
              closed
                  ? Colors.grey
                  : (replied ? Colors.green : Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );

  String _date(dynamic ts) {
    final t = (ts as num?)?.toInt() ?? 0;
    if (t == 0) return '—';
    final d = DateTime.fromMillisecondsSinceEpoch(t * 1000);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

// ============================ 详情/对话页 ============================

class TicketDetailPage extends ConsumerStatefulWidget {
  final int id;
  final String subject;
  const TicketDetailPage({super.key, required this.id, required this.subject});

  @override
  ConsumerState<TicketDetailPage> createState() => _TicketDetailPageState();
}

class _TicketDetailPageState extends ConsumerState<TicketDetailPage> {
  bool _loading = true;
  String? _error;
  bool _closed = false;
  bool _sending = false;
  List<Map<String, dynamic>> _messages = const [];
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
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
      final t = await XboardApi(a.url).fetchTicketDetail(a.token, widget.id);
      if (!mounted) return;
      final msg = t['message'];
      setState(() {
        _messages = msg is List
            ? msg
                .map((e) => e is Map<String, dynamic>
                    ? e
                    : Map<String, dynamic>.from(e as Map))
                .toList()
            : const [];
        _closed = ((t['status'] as num?)?.toInt() ?? 0) == 1;
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final a = _auth();
    if (a == null) return;
    setState(() => _sending = true);
    try {
      await XboardApi(a.url).replyTicket(a.token, widget.id, text);
      _input.clear();
      await _load();
    } on XboardApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('回复失败:$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _close() async {
    final a = _auth();
    if (a == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('关闭工单'),
        content: const Text('确定关闭这个工单吗?关闭后将无法再回复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('关闭')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await XboardApi(a.url).closeTicket(a.token, widget.id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('关闭失败:$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.subject, overflow: TextOverflow.ellipsis),
        actions: [
          if (!_closed && !_loading && _error == null)
            IconButton(
              tooltip: '关闭工单',
              onPressed: _close,
              icon: const Icon(Icons.check_circle_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _thread()),
          if (!_loading && _error == null) _composer(),
        ],
      ),
    );
  }

  Widget _thread() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _CenterMsg.error(_error!, onRetry: _load);
    if (_messages.isEmpty) return _CenterMsg.empty('暂无对话');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _messages.length,
        itemBuilder: (_, i) => _bubble(_messages[i]),
      ),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final theme = Theme.of(context);
    final isMe = m['is_me'] == true || m['is_me'] == 1;
    final text = m['message']?.toString() ?? '';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.74),
        decoration: BoxDecoration(
          color: isMe
              ? _kIndigo
              : theme.colorScheme.surfaceContainerHighest.withOpacity(0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(isMe ? '我' : '客服',
                style: TextStyle(
                    fontSize: 11,
                    color: isMe ? Colors.white70 : theme.hintColor)),
            const SizedBox(height: 3),
            Text(text,
                style: TextStyle(
                    fontSize: 14,
                    color: isMe ? Colors.white : theme.colorScheme.onSurface)),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    if (_closed) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Text('工单已关闭',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).hintColor)),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '输入回复…',
                  filled: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: _kIndigo),
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================ 新建工单表单 ============================

class _NewTicketSheet extends ConsumerStatefulWidget {
  const _NewTicketSheet();

  @override
  ConsumerState<_NewTicketSheet> createState() => _NewTicketSheetState();
}

class _NewTicketSheetState extends ConsumerState<_NewTicketSheet> {
  final _subject = TextEditingController();
  final _message = TextEditingController();
  int _level = 1; // 0 普通 / 1 重要 / 2 紧急
  bool _submitting = false;

  @override
  void dispose() {
    _subject.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subject.text.trim();
    final message = _message.text.trim();
    if (subject.isEmpty || message.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写主题和内容')));
      return;
    }
    final auth = ref.read(xboardAuthProvider);
    final token = auth.authData;
    if (token == null) return;
    setState(() => _submitting = true);
    try {
      await XboardApi(auth.panelUrl).createTicket(token,
          subject: subject, message: message, level: _level);
      if (mounted) Navigator.pop(context, true);
    } on XboardApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('提交失败:$e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('新建工单',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(
            controller: _subject,
            decoration: const InputDecoration(
                labelText: '主题', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('优先级', style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(width: 12),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('普通')),
                  ButtonSegment(value: 1, label: Text('重要')),
                  ButtonSegment(value: 2, label: Text('紧急')),
                ],
                selected: {_level},
                onSelectionChanged: (s) => setState(() => _level = s.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _message,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
                labelText: '问题描述', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: _kIndigo,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('提交'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================ 复用的居中提示 ============================

class _CenterMsg {
  static Widget error(String msg, {required VoidCallback onRetry}) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
              const SizedBox(height: 12),
              Text(msg, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );

  static Widget empty(String msg) => Builder(
        builder: (context) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined,
                    size: 40, color: Theme.of(context).hintColor),
                const SizedBox(height: 12),
                Text(msg,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ],
            ),
          ),
        ),
      );
}
