// 通用网页页。
//   openWeb()      = 全平台【App 内】打开(充值/订单/工单用):手机 webview_flutter,桌面 flutter_inappwebview。
//   openExternal() = 系统浏览器打开(官网用)。
//
// 依赖(pubspec 的 dependencies):
//   webview_flutter: ^4.7.0          (手机内嵌;之前已加)
//   flutter_inappwebview: ^6.1.5     (桌面内嵌;新加。若 pub get 报冲突,用它建议的版本号)
//   url_launcher                     (FlClash 已有)
//
// ⚠ 桌面内嵌需要系统 WebView 运行时:Windows=Edge WebView2(Win10/11 一般自带),macOS=WKWebView(系统自带)。

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

bool get _isMobile => Platform.isAndroid || Platform.isIOS;

/// 系统浏览器打开(官网用)。
Future<void> openExternal(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// App 内打开(充值/订单/工单用)——全平台都在应用内嵌网页,不跳外部浏览器。
Future<void> openWeb(
  BuildContext context, {
  required String url,
  required String title,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => WebPage(url: url, title: title)),
  );
}

class WebPage extends StatefulWidget {
  final String url;
  final String title;
  const WebPage({super.key, required this.url, required this.title});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  WebViewController? _mobileController; // 手机端 webview_flutter
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    if (_isMobile) {
      _mobileController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (p) => setState(() => _progress = p),
            onPageFinished: (_) => setState(() => _progress = 100),
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: (_isMobile && _progress < 100)
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
        actions: [
          IconButton(
            tooltip: '用系统浏览器打开',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => openExternal(widget.url),
          ),
        ],
      ),
      body: _isMobile
          ? WebViewWidget(controller: _mobileController!)
          : InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
            ),
    );
  }
}
