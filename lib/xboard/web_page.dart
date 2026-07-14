// 只保留「用系统浏览器打开外部链接」。
//
// 原来的内嵌 WebView(webview_flutter / flutter_inappwebview)已删除:
//   flutter_inappwebview 的 Windows 版是早期预览,会阻塞平台线程 → 点开卡死。
//   充值/订单/工单已改为原生页面(orders_page / tickets_page / plans_page)。
//   仅「官方网站」和「支付跳转(易支付收银台)」用系统浏览器打开——支付网关本就
//   拒绝内嵌 webview,必须外部浏览器。
//
// 依赖:url_launcher(FlClash 已自带)。pubspec 里 webview_flutter / flutter_inappwebview
//   都可以删掉了(全项目只有本文件用过它们)。

import 'package:url_launcher/url_launcher.dart';

/// 用系统浏览器打开(官网、支付收银台)。
Future<void> openExternal(String url) async {
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
