import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/models.dart';

class ApiClient {
  // In production, Flutter web is served by the Go server itself, so
  // Uri.base already points at the right host:port.
  //
  // In development, `flutter run -d chrome` uses its own dev server on a
  // random port, while Go listens on a fixed port (default 5173).
  // Pass `--dart-define=BACKEND_PORT=5173` to override the port at compile
  // time so the client can reach the backend.
  //
  // Example dev command:
  //   flutter run -d chrome --dart-define=BACKEND_PORT=5173
  static const String _backendPort =
      String.fromEnvironment('BACKEND_PORT', defaultValue: '');

  static String get _effectivePort {
    if (_backendPort.isNotEmpty) return _backendPort;
    return Uri.base.port.toString();
  }

  static String get baseUrl {
    final origin = Uri.base;
    return '${origin.scheme}://${origin.host}:$_effectivePort/api';
  }

  static String get wsUrl {
    final origin = Uri.base;
    final wsScheme = origin.scheme == 'https' ? 'wss' : 'ws';
    return '$wsScheme://${origin.host}:$_effectivePort/ws';
  }

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final StreamController<Snapshot> _snapshotController = StreamController<Snapshot>.broadcast();
  final StreamController<bool> _connectionController = StreamController<bool>.broadcast();
  
  Stream<Snapshot> get snapshotStream => _snapshotController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  Timer? _reconnectTimer;
  int _reconnectDelay = 500;

  void connectStream() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _connectionController.add(true);
      _reconnectDelay = 500;

      _subscription = _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            final snapshot = Snapshot.fromJson(data);
            _snapshotController.add(snapshot);
          } catch (e) {
            print('Error parsing snapshot: $e');
          }
        },
        onDone: () {
          _handleDisconnect();
        },
        onError: (error) {
          _handleDisconnect();
        },
      );
    } catch (e) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _connectionController.add(false);
    _subscription?.cancel();
    _channel?.sink.close();
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: _reconnectDelay), () {
      _reconnectDelay = (_reconnectDelay * 1.6).toInt().clamp(500, 8000);
      connectStream();
    });
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _snapshotController.close();
    _connectionController.close();
  }

  Future<Map<String, dynamic>> register(String name, String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'email': email, 'password': password}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }

  Future<Map<String, dynamic>> login(String identifier, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'identifier': identifier, 'password': password}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }

  Future<void> setStatus(int id, bool value) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'value': value}),
      );
    } catch (e) {
      // Ignore network errors for status updates
    }
  }

  Future<void> heartbeat(int id) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/heartbeat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      );
    } catch (e) {
      // The server will expire the user if heartbeats stop succeeding.
    }
  }

  Future<void> reset() async {
    try {
      await http.post(Uri.parse('$baseUrl/reset'));
    } catch (e) {
      // Ignore network errors for reset
    }
  }

  Future<Map<String, dynamic>> boost(int id) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/boost'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }

  Future<Map<String, dynamic>> jam(int attacker, int target) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/jam'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'attacker': attacker, 'target': target}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }

  Future<List<SectorSnap>> getSectors() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/sectors'));
      final data = jsonDecode(res.body) as List<dynamic>;
      return data
          .map((item) => SectorSnap.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>> move(int id, int sector) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/move'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': id, 'sector': sector}),
      );
      return jsonDecode(res.body);
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }
}
