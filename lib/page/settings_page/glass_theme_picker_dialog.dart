import 'package:coriander_player/app_settings.dart';
import 'package:coriander_player/utils.dart';
import 'package:coriander_player/hotkeys_helper.dart';
import 'package:coriander_player/glass_theme/glass_dialog.dart';
import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';

class GlassThemePickerDialog extends StatefulWidget {
  const GlassThemePickerDialog({super.key});

  @override
  State<GlassThemePickerDialog> createState() => _GlassThemePickerDialogState();
}

class _GlassThemePickerDialogState extends State<GlassThemePickerDialog> {
  var selectedColor = Color(AppSettings.instance.defaultTheme);
  late final rgbHexTextEditingController = TextEditingController(
    text: selectedColor.toRGBHexString(),
  );

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: "主题选择器",
      width: 350.0,
      actions: [
        GlassDialogButton(
          label: "取消",
          onTap: () => Navigator.pop(context),
        ),
        GlassDialogButton(
          label: "确定",
          primary: true,
          onTap: () {
            Navigator.pop(context, selectedColor);
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Focus(
            onFocusChange: HotkeysHelper.onFocusChanges,
            child: TextField(
              autofocus: true,
              controller: rgbHexTextEditingController,
              onChanged: (value) {
                final c = fromRGBHexString(value);
                if (c != null) {
                  setState(() {
                    selectedColor = c;
                  });
                }
              },
              decoration: const InputDecoration(
                labelText: "Hex RGB",
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 16.0),
          SizedBox(
            height: 400,
            child: ColorWheelPicker(
              color: selectedColor,
              onChanged: (color) {
                setState(() {
                  selectedColor = color;
                });
                rgbHexTextEditingController.text = color.toRGBHexString();
              },
              onWheel: (isWheel) {},
            ),
          ),
        ],
      ),
    );
  }
}
