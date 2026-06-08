import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../cloud_service/cloud_connection.dart';
import '../../cloud_service/cloud_service_manager.dart';
import '../../cloud_service/webdav_service.dart';

class CloudConnectionForm extends StatefulWidget {
  final CloudConnection? connection;

  const CloudConnectionForm({super.key, this.connection});

  @override
  State<CloudConnectionForm> createState() => _CloudConnectionFormState();
}

class _CloudConnectionFormState extends State<CloudConnectionForm> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late String _displayName;
  late String _serverUrl;
  late String _username;
  late String _password;
  bool _isTesting = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _name = widget.connection?.name ?? '';
    _displayName = widget.connection?.displayName ?? '';
    _serverUrl = widget.connection?.serverUrl ?? '';
    _username = widget.connection?.username ?? '';
    _password = widget.connection?.password ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.connection == null ? '添加云服务连接' : '编辑云服务连接'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(
                  fieldKey: const Key('cloud_name'),
                  label: '连接名称',
                  hint: '例如：我的WebDAV',
                  initialValue: _name,
                  onSaved: (value) => _name = value!,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入连接名称';
                    }
                    return null;
                  },
                ),
                _buildTextField(
                  label: '显示名称（可选）',
                  hint: '在界面上显示的名称',
                  initialValue: _displayName,
                  onSaved: (value) => _displayName = value!,
                ),
                _buildTextField(
                  fieldKey: const Key('cloud_url'),
                  label: '服务器地址',
                  hint: '例如：https://cloud.example.com/webdav',
                  initialValue: _serverUrl,
                  onSaved: (value) => _serverUrl = value!,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入服务器地址';
                    }
                    if (!value.startsWith('http')) {
                      return '请输入有效的URL地址';
                    }
                    return null;
                  },
                ),
                _buildTextField(
                  fieldKey: const Key('cloud_user'),
                  label: '用户名',
                  hint: 'WebDAV用户名',
                  initialValue: _username,
                  onSaved: (value) => _username = value!,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入用户名';
                    }
                    return null;
                  },
                ),
                _buildTextField(
                  fieldKey: const Key('cloud_pass'),
                  label: '密码',
                  hint: 'WebDAV密码',
                  initialValue: _password,
                  onSaved: (value) => _password = value!,
                  obscureText: true,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '请输入密码';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                if (_isTesting)
                  const LinearProgressIndicator(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _isTesting ? null : _testConnection,
          child: const Text('测试连接'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveConnection,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required String initialValue,
    required void Function(String?) onSaved,
    String? Function(String?)? validator,
    bool obscureText = false,
    Key? fieldKey,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        key: fieldKey,
        initialValue: initialValue,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onSaved: onSaved,
        validator: validator,
        obscureText: obscureText,
      ),
    );
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    
    _formKey.currentState!.save();
    
    setState(() {
      _isTesting = true;
    });

    try {
      final service = WebDavService(
        serverUrl: _serverUrl,
        username: _username,
        password: _password,
      );

      final isConnected = await service.testConnection();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isConnected ? '连接成功' : '连接失败'),
            backgroundColor: isConnected ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接测试失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTesting = false;
        });
      }
    }
  }

  Future<void> _saveConnection() async {
    if (!_formKey.currentState!.validate()) return;
    
    _formKey.currentState!.save();
    
    setState(() {
      _isLoading = true;
    });

    try {
      final manager = context.read<CloudServiceManager>();
      final connection = CloudConnection(
        id: widget.connection?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _name,
        type: CloudServiceType.webdav,
        serverUrl: _serverUrl,
        username: _username,
        password: _password,
        displayName: _displayName.isNotEmpty ? _displayName : null,
        lastSync: DateTime.now(),
        isActive: true,
      );

      if (widget.connection == null) {
        await manager.addConnection(connection);
      } else {
        await manager.updateConnection(connection);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.connection == null ? '连接已添加' : '连接已更新',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
}