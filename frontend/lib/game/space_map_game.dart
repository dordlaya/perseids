import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/experimental.dart';

import '../state/app_state.dart';
import 'components/background_component.dart';
import 'components/star_component.dart';
import 'components/probe_component.dart';

class SpaceMapGame extends FlameGame with ScaleDetector, ScrollDetector {
  final AppState state;

  late final BackgroundComponent background;
  final Map<int, StarComponent> starComponents = {};
  final Map<int, ProbeComponent> probeComponents = {};

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

    if (state.world.w > 0 && state.world.h > 0) {
      camera.setBounds(Rectangle.fromLTRB(0, 0, state.world.w, state.world.h));
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
        starComponents[user.id]!.user = user;
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
    if (state.world.w == 0 || state.world.h == 0) return 0.4;
    // Add a small 100px margin to the bounds on each side
    final wMargin = state.world.w + 200; 
    final hMargin = state.world.h + 200;
    
    // The required zoom to fit the game canvas within the restricted world area.
    // Taking the max ensures we zoom in enough so that neither dimension sees black.
    return max(size.x / wMargin, size.y / hMargin).clamp(0.05, maxZoomLimit);
  }

  @override
  void onScaleStart(ScaleStartInfo info) {
    _startZoom = camera.viewfinder.zoom;
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    // Panning
    camera.viewfinder.position -= info.delta.global / camera.viewfinder.zoom;

    // Pinch to zoom
    if (info.pointerCount >= 2) {
      final newZoom = (_startZoom * info.raw.scale).clamp(
        dynamicMinZoom,
        maxZoomLimit,
      );
      camera.viewfinder.zoom = newZoom;
    }
  }

  @override
  void onScroll(PointerScrollInfo info) {
    final zoomDelta = info.scrollDelta.global.y > 0 ? 1 / 1.12 : 1.12;
    final newZoom = (camera.viewfinder.zoom * zoomDelta).clamp(
      dynamicMinZoom,
      maxZoomLimit,
    );
    camera.viewfinder.zoom = newZoom;
  }
}
