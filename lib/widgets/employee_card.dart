import 'package:flutter/material.dart';

import 'package:psygo/l10n/l10n.dart';

import '../models/agent.dart';
import 'custom_network_image.dart';

/// 员工卡片组件
/// 显示员工头像、名称、状态徽章、工作状态
/// 入职/离职状态会显示脉冲动画效果
class EmployeeCard extends StatefulWidget {
  final Agent employee;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isOffboarding;

  const EmployeeCard({
    super.key,
    required this.employee,
    this.onTap,
    this.onLongPress,
    this.isOffboarding = false,
  });

  @override
  State<EmployeeCard> createState() => _EmployeeCardState();
}

class _EmployeeCardState extends State<EmployeeCard>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _typewriterController;
  static const Duration _onboardingLineDuration = Duration(seconds: 7);
  static const int _onboardingTypingMs = 2700;
  static const int _onboardingHoldFullMs = 1300;
  static const int _onboardingDeletingMs = 2600;
  static const int _onboardingHoldEmptyMs = 400;
  int _onboardingLineIndex = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _typewriterController = AnimationController(
      duration: _onboardingLineDuration,
      vsync: this,
    )..addStatusListener(_handleTypewriterStatus);

    // 入职/离职状态才启动动画
    if (_shouldPulse(widget)) {
      _pulseController.repeat(reverse: true);
    }
    if (_shouldTypewriter(widget)) {
      _startOnboardingTypewriter();
    }
  }

  @override
  void didUpdateWidget(EmployeeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldShouldPulse = _shouldPulse(oldWidget);
    final newShouldPulse = _shouldPulse(widget);
    if (oldShouldPulse != newShouldPulse) {
      if (newShouldPulse) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    }

    final oldShouldTypewriter = _shouldTypewriter(oldWidget);
    final newShouldTypewriter = _shouldTypewriter(widget);
    if (oldShouldTypewriter != newShouldTypewriter) {
      if (newShouldTypewriter) {
        _startOnboardingTypewriter();
      } else {
        _stopOnboardingTypewriter(resetLine: true);
      }
    }
  }

  @override
  void dispose() {
    _stopOnboardingTypewriter(resetLine: false);
    _typewriterController
      ..removeStatusListener(_handleTypewriterStatus)
      ..dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final isOffboarding = widget.isOffboarding;
    final isOnboarding = !widget.employee.isReady && !isOffboarding;

    // 将动画部分分离，只在需要时才使用 AnimatedBuilder
    if (isOnboarding || isOffboarding) {
      return AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          // 入职中状态时有微妙的发光效果
          final glowOpacity = _pulseAnimation.value * 0.3;
          final cardColor = isOffboarding
              ? Color.lerp(
                  theme.colorScheme.surfaceContainerLow,
                  theme.colorScheme.errorContainer.withValues(alpha: 0.3),
                  _pulseAnimation.value * 0.4,
                )
              : Color.lerp(
                  theme.colorScheme.surfaceContainerLow,
                  Colors.orange.withValues(alpha: 0.08),
                  _pulseAnimation.value * 0.3,
                );
          final borderColor = isOffboarding
              ? Color.lerp(
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                  theme.colorScheme.error.withValues(alpha: 0.45),
                  _pulseAnimation.value * 0.6,
                )!
              : Color.lerp(
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                  Colors.orange.withValues(alpha: 0.4),
                  _pulseAnimation.value * 0.5,
                )!;

          return _buildCardContainer(
            context,
            theme,
            l10n,
            isOnboarding: isOnboarding,
            isOffboarding: isOffboarding,
            glowOpacity: glowOpacity,
            cardColor: cardColor,
            borderColor: borderColor,
          );
        },
      );
    }

    // 非入职状态：静态渲染，无需动画
    return _buildCardContainer(
      context,
      theme,
      l10n,
      isOnboarding: false,
      isOffboarding: false,
      cardColor: theme.colorScheme.surfaceContainerLow,
      borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
    );
  }

  bool _shouldPulse(EmployeeCard card) {
    return card.isOffboarding || !card.employee.isReady;
  }

  bool _shouldTypewriter(EmployeeCard card) {
    return !card.isOffboarding && !card.employee.isReady;
  }

  void _startOnboardingTypewriter() {
    _onboardingLineIndex = 0;
    _typewriterController
      ..stop()
      ..reset()
      ..forward();
  }

  void _stopOnboardingTypewriter({required bool resetLine}) {
    _typewriterController
      ..stop()
      ..reset();
    if (!resetLine) return;
    _onboardingLineIndex = 0;
  }

  void _handleTypewriterStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_shouldTypewriter(widget)) {
      return;
    }
    if (!mounted) return;
    final lines =
        _onboardingLines(Localizations.localeOf(context).languageCode);
    if (lines.isEmpty) return;
    final maxIndex = lines.length - 1;

    final nextLineIndex =
        _onboardingLineIndex < maxIndex ? _onboardingLineIndex + 1 : maxIndex;
    if (nextLineIndex != _onboardingLineIndex) {
      setState(() {
        _onboardingLineIndex = nextLineIndex;
      });
    }
    _typewriterController
      ..reset()
      ..forward();
  }

  List<String> _onboardingLines(String languageCode) {
    if (languageCode == 'zh' || languageCode == 'yue') {
      return const [
        '请 IT 同事开通工作账号…🪪',
        '抱着新电脑去工位报到…💻',
        '拆封新电脑，贴上专属工牌…✨',
        '启动工作环境，准备开工…🚀',
      ];
    }
    return const [
      'Open work account with IT… 🪪',
      'Carry the new laptop to the desk… 💻',
      'Unbox laptop and add a name tag… ✨',
      'Boot work environment, ready to roll! 🚀',
    ];
  }

  int _typewriterElapsedMs() {
    return (_typewriterController.value *
            _onboardingLineDuration.inMilliseconds)
        .round();
  }

  List<InlineSpan> _onboardingTypewriterSpans(
    L10n l10n,
    TextStyle? textStyle,
  ) {
    if (!_shouldTypewriter(widget)) {
      return [TextSpan(text: l10n.employeeOnboarding)];
    }
    final lines =
        _onboardingLines(Localizations.localeOf(context).languageCode);
    if (lines.isEmpty) {
      return [TextSpan(text: l10n.employeeOnboarding)];
    }
    final line = lines[_onboardingLineIndex.clamp(0, lines.length - 1)];
    final runes = line.runes.toList(growable: false);
    final runeCount = runes.length;
    if (runeCount == 0) {
      return const [TextSpan(text: '')];
    }

    final elapsedMs = _typewriterElapsedMs();
    final baseColor = textStyle?.color ?? Colors.orange.shade800;

    if (elapsedMs < _onboardingTypingMs) {
      final perRuneMs = _onboardingTypingMs / runeCount;
      final rawTyped = elapsedMs / perRuneMs;
      final fullCount = rawTyped.floor().clamp(0, runeCount);
      final fadeProgress = (rawTyped - fullCount).clamp(0.0, 1.0);
      final spans = <InlineSpan>[];
      if (fullCount > 0) {
        spans.add(
          TextSpan(text: String.fromCharCodes(runes.take(fullCount))),
        );
      }
      if (fullCount < runeCount) {
        final fadingChar = String.fromCharCodes([runes[fullCount]]);
        spans.add(
          TextSpan(
            text: fadingChar,
            style: textStyle?.copyWith(
              color: baseColor.withValues(
                alpha: Curves.easeOut.transform(fadeProgress),
              ),
            ),
          ),
        );
      }
      return spans;
    }

    const fullVisibleEnd = _onboardingTypingMs + _onboardingHoldFullMs;
    const deletingEnd = fullVisibleEnd + _onboardingDeletingMs;
    const emptyEnd = deletingEnd + _onboardingHoldEmptyMs;

    if (elapsedMs < fullVisibleEnd) {
      return [TextSpan(text: line)];
    }

    if (elapsedMs < deletingEnd) {
      final deletingElapsed = elapsedMs - fullVisibleEnd;
      final perRuneMs = _onboardingDeletingMs / runeCount;
      final rawRemoved = deletingElapsed / perRuneMs;
      final removedCount = rawRemoved.floor().clamp(0, runeCount);
      final fadeProgress = (rawRemoved - removedCount).clamp(0.0, 1.0);
      final remainingCount = (runeCount - removedCount).clamp(0, runeCount);
      if (remainingCount <= 0) {
        return const [TextSpan(text: '')];
      }
      if (remainingCount == 1) {
        return [
          TextSpan(
            text: String.fromCharCodes([runes[0]]),
            style: textStyle?.copyWith(
              color: baseColor.withValues(
                alpha: 1 - Curves.easeIn.transform(fadeProgress),
              ),
            ),
          ),
        ];
      }
      return [
        TextSpan(text: String.fromCharCodes(runes.take(remainingCount - 1))),
        TextSpan(
          text: String.fromCharCodes([runes[remainingCount - 1]]),
          style: textStyle?.copyWith(
            color: baseColor.withValues(
              alpha: 1 - Curves.easeIn.transform(fadeProgress),
            ),
          ),
        ),
      ];
    }

    if (elapsedMs < emptyEnd) {
      return const [TextSpan(text: '')];
    }

    return const [TextSpan(text: '')];
  }

  bool _showTypewriterCursor() {
    const blinkCycleMs = 800;
    return _typewriterElapsedMs() % blinkCycleMs < 460;
  }

  Widget _buildSecondaryStatus(
    ThemeData theme,
    L10n l10n, {
    required bool isOnboarding,
  }) {
    if (isOnboarding) {
      final textStyle = theme.textTheme.bodySmall?.copyWith(
        color: Colors.orange.shade800.withValues(alpha: 0.95),
        fontWeight: FontWeight.w600,
        height: 1.2,
      );
      return AnimatedBuilder(
        animation: _typewriterController,
        builder: (context, child) {
          final messageSpans = _onboardingTypewriterSpans(l10n, textStyle);
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: Colors.orange.shade500,
                  backgroundColor: Colors.orange.shade100.withValues(
                    alpha: 0.35,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: RichText(
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: textStyle,
                    children: [
                      ...messageSpans,
                      TextSpan(
                        text: '▍',
                        style: textStyle?.copyWith(
                          color: _showTypewriterCursor()
                              ? Colors.orange.shade600
                              : Colors.orange.shade600.withValues(alpha: 0.15),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
    return Row(
      children: [
        _buildWorkStatusDot(theme),
        if (widget.employee.isReady) const SizedBox(width: 6),
        Flexible(
          child: Text(
            _getWorkStatusText(l10n),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildCardContainer(
    BuildContext context,
    ThemeData theme,
    L10n l10n, {
    required bool isOnboarding,
    required bool isOffboarding,
    double glowOpacity = 0.0,
    required Color? cardColor,
    required Color borderColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: cardColor,
        gradient: isOnboarding
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.orange.withValues(alpha: 0.05 + glowOpacity * 0.1),
                  theme.colorScheme.surfaceContainerLow,
                  Colors.orange.withValues(alpha: 0.03 + glowOpacity * 0.08),
                ],
              )
            : isOffboarding
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.error.withValues(
                        alpha: 0.06 + glowOpacity * 0.12,
                      ),
                      theme.colorScheme.surfaceContainerLow,
                      theme.colorScheme.errorContainer.withValues(
                        alpha: 0.08 + glowOpacity * 0.1,
                      ),
                    ],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.05),
                      theme.colorScheme.surfaceContainerLow,
                      theme.colorScheme.secondaryContainer
                          .withValues(alpha: 0.03),
                    ],
                  ),
        boxShadow: isOnboarding
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: glowOpacity * 0.6),
                  blurRadius: 24,
                  spreadRadius: 0,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: theme.colorScheme.shadow.withAlpha(10),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : isOffboarding
                ? [
                    BoxShadow(
                      color: theme.colorScheme.error.withValues(
                        alpha: glowOpacity * 0.6,
                      ),
                      blurRadius: 24,
                      spreadRadius: 0,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: theme.colorScheme.shadow.withAlpha(12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.06),
                      blurRadius: 16,
                      spreadRadius: -4,
                      offset: const Offset(0, 6),
                    ),
                    BoxShadow(
                      color: theme.colorScheme.shadow.withAlpha(6),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
      ),
      child: Card(
        elevation: 0,
        color: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: borderColor,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // 头像 + 状态指示器
                _buildAvatar(context, theme),
                const SizedBox(width: 12),

                // 员工信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 名称
                      Text(
                        widget.employee.displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: (isOnboarding || isOffboarding)
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.7)
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),

                      // 副标题状态
                      _buildSecondaryStatus(
                        theme,
                        l10n,
                        isOnboarding: isOnboarding,
                      ),
                    ],
                  ),
                ),

                // 就绪状态徽章
                _buildStatusBadge(context, theme, l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, ThemeData theme) {
    final isOffboarding = widget.isOffboarding;
    final isOnboarding = !widget.employee.isReady && !isOffboarding;

    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        children: [
          // 装饰环（总是显示，增加层次感）
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isOffboarding
                          ? [
                              theme.colorScheme.error.withValues(
                                alpha: 0.25 + _pulseAnimation.value * 0.25,
                              ),
                              theme.colorScheme.errorContainer.withValues(
                                alpha: 0.2 + _pulseAnimation.value * 0.2,
                              ),
                            ]
                          : isOnboarding
                              ? [
                                  Colors.orange.withValues(
                                    alpha: 0.3 + _pulseAnimation.value * 0.3,
                                  ),
                                  Colors.deepOrange.withValues(
                                    alpha: 0.2 + _pulseAnimation.value * 0.2,
                                  ),
                                ]
                              : [
                                  theme.colorScheme.primary
                                      .withValues(alpha: 0.15),
                                  theme.colorScheme.secondary
                                      .withValues(alpha: 0.1),
                                ],
                    ),
                  ),
                );
              },
            ),
          ),
          // 内层白色环
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surface,
                ),
              ),
            ),
          ),
          // 头像
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ],
                ),
                child: widget.employee.avatarUrl != null &&
                        widget.employee.avatarUrl!.isNotEmpty
                    ? ClipOval(
                        child: Opacity(
                          opacity: (isOnboarding || isOffboarding) ? 0.75 : 1.0,
                          child: CustomNetworkImage(
                            widget.employee.avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                _buildAvatarFallback(theme),
                          ),
                        ),
                      )
                    : _buildAvatarFallback(theme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarFallback(ThemeData theme) {
    return Center(
      child: Text(
        widget.employee.displayName.isNotEmpty
            ? widget.employee.displayName[0].toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildWorkStatusDot(ThemeData theme) {
    if (!widget.employee.isReady || widget.isOffboarding) {
      return const SizedBox.shrink();
    }

    final dotColor = _getWorkStatusColor(widget.employee.computedWorkStatus);

    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.colorScheme.surface,
          width: 2,
        ),
      ),
    );
  }

  String _getWorkStatusText(L10n l10n) {
    if (widget.isOffboarding) {
      return '${l10n.deleteEmployee}...';
    }
    if (!widget.employee.isReady) {
      return l10n.employeeOnboarding;
    }

    switch (widget.employee.computedWorkStatus) {
      case 'working':
        return '💼 ${l10n.employeeWorking}';
      case 'slacking':
        return '🐟 ${l10n.employeeSlacking}';
      default:
        return '😴 ${l10n.employeeSleeping}';
    }
  }

  Color _getWorkStatusColor(String status) {
    switch (status) {
      case 'working':
        return Colors.green;
      case 'slacking':
        return Colors.blue;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _buildStatusBadge(BuildContext context, ThemeData theme, L10n l10n) {
    if (widget.isOffboarding) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.error.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${l10n.deleteEmployee}...',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    if (!widget.employee.isReady) {
      return const SizedBox.shrink();
    }

    // 就绪状态 - 使用 Material 3 的 Chip 样式
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.green.withValues(alpha: 0.18),
            Colors.teal.withValues(alpha: 0.12),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.green.withValues(alpha: 0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.shade500,
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.employeeReady,
            style: theme.textTheme.labelSmall?.copyWith(
              color: Colors.green.shade700,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
