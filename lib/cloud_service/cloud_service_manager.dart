import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cloud_connection.dart';
import 'webdav_service.dart';

class CloudServiceManager extends ChangeNotifier {
  static const String _storageKey = 'cloud_connections';
  static const String _passwordStorageKey = 'cloud_passwords';
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static bool _secureStorageAvailable = true;

  static CloudServiceManager? _instance;
  static CloudServiceManager get instance {
    if (_instance == null) {
      throw StateError('CloudServiceManager not initialized');
    }
    return _instance!;
  }

  final List<CloudConnection> _connections = [];
  final Map<String, WebDavService> _services = {};
  final Completer<void> _readyCompleter = Completer<void>();
  Future<void> get ready => _readyCompleter.future;

  List<CloudConnection> get connections => List.unmodifiable(_connections);

  CloudServiceManager() {
    _instance = this;
    _loadConnections();
  }

  Future<bool> _trySecureStorageWrite(String key, String value) async {
    if (!_secureStorageAvailable) return false;
    try {
      await _secureStorage.write(key: key, value: value);
      return true;
    } catch (e) {
      _secureStorageAvailable = false;
      return false;
    }
  }

  Future<String?> _trySecureStorageRead(String key) async {
    if (!_secureStorageAvailable) return null;
    try {
      return await _secureStorage.read(key: key);
    } catch (e) {
      _secureStorageAvailable = false;
      return null;
    }
  }

  Future<bool> _trySecureStorageDelete(String key) async {
    if (!_secureStorageAvailable) return false;
    try {
      await _secureStorage.delete(key: key);
      return true;
    } catch (e) {
      _secureStorageAvailable = false;
      return false;
    }
  }

  Future<Map<String, String>> _loadPasswordMap() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_passwordStorageKey);
    if (jsonStr == null) return {};
    final Map<String, dynamic> decoded = jsonDecode(jsonStr);
    return decoded.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> _savePasswordMap(Map<String, String> passwords) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_passwordStorageKey, jsonEncode(passwords));
  }

  Future<void> _savePassword(String connectionId, String password) async {
    final secureOk = await _trySecureStorageWrite(
      'cloud_password_$connectionId',
      password,
    );
    if (!secureOk) {
      final passwords = await _loadPasswordMap();
      passwords[connectionId] = password;
      await _savePasswordMap(passwords);
    }
  }

  Future<String?> _loadPassword(String connectionId, {String? jsonFallback}) async {
    final securePassword = await _trySecureStorageRead(
      'cloud_password_$connectionId',
    );
    if (securePassword != null && securePassword.isNotEmpty) {
      return securePassword;
    }

    final passwords = await _loadPasswordMap();
    final mapPassword = passwords[connectionId];
    if (mapPassword != null && mapPassword.isNotEmpty) {
      await _trySecureStorageWrite(
        'cloud_password_$connectionId',
        mapPassword,
      );
      return mapPassword;
    }

    if (jsonFallback != null && jsonFallback.isNotEmpty) {
      await _savePassword(connectionId, jsonFallback);
      return jsonFallback;
    }

    return null;
  }

  Future<void> _deletePassword(String connectionId) async {
    await _trySecureStorageDelete('cloud_password_$connectionId');
    final passwords = await _loadPasswordMap();
    passwords.remove(connectionId);
    await _savePasswordMap(passwords);
  }

  Future<void> _loadConnections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _connections.clear();

        for (var json in jsonList) {
          final password = await _loadPassword(
            json['id'],
            jsonFallback: json['password'] as String?,
          );

          _connections.add(CloudConnection(
            id: json['id'],
            name: json['name'],
            type: CloudServiceType.values.firstWhere(
              (e) => e.toString() == 'CloudServiceType.${json['type']}',
            ),
            serverUrl: json['serverUrl'],
            username: json['username'],
            password: password ?? '',
            displayName: json['displayName'],
            lastSync: DateTime.parse(json['lastSync']),
            isActive: json['isActive'] ?? true,
          ));
        }

        await _saveConnections();
        notifyListeners();
      }
    } finally {
      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
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

    for (final conn in _connections) {
      await _savePassword(conn.id, conn.password);
    }
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
    await _deletePassword(id);
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
    for (final conn in _connections) {
      await _deletePassword(conn.id);
    }
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
