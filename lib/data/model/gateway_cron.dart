class GatewayCronJob {
  final String id;
  final String? name;
  final bool? enabled;
  final Map<String, dynamic> raw;

  const GatewayCronJob({
    required this.id,
    this.name,
    this.enabled,
    this.raw = const <String, dynamic>{},
  });

  factory GatewayCronJob.fromJson(Map<String, dynamic> json) {
    final id =
        (json['id'] ?? json['jobId'] ?? json['key'])?.toString().trim() ?? '';
    return GatewayCronJob(
      id: id,
      name: (json['name'] ?? json['title'])?.toString(),
      enabled: json['enabled'] as bool?,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class GatewayCronList {
  final List<GatewayCronJob> jobs;
  final Map<String, dynamic> raw;

  const GatewayCronList({this.jobs = const [], this.raw = const {}});

  factory GatewayCronList.fromJson(Map<String, dynamic> json) {
    final rawJobs = json['jobs'] ?? json['items'] ?? json['entries'];
    final jobs =
        rawJobs is List
            ? rawJobs
                .whereType<Map>()
                .map(
                  (item) =>
                      GatewayCronJob.fromJson(item.cast<String, dynamic>()),
                )
                .where((job) => job.id.isNotEmpty)
                .toList(growable: false)
            : const <GatewayCronJob>[];
    return GatewayCronList(jobs: jobs, raw: Map<String, dynamic>.from(json));
  }
}

class GatewayCronRuns {
  final List<Map<String, dynamic>> entries;
  final Map<String, dynamic> raw;

  const GatewayCronRuns({this.entries = const [], this.raw = const {}});

  factory GatewayCronRuns.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] ?? json['runs'] ?? json['items'];
    final entries =
        rawEntries is List
            ? rawEntries
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList(growable: false)
            : const <Map<String, dynamic>>[];
    return GatewayCronRuns(
      entries: entries,
      raw: Map<String, dynamic>.from(json),
    );
  }
}
