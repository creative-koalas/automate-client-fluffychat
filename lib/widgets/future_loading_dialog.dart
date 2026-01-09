import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';

import 'package:psygo/l10n/l10n.dart';
import 'package:psygo/utils/localized_exception_extension.dart';
import 'package:psygo/widgets/adaptive_dialogs/adaptive_dialog_action.dart';

/// Displays a loading dialog which reacts to the given [future]. The dialog
/// will be dismissed and the value will be returned when the future completes.
/// If an error occured, then [onError] will be called and this method returns
/// null.
Future<Result<T>> showFutureLoadingDialog<T>({
  required BuildContext context,
  Future<T> Function()? future,
  Future<T> Function(void Function(double?) setProgress)? futureWithProgress,
  String? title,
  String? backLabel,
  bool barrierDismissible = false,
  bool delay = true,
  ExceptionContext? exceptionContext,
  bool ignoreError = false,
}) async {
  assert(future != null || futureWithProgress != null);
  final onProgressStream = StreamController<double?>();
  final futureExec =
      futureWithProgress?.call(onProgressStream.add) ?? future!();
  final resultFuture = ResultFuture(futureExec);

  if (delay) {
    var i = 3;
    while (i > 0) {
      final result = resultFuture.result;
      if (result != null) {
        if (result.isError) break;
        return result;
      }
      await Future.delayed(const Duration(milliseconds: 100));
      i--;
    }
  }

  final result = await showAdaptiveDialog<Result<T>>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (BuildContext context) => LoadingDialog<T>(
      future: futureExec,
      title: title,
      backLabel: backLabel,
      exceptionContext: exceptionContext,
      onProgressStream: onProgressStream.stream,
    ),
  );
  return result ??
      Result.error(
        Exception('FutureDialog canceled'),
        StackTrace.current,
      );
}

class LoadingDialog<T> extends StatefulWidget {
  final String? title;
  final String? backLabel;
  final Future<T> future;
  final ExceptionContext? exceptionContext;
  final Stream<double?> onProgressStream;

  const LoadingDialog({
    super.key,
    required this.future,
    this.title,
    this.backLabel,
    this.exceptionContext,
    required this.onProgressStream,
  });

  @override
  LoadingDialogState<T> createState() => LoadingDialogState<T>();
}

class LoadingDialogState<T> extends State<LoadingDialog> {
  Object? exception;
  StackTrace? stackTrace;

  @override
  void initState() {
    super.initState();
    widget.future.then(
      (result) => Navigator.of(context).pop<Result<T>>(Result.value(result)),
      onError: (e, s) => setState(() {
        exception = e;
        stackTrace = s;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exception = this.exception;
    final titleLabel = exception != null
        ? exception.toLocalizedString(context, widget.exceptionContext)
        : widget.title ?? L10n.of(context).loadingPleaseWait;

    return AlertDialog.adaptive(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      title: exception == null
          ? null
          : Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withAlpha(60),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.error,
                size: 40,
              ),
            ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (exception == null) ...[
              // 加载动画容器
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(40),
                  shape: BoxShape.circle,
                ),
                child: StreamBuilder(
                  stream: widget.onProgressStream,
                  builder: (context, snapshot) => SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: snapshot.data,
                      strokeWidth: 3,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            Text(
              titleLabel,
              maxLines: 4,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: exception == null ? 15 : 14,
                fontWeight: exception == null ? FontWeight.w500 : FontWeight.normal,
                color: exception == null
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
      actions: exception == null
          ? null
          : [
              AdaptiveDialogAction(
                onPressed: () => Navigator.of(context).pop<Result<T>>(
                  Result.error(
                    exception,
                    stackTrace,
                  ),
                ),
                child: Text(
                  widget.backLabel ?? L10n.of(context).close,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
    );
  }
}

extension DeprecatedApiAccessExtension<T> on Result<T> {
  T? get result => asValue?.value;

  Object? get error => asError?.error;
}
