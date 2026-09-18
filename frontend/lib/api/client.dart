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

  /// Bearer token returned by /api/register or /api/login. Every mutating
  /// call sends it as "Authorization: Bearer <token>"; the server resolves
  /// the acting user from this, never from an id in the request body.
  String? authToken;

  /// Fired when an authenticated call comes back 401 (token missing,
  /// unknown, or expired — sessions expire after 24h of inactivity).
  /// AppState wires this to clearSession() so the UI drops back to the
  /// login screen instead of silently failing every subsequent action.
  void Function()? onUnauthorized;

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        if (authToken != null) 'Authorization': 'Bearer $authToken',
      };

  /// POSTs to an authenticated endpoint and handles a 401 uniformly.
  Future<http.Response> _postAuthed(String path, {Object? body}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/$path'),
      headers: _authHeaders,
      body: body == null ? null : jsonEncode(body),
    );
    if (res.statusCode == 401) {
      authToken = null;
      onUnauthorized?.call();
    }
    return res;
  }

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

  /// Registers a new account. On success, stores the returned session token
  /// so subsequent calls are authenticated — callers don't need to thread it
  /// through manually, but AppState should still persist it (see
  /// AppState.setSession) so it survives a page refresh.
  Future<Map<String, dynamic>> register(String name, String email, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'email': email, 'password': password}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['token'] is String) {
        authToken = data['token'] as String;
      }
      return data;
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }

  /// Logs in with an email or username. On success, stores the returned
  /// session token the same way register() does.
  Future<Map<String, dynamic>> login(String identifier, String password) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'identifier': identifier, 'password': password}),
      );
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['token'] is String) {
        authToken = data['token'] as String;
      }
      return data;
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }

  /// Revokes the current session token server-side. Call this on explicit
  /// logout; clearToken() alone only forgets it locally.
  Future<void> logout() async {
    try {
      await http.post(Uri.parse('$baseUrl/logout'), headers: _authHeaders);
    } catch (e) {
      // Best-effort — the token will simply expire server-side otherwise.
    } finally {
      authToken = null;
    }
  }

  /// Forgets the token locally without calling the server (e.g. when a
  /// request comes back 401, meaning the server already invalidated it).
  void clearToken() {
    authToken = null;
  }

  /// Sets the CALLER's own online/offline flag — there is no "id" parameter
  /// because the server always acts on whoever the bearer token belongs to.
  Future<void> setStatus(bool value) async {
    try {
      await _postAuthed('status', body: {'value': value});
    } catch (e) {
      // Ignore network errors for status updates
    }
  }

  Future<void> heartbeat() async {
    try {
      await _postAuthed('heartbeat');
    } catch (e) {
      // The server will expire the user if heartbeats stop succeeding.
    }
  }

  /// Operator-only: requires the server's ADMIN_TOKEN, not a player session
  /// token. Not wired into any UI; kept for scripted/manual ops use.
  Future<void> reset(String adminToken) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/reset'),
        headers: {'Authorization': 'Bearer $adminToken'},
      );
    } catch (e) {
      // Ignore network errors for reset
    }
  }

  Future<Map<String, dynamic>> boost() async {
    try {
      final res = await _postAuthed('boost');
      return jsonDecode(res.body);
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }

  /// Jams [target]; the attacker is always the caller, inferred server-side
  /// from the session token.
  Future<Map<String, dynamic>> jam(int target) async {
    try {
      final res = await _postAuthed('jam', body: {'target': target});
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

  /// Moves the CALLER's own probe to [sector] — no "id" parameter; see
  /// setStatus() above for why.
  Future<Map<String, dynamic>> move(int sector) async {
    try {
      final res = await _postAuthed('move', body: {'sector': sector});
      return jsonDecode(res.body);
    } catch (e) {
      return {'ok': false, 'error': 'network'};
    }
  }
}
