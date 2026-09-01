import 'package:flutter/material.dart';

import '../../config/app_theme.dart' show AppColors;

class ComposerActionButton {
  final Key? key;
  final IconData icon;
  final String title;
  final VoidCallback onPressed;
  final Color color;
  final bool visible;

  const ComposerActionButton({
    this.key,
    required this.icon,
    required this.title,
    required this.onPressed,
    this.color = AppColors.secondary,
    this.visible = true,
  });
}

class ComposerActionBar extends StatelessWidget {
  final List<ComposerActionButton> buttons;

  const ComposerActionBar({super.key, required this.buttons});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < buttons.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Visibility(
                visible: buttons[i].visible,
                child: OutlinedButton.icon(
                  key: buttons[i].key,
                  icon: Icon(
                    buttons[i].icon,
                    color: buttons[i].color,
                    size: 12,
                  ),
                  label: Text(
                    buttons[i].title,
                    style: TextStyle(
                      color: buttons[i].color,
                      fontSize: 12,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.withOpacity(0.5)),
                    foregroundColor: buttons[i].color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  onPressed: buttons[i].onPressed,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
