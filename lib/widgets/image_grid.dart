import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth_provider.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets.dart';
import '../share_log.dart';

/// Post media, same as the web (image-grid.tsx): 1 image = full width (up to 512 px tall), 2 = side by
/// side, 3 = one tall + two stacked, 4 = 2x2; 16:9 frame, 2 px gaps, rounded outer corners with a border.
/// Tap any image: full-screen viewer that swipes between photos, with a counter, share and close.
class ImageGrid extends StatelessWidget {
  final List<String> images;

  /// link shared from the viewer (the ask's page)
  final String? shareUrl;

  /// the post's id, to record the share
  final String? shareRef;
  const ImageGrid(this.images, {super.key, this.shareUrl, this.shareRef});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final p = Pal.of(context);
    final shown = images.take(4).toList();
    final n = shown.length;
    Widget tile(int i) => GestureDetector(
          onTap: () => openImageViewer(context, images, i, shareUrl: shareUrl, shareRef: shareRef),
          child: Stack(fit: StackFit.expand, children: [
            ColoredBox(color: p.chip, child: NetImg(shown[i])),
            if (i == 3 && images.length > 4)
              Container(
                color: kInk.withValues(alpha: .55),
                alignment: Alignment.center,
                child: Text('+${images.length - 4}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
          ]),
        );
    const gap = 2.0;
    Widget body;
    if (n == 1) {
      body = GestureDetector(
        onTap: () => openImageViewer(context, images, 0, shareUrl: shareUrl, shareRef: shareRef),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 512, minHeight: 120),
          child: SizedBox(width: double.infinity, child: ColoredBox(color: p.chip, child: NetImg(shown[0], fit: BoxFit.cover))),
        ),
      );
    } else {
      body = AspectRatio(
        aspectRatio: 16 / 9,
        child: n == 2
            ? Row(children: [Expanded(child: tile(0)), const SizedBox(width: gap), Expanded(child: tile(1))])
            : Row(children: [
                Expanded(
                  child: n == 3 ? tile(0) : Column(children: [Expanded(child: tile(0)), const SizedBox(height: gap), Expanded(child: tile(2))]),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: Column(children: [
                    Expanded(child: tile(1)),
                    const SizedBox(height: gap),
                    Expanded(child: tile(n == 3 ? 2 : 3)),
                  ]),
                ),
              ]),
      );
    }
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: p.border)),
      child: ClipRRect(borderRadius: BorderRadius.circular(13), child: body),
    );
  }
}

void openImageViewer(BuildContext context, List<String> images, int start, {String? shareUrl, String? shareRef}) {
  Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.black,
    pageBuilder: (_, __, ___) => _Viewer(images, start, shareUrl, shareRef),
    transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
  ));
}

class _Viewer extends StatefulWidget {
  final List<String> images;
  final int start;
  final String? shareUrl, shareRef;
  const _Viewer(this.images, this.start, this.shareUrl, this.shareRef);
  @override
  State<_Viewer> createState() => _ViewerState();
}

class _ViewerState extends State<_Viewer> {
  late final _pc = PageController(initialPage: widget.start);
  late int _i = widget.start;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.images.length;
    Widget roundBtn(WI icon, String label, VoidCallback onTap) => Semantics(
          button: true,
          label: label,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), shape: BoxShape.circle),
              child: WIcon(icon, size: 20, color: Colors.white, strokeWidth: 1.9),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        PageView.builder(
          controller: _pc,
          itemCount: n,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (_, i) => InteractiveViewer(maxScale: 4, child: Center(child: NetImg(widget.images[i], fit: BoxFit.contain))),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (n > 1)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
                  child: Text('${_i + 1} / $n', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              const Spacer(),
              if (widget.shareUrl != null) ...[
                roundBtn(WI.share, t('Share'), () => shareAndLog(context.read<AuthProvider>().api, entity: 'post', ref: widget.shareRef ?? '', text: widget.shareUrl!)),
                const SizedBox(width: 8),
              ],
              roundBtn(WI.close, t('Close'), () => Navigator.pop(context)),
            ]),
          ),
        ),
      ]),
    );
  }
}
