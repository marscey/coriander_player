import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_connection.dart';
import 'webdav_service.dart';

class CloudServiceManager extends ChangeNotifier {
  static const String _storageKey = 'cloud_connections';
  final List<CloudConnection> _connections = [];
  final Map<String, WebDavService> _services = {};

  List<CloudConnection> get connections => List.unmodifiable(_connections);

  CloudServiceManager() {
    _loadConnections();
  }

  Future<void> _loadConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_storageKey);
    
    if (jsonString != null) {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      _connections.clear();
      _connections.addAll(
        jsonList.map((json) => CloudConnection(
          id: json['id'],
          name: json['name'],
          type: CloudServiceType.values.firstWhere(
            (e) => e.toString() == 'CloudServiceType.${json['type']}',
          ),
          serverUrl: json['serverUrl'],
          username: json['username'],
          password: json['password'],
          displayName: json['displayName'],
          lastSync: DateTime.parse(json['lastSync']),
          isActive: json['isActive'] ?? true,
        )),
      );
      notifyListeners();
    }
  }

  Future<void> _saveConnections() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = _connections.map((conn) => {
      'id': conn.id,
      'name': conn.name,
      'type': conn.type.toString().split('.').last,
      'serverUrl': conn.serverUrl,
      'username': conn.username,
      'password': conn.password,
      'displayName': conn.displayName,
      'lastSync': conn.lastSync.toIso8601String(),
      'isActive': conn.isActive,
    }).toList();
    
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  Future<void> addConnection(CloudConnection connection) async {
    _connections.removeWhere((c) => c.id == connection.id);
    _connections.add(connection);
    await _saveConnections();
    notifyListeners();
  }

  Future<void> updateConnection(CloudConnection connection) async {
    final index = _connections.indexWhere((c) => c.id == connection.id);
    if (index != -1) {
      _connections[index] = connection;
      await _saveConnections();
      notifyListeners();
    }
  }

  Future<void> removeConnection(String id) async {
    _connections.removeWhere((c) => c.id == id);
    _services.remove(id);
    await _saveConnections();
    notifyListeners();
  }

  Future<void> deleteConnection(String id) async {
    return removeConnection(id);
  }

  List<CloudConnection> getAllConnections() {
    return List.unmodifiable(_connections);
  }

  Future<void> clearAllConnections() async {
    _connections.clear();
    _services.clear();
    await _saveConnections();
    notifyListeners();
  }

  Future<void> loadConnections() async {
    return _loadConnections();
  }

  WebDavService? getService(String connectionId) {
    final connection = _connections.firstWhere(
      (c) => c.id == connectionId,
    );
    
    if (connection.type != CloudServiceType.webdav) return null;
    
    // 调试输出连接信息
    debugPrint('=== WebDAV Connection Debug ===');
    debugPrint('Connection ID: ${connection.id}');
    debugPrint('Server URL: ${connection.serverUrl}');
    debugPrint('Username: ${connection.username}');
    debugPrint('Password: ${connection.password.isEmpty ? "[EMPTY]" : "[PROVIDED]"}');
    debugPrint('============================');
    
    return _services.putIfAbsent(connectionId, () => WebDavService(
      serverUrl: connection.serverUrl,
      username: connection.username,
      password: connection.password,
    ));
  }

  CloudConnection? getConnection(String id) {
    try {
      return _connections.firstWhere((c) => c.id == id);
    } catch (e) {
      return null;
    }
  }
}