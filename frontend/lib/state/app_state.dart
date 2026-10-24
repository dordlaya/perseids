import 'package:flutter/material.dart';

import 'dart:async';
import 'dart:math';

import '../models/models.dart';
import '../api/client.dart';

import 'dart:convert';

import 'package:web/web.dart' as web;

class DisplayProbe {
  final int id;
  double x;
  double y;
  double tx;
  double ty;
  double hue;
  List<Offset> trail = [];

  DisplayProbe({
    required this.id,
    required this.x,
    required this.y,
    required this.tx,
    required this.ty,
    required this.hue,
  });
}

class AppState extends ChangeNotifier {
  // Keep the previous account online while switching users during
  // development. Set PRESERVE_USERS_ON_LOGOUT=false to revoke the session
  // and mark the user offline immediately instead.
  static const bool preserveUsersOnLogout = bool.fromEnvironment(
    'PRESERVE_USERS_ON_LOGOUT',
    defaultValue: true,
  );

  final ApiClient api = ApiClient();

  bool isConnected = false;

  int collisions = 0;
  int maxProbes = 10;
  double spawnInterval = 10.0;
  int serverRev = -1;
  WorldSnap world = WorldSnap(w: 0, h: 0);

  List<UserSnap> users = [];
  List<SectorSnap> sectors = [];
  List<DisplayProbe> probes = [];
  Map<int, DisplayProbe> _probeById = {};

  int? sessionUserId;
  String? sessionUserName;
  int? previewUserId;
  int? selectedUserId;
  final Map<String, int> _jamCooldowns = {};

  bool showLoginModal = false;
  Timer? _heartbeatTimer;

  // Jam toast: set when the player's own star is jammed, cleared after display.
  String? jamToastMessage;
  int _lastSeenJamAt = 0;

  AppState() {
    _loadSession();

    // If a session token is rejected (expired, or revoked from another
    // tab), drop back to a clean logged-out state instead of every
    // subsequent action silently failing.
    api.onUnauthorized = () {
      clearSession();
      showLoginModal = true;
      notifyListeners();
    };

    api.connectionStream.listen((connected) {
      isConnected = connected;
      notifyListeners();
    });

    api.snapshotStream.listen(_applySnapshot);

    api.connectStream();
  }

  void _loadSession() {
    try {
      final sessionStr = web.window.localStorage.getItem('spacemap.session');
      if (sessionStr != null) {
        final session = jsonDecode(sessionStr);
        sessionUserId = session['id'];
        sessionUserName = session['name'];
        final token = session['token'];
        if (token is String && token.isNotEmpty) {
          api.authToken = token;
        }
      }
    } catch (_) {}
    // No token means we can't authenticate any request even if an id/name
    // happen to be cached, so treat that as logged out.
    if (sessionUserId == null || api.authToken == null) {
      clearSession();
      showLoginModal = true;
    } else {
      _startHeartbeat();
    }
  }

  /// Called after a successful register/login. [token] is the bearer token
  /// the server issued; api.authToken is already set by ApiClient at that
  /// point, but we persist it here so it survives a page refresh.
  void setSession(int id, String name, String token) {
    sessionUserId = id;
    sessionUserName = name;
    api.authToken = token;
    web.window.localStorage.setItem(
      'spacemap.session',
      jsonEncode({'id': id, 'name': name, 'token': token}),
    );
    _startHeartbeat();
    notifyListeners();
  }

  void clearSession() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    sessionUserId = null;
    sessionUserName = null;
    api.clearToken();
    web.window.localStorage.removeItem('spacemap.session');
    notifyListeners();
  }

  /// Ends the local session, optionally preserving server-side presence.
  Future<void> logout() async {
    if (!preserveUsersOnLogout) {
      await api.logout();
    }
    clearSession();
  }

  int jamCooldownUntilFor(int targetUserId) {
    final attackerId = sessionUserId;
    if (attackerId == null) return 0;
    return _jamCooldowns['$attackerId:$targetUserId'] ?? 0;
  }

  void onStarTapped(int userId) {
    if (previewUserId == userId) {
      selectedUserId = userId;
    } else {
      previewUserId = userId;
      selectedUserId = null;
    }
    notifyListeners();
  }

  void showUserDetails(int userId) {
    previewUserId = userId;
    selectedUserId = userId;
    notifyListeners();
  }

  void clearStarSelection() {
    previewUserId = null;
    selectedUserId = null;
    notifyListeners();
  }

  Future<Map<String, dynamic>> jam(int targetUserId) async {
    final attackerId = sessionUserId;
    if (attackerId == null) {
      jamToastMessage = 'Log in to jam another star.';
      notifyListeners();
      return {'ok': false, 'error': 'unauthorized'};
    }

    final result = await api.jam(targetUserId);
    final cooldownUntil = result['cooldownUntil'];
    if (cooldownUntil is num) {
      _jamCooldowns['$attackerId:$targetUserId'] = cooldownUntil.toInt();
    }
    final targetName = getUserById(targetUserId)?.name ?? 'star';
    final error = result['error'];
    jamToastMessage = result['ok'] == true
        ? 'Jammed $targetName — +${result['rewardPercent'] ?? 1}% pull for 60 s (total +${result['rewardTotalPercent'] ?? 1}%)'
        : switch (error) {
            'self' => 'You cannot jam your own star.',
            'not_found' => 'That star could not be found.',
            'target_offline' => '$targetName is offline and cannot be jammed.',
            'offline' => 'Go online before jamming another star.',
            'in_transit' => 'You cannot jam while in transit.',
            'target_boosted' => '$targetName is boosted and immune to jams.',
            'cooldown' => 'Your jam cooldown for $targetName is still active.',
            _ => 'Could not jam $targetName.',
          };
    notifyListeners();
    return result;
  }

  Future<Map<String, dynamic>> setAppearance(String appearanceId) async {
    final result = await api.setAppearance(appearanceId);
    if (result['ok'] != true || sessionUserId == null) return result;

    users = users
        .map(
          (user) => user.id == sessionUserId
              ? user.copyWith(appearanceId: appearanceId)
              : user,
        )
        .toList();
    notifyListeners();
    return result;
  }

  void _startHeartbeat() {
    if (sessionUserId == null) return;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (isConnected) {
        api.heartbeat();
      }
    });
    api.heartbeat();
  }

  void _applySnapshot(Snapshot snap) {
    collisions = snap.collisions;
    maxProbes = snap.maxProbes;
    spawnInterval = snap.spawnInterval;

    if (snap.users != null) {
      users = snap.users!;
      if (snap.world != null) {
        world = snap.world!;
      }
      if (snap.rev != null && snap.rev != serverRev) {
        serverRev = snap.rev!;
        _validateSession();
      }
      // Detect when the player's own star gets newly jammed.
      _checkJamToast();
    }

    Set<int> seen = {};
    for (var s in snap.probes) {
      seen.add(s.id);
      var p = _probeById[s.id];
      if (p == null) {
        p = DisplayProbe(id: s.id, x: s.x, y: s.y, tx: s.x, ty: s.y, hue: s.hue);
        _probeById[s.id] = p;
        probes.add(p);
      } else {
        p.tx = s.x;
        p.ty = s.y;
        p.hue = s.hue;
      }
    }

    probes.removeWhere((p) {
      if (!seen.contains(p.id)) {
        _probeById.remove(p.id);
        return true;
      }
      return false;
    });

    notifyListeners();
  }

  void _validateSession() {
    if (sessionUserId == null) return;
    final me = getUserById(sessionUserId!);
    if (me == null || (sessionUserName != null && me.name.toLowerCase() != sessionUserName!.toLowerCase())) {
      clearSession();
    }
  }

  void _checkJamToast() {
    if (sessionUserId == null) return;
    final me = getUserById(sessionUserId!);
    if (me == null) return;
    // Fire a toast when lastJamAt is newer than the last one we already showed.
    if (me.lastJamAt > 0 && me.lastJamAt != _lastSeenJamAt) {
      _lastSeenJamAt = me.lastJamAt;
      final by = me.lastJamBy.isNotEmpty ? me.lastJamBy : 'someone';
      jamToastMessage = '⚡ Jammed by $by — pull −25% for 60 s';
      notifyListeners();
    }
  }

  void dismissJamToast() {
    if (jamToastMessage != null) {
      jamToastMessage = null;
      notifyListeners();
    }
  }

  UserSnap? getUserById(int id) {
    try {
      return users.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshSectors() async {
    sectors = await api.getSectors();
    notifyListeners();
  }

  void stepDisplay(double dt) {
    // Frame-rate independent smoothing: the same response is produced at
    // 30, 60, or 120 FPS.
    final pk = 1 - exp(-18 * dt.clamp(0.0, 0.1));
    for (var p in probes) {
      p.x += (p.tx - p.x) * pk;
      p.y += (p.ty - p.y) * pk;
      p.trail.add(Offset(p.x, p.y));
      if (p.trail.length > 26) {
        p.trail.removeAt(0);
      }
    }
    // Don't notifyListeners here, Flame will access this state in its update loop
    // to avoid excessive Flutter rebuilds.
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    api.dispose();
    super.dispose();
  }
}
