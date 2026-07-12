// 通用网页页 —— 移动端内嵌 WebView(充值/客服弹窗),桌面端回退外部浏览器。
//
// 依赖:pubspec.yaml 的 dependencies 加 `webview_flutter: ^4.7.0`
//       (仅 Android/iOS 需要;桌面走 url_launcher,FlClash 已有)。
// Android 需 minSdk >= 19(FlClash 已是 26,OK)。

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 打开一个网页:Android/iOS 内嵌 WebView;桌面(Win/mac/Linux)用系统浏览器打开。
Future<void> openWeb(
  BuildContext context, {
  required String url,
  required String title,
}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => WebPage(url: url, title: title)),
    );
    // 若想用 FlClash 的转场:BaseNavigator.push(context, WebPage(url: url, title: title));
  } else {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

class WebPage extends StatefulWidget {
  final String url;
  final String title;
  const WebPage({super.key, required this.url, required this.title});

  @override
  State<WebPage> createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late final WebViewController _controller;
  int _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onPageFinished: (_) => setState(() => _progress = 100),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
        actions: [
          IconButton(
            tooltip: '外部浏览器打开',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () async {
              final uri = Uri.parse(widget.url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}
