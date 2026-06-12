// 云服务扫描元数据端到端测试
// 步骤1: 从 WebDAV 下载 head/tail 字节并保存到临时文件
// 步骤2: Rust 端读取这些字节并验证元数据提取
// 运行: dart test/test_webdav_scan_e2e.dart
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

  final testDir = Directory('/tmp/coriander_webdav_test');
  if (!testDir.existsSync()) {
    testDir.createSync(recursive: true);
  }

  print('========================================');
  print('云服务扫描元数据端到端测试');
  print('========================================');
  print('[E2E] 目标文件: $filePath');

  final url = getFileUrl(filePath);
  print('[E2E] URL: $url');

  // ========== Step 1: 获取文件大小 ==========
  print('\n--- Step 1: 获取文件大小 ---');
  int? fileSize;

  // 方法A: HEAD 请求
  try {
    final headResp = await http.head(
      Uri.parse(url),
      headers: {'Authorization': getAuthHeader()},
    );
    print('[E2E] HEAD 状态码: ${headResp.statusCode}');
    if (headResp.statusCode == 200) {
      final cl = headResp.headers['content-length'];
      print('[E2E] HEAD content-length: $cl');
      fileSize = cl != null ? int.tryParse(cl) : null;
    }
    // 打印所有响应头
    print('[E2E] HEAD 响应头:');
    headResp.headers.forEach((k, v) => print('[E2E]   $k: $v'));
  } catch (e) {
    print('[E2E] HEAD 请求失败: $e');
  }

  // 方法B: PROPFIND 请求
  if (fileSize == null) {
    print('[E2E] HEAD 未获取到文件大小，尝试 PROPFIND...');
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
      print('[E2E] PROPFIND 状态码: ${response.statusCode}');
      final contentLengthRegex = RegExp(
          r'<D:getcontentlength[^>]*>(\d+)<\/D:getcontentlength>',
          caseSensitive: false);
      final match = contentLengthRegex.firstMatch(response.body);
      if (match != null) {
        fileSize = int.tryParse(match.group(1)!);
        print('[E2E] PROPFIND 文件大小: $fileSize bytes');
      }
    } catch (e) {
      print('[E2E] PROPFIND 失败: $e');
    }
  }

  if (fileSize == null || fileSize < 128) {
    print('[E2E] FAIL: 无法获取文件大小，测试终止');
    exit(1);
  }
  print('[E2E] 文件大小: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB)');

  // ========== Step 2: 下载头部 64KB ==========
  print('\n--- Step 2: 下载头部 64KB ---');
  final headSize = (64 * 1024).clamp(0, fileSize);
  Uint8List? headBytes;

  try {
    final headResponse = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': getAuthHeader(),
        'Range': 'bytes=0-${headSize - 1}',
      },
    );
    print('[E2E] HEAD Range 状态码: ${headResponse.statusCode}');
    print('[E2E] HEAD Range body 长度: ${headResponse.bodyBytes.length}');
    print('[E2E] HEAD Range content-range: ${headResponse.headers['content-range']}');

    if (headResponse.statusCode == 206) {
      headBytes = headResponse.bodyBytes;
      print('[E2E] SUCCESS: 获取到头部 ${headBytes.length} 字节');
    } else if (headResponse.statusCode == 200) {
      // 服务器不支持 Range，截取头部
      headBytes = headResponse.bodyBytes.sublist(0, headSize);
      print('[E2E] WARNING: 服务器返回 200，截取头部 ${headBytes.length} 字节');
    } else if (headResponse.statusCode == 302 || headResponse.statusCode == 301) {
      // 重定向处理
      final location = headResponse.headers['location'];
      print('[E2E] 重定向到: $location');
      if (location != null) {
        final redirectResponse = await http.get(
          Uri.parse(location),
          headers: {'Range': 'bytes=0-${headSize - 1}'},
        );
        print('[E2E] CDN 响应状态码: ${redirectResponse.statusCode}');
        if (redirectResponse.statusCode == 206 || redirectResponse.statusCode == 200) {
          headBytes = redirectResponse.bodyBytes;
          print('[E2E] SUCCESS: 从 CDN 获取到头部 ${headBytes.length} 字节');
        }
      }
    }
  } catch (e) {
    print('[E2E] HEAD Range 请求失败: $e');
  }

  if (headBytes == null) {
    print('[E2E] FAIL: 无法获取头部字节，测试终止');
    exit(1);
  }

  // 验证 FLAC magic
  if (headBytes.length >= 4) {
    final magic = String.fromCharCodes(headBytes.sublist(0, 4));
    print('[E2E] 文件头 magic: $magic ${magic == 'fLaC' ? '✓ (FLAC)' : '✗ (非FLAC)'}');
  }

  // 保存头部字节
  final headFile = File('${testDir.path}/webdav_head.bin');
  await headFile.writeAsBytes(headBytes);
  print('[E2E] 头部字节已保存到: ${headFile.path}');

  // ========== Step 3: 下载尾部 128KB ==========
  print('\n--- Step 3: 下载尾部 128KB ---');
  final tailSize = (128 * 1024).clamp(0, fileSize);
  final tailStart = fileSize - tailSize;
  Uint8List? tailBytes;

  try {
    final tailResponse = await http.get(
      Uri.parse(url),
      headers: {
        'Authorization': getAuthHeader(),
        'Range': 'bytes=$tailStart-${fileSize - 1}',
      },
    );
    print('[E2E] TAIL Range 状态码: ${tailResponse.statusCode}');
    print('[E2E] TAIL Range body 长度: ${tailResponse.bodyBytes.length}');

    if (tailResponse.statusCode == 206) {
      tailBytes = tailResponse.bodyBytes;
      print('[E2E] SUCCESS: 获取到尾部 ${tailBytes.length} 字节');
    } else if (tailResponse.statusCode == 200) {
      tailBytes = tailResponse.bodyBytes.sublist(tailStart);
      print('[E2E] WARNING: 服务器返回 200，截取尾部 ${tailBytes.length} 字节');
    } else if (tailResponse.statusCode == 302 || tailResponse.statusCode == 301) {
      final location = tailResponse.headers['location'];
      if (location != null) {
        final redirectResponse = await http.get(
          Uri.parse(location),
          headers: {'Range': 'bytes=$tailStart-${fileSize - 1}'},
        );
        if (redirectResponse.statusCode == 206 || redirectResponse.statusCode == 200) {
          tailBytes = redirectResponse.bodyBytes;
          print('[E2E] SUCCESS: 从 CDN 获取到尾部 ${tailBytes.length} 字节');
        }
      }
    }
  } catch (e) {
    print('[E2E] TAIL Range 请求失败: $e');
  }

  if (tailBytes == null) {
    print('[E2E] FAIL: 无法获取尾部字节，测试终止');
    exit(1);
  }

  // 保存尾部字节
  final tailFile = File('${testDir.path}/webdav_tail.bin');
  await tailFile.writeAsBytes(tailBytes);
  print('[E2E] 尾部字节已保存到: ${tailFile.path}');

  // ========== Step 4: 分析 FLAC 元数据块结构 ==========
  print('\n--- Step 4: 分析 FLAC 元数据块结构 ---');
  if (headBytes.length >= 4 && String.fromCharCodes(headBytes.sublist(0, 4)) == 'fLaC') {
    int offset = 4;
    int blockCount = 0;
    while (offset + 4 <= headBytes.length) {
      final isLast = (headBytes[offset] & 0x80) != 0;
      final blockType = headBytes[offset] & 0x7F;
      final blockSize = ((headBytes[offset + 1] as int) << 16) |
          ((headBytes[offset + 2] as int) << 8) |
          (headBytes[offset + 3] as int);
      final blockEnd = offset + 4 + blockSize;

      final typeNames = {
        0: 'STREAMINFO',
        1: 'PADDING',
        2: 'APPLICATION',
        3: 'SEEKTABLE',
        4: 'VORBIS_COMMENT',
        5: 'CUESHEET',
        6: 'PICTURE',
      };
      final typeName = typeNames[blockType] ?? 'UNKNOWN($blockType)';
      final isComplete = blockEnd <= headBytes.length;

      print('[E2E] Block #$blockCount: type=$typeName, size=$blockSize, '
          'offset=$offset, is_last=$isLast, complete=$isComplete');

      // 如果是 VORBIS_COMMENT 块，尝试解析内容
      if (blockType == 4 && isComplete) {
        print('[E2E]   >>> VORBIS_COMMENT 块完整！包含 genre/year 等标签信息');
        // 解析 Vorbis Comment
        try {
          final vcData = headBytes.sublist(offset + 4, blockEnd);
          // Vendor string
          final vendorLen = _readLE32(vcData, 0);
          final vendorStr = utf8.decode(vcData.sublist(4, 4 + vendorLen), allowMalformed: true);
          print('[E2E]   Vendor: $vendorStr');

          // Comment count
          final commentCount = _readLE32(vcData, 4 + vendorLen);
          print('[E2E]   Comment count: $commentCount');

          var pos = 8 + vendorLen;
          for (int i = 0; i < commentCount && pos + 4 <= vcData.length; i++) {
            final commentLen = _readLE32(vcData, pos);
            if (pos + 4 + commentLen > vcData.length) break;
            final comment = utf8.decode(
              vcData.sublist(pos + 4, pos + 4 + commentLen),
              allowMalformed: true,
            );
            final lowerComment = comment.toLowerCase();
            if (lowerComment.startsWith('genre=') ||
                lowerComment.startsWith('date=') ||
                lowerComment.startsWith('title=') ||
                lowerComment.startsWith('artist=') ||
                lowerComment.startsWith('album=') ||
                lowerComment.startsWith('tracknumber=')) {
              print('[E2E]   Comment[$i]: $comment');
            }
            pos += 4 + commentLen;
          }
        } catch (e) {
          print('[E2E]   解析 Vorbis Comment 失败: $e');
        }
      }

      if (isLast || !isComplete) break;
      offset = blockEnd;
      blockCount++;
    }
  }

  // ========== Step 5: 保存元数据信息文件 ==========
  print('\n--- Step 5: 保存测试信息 ---');
  final infoFile = File('${testDir.path}/test_info.json');
  await infoFile.writeAsString(json.encode({
    'file_path': filePath,
    'file_size': fileSize,
    'head_size': headBytes.length,
    'tail_size': tailBytes.length,
    'tail_start': tailStart,
    'head_file': headFile.path,
    'tail_file': tailFile.path,
    'timestamp': DateTime.now().toIso8601String(),
  }));
  print('[E2E] 测试信息已保存到: ${infoFile.path}');

  // ========== Step 6: 与本地文件对比（如果存在）==========
  print('\n--- Step 6: 与本地文件对比 ---');
  const localFilePath = '/tmp/coriander_test/02. 最伟大的作品.flac';
  final localFile = File(localFilePath);
  if (localFile.existsSync()) {
    final localSize = localFile.lengthSync();
    print('[E2E] 本地文件大小: $localSize bytes');
    print('[E2E] WebDAV 文件大小: $fileSize bytes');
    print('[E2E] 大小匹配: ${localSize == fileSize ? '✓' : '✗'}');

    // 对比头部字节
    final localHead = localFile.openSync();
    final localHeadBytes = Uint8List(headSize);
    localHead.readIntoSync(localHeadBytes, 0, headSize);
    localHead.closeSync();

    bool headMatch = true;
    int firstDiff = -1;
    for (int i = 0; i < headBytes.length && i < localHeadBytes.length; i++) {
      if (headBytes[i] != localHeadBytes[i]) {
        headMatch = false;
        firstDiff = i;
        break;
      }
    }
    print('[E2E] 头部字节匹配: ${headMatch ? '✓' : '✗ (第一个差异在偏移 $firstDiff)'}');
  } else {
    print('[E2E] 本地文件不存在: $localFilePath');
    print('[E2E] 跳过对比');
  }

  // ========== Step 7: 模拟 _createAudioViaRange 流程 ==========
  print('\n--- Step 7: 模拟 _createAudioViaRange 流程 ---');
  print('[E2E] 这一步需要 Rust FFI，无法在纯 Dart 脚本中执行');
  print('[E2E] 请运行 Rust 测试来验证元数据提取:');
  print('[E2E]   cd rust && cargo test test_read_metadata_from_webdav_saved_bytes -- --nocapture');

  print('\n========================================');
  print('Dart 端测试完成');
  print('========================================');
  print('[E2E] 保存的文件:');
  print('[E2E]   头部字节: ${headFile.path} (${headBytes.length} bytes)');
  print('[E2E]   尾部字节: ${tailFile.path} (${tailBytes.length} bytes)');
  print('[E2E]   测试信息: ${infoFile.path}');
  print('');
  print('[E2E] 下一步: 运行 Rust 测试验证元数据提取');
}

int _readLE32(Uint8List data, int offset) {
  return (data[offset] as int) |
      ((data[offset + 1] as int) << 8) |
      ((data[offset + 2] as int) << 16) |
      ((data[offset + 3] as int) << 24);
}
