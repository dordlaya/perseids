import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../state/app_state.dart';
import '../game/space_map_game.dart';
import '../models/models.dart';

import 'package:flame/components.dart' hide Timer;

import 'helpers.dart';
import '../game/components/star_component.dart' show starTierName;

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
  StarAppearance selectedAppearance = StarAppearance.haloRing;
  String? error;

  void submit(AppState state) async {
    setState(() => error = null);
    if (isLoginMode) {
      final res = await state.api.login(
        identifierController.text,
        passwordController.text,
      );
      if (res['ok'] == true) {
        state.setSession(res['id'], res['name'], res['token'] as String);
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
        appearanceId: selectedAppearance.id,
      );
      if (res['ok'] == true) {
        state.setSession(res['id'], res['name'], res['token'] as String);
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
                  const SizedBox(height: 18),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Choose your star',
                      style: TextStyle(color: spaceTextSecondary, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StarAppearanceChoiceStrip(
                    selected: selectedAppearance,
                    onSelected: (appearance) =>
                        setState(() => selectedAppearance = appearance),
                  ),
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

class _StarAppearanceChoiceStrip extends StatelessWidget {
  final StarAppearance selected;
  final ValueChanged<StarAppearance> onSelected;

  const _StarAppearanceChoiceStrip({
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: StarAppearance.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final appearance = StarAppearance.values[index];
          final isSelected = appearance == selected;
          return InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onSelected(appearance),
            child: Container(
              width: 82,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: BoxDecoration(
                color: isSelected ? spaceAccent.withOpacity(0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? spaceAccent.withOpacity(0.65) : spaceBorder,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CustomPaint(
                    size: const Size(34, 34),
                    painter: _AppearanceSwatchPainter(appearance),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    appearance.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isSelected ? spaceAccent : spaceTextSecondary,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AppearanceSwatchPainter extends CustomPainter {
  final StarAppearance appearance;

  const _AppearanceSwatchPainter(this.appearance);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final color = switch (appearance) {
      StarAppearance.haloRing => const Color(0xFF7CFFCF),
      StarAppearance.particles => const Color(0xFF55DFFF),
      StarAppearance.orb => const Color(0xFF62AFFF),
      StarAppearance.swirl => const Color(0xFFB36CFF),
      StarAppearance.coreCircle => const Color(0xFFFFB347),
      StarAppearance.lens => const Color(0xFF25D9F2),
    };
    final glow = Paint()
      ..color = color.withOpacity(0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, size.width * 0.36, glow);

    final fill = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white, color.withOpacity(0.75), color.withOpacity(0.08)],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.34));
    canvas.drawCircle(center, size.width * 0.3, fill);

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    switch (appearance) {
      case StarAppearance.haloRing:
      case StarAppearance.coreCircle:
        canvas.drawCircle(center, size.width * 0.38, ring);
        canvas.drawCircle(center, size.width * 0.47, ring..strokeWidth = 0.8);
      case StarAppearance.particles:
        for (var i = 0; i < 12; i++) {
          final angle = i * 2 * pi / 12;
          canvas.drawCircle(
            Offset(
              center.dx + cos(angle) * size.width * 0.43,
              center.dy + sin(angle) * size.height * 0.43,
            ),
            0.9,
            Paint()..color = color,
          );
        }
      case StarAppearance.orb:
      case StarAppearance.lens:
        canvas.drawOval(
          Rect.fromCenter(
            center: center,
            width: size.width * 0.9,
            height: size.height * 0.34,
          ),
          ring,
        );
      case StarAppearance.swirl:
        final path = Path();
        for (var i = 0; i <= 50; i++) {
          final t = i / 50 * 2.5 * pi;
          final radius = size.width * 0.04 + size.width * 0.36 * i / 50;
          final point = Offset(
            center.dx + cos(t) * radius,
            center.dy + sin(t) * radius,
          );
          if (i == 0) {
            path.moveTo(point.dx, point.dy);
          } else {
            path.lineTo(point.dx, point.dy);
          }
        }
        canvas.drawPath(path, ring);
    }
  }

  @override
  bool shouldRepaint(_AppearanceSwatchPainter oldDelegate) =>
      oldDelegate.appearance != appearance;
}

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

class HudOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Positioned(
      top: 16,
      left: 16,
      width: isMobile ? 184 : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            padding: EdgeInsets.all(isMobile ? 10 : 14),
            decoration: _glassDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Server - Statistics',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: spaceTextSecondary,
                          fontSize: isMobile ? 10 : 11,
                          letterSpacing: isMobile ? 0.5 : 1.2,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: state.isConnected ? spaceOnline : spaceDanger,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isMobile ? 8 : 10),
                if (isMobile)
                  Row(
                    children: [
                      Expanded(
                        child: _mobileStat(
                          'PROBES',
                          '${state.probes.length}/${state.maxProbes}',
                          spaceAccent,
                        ),
                      ),
                      Expanded(
                        child: _mobileStat(
                          'USERS',
                          '${state.users.where((u) => u.loggedIn).length}/${state.users.length}',
                          spaceAccent,
                        ),
                      ),
                      Expanded(
                        child: _mobileStat(
                          'COLLISIONS',
                          '${state.collisions}',
                          spaceAccent,
                        ),
                      ),
                    ],
                  )
                else ...[
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: spaceTextSecondary,
            fontSize: 8,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
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
    if (isMobile) return const SizedBox.shrink();

    return Positioned(
      top: 14,
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
                    onTap: () => state.logout(),
                    child: Text(
                      AppState.preserveUsersOnLogout ? 'Switch User' : 'Log Out',
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
// Unified Left Panel: Leaderboard + Activity Log
// ---------------------------------------------------------------------------

class GamePanelOverlay extends StatefulWidget {
  final SpaceMapGame? game;
  const GamePanelOverlay({super.key, this.game});

  @override
  State<GamePanelOverlay> createState() => _GamePanelOverlayState();
}

class _GamePanelOverlayState extends State<GamePanelOverlay> {
  bool expanded = false;
  int activeTab = 0; // 0 = Leaders, 1 = Log

  void _focusUser(AppState state, int id) {
    final u = state.getUserById(id);
    if (u != null && widget.game != null) {
      widget.game!.moveCameraTo(Vector2(u.x, u.y), zoom: 1.8);
      state.showUserDetails(u.id);
    }
  }

  Widget _eventIcon(String type) {
    IconData icon;
    Color color;
    switch (type) {
      case 'jam_received':
        icon = Icons.flash_on;
        color = spaceDanger;
        break;
      case 'jam_sent':
        icon = Icons.gps_fixed;
        color = const Color(0xFFFF9E79);
        break;
      case 'boost':
        icon = Icons.bolt;
        color = spaceStar;
        break;
      case 'moved':
        icon = Icons.flight_takeoff;
        color = spaceAccent;
        break;
      case 'tier_up':
        icon = Icons.auto_awesome;
        color = const Color(0xFFFFD700);
        break;
      case 'status':
        icon = Icons.power_settings_new;
        color = spaceOnline;
        break;
      case 'birth':
      default:
        icon = Icons.star_border;
        color = spaceAccent;
        break;
    }
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Icon(icon, color: color, size: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 600;

    // Leaderboard data
    final sortedUsers = List.of(state.users)
      ..sort((a, b) => b.r.compareTo(a.r));
    final top10 = sortedUsers.take(10).toList();

    // Event history data
    UserSnap? targetUser;
    if (state.selectedUserId != null) {
      targetUser = state.getUserById(state.selectedUserId!);
    }
    targetUser ??= state.previewUserId != null
        ? state.getUserById(state.previewUserId!)
        : null;
    targetUser ??= state.sessionUserId != null ? state.getUserById(state.sessionUserId!) : null;
    if (targetUser == null && state.users.isNotEmpty) {
      targetUser = state.users.first;
    }
    final events = targetUser != null ? List<UserEvent>.from(targetUser.events.reversed) : <UserEvent>[];
    final logTargetName = targetUser != null ? targetUser.name : 'No Star';

    return Positioned(
      top: isMobile ? 140 : 155,
      left: 16,
      width: isMobile ? 170 : 200,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          child: Container(
            decoration: _glassDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header / Tab Switcher
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 4 : 6,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      // Tab 0: Leaders
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() {
                            if (!expanded) {
                              expanded = true;
                              activeTab = 0;
                            } else if (activeTab == 0) {
                              expanded = false;
                            } else {
                              activeTab = 0;
                            }
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 6 : 10,
                            vertical: 6,
                          ),
                          decoration: expanded && activeTab == 0
                              ? BoxDecoration(
                                  color: spaceAccent.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: spaceAccent.withOpacity(0.4)),
                                )
                              : null,
                          child: Text(
                            '🏆 Leaders',
                            style: TextStyle(
                              color: spaceTextPrimary,
                              fontSize: isMobile ? 11.5 : 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Tab 1: Log
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() {
                            if (!expanded) {
                              expanded = true;
                              activeTab = 1;
                            } else if (activeTab == 1) {
                              expanded = false;
                            } else {
                              activeTab = 1;
                            }
                          });
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: isMobile ? 6 : 10,
                            vertical: 6,
                          ),
                          decoration: expanded && activeTab == 1
                              ? BoxDecoration(
                                  color: spaceAccent.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: spaceAccent.withOpacity(0.4)),
                                )
                              : null,
                          child: Text(
                            '📜 Log',
                            style: TextStyle(
                              color: spaceTextPrimary,
                              fontSize: isMobile ? 11.5 : 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      // Chevron toggle
                      IconButton(
                        iconSize: 16,
                        splashRadius: 16,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        icon: Icon(
                          expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                          color: spaceTextSecondary,
                        ),
                        onPressed: () => setState(() => expanded = !expanded),
                      ),
                    ],
                  ),
                ),

                // Expanded Content Body
                if (expanded) ...[
                  const Divider(color: spaceBorder, height: 1),
                  if (activeTab == 0)
                    // LEADERBOARD VIEW
                    Container(
                      constraints: BoxConstraints(maxHeight: isMobile ? 240 : 360),
                      child: top10.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(16.0),
                              child: Text('No stars yet', style: TextStyle(color: spaceTextSecondary, fontSize: 11.5)),
                            )
                          : ListView.builder(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: top10.length,
                              itemBuilder: (context, i) {
                                final u = top10[i];
                                final isSelected =
                                    state.selectedUserId == u.id ||
                                    state.previewUserId == u.id;
                                return InkWell(
                                  onTap: () => _focusUser(state, u.id),
                                  child: Container(
                                    color: isSelected ? spaceAccent.withOpacity(0.1) : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 5.0),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 20,
                                          child: Text(
                                            '${i + 1}',
                                            style: const TextStyle(color: spaceTextSecondary, fontSize: 11),
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                u.name,
                                                style: const TextStyle(color: spaceTextPrimary, fontSize: 12),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                getSectorName(u.sector),
                                                style: const TextStyle(color: spaceTextSecondary, fontSize: 10),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                          '${u.r.toStringAsFixed(1)}px',
                                          style: const TextStyle(color: spaceStar, fontSize: 11),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: u.loggedIn ? spaceOnline : spaceOffline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    )
                  else
                    // LOG VIEW
                    Container(
                      constraints: BoxConstraints(maxHeight: isMobile ? 240 : 360),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            color: const Color(0x22000000),
                            child: Row(
                              children: [
                                const Text('Target: ', style: TextStyle(color: spaceTextSecondary, fontSize: 10.5)),
                                Expanded(
                                  child: Text(
                                    logTargetName,
                                    style: const TextStyle(color: spaceAccent, fontSize: 11, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: events.isEmpty
                                ? const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: Text(
                                        'No actions recorded yet',
                                        style: TextStyle(color: spaceTextSecondary, fontSize: 11.5),
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                                    itemCount: events.length,
                                    separatorBuilder: (_, __) => Divider(
                                      color: spaceBorder.withOpacity(0.3),
                                      height: 6,
                                    ),
                                    itemBuilder: (context, i) {
                                      final ev = events[i];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 2.0),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2.0),
                                              child: _eventIcon(ev.type),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    ev.msg,
                                                    style: const TextStyle(
                                                      color: spaceTextPrimary,
                                                      fontSize: 11,
                                                      height: 1.2,
                                                    ),
                                                  ),
                                                  Text(
                                                    formatTimeAgo(ev.t),
                                                    style: const TextStyle(
                                                      color: spaceTextSecondary,
                                                      fontSize: 9.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (ev.actorId != null &&
                                                targetUser != null &&
                                                ev.actorId != targetUser.id)
                                              InkWell(
                                                onTap: () => _focusUser(state, ev.actorId!),
                                                child: const Padding(
                                                  padding: EdgeInsets.only(left: 4.0, top: 2.0),
                                                  child: Icon(
                                                    Icons.my_location,
                                                    size: 13,
                                                    color: spaceAccent,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Aliases for compatibility
typedef LeaderboardOverlay = GamePanelOverlay;
typedef EventHistoryOverlay = GamePanelOverlay;

// ---------------------------------------------------------------------------
// Star Info Panel
// ---------------------------------------------------------------------------

class StarPreviewOverlay extends StatelessWidget {
  const StarPreviewOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.selectedUserId != null || state.previewUserId == null) {
      return const SizedBox.shrink();
    }

    final user = state.getUserById(state.previewUserId!);
    if (user == null) return const SizedBox.shrink();

    final now = DateTime.now().millisecondsSinceEpoch;
    final jammed = user.lastJamAt > 0 && now - user.lastJamAt < 60000;
    final boosted = user.boostAt > 0 && now - user.boostAt < 60000;
    final statusColor = jammed
        ? spaceDanger
        : boosted
            ? spaceStar
            : user.loggedIn
                ? spaceOnline
                : spaceOffline;
    final status = [
      user.loggedIn ? 'online' : 'offline',
      if (jammed) 'jammed',
      if (boosted) 'boosted',
    ].join(' · ');
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
            padding: const EdgeInsets.all(12),
            decoration: _glassDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: spaceAccent.withOpacity(0.16),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: spaceAccent.withOpacity(0.4),
                        ),
                      ),
                      child: const Icon(
                        Icons.auto_awesome,
                        color: spaceAccent,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        user.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: spaceStar,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close star preview',
                      constraints: const BoxConstraints(
                        minWidth: 40,
                        minHeight: 40,
                      ),
                      padding: EdgeInsets.zero,
                      icon: const Icon(
                        Icons.close,
                        color: spaceTextSecondary,
                        size: 18,
                      ),
                      onPressed: state.clearStarSelection,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tap again for details',
                  style: TextStyle(
                    color: spaceTextSecondary,
                    fontSize: 10,
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

class StarInfoOverlay extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.selectedUserId == null) return const SizedBox.shrink();

    final u = state.getUserById(state.selectedUserId!);
    if (u == null) return const SizedBox.shrink();

    final now = DateTime.now().millisecondsSinceEpoch;
    final jammed = u.lastJamAt > 0 && (now - u.lastJamAt) < 60000;
    final boosted = u.boostAt > 0 && (now - u.boostAt) < 60000;
    final arriving = u.gravityUntil > now;
    final jamCooldownUntil = state.jamCooldownUntilFor(u.id);
    final jamCooldownRemaining =
        jamCooldownUntil > now ? jamCooldownUntil - now : 0;

    final statusColor = arriving
        ? spaceAccent
        : boosted
        ? spaceStar
        : jammed
        ? spaceDanger
        : (u.loggedIn ? spaceOnline : spaceOffline);
    final statusText =
        (u.loggedIn ? 'online' : 'offline') +
        (arriving
            ? ' · arriving'
            : (boosted ? ' · boosted' : (jammed ? ' · jammed' : '')));
    final isMobile = MediaQuery.of(context).size.width < 600;
    final panelHeight = MediaQuery.sizeOf(context).height * 0.62;

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
        _infoRow('class', starTierName(u.r)),
        _infoRow('growth', '+${(u.r - 10.0).toStringAsFixed(1)} px'),
        _infoRow(
          'position',
          '${u.x.toStringAsFixed(0)}, ${u.y.toStringAsFixed(0)}',
        ),
        if (u.id == state.sessionUserId) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: spaceAccent,
              side: const BorderSide(color: spaceAccent),
              minimumSize: const Size.fromHeight(38),
            ),
            onPressed: () => _openAppearanceDialog(context, state, u),
            icon: const Icon(Icons.palette_outlined, size: 16),
            label: const Text('Customize star'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: spaceStar,
              foregroundColor: const Color(0xFF050C1A),
              minimumSize: const Size.fromHeight(38),
            ),
            onPressed: () => state.api.setStatus(!u.loggedIn),
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
        if (state.sessionUserId != null && u.id != state.sessionUserId) ...[
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: boosted
                  ? spaceStar.withOpacity(0.12)
                  : spaceDanger.withOpacity(0.2),
              foregroundColor: boosted ? spaceStar : spaceDanger,
              elevation: 0,
              side: BorderSide(
                color: boosted ? spaceStar.withOpacity(0.5) : spaceDanger,
              ),
              minimumSize: const Size.fromHeight(38),
            ),
            onPressed: !u.loggedIn ||
                    arriving ||
                    boosted ||
                    jamCooldownRemaining > 0
                ? null
                : () => state.jam(u.id),
            child: Text(
              boosted
                  ? 'Boosted (Immune)'
                  : jamCooldownRemaining > 0
                      ? 'You can jam again in ${fmtClock(jamCooldownRemaining)}'
                      : (jammed ? 'Jam again (−25%)' : 'Jam −25%'),
            ),
          ),
        ],
      ],
    );

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
            constraints: isMobile
                ? BoxConstraints(maxHeight: panelHeight)
                : const BoxConstraints(),
            decoration: _glassDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    top: 4,
                    bottom: 4,
                    right: 4,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: spaceAccent.withOpacity(0.16),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: spaceAccent.withOpacity(0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: spaceAccent,
                          size: 15,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'STAR PROFILE',
                              style: TextStyle(
                                color: spaceTextSecondary,
                                fontSize: 9,
                                letterSpacing: 1.4,
                              ),
                            ),
                            Text(
                              u.name,
                              style: const TextStyle(
                                color: spaceStar,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close star info',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.close,
                          color: spaceTextSecondary,
                          size: 20,
                        ),
                        onPressed: () {
                          state.clearStarSelection();
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(color: spaceBorder, height: 1),
                if (isMobile)
                  Flexible(
                    fit: FlexFit.loose,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: details,
                    ),
                  )
                else
                  Padding(padding: const EdgeInsets.all(12), child: details),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAppearanceDialog(
    BuildContext context,
    AppState state,
    UserSnap user,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var selected = starAppearanceFromId(user.appearanceId);
        var saving = false;
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            backgroundColor: const Color(0xFF081321),
            title: const Text(
              'Customize your star',
              style: TextStyle(color: spaceTextPrimary),
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your star keeps this design as it grows and shrinks.',
                    style: TextStyle(color: spaceTextSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 14),
                  _StarAppearanceChoiceStrip(
                    selected: selected,
                    onSelected: (appearance) {
                      setDialogState(() {
                        selected = appearance;
                        error = null;
                      });
                    },
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!, style: const TextStyle(color: spaceDanger)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() => saving = true);
                        final result = await state.setAppearance(selected.id);
                        if (!dialogContext.mounted) return;
                        if (result['ok'] == true) {
                          Navigator.of(dialogContext).pop();
                        } else {
                          setDialogState(() {
                            saving = false;
                            error = 'Could not save star appearance.';
                          });
                        }
                      },
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ],
          ),
        );
      },
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
                  if (state.sectors
                      .where((sector) => sector.id != user.sector)
                      .isEmpty)
                    const Text(
                      'No other galaxies exist yet.',
                      style: TextStyle(color: spaceTextSecondary, fontSize: 12),
                    ),
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
                            getSectorName(sector.id),
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
                        final result = await state.api.move(selected!);
                        if (result['ok'] == true) {
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          await state.refreshSectors();
                          if (context.mounted) {
                            setState(() {
                              submitting = false;
                              error =
                                  result['error']?.toString() ?? 'move_failed';
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
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: spaceTextSecondary, fontSize: 11.5),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: valColor ?? spaceTextPrimary,
                fontSize: 11.5,
              ),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
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
    bool isJammed = false;
    int cooldown = 0;

    if (me != null && me.loggedIn) {
      final at = me.boostAt;
      isJammed = me.lastJamAt > 0 && (now - me.lastJamAt) < 60000;
      if (now - at < 60000) {
        isBoosting = true;
      } else if (now < at + 600000) {
        cooldown = (at + 600000) - now;
      } else if (!isJammed) {
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
              child: Tooltip(
                message: isJammed
                    ? 'Cannot boost while jammed'
                    : (canBoost ? 'Activate Boost (+100% pull)' : 'Boost'),
                child: FloatingActionButton(
                  mini: true,
                  backgroundColor: isBoosting
                      ? spaceDanger
                      : (isJammed ? const Color(0x662A0D0D) : spaceBg),
                  foregroundColor: isBoosting
                      ? Colors.white
                      : (isJammed
                          ? spaceDanger.withOpacity(0.5)
                          : (canBoost ? spaceAccent : spaceTextSecondary)),
                  elevation: 4,
                  onPressed: canBoost
                      ? () => state.api.boost()
                      : null,
                  child: Text(
                    cooldown > 0
                        ? fmtClock(cooldown)
                        : (isJammed ? '🚫' : '⚡'),
                    style: TextStyle(
                      fontSize: cooldown > 0 ? 11 : (isJammed ? 16 : 22),
                      color: isJammed && !isBoosting
                          ? spaceDanger.withOpacity(0.7)
                          : null,
                    ),
                  ),
                ),
              ),
            ),

          if (me != null)
            _btn(Icons.my_location, () {
              if (game != null) {
                game!.moveCameraTo(Vector2(me.x, me.y), zoom: 1.8);
                state.showUserDetails(me.id);
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
// Jam Toast
// ---------------------------------------------------------------------------

class JamToastOverlay extends StatefulWidget {
  const JamToastOverlay({super.key});

  @override
  State<JamToastOverlay> createState() => _JamToastOverlayState();
}

class _JamToastOverlayState extends State<JamToastOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _curve;
  Timer? _autoHide;
  String? _displayedMessage;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _curve = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    _autoHide?.cancel();
    super.dispose();
  }

  void _trigger(AppState state, String message) {
    if (_displayedMessage == message && _anim.value > 0) return;
    _displayedMessage = message;
    _autoHide?.cancel();
    _anim.forward(from: 0);
    _autoHide = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        _anim.reverse().then((_) {
          if (mounted) {
            _displayedMessage = null;
            state.dismissJamToast();
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final msg = state.jamToastMessage;

    if (msg != null && msg != _displayedMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _trigger(state, msg);
      });
    }

    if (msg == null && _displayedMessage == null) return const SizedBox.shrink();

    return Positioned(
      top: 80,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, child) {
            final t = _curve.value.clamp(0.0, 1.0);
            return Transform.translate(
              offset: Offset(0, -20 * (1 - t)),
              child: Opacity(opacity: t, child: child),
            );
          },
          child: GestureDetector(
            onTap: () {
              _autoHide?.cancel();
              _anim.reverse().then((_) {
                if (mounted) {
                  _displayedMessage = null;
                  state.dismissJamToast();
                }
              });
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xCC1A0505),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: spaceDanger.withOpacity(0.7)),
                    boxShadow: [
                      BoxShadow(
                        color: spaceDanger.withOpacity(0.35),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                  child: Text(
                    msg ?? _displayedMessage ?? '',
                    style: const TextStyle(
                      color: spaceDanger,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top Navigation: Search Bar + Account Action
// ---------------------------------------------------------------------------

class TopNavOverlay extends StatefulWidget {
  final SpaceMapGame? game;
  const TopNavOverlay({super.key, this.game});

  @override
  State<TopNavOverlay> createState() => _TopNavOverlayState();
}

class _TopNavOverlayState extends State<TopNavOverlay> {
  bool isSearchOpen = false;
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
        state.showUserDetails(u.id);
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
    setState(() {
      _results = [];
      isSearchOpen = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Positioned(
      top: 16,
      right: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search button / Search input
              if (!isSearchOpen)
                InkWell(
                  onTap: () => setState(() => isSearchOpen = true),
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: _glassDecoration(10),
                        child: const Icon(Icons.search, color: spaceAccent, size: 20),
                      ),
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Container(
                      width: isMobile ? 180 : 260,
                      height: 40,
                      padding: const EdgeInsets.only(left: 10, right: 4),
                      decoration: _glassDecoration(10),
                      child: Row(
                        children: [
                          const Icon(Icons.search, color: spaceAccent, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              autofocus: true,
                              onChanged: (v) => _runSearch(state, v),
                              style: const TextStyle(color: spaceTextPrimary, fontSize: 12.5),
                              decoration: const InputDecoration(
                                hintText: 'Search star/sector...',
                                hintStyle: TextStyle(color: spaceTextSecondary, fontSize: 12),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                          IconButton(
                            iconSize: 16,
                            splashRadius: 16,
                            icon: const Icon(Icons.close, color: spaceTextSecondary),
                            onPressed: () {
                              setState(() {
                                isSearchOpen = false;
                                _searchController.clear();
                                _results = [];
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // Account / Login Button
              if (state.sessionUserId == null)
                InkWell(
                  onTap: () {
                    state.showLoginModal = true;
                    state.notifyListeners();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: _glassDecoration(10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person_add, color: spaceAccent, size: 18),
                            if (!isMobile) ...[
                              const SizedBox(width: 6),
                              const Text(
                                'Log In',
                                style: TextStyle(color: spaceTextPrimary, fontSize: 12.5),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              else
                PopupMenuButton<String>(
                  tooltip: 'Account',
                  color: const Color(0xFF081321),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: spaceBorder),
                  ),
                  onSelected: (val) {
                    if (val == 'logout') {
                      state.logout();
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Text(
                        'Signed in as ${state.sessionUserName}',
                        style: const TextStyle(color: spaceAccent, fontSize: 12),
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(
                            AppState.preserveUsersOnLogout
                                ? Icons.switch_account
                                : Icons.logout,
                            size: 16,
                            color: spaceDanger,
                          ),
                          SizedBox(width: 8),
                          Text(
                            AppState.preserveUsersOnLogout
                                ? 'Switch User'
                                : 'Log Out',
                            style: TextStyle(color: spaceDanger, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                      child: Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: _glassDecoration(10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.account_circle, color: spaceAccent, size: 20),
                            if (!isMobile) ...[
                              const SizedBox(width: 6),
                              Text(
                                state.sessionUserName ?? '',
                                style: const TextStyle(color: spaceTextPrimary, fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // Search Dropdown Results
          if (isSearchOpen && _results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: isMobile ? 220 : 280,
              decoration: _glassDecoration(12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final res = _results[i];
                      return InkWell(
                        onTap: () => _pick(state, res),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 7.0),
                          child: Row(
                            children: [
                              Icon(
                                res['kind'] == 'sector' ? Icons.travel_explore : Icons.star,
                                color: spaceAccent,
                                size: 15,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      res['label'],
                                      style: const TextStyle(color: spaceTextPrimary, fontSize: 12),
                                    ),
                                    Text(
                                      res['sub'],
                                      style: const TextStyle(color: spaceTextSecondary, fontSize: 10),
                                    ),
                                  ],
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

typedef SearchOverlay = TopNavOverlay;
