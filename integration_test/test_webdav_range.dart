// 测试 WebDAV Range 请求是否正常工作
// 运行: dart test/test_webdav_range.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

void main() async {
  const serverUrl = 'http://106.13.25.163:5244/dav';
  const username = 'musictest';
  const password = 'Lkh&@002';

  String getAuthHeader() {
    final credentials = base64.encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  String getFileUrl(String filePath) {
    final uri = Uri.parse(serverUrl);
    final segments = [
      ...uri.pathSegments,
      ...filePath.split('/').where((s) => s.isNotEmpty),
    ];
    return uri.replace(pathSegments: segments).toString();
  }

  const filePath =
      '歌单/周杰伦Hi-Res全集（2024年环球音乐官方新版）/[2022-07-15] 周杰伦《最伟大的作品》[Hi-Res／48kHz／24bit／FLAC]/02. 最伟大的作品.flac';

  final url = getFileUrl(filePath);
  print('[TEST] URL: $url');

  // 测试 1: HEAD 请求获取文件大小
  print('\n=== 测试 1: HEAD 请求 ===');
  try {
    final headResponse = await http.head(
      Uri.parse(url),
      headers: {'Authorization': getAuthHeader()},
    );
    print('[TEST] HEAD status: ${headResponse.statusCode}');
    print('[TEST] HEAD content-length: ${headResponse.headers['content-length']}');
    print('[TEST] HEAD headers: ${headResponse.headers}');
  } catch (e) {
    print('[TEST] HEAD error: $e');
  }

  // 测试 2: Range 请求获取头部字节
  print('\n=== 测试 2: Range 请求 (0-65535) ===');
  try {
    final rangeResponse = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': getAuthHeader(),
        'Range': 'bytes=0-65535',
      },
    );
    print('[TEST] Range status: ${rangeResponse.statusCode}');
    print('[TEST] Range body length: ${rangeResponse.bodyBytes.length}');
    print('[TEST] Range content-range: ${rangeResponse.headers['content-range']}');
    print('[TEST] Range content-length: ${rangeResponse.headers['content-length']}');

    if (rangeResponse.statusCode == 206) {
      print('[TEST] SUCCESS: 服务器支持 Range 请求');
      // 检查 FLAC magic
      final bytes = rangeResponse.bodyBytes;
      if (bytes.length >= 4) {
        final magic = String.fromCharCodes(bytes.sublist(0, 4));
        print('[TEST] First 4 bytes (magic): $magic');
        if (magic == 'fLaC') {
          print('[TEST] SUCCESS: FLAC magic 验证通过');
        }
      }
    } else if (rangeResponse.statusCode == 200) {
      print('[TEST] WARNING: 服务器返回 200 而不是 206，可能不支持 Range');
      print('[TEST] 下载了完整文件，大小: ${rangeResponse.bodyBytes.length}');
    } else {
      print('[TEST] FAIL: 意外的状态码 ${rangeResponse.statusCode}');
    }
  } catch (e) {
    print('[TEST] Range error: $e');
  }

  // 测试 3: 使用 HttpClient 手动处理重定向
  print('\n=== 测试 3: 手动处理重定向 ===');
  try {
    final client = HttpClient();
    client.autoUncompress = false;

    final request = await client.getUrl(Uri.parse(url));
    request.headers.set('Authorization', getAuthHeader());
    request.headers.set('Range', 'bytes=0-65535');
    request.followRedirects = false;

    final response = await request.close();
    print('[TEST] 初始响应状态码: ${response.statusCode}');
    print('[TEST] 初始响应头:');
    response.headers.forEach((name, values) {
      print('[TEST]   $name: $values');
    });

    if (response.statusCode == 302 || response.statusCode == 301) {
      final location = response.headers.value('location');
      print('[TEST] 重定向到: $location');
      await response.drain<void>();

      // 跟随重定向，不带 Authorization 但带 Range
      if (location != null) {
        final redirectRequest = await client.getUrl(Uri.parse(location));
        redirectRequest.headers.set('Range', 'bytes=0-65535');
        // CDN URL 已有签名，不需要 Authorization
        final redirectResponse = await redirectRequest.close();
        print('[TEST] CDN 响应状态码: ${redirectResponse.statusCode}');
        print('[TEST] CDN content-range: ${redirectResponse.headers.value('content-range')}');

        final bytes = await redirectResponse.fold<BytesBuilder>(
          BytesBuilder(),
          (b, d) => b..add(d),
        );
        print('[TEST] CDN 响应体大小: ${bytes.length}');
        if (redirectResponse.statusCode == 206) {
          print('[TEST] SUCCESS: CDN 支持 Range 请求');
        }
      }
    }

    client.close();
  } catch (e) {
    print('[TEST] 手动重定向 error: $e');
  }

  // 测试 4: 使用 PROPFIND 获取文件大小
  print('\n=== 测试 4: PROPFIND 获取文件大小 ===');
  try {
    final request = http.Request('PROPFIND', Uri.parse(url));
    request.headers.addAll({
      'Authorization': getAuthHeader(),
      'Depth': '0',
    });
    request.body = '''<?xml version="1.0" encoding="utf-8" ?>
      <propfind xmlns="DAV:">
        <prop>
          <getcontentlength/>
        </prop>
      </propfind>''';

    final response = await http.Response.fromStream(await request.send());
    print('[TEST] PROPFIND status: ${response.statusCode}');
    print('[TEST] PROPFIND body (first 500 chars): ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');

    // 解析 getcontentlength
    final contentLengthRegex = RegExp(r'<D:getcontentlength[^>]*>(\d+)<\/D:getcontentlength>', caseSensitive: false);
    final match = contentLengthRegex.firstMatch(response.body);
    if (match != null) {
      print('[TEST] 文件大小: ${match.group(1)} bytes');
    }
  } catch (e) {
    print('[TEST] PROPFIND error: $e');
  }

  print('\n=== 测试完成 ===');
}
