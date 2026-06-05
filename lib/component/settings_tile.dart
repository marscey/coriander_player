import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.description,
    this.subtitle,
    required this.action,
  });

  final String description;
  final String? subtitle;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                description,
                style: TextStyle(color: scheme.onSurface, fontSize: 18.0),
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    subtitle!,
                    style: TextStyle(
                      color: scheme.outline,
                      fontSize: 13.0,
                      height: 1.3,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 16.0),
        action,
      ],
    );
  }
}
