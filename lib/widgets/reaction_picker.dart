import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// The web's ReactionPicker: a pill with ❤️ 👍 🙏 that pops above the trigger. In [quick] mode the first
/// tap reacts with ❤️ straight away and shows the options, which go away by themselves after 3 seconds.
/// Tapping the current reaction again clears it.
class ReactionPicker extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChange;
  final Widget Function(bool open) trigger;
  final bool quick;
  const ReactionPicker({super.key, required this.value, required this.onChange, required this.trigger, this.quick = false});
  @override
  State<ReactionPicker> createState() => _ReactionPickerState();
}

class _ReactionPickerState extends State<ReactionPicker> with SingleTickerProviderStateMixin {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));
  Timer? _auto;

  @override
  void dispose() {
    _auto?.cancel();
    _in.dispose();
    super.dispose();
  }

  void _open() {
    _portal.show();
    _in.forward(from: 0);
    _auto?.cancel();
    if (widget.quick) _auto = Timer(const Duration(seconds: 3), _close);
    setState(() {});
  }

  void _close() {
    _auto?.cancel();
    if (!_portal.isShowing) return;
    _portal.hide();
    if (mounted) setState(() {});
  }

  void _tap() {
    if (_portal.isShowing) return _close();
    if (widget.quick && widget.value == null) widget.onChange(kReactions.first);
    _open();
  }

  @override
  Widget build(BuildContext context) {
    final p = Pal.of(context);
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Stack(children: [
          // tap anywhere else closes it
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _close)),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: const Offset(-4, -6),
            child: FadeTransition(
              opacity: _in,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, .1), end: Offset.zero).animate(CurvedAnimation(parent: _in, curve: Curves.easeOut)),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: p.card,
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: p.border),
                      boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 15, offset: Offset(0, 6))],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final r in kReactions)
                        GestureDetector(
                          onTap: () {
                            widget.onChange(widget.value == r ? null : r);
                            _close();
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: widget.value == r ? p.chip : Colors.transparent),
                            child: Text(kReactionEmoji[r]!, style: const TextStyle(fontSize: 20)),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
        child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _tap, child: widget.trigger(_portal.isShowing)),
      ),
    );
  }
}
