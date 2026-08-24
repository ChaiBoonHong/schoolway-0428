import 'package:schoolway/core/theme/schoolway_theme.dart';
import 'package:flutter/material.dart';

Future<T?> showAppModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  Color? backgroundColor,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: backgroundColor ?? SchoolWayTheme.transparent,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    builder: builder,
  );
}
