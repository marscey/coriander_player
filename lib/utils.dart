// ignore_for_file: unnecessary_this

import 'dart:io';
import 'package:coriander_player/app_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:pinyin/pinyin.dart';

extension StringHMMSS on Duration {
  /// Returns a string with hours, minutes, seconds,
  /// in the following format: H:MM:SS
  String toStringHMMSS() {
    return toString().split(".").first;
  }
}

/// 把 dec 表示成两位 hex
String _toHexString(int dec) {
  assert(dec >= 0 && dec <= 0xff);

  var hex = dec.toRadixString(16);
  if (hex.length == 1) hex = "0$hex";
  return hex;
}

extension RGBHexString on Color {
  String toRGBHexString() {
    final redHex = _toHexString(red);
    final greenHex = _toHexString(green);
    final blueHex = _toHexString(blue);

    return "#$redHex$greenHex$blueHex";
  }
}

/// [rgbHexStr] 必须是 #RRGGBB
Color? fromRGBHexString(String rgbHexStr) {
  if (rgbHexStr.startsWith("#") && rgbHexStr.length == 7) {
    return Color(0xff000000 + int.parse(rgbHexStr.substring(1), radix: 16));
  }

  return null;
}

Map<String, String> _pinyinCache = {};

extension PinyinCompare on String {
  /// convert str to pinyin, cache it when it hasn't been converted;
  String _getPinyin() {
    final cachedPinyin = _pinyinCache[this];
    if (cachedPinyin != null) return cachedPinyin;

    final splited = this.split("");
    final pinyinBuilder = StringBuffer();

    for (var c in splited) {
      if (ChineseHelper.isChinese(c)) {
        final pinyin = PinyinHelper.convertToPinyinArray(
          c,
          PinyinFormat.WITHOUT_TONE,
        ).firstOrNull;

        pinyinBuilder.write(pinyin ?? c);
      } else {
        pinyinBuilder.write(c);
      }
    }

    final pinyin = pinyinBuilder.toString();

    _pinyinCache[this] = pinyin;

    return pinyin;
  }

  /// Compares this string to [other] with pinyin first, else use the ordering of the code units.
  ///
  /// Returns a negative value if `this` is ordered before `other`,
  /// a positive value if `this` is ordered after `other`,
  /// or zero if `this` and `other` are equivalent.
  int localeCompareTo(String other) {
    final thisContainsChinese = ChineseHelper.containsChinese(this);
    final otherContainsChinese = ChineseHelper.containsChinese(other);

    final thisCmpStr = thisContainsChinese ? this._getPinyin() : this;
    final otherCmpStr = otherContainsChinese ? other._getPinyin() : other;

    return thisCmpStr.compareTo(otherCmpStr);
  }
}

final GlobalKey<NavigatorState> ROUTER_KEY = GlobalKey();

final SCAFFOLD_MESSAGER = GlobalKey<ScaffoldMessengerState>();
void showTextOnSnackBar(String text) {
  SCAFFOLD_MESSAGER.currentState?.showSnackBar(SnackBar(content: Text(text)));
}

final LOGGER_MEMORY = MemoryOutput(
  secondOutput: kDebugMode ? ConsoleOutput() : null,
);

/// 把 logger 的输出同步落盘，交给 DebugLogger
class _FileLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      DebugLogger.instance.log(line);
    }
  }
}

final LOGGER = Logger(
  filter: ProductionFilter(),
  printer: SimplePrinter(colors: false),
  output: MultiOutput([LOGGER_MEMORY, _FileLogOutput()]),
  level: Level.all,
);

/// 运行日志落盘
///
/// 路径：macOS 为 `~/Library/Logs/coriander_player/`，其他平台为 `<appData>/logs/`。
/// 按天切分（app-YYYY-MM-DD.log），默认保留最近 7 天，追加写入不清空。
class DebugLogger {
  static const int _retainDays = 7;
  static const int _maxMemoryLines = 3000;

  static final DebugLogger _instance = DebugLogger._();
  static DebugLogger get instance => _instance;
  DebugLogger._();

  final List<String> _memLogs = [];
  Directory? _dir;
  IOSink? _sink;
  String? _dayKey;
  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      _dir = await getLogsDir();
      _openSink(DateTime.now());
      _sink?.writeln('===== app start ${DateTime.now()} =====');
      _cleanupOldLogs();
    } catch (err) {
      // 日志不可写不应阻塞启动
      stdout.writeln('[log] init failed: $err');
    }
  }

  void log(String message) {
    final now = DateTime.now();
    final entry = '[${_clock(now)}] $message';
    _memLogs.add(entry);
    if (_memLogs.length > _maxMemoryLines) _memLogs.removeAt(0);

    final sink = _sink;
    if (sink == null) return;

    final key = _dateKey(now);
    if (key != _dayKey) {
      _openSink(now);
      _cleanupOldLogs();
    }
    _sink?.writeln(entry);
  }

  File get _currentFile {
    final dir = _dir;
    if (dir == null) throw StateError('日志目录未初始化');
    return File(p.join(dir.path, 'app-${_dayKey ?? _dateKey(DateTime.now())}.log'));
  }

  void _openSink(DateTime now) {
    try {
      _dayKey = _dateKey(now);
      _sink?.flush();
      _sink?.close();
      final dir = _dir;
      if (dir == null) return;
      final file = File(p.join(dir.path, 'app-${_dayKey!}.log'));
      if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
      _sink = file.openWrite(mode: FileMode.append);
    } catch (err) {
      _sink = null;
      stdout.writeln('[log] open failed: $err');
    }
  }

  void _cleanupOldLogs() {
    try {
      final dir = _dir;
      if (dir == null || !dir.existsSync()) return;
      final limit = DateTime.now().subtract(const Duration(days: _retainDays));
      for (final entity in dir.listSync()) {
        if (entity is! File || !entity.path.endsWith('.log')) continue;
        if (entity.statSync().modified.isBefore(limit)) entity.deleteSync();
      }
    } catch (_) {}
  }

  /// 读取当天日志文件；文件不可用时回退到内存日志
  Future<String> readLogs() async {
    try {
      final file = _currentFile;
      if (await file.exists()) {
        final text = await file.readAsString();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {}
    if (_memLogs.isEmpty) return '暂无日志';
    return _memLogs.join('\n');
  }

  Future<void> clear() async {
    _memLogs.clear();
    try {
      _sink?.flush();
      final file = _currentFile;
      if (await file.exists()) await file.writeAsString('');
    } catch (_) {}
  }

  /// 日志目录绝对路径，方便"打开日志目录"
  Future<String?> logsPath() async {
    try {
      return (await getLogsDir()).path;
    } catch (_) {
      return null;
    }
  }

  String _dateKey(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';
}

/// 便捷函数：写一条运行日志（同时进内存与文件）
void debugLog(String message) {
  LOGGER.d(message);
}

