import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/session_refresh.dart';
import '../jobs/jobs_providers.dart';

/// Загрузка фотографий в хранилище (ТЗ §2.5, ADR-5).
///
/// Файл уходит от телефона прямо в хранилище по временной ссылке: снимок с
/// камеры весит мегабайты, и гнать его через наш сервер значит платить за
/// трафик дважды и ронять загрузку вместе с сервисом.
class PhotoUploader {
  PhotoUploader(this._ref);

  final Ref _ref;

  static final _picker = ImagePicker();

  /// Выбрать снимки и загрузить их. Возвращает постоянные адреса файлов —
  /// именно они сохраняются в карточке.
  ///
  /// [limit] — сколько ещё можно добавить, [folder] — раздел хранилища.
  Future<List<String>> pickAndUpload({
    required String folder,
    int limit = 8,
    bool fromCamera = false,
  }) async {
    final files = <XFile>[];
    if (fromCamera) {
      final shot = await _picker.pickImage(
        source: ImageSource.camera,
        // Сжимаем на устройстве: полноразмерный кадр с телефона грузится
        // минутами на мобильном интернете и не даёт ничего полезного.
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (shot != null) files.add(shot);
    } else {
      final picked = await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 80);
      files.addAll(picked.take(limit));
    }
    if (files.isEmpty) return const [];

    final api = _ref.read(jobsApiProvider);
    final refresher = _ref.read(sessionRefresherProvider);
    final urls = <String>[];

    for (final file in files) {
      final bytes = await file.readAsBytes();
      final type = _contentType(file);

      final links = await refresher.run(
        (t) => api.uploadLinks(t, contentType: type, folder: folder),
      );
      if (links.isEmpty) continue;

      await api.uploadBytes(links.first.uploadUrl, bytes, type);
      urls.add(links.first.publicUrl);
    }
    return urls;
  }

  /// Тип файла по расширению: image_picker не везде отдаёт mimeType.
  static String _contentType(XFile file) {
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.heic')) return 'image/heic';
    if (name.endsWith('.pdf')) return 'application/pdf';
    return 'image/jpeg';
  }
}

final photoUploaderProvider = Provider<PhotoUploader>(PhotoUploader.new);
