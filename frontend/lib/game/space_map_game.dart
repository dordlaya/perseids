import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/experimental.dart';
import 'dart:math';

import '../state/app_state.dart';
import 'components/background_component.dart';
import 'components/star_component.dart';
import 'components/probe_component.dart';
import 'dart:math' as math;

class SpaceMapGame extends FlameGame with ScaleDetector, ScrollDetector {
  final AppState state;

  late final BackgroundComponent background;
  final Map<int, StarComponent> starComponents = {};
  final Map<int, ProbeComponent> probeComponents = {};
  Vector2? _cameraTarget;
  double? _cameraZoomTarget;

  SpaceMapGame(this.state);

  @override
  Future<void> onLoad() async {
    camera = CameraComponent(world: world);
    camera.viewfinder.zoom = 1.0;

    background = BackgroundComponent(state);
    world.add(background);

    // Add components that exist on load
    _syncComponents();
  }

  @override
  void update(double dt) {
    super.update(dt);
    state.stepDisplay(dt);
    _syncComponents();
    final target = _cameraTarget;
    if (target != null) {
      final amount = 1 - math.exp(-8 * dt.clamp(0.0, 0.1));
      final position = camera.viewfinder.position;
      position.x += (target.x - position.x) * amount;
      position.y += (target.y - position.y) * amount;
    }
    final zoomTarget = _cameraZoomTarget;
    if (zoomTarget != null) {
      final amount = 1 - math.exp(-8 * dt.clamp(0.0, 0.1));
      camera.viewfinder.zoom += (zoomTarget - camera.viewfinder.zoom) * amount;
    }
  }

  void moveCameraTo(Vector2 position, {double? zoom}) {
    _cameraTarget = position.clone();
    _cameraZoomTarget = zoom;
  }

  void stopCameraFollow() {
    _cameraTarget = null;
    _cameraZoomTarget = null;

    if (state.world.w > 0 && state.world.h > 0) {
      camera.setBounds(Rectangle.fromLTRB(0, 0, state.world.w, state.world.h));
      
      final minZ = dynamicMinZoom;
      if (camera.viewfinder.zoom < minZ) {
        camera.viewfinder.zoom = minZ;
      }
    }
  }

  void _syncComponents() {
    // Sync Users
    final currentUserIds = state.users.map((u) => u.id).toSet();

    // Remove deleted users
    starComponents.removeWhere((id, comp) {
      if (!currentUserIds.contains(id)) {
        comp.removeFromParent();
        return true;
      }
      return false;
    });

    // Add new / Update existing
    for (final user in state.users) {
      if (starComponents.containsKey(user.id)) {
        starComponents[user.id]!.updateUser(user);
      } else {
        final comp = StarComponent(user, state);
        starComponents[user.id] = comp;
        world.add(comp);
      }
    }

    // Sync Probes
    final currentProbeIds = state.probes.map((p) => p.id).toSet();

    // Remove deleted probes
    probeComponents.removeWhere((id, comp) {
      if (!currentProbeIds.contains(id)) {
        comp.removeFromParent();
        return true;
      }
      return false;
    });

    // Add new / Update existing
    for (final probe in state.probes) {
      if (probeComponents.containsKey(probe.id)) {
        // Position is handled internally by the component reading from the probe object
      } else {
        final comp = ProbeComponent(probe);
        probeComponents[probe.id] = comp;
        world.add(comp);
      }
    }
  }

  // --- Camera Controls ---
  
  static const double maxZoomLimit = 2.6;
  
  late double _startZoom;

  double get dynamicMinZoom {
    if (state.world.w == 0 || state.world.h == 0) return 0.15;
    // Calculate the zoom needed to fit the entire world on screen with a small padding.
    // Take the smaller of the two axes so the full map fits.
    final fitW = size.x / (state.world.w + 100);
    final fitH = size.y / (state.world.h + 100);
    // Allow zooming out to fit the whole map, but no further.
    return min(fitW, fitH).clamp(0.05, maxZoomLimit);
  }

  @override
  void onScaleStart(ScaleStartInfo info) {
    stopCameraFollow();
    _startZoom = camera.viewfinder.zoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    // Panning
    camera.viewfinder.position -= info.delta.global / camera.viewfinder.zoom;
    
    // Pinch to zoom
    if (info.pointerCount >= 2) {
      final newZoom = (_startZoom * info.raw.scale).clamp(dynamicMinZoom, maxZoomLimit);
      camera.viewfinder.zoom = newZoom;
    }
  }

  @override
  void onScroll(PointerScrollInfo info) {
    final zoomDelta = info.scrollDelta.global.y > 0 ? 1 / 1.12 : 1.12;
    final newZoom = (camera.viewfinder.zoom * zoomDelta).clamp(dynamicMinZoom, maxZoomLimit);
    camera.viewfinder.zoom = newZoom;
  }
}
