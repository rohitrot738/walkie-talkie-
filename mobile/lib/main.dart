import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

// Apne server ka address yahan daalein (emulator: 10.0.2.2, real phone: PC ka IP ya deployed URL)
const serverUrl = 'http://10.0.2.2:3000';
const minFreq = 1.0, maxFreq = 999.9;

void main() => runApp(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WalkieScreen(),
    ));

class WalkieScreen extends StatefulWidget {
  const WalkieScreen({super.key});
  @override
  State<WalkieScreen> createState() => _WalkieScreenState();
}

class _WalkieScreenState extends State<WalkieScreen> {
  late io.Socket socket;
  MediaStream? stream;
  final Map<String, RTCPeerConnection> pcs = {};
  final Map<String, List<RTCIceCandidate>> pendingIce = {};
  double freq = 146.5;
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
    socket = io.io(serverUrl, io.OptionBuilder().setTransports(['websocket']).build());
    socket.on('signal', (d) => _onSignal(d['from'], d['data']));
    socket.on('peer-left', (id) => _dropPeer(id));
    socket.on('peer-joined', (_) => setState(() => count++));
    socket.on('speaker', (id) => setState(() {
          status = id == null
              ? 'Channel free'
              : id == socket.id
                  ? 'You are talking...'
                  : 'Someone is talking...';
        }));
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
    socket.emitWithAck('join', freq.toStringAsFixed(1), ack: (res) async {
      if (res['error'] != null) {
        setState(() => status = res['error']);
        return;
      }
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

  void _step(double d) => setState(() {
        freq = ((freq + d) * 10).round() / 10;
        freq = freq.clamp(minFreq, maxFreq);
      });

  @override
  void dispose() {
    pcs.keys.toList().forEach(_dropPeer);
    stream?.dispose();
    socket.dispose();
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
                const Text('FREQ (MHz) 1.0 - 999.9', style: TextStyle(color: Color(0xFF005522))),
                Text(freq.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold, color: Color(0xFF005522))),
                Text(joined ? '$count on this frequency' : 'Not connected',
                    style: const TextStyle(color: Color(0xFF005522))),
              ]),
            ),
            const SizedBox(height: 16),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(color: Colors.white, iconSize: 36, icon: const Icon(Icons.remove_circle), onPressed: () => _step(-0.1)),
              IconButton(color: Colors.white, iconSize: 28, icon: const Icon(Icons.keyboard_double_arrow_left), onPressed: () => _step(-10)),
              IconButton(color: Colors.white, iconSize: 28, icon: const Icon(Icons.keyboard_double_arrow_right), onPressed: () => _step(10)),
              IconButton(color: Colors.white, iconSize: 36, icon: const Icon(Icons.add_circle), onPressed: () => _step(0.1)),
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
