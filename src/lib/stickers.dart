// ZARR CHAT - bantuan sticker: favorit (dari sticker siapa pun) dan lembar detail sticker.
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'state.dart';
import 'theme.dart';
import 'widgets.dart';

class StickerStore {
  static Future<bool> isFavorite(int mediaId) async {
    final r = asMap(await app.api.get('/stickers'));
    return asList(r['favorites']).any((s) => asMap(s)['mediaId'] == mediaId);
  }

  static Future<void> addFavorite(int mediaId) => app.api.post('/stickers/save', {'mediaId': mediaId});
  static Future<void> removeFavorite(int mediaId) => app.api.delete('/stickers/favorite-by-media/$mediaId');
}

/// Lembar detail saat sticker di dalam chat diketuk: tambah / hapus dari favorit (seperti WhatsApp).
Future<void> showStickerDetail(BuildContext context, Media media) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: pal(context).surface,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      side: BorderSide(color: pal(context).line, width: 2),
    ),
    builder: (ctx) => _StickerDetail(media: media),
  );
}

class _StickerDetail extends StatefulWidget {
  final Media media;
  const _StickerDetail({required this.media});
  @override
  State<_StickerDetail> createState() => _StickerDetailState();
}

class _StickerDetailState extends State<_StickerDetail> {
  bool? fav;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    StickerStore.isFavorite(widget.media.id).then((v) {
      if (mounted) setState(() => fav = v);
    }).catchError((Object _) {
      if (mounted) setState(() => fav = false);
    });
  }

  Future<void> toggle() async {
    final isFav = fav == true;
    setState(() => busy = true);
    try {
      if (isFav) {
        await StickerStore.removeFavorite(widget.media.id);
      } else {
        await StickerStore.addFavorite(widget.media.id);
      }
      app.toast(isFav ? 'Dihapus dari favorit.' : 'Ditambahkan ke favorit.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      app.toast(errText(e), error: true);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = pal(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 44, height: 5, decoration: BoxDecoration(color: p.divider, borderRadius: BorderRadius.circular(3))),
          const SizedBox(height: 16),
          CachedNetworkImage(
            imageUrl: app.api.abs(widget.media.url),
            httpHeaders: app.api.mediaHeaders,
            width: 200,
            height: 200,
            fit: BoxFit.contain,
            errorWidget: (c, u, e) => const SizedBox(width: 200, height: 200, child: Icon(Icons.broken_image)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: NeoButton(
              fav == true ? 'Hapus dari favorit' : 'Tambahkan ke favorit',
              icon: fav == true ? Icons.star : Icons.star_border,
              primary: fav != true,
              busy: busy || fav == null,
              onPressed: toggle,
            ),
          ),
        ]),
      ),
    );
  }
}
