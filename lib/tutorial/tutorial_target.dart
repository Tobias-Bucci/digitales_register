import 'package:dr/tutorial/tutorial_service.dart';
import 'package:flutter/material.dart';

/// Registers a piece of the existing UI as a spotlight target without changing
/// its layout or gesture handling.
class TutorialTarget extends StatefulWidget {
  const TutorialTarget({
    super.key,
    required this.id,
    required this.child,
  });

  final String id;
  final Widget child;

  @override
  State<TutorialTarget> createState() => _TutorialTargetState();
}

class _TutorialTargetState extends State<TutorialTarget> {
  bool _inTree = true;
  @override
  void deactivate() {
    _inTree = false;
    tutorialTargets.remove(widget.id, context);
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _inTree = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  @override
  void didUpdateWidget(TutorialTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      tutorialTargets.remove(oldWidget.id, context);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _register());
  }

  void _register() {
    if (mounted && _inTree) tutorialTargets.register(widget.id, context);
  }

  @override
  void dispose() {
    tutorialTargets.remove(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
