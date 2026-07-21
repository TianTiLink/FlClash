import 'package:flutter/material.dart';

import 'xboard_api.dart';

class RegistrationSlider extends StatefulWidget {
  final String baseUrl;
  final ValueChanged<String> onVerified;

  const RegistrationSlider({
    required this.baseUrl,
    required this.onVerified,
    super.key,
  });

  @override
  State<RegistrationSlider> createState() => _RegistrationSliderState();
}

class _RegistrationSliderState extends State<RegistrationSlider> {
  XboardSliderChallenge? _challenge;
  double _offset = 0;
  bool _loading = true;
  bool _verifying = false;
  bool _verified = false;
  String? _message;
  int _startedAt = 0;
  final List<Map<String, num>> _track = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _verifying = false;
        _verified = false;
        _message = null;
        _challenge = null;
        _offset = 0;
        _track.clear();
        _startedAt = 0;
      });
    }
    try {
      final challenge =
          await XboardApi(widget.baseUrl).fetchRegistrationChallenge();
      if (!mounted) return;
      setState(() {
        _challenge = challenge;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = error.toString();
      });
    }
  }

  void _start(double _) {
    _startedAt = DateTime.now().millisecondsSinceEpoch;
    _track
      ..clear()
      ..add(const {'x': 0, 't': 0});
  }

  void _move(double value) {
    if (_startedAt == 0) _start(value);
    final elapsed = DateTime.now().millisecondsSinceEpoch - _startedAt;
    final previous = _track.isEmpty ? null : _track.last;
    if (_track.length < 95 &&
        (previous == null ||
            ((previous['x'] ?? 0) - value).abs() >= 0.2 ||
            elapsed - (previous['t'] ?? 0) >= 45)) {
      _track.add({'x': double.parse(value.toStringAsFixed(1)), 't': elapsed});
    }
    setState(() => _offset = value);
  }

  Future<void> _finish(double value) async {
    final challenge = _challenge;
    if (challenge == null || _verifying || _verified) return;
    _move(value);
    final elapsed = DateTime.now().millisecondsSinceEpoch - _startedAt;
    _track.add({'x': double.parse(value.toStringAsFixed(1)), 't': elapsed});
    setState(() {
      _verifying = true;
      _message = '正在核验...';
    });
    try {
      final token = await XboardApi(widget.baseUrl).verifyRegistrationSlider(
        challenge.challengeId,
        value,
        _track,
      );
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _verified = true;
        _message = '验证通过，可继续注册';
      });
      widget.onVerified(token);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _message = error.toString();
      });
      await Future<void>.delayed(const Duration(milliseconds: 700));
      if (mounted) await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final challenge = _challenge;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(child: Text('安全验证：拖动拼图对准缺口')),
                IconButton(
                  tooltip: '换一张',
                  onPressed: _loading || _verifying ? null : _load,
                  icon: const Icon(Icons.refresh, size: 20),
                ),
              ],
            ),
            if (_loading)
              const SizedBox(
                height: 150,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (challenge != null) ...[
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final scale = width / challenge.width;
                  return SizedBox(
                    width: width,
                    height: challenge.height * scale,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: Image.memory(
                              challenge.background,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                          ),
                          Positioned(
                            left: _offset * scale,
                            top: challenge.pieceY * scale,
                            width: challenge.pieceWidth * scale,
                            height: challenge.pieceHeight * scale,
                            child: Image.memory(
                              challenge.piece,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Slider(
                min: 0,
                max: challenge.width - challenge.pieceWidth,
                value: _offset,
                onChangeStart: _verifying || _verified ? null : _start,
                onChanged: _verifying || _verified ? null : _move,
                onChangeEnd: _verifying || _verified ? null : _finish,
              ),
            ],
            Text(
              _verified ? '✓ ${_message ?? ''}' : (_message ?? '按住滑块向右拖动'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: _verified
                    ? theme.colorScheme.primary
                    : (_message != null && !_verifying
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant),
                fontWeight: _verified ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
