class VisionCheckResult {
  const VisionCheckResult({
    required this.ok,
    required this.label,
    this.detail,
    this.imageBytes,
  });

  final bool ok;
  final String label;
  final String? detail;
  final List<int>? imageBytes;
}
