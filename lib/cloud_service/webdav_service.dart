import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:coriander_player/cloud_service/cloud_utils.dart';

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

  String get _authHeader {
    final credentials = base64.encode(utf8.encode('$username:$password'));
    debugPrint('Auth Header: Basic [${credentials.substring(0, 10)}...]');
    return 'Basic $credentials';
  }

  Future<bool> testConnection() async {
    try {
      debugPrint('Testing connection to: $serverUrl');
      debugPrint('Username: $username');
      debugPrint('Password: ${password.isEmpty ? "[EMPTY]" : "[PROVIDED]"}');
      
      final response = await http.head(
        Uri.parse(serverUrl),
        headers: {'Authorization': _authHeader},
      );
      debugPrint('Test connection status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Test connection error: $e');
      return false;
    }
  }

  Future<List<WebDavFile>> listFiles(String directoryPath) async {
    try {
      // 确保URL格式正确，避免双斜杠
      String cleanUrl = serverUrl.replaceAll(RegExp(r'/+$'), ''); // 移除末尾的斜杠
      String pathUrl = directoryPath.isEmpty 
          ? cleanUrl 
          : '$cleanUrl/${directoryPath.replaceFirst(RegExp(r'^/+'), '')}';
          
      debugPrint('Listing files from: $pathUrl');
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
      
      debugPrint('PROPFIND Request URL: $pathUrl');
      debugPrint('Request Headers: ${request.headers}');
      
      final response = await http.Response.fromStream(await request.send());

      debugPrint('Response Status: ${response.statusCode}');
      debugPrint('Response Body Length: ${response.body.length}');
      
      if (response.statusCode != 207) {
        debugPrint('Error Response Body: ${response.body}');
        throw Exception('Failed to list files: ${response.statusCode}');
      }

      final files = _parseWebDavResponse(response.body, directoryPath);
      debugPrint('Successfully parsed ${files.length} files/directories');
      
      return files;
    } catch (e) {
      debugPrint('WebDAV list files error: $e');
      throw Exception('Failed to connect to WebDAV: $e');
    }
  }

  List<WebDavFile> _parseWebDavResponse(String xmlResponse, String basePath) {
    final files = <WebDavFile>[];
    
    debugPrint('Raw XML Response (first 500 chars): ${xmlResponse.substring(0, xmlResponse.length < 500 ? xmlResponse.length : 500)}...');
    debugPrint('XML Response Length: ${xmlResponse.length}');
    debugPrint('Base path: $basePath');
    
    // 使用正则表达式提取所有response块
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
    debugPrint('Found ${responses.length} response blocks');
    
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
        
        // 如果name为空，从href提取
        if (name.isEmpty) {
          name = href.split('/').last;
          if (name.isEmpty && href.endsWith('/')) {
            name = href.split('/')[href.split('/').length - 2];
          }
        }
        
        // URL解码
        try {
          href = Uri.decodeFull(href);
        } catch (e) {
          debugPrint('URL decode error for href: $href');
        }
        
        debugPrint('Processing: href=$href, name=$name, isCollection=$isCollection');
        
        // 清理路径
        String cleanPath = href;
        
        // 移除服务器URL前缀
        if (cleanPath.startsWith(serverUrl)) {
          cleanPath = cleanPath.substring(serverUrl.length);
        }
        
        // 移除WebDAV路径前缀
        if (cleanPath.startsWith('/dav')) {
          cleanPath = cleanPath.substring(4);
        }
        
        // 移除前导斜杠
        cleanPath = cleanPath.replaceFirst(RegExp(r'^/+'), '');
        
        // 移除末尾斜杠（对于目录）
        if (isCollection) {
          cleanPath = cleanPath.replaceFirst(RegExp(r'\/$'), '');
        }
        
        // 跳过隐藏文件
        if (name.isEmpty || name.startsWith('.')) {
          debugPrint('Skipping: $name (path: $cleanPath) - empty or hidden file');
          continue;
        }
        
        // 跳过当前目录本身（当不是根目录时）
        if (basePath.isNotEmpty && cleanPath == basePath) {
          debugPrint('Skipping: $name (path: $cleanPath) - current directory');
          continue;
        }
        
        // 跳过重复路径（只在非根目录时应用此检查）
        if (basePath.isNotEmpty && 
            (href.endsWith('/${Uri.encodeComponent(basePath)}') || href == '/dav/$basePath')) {
          debugPrint('Skipping: $name (path: $cleanPath) - duplicate path');
          continue;
        }
        
        // 跳过根目录节点（无论是否是根目录访问）
        if ((href == '/dav/' || href == '/dav')) {
          debugPrint('Skipping: $name (path: $cleanPath) - root directory node');
          continue;
        }
        
        debugPrint('Adding file: $name, path: $cleanPath, isDir: $isCollection');
        
        final sizeStr = contentLengthMatch?.group(1) ?? '0';
        final lastModified = lastModifiedMatch?.group(1) ?? '';
        
        DateTime modifiedDate;
        try {
          modifiedDate = lastModified.isNotEmpty ? 
              DateTime.parse(lastModified) : DateTime.now();
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

    debugPrint('Successfully parsed ${files.length} files/directories');
    
    // 打印所有找到的文件用于调试
    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      debugPrint('File ${i+1}: ${file.name} (${file.isDirectory ? "目录" : "文件"}) path: ${file.path}');
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
      Uri.parse('$serverUrl/$filePath'),
      headers: {'Authorization': _authHeader},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to download file: ${response.statusCode}');
    }

    return response.bodyBytes;
  }

  String getFileUrl(String filePath) {
    return '$serverUrl/$filePath';
  }

  Future<List<WebDavFile>> scanAudioFiles(String directoryPath) async {
    final allFiles = await listFiles(directoryPath);
    return allFiles.where((file) => file.isAudioFile).toList();
  }
}