import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Scrolls [controller] to the bottom, retrying across frames while a lazy
/// [ListView] / [CustomScrollView] is still growing [maxScrollExtent].
void scrollListToEnd(
  ScrollController controller, {
  bool jump = false,
  Duration animateDuration = const Duration(milliseconds: 180),
  int maxAttempts = 15,
}) {
  var attempts = 0;
  var lastExtent = -1.0;

  void schedule() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;

      final target = controller.position.maxScrollExtent;
      final grew = target > lastExtent + 0.5;

      if (jump || grew) {
        controller.jumpTo(target);
      } else {
        controller.animateTo(
          target,
          duration: animateDuration,
          curve: Curves.easeOut,
        );
      }

      attempts++;
      lastExtent = target;

      if (attempts < maxAttempts && grew) {
        schedule();
      }
    });
  }

  schedule();
}
