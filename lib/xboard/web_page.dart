// 只保留「用系统浏览器打开外部链接」(官网、支付收银台)。
import 'package:url_launcher/url_launcher.dart';

/// 用系统浏览器打开。返回是否成功。
/// ⚠ 修复支付「点了没反应」:不再用 canLaunchUrl 前置判断——安卓 11+ 没声明 <queries>
///   时 canLaunchUrl 对 https 返回 false,老代码于是啥也不干、也不报错(收银台不弹)。
///   launchUrl 直接走 startActivity,不受该限制,能正常打开浏览器。
Future<bool> openExternal(String url) async {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return false;
  }
  for (final mode in const [
    LaunchMode.externalApplication,
    LaunchMode.platformDefault,
  ]) {
    try {
      if (await launchUrl(uri, mode: mode)) return true;
    } catch (_) {}
  }
  return false;
}
