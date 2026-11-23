import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Coriander Player 统一玻璃参数预设（单一真相源）
///
/// 规则：**页面与组件只允许引用本文件的预设，不允许自己 new `LiquidGlassSettings`**。
/// 所有预设都接受 `isDark`，浅色/深色共用同一套结构参数，只换 glassColor。
/// 调用处统一传 `Theme.of(context).brightness == Brightness.dark`。
///
/// 参考来源：
/// - liquid_glass_widgets/example/lib/constants/glass_settings.dart
/// - artist_detail_page_v3 已在真机验证的交互参数
/// - iOS 26 Liquid Glass 开发手册

// ─── 通用常量 ──────────────────────────────────────────

/// Apple 标准光源角度：135°（左上方），所有表面统一
const double kAppleLightAngle = 0.75 * math.pi;

/// 导航按钮玻璃质量
const navButtonQuality = GlassQuality.premium;

/// 底部导航栏高度
const double kBarHeight = 64.0;

/// 底部导航栏水平内边距
const double kBarPaddingH = 20.0;

/// 底部导航栏垂直内边距
const double kBarPaddingV = 16.0;

/// Tab 间距
const double kBarSpacing = 8.0;

/// 调用处取明暗的统一入口
bool glassIsDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

// ─── 内部构造：结构参数统一，仅 tint 随明暗变化 ─────────────

LiquidGlassSettings _settings({
  required Color glassColor,
  double blur = 3,
  double thickness = 30,
  double ambientStrength = 1,
  double lightIntensity = 0.6,
  double chromaticAberration = 0.3,
  double refractiveIndex = 1.59,
  double saturation = 0.7,
  GlassSpecularSharpness specularSharpness = GlassSpecularSharpness.medium,
}) =>
    LiquidGlassSettings(
      blur: blur,
      thickness: thickness,
      ambientStrength: ambientStrength,
      lightIntensity: lightIntensity,
      lightAngle: kAppleLightAngle,
      chromaticAberration: chromaticAberration,
      refractiveIndex: refractiveIndex,
      saturation: saturation,
      glassColor: glassColor,
      specularSharpness: specularSharpness,
    );

/// 浅色用白玻璃、深色用黑玻璃的取值助手
Color _tint(bool isDark, {required double lightAlpha, double darkAlpha = 0}) {
  if (isDark) {
    return Color.fromRGBO(28, 28, 30, darkAlpha == 0 ? lightAlpha : darkAlpha);
  }
  return Color.fromRGBO(242, 242, 247, lightAlpha);
}

// ─── 导航 / 栏位 ────────────────────────────────────────

/// 导航按钮（AppBar 按钮、返回按钮、更多按钮等）
/// 浅色 16% 白；深色 14% 白（在深背景上不过曝）
LiquidGlassSettings navButtonSettings(bool isDark) => _settings(
      glassColor:
          isDark ? const Color(0x24FFFFFF) : const Color(0x29FFFFFF),
      specularSharpness: GlassSpecularSharpness.medium,
    );

/// 顶部栏整条（详情页/设置页 AppBar 底衬）
LiquidGlassSettings topBarSettings(bool isDark) => _settings(
      glassColor: _tint(isDark, lightAlpha: 0.67),
      specularSharpness: GlassSpecularSharpness.medium,
    );

/// 底部 Tab 栏
LiquidGlassSettings tabBarSettings(bool isDark) => topBarSettings(isDark);

/// 半透明胶囊（返回/更多/底部分页条）；比 navButton 更透
LiquidGlassSettings pillSettings(bool isDark) => _settings(
      glassColor:
          isDark ? const Color(0x1FFFFFFF) : const Color(0x1FFFFFFF),
      specularSharpness: GlassSpecularSharpness.medium,
    );

/// 搜索胶囊（壳层 SearchPill / 搜索结果页底部输入框）
LiquidGlassSettings searchPillSettings(bool isDark) => _settings(
      glassColor: _tint(isDark, lightAlpha: 0.8),
      specularSharpness: GlassSpecularSharpness.medium,
    );

/// 迷你播放条 Pill
LiquidGlassSettings playBarPillSettings(bool isDark) => _settings(
      glassColor: _tint(isDark, lightAlpha: 0.8),
    );

// ─── 内容层 ────────────────────────────────────────────

/// 卡片容器
LiquidGlassSettings cardSettings(bool isDark) => _settings(
      blur: 10,
      thickness: 10,
      glassColor:
          isDark ? const Color(0x1FFFFFFF) : const Color(0x1FFFFFFF),
      lightIntensity: 0.7,
      ambientStrength: 0.4,
      saturation: 1.2,
      refractiveIndex: 0.7,
      chromaticAberration: 0.0,
    );

/// 列表项 — 轻量玻璃
LiquidGlassSettings listTileSettings(bool isDark) => _settings(
      blur: 4,
      thickness: 10,
      glassColor:
          isDark ? const Color(0x14FFFFFF) : const Color(0x0FFFFFFF),
      lightIntensity: 0.5,
      ambientStrength: 0.2,
      saturation: 1.0,
      refractiveIndex: 0.7,
      chromaticAberration: 0.0,
    );

/// 设置项
LiquidGlassSettings settingsTileSettings(bool isDark) => _settings(
      blur: 10,
      thickness: 10,
      glassColor:
          isDark ? const Color(0x2EFFFFFF) : const Color(0x33FFFFFF),
      lightIntensity: 0.7,
      ambientStrength: 0.3,
      saturation: 0.0,
      refractiveIndex: 0.7,
      chromaticAberration: 0.0,
    );

/// 搜索栏 / 输入框
LiquidGlassSettings searchSettings(bool isDark) => _settings(
      blur: 20,
      thickness: 10,
      glassColor:
          isDark ? const Color(0x1FFFFFFF) : const Color(0x1FFFFFFF),
      lightIntensity: 0.7,
      ambientStrength: 0.4,
      saturation: 1.2,
      refractiveIndex: 0.7,
      chromaticAberration: 0.0,
    );

/// 模态底部表单：深色下需要更高不透明度保证文字可读
LiquidGlassSettings sheetSettings(bool isDark) => _settings(
      blur: 10,
      thickness: 10,
      glassColor:
          isDark ? const Color(0xE61C1C1E) : const Color(0x1FFFFFFF),
      lightIntensity: 0.7,
      ambientStrength: 0.4,
      saturation: 1.2,
      refractiveIndex: 0.15,
      chromaticAberration: 0.0,
    );

/// 模态对话框
LiquidGlassSettings dialogSettings(bool isDark) => _settings(
      blur: 10,
      thickness: 10,
      glassColor:
          isDark ? const Color(0xD91C1C1E) : const Color(0x1FFFFFFF),
      lightIntensity: 0.7,
      ambientStrength: 0.4,
      saturation: 1.2,
      refractiveIndex: 0.15,
      chromaticAberration: 0.0,
    );

/// 按钮组（GlassButtonGroup）
LiquidGlassSettings buttonGroupSettings(bool isDark) => _settings(
      glassColor:
          isDark ? const Color(0x2EFFFFFF) : const Color(0x3DFFFFFF),
      specularSharpness: GlassSpecularSharpness.medium,
    );

// ─── 共享背景（供 GlassAppShell 和所有页面使用）───────────────

/// 统一的 Glass 版页面背景（与 Artist V3 相同风格的渐变色 + 暗化层）
///
/// 所有使用 GlassScaffold 的页面都应该使用这个函数构建背景，
/// 确保视觉一致性并避免双层 GlassScaffold 导致的白色条带问题。
Widget buildGlassBackground(ColorScheme scheme) {
  final isDark = scheme.brightness == Brightness.dark;
  return Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(color: scheme.secondaryContainer),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.primary.withValues(alpha: 0.18),
                scheme.secondaryContainer.withValues(alpha: 0.55),
                scheme.surface.withValues(alpha: 0.9),
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.12),
                    ]
                  : [
                      Colors.black.withValues(alpha: 0.22),
                      Colors.black.withValues(alpha: 0.06),
                    ],
            ),
          ),
        ),
      ),
    ],
  );
}
