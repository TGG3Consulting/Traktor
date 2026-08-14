import 'dart:convert';

import 'package:http/http.dart' as http;

/// Разбор тела ответа как UTF-8.
///
/// `http.Response.body` берёт кодировку из заголовка Content-Type, а при его
/// отсутствии считает тело latin-1 — русские и армянские тексты в этом случае
/// превращаются в мусор вроде «Ð¡ÐµÑÑÐ¸Ñ». Наши сервисы всегда отдают UTF-8,
/// поэтому декодируем байты сами и не зависим от заголовка.
Map<String, dynamic> decodeJsonBody(http.Response resp) {
  if (resp.bodyBytes.isEmpty) return {};
  final text = utf8.decode(resp.bodyBytes, allowMalformed: true);
  if (text.trim().isEmpty) return {};
  final decoded = jsonDecode(text);
  if (decoded is Map) return decoded.cast<String, dynamic>();
  return {'data': decoded};
}
