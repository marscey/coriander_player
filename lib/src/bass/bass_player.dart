// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:io';
import 'package:coriander_player/app_preference.dart';
import 'package:coriander_player/src/bass/bass_wasapi.dart' as BASS;
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/platform_helper.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:path/path.dart' as path;
import 'package:coriander_player/src/bass/bass.dart' as BASS;
import 'dart:ffi' as ffi;

enum PlayerState {
  /// stop() has been called or the end of an audio has been reached
  stopped,

  /// start() has been called
  playing,

  /// pause() has been called
  paused,

  /// BASS_Pause() has been called or stopping unexpectedly (eg. a USB soundcard being disconnected).
  /// In either case, playback will be resumed by BASS_Start.
  pausedDevice,

  ///Playback of the stream has been stalled due to a lack of sample data.
  ///Playback will automatically resume once there is sufficient data to do so.
  stalled,

  /// the end of an audio has been reached
  completed,

  unknown,
}

List<String> get _bassPlugins {
  if (PlatformHelper.isMacOS) {
    return [
      "BASS/bassape.dylib",
      "BASS/bassdsd.dylib",
      "BASS/bassflac.dylib",
      "BASS/bassmidi.dylib",
      "BASS/bassopus.dylib",
      "BASS/basswv.dylib"
    ];
  } else if (PlatformHelper.isWindows) {
    return [
      "BASS/bassape.dll",
      "BASS/bassdsd.dll",
      "BASS/bassflac.dll",
      "BASS/bassmidi.dll",
      "BASS/bassopus.dll",
      "BASS/basswv.dll"
    ];
  } else {
    return [
      "BASS/libbassape.so",
      "BASS/libbassdsd.so",
      "BASS/libbassflac.so",
      "BASS/libbassmidi.so",
      "BASS/libbassopus.so",
      "BASS/libbasswv.so"
    ];
  }
}

class BassPlayer {
  late final ffi.DynamicLibrary _bassLib;
  late final ffi.DynamicLibrary _bassWasapiLib;
  late final BASS.Bass _bass;
  late final BASS.BassWasapi _bassWasapi;

  String? _fPath;
  int? _fstream;
  ffi.Pointer<ffi.Uint8>? _fileData; // 用于跟踪从内存加载时分配的内存

  /// 是否启用 wasapi 独占模式
  bool wasapiExclusive = false;

  Timer? _positionUpdater;
  final _positionStreamController = StreamController<double>.broadcast();
  final _playerStateStreamController =
      StreamController<PlayerState>.broadcast();

  /// audio's length in seconds
  double get length => _fstream == null
      ? 1.0
      : _bass.BASS_ChannelBytes2Seconds(_fstream!,
          _bass.BASS_ChannelGetLength(_fstream!, BASS.BASS_POS_BYTE));

  /// current position in seconds
  double get position => _fstream == null
      ? 0.0
      : _bass.BASS_ChannelBytes2Seconds(_fstream!,
          _bass.BASS_ChannelGetPosition(_fstream!, BASS.BASS_POS_BYTE));

  PlayerState get playerState {
    if (_fstream == null) {
      return PlayerState.unknown;
    }

    switch (_bass.BASS_ChannelIsActive(_fstream!)) {
      case BASS.BASS_ACTIVE_STOPPED:
        return PlayerState.stopped;
      case BASS.BASS_ACTIVE_PLAYING:
        if (wasapiExclusive) {
          /// wasapi exclusive's channel is a decoding channel,
          /// will be BASS_ACTIVE_PLAYING as long as there is still data to decode.
          /// So here we check BASS_WASAPI_IsStarted to
          /// judge between BASS_ACTIVE_PLAYING and BASS_ACTIVE_PAUSED
          return _bassWasapi.BASS_WASAPI_IsStarted() == BASS.TRUE
              ? PlayerState.playing
              : PlayerState.paused;
        }
        return PlayerState.playing;
      case BASS.BASS_ACTIVE_PAUSED:
        return PlayerState.paused;
      case BASS.BASS_ACTIVE_PAUSED_DEVICE:
        return PlayerState.pausedDevice;
      case BASS.BASS_ACTIVE_STALLED:
        return PlayerState.stalled;
      default:
        return PlayerState.unknown;
    }
  }

  double get volumeDsp {
    if (_fstream == null) return 0;

    final volDsp = ffi.malloc.allocate<ffi.Float>(ffi.sizeOf<ffi.Float>());
    _bass.BASS_ChannelGetAttribute(_fstream!, BASS.BASS_ATTRIB_VOLDSP, volDsp);
    return volDsp.value;
  }

  /// update every 33ms
  Stream<double> get positionStream => _positionStreamController.stream;

  Stream<PlayerState> get playerStateStream =>
      _playerStateStreamController.stream;

  Timer _getPositionUpdater() {
    return Timer.periodic(
      const Duration(milliseconds: 33),
      (timer) {
        _positionStreamController.add(position);

        /// check if the channel has completed
        if (playerState == PlayerState.stopped) {
          _playerStateStreamController.add(PlayerState.completed);
        }
      },
    );
  }

  void _bassInit() {
    // 使用已定义的初始化标志
    int initFlags = BASS.BASS_DEVICE_REINIT;
    
    if (PlatformHelper.isMacOS) {
      LOGGER.i("[bassInit] macOS platform detected, using default flags");
    }
    
    // 尝试不同的设备ID和采样率组合
    List<int> deviceIds = [1]; // 默认设备
    List<int> sampleRates = [48000, 44100, 96000]; // 常见采样率
    
    bool initialized = false;
    
    for (int deviceId in deviceIds) {
      for (int sampleRate in sampleRates) {
        LOGGER.i("[bassInit] Trying to initialize device $deviceId at $sampleRate Hz");
        
        if (_bass.BASS_Init(
                deviceId, sampleRate, initFlags, ffi.nullptr, ffi.nullptr) != 0) {
          LOGGER.i("[bassInit] Success! Initialized device $deviceId at $sampleRate Hz");
          initialized = true;
          break;
        }
        
        int errorCode = _bass.BASS_ErrorGetCode();
        LOGGER.w("[bassInit] Failed with error code: $errorCode");
      }
      
      if (initialized) break;
    }
    
    if (!initialized) {
      // 如果所有尝试都失败，使用原始的初始化方式并抛出错误
      LOGGER.e("[bassInit] All initialization attempts failed, using fallback");
      if (_bass.BASS_Init(
              1, 48000, BASS.BASS_DEVICE_REINIT, ffi.nullptr, ffi.nullptr) == 0) {
        int errorCode = _bass.BASS_ErrorGetCode();
        LOGGER.e("[bassInit] Final initialization failed with error code: $errorCode");
        
        switch (errorCode) {
          case BASS.BASS_ERROR_DEVICE:
            throw const FormatException("device is invalid.");
          case BASS.BASS_ERROR_NOTAVAIL:
            throw const FormatException(
                "The BASS_DEVICE_REINIT flag cannot be used when device is -1. Use the real device number instead.");
          case BASS.BASS_ERROR_ALREADY:
            throw const FormatException(
                "The device has already been initialized. The BASS_DEVICE_REINIT flag can be used to request reinitialization.");
          case BASS.BASS_ERROR_ILLPARAM:
            throw const FormatException("win is not a valid window handle.");
          case BASS.BASS_ERROR_DRIVER:
            throw const FormatException("There is no available device driver.");
          case BASS.BASS_ERROR_BUSY:
            throw const FormatException(
                "Something else has exclusive use of the device.");
          case BASS.BASS_ERROR_FORMAT:
            throw const FormatException(
                "The specified format is not supported by the device. Try changing the freq parameter.");
          case BASS.BASS_ERROR_MEM:
            throw const FormatException("There is insufficient memory.");
          case BASS.BASS_ERROR_UNKNOWN:
            throw const FormatException(
                "Some other mystery problem! Maybe Something else has exclusive use of the device.");
        }
      }
    }
  }

  void _startDevice() {
    if (_bass.BASS_Start() == BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          _startDevice();
          break;
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The app's audio has been interrupted and cannot be resumed yet. (iOS only)");
        case BASS.BASS_ERROR_REINIT:
          throw const FormatException(
              "The device is currently being reinitialized or needs to be.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException(
              "Some other mystery problem! Maybe Something else has exclusive use of the device.");
      }
    }
  }

  /// load BASS library based on platform
  BassPlayer() {
    try {
      final libPath = PlatformHelper.bassLibraryPath;
      _bassLib = ffi.DynamicLibrary.open(libPath);
      _bass = BASS.Bass(_bassLib);

      // WASAPI is Windows-only
      if (PlatformHelper.supportsWasapi()) {
        final wasapiLibPath = PlatformHelper.bassWasapiLibraryPath;
        if (wasapiLibPath.isNotEmpty) {
          try {
            _bassWasapiLib = ffi.DynamicLibrary.open(wasapiLibPath);
            _bassWasapi = BASS.BassWasapi(_bassWasapiLib);
          } catch (e) {
            LOGGER.w("Failed to load BASS WASAPI library: $e");
          }
        }
      }

      // load add-ons to avoid using os codec or support more format
      // Use PlatformHelper.bassPluginPaths to get the correct plugin paths for the current platform
      for (final pluginPath in PlatformHelper.bassPluginPaths) {
        try {
          final pluginPathP =
              pluginPath.toNativeUtf16() as ffi.Pointer<ffi.Char>;
          final hplugin = _bass.BASS_PluginLoad(pluginPathP, BASS.BASS_UNICODE);

          if (hplugin == 0) {
            switch (_bass.BASS_ErrorGetCode()) {
              case BASS.BASS_ERROR_FILEOPEN:
                LOGGER.w("[BASS Plugin] Could not open plugin: $pluginPath");
                break;
              case BASS.BASS_ERROR_FILEFORM:
                LOGGER.w("[BASS Plugin] $pluginPath is not a valid plugin");
                break;
              case BASS.BASS_ERROR_VERSION:
                LOGGER.w(
                    "[BASS Plugin] $pluginPath requires a different BASS version");
                break;
              case BASS.BASS_ERROR_ALREADY:
                // Plugin already loaded, continue
                break;
              default:
                LOGGER.w("[BASS Plugin] Failed to load $pluginPath");
            }
          }
        } catch (e) {
          LOGGER.w("[BASS Plugin] Exception loading $pluginPath: $e");
        }
      }

      try {
        _bassInit();
      } catch (err) {
        LOGGER.e("[bass init] $err");
      }
    } catch (e) {
      LOGGER.e("Failed to initialize BASS library: $e");
      // 创建一个模拟的Bass实例，避免应用程序崩溃
      _createMockBassInstance();
    }
  }

  /// 创建一个模拟的Bass实例，当无法加载真实的BASS库时使用
  void _createMockBassInstance() {
    // 使用正确类型的泛型函数创建模拟的Bass实例
    _bass = BASS.Bass.fromLookup(<T extends ffi.NativeType>(String symbolName) {
      throw UnsupportedError('BASS library is not available');
    });
  }

  /// true: 操作成功；false: 操作失败
  bool useExclusiveMode(bool exclusive) {
    // WASAPI exclusive mode is only supported on Windows
    if (PlatformHelper.isMacOS) {
      if (exclusive) {
        showTextOnSnackBar("WASAPI独占模式仅在Windows平台可用");
      }
      return !exclusive; // Always return false if trying to enable, true if disabling
    }

    // Original Windows implementation
    if (!PlatformHelper.supportsWasapi()) {
      return false;
    }

    final prevState = wasapiExclusive;
    try {
      final lastPos = position;
      if (prevState) {
        _bassWasapi.BASS_WASAPI_Free();
        _bassInit();
      }
      wasapiExclusive = exclusive;
      if (_fstream != null && _fPath != null) {
        setSource(_fPath!);
        setVolumeDsp(AppPreference.instance.playbackPref.volumeDsp);
        seek(lastPos);
        start();
      }
      return true;
    } catch (err) {
      LOGGER.e("[use exclusive mode] $err");
      showTextOnSnackBar(err.toString());
    }
    wasapiExclusive = prevState;
    return false;
  }

  /// if setSource has been called once,
  /// it will pause current channel and free current stream.
  void setSource(String filePath) {
    if (_fstream != null) {
      _positionUpdater?.cancel();
      freeFStream();
    }
    // Ensure path uses platform-appropriate separators
    final normalizedPath = PlatformHelper.normalizePath(filePath);
    
    // 添加详细日志进行调试
    LOGGER.i("[setSource] Original path: $filePath");
    LOGGER.i("[setSource] Normalized path: $normalizedPath");
    
    // 检查文件是否存在
    final file = File(normalizedPath);
    LOGGER.i("[setSource] File exists: ${file.existsSync()}");
    
    int handle = 0;
    const flags = 
        BASS.BASS_UNICODE | BASS.BASS_SAMPLE_FLOAT | BASS.BASS_ASYNCFILE;
    const exclusiveFlags = flags | BASS.BASS_STREAM_DECODE;
    
    try {
      if (PlatformHelper.isMacOS) {
        // 在macOS平台上，尝试多种路径编码和打开方式
        LOGGER.i("[setSource] macOS path handling");
        
        // 首先尝试使用UTF16编码的路径（标准方法）
        final pathUtf16 = normalizedPath.toNativeUtf16() as ffi.Pointer<ffi.Void>;
        handle = _bass.BASS_StreamCreateFile(
          BASS.FALSE,  // FALSE表示使用文件路径
          pathUtf16,
          0,
          0,
          wasapiExclusive ? exclusiveFlags : flags,
        );
        
        if (handle == 0) {
          // 如果UTF16路径失败，尝试使用UTF8编码的路径
          LOGGER.i("[setSource] Trying UTF8 path on macOS");
          final pathUtf8 = normalizedPath.toNativeUtf8() as ffi.Pointer<ffi.Void>;
          handle = _bass.BASS_StreamCreateFile(
            BASS.FALSE,
            pathUtf8,
            0,
            0,
            wasapiExclusive ? (exclusiveFlags & ~BASS.BASS_UNICODE) : (flags & ~BASS.BASS_UNICODE),
          );
        }
        
        // 如果仍然失败，尝试不使用ASYNCFILE标志
        if (handle == 0) {
          LOGGER.i("[setSource] Trying without ASYNCFILE flag");
          final pathUtf16NoAsync = normalizedPath.toNativeUtf16() as ffi.Pointer<ffi.Void>;
          const noAsyncFlags = BASS.BASS_UNICODE | BASS.BASS_SAMPLE_FLOAT;
          const noAsyncExclusiveFlags = noAsyncFlags | BASS.BASS_STREAM_DECODE;
          
          handle = _bass.BASS_StreamCreateFile(
            BASS.FALSE,
            pathUtf16NoAsync,
            0,
            0,
            wasapiExclusive ? noAsyncExclusiveFlags : noAsyncFlags,
          );
        }
        
        // 如果仍然失败，尝试从内存加载文件（绕过路径问题）
        if (handle == 0) {
          LOGGER.i("[setSource] Trying memory-based loading on macOS");
          try {
            // 读取文件内容到内存
            final fileBytes = file.readAsBytesSync();
            LOGGER.i("[setSource] File size: ${fileBytes.length} bytes");
            
            // 将Dart的Uint8List转换为ffi.Pointer<ffi.Uint8>
            _fileData = ffi.malloc.allocate(fileBytes.length);
            // 优化内存复制方式，减少循环开销
            final fileDataAsTypedList = _fileData!.asTypedList(fileBytes.length);
            fileDataAsTypedList.setAll(0, fileBytes);
            
            // 从内存创建流 - 尝试多种标志组合
            int memoryFlags = wasapiExclusive 
                ? (exclusiveFlags & ~BASS.BASS_ASYNCFILE) // 从内存加载时不需要ASYNCFILE
                : (flags & ~BASS.BASS_ASYNCFILE);
            
            // 第一次尝试
            handle = _bass.BASS_StreamCreateFile(
              BASS.TRUE,  // TRUE表示使用内存
              _fileData!.cast(),
              0,
              fileBytes.length,
              memoryFlags,
            );
            
            LOGGER.i("[setSource] First memory loading attempt: handle = $handle");
            
            // 如果第一次尝试失败，尝试使用基础标志
            if (handle == 0) {
              LOGGER.w("[setSource] First memory load attempt failed, trying with basic flags");
              handle = _bass.BASS_StreamCreateFile(
                BASS.TRUE,
                _fileData!.cast(),
                0,
                fileBytes.length,
                0, // 基础标志
              );
              
              LOGGER.i("[setSource] Basic memory loading attempt: handle = $handle");
              if (handle == 0) {
                final basicErrorCode = _bass.BASS_ErrorGetCode();
                LOGGER.e("[setSource] BASS error code from basic memory loading: $basicErrorCode");
              }
            }
            
            // 注意：这里不释放fileData，因为BASS需要它来播放
            // 应该在freeFStream方法中释放
          } catch (e) {
            LOGGER.e("[setSource] Exception during memory loading: $e");
            // 确保在异常情况下也释放内存
            if (_fileData != null) {
              try {
                ffi.malloc.free(_fileData!);
              } catch (freeError) {
                LOGGER.e("[setSource] Exception during memory free: $freeError");
              }
              _fileData = null;
            }
          }
        }
        
        // 如果仍然失败，获取BASS错误码用于调试
        if (handle == 0) {
          final errorCode = _bass.BASS_ErrorGetCode();
          LOGGER.e("[setSource] BASS error code: $errorCode");
        }
      } else {
        // 其他平台使用原方法
        final pathPointer = normalizedPath.toNativeUtf16() as ffi.Pointer<ffi.Void>;
        handle = _bass.BASS_StreamCreateFile(
          BASS.FALSE,
          pathPointer,
          0,
          0,
          wasapiExclusive ? exclusiveFlags : flags,
        );
      }
    } catch (e) {
      LOGGER.e("[setSource] Exception: $e");
    }

    if (handle != 0) {
      _fstream = handle;
      _fPath = normalizedPath;
    } else {
      _fstream = null;
      _fPath = null;
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          setSource(normalizedPath);
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "The BASS_STREAM_AUTOFREE flag cannot be combined with the BASS_STREAM_DECODE flag.");
        case BASS.BASS_ERROR_ILLPARAM:
          throw const FormatException(
              "The length must be specified when streaming from memory.");
        case BASS.BASS_ERROR_FILEOPEN:
          throw const FormatException("The file could not be opened.");
        case BASS.BASS_ERROR_FILEFORM:
          throw const FormatException(
              "The file's format is not recognised/supported.");
        case BASS.BASS_ERROR_NOTAUDIO:
          throw const FormatException(
              "The file does not contain audio, or it also contains video and videos are disabled.");
        case BASS.BASS_ERROR_CODEC:
          throw const FormatException(
              "The file uses a codec that is not available/supported. This can apply to WAV and AIFF files.");
        case BASS.BASS_ERROR_FORMAT:
          throw const FormatException("The sample format is not supported.");
        case BASS.BASS_ERROR_SPEAKER:
          throw const FormatException(
              "The specified SPEAKER flags are invalid.");
        case BASS.BASS_ERROR_MEM:
          throw const FormatException("There is insufficient memory.");
        case BASS.BASS_ERROR_NO3D:
          throw const FormatException("Could not initialize 3D support.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
  }

  /// [BASS_ATTRIB_VOLDSP] attribute does have direct effect on decoding/recording channels.
  void setVolumeDsp(double volume) {
    if (_fstream == null) return;

    if (_bass.BASS_ChannelSetAttribute(
          _fstream!,
          BASS.BASS_ATTRIB_VOLDSP,
          volume,
        ) ==
        0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_ILLTYPE:
          throw const FormatException("attrib is not valid.");
        case BASS.BASS_ERROR_ILLPARAM:
          throw const FormatException("value is not valid.");
      }
    }
  }

  void _bassWasapiInit() {
    if (_bassWasapi.BASS_WASAPI_Init(
          -1,
          0,
          0,
          BASS.BASS_WASAPI_EXCLUSIVE | BASS.BASS_WASAPI_EVENT,
          0.05,
          0,
          ffi.Pointer<BASS.WASAPIPROC>.fromAddress(-1),
          ffi.Pointer<ffi.Void>.fromAddress(_fstream!),
        ) ==
        BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_WASAPI:
          throw const FormatException("WASAPI is not available.");
        case BASS.BASS_ERROR_DEVICE:
          throw const FormatException("device is invalid.");
        case BASS.BASS_ERROR_ALREADY:
          _bassWasapi.BASS_WASAPI_Free();
          _bassWasapiInit();
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "Exclusive mode and/or event-driven buffering is unavailable on the device, or WASAPIPROC_PUSH is unavailable on input devices and when using event-driven buffering.");
        case BASS.BASS_ERROR_DRIVER:
          throw const FormatException("The driver could not be initialized.");
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException(
              "The BASS channel handle in user is invalid, or not of the required type.");
        case BASS.BASS_ERROR_FORMAT:
          throw const FormatException(
              "The specified format (or that of the BASS channel) is not supported by the device. If the BASS_WASAPI_AUTOFORMAT flag was specified, no other format could be found either.");
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The device is already in use, eg. another process may have initialized it in exclusive mode.");
        case BASS.BASS_ERROR_INIT:
          _bassInit();
          _bassWasapiInit();
          break;
        case BASS.BASS_ERROR_WASAPI_BUFFER:
          throw const FormatException(
              "buffer is too large or small (exclusive mode only).");
        case BASS.BASS_ERROR_WASAPI_CATEGORY:
          throw const FormatException(
              "The category/raw mode could not be set.");
        case BASS.BASS_ERROR_WASAPI_DENIED:
          throw const FormatException(
              "Access to the device is denied. This could be due to privacy settings.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
  }

  void _start_wasapiExclusive() {
    _bassWasapiInit();

    if (_bassWasapi.BASS_WASAPI_Start() == BASS.FALSE) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          _bassWasapiInit();
          _start_wasapiExclusive();
          break;
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
    _playerStateStreamController.add(playerState);
    _positionUpdater = _getPositionUpdater();
  }

  /// start/resume channel
  ///
  /// do nothing if [setSource] hasn't been called
  void start() {
    if (_fstream == null) return;

    if (wasapiExclusive) {
      return _start_wasapiExclusive();
    }
    if (_bass.BASS_ChannelStart(_fstream!) == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_DECODE:
          throw const FormatException(
              "handle is a decoding channel, so cannot be played.");
        case BASS.BASS_ERROR_START:
          _startDevice();
          start();
          break;
      }
    }

    _playerStateStreamController.add(playerState);
    _positionUpdater = _getPositionUpdater();
  }

  void _pause_wasapiExclusive() {
    if (_bassWasapi.BASS_WASAPI_Stop(BASS.FALSE) == BASS.TRUE) {
      _playerStateStreamController.add(playerState);
      _positionUpdater?.cancel();
    }
  }

  /// pause channel, call [start] to resume channel
  ///
  /// do nothing if [setSource] hasn't been called
  void pause() {
    if (_fstream == null) return;

    if (wasapiExclusive) {
      return _pause_wasapiExclusive();
    }

    if (_bass.BASS_ChannelPause(_fstream!) == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_DECODE:
          throw const FormatException(
              "handle is a decoding channel, so cannot be played or paused.");
        case BASS.BASS_ERROR_NOPLAY:
          throw const FormatException("The channel is not playing.");
      }
    }

    _playerStateStreamController.add(playerState);
    _positionUpdater?.cancel();
  }

  /// set channel's position to given [position]
  /// don't check if the position is valid.
  ///
  /// do nothing if [setSource] hasn't been called
  void seek(double position) {
    if (_fstream == null) return;

    if (_bass.BASS_ChannelSetPosition(
          _fstream!,
          _bass.BASS_ChannelSeconds2Bytes(_fstream!, position),
          BASS.BASS_POS_BYTE,
        ) ==
        0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          throw const FormatException("handle is not a valid channel.");
        case BASS.BASS_ERROR_NOTFILE:
          throw const FormatException("The stream is not a file stream.");
        case BASS.BASS_ERROR_POSITION:
          throw const FormatException(
              "The requested position is invalid, eg. it is beyond the end or the download has not yet reached it.");
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "The requested mode is not available. Invalid flags are ignored and do not result in this error.");
        case BASS.BASS_ERROR_UNKNOWN:
          throw const FormatException("Some other mystery problem!");
      }
    }
  }

  /// It is not necessary to individually free the samples/streams/musics
  /// as these are all automatically freed after [setSource] or [free] is called.
  ///
  /// do nothing if [setSource] hasn't been called
  void freeFStream() {
    if (_fstream == null) return;

    if (_bass.BASS_StreamFree(_fstream!) == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_HANDLE:
          LOGGER.w("StreamFree is called on a invalid handle.");
          break;
        case BASS.BASS_ERROR_NOTAVAIL:
          throw const FormatException(
              "Device streams (STREAMPROC_DEVICE) cannot be freed.");
      }
    }
    
    _fstream = null;
    _fPath = null;
    
    // Release memory allocated for file data if it exists
    if (_fileData != null) {
      ffi.malloc.free(_fileData!);
      _fileData = null;
    }
    
    if (_positionUpdater != null) {
      _positionUpdater!.cancel();
      _positionUpdater = null;
    }
  }

  /// Frees all resources used by the output device,
  /// including all its samples, streams and MOD musics.
  ///
  /// Also free the bass.dll.
  void free() {
    // 仅在wasapiExclusive为true且_bassWasapi已初始化时调用BASS_WASAPI_Free
    if (wasapiExclusive && PlatformHelper.supportsWasapi()) {
      _bassWasapi.BASS_WASAPI_Free();
    }

    if (_bass.BASS_Free() == 0) {
      switch (_bass.BASS_ErrorGetCode()) {
        case BASS.BASS_ERROR_INIT:
          LOGGER.w("BASS_Free is called before BASS_Init complete normally.");
          break;
        case BASS.BASS_ERROR_BUSY:
          throw const FormatException(
              "The device is currently being reinitialized.");
      }
    }

    // 仅在Windows平台上关闭_bassWasapiLib（因为它只在Windows上初始化）
    if (PlatformHelper.supportsWasapi()) {
      _bassWasapiLib.close();
    }
    _bassLib.close();

    _positionUpdater?.cancel();
    _playerStateStreamController.close();
    _positionStreamController.close();
  }
}
