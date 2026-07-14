// 图片上传 + 消息渲染(工单页 / 游客页共用)。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 上传图片,返回完整可访问 URL(面板域名 + /dl/tickets/xxx.jpg)。
Future<String> xboardUploadImage({
  required String panelBase,
  required String endpoint,
  required String filePath,
  String? authData,
}) async {
  final base = panelBase.replaceAll(RegExp(r'/+$'), '');
  final req = http.MultipartRequest('POST', Uri.parse('$base$endpoint'));
  req.headers['Accept'] = 'application/json';
  if (authData != null) req.headers['Authorization'] = authData;
  req.files.add(await http.MultipartFile.fromPath('file', filePath));
  final streamed = await req.send().timeout(const Duration(seconds: 60));
  final resp = await http.Response.fromStream(streamed);
  dynamic body;
  try {
    body = jsonDecode(utf8.decode(resp.bodyBytes));
  } catch (_) {}
  if (resp.statusCode >= 400 || (body is Map && body['status'] == 'fail')) {
    throw (body is Map ? body['message'] : null)?.toString() ??
        '上传失败(${resp.statusCode})';
  }
  final path = (body is Map && body['data'] is Map) ? body['data']['path'] : null;
  if (path == null) throw '上传返回异常';
  return '$base$path';
}

/// 聊天气泡内容:以 [img]<url> 开头则渲染成图片(限 http/https),否则普通文字。
Widget xboardMessageContent(String text, {required Color textColor}) {
  const p = '[img]';
  if (text.startsWith(p)) {
    final url = text.substring(p.length);
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 220),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Text('[图片加载失败]', style: TextStyle(color: textColor)),
          ),
        ),
      );
    }
  }
  return Text(text, style: TextStyle(fontSize: 14, color: textColor));
}
