import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class VoipService {
  RTCPeerConnection? _peer;
  MediaStream? _localStream;
  HttpServer? _server;

  Future<void> _createPeer() async {
    if (_peer != null) return;
    _peer = await createPeerConnection({'iceServers': []});
    _localStream =
        await navigator.mediaDevices.getUserMedia({'audio': true});
    for (var track in _localStream!.getTracks()) {
      await _peer!.addTrack(track, _localStream!);
    }
  }

  Future<void> startServer() async {
    await _createPeer();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    _server!.listen((HttpRequest request) async {
      if (request.method == 'POST' && request.uri.path == '/offer') {
        final body = await utf8.decoder.bind(request).join();
        final data = jsonDecode(body);
        await _peer!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']));
        final answer = await _peer!.createAnswer();
        await _peer!.setLocalDescription(answer);
        request.response
          ..statusCode = HttpStatus.ok
          ..write(jsonEncode({'sdp': answer.sdp, 'type': answer.type}))
          ..close();
      } else {
        request.response
          ..statusCode = HttpStatus.notFound
          ..close();
      }
    });
  }

  Future<void> call(String ip) async {
    await _createPeer();
    final offer = await _peer!.createOffer();
    await _peer!.setLocalDescription(offer);
    final client = HttpClient();
    final req = await client.postUrl(Uri.parse('http://$ip:8080/offer'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({'sdp': offer.sdp, 'type': offer.type}));
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(respBody);
    await _peer!
        .setRemoteDescription(RTCSessionDescription(data['sdp'], data['type']));
  }

  Future<void> dispose() async {
    await _server?.close();
    await _localStream?.dispose();
    await _peer?.close();
  }
}
