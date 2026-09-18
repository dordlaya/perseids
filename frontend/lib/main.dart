import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flame/game.dart';

import 'state/app_state.dart';
import 'game/space_map_game.dart';
import 'ui/overlays.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const SpaceMapApp(),
    ),
  );
}

class SpaceMapApp extends StatelessWidget {
  const SpaceMapApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Perseids',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF03050A),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF9FE7FF),
            foregroundColor: const Color(0xFF050C1A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      home: const GameScreen(),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({Key? key}) : super(key: key);

  @override
  _GameScreenState createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  SpaceMapGame? _game;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_game == null) {
      final state = context.read<AppState>();
      _game = SpaceMapGame(state);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Flame Game Layer
          GameWidget<SpaceMapGame>(game: _game!),

          // UI Overlays
          HudOverlay(),
          SessionBarOverlay(),
          LeaderboardOverlay(game: _game),
          SearchOverlay(game: _game),
          StarInfoOverlay(),
          ControlsOverlay(game: _game),

          // Add button
          Positioned(
            top: 16,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.person_add),
              onPressed: () {
                context.read<AppState>().showLoginModal = true;
                context.read<AppState>().notifyListeners();
              },
            ),
          ),

          // Modals
          LoginOverlay(game: _game),
        ],
      ),
    );
  }
}
