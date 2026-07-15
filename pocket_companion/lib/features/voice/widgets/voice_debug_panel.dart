import 'package:flutter/material.dart';

import '../barge_in_config.dart';
import '../voice_audio_gate_config.dart';
import '../voice_debug_sample.dart';
import '../voice_debug_sample_summary.dart';
import '../voice_debug_snapshot.dart';
import '../voice_profile_preset.dart';
import '../voice_runtime_profile.dart';
import '../voice_tuning_recommendation.dart';
import '../voice_wake_config.dart';
import 'voice_debug_samples_view.dart';
import 'voice_tuning_recommendation_view.dart';

class VoiceDebugPanel extends StatelessWidget {
  const VoiceDebugPanel({
    super.key,
    required this.snapshot,
    required this.wakeConfig,
    required this.audioGateConfig,
    required this.bargeInConfig,
    required this.activeProfile,
    required this.isCustomProfile,
    required this.tuningRecommendation,
    required this.onProfileChanged,
    required this.onWakeConfigChanged,
    required this.onAudioGateConfigChanged,
    required this.onBargeInConfigChanged,
    required this.onApplyTuningRecommendation,
    required this.onRefreshGatewayHealth,
    required this.onSaveSample,
    required this.recentSamples,
    required this.sampleSummary,
    required this.sampleExportPath,
    required this.onClearSamples,
  });

  final VoiceDebugSnapshot snapshot;
  final VoiceWakeConfig wakeConfig;
  final VoiceAudioGateConfig audioGateConfig;
  final BargeInConfig bargeInConfig;
  final VoiceRuntimeProfile activeProfile;
  final bool isCustomProfile;
  final VoiceTuningRecommendation tuningRecommendation;
  final ValueChanged<VoiceRuntimeProfile> onProfileChanged;
  final ValueChanged<VoiceWakeConfig> onWakeConfigChanged;
  final ValueChanged<VoiceAudioGateConfig> onAudioGateConfigChanged;
  final ValueChanged<BargeInConfig> onBargeInConfigChanged;
  final VoidCallback onApplyTuningRecommendation;
  final VoidCallback onRefreshGatewayHealth;
  final ValueChanged<VoiceDebugSampleLabel> onSaveSample;
  final List<VoiceDebugSample> recentSamples;
  final VoiceDebugSampleSummary sampleSummary;
  final String? sampleExportPath;
  final VoidCallback onClearSamples;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.78),
      letterSpacing: 0,
    );
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF101820),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _Field('state', snapshot.voiceState.name, style),
              _Field('duration', '${snapshot.durationMs}ms', style),
              _Field('speech', '${snapshot.speechDurationMs}ms', style),
              _Field('avgRms', snapshot.avgRms.toStringAsFixed(1), style),
              _Field('maxRms', snapshot.maxRms.toStringAsFixed(1), style),
              _Field(
                'ratio',
                snapshot.speechLikeRatio.toStringAsFixed(3),
                style,
              ),
              _Field('record', snapshot.recordReason, style),
              _Field('callStt', snapshot.callStt.toString(), style),
              _Field('gate', snapshot.gateReason, style),
              _Field('gateFlags', snapshot.gateFlags.join(','), style),
              _Field('text', snapshot.normalizedText, style),
              _Field('sttFlags', snapshot.sttFlags.join(','), style),
              _Field('wake', snapshot.wakeWord, style),
              _Field('match', snapshot.matchType, style),
              _Field('score', snapshot.wakeScore.toStringAsFixed(2), style),
              _Field('command', snapshot.command, style),
              _Field('wakeCd', snapshot.wakeCooldownActive.toString(), style),
              _Field('ttsCd', snapshot.ttsCooldownActive.toString(), style),
              _Field('life', snapshot.lifecycleState, style),
              _Field('lifeReason', snapshot.lifecycleReason, style),
              _Field('permission', snapshot.permissionStatus, style),
              _Field(
                'recordingBusy',
                snapshot.recordingInProgress.toString(),
                style,
              ),
              _Field('warning', snapshot.runtimeWarning, style),
              _Field('profile', snapshot.voiceProfile, style),
              _Field(
                'customProfile',
                snapshot.isCustomVoiceProfile.toString(),
                style,
              ),
              _Field('profileSource', snapshot.profileSource, style),
              _Field('wakeDetector', snapshot.wakeDetectorType, style),
              _Field('detectorStatus', snapshot.wakeDetectorStatus, style),
              _Field('barge', snapshot.bargeInDetected.toString(), style),
              _Field(
                'bargeAvg',
                snapshot.bargeInAvgRms.toStringAsFixed(1),
                style,
              ),
              _Field(
                'bargeMax',
                snapshot.bargeInMaxRms.toStringAsFixed(1),
                style,
              ),
              _Field(
                'bargeRatio',
                snapshot.bargeInSpeechLikeRatio.toStringAsFixed(3),
                style,
              ),
              _Field('bargeReason', snapshot.bargeInReason, style),
            ],
          ),
          const SizedBox(height: 8),
          _ProfileSelector(
            activeProfile: activeProfile,
            isCustomProfile: isCustomProfile,
            onChanged: onProfileChanged,
          ),
          const SizedBox(height: 8),
          _ServiceStatus(snapshot: snapshot, onRefresh: onRefreshGatewayHealth),
          const SizedBox(height: 8),
          _SliderRow(
            label: 'minAvgRms',
            value: audioGateConfig.minAvgRms,
            min: 0,
            max: 500,
            onChanged: (value) => onAudioGateConfigChanged(
              audioGateConfig.copyWith(minAvgRms: value),
            ),
          ),
          _SliderRow(
            label: 'minMaxRms',
            value: audioGateConfig.minMaxRms,
            min: 0,
            max: 3000,
            onChanged: (value) => onAudioGateConfigChanged(
              audioGateConfig.copyWith(minMaxRms: value),
            ),
          ),
          _SliderRow(
            label: 'minSpeechRatio',
            value: audioGateConfig.minSpeechLikeRatio,
            min: 0,
            max: 0.5,
            divisions: 50,
            onChanged: (value) => onAudioGateConfigChanged(
              audioGateConfig.copyWith(minSpeechLikeRatio: value),
            ),
          ),
          _SliderRow(
            label: 'wakeScore',
            value: wakeConfig.wakeScoreThreshold,
            min: 0.5,
            max: 1.0,
            divisions: 50,
            onChanged: (value) => onWakeConfigChanged(
              wakeConfig.copyWith(wakeScoreThreshold: value),
            ),
          ),
          _SliderRow(
            label: 'silenceMs',
            value: wakeConfig.conversationSilenceTimeout.inMilliseconds
                .toDouble(),
            min: 300,
            max: 3000,
            onChanged: (value) => onWakeConfigChanged(
              wakeConfig.copyWith(
                conversationSilenceTimeout: Duration(
                  milliseconds: value.round(),
                ),
              ),
            ),
          ),
          _SliderRow(
            label: 'startMs',
            value: wakeConfig.conversationStartTimeout.inMilliseconds
                .toDouble(),
            min: 500,
            max: 8000,
            onChanged: (value) => onWakeConfigChanged(
              wakeConfig.copyWith(
                conversationStartTimeout: Duration(milliseconds: value.round()),
              ),
            ),
          ),
          _SliderRow(
            label: 'idleSec',
            value: wakeConfig.conversationIdleTimeout.inSeconds.toDouble(),
            min: 5,
            max: 60,
            onChanged: (value) => onWakeConfigChanged(
              wakeConfig.copyWith(
                conversationIdleTimeout: Duration(seconds: value.round()),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SampleButton(
                '正常唤醒',
                VoiceDebugSampleLabel.normalWake,
                onSaveSample,
              ),
              _SampleButton(
                '误唤醒',
                VoiceDebugSampleLabel.falseWake,
                onSaveSample,
              ),
              _SampleButton(
                '漏唤醒',
                VoiceDebugSampleLabel.missedWake,
                onSaveSample,
              ),
              _SampleButton(
                '正确忽略',
                VoiceDebugSampleLabel.ignoredCorrectly,
                onSaveSample,
              ),
              _SampleButton(
                '正常打断',
                VoiceDebugSampleLabel.normalBargeIn,
                onSaveSample,
              ),
              _SampleButton(
                '误打断',
                VoiceDebugSampleLabel.falseBargeIn,
                onSaveSample,
              ),
            ],
          ),
          VoiceDebugSamplesView(
            samples: recentSamples,
            summary: sampleSummary,
            exportPath: sampleExportPath,
            onClear: onClearSamples,
          ),
          VoiceTuningRecommendationView(
            recommendation: tuningRecommendation,
            onApply: onApplyTuningRecommendation,
          ),
        ],
      ),
    );
  }
}

class _ProfileSelector extends StatelessWidget {
  const _ProfileSelector({
    required this.activeProfile,
    required this.isCustomProfile,
    required this.onChanged,
  });

  final VoiceRuntimeProfile activeProfile;
  final bool isCustomProfile;
  final ValueChanged<VoiceRuntimeProfile> onChanged;

  @override
  Widget build(BuildContext context) {
    final preset = VoiceProfilePreset.forProfile(activeProfile);
    final description = isCustomProfile
        ? VoiceProfilePreset.custom.description
        : preset.description;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('语音模式', style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(width: 12),
            DropdownButton<VoiceRuntimeProfile>(
              value: activeProfile,
              dropdownColor: const Color(0xFF182430),
              items: VoiceRuntimeProfile.values
                  .map(
                    (profile) => DropdownMenuItem<VoiceRuntimeProfile>(
                      value: profile,
                      child: Text(profile.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (profile) {
                if (profile != null) {
                  onChanged(profile);
                }
              },
            ),
          ],
        ),
        Text(
          description,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.68),
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ServiceStatus extends StatelessWidget {
  const _ServiceStatus({required this.snapshot, required this.onRefresh});

  final VoiceDebugSnapshot snapshot;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
      color: Colors.white.withValues(alpha: 0.78),
      letterSpacing: 0,
    );
    final checkedAt = snapshot.gatewayCheckedAt.millisecondsSinceEpoch == 0
        ? '-'
        : snapshot.gatewayCheckedAt.toIso8601String();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('服务状态', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _Field('Gateway', snapshot.gatewayOk.toString(), style),
            _Field('STT', snapshot.sttOk.toString(), style),
            _Field('LLM', snapshot.llmOk.toString(), style),
            _Field('TTS', snapshot.ttsOk.toString(), style),
            _Field('checked', checkedAt, style),
            _Field('reason', snapshot.gatewayHealthReason, style),
          ],
        ),
        const SizedBox(height: 6),
        FilledButton.tonalIcon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('重新检测'),
        ),
      ],
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(min, max).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 96,
          child: Text(
            '$label ${clamped.toStringAsFixed(label.endsWith('Ratio') || label == 'wakeScore' ? 2 : 0)}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        Expanded(
          child: Slider(
            value: clamped,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _SampleButton extends StatelessWidget {
  const _SampleButton(this.label, this.value, this.onPressed);

  final String label;
  final VoiceDebugSampleLabel value;
  final ValueChanged<VoiceDebugSampleLabel> onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonal(
      onPressed: () => onPressed(value),
      child: Text(label),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, this.style);

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text('$label: ${value.isEmpty ? '-' : value}', style: style);
  }
}
