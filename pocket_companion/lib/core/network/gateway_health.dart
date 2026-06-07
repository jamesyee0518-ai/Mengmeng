class GatewayComponentHealth {
  const GatewayComponentHealth({
    required this.ok,
    this.reason = '',
    this.provider = '',
    this.model = '',
    this.reachable = false,
    this.engine = '',
    this.ffmpeg = false,
    this.whisperCli = false,
    this.modelPathExists = false,
  });

  factory GatewayComponentHealth.fromJson(Object? value) {
    if (value is! Map) {
      return const GatewayComponentHealth(ok: false, reason: 'invalid_json');
    }
    return GatewayComponentHealth(
      ok: value['ok'] == true,
      reason: _stringValue(value['reason']),
      provider: _stringValue(value['provider']),
      model: _stringValue(value['model']),
      reachable: value['reachable'] == true,
      engine: _stringValue(value['engine']),
      ffmpeg: value['ffmpeg'] == true,
      whisperCli: value['whisperCli'] == true,
      modelPathExists: value['modelPathExists'] == true,
    );
  }

  final bool ok;
  final String reason;
  final String provider;
  final String model;
  final bool reachable;
  final String engine;
  final bool ffmpeg;
  final bool whisperCli;
  final bool modelPathExists;
}

class GatewayHealth {
  GatewayHealth({
    required this.ok,
    required this.gateway,
    required this.stt,
    required this.llm,
    required this.tts,
    this.reason = '',
    DateTime? timestamp,
    DateTime? checkedAt,
  }) : timestamp = timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
       checkedAt = checkedAt ?? DateTime.now();

  factory GatewayHealth.fromJson(Object? value, {DateTime? checkedAt}) {
    if (value is! Map) {
      return GatewayHealth.unavailable(
        reason: 'invalid_json',
        checkedAt: checkedAt,
      );
    }
    final gateway = GatewayComponentHealth.fromJson(value['gateway']);
    final stt = GatewayComponentHealth.fromJson(value['stt']);
    final llm = GatewayComponentHealth.fromJson(value['llm']);
    final tts = GatewayComponentHealth.fromJson(value['tts']);
    return GatewayHealth(
      ok: value['ok'] == true,
      gateway: gateway,
      stt: stt,
      llm: llm,
      tts: tts,
      reason: _firstReason([gateway, stt, llm, tts]),
      timestamp:
          DateTime.tryParse(_stringValue(value['timestamp'])) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      checkedAt: checkedAt,
    );
  }

  factory GatewayHealth.unavailable({
    required String reason,
    DateTime? checkedAt,
  }) {
    final failed = GatewayComponentHealth(ok: false, reason: reason);
    return GatewayHealth(
      ok: false,
      gateway: failed,
      stt: failed,
      llm: failed,
      tts: failed,
      reason: reason,
      checkedAt: checkedAt,
    );
  }

  final bool ok;
  final GatewayComponentHealth gateway;
  final GatewayComponentHealth stt;
  final GatewayComponentHealth llm;
  final GatewayComponentHealth tts;
  final String reason;
  final DateTime timestamp;
  final DateTime checkedAt;
}

String _firstReason(List<GatewayComponentHealth> components) {
  for (final component in components) {
    if (!component.ok && component.reason.isNotEmpty) {
      return component.reason;
    }
  }
  return '';
}

String _stringValue(Object? value) => value is String ? value : '';
