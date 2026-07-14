// 游客客服聊天页(免登录)。用本地随机 guest_id 收发,近实时轮询。走 Reseller 公开接口。
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'xboard_auth.dart'; // kDefaultPanelUrl

const Color _kIndigo = Color(0xFF2B2F77);

class GuestChatPage extends StatefulWidget {
  const GuestChatPage({super.key});

  @override
  State<GuestChatPage> createState() => _GuestChatPageState();
}

class _GuestChatPageState extends State<GuestChatPage> {
  static const _storage = FlutterSecureStorage();
  static const _kGuestId = 'xboard_guest_id';

  String? _guestId;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  List<Map<String, dynamic>> _messages = const [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;

  String get _base => kDefaultPanelUrl.replaceAll(RegExp(r'/+$'), '');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var id = await _storage.read(key: _kGuestId);
    if (id == null || id.isEmpty) {
      id = _genGuestId();
      await _storage.write(key: _kGuestId, value: id);
    }
    _guestId = id;
    await _load(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  String _genGuestId() {
    final r = Random.secure();
    const chars = '0123456789abcdef';
    return 'g${List.generate(24, (_) => chars[r.nextInt(16)]).join()}';
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    if (_guestId == null) return;
    try {
      final uri = Uri.parse('$_base/api/v1/reseller/guest/fetch')
          .replace(queryParameters: {'guest_id': _guestId!});
      final resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      final data = body is Map ? body['data'] : null;
      final msgs = data is Map ? data['messages'] : null;
      final next = msgs is List
          ? msgs.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      final changed = next.length != _messages.length;
      setState(() {
        _messages = next;
        _loading = false;
        _error = null;
      });
      if (initial || changed) _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      if (initial) {
        setState(() {
          _loading = false;
          _error = '连接客服失败,请检查网络后重试';
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _guestId == null) return;
    setState(() => _sending = true);
    try {
      final resp = await http
          .post(
            Uri.parse('$_base/api/v1/reseller/guest/send'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'guest_id': _guestId, 'message': text}),
          )
          .timeout(const Duration(seconds: 15));
      dynamic body;
      try {
        body = jsonDecode(utf8.decode(resp.bodyBytes));
      } catch (_) {}
      if (resp.statusCode >= 400 ||
          (body is Map && body['status'] == 'fail')) {
        throw (body is Map ? body['message'] : null) ?? '发送失败';
      }
      _input.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发送失败:$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('联系客服')),
      body: Column(
        children: [
          Expanded(child: _thread()),
          _composer(),
        ],
      ),
    );
  }

  Widget _thread() {
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
              FilledButton(
                  onPressed: () => _load(initial: true),
                  child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text('发个消息,客服会尽快回复你 👋',
            style: TextStyle(color: Theme.of(context).hintColor)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i]),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final theme = Theme.of(context);
    final isStaff = m['is_staff'] == true;
    final text = m['message']?.toString() ?? '';
    return Align(
      alignment: isStaff ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.74),
        decoration: BoxDecoration(
          color: isStaff
              ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.6)
              : _kIndigo,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isStaff ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Text(isStaff ? '客服' : '我',
                style: TextStyle(
                    fontSize: 11,
                    color: isStaff ? theme.hintColor : Colors.white70)),
            const SizedBox(height: 3),
            Text(text,
                style: TextStyle(
                    fontSize: 14,
                    color: isStaff ? theme.colorScheme.onSurface : Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _composer() {
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
                  hintText: '输入消息…',
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
