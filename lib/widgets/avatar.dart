import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/utils/string_color.dart';
import 'package:psygo/widgets/mxc_image.dart';
import 'package:psygo/widgets/presence_builder.dart';

class Avatar extends StatelessWidget {
  final Uri? mxContent;
  final String? name;
  final double size;
  final void Function()? onTap;
  static const double defaultSize = 48;
  final Client? client;
  final String? presenceUserId;
  final Color? presenceBackgroundColor;
  final BorderRadius? borderRadius;
  final IconData? icon;
  final BorderSide? border;
  final Color? backgroundColor;
  final Color? textColor;
  final bool showShadow;

  const Avatar({
    this.mxContent,
    this.name,
    this.size = defaultSize,
    this.onTap,
    this.client,
    this.presenceUserId,
    this.presenceBackgroundColor,
    this.borderRadius,
    this.border,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.showShadow = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final name = this.name;
    final fallbackLetters =
        name == null || name.isEmpty ? '@' : name.substring(0, 1);

    final noPic = mxContent == null ||
        mxContent.toString().isEmpty ||
        mxContent.toString() == 'null';
    final borderRadius = this.borderRadius ?? BorderRadius.circular(size / 2);
    final presenceUserId = this.presenceUserId;
    final avatarColor = backgroundColor ?? name?.lightColorAvatar;
    final container = Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            boxShadow: showShadow
                ? FluffyThemes.shadow(
                    context,
                    elevation: FluffyThemes.elevationSm,
                  )
                : null,
          ),
          child: Material(
            color: theme.brightness == Brightness.light
                ? Colors.white
                : Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: borderRadius,
              side: border ?? BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: MxcImage(
              client: client,
              borderRadius: borderRadius,
              key: ValueKey(mxContent.toString()),
              cacheKey: '${mxContent}_$size',
              uri: noPic ? null : mxContent,
              fit: BoxFit.cover,
              width: size,
              height: size,
              placeholder: (_) => noPic
                  ? Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            avatarColor ?? theme.colorScheme.primary,
                            (avatarColor ?? theme.colorScheme.primary)
                                .withAlpha(200),
                          ],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        fallbackLetters,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'RobotoMono',
                          color: textColor ?? Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: (size / 2.5).roundToDouble(),
                          shadows: [
                            Shadow(
                              color: Colors.black.withAlpha(30),
                              blurRadius: FluffyThemes.elevationSm,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    )
                  : TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: FluffyThemes.durationSlow,
                      curve: FluffyThemes.curveSharp,
                      builder: (context, opacity, child) => Opacity(
                        opacity: opacity,
                        child: child,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                              theme.colorScheme.surfaceContainerHigh.withAlpha(80),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.person_2_rounded,
                            color: theme.colorScheme.tertiary.withAlpha(150),
                            size: size / 1.5,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        if (presenceUserId != null)
          PresenceBuilder(
            client: client,
            userId: presenceUserId,
            builder: (context, presence) {
              if (presence == null ||
                  (presence.presence == PresenceType.offline &&
                      presence.lastActiveTimestamp == null)) {
                return const SizedBox.shrink();
              }
              final dotColor = presence.presence.isOnline
                  ? Colors.green
                  : presence.presence.isUnavailable
                      ? Colors.orange
                      : Colors.grey;
              return Positioned(
                bottom: -3,
                right: -3,
                child: AnimatedContainer(
                  duration: FluffyThemes.durationFast,
                  curve: FluffyThemes.curveBounce,
                  width: FluffyThemes.iconSizeXs,
                  height: FluffyThemes.iconSizeXs,
                  decoration: BoxDecoration(
                    color: presenceBackgroundColor ?? theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(FluffyThemes.radiusFull),
                    boxShadow: FluffyThemes.shadow(
                      context,
                      elevation: FluffyThemes.elevationXs,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: AnimatedContainer(
                    duration: FluffyThemes.durationFast,
                    curve: FluffyThemes.curveStandard,
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      borderRadius: BorderRadius.circular(FluffyThemes.radiusFull),
                      border: Border.all(
                        width: 1,
                        color: theme.colorScheme.surface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
    if (onTap == null) return container;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: container,
      ),
    );
  }
}
