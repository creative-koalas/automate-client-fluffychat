import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';

import 'package:matrix/matrix.dart';

import 'package:psygo/config/themes.dart';
import 'package:psygo/utils/platform_infos.dart';
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
  final Color? statusDotColor;
  final bool showShadow;
  final bool showWorkingPulse;
  final Color? workingPulseColor;

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
    this.statusDotColor,
    this.showShadow = false,
    this.showWorkingPulse = false,
    this.workingPulseColor,
    super.key,
  });

  Widget _buildStatusDot(
    BuildContext context,
    ThemeData theme,
    Color dotColor,
  ) {
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
  }

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
      clipBehavior: Clip.none,
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
              cacheKey: PlatformInfos.isMacOS
                  ? '${mxContent}_${size}_avatar_full_macos'
                  : '${mxContent}_${size}_avatar_crop',
              uri: noPic ? null : mxContent,
              fit: BoxFit.cover,
              width: size,
              height: size,
              // Full-size avatars on macOS avoid the softness difference
              // between list thumbnails and the full-screen viewer.
              isThumbnail: !PlatformInfos.isMacOS,
              // Avatars are always rendered into a square box. Request a cropped
              // square thumbnail from the homeserver so Flutter does not upscale
              // a smaller "scaled" thumbnail on desktop retina displays.
              thumbnailMethod: ThumbnailMethod.crop,
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
        if (statusDotColor != null)
          _buildStatusDot(
            context,
            theme,
            statusDotColor!,
          )
        else if (presenceUserId != null)
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
              return _buildStatusDot(context, theme, dotColor);
            },
          ),
      ],
    );
    final shouldAnimatePulse =
        showWorkingPulse && !(MediaQuery.maybeOf(context)?.disableAnimations ?? false);
    final avatarWithPulse = showWorkingPulse
        ? _AvatarWorkingDots(
            size: size,
            color: workingPulseColor ?? theme.colorScheme.tertiary,
            animated: shouldAnimatePulse,
            child: container,
          )
        : container;

    if (onTap == null) return avatarWithPulse;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: avatarWithPulse,
      ),
    );
  }
}

class _AvatarWorkingDots extends StatelessWidget {
  final double size;
  final Color color;
  final bool animated;
  final Widget child;

  const _AvatarWorkingDots({
    required this.size,
    required this.color,
    required this.animated,
    required this.child,
  });

  Widget _buildStaticDots() {
    final dotSizes = [
      (size * 0.12).clamp(4.4, 7.4).toDouble(),
      (size * 0.19).clamp(7.4, 11.6).toDouble(),
      (size * 0.26).clamp(10.2, 15.4).toDouble(),
    ];
    final dotTones = [0.70, 0.84, 0.96];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 0; i < dotSizes.length; i++)
          Container(
            width: dotSizes[i],
            height: dotSizes[i],
            decoration: BoxDecoration(
              color: color.withValues(alpha: dotTones[i]),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  Widget _buildDots(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final badgeWidth = size * 0.58;
    final badgeHeight = size * 0.27;
    final shellColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.68)
        : theme.colorScheme.surface.withValues(alpha: 0.92);
    final borderColor = isDark
        ? theme.colorScheme.onSurface.withValues(alpha: 0.16)
        : Colors.black.withValues(alpha: 0.06);

    return IgnorePointer(
        child: Container(
          width: badgeWidth,
          height: badgeHeight,
          padding: EdgeInsets.symmetric(
            horizontal: badgeWidth * 0.11,
            vertical: badgeHeight * 0.08,
          ),
          decoration: BoxDecoration(
            color: shellColor,
            borderRadius: BorderRadius.circular(badgeHeight * 0.55),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.10),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: animated
              ? Center(
                  child: LoadingAnimationWidget.staggeredDotsWave(
                    color: color,
                    size: (badgeHeight * 1.90).clamp(16.0, 34.0),
                  ),
                )
              : _buildStaticDots(),
        ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dotsHeight = size * 0.22;
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size + dotsHeight * 0.75,
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: 0,
              child: SizedBox(
                width: size,
                height: size,
                child: child,
              ),
            ),
            Positioned(
              bottom: 0,
              child: _buildDots(context),
            ),
          ],
        ),
      ),
    );
  }
}
