const List<String> sectorWords = [
  'Andromeda', 'Cygnus', 'Draco', 'Eridanus', 'Fornax', 'Hydra', 'Indus', 'Lyra',
  'Orion', 'Perseus', 'Phoenix', 'Serpens', 'Tucana', 'Vela', 'Carina', 'Pyxis',
];

String getSectorName(int i) {
  final base = sectorWords[i % sectorWords.length];
  final tier = i ~/ sectorWords.length;
  return tier > 0 ? '$base-${tier + 1}' : base;
}

String formatDuration(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  if (h > 0) return '${h}h ${m}m ${sec}s';
  if (m > 0) return '${m}m ${sec}s';
  return '${sec}s';
}

String fmtClock(int ms) {
  final s = (ms / 1000).ceil();
  final m = s ~/ 60;
  final sec = s % 60;
  return m > 0 ? '$m:${sec.toString().padLeft(2, '0')}' : '${sec}s';
}

String formatTimeAgo(int timestampMs) {
  if (timestampMs <= 0) return '';
  final diff = DateTime.now().millisecondsSinceEpoch - timestampMs;
  if (diff < 3000) return 'Just now';
  final s = diff ~/ 1000;
  if (s < 60) return '${s}s ago';
  final m = s ~/ 60;
  if (m < 60) return '${m}m ago';
  final h = m ~/ 60;
  if (h < 24) return '${h}h ago';
  return '${h ~/ 24}d ago';
}
