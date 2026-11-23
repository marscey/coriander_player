import 'dart:convert';
import 'dart:io';

import 'package:coriander_player/platform_helper.dart';
import 'package:coriander_player/utils.dart';

/// 桌面端单实例守卫。
///
/// 实现方式：第一个实例在回环地址上监听一个固定端口，后续实例连接该端口
/// 发送 `show` 后立即退出，前一个实例收到消息即把窗口显示并聚焦。
///
/// 背景：应用「关闭窗口即最小化到托盘」（`AppSettings.closeToTray`）时进程仍在，
/// 用户再点一次图标 / 再跑一次 `flutter run`，就会多出一个进程（多份托盘图标、
/// 两条播放队列互相打架）。移动端没有该问题，直接放行。
class SingleInstance {
  SingleInstance._();

  /// 固定端口：Coriander Player 专用（非系统保留端口）
  static const int port = 45123;

  static ServerSocket? _server;

  /// 是否是第一个实例。返回 false 时应立即退出进程。
  ///
  /// [onActivate] 在收到其它实例的激活请求时于主实例中回调（用于显示窗口）。
  static Future<bool> acquire({void Function()? onActivate}) async {
    if (!PlatformHelper.isDesktop) return true;

    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      ).timeout(const Duration(seconds: 1));
    } on SocketException {
      await _notifyExistingInstance();
      return false;
    } catch (e) {
      // 无法判定时不要阻断启动
      LOGGER.w('[single-instance] bind 失败，跳过检查: $e');
      return true;
    }

    _server!.listen(
      (socket) {
        try {
          socket.add(utf8.encode('show'));
          socket.destroy();
        } catch (_) {}
        LOGGER.i('[single-instance] 收到其它实例的激活请求，显示主窗口');
        onActivate?.call();
      },
      onError: (e) => LOGGER.w('[single-instance] listener error: $e'),
    );

    return true;
  }

  static Future<void> _notifyExistingInstance() async {
    try {
      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 800),
      );
      socket.write('show');
      await socket.flush();
      await socket.close();
      LOGGER.i('[single-instance] 已有实例在运行，已请求其显示窗口，本次退出');
    } catch (e) {
      LOGGER.w('[single-instance] 通知已有实例失败: $e');
    }
  }
}
