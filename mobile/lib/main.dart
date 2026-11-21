import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// Default server; app ke andar "Server" field se badla ja sakta hai
const defaultServerUrl = String.fromEnvironment('SERVER_URL', defaultValue: 'http://10.0.2.2:3000');
// Frequency 3 decimal tak (1 unit = 0.001 MHz)
const minFreq = 1000, maxFreq = 999999;

void main() {
  FlutterForegroundTask.initCommunicationPort();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: WithForegroundTask(child: WalkieScreen()),
  ));
}

class WalkieScreen extends StatefulWidget {
  const WalkieScreen({super.key});
  @override
  State<WalkieScreen> createState() => _WalkieScreenState();
}

class _WalkieScreenState extends State<WalkieScreen> {
  io.Socket? _socket;
  String? _url;
  io.Socket get socket => _socket!;
  final urlCtrl = TextEditingController(text: defaultServerUrl);
  MediaStream? stream;
  final Map<String, RTCPeerConnection> pcs = {};
  final Map<String, List<RTCIceCandidate>> pendingIce = {};
  int freq = 146500;
  bool joined = false, talking = false;
  String status = 'Not connected';
  int count = 0;

  static const cfg = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'}
    ]
  };

  @override
  void initState() {
    super.initState();
    _initForegroundService();
    SharedPreferences.getInstance().then((p) {
      final u = p.getString('serverUrl');
      if (u != null) urlCtrl.text = u;
    });
  }

  void _connect(String url) {
    _socket?.dispose();
    final sock = io.io(url, io.OptionBuilder().setTransports(['websocket']).disableAutoConnect().build());
    _socket = sock;
    _url = url;
    sock.on('signal', (d) => _onSignal(d['from'], d['data']));
    sock.on('peer-left', (id) => _dropPeer(id));
    sock.on('peer-joined', (_) => setState(() => count++));
    sock.on('connect_error', (_) => setState(() => status = 'Server se connect nahi ho paya'));
    sock.on('speaker', (id) => setState(() {
          status = id == null
              ? 'Channel free'
              : id == sock.id
                  ? 'You are talking...'
                  : 'Someone is talking...';
        }));
    sock.connect();
  }

  // Foreground service keeps mic + socket alive when the app is in background
  void _initForegroundService() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'walkie_service',
        channelName: 'Walkie Talkie',
        channelImportance: NotificationChannelImportance.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<void> _startService(String freqText) async {
    await FlutterForegroundTask.requestNotificationPermission();
    final title = 'Walkie Talkie';
    final text = 'Listening on $freqText MHz';
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: text);
    } else {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: title,
        notificationText: text,
        serviceTypes: [ForegroundServiceTypes.microphone],
      );
    }
  }

  Future<void> _ensureMic() async {
    if (stream != null) return;
    await Permission.microphone.request();
    stream = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});
    stream!.getAudioTracks().first.enabled = false;
  }

  Future<RTCPeerConnection> _peer(String id) async {
    if (pcs[id] != null) return pcs[id]!;
    final pc = await createPeerConnection(cfg);
    pcs[id] = pc;
    for (final t in stream!.getAudioTracks()) {
      await pc.addTrack(t, stream!);
    }
    pc.onIceCandidate = (c) => socket.emit('signal', {
          'to': id,
          'data': {'candidate': c.toMap()}
        });
    return pc; // incoming audio plays automatically via native WebRTC
  }

  void _dropPeer(String id) {
    pcs.remove(id)?.close();
    pendingIce.remove(id);
  }

  Future<void> _onSignal(String from, Map data) async {
    final pc = await _peer(from);
    if (data['sdp'] != null) {
      final s = data['sdp'];
      await pc.setRemoteDescription(RTCSessionDescription(s['sdp'], s['type']));
      for (final c in pendingIce.remove(from) ?? []) {
        await pc.addCandidate(c);
      }
      if (s['type'] == 'offer') {
        final answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        socket.emit('signal', {'to': from, 'data': {'sdp': answer.toMap()}});
      }
    } else if (data['candidate'] != null) {
      final c = data['candidate'];
      final cand = RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']);
      if (await pc.getRemoteDescription() == null) {
        (pendingIce[from] ??= []).add(cand);
      } else {
        await pc.addCandidate(cand);
      }
    }
  }

  Future<void> _join() async {
    await _ensureMic();
    pcs.keys.toList().forEach(_dropPeer);
    final url = urlCtrl.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('serverUrl', url);
    if (_socket == null || _url != url) _connect(url);
    if (!socket.connected) {
      final done = Completer<void>();
      socket.once('connect', (_) => done.complete());
      await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      if (!socket.connected) return;
    }
    socket.emitWithAck('join', _freqText, ack: (res) async {
      if (res['error'] != null) {
        setState(() => status = res['error']);
        return;
      }
      _startService(res['freq']);
      setState(() {
        joined = true;
        count = res['count'];
        status = 'Joined ${res['freq']} MHz';
      });
      for (final id in List<String>.from(res['peers'])) {
        final pc = await _peer(id);
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        socket.emit('signal', {'to': id, 'data': {'sdp': offer.toMap()}});
      }
    });
  }

  void _pttDown() {
    if (!joined || talking) return;
    socket.emitWithAck('ptt-start', null, ack: (ok) {
      if (ok != true) {
        setState(() => status = 'Channel busy');
        return;
      }
      stream!.getAudioTracks().first.enabled = true;
      setState(() => talking = true);
    });
  }

  void _pttUp() {
    if (!talking) return;
    stream!.getAudioTracks().first.enabled = false;
    socket.emit('ptt-stop');
    setState(() => talking = false);
  }

  void _step(int d) => setState(() {
        freq = (freq + d).clamp(minFreq, maxFreq).toInt();
      });

  String get _freqText => (freq / 1000).toStringAsFixed(3);

  Future<void> _editFreq() async {
    final c = TextEditingController(text: _freqText);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Frequency (MHz)'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: '1.000 - 999.999'),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK'))],
      ),
    );
    final parsed = double.tryParse(v ?? '');
    if (parsed != null) setState(() => freq = (parsed * 1000).round().clamp(minFreq, maxFreq).toInt());
  }

  @override
  void dispose() {
    pcs.keys.toList().forEach(_dropPeer);
    stream?.dispose();
    _socket?.dispose();
    FlutterForegroundTask.stopService();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SafeArea(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 300,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF8FD18F), borderRadius: BorderRadius.circular(8)),
              child: Column(children: [
                const Text('FREQ (MHz) 1.000 - 999.999', style: TextStyle(color: Color(0xFF005522))),
                GestureDetector(
                  onTap: _editFreq,
                  child: Text(_freqText,
                      style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF005522))),
                ),
                Text(joined ? '$count on this frequency' : 'Not connected',
                    style: const TextStyle(color: Color(0xFF005522))),
              ]),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 300,
              child: TextField(
                controller: urlCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                    labelText: 'Server URL', labelStyle: TextStyle(color: Colors.white70), isDense: true),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, children: [
              for (final d in [-1000, -100, -1, 1, 100, 1000])
                TextButton(
                  onPressed: () => _step(d),
                  child: Text('${d < 0 ? '−' : '+'}${(d.abs() / 1000).toString().replaceFirst(RegExp(r'^0(?=\.)'), '')}',
                      style: const TextStyle(color: Colors.white, fontSize: 18)),
                ),
            ]),
            ElevatedButton(onPressed: _join, child: const Text('Join Frequency')),
            const SizedBox(height: 32),
            GestureDetector(
              onTapDown: (_) => _pttDown(),
              onTapUp: (_) => _pttUp(),
              onTapCancel: _pttUp,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: !joined ? Colors.grey : talking ? Colors.green : Colors.red,
                  boxShadow: talking ? [const BoxShadow(color: Colors.green, blurRadius: 30)] : null,
                ),
                alignment: Alignment.center,
                child: const Text('HOLD TO TALK',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 20),
            Text(status, style: const TextStyle(color: Colors.white)),
          ]),
        ),
      ),
    );
  }
}
