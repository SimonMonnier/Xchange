import 'dart:convert';
import 'dart:io';

import 'models/announcement.dart';

class AdHttpServer {
  HttpServer? _server;

  Future<void> start(Announcement ad) async {
    _server = await HttpServer.bind(InternetAddress.anyIPv4, 8081);
    _server!.listen((HttpRequest request) async {
      if (request.uri.path == '/announcement') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(ad.toJson()));
      } else if (request.uri.path == '/image' && ad.imageBase64 != null) {
        request.response.headers.contentType =
            ContentType('application', 'octet-stream');
        request.response.add(base64Decode(ad.imageBase64!));
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  }

  Future<void> stop() async {
    await _server?.close();
    _server = null;
  }
}
