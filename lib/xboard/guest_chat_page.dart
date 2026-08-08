// 在线客服聊天页。登录用户使用当前账号身份，未登录用户使用游客身份；近实时轮询 TianTi Core。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'xboard_auth.dart'; // ttActiveBase(failover 后的生效通信地址)
import 'xboard_upload.dart';

const Color _kIndigo = Color(0xFF2B2F77);

class GuestChatPage extends ConsumerStatefulWidget {
  const GuestChatPage({super.key});

  @override
  ConsumerState<GuestChatPage> createState() => _GuestChatPageState();
}

class _GuestChatPageState extends ConsumerState<GuestChatPage> {
  static const _storage = FlutterSecureStorage();
  static const _kConversationId = 'tianti_support_conversation_id';
  static const _kSupportToken = 'tianti_support_token';
  static const _kSupportIdentity = 'tianti_support_identity';

  String? _conversationId;
  String? _supportToken;
  bool _loading = true;
  String? _error;
  bool _sending = false;
  List<Map<String, dynamic>> _messages = const [];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _poll;

  String get _base => ttActiveBase.replaceAll(RegExp(r'/+$'), '');

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final auth = ref.read(xboardAuthProvider);
    final currentIdentity = auth.loggedIn && auth.email.trim().isNotEmpty
        ? 'user:${auth.email.trim().toLowerCase()}'
        : 'guest';
    final storedIdentity = await _storage.read(key: _kSupportIdentity);
    _conversationId = await _storage.read(key: _kConversationId);
    _supportToken = await _storage.read(key: _kSupportToken);
    if (storedIdentity != currentIdentity) {
      await _clearSession();
    }
    if ((_conversationId ?? '').isEmpty || (_supportToken ?? '').isEmpty) {
      await _createSession();
    }
    await _storage.write(key: _kSupportIdentity, value: currentIdentity);
    await _load(initial: true);
    _poll = Timer.periodic(const Duration(seconds: 3), (_) => _load());
  }

  Future<void> _createSession() async {
    final auth = ref.read(xboardAuthProvider);
    final resp = await http
        .post(
          Uri.parse('$_base/api/v1/unified-admin/public/support/conversations'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            if ((auth.authData ?? '').isNotEmpty)
              'Authorization': auth.authData!,
          },
          body: jsonEncode({'display_name': '天梯客户端访客', 'subject': '客户端在线客服'}),
        )
        .timeout(const Duration(seconds: 15));
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    final data = body is Map ? body['data'] : null;
    final conversation = data is Map ? data['conversation'] : null;
    final id = conversation is Map ? conversation['id']?.toString() : null;
    final token = data is Map ? data['access_token']?.toString() : null;
    if (resp.statusCode >= 400 || id == null || token == null) {
      throw Exception(body is Map ? body['message'] ?? '客服会话创建失败' : '客服会话创建失败');
    }
    _conversationId = id;
    _supportToken = token;
    await _storage.write(key: _kConversationId, value: id);
    await _storage.write(key: _kSupportToken, value: token);
  }

  Future<void> _clearSession() async {
    _conversationId = null;
    _supportToken = null;
    await _storage.delete(key: _kConversationId);
    await _storage.delete(key: _kSupportToken);
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false, bool allowRecreate = true}) async {
    if (_conversationId == null || _supportToken == null) return;
    try {
      final uri = Uri.parse(
        '$_base/api/v1/unified-admin/public/support/conversations/${Uri.encodeComponent(_conversationId!)}/messages',
      );
      final resp = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'X-Support-Token': _supportToken!,
            },
          )
          .timeout(const Duration(seconds: 15));
      if ((resp.statusCode == 401 || resp.statusCode == 404) && allowRecreate) {
        await _clearSession();
        await _createSession();
        await _load(initial: initial, allowRecreate: false);
        return;
      }
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (resp.statusCode >= 400) {
        throw Exception(
          body is Map ? body['message'] ?? '客服会话读取失败' : '客服会话读取失败',
        );
      }
      final data = body is Map ? body['data'] : null;
      final next = data is List
          ? data.map((e) {
              final row = Map<String, dynamic>.from(e as Map);
              final path = row['attachment_url']?.toString() ?? '';
              return <String, dynamic>{
                ...row,
                'is_staff': row['sender_type'] == 'administrator',
                'message': row['type'] == 'image' && path.isNotEmpty
                    ? '[img]${path.startsWith('http') ? path : '$_base$path'}'
                    : row['body']?.toString() ?? '',
              };
            }).toList()
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
    if (text.isEmpty ||
        _sending ||
        _conversationId == null ||
        _supportToken == null) {
      return;
    }
    setState(() => _sending = true);
    try {
      final resp = await http
          .post(
            Uri.parse(
              '$_base/api/v1/unified-admin/public/support/conversations/${Uri.encodeComponent(_conversationId!)}/messages',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-Support-Token': _supportToken!,
            },
            body: jsonEncode({'message': text}),
          )
          .timeout(const Duration(seconds: 15));
      dynamic body;
      try {
        body = jsonDecode(utf8.decode(resp.bodyBytes));
      } catch (_) {}
      if (resp.statusCode >= 400 || (body is Map && body['status'] == 'fail')) {
        throw (body is Map ? body['message'] : null) ?? '发送失败';
      }
      _input.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发送失败:$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    if (_sending || _conversationId == null || _supportToken == null) return;
    final XFile? x = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (x == null) return;
    setState(() => _sending = true);
    try {
      await xboardUploadImage(
        panelBase: _base,
        endpoint:
            '/api/v1/unified-admin/public/support/conversations/${Uri.encodeComponent(_conversationId!)}/images',
        filePath: x.path,
        extraHeaders: {'X-Support-Token': _supportToken!},
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('发图失败:$e')));
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
              const Icon(
                Icons.error_outline,
                size: 40,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => _load(initial: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          '发个消息,客服会尽快回复你 👋',
          style: TextStyle(color: Theme.of(context).hintColor),
        ),
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
          maxWidth: MediaQuery.of(context).size.width * 0.74,
        ),
        decoration: BoxDecoration(
          color: isStaff
              ? theme.colorScheme.surfaceContainerHighest.withOpacity(0.6)
              : _kIndigo,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: isStaff
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.end,
          children: [
            Text(
              isStaff ? '客服' : '我',
              style: TextStyle(
                fontSize: 11,
                color: isStaff ? theme.hintColor : Colors.white70,
              ),
            ),
            const SizedBox(height: 3),
            xboardMessageContent(
              text,
              textColor: isStaff ? theme.colorScheme.onSurface : Colors.white,
              headers: {'X-Support-Token': _supportToken!},
            ),
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
            IconButton(
              tooltip: '发送图片',
              onPressed: _sending ? null : _pickAndSendImage,
              icon: const Icon(Icons.image_outlined),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: '输入消息…',
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
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
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
