import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:coriander_player/utils.dart';

class WebDavFile {
  final String path;
  final String name;
  final bool isDirectory;
  final int size;
  final DateTime lastModified;
  final String? contentType;

  const WebDavFile({
    required this.path,
    required this.name,
    required this.isDirectory,
    required this.size,
    required this.lastModified,
    this.contentType,
  });

  bool get isAudioFile {
    final audioExtensions = {
      '.mp3', '.flac', '.wav', '.aac', '.m4a', '.ogg', '.opus', '.ape', '.wma'
    };
    final ext = p.extension(name).toLowerCase();
    return !isDirectory && audioExtensions.contains(ext);
  }
}

class WebDavService {
  final String serverUrl;
  final String username;
  final String password;

  const WebDavService({
    required this.serverUrl,
    required this.username,
    required this.password,
  });

  String get serverUrlPathPrefix {
    final uri = Uri.parse(serverUrl);
    return uri.path.replaceAll(RegExp(r'/+$'), '');
  }

  String get _authHeader {
    final credentials = base64.encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  Future<bool> testConnection() async {
    try {
      LOGGER.d('[WebDAV] 测试连接: $serverUrl');
      final response = await http.head(
        Uri.parse(serverUrl),
        headers: {'Authorization': _authHeader},
      );
      LOGGER.d('[WebDAV] 连接状态: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      LOGGER.e('[WebDAV] 连接测试失败: $e');
      return false;
    }
  }

  Future<List<WebDavFile>> listFiles(String directoryPath) async {
    try {
      String cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), '');
      String pathUrl = directoryPath.isEmpty
          ? cleanUrl
          : '$cleanUrl/${directoryPath.replaceFirst(RegExp(r'^/+'), '')}';

      LOGGER.d('[WebDAV] 列出文件: $pathUrl');
      final request = http.Request(
        'PROPFIND',
        Uri.parse(pathUrl),
      );
      request.headers.addAll({
        'Authorization': _authHeader,
        'Depth': '1',
      });
      request.body = '''<?xml version="1.0" encoding="utf-8" ?>
        <propfind xmlns="DAV:">
          <prop>
            <displayname/>
            <getcontentlength/>
            <getcontenttype/>
            <getlastmodified/>
            <resourcetype/>
          </prop>
        </propfind>''';

      final response = await http.Response.fromStream(await request.send());

      LOGGER.d('[WebDAV] 响应状态: ${response.statusCode}');

      if (response.statusCode != 207) {
        LOGGER.e('[WebDAV] 列出文件失败: ${response.statusCode}');
        throw Exception('Failed to list files: ${response.statusCode}');
      }

      final files = _parseWebDavResponse(response.body, directoryPath);
      LOGGER.d('[WebDAV] 解析到 ${files.length} 个文件/目录');

      return files;
    } catch (e) {
      LOGGER.e('[WebDAV] 列出文件错误: $e');
      throw Exception('Failed to connect to WebDAV: $e');
    }
  }

  List<WebDavFile> _parseWebDavResponse(String xmlResponse, String basePath) {
    final files = <WebDavFile>[];

    final responseRegex = RegExp(
      r'<D:response[^>]*>(.*?)<\/D:response>',
      caseSensitive: false,
      dotAll: true,
    );

    final hrefRegex = RegExp(
      r'<D:href[^>]*>(.*?)<\/D:href>',
      caseSensitive: false,
    );

    final displayNameRegex = RegExp(
      r'<D:displayname[^>]*>(.*?)<\/D:displayname>',
      caseSensitive: false,
    );

    final contentLengthRegex = RegExp(
      r'<D:getcontentlength[^>]*>(\d+)<\/D:getcontentlength>',
      caseSensitive: false,
    );

    final lastModifiedRegex = RegExp(
      r'<D:getlastmodified[^>]*>(.*?)<\/D:getlastmodified>',
      caseSensitive: false,
    );

    final collectionRegex = RegExp(
      r'<D:collection|<D:resourcetype>\s*<D:collection',
      caseSensitive: false,
      dotAll: true,
    );

    final responses = responseRegex.allMatches(xmlResponse);

    for (final responseMatch in responses) {
      final responseContent = responseMatch.group(1) ?? '';

      final hrefMatch = hrefRegex.firstMatch(responseContent);
      final displayNameMatch = displayNameRegex.firstMatch(responseContent);
      final contentLengthMatch = contentLengthRegex.firstMatch(responseContent);
      final lastModifiedMatch = lastModifiedRegex.firstMatch(responseContent);
      final isCollection = collectionRegex.hasMatch(responseContent);

      if (hrefMatch != null) {
        String href = hrefMatch.group(1) ?? '';
        String name = displayNameMatch?.group(1) ?? '';

        if (name.isEmpty) {
          name = href.split('/').last;
          if (name.isEmpty && href.endsWith('/')) {
            name = href.split('/')[href.split('/').length - 2];
          }
        }

        try {
          href = Uri.decodeFull(href);
        } catch (e) {
          LOGGER.w('[WebDAV] URL解码失败: $href');
        }

        // XML 中的 HTML 实体解码（如 &amp; → &）
        href = href
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'");

        // displayname 也可能包含 HTML 实体
        name = name
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'");

        String cleanPath = href;

        if (cleanPath.startsWith(serverUrl)) {
          cleanPath = cleanPath.substring(serverUrl.length);
        }

        if (cleanPath.startsWith('/dav')) {
          cleanPath = cleanPath.substring(4);
        }

        cleanPath = cleanPath.replaceFirst(RegExp(r'^/+'), '');

        if (isCollection) {
          cleanPath = cleanPath.replaceFirst(RegExp(r'\/$'), '');
        }

        if (name.isEmpty || name.startsWith('.')) {
          continue;
        }

        if (basePath.isNotEmpty && cleanPath == basePath) {
          continue;
        }

        if (basePath.isNotEmpty &&
            (href.endsWith('/${Uri.encodeComponent(basePath)}') || href == '/dav/$basePath')) {
          continue;
        }

        if ((href == '/dav/' || href == '/dav')) {
          continue;
        }

        final sizeStr = contentLengthMatch?.group(1) ?? '0';
        final lastModified = lastModifiedMatch?.group(1) ?? '';

        DateTime modifiedDate;
        try {
          modifiedDate = lastModified.isNotEmpty
              ? DateTime.parse(lastModified) : DateTime.now();
        } catch (e) {
          modifiedDate = DateTime.now();
        }

        files.add(WebDavFile(
          path: cleanPath,
          name: name,
          isDirectory: isCollection,
          size: int.tryParse(sizeStr) ?? 0,
          lastModified: modifiedDate,
          contentType: isCollection ? null : _getContentType(name),
        ));
      }
    }

    return files;
  }

  String? _getContentType(String filename) {
    final extension = p.extension(filename).toLowerCase();
    const contentTypes = {
      '.mp3': 'audio/mpeg',
      '.flac': 'audio/flac',
      '.wav': 'audio/wav',
      '.aac': 'audio/aac',
      '.m4a': 'audio/mp4',
      '.ogg': 'audio/ogg',
      '.opus': 'audio/opus',
    };
    return contentTypes[extension];
  }

  Future<List<int>> downloadFile(String filePath) async {
    final response = await http.get(
      Uri.parse(getFileUrl(filePath)),
      headers: {'Authorization': _authHeader},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to download file: ${response.statusCode}');
    }

    return response.bodyBytes;
  }

  /// 通过 HTTP Range 请求下载文件的指定字节范围。
  /// [start] 起始字节偏移（包含），[end] 结束字节偏移（包含）。
  /// 返回 null 表示服务器不支持 Range 请求。
  Future<Uint8List?> downloadRange(String filePath, int start, int end) async {
    try {
      final url = getFileUrl(filePath);
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': _authHeader,
          'Range': 'bytes=$start-$end',
        },
      );

      if (response.statusCode == 206) {
        return response.bodyBytes;
      } else if (response.statusCode == 200) {
        // 服务器不支持 Range，返回完整文件中截取需要的部分
        final bytes = response.bodyBytes;
        if (start < bytes.length) {
          return bytes.sublist(start, (end + 1).clamp(0, bytes.length));
        }
        return null;
      }
      LOGGER.w('[WebDAV] downloadRange failed: ${response.statusCode}');
      return null;
    } catch (e) {
      LOGGER.e('[WebDAV] downloadRange error: $e');
      return null;
    }
  }

  /// 获取文件大小（通过 HEAD 请求）。
  /// 返回 null 表示无法获取。
  Future<int?> getFileSize(String filePath) async {
    try {
      final url = getFileUrl(filePath);
      final response = await http.head(
        Uri.parse(url),
        headers: {'Authorization': _authHeader},
      );
      if (response.statusCode == 200) {
        final contentLength = response.headers['content-length'];
        if (contentLength != null) {
          return int.tryParse(contentLength);
        }
      }
      return null;
    } catch (e) {
      LOGGER.e('[WebDAV] getFileSize error: $e');
      return null;
    }
  }

  String getFileUrl(String filePath) {
    final uri = Uri.parse(serverUrl);
    final segments = [
      ...uri.pathSegments,
      ...filePath.split('/').where((s) => s.isNotEmpty),
    ];
    return uri.replace(pathSegments: segments).toString();
  }

  Future<String> getStreamingUrl(String filePath) async {
    try {
      final url = getFileUrl(filePath);
      final client = HttpClient();
      client.autoUncompress = false;
      client.findProxy = HttpClient.findProxyFromEnvironment;
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = false;
      request.headers.set('Authorization', _authHeader);
      request.headers.set('Range', 'bytes=0-0');
      final response = await request.close();
      final statusCode = response.statusCode;
      final location = response.headers.value('location');
      await response.drain<void>();
      client.close();

      if ((statusCode == 302 || statusCode == 301) &&
          location != null &&
          location.isNotEmpty) {
        LOGGER.i('[WebDAV] redirect to CDN: $location');
        return location;
      }
      LOGGER.i('[WebDAV] no redirect, status=$statusCode, using original url');
      return url;
    } catch (e) {
      LOGGER.e('[WebDAV] getStreamingUrl failed: $e');
      return getFileUrl(filePath);
    }
  }

  Future<Map<String, String>> getAuthHeadersForStreaming(String filePath) async {
    return {'Authorization': _authHeader};
  }

  Map<String, String> getAuthHeaders() {
    return {'Authorization': _authHeader};
  }

  Future<List<WebDavFile>> scanAudioFiles(String directoryPath) async {
    final result = <WebDavFile>[];
    await _scanAudioFilesRecursive(directoryPath, result);
    return result;
  }

  Future<void> _scanAudioFilesRecursive(String directoryPath, List<WebDavFile> result) async {
    final files = await listFiles(directoryPath);
    for (final file in files) {
      if (file.isAudioFile) {
        result.add(file);
      } else if (file.isDirectory) {
        try {
          await _scanAudioFilesRecursive(file.path, result);
        } catch (e) {
          LOGGER.w('[WebDAV] 递归扫描子文件夹失败: ${file.path} - $e');
        }
      }
    }
  }
}
