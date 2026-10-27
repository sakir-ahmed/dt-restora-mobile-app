import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/theme.dart';

/// Absolute URL of a menu item photo, built from the API host so it works
/// on the demo server and on a local one. Null when the item has no photo.
String? foodImageUrl(AppState app, Map item) {
  final raw = (item['cover_url'] ?? (item['photo_path'] == null ? null : '/storage/${item['photo_path']}')) as String?;
  if (raw == null || raw.isEmpty) {
    return null;
  }
  if (raw.startsWith('http')) {
    return raw;
  }
  final origin = app.api.baseUrl.replaceFirst(RegExp(r'/api/v\d+/?$'), '');
  return '$origin${raw.startsWith('/') ? '' : '/'}$raw';
}

/// Photo with a branded placeholder. Images are cached on disk, so photos
/// seen once still show when the device is offline.
class FoodImage extends StatelessWidget {
  const FoodImage({super.key, required this.url, this.fit = BoxFit.cover, this.iconSize = 32});

  final String? url;
  final BoxFit fit;
  final double iconSize;

  Widget _placeholder(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: context.isDark
                ? const [Color(0xFF16264A), Color(0xFF0F1D3A)]
                : const [Color(0xFFE6EEF9), Color(0xFFD3E2F6)],
          ),
        ),
        child: Center(child: Icon(Icons.restaurant, size: iconSize, color: context.brand.withValues(alpha: 0.45))),
      );

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return _placeholder(context);
    }
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (context, _) => _placeholder(context),
      errorWidget: (context, _, _) => _placeholder(context),
    );
  }
}
