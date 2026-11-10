import 'dart:async';

import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter/foundation.dart';

import 'secret_store.dart';

/// 精简版的全部状态：一个账号、一台主机、一个会话。
///
/// 刻意不用状态图：这里只有一条直线
/// 登录 → 列主机 → 连接 → 列会话 → 聊天。
/// 所有远程能力都来自官方 packages/dsh_remote，不复制协议代码。
class LiteController extends ChangeNotifier {
  LiteController() : _account = _buildAccount(Uri.parse(_defaultServer));

  static const _defaultServer = 'https://dsh.r2049.cn';
  static const _serverKey = 'server_url';

  static final _secrets = KeystoreSecretStore();

  RemoteAccount _account;

  static RemoteAccount _buildAccount(Uri server) => RemoteAccount(
    secrets: _secrets,
    serverUrl: server,
    deviceName: 'DSH Lite',
    platform: 'dsh-lite-android',
    clientVersion: '0.1.0',
  );

  // ---- 对外状态 ----
  String serverUrl = _defaultServer;
  RemoteUser? user;
  bool busy = false;
  String? error;

  List<RemoteHost> hosts = const [];
  RemoteHost? host;
  RemoteConnectionState? linkState;

  DshClient? client;
  List<SessionSummary> sessions = const [];

  ChatTranscript? transcript;
  String? sessionId;
  StreamSubscription<DshEvent>? _events;
  Timer? _ticker;

  bool get signedIn => user != null;
  bool get linked => client != null;

  // ---- 启动 ----
  Future<void> boot() async {
    try {
      final stored = await _secrets.read(_serverKey);
      if (stored != null && stored.isNotEmpty && stored != _defaultServer) {
        serverUrl = stored;
        _account = _buildAccount(Uri.parse(stored));
      }
      user = await _account.currentUser();
      if (user != null) hosts = await _account.listHosts();
    } catch (e) {
      error = _humanize(e);
    }
    notifyListeners();
  }

  Future<void> setServer(String url) async {
    final normalized = normalizeServerUrl(url).toString();
    serverUrl = normalized;
    await _secrets.write(_serverKey, normalized);
    _account = _buildAccount(Uri.parse(normalized));
    user = null;
    hosts = const [];
    notifyListeners();
  }

  // ---- 登录 ----
  Future<void> signInWithPassword(String email, String password) async {
    await _run(() async {
      user = await _account.loginWithPassword(email.trim(), password);
      hosts = await _account.listHosts();
    });
  }

  Future<void> logout() async {
    await _run(() async {
      await disconnect();
      await _account.logout();
      user = null;
      hosts = const [];
    });
  }

  // ---- 主机 ----
  Future<void> refreshHosts() async {
    await _run(() async {
      hosts = await _account.listHosts();
    });
  }

  Future<void> connect(RemoteHost h) async {
    await _run(() async {
      await disconnect();
      host = h;
      linkState = null;
      client = await _account.connectHost(
        h,
        onState: (s) {
          linkState = s;
          notifyListeners();
        },
        // 首连即信任；正式发布应加指纹确认对话框。
        confirmNewHost: (candidate) async => true,
      );
      sessions = await client!.listSessions();
    });
  }

  Future<void> disconnect() async {
    await _stopWatching();
    sessions = const [];
    try {
      await client?.close();
    } catch (_) {}
    client = null;
    linkState = null;
    notifyListeners();
  }

  // ---- 会话 ----
  Future<void> newSession() async {
    await _run(() async {
      _requireClient();
      final id = (await client!.createSession()).sessionId;
      sessions = await client!.listSessions();
      await _watch(id);
    });
  }

  Future<void> openSession(String id) async {
    await _run(() async {
      _requireClient();
      await _watch(id);
    });
  }

  /// 从聊天页返回会话列表：保留连接，只停掉事件订阅。
  Future<void> leaveSession() async {
    await _stopWatching();
    notifyListeners();
  }

  Future<void> _watch(String id) async {
    await _stopWatching();
    final t = ChatTranscript();
    transcript = t;
    sessionId = id;
    _events = client!.watch(id).listen(
      (event) {
        final changed = t.apply(event);
        if (changed) notifyListeners();
      },
      onError: (Object e) {
        error = _humanize(e);
        notifyListeners();
      },
    );
    // 流式文本的中间态不保证每帧都算 changed，补一个低频心跳。
    _ticker = Timer.periodic(const Duration(milliseconds: 800), (_) => notifyListeners());
  }

  Future<void> _stopWatching() async {
    await _events?.cancel();
    _events = null;
    _ticker?.cancel();
    _ticker = null;
    transcript = null;
    sessionId = null;
  }

  Future<void> send(String text) async {
    final id = sessionId;
    if (id == null || text.trim().isEmpty) return;
    _requireClient();
    await _run(() => client!.prompt(id, text.trim()));
  }

  Future<void> cancelTurn() async {
    final id = sessionId;
    if (id == null || client == null) return;
    try {
      await client!.cancel(id);
    } catch (_) {
      // 空闲时 cancel 也会返回 accepted，这里吞掉无妨。
    }
  }

  void _requireClient() {
    if (client == null) throw StateError('尚未连接主机');
  }

  Future<void> _run(Future<void> Function() body) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await body();
    } catch (e) {
      error = _humanize(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _humanize(Object e) {
    if (e is RemoteConnectException) return '连接失败：${e.failure.message}';
    final text = e.toString();
    return text.length > 240 ? '${text.substring(0, 240)}…' : text;
  }

  @override
  void dispose() {
    _events?.cancel();
    _ticker?.cancel();
    client?.close();
    super.dispose();
  }
}
