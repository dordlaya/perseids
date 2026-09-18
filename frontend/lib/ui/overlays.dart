import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../game/space_map_game.dart';
import '../models/models.dart';

import 'package:flame/components.dart';

import 'helpers.dart';

import 'dart:ui';
import 'dart:math';

// Deep Space Color Palette
const Color spaceBg = Color(0xB3050C1A);
const Color spaceBorder = Color(0x339FE7FF);
const Color spaceTextPrimary = Color(0xFFE6F3FF);
const Color spaceTextSecondary = Color(0xFF8AA0AD);
const Color spaceAccent = Color(0xFF9FE7FF);
const Color spaceStar = Color(0xFFFFD68C);
const Color spaceOnline = Color(0xFF7CFF9B);
const Color spaceOffline = Color(0xFF5A7D8C);
const Color spaceDanger = Color(0xFFFF8A8A);

BoxDecoration _glassDecoration([double radius = 12.0]) {
  return BoxDecoration(
    color: spaceBg,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: spaceBorder),
    boxShadow: const [
      BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------

class LoginOverlay extends StatefulWidget {
  final SpaceMapGame? game;
  const LoginOverlay({this.game});
  @override
  _LoginOverlayState createState() => _LoginOverlayState();
}

class _LoginOverlayState extends State<LoginOverlay> {
  bool isLoginMode = true;
  final TextEditingController identifierController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  String? error;

  void submit(AppState state) async {
    setState(() => error = null);
    if (isLoginMode) {
      final res = await state.api.login(
        identifierController.text,
        passwordController.text,
      );
      if (res['ok'] == true) {
        state.setSession(res['id'], res['name']);
        state.showLoginModal = false;
        state.notifyListeners();
        _zoomToFullMap(state);
      } else {
        setState(() => error = res['error']);
      }
    } else {
      final res = await state.api.register(
        nameController.text,
        emailController.text,
        passwordController.text,
      );
      if (res['ok'] == true) {
        state.setSession(res['id'], res['name']);
        state.showLoginModal = false;
        state.notifyListeners();
        _zoomToFullMap(state);
      } else {
        setState(() => error = res['error']);
      }
    }
  }

  void _zoomToFullMap(AppState state) {
    final game = widget.game;
    if (game == null) return;
    // Small delay so the world snapshot has been received before we set bounds
    Future.delayed(const Duration(milliseconds: 300), () {
      final ww = state.world.w > 0 ? state.world.w : 1680;
      final wh = state.world.h > 0 ? state.world.h : 560;
      // Centre the camera on the middle of the world
      game.camera.viewfinder.position = Vector2(ww / 2, wh / 2);
      // Zoom out to fit the whole map
      game.camera.viewfinder.zoom = game.dynamicMinZoom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (!state.showLoginModal) return const SizedBox.shrink();

    return Container(
      color: const Color(0x99000000),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Center(
          child: Container(
            width: 360,
            padding: const EdgeInsets.all(28),
            decoration: _glassDecoration(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PERSEIDS',
                  style: TextStyle(
                    color: spaceTextPrimary,
                    fontSize: 22,
                    letterSpacing: 4,
                    fontWeight: FontWeight.w300,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Join the cosmos',
                  style: TextStyle(color: spaceTextSecondary, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLoginMode
                              ? spaceAccent
                              : Colors.transparent,
                          foregroundColor: isLoginMode
                              ? const Color(0xFF050C1A)
                              : spaceTextSecondary,
                          elevation: 0,
                        ),
                        onPressed: () => setState(() => isLoginMode = true),
                        child: const Text('Log In'),
                      ),
                    ),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: !isLoginMode
                              ? spaceAccent
                              : Colors.transparent,
                          foregroundColor: !isLoginMode
                              ? const Color(0xFF050C1A)
                              : spaceTextSecondary,
                          elevation: 0,
                        ),
                        onPressed: () => setState(() => isLoginMode = false),
                        child: const Text('Register'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (isLoginMode) ...[
                  _input(identifierController, 'Email or username'),
                  const SizedBox(height: 12),
                  _input(passwordController, 'Password', obscure: true),
                ] else ...[
                  _input(nameController, 'Nickname'),
                  const SizedBox(height: 12),
                  _input(emailController, 'Email'),
                  const SizedBox(height: 12),
                  _input(passwordController, 'Password', obscure: true),
                ],
                const SizedBox(height: 24),
                if (error != null)
                  Text(error!, style: const TextStyle(color: spaceDanger)),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () => submit(state),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                  ),
                  child: Text(isLoginMode ? 'Log In' : 'Register'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    state.showLoginModal = false;
                    state.notifyListeners();
                  },
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: spaceTextSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _input(
    TextEditingController controller,
    String hint, {
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: spaceTextPrimary),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: const TextStyle(color: spaceTextSecondary),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: spaceTextSecondary.withOpacity(0.5)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: spaceAccent),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

class HudOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Positioned(
      top: 16,
      left: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: _glassDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'SPACE MAP · LIVE',
                  style: TextStyle(
                    color: spaceTextSecondary,
                    fontSize: 11,
                    letterSpacing: 2.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Probes: ${state.probes.length} / ${state.maxProbes}',
                  style: const TextStyle(color: spaceAccent),
                ),
                Text(
                  'Users: ${state.users.where((u) => u.loggedIn).length} / ${state.users.length}',
                  style: const TextStyle(color: spaceAccent),
                ),
                Text(
                  'Collisions: ${state.collisions}',
                  style: const TextStyle(color: spaceAccent),
                ),
                const SizedBox(height: 2),
                Text(
                  state.isConnected ? 'live' : 'reconnecting...',
                  style: TextStyle(
                    color: state.isConnected ? spaceOnline : spaceDanger,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Session Bar
// ---------------------------------------------------------------------------

class SessionBarOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.sessionUserId == null) return const SizedBox.shrink();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Positioned(
      top: isMobile ? 120 : 14,
      left: 0,
      right: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: _glassDecoration(999),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Signed in as ${state.sessionUserName}',
                    style: const TextStyle(color: spaceAccent),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    onTap: () => state.clearSession(),
                    child: const Text(
                      'Log Out',
                      style: TextStyle(color: spaceTextSecondary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Leaderboard
// ---------------------------------------------------------------------------

class LeaderboardOverlay extends StatefulWidget {
  final SpaceMapGame? game;
  const LeaderboardOverlay({this.game});

  @override
  _LeaderboardOverlayState createState() => _LeaderboardOverlayState();
}

class _LeaderboardOverlayState extends State<LeaderboardOverlay> {
  bool expanded = false;

  void _focusUser(AppState state, int id) {
    final u = state.getUserById(id);
    if (u != null && widget.game != null) {
      widget.game!.moveCameraTo(Vector2(u.x, u.y), zoom: 1.8);
      state.selectedUserId = u.id;
      state.notifyListeners();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 600;

    final sortedUsers = List.of(state.users)
      ..sort((a, b) => b.r.compareTo(a.r));
    final top10 = sortedUsers.take(10).toList();

    return Positioned(
      top: isMobile ? 16 : 56,
      right: 16,
      width: isMobile ? 160 : 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: _glassDecoration(),
            child: Column(
              children: [
                InkWell(
                  onTap: () => setState(() => expanded = !expanded),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🏆 Leaderboard',
                          style: TextStyle(
                            color: spaceTextPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Icon(
                          expanded
                              ? Icons.keyboard_arrow_down
                              : Icons.keyboard_arrow_left,
                          color: spaceTextSecondary,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                if (expanded)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 400),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: top10.length,
                      itemBuilder: (context, i) {
                        final u = top10[i];
                        return InkWell(
                          onTap: () => _focusUser(state, u.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
                              vertical: 6.0,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    '${i + 1}',
                                    style: const TextStyle(
                                      color: spaceTextSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u.name,
                                        style: const TextStyle(
                                          color: spaceTextPrimary,
                                          fontSize: 12.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        getSectorName(u.sector),
                                        style: const TextStyle(
                                          color: spaceTextSecondary,
                                          fontSize: 10.5,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '${u.r.toStringAsFixed(1)}px',
                                  style: const TextStyle(
                                    color: spaceStar,
                                    fontSize: 11.5,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: u.loggedIn
                                        ? spaceOnline
                                        : spaceOffline,
                                    boxShadow: u.loggedIn
                                        ? const [
                                            BoxShadow(
                                              color: spaceOnline,
                                              blurRadius: 4,
                                            ),
                                          ]
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Star Info Panel
// ---------------------------------------------------------------------------

class StarInfoOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.selectedUserId == null) return const SizedBox.shrink();

    final u = state.getUserById(state.selectedUserId!);
    if (u == null) return const SizedBox.shrink();

    final now = DateTime.now().millisecondsSinceEpoch;
    final jammed = u.lastJamAt > 0 && (now - u.lastJamAt) < 60000;
    final arriving = u.gravityUntil > now;

    final statusColor = arriving
        ? spaceAccent
        : jammed
        ? spaceDanger
        : (u.loggedIn ? spaceOnline : spaceOffline);
    final statusText =
        (u.loggedIn ? 'online' : 'offline') +
        (arriving ? ' · arriving' : (jammed ? ' · jammed' : ''));
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Positioned(
      left: isMobile ? 76 : null,
      right: 16,
      bottom: 16,
      width: isMobile ? null : 240,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: _glassDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        u.name,
                        style: const TextStyle(
                          color: spaceStar,
                          fontSize: 16,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        state.selectedUserId = null;
                        state.notifyListeners();
                      },
                      child: const Icon(
                        Icons.close,
                        color: spaceTextSecondary,
                        size: 16,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow('sector', getSectorName(u.sector)),
                _infoRow('status', statusText, valColor: statusColor),
                if (arriving)
                  _infoRow(
                    'gravity',
                    'offline · ${fmtClock(u.gravityUntil - now)}',
                    valColor: spaceAccent,
                  ),
                _infoRow('pull force', '${(u.pull * 100).round()}%'),
                _infoRow('age', formatDuration(now - u.createdAt)),
                _infoRow('absorbed', '${u.hits}'),
                _infoRow('size', '${u.r.toStringAsFixed(1)} px'),
                _infoRow('growth', '+${(u.r - 10.0).toStringAsFixed(1)} px'),
                _infoRow(
                  'position',
                  '${u.x.toStringAsFixed(0)}, ${u.y.toStringAsFixed(0)}',
                ),

                if (u.id == state.sessionUserId) ...[
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: spaceStar,
                      foregroundColor: const Color(0xFF050C1A),
                      minimumSize: const Size.fromHeight(38),
                    ),
                    onPressed: () => state.api.setStatus(u.id, !u.loggedIn),
                    child: Text(u.loggedIn ? 'Go Dark' : 'Go Live'),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: spaceAccent.withOpacity(0.16),
                      foregroundColor: spaceAccent,
                      elevation: 0,
                      side: const BorderSide(color: spaceAccent),
                      minimumSize: const Size.fromHeight(38),
                    ),
                    onPressed: !u.loggedIn || u.moveReadyAt > now
                        ? null
                        : () => _openMoveDialog(context, state, u),
                    child: Text(
                      u.moveReadyAt > now
                          ? 'Move cooldown · ${fmtClock(u.moveReadyAt - now)}'
                          : 'Move to another galaxy',
                    ),
                  ),
                ],

                if (state.sessionUserId != null &&
                    u.id != state.sessionUserId) ...[
                  const SizedBox(height: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: spaceDanger.withOpacity(0.2),
                      foregroundColor: spaceDanger,
                      elevation: 0,
                      side: const BorderSide(color: spaceDanger),
                      minimumSize: const Size.fromHeight(38),
                    ),
                    onPressed: arriving
                        ? null
                        : () => state.api.jam(state.sessionUserId!, u.id),
                    child: const Text('Jam −25%'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMoveDialog(
    BuildContext context,
    AppState state,
    UserSnap user,
  ) async {
    await state.refreshSectors();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        int? selected;
        String? error;
        bool submitting = false;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            backgroundColor: const Color(0xFF081321),
            title: const Text(
              'Move to a galaxy',
              style: TextStyle(color: spaceTextPrimary),
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Your gravity will be offline for 30 seconds after arrival.',
                    style: TextStyle(color: spaceTextSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  ...state.sectors
                      .where((sector) => sector.id != user.sector)
                      .map(
                        (sector) => RadioListTile<int>(
                          value: sector.id,
                          groupValue: selected,
                          onChanged: sector.available && !submitting
                              ? (value) => setState(() => selected = value)
                              : null,
                          title: Text(
                            sector.name,
                            style: const TextStyle(color: spaceTextPrimary),
                          ),
                          subtitle: Text(
                            '${sector.occupied}/${sector.capacity} stars'
                            '${sector.available ? '' : ' · Full'}',
                            style: TextStyle(
                              color: sector.available
                                  ? spaceTextSecondary
                                  : spaceDanger,
                            ),
                          ),
                          activeColor: spaceAccent,
                        ),
                      ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: spaceDanger)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: submitting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selected == null || submitting
                    ? null
                    : () async {
                        setState(() => submitting = true);
                        final result = await state.api.move(user.id, selected!);
                        if (result['ok'] == true) {
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          await state.refreshSectors();
                          if (context.mounted) {
                            setState(() {
                              submitting = false;
                              error = result['error']?.toString() ?? 'move_failed';
                            });
                          }
                        }
                      },
                child: Text(submitting ? 'Moving...' : 'Move'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value, {Color? valColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: spaceTextSecondary, fontSize: 11.5),
          ),
          Text(
            value,
            style: TextStyle(
              color: valColor ?? spaceTextPrimary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Controls & Search
// ---------------------------------------------------------------------------

class ControlsOverlay extends StatelessWidget {
  final SpaceMapGame? game;
  const ControlsOverlay({this.game});

  void zoom(double factor) {
    if (game != null) {
      final z = game!.camera.viewfinder.zoom * factor;
      game!.camera.viewfinder.zoom = z.clamp(game!.dynamicMinZoom, SpaceMapGame.maxZoomLimit);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final me = state.sessionUserId != null
        ? state.getUserById(state.sessionUserId!)
        : null;

    final now = DateTime.now().millisecondsSinceEpoch;
    bool isBoosting = false;
    bool canBoost = false;
    int cooldown = 0;

    if (me != null && me.loggedIn) {
      final at = me.boostAt;
      if (now - at < 60000) {
        isBoosting = true;
      } else if (now < at + 600000) {
        cooldown = (at + 600000) - now;
      } else {
        canBoost = true;
      }
    }

    return Positioned(
      left: 16,
      bottom: 16,
      child: Column(
        children: [
          if (state.sessionUserId != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10.0),
              child: FloatingActionButton(
                mini: true,
                backgroundColor: isBoosting ? spaceDanger : spaceBg,
                foregroundColor: isBoosting
                    ? Colors.white
                    : (canBoost ? spaceAccent : spaceTextSecondary),
                elevation: 4,
                onPressed: canBoost
                    ? () => state.api.boost(state.sessionUserId!)
                    : null,
                child: Text(
                  cooldown > 0 ? fmtClock(cooldown) : '⚡',
                  style: TextStyle(fontSize: cooldown > 0 ? 11 : 22),
                ),
              ),
            ),

          if (me != null)
            _btn(Icons.my_location, () {
              if (game != null) {
                game!.moveCameraTo(Vector2(me.x, me.y), zoom: 1.8);
                state.selectedUserId = me.id;
                state.notifyListeners();
              }
            }),

          _btn(Icons.add, () => zoom(1.25)),
          _btn(Icons.remove, () => zoom(1 / 1.25)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: InkWell(
        onTap: onPressed,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              width: 44,
              height: 44,
              decoration: _glassDecoration(10),
              child: Icon(icon, color: spaceAccent, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

class SearchOverlay extends StatefulWidget {
  final SpaceMapGame? game;
  const SearchOverlay({this.game});

  @override
  _SearchOverlayState createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  List<dynamic> _results = [];

  void _runSearch(AppState state, String q) {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }

    q = q.toLowerCase();
    final items = [];

    // Sectors
    final n = max(1, (state.users.length / 10).ceil());
    for (int i = 0; i < n; i++) {
      if (getSectorName(i).toLowerCase().contains(q)) {
        items.add({
          'kind': 'sector',
          'label': getSectorName(i),
          'sub': 'sector',
          'index': i,
        });
      }
    }

    // Stars
    for (final u in state.users) {
      if (u.name.toLowerCase().contains(q)) {
        items.add({
          'kind': 'star',
          'label': u.name,
          'sub': 'star · ${getSectorName(u.sector)}',
          'user': u,
        });
      }
    }

    setState(() {
      _results = items.take(8).toList();
    });
  }

  void _pick(AppState state, dynamic item) {
    if (widget.game != null) {
      if (item['kind'] == 'star') {
        final u = item['user'] as UserSnap;
        widget.game!.moveCameraTo(Vector2(u.x, u.y), zoom: 1.8);
        state.selectedUserId = u.id;
        state.notifyListeners();
      } else {
        final i = item['index'] as int;
        final col = i % 4;
        final row = i ~/ 4;
        final cx = col * 560.0 + 280.0;
        final cy = row * 560.0 + 280.0;
        widget.game!.moveCameraTo(Vector2(cx, cy), zoom: 0.5);
      }
    }
    _searchController.clear();
    setState(() => _results = []);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Positioned(
      top: isMobile ? (state.sessionUserId != null ? 180 : 130) : 60,
      left: isMobile ? 16 : 244,
      right: isMobile ? 16 : null,
      width: isMobile ? null : 360,
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => _runSearch(state, v),
                decoration: InputDecoration(
                  hintText: 'Search star or sector...',
                  hintStyle: const TextStyle(color: spaceTextSecondary),
                  filled: true,
                  fillColor: spaceBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: const TextStyle(color: spaceTextPrimary, fontSize: 13),
              ),
            ),
          ),
          if (_results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              decoration: _glassDecoration(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final res = _results[i];
                      return InkWell(
                        onTap: () => _pick(state, res),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12.0,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: res['kind'] == 'star'
                                      ? spaceStar
                                      : spaceAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: res['kind'] == 'star'
                                          ? spaceStar
                                          : spaceAccent,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  res['label'],
                                  style: const TextStyle(
                                    color: spaceTextPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              Text(
                                res['sub'],
                                style: const TextStyle(
                                  color: spaceTextSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
