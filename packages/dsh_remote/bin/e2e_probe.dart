// 纯 Dart 端到端验证：登录 → 列主机 → 连接 → 列会话 → 发消息 → 收事件
//
// 用法：
//   DSH_REMOTE_PASSWORD=xxx dart run bin/e2e_probe.dart \
//       --server https://dsh.r2049.cn --email you@example.com \
//       --state /tmp/e2e-state.json [--send "你好"] [--watch 20]
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_remote/dsh_remote.dart';

class _FileSecretStore implements SecretStore {
  _FileSecretStore(this.file) {
    if (file.existsSync()) {
      final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      decoded.forEach((k, v) => _values[k] = v! as String);
    }
  }
  final File file;
  final Map<String, String> _values = {};
  Future<void> _flush() async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_values));
    await tmp.rename(file.path);
  }
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
    await _flush();
  }
  @override
  Future<void> delete(String key) async {
    _values.remove(key);
    await _flush();
  }
}

String? _opt(List<String> a, String n) {
  final i = a.indexOf(n);
  return i >= 0 && i + 1 < a.length ? a[i + 1] : null;
}

void _log(String m) =>
    stdout.writeln('[${DateTime.now().toIso8601String().substring(11, 19)}] $m');

Future<void> main(List<String> args) async {
  final server = _opt(args, '--server') ?? defaultRemoteServer.toString();
  final statePath = _opt(args, '--state');
  final email = _opt(args, '--email');
  final hostSel = _opt(args, '--host');
  final sendText = _opt(args, '--send');
  final watchSec = int.tryParse(_opt(args, '--watch') ?? '') ?? 20;

  if (statePath == null) {
    stderr.writeln('必须给 --state（凭据持久化）');
    exit(2);
  }

  final account = RemoteAccount(
    secrets: _FileSecretStore(File(statePath)),
    serverUrl: server,
    deviceName: 'dsh-lite probe',
    platform: 'dsh-lite-probe',
  );

  DshClient? client;
  var code = 0;
  try {
    // ① 登录
    var user = await account.currentUser();
    if (user == null) {
      if (email == null) {
        stderr.writeln('未登录且未给 --email');
        exit(2);
      }
      final pw = Platform.environment['DSH_REMOTE_PASSWORD'];
      if (pw == null || pw.isEmpty) {
        stderr.writeln('需要 DSH_REMOTE_PASSWORD');
        exit(2);
      }
      _log('登录中 $email @ $server');
      user = await account.loginWithPassword(email, pw);
    }
    _log('✅ 已登录: ${user.account}  device=${user.deviceId}');

    // ② 列主机
    final hosts = await account.listHosts();
    _log('✅ listHosts: ${hosts.length} 台');
    for (final h in hosts) {
      _log('   · ${h.name}  id=${h.id}  online=${h.online}  '
          'platform=${h.platform}  dsh=${h.harnessVersion}  trust=${h.trust.name}');
    }

    final host = hosts
        .where((h) => hostSel == null ? h.online : (h.id == hostSel || h.name == hostSel))
        .firstOrNull;
    if (host == null) {
      _log('⚠️  没有可用的在线主机，到此为止（登录+列主机已验证通过）');
      exit(0);
    }

    // ③ 连接
    final sw = Stopwatch()..start();
    client = await account.connectHost(
      host,
      onState: (s) => _log('   连接状态: ${s.phase.name}'),
    );
    _log('✅ connectHost 成功，用时 ${sw.elapsedMilliseconds}ms');
    final carrier = client.remoteCarrier;
    if (carrier != null) {
      _log('   capabilities: ${carrier.capabilities.join(", ")}');
    }

    // ④ 列会话
    final sessions = await client.listSessions();
    _log('✅ listSessions: ${sessions.length} 个会话');

    // ⑤ 发消息 + 收实时事件
    if (sendText != null) {
      String sid;
      if (sessions.isNotEmpty) {
        sid = sessions.first.sessionId;
        _log('复用会话 $sid');
      } else {
        final created = await client.createSession();
        sid = created.sessionId;
        _log('新建会话 $sid');
      }
      final rid = await client.prompt(sid, sendText);
      _log('✅ prompt 已发出 requestId=$rid');

      _log('监听事件 ${watchSec}s ...');
      final done = Completer<void>();
      final sub = client.watch(sid).listen(
        (e) {
          final type = e.runtimeType.toString();
          _log('   ← $type');
        },
        onError: (Object e) => _log('   事件错误: $e'),
        onDone: () => _log('   事件流结束'),
      );
      Timer(Duration(seconds: watchSec), () {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
      await sub.cancel();
    }
  } catch (e, st) {
    _log('❌ 失败: $e');
    if (args.contains('--trace')) stdout.writeln(st);
    code = 1;
  } finally {
    try {
      await client?.close();
    } catch (_) {}
  }
  exit(code);
}
