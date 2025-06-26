import 'dart:async';

import 'package:flutter/material.dart';

typedef TransitionBuilder =
    Widget Function(Widget child, Animation<double> animation);

class TransitionSwitcherController extends ChangeNotifier {
  Future<void> Function(Widget newChild)? _switchChild;
  bool isDone = false;

  Future<void> switchChild(Widget newChild) {
    isDone = false;
    if (_switchChild != null) {
      return _switchChild!(newChild);
    }
    return Future.value();
  }
}

class TransitionSwitcher extends StatefulWidget {
  final Widget child;
  final TransitionBuilder transitionIn;
  final TransitionBuilder transitionOut;
  final Duration outDuration;
  final Duration inDuration;
  final Duration inDelay;
  final TransitionSwitcherController? controller;

  const TransitionSwitcher({
    super.key,
    required this.child,
    required this.transitionIn,
    required this.transitionOut,
    this.outDuration = const Duration(milliseconds: 400),
    this.inDuration = const Duration(milliseconds: 400),
    this.inDelay = const Duration(milliseconds: 200),
    this.controller,
  });

  @override
  State<TransitionSwitcher> createState() => _TransitionSwitcherState();
}

class _TransitionSwitcherState extends State<TransitionSwitcher>
    with TickerProviderStateMixin {
  late Widget _currentChild;
  late Widget _nextChild;
  bool _isTransitioning = false;
  bool _isTransitioningOut = false;
  late AnimationController _outController;
  late AnimationController _inController;
  late Animation<double> _outAnimation;
  late Animation<double> _inAnimation;
  late TransitionSwitcherController _internalController;

  Completer<void>? _transitionCompleter;

  @override
  void initState() {
    super.initState();
    _currentChild = widget.child;
    _nextChild = widget.child;
    _outController = AnimationController(
      vsync: this,
      duration: widget.outDuration,
    );
    _inController = AnimationController(
      vsync: this,
      duration: widget.inDuration,
    );
    _outAnimation = CurvedAnimation(
      parent: _outController,
      curve: Curves.easeOut,
    );
    _inAnimation = CurvedAnimation(parent: _inController, curve: Curves.easeIn);
    _internalController = widget.controller ?? TransitionSwitcherController();
    _internalController._switchChild = _switchChild;
  }

  @override
  void didUpdateWidget(covariant TransitionSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.outDuration != oldWidget.outDuration) {
      _outController.duration = widget.outDuration;
    }
    if (widget.inDuration != oldWidget.inDuration) {
      _inController.duration = widget.inDuration;
    }
    if (widget.controller != oldWidget.controller) {
      (oldWidget.controller ?? _internalController)._switchChild = null;
      (widget.controller ?? _internalController)._switchChild = _switchChild;
    }
  }

  @override
  void dispose() {
    _outController.dispose();
    _inController.dispose();
    (widget.controller ?? _internalController)._switchChild = null;
    super.dispose();
  }

  Future<void> _switchChild(Widget newChild) async {
    if (_isTransitioning || newChild == _currentChild) return Future.value();
    _transitionCompleter = Completer<void>();
    setState(() {
      _nextChild = newChild;
      _isTransitioning = true;
      _isTransitioningOut = true;
    });

    _outController.reset();
    _inController.reset();

    // Start out animation
    final outFuture = _outController.forward();

    // Start in animation after a delay
    final inFuture = Future.delayed(widget.inDelay, () {
      if (mounted) return _inController.forward();
      return Future.value();
    }).then((f) => f); // flatten

    // Wait for both to finish
    await Future.wait([outFuture, inFuture]);

    setState(() {
      _currentChild = _nextChild;
      _isTransitioningOut = false;
      _isTransitioning = false;
    });

    _transitionCompleter?.complete();
    return _transitionCompleter!.future;
  }

  @override
  Widget build(BuildContext context) {
    if (!_isTransitioning) {
      return widget.transitionIn(_currentChild, kAlwaysCompleteAnimation);
    }
    if (_isTransitioningOut) {
      // Outgoing and incoming widgets are both visible and animating
      return Stack(
        children: [
          widget.transitionOut(_currentChild, _outAnimation),
          widget.transitionIn(_nextChild, _inAnimation),
        ],
      );
    } else {
      // Only animate in the next child (should be rare)
      return widget.transitionIn(_currentChild, kAlwaysCompleteAnimation);
    }
  }
}

// Helper for always-complete animation
final kAlwaysCompleteAnimation = AlwaysStoppedAnimation<double>(1.0);
