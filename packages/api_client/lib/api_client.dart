/// Клиент Traktor API. Сгенерирован по смыслу из contracts/openapi/traktor.yaml
/// (в CI подключим полноценный кодоген; здесь — тонкий ручной клиент под текущие
/// эндпоинты identity, чтобы приложение работало против реального сервиса).
library api_client;

export 'src/json_body.dart';
export 'src/models.dart';
export 'src/auth_api.dart';
export 'src/devices_api.dart';
export 'src/jobs_models.dart';
export 'src/jobs_api.dart';
