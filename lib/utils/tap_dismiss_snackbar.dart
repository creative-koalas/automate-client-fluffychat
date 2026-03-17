import 'package:flutter/material.dart';

void showTapDismissSnackBar(
  BuildContext context,
  String message, {
  Duration? duration,
  Color? backgroundColor,
  SnackBarBehavior? behavior,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      duration: duration ?? const Duration(seconds: 4),
      backgroundColor: backgroundColor,
      behavior: behavior,
      content: InkWell(
        onTap: messenger.hideCurrentSnackBar,
        child: Text(message),
      ),
    ),
  );
}
