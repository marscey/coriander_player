enum CloudServiceType {
  webdav,
  // 未来可扩展：s3, ftp, onedrive, googledrive等
}

class CloudConnection {
  final String id;
  final String name;
  final CloudServiceType type;
  final String serverUrl;
  final String username;
  final String password;
  final String? displayName;
  final DateTime lastSync;
  final bool isActive;

  CloudConnection({
    required this.id,
    required this.name,
    required this.type,
    required this.serverUrl,
    required this.username,
    required this.password,
    this.displayName,
    DateTime? lastSync,
    this.isActive = true,
  }) : lastSync = lastSync ?? DateTime.fromMillisecondsSinceEpoch(0);

  CloudConnection copyWith({
    String? id,
    String? name,
    CloudServiceType? type,
    String? serverUrl,
    String? username,
    String? password,
    String? displayName,
    DateTime? lastSync,
    bool? isActive,
  }) {
    return CloudConnection(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      serverUrl: serverUrl ?? this.serverUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      displayName: displayName ?? this.displayName,
      lastSync: lastSync ?? this.lastSync,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudConnection &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}