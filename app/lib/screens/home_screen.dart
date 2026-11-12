import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/client.dart';
import '../api/input.dart';
import '../api/share_source.dart';
import '../l10n/app_localizations.dart';
import '../widgets/error_messages.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.client, this.shareSource});

  final PravdomerClient client;
  final ShareSource? shareSource;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _controller = TextEditingController();
  StreamSubscription<String>? _shareSub;
  Timer? _cooldownTimer;
  bool _busy = false;
  String? _errorCode;
  int _cooldown = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    final share = widget.shareSource;
    if (share != null) {
      share.initial().then((c) {
        if (c != null) _onShared(c);
      });
      _shareSub = share.stream.listen(_onShared);
    }
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    _cooldownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onShared(String content) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _controller.text = content;
    _analyse();
  }

  void _startCooldown(Duration d) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = d.inSeconds.clamp(1, 3600));
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) {
          t.cancel();
          if (_errorCode == 'rate_limited') _errorCode = null;
        }
      });
    });
  }

  Future<void> _analyse() async {
    final input = classifyInput(_controller.text);
    if (input == null) {
      setState(() => _errorCode = 'empty');
      return;
    }
    if (_busy || _cooldown > 0) return;
    setState(() {
      _busy = true;
      _errorCode = null;
    });
    try {
      final start = await widget.client.createAnalysis(
        url: input.url,
        text: input.text,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ResultScreen(
            connect: () => widget.client.events(start.id),
            sourceUrl: input.url,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorCode = e.code);
      if (e.code == 'rate_limited') {
        _startCooldown(e.retryAfter ?? const Duration(seconds: 60));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t != null && t.isNotEmpty) _controller.text = t;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final input = classifyInput(_controller.text);
    final String? error = switch (_errorCode) {
      null => null,
      'empty' => l.errorEmptyInput,
      'rate_limited' => l.errorRateLimited(_cooldown),
      final c => errorMessage(l, c),
    };
    return Scaffold(
      appBar: AppBar(title: Text(l.appTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(l.homeHeadline, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(l.homeIntro, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 20),
            TextField(
              key: const Key('input'),
              controller: _controller,
              minLines: 3,
              maxLines: 10,
              keyboardType: TextInputType.multiline,
              decoration: InputDecoration(
                hintText: l.inputHint,
                border: const OutlineInputBorder(),
                helperText: input == null
                    ? null
                    : input.isUrl
                    ? l.inputDetectedUrl
                    : l.inputDetectedText(input.text!.length),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste),
                  label: Text(l.pasteButton),
                ),
                if (_controller.text.isNotEmpty)
                  TextButton.icon(
                    onPressed: _controller.clear,
                    icon: const Icon(Icons.clear),
                    label: Text(l.clearButton),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('analyse'),
              onPressed: (_busy || _cooldown > 0) ? null : _analyse,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.thermostat),
              label: Text(l.analyseButton),
            ),
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(
                error,
                key: const Key('home-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
