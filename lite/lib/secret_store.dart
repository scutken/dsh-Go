import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 复用官方 SecretStore 接口，底层换成 Android Keystore。
///
/// 不自己实现加密：flutter_secure_storage 走 Android Keystore，
/// 设备身份与 token 和官方 App 同一套安全边界。
class KeystoreSecretStore implements SecretStore {
  KeystoreSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _prefix = 'dsh_lite.v1.';

  @override
  Future<String?> read(String key) => _storage.read(key: '$_prefix$key');

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: '$_prefix$key', value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: '$_prefix$key');
}
