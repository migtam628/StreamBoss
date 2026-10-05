import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// Network image that degrades to nothing on failure.
/// Native platforms use the disk-cached widget (big libraries show thousands of posters);
/// web uses the plain image provider, where the browser already caches and the cached widget
/// can render empty when an image is served from Flutter's in-memory cache.
class NetImage extends StatelessWidget {
  final String url;
  final BoxFit fit;
  final Widget Function()? fallback;
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.fallback});

  @override
  Widget build(BuildContext context) {
    Widget fail() => fallback?.call() ?? const SizedBox.shrink();
    if (kIsWeb) {
      return Image.network(url, fit: fit, errorBuilder: (_, __, ___) => fail());
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      errorWidget: (_, __, ___) => fail(),
      placeholder: (_, __) => const SizedBox.shrink(),
    );
  }
}
