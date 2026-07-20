// 注册页 —— App 内原生注册(邮箱+密码,选填邀请码/邮箱验证码)。
// 注册成功即自动登录,门控(XboardGate)会切到主界面,本页自动弹出。
// 邮箱验证码:仅当你面板开启「邮箱验证」时必填;没开就留空。

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'xboard_api.dart';
import 'xboard_auth.dart';
import 'xboard_sync.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _pass2 = TextEditingController();
  final _invite = TextEditingController();
  final _code = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _sending = false;
  int _cooldown = 0;
  Timer? _timer;
  String? _error;
  // 是否需要邮箱验证码框:null=还在读后台配置(先不显示,避免闪现),
  // true=后台开了邮箱验证→显示;false=后台关了→隐藏。
  bool? _needCode;

  @override
  void initState() {
    super.initState();
    // 读后台通用配置(is_email_verify),决定要不要显示验证码框,而不是写死永远显示。
    XboardApi(ttActiveBase).needEmailVerify().then((need) {
      if (mounted) setState(() => _needCode = need);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    _invite.dispose();
    _code.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = '请先填写正确的邮箱');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await XboardApi(ttActiveBase).sendEmailVerify(email);
      _startCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('验证码已发送,请查收邮箱')));
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startCooldown() {
    setState(() => _cooldown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (_pass.text != _pass2.text) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mihomoUrl = await ref.read(xboardAuthProvider.notifier).register(
            panelUrl: ttActiveBase,
            email: _email.text.trim(),
            password: _pass.text,
            inviteCode: _invite.text.trim(),
            emailCode: _code.text.trim(),
          );
      if (mihomoUrl != null) await importXboardSubscription(mihomoUrl);
      // 注册即登录:弹掉本页,门控已切到主界面(新号无套餐会在「我的」页看到去充值提示)。
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('注册账号')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.mail_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? '请输入邮箱'
                        : (!v.contains('@') ? '邮箱格式不正确' : null),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pass,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: '密码(至少 8 位)',
                      prefixIcon: const Icon(Icons.lock_outline),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.length < 8) ? '密码至少 8 位' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pass2,
                    obscureText: _obscure,
                    decoration: const InputDecoration(
                      labelText: '确认密码',
                      prefixIcon: Icon(Icons.lock_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? '请再次输入密码' : null,
                  ),
                  // 仅当后台开启「邮箱验证」时才显示验证码框(_needCode==true);
                  // 后台关闭、或配置还没读到时不显示,不再写死永远显示。
                  if (_needCode == true) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _code,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '邮箱验证码',
                              prefixIcon: Icon(Icons.verified_outlined),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 56,
                          child: OutlinedButton(
                            onPressed:
                                (_sending || _cooldown > 0) ? null : _sendCode,
                            child: Text(_cooldown > 0
                                ? '${_cooldown}s'
                                : (_sending ? '发送中' : '发送验证码')),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _invite,
                    decoration: const InputDecoration(
                      labelText: '邀请码(选填)',
                      prefixIcon: Icon(Icons.card_giftcard_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _register,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('注册并登录'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('已有账号?返回登录'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
