import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/external_activity.dart';
import '../core/l10n.dart';
import '../core/photo_picker.dart';
import '../core/theme.dart';

/// Keeps a selected batch until both uploading and attaching it have succeeded.
/// A retry reuses uploaded IDs instead of asking the user to select again.
class ProfileGalleryUpload extends StatefulWidget {
  final JobaApi api;
  final int count;
  final VoidCallback onSaved;
  final Future<List<PhotoFile>> Function(int limit)? pick;
  const ProfileGalleryUpload(
      {required this.api,
      required this.count,
      required this.onSaved,
      this.pick,
      super.key});
  @override
  State<ProfileGalleryUpload> createState() => _ProfileGalleryUploadState();
}

class _ProfileGalleryUploadState extends State<ProfileGalleryUpload> {
  List<PhotoFile> pending = [];
  final ids = <String>[];
  bool busy = false;
  Object? error;

  Future<void> add() async {
    if (busy) return;
    final client = widget.api, generation = widget.api.sessionGeneration;
    bool current() =>
        mounted &&
        identical(client, widget.api) &&
        client.sessionGeneration == generation &&
        client.authenticated;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (pending.isEmpty) {
        final limit = 20 - widget.count;
        final photos = await withExternalActivity(() => widget.pick != null
            ? widget.pick!(limit)
            : choosePhotos(context, limit: limit));
        if (!current() || photos.isEmpty) return;
        if (photos.length > limit)
          throw ApiException('TOO_MANY_PHOTOS',
              'В галерее может быть не больше 20 фотографий. Выберите меньше фотографий.');
        setState(() => pending = photos);
      }
      while (ids.length < pending.length) {
        final photo = pending[ids.length];
        final upload =
            await client.upload(photo.bytes, photo.mime, 'portfolio');
        if (!current()) return;
        if (upload['status'] != 'clean')
          throw ApiException('UNSAFE_UPLOAD', 'Файл не прошёл проверку');
        setState(() => ids.add(upload['id'] as String));
      }
      // Read current data so adding photos cannot overwrite newer profile edits.
      final response = await client.request('/me/contractor-profile') as Json;
      final profile = response['profile'] as Json?;
      if (profile == null) throw ApiException('NOT_FOUND', 'Профиль не найден');
      if (!current()) return;
      final gallery = <String>{
        ...(profile['gallery_ids'] as List? ?? []).cast<String>(),
        ...ids
      }.toList();
      if (gallery.length > 20)
        throw ApiException('TOO_MANY_PHOTOS',
            'В галерее может быть не больше 20 фотографий. Выберите меньше фотографий.');
      await client.request('/me/contractor-profile', method: 'PUT', body: {
        ...profile,
        'expected_version': profile['version'],
        'gallery_ids': gallery,
      });
      if (!current()) return;
      pending = [];
      ids.clear();
      widget.onSaved();
    } catch (e) {
      if (current()) setState(() => error = e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: OutlinedButton.icon(
              onPressed: busy ? null : add,
              icon: const Icon(Icons.photo_library_outlined),
              label: UiText(pending.isEmpty
                  ? 'Добавить фотографии'
                  : 'Повторить загрузку'),
            )),
        const UiText(
            'Можно выбрать несколько фотографий сразу. До 20 фото в галерее.'),
        if (busy) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: pending.isEmpty ? null : ids.length / pending.length),
          if (pending.isNotEmpty)
            Text(localize(context, 'Загружено: {completed} из {total}')
                .replaceAll('{completed}', '${ids.length}')
                .replaceAll('{total}', '${pending.length}')),
        ],
        if (error != null) Notice(errorText(context, error!), error: true),
      ]);
}
