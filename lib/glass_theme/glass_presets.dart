import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

/// Coriander Player 统一玻璃参数预设
///
/// 所有 Glass 版页面的组件参数统一从此处引用，
/// 避免各文件各自定义，方便全局调整。
///
/// 参考来源：
/// - liquid_glass_widgets/example/lib/constants/glass_settings.dart
/// - artist_detail_page_v3.dart 已验证参数
/// - iOS 26 Liquid Glass 开发手册

// ─── 通用常量 ──────────────────────────────────────────

/// Apple 标准光源角度：135°（左上方），所有表面统一
const double kAppleLightAngle = 0.75 * math.pi;

/// 导航按钮玻璃质量（与 Artist V3 一致）
const navButtonQuality = GlassQuality.premium;

/// 底部导航栏高度
const double kBarHeight = 64.0;

/// 底部导航栏水平内边距
const double kBarPaddingH = 20.0;

/// 底部导航栏垂直内边距
const double kBarPaddingV = 16.0;

/// Tab 间距
const double kBarSpacing = 8.0;

// ─── 玻璃设置预设 ──────────────────────────────────────

/// 导航按钮（AppBar 按钮、返回按钮等）
/// 参考 artist_detail_page_v3._navButtonSettings
/// glassColor alpha 0x3D(24%) → 0x29(16%)：更通透，保留反射/色散不变
const navButtonSettings = LiquidGlassSettings(
  blur: 3,
  thickness: 30,
  ambientStrength: 1,
  lightIntensity: 0.6,
  lightAngle: kAppleLightAngle,
  chromaticAberration: 0.3,
  refractiveIndex: 1.59,
  saturation: 0.7,
  glassColor: Color(0x29FFFFFF), // ~16% alpha，更通透
  specularSharpness: GlassSpecularSharpness.medium,
);

/// 底部导航栏 — 参考 RecommendedGlassSettings.bottomBar + artist V3
LiquidGlassSettings bottomBarSettings(bool isDark) => LiquidGlassSettings(
      glassColor: isDark ? const Color(0xAA1C1C1E) : const Color(0xAAF2F2F7),
      thickness: 30,
      blur: 3,
      chromaticAberration: 0.3,
      lightAngle: kAppleLightAngle,
      lightIntensity: 0.6,
      ambientStrength: 1,
      refractiveIndex: 1.59,
      saturation: 0.7,
      specularSharpness: GlassSpecularSharpness.medium,
    );

/// 迷你播放条 Pill — 参考 artist V3 _PlayBarPill
LiquidGlassSettings playBarPillSettings(bool isDark) => LiquidGlassSettings(
      glassColor: isDark ? const Color(0xCC1C1C1E) : const Color(0xCCF2F2F7),
      thickness: 30,
      blur: 3,
      lightIntensity: 0.6,
      chromaticAberration: 0.3,
      refractiveIndex: 1.59,
      saturation: 0.7,
      ambientStrength: 1,
      lightAngle: kAppleLightAngle,
    );

/// 卡片容器 — 参考 RecommendedGlassSettings.overlay
const cardSettings = LiquidGlassSettings(
  blur: 10,
  thickness: 10,
  glassColor: Color.fromRGBO(255, 255, 255, 0.12),
  lightAngle: kAppleLightAngle,
  lightIntensity: 0.7,
  ambientStrength: 0.4,
  saturation: 1.2,
  refractiveIndex: 0.7,
  chromaticAberration: 0.0,
);

/// 列表项 — 轻量玻璃效果
const listTileSettings = LiquidGlassSettings(
  blur: 4,
  thickness: 10,
  glassColor: Color.fromRGBO(255, 255, 255, 0.06),
  lightAngle: kAppleLightAngle,
  lightIntensity: 0.5,
  ambientStrength: 0.2,
  saturation: 1.0,
  refractiveIndex: 0.7,
  chromaticAberration: 0.0,
);

/// 设置项 — 参考 RecommendedGlassSettings.interactive
const settingsTileSettings = LiquidGlassSettings(
  blur: 10,
  thickness: 10,
  glassColor: Color.fromRGBO(255, 255, 255, 0.2),
  lightAngle: kAppleLightAngle,
  lightIntensity: 0.7,
  ambientStrength: 0.3,
  saturation: 0.0,
  refractiveIndex: 0.7,
  chromaticAberration: 0.0,
);

/// 搜索栏 — 参考 RecommendedGlassSettings.input
const searchSettings = LiquidGlassSettings(
  blur: 20,
  thickness: 10,
  glassColor: Color.fromRGBO(255, 255, 255, 0.12),
  lightAngle: kAppleLightAngle,
  lightIntensity: 0.7,
  ambientStrength: 0.4,
  saturation: 1.2,
  refractiveIndex: 0.7,
  chromaticAberration: 0.0,
);

/// 模态弹窗/底部表单 — 参考 RecommendedGlassSettings.sheet
const sheetSettings = LiquidGlassSettings(
  blur: 10,
  thickness: 10,
  glassColor: Color.fromRGBO(255, 255, 255, 0.12),
  lightAngle: kAppleLightAngle,
  lightIntensity: 0.7,
  ambientStrength: 0.4,
  saturation: 1.2,
  refractiveIndex: 0.15,
  chromaticAberration: 0.0,
);

/// 按钮组 — 参考 artist V3 GlassButtonGroup
const buttonGroupSettings = LiquidGlassSettings(
  blur: 3,
  thickness: 30,
  ambientStrength: 1,
  lightIntensity: 0.6,
  lightAngle: kAppleLightAngle,
  chromaticAberration: 0.3,
  refractiveIndex: 1.59,
  saturation: 0.7,
  glassColor: Color(0x3DFFFFFF),
  specularSharpness: GlassSpecularSharpness.medium,
);

// ─── 共享背景（供 GlassAppShell 和所有页面使用）───────────────

/// 统一的 Glass 版页面背景（与 Artist V3 相同风格的渐变色 + 暗化层）
///
/// 所有使用 GlassScaffold 的页面都应该使用这个函数构建背景，
/// 确保视觉一致性并避免双层 GlassScaffold 导致的白色条带问题。
Widget buildGlassBackground(ColorScheme scheme) {
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
              colors: [
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