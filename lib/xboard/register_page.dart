// 注册页 —— App 内原生注册(邮箱+密码,选填邀请码/邮箱验证码)。
// 注册成功即自动登录,门控(XboardGate)会切到主界面,本页自动弹出。
// 邮箱验证码:仅当你面板开启「邮箱验证」时必填;没开就留空。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../common/common.dart';
import 'xboard_auth.dart';
import 'xboard_sync.dart';
import 'xboard_api.dart';

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
  final _emailCode = TextEditingController();
  final _companyWebsite = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _sendingCode = false;
  int _resendSeconds = 0;
  Timer? _resendTimer;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    _pass2.dispose();
    _invite.dispose();
    _emailCode.dispose();
    _companyWebsite.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendEmailCode() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = '请先输入有效邮箱');
      return;
    }
    setState(() => _error = null);
    try {
      final api = XboardApi(ttActiveBase);
      final captcha = await api.fetchRegistrationCaptcha();
      if (!mounted) return;
      final answer = await _showCaptchaDialog(api, captcha);
      if (answer == null || !mounted) return;
      setState(() => _sendingCode = true);
      await api.sendRegistrationEmailCode(
        email,
        captchaId: answer.$1,
        captchaAnswer: answer.$2,
      );
      if (!mounted) return;
      setState(() {
        _resendSeconds = 60;
        _sendingCode = false;
      });
      _resendTimer?.cancel();
      _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return timer.cancel();
        setState(() {
          _resendSeconds--;
          if (_resendSeconds <= 0) timer.cancel();
        });
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('验证码已发送，请查收邮箱')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _sendingCode = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<(String, String)?> _showCaptchaDialog(
    XboardApi api,
    RegistrationCaptcha initial,
  ) async {
    var challenge = initial;
    final answer = TextEditingController();
    final result = await showDialog<(String, String)>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('安全验证'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('验证成功后才会发送邮箱验证码。'),
              const SizedBox(height: 16),
              Text('请计算：${challenge.question}'),
              const SizedBox(height: 10),
              TextField(
                controller: answer,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 3,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: '计算结果',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                try {
                  final replacement = await api.fetchRegistrationCaptcha();
                  answer.clear();
                  setDialogState(() => challenge = replacement);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
              },
              child: const Text('换一个'),
            ),
            FilledButton(
              onPressed: () {
                final value = answer.text.trim();
                if (!RegExp(r'^\d{1,3}$').hasMatch(value)) return;
                Navigator.pop(dialogContext, (challenge.id, value));
              },
              child: const Text('验证并发送'),
            ),
          ],
        ),
      ),
    );
    answer.dispose();
    return result;
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
    final previousSubscription = ref.read(xboardAuthProvider).subscribeUrl;
    try {
      final outcome = await ref
          .read(xboardAuthProvider.notifier)
          .register(
            panelUrl: ttActiveBase,
            email: _email.text.trim(),
            password: _pass.text,
            inviteCode: _invite.text.trim(),
            emailCode: _emailCode.text.trim(),
            sliderToken: null,
            companyWebsite: _companyWebsite.text,
          );
      String? syncWarning = outcome.syncWarning;
      if (outcome.mihomoUrl != null) {
        try {
          await importXboardSubscription(outcome.mihomoUrl!);
        } catch (error) {
          syncWarning = context.appLocalizations.accountLoginImportFailed(error);
        }
      } else if (syncWarning == null) {
        try {
          await clearTianTiSubscriptionProfiles(
            subscribeUrl: previousSubscription,
          );
        } catch (error) {
          syncWarning = context.appLocalizations.accountLoginSyncFailed(error);
        }
      }
      if (syncWarning != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(syncWarning),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      // 注册即登录:弹掉本页,门控已切到主界面(新号无套餐会在「我的」页看到去充值提示)。
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _emailCode,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          maxLength: 6,
                          decoration: const InputDecoration(
                            counterText: '',
                            labelText: '邮箱验证码',
                            prefixIcon: Icon(Icons.mark_email_read_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => RegExp(r'^\d{6}$').hasMatch(v ?? '')
                              ? null
                              : '请输入 6 位验证码',
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 56,
                        child: OutlinedButton(
                          onPressed: _sendingCode || _resendSeconds > 0
                              ? null
                              : _sendEmailCode,
                          child: Text(
                            _sendingCode
                                ? '发送中…'
                                : (_resendSeconds > 0
                                      ? '${_resendSeconds}s'
                                      : '发送验证码'),
                          ),
                        ),
                      ),
                    ],
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
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
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
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _invite,
                    decoration: const InputDecoration(
                      labelText: '邀请码(选填)',
                      prefixIcon: Icon(Icons.card_giftcard_outlined),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Offstage(
                    offstage: true,
                    child: TextFormField(
                      controller: _companyWebsite,
                      autofillHints: null,
                      decoration: const InputDecoration(labelText: '公司网站'),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _register,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
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
