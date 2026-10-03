import 'package:flutter/material.dart';

import 'app_theme.dart';

class AureaBrandMark extends StatelessWidget {
  const AureaBrandMark({super.key, this.size = 42});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Aurea',
    image: true,
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * .3),
        gradient: const LinearGradient(
          colors: [Color(0xFF10131A), Color(0xFF1B2030)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AureaColors.indigo.withValues(alpha: .2),
            blurRadius: size * .35,
            offset: Offset(0, size * .12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(size * .13),
        child: Image.asset(
          'assets/images/app_mark_transparent_v2.png',
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
}

class AureaBrandLockup extends StatelessWidget {
  const AureaBrandLockup({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AureaBrandMark(size: compact ? 36 : 46),
      SizedBox(width: compact ? 10 : 12),
      Text(
        'Aurea',
        style:
            (compact
                    ? Theme.of(context).textTheme.titleLarge
                    : Theme.of(context).textTheme.headlineSmall)
                ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.5),
      ),
    ],
  );
}

class AureaPageBackground extends StatelessWidget {
  const AureaPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: dark ? AureaColors.midnight : AureaColors.paper),
        Positioned(
          right: -130,
          top: -150,
          child: IgnorePointer(
            child: Container(
              width: 330,
              height: 330,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AureaColors.indigo.withValues(alpha: dark ? .15 : .1),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: -160,
          bottom: -170,
          child: IgnorePointer(
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AureaColors.teal.withValues(alpha: dark ? .11 : .07),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class AureaSectionHeader extends StatelessWidget {
  const AureaSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      if (actionLabel != null && onAction != null)
        TextButton(onPressed: onAction, child: Text(actionLabel!)),
    ],
  );
}

class AureaEmptyState extends StatelessWidget {
  const AureaEmptyState({
    super.key,
    required this.asset,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.imageSize = 180,
  });

  final String asset;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final double imageSize;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          asset,
          width: imageSize,
          height: imageSize,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 18),
          FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    ),
  );
}

class AureaIconBadge extends StatelessWidget {
  const AureaIconBadge({
    super.key,
    required this.icon,
    this.color,
    this.size = 44,
  });

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: resolved.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(size * .34),
      ),
      child: Icon(icon, color: resolved, size: size * .5),
    );
  }
}
