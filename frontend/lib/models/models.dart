class WorldSnap {
  final double w;
  final double h;

  WorldSnap({required this.w, required this.h});

  factory WorldSnap.fromJson(Map<String, dynamic> json) {
    return WorldSnap(
      w: (json['w'] as num?)?.toDouble() ?? 0.0,
      h: (json['h'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class UserSnap {
  final int id;
  final String name;
  final double x;
  final double y;
  final double r;
  final int hits;
  final bool loggedIn;
  final double pull;
  final double pulse;
  final int createdAt;
  final int sector;
  final int boostAt;
  final int gravityUntil;
  final int moveReadyAt;
  final int lastJamAt;
  final String lastJamBy;

  UserSnap({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.r,
    required this.hits,
    required this.loggedIn,
    required this.pull,
    required this.pulse,
    required this.createdAt,
    required this.sector,
    required this.boostAt,
    required this.gravityUntil,
    required this.moveReadyAt,
    required this.lastJamAt,
    required this.lastJamBy,
  });

  factory UserSnap.fromJson(Map<String, dynamic> json) {
    return UserSnap(
      id: json['id'] as int,
      name: json['name'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      r: (json['r'] as num).toDouble(),
      hits: json['hits'] as int,
      loggedIn: json['loggedIn'] as bool? ?? false,
      pull: (json['pull'] as num?)?.toDouble() ?? 0.0,
      pulse: (json['pulse'] as num?)?.toDouble() ?? 0.0,
      createdAt: json['createdAt'] as int? ?? 0,
      sector: json['sector'] as int? ?? 0,
      boostAt: json['boostAt'] as int? ?? 0,
      gravityUntil: json['gravityUntil'] as int? ?? 0,
      moveReadyAt: json['moveReadyAt'] as int? ?? 0,
      lastJamAt: json['lastJamAt'] as int? ?? 0,
      lastJamBy: json['lastJamBy'] as String? ?? '',
    );
  }

}

class SectorSnap {
  final int id;
  final String name;
  final int occupied;
  final int capacity;
  final bool available;

  SectorSnap({
    required this.id,
    required this.name,
    required this.occupied,
    required this.capacity,
    required this.available,
  });

  factory SectorSnap.fromJson(Map<String, dynamic> json) {
    return SectorSnap(
      id: json['id'] as int,
      name: json['name'] as String,
      occupied: json['occupied'] as int? ?? 0,
      capacity: json['capacity'] as int? ?? 10,
      available: json['available'] as bool? ?? false,
    );
  }
}

class ProbeSnap {
  final int id;
  final double x;
  final double y;
  final double hue;

  ProbeSnap({
    required this.id,
    required this.x,
    required this.y,
    required this.hue,
  });

  factory ProbeSnap.fromJson(Map<String, dynamic> json) {
    return ProbeSnap(
      id: json['id'] as int,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      hue: (json['hue'] as num?)?.toDouble() ?? 180.0,
    );
  }
}

class Snapshot {
  final int t;
  final int collisions;
  final int maxProbes;
  final double spawnInterval;
  final List<ProbeSnap> probes;
  final int? rev;
  final WorldSnap? world;
  final List<UserSnap>? users;

  Snapshot({
    required this.t,
    required this.collisions,
    required this.maxProbes,
    required this.spawnInterval,
    required this.probes,
    this.rev,
    this.world,
    this.users,
  });

  factory Snapshot.fromJson(Map<String, dynamic> json) {
    return Snapshot(
      t: json['t'] as int? ?? 0,
      collisions: json['collisions'] as int? ?? 0,
      maxProbes: json['maxProbes'] as int? ?? 10,
      spawnInterval: (json['spawnInterval'] as num?)?.toDouble() ?? 10.0,
      probes: (json['probes'] as List<dynamic>?)
              ?.map((e) => ProbeSnap.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      rev: json['rev'] as int?,
      world: json['world'] != null ? WorldSnap.fromJson(json['world']) : null,
      users: (json['users'] as List<dynamic>?)
          ?.map((e) => UserSnap.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
