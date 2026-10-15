import 'package:flutter/material.dart';

import '../api.dart';
import '../theme.dart';

/// Photos on a post: 1 = wide, 2 = side by side, 3-4 = grid. Tap opens a full-screen viewer.
class ImageGrid extends StatelessWidget {
  final List<String> images;
  const ImageGrid(this.images, {super.key});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const SizedBox.shrink();
    final p = Pal.of(context);
    Widget tile(int i, {double? aspect}) => GestureDetector(
          onTap: () => openImageViewer(context, images, i),
          child: AspectRatio(
            aspectRatio: aspect ?? 1,
            child: Image.network(mediaUrl(images[i]), fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: p.field, child: Icon(Icons.broken_image_outlined, color: p.muted))),
          ),
        );
    final shown = images.take(4).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: shown.length == 1
            ? tile(0, aspect: 16 / 10)
            : GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 3,
                crossAxisSpacing: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: shown.length == 2 ? 1 : 1.4,
                children: [for (var i = 0; i < shown.length; i++) tile(i, aspect: shown.length == 2 ? 1 : 1.4)],
              ),
      ),
    );
  }
}

void openImageViewer(BuildContext context, List<String> images, int start) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _Viewer(images, start)));
}

class _Viewer extends StatelessWidget {
  final List<String> images;
  final int start;
  const _Viewer(this.images, this.start);
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
        body: PageView(
          controller: PageController(initialPage: start),
          children: [for (final u in images) InteractiveViewer(child: Center(child: Image.network(mediaUrl(u), fit: BoxFit.contain)))],
        ),
      );
}
