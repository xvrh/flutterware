/// Traffic generator for the http-profile spike (network-in-run-cockpit).
///
/// Serves its own loopback `HttpServer` and fires requests at it through both
/// `dart:io` `HttpClient` and `package:http`, so the VM's http profile
/// (`ext.dart.io.getHttpProfile`) has something to record without any external
/// server running. One request fires at startup, before any host could have
/// enabled profiling over the wire — that request is the measurement for
/// whether capture must be armed in the entry point.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  // Deliberately does not arm the profiler itself: capturing the `/startup`
  // request is the run guest's job, and this entry point is what verifies it.
  runApp(const NetworkSpikeApp());
}

class NetworkSpikeApp extends StatelessWidget {
  const NetworkSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(title: 'Network spike', home: NetworkSpikePage());
  }
}

class NetworkSpikePage extends StatefulWidget {
  const NetworkSpikePage({super.key});

  @override
  State<NetworkSpikePage> createState() => _NetworkSpikePageState();
}

class _NetworkSpikePageState extends State<NetworkSpikePage> {
  HttpServer? _server;
  final _ioClient = HttpClient();
  final _log = <String>[];

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    var server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle);
    setState(() {});
    // The startup request: fired before any host-side enable can have landed.
    await _getIo('/startup');
  }

  Future<void> _handle(HttpRequest request) async {
    var response = request.response;
    switch (request.uri.path) {
      case '/echo':
        var body = await utf8.decoder.bind(request).join();
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({'echo': jsonDecode(body)}));
      case '/slow':
        await Future<void>.delayed(const Duration(milliseconds: 300));
        response.write('slow response');
      case '/missing':
        response.statusCode = HttpStatus.notFound;
        response.write('not found');
      default:
        response.headers.contentType = ContentType.json;
        response.write(
          jsonEncode({'hello': 'world', 'path': request.uri.path}),
        );
    }
    await response.close();
  }

  Uri _uri(String path) => Uri.parse('http://localhost:${_server!.port}$path');

  Future<void> _getIo(String path) async {
    var request = await _ioClient.getUrl(_uri(path));
    request.headers.add('x-spike', 'io-get');
    var response = await request.close();
    var body = await utf8.decoder.bind(response).join();
    _done('io GET $path -> ${response.statusCode} (${body.length}b)');
  }

  Future<void> _postIo(String path) async {
    var request = await _ioClient.postUrl(_uri(path));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode({'name': 'spike', 'answer': 42}));
    var response = await request.close();
    var body = await utf8.decoder.bind(response).join();
    _done('io POST $path -> ${response.statusCode} (${body.length}b)');
  }

  Future<void> _getPackageHttp(String path) async {
    var response = await http.get(_uri(path), headers: {'x-spike': 'pkg-get'});
    _done(
      'http GET $path -> ${response.statusCode} '
      '(${response.body.length}b)',
    );
  }

  void _done(String line) {
    if (!mounted) return;
    setState(() => _log.add(line));
  }

  @override
  Widget build(BuildContext context) {
    var server = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Network spike')),
      body: server == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Serving on port ${server.port}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => _getIo('/hello'),
                  child: const Text('GET io'),
                ),
                ElevatedButton(
                  onPressed: () => _postIo('/echo'),
                  child: const Text('POST io json'),
                ),
                ElevatedButton(
                  onPressed: () => _getPackageHttp('/hello'),
                  child: const Text('GET package:http'),
                ),
                ElevatedButton(
                  onPressed: () => _getIo('/missing'),
                  child: const Text('GET 404'),
                ),
                ElevatedButton(
                  onPressed: () => _getIo('/slow'),
                  child: const Text('GET slow'),
                ),
                const Divider(),
                Text('${_log.length} requests done'),
                for (var line in _log) Text(line),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _server?.close(force: true);
    _ioClient.close(force: true);
    super.dispose();
  }
}
