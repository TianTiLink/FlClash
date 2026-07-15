// 登录页 —— 用主站账号密码登录,登录成功后自动拉取并激活订阅。
// 纯 Flutter Material + Riverpod,不依赖 FlClash 的私有组件(便于移植/换肤)。

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart'; // FlClash 已依赖;用于打开注册/充值页

import 'xboard_auth.dart';
import 'xboard_sync.dart';
import 'register_page.dart';
import 'guest_chat_page.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final st = ref.read(xboardAuthProvider);
    _emailCtrl.text = st.email;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final mihomoUrl = await ref.read(xboardAuthProvider.notifier).login(
            panelUrl: ttActiveBase,
            email: _emailCtrl.text.trim(),
            password: _passCtrl.text,
          );
      // mihomoUrl 为 null 代表账号密码正确、但还没有可用套餐/订阅——
      // 仍然放行进主界面(门控会自动切换),让用户在账户页看到「去充值」提示,
      // 而不是把一个已注册但还没付费的用户挡在登录页外面。
      if (mihomoUrl != null) {
        await importXboardSubscription(mihomoUrl);
      }
      // 登录态变化后,门控(XboardGate)会自动切到主界面,无需手动导航。
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPanel(String path) async {
    var base = ttActiveBase.replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse('$base$path');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
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
                  // 天梯品牌 Logo(资源放 assets/images/,pubspec 已声明该目录,自动打包)
                  Image.asset('assets/images/tt_logo.png',
                      width: 72, height: 72),
                  const SizedBox(height: 12),
                  Text('登录',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text('用主站账号登录,自动同步节点',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.hintColor)),
                  const SizedBox(height: 24),
                  // 面板地址已隐藏(写死在 kDefaultPanelUrl),用户只填邮箱密码。
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(
                      labelText: '邮箱',
                      prefixIcon: Icon(Icons.mail_outline),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入邮箱' : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onFieldSubmitted: (_) => _busy ? null : _login(),
                    decoration: InputDecoration(
                      labelText: '密码',
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
                        (v == null || v.isEmpty) ? '请输入密码' : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _login,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('登录'),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const RegisterPage()),
                        ),
                        child: const Text('注册账号'),
                      ),
                      TextButton(
                        onPressed: () => _openPanel('/#/forget'),
                        child: const Text('忘记密码'),
                      ),
                    ],
                  ),
                  const Divider(height: 28),
                  Center(
                    child: RichText(
                      text: TextSpan(
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                        children: [
                          const TextSpan(text: '还没套餐?'),
                          TextSpan(
                            text: '去充值 →',
                            style: TextStyle(color: theme.colorScheme.primary),
                            recognizer: TapGestureRecognizer()
                              ..onTap = () => _openPanel('/#/plan'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const GuestChatPage())),
                      icon: const Icon(Icons.support_agent, size: 18),
                      label: const Text('联系客服'),
                    ),
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
