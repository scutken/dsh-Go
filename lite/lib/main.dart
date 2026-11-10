import 'package:dsh_remote/dsh_remote.dart';
import 'package:flutter/material.dart';

import 'controller.dart' as lite;

void main() => runApp(const LiteApp());

class LiteApp extends StatelessWidget {
  const LiteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DSH Lite',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF4B67B4),
        useMaterial3: true,
        brightness: Brightness.dark,
      ),
      home: const _Gate(),
    );
  }
}

class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  final _c = lite.LiteController();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_bump);
    _c.boot().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  void _bump() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _c.removeListener(_bump);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final c = _c;
    if (c.busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!c.signedIn) return SignInPage(controller: c, onDone: _bump);
    if (c.sessionId != null) return ChatPage(controller: c, onDone: _bump);
    if (!c.linked) return HostsPage(controller: c, onDone: _bump);
    return SessionsPage(controller: c, onDone: _bump);
  }
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key, required this.controller, required this.onDone});
  final lite.LiteController controller;
  final VoidCallback onDone;

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  late final TextEditingController _server = TextEditingController(text: widget.controller.serverUrl);
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _server.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('DSH Lite')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          const Text('连接远程 DSH', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            '精简版：不含本地 Linux 环境、无障碍、ADB，只保留远程连接。',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _server,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://dsh.r2049.cn',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            decoration: const InputDecoration(labelText: '邮箱', border: OutlineInputBorder()),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(labelText: '密码', border: OutlineInputBorder()),
            obscureText: true,
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () async {
              final url = _server.text.trim();
              if (url.isNotEmpty && url != c.serverUrl) await c.setServer(url);
              await c.signInWithPassword(_email.text, _password.text);
              widget.onDone();
            },
            child: const Text('登录'),
          ),
          if (c.error != null) _errorBox(context, c.error!),
          const SizedBox(height: 32),
          Text(
            '主机需要先装 ds-harness-remote 插件并保持在线。',
            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(BuildContext context, String msg) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
      child: Text(msg, style: TextStyle(color: scheme.onErrorContainer, fontSize: 12)),
    );
  }
}

class HostsPage extends StatelessWidget {
  const HostsPage({super.key, required this.controller, required this.onDone});
  final lite.LiteController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(
        title: const Text('主机'),
        actions: [
          IconButton(
            onPressed: () async {
              await c.refreshHosts();
              onDone();
            },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () async {
              await c.logout();
              onDone();
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await c.refreshHosts();
          onDone();
        },
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '已登录：${c.user?.account ?? ''}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            if (c.hosts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('没有主机。请在电脑上安装 ds-harness-remote 插件并保持在线。'),
              ),
            for (final h in c.hosts)
              Card(
                child: ListTile(
                  leading: Icon(
                    h.online ? Icons.computer : Icons.computer_outlined,
                    color: h.online ? Colors.greenAccent : Colors.grey,
                  ),
                  title: Text(h.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${h.platform} · DSH ${h.harnessVersion ?? "?"} · ${h.online ? "在线" : "离线"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: h.online ? const Icon(Icons.chevron_right) : null,
                  onTap: h.online
                      ? () async {
                          await c.connect(h);
                          onDone();
                        }
                      : null,
                ),
              ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(c.error!, style: const TextStyle(fontSize: 12, color: Colors.orangeAccent)),
              ),
          ],
        ),
      ),
    );
  }
}

class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key, required this.controller, required this.onDone});
  final lite.LiteController controller;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Scaffold(
      appBar: AppBar(
        title: Text(c.host?.name ?? '会话', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '新建会话',
            onPressed: () async {
              await c.newSession();
              onDone();
            },
            icon: const Icon(Icons.add),
          ),
          IconButton(
            tooltip: '断开',
            onPressed: () async {
              await c.disconnect();
              onDone();
            },
            icon: const Icon(Icons.link_off),
          ),
        ],
      ),
      body: c.sessions.isEmpty
          ? const Center(child: Text('没有会话，点右上角 + 新建', style: TextStyle(color: Colors.grey)))
          : ListView(
              children: [
                for (final s in c.sessions)
                  ListTile(
                    dense: true,
                    leading: Icon(s.running ? Icons.play_circle : Icons.chat_bubble_outline, size: 20),
                    title: Text(
                      (s.raw['title'] as String?)?.isNotEmpty == true ? s.raw['title'] as String : s.sessionId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    subtitle: Text(
                      s.cwd ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onTap: () async {
                      await c.openSession(s.sessionId);
                      onDone();
                    },
                  ),
              ],
            ),
    );
  }
}

/// 聊天页：直接用官方 ChatTranscript 的输出渲染，自己不解析事件结构。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.controller, required this.onDone});
  final lite.LiteController controller;
  final VoidCallback onDone;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final t = c.transcript;
    final items = t?.items ?? const <ChatItem>[];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () async {
            await c.leaveSession();
            widget.onDone();
          },
        ),
        title: Text(t?.title ?? c.sessionId ?? '', overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('还没有消息', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _bubble(context, items[i]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        hintText: '发消息…',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: () {
                      final text = _input.text;
                      if (text.trim().isEmpty) return;
                      _input.clear();
                      c.send(text).then((_) => widget.onDone());
                    },
                    icon: const Icon(Icons.send, size: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(BuildContext context, ChatItem item) {
    final scheme = Theme.of(context).colorScheme;
    switch (item) {
      case UserChatItem(:final text):
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 320),
            decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(12)),
            child: SelectableText(text, style: TextStyle(color: scheme.onPrimaryContainer)),
          ),
        );
      case AssistantChatItem(:final text, :final interrupted):
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(10),
            constraints: const BoxConstraints(maxWidth: 340),
            decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(text.isEmpty ? '…' : text),
                if (interrupted)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('（已中断）', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
              ],
            ),
          ),
        );
      case ToolChatItem(:final name):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              const Icon(Icons.build_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(
                child: Text('工具：$name', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ),
            ],
          ),
        );
      case NoticeChatItem(:final text):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(text, style: const TextStyle(fontSize: 12, color: Colors.orangeAccent)),
        );
    }
  }
}
