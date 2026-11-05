import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:samseer/samseer.dart';

import 'samseer_notification_bridge.dart';
import 'samseer_webview_demo_page.dart';

late final Samseer samseer;
late final Dio dio;
late final http.Client httpClient;
late final FlutterLocalNotificationsPlugin notifications;
late final SamseerNotificationBridge samseerNotifications;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  samseer = Samseer(
    configuration: const SamseerConfiguration(
      showInspectorOnShake: true,
    ),
  );

  dio = Dio()..interceptors.add(samseer.dioInterceptor);
  httpClient = samseer.httpClient();
  HttpOverrides.global = samseer.httpOverrides;

  notifications = FlutterLocalNotificationsPlugin();
  samseerNotifications = SamseerNotificationBridge(
    samseer: samseer,
    plugin: notifications,
  );

  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    ),
    onDidReceiveNotificationResponse: samseerNotifications.handleTap,
  );

  samseerNotifications.start();

  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'samseer example',
      debugShowCheckedModeBanner: false,
      navigatorKey: samseer.navigatorKey,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        brightness: Brightness.dark,
      ),
      builder: (context, child) => samseer.overlay(child: child!),
      home: const Home(),
    );
  }
}

class Home extends StatelessWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('samseer example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: samseer.showInspector,
            tooltip: 'Open inspector',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Dio', children: [
            _Tile(
              label: 'GET /posts',
              onTap: () =>
                  dio.get('https://jsonplaceholder.typicode.com/posts'),
            ),
            _Tile(
              label: 'GET /posts/1',
              onTap: () =>
                  dio.get('https://jsonplaceholder.typicode.com/posts/1'),
            ),
            _Tile(
              label: 'POST /posts',
              onTap: () => dio.post(
                'https://jsonplaceholder.typicode.com/posts',
                data: {'title': 'hello', 'body': 'samseer', 'userId': 1},
              ),
            ),
            _Tile(
              label: 'GET 404',
              onTap: () => dio
                  .get('https://jsonplaceholder.typicode.com/notfound')
                  .catchError(
                    (_) => Response(requestOptions: RequestOptions(path: '')),
                  ),
            ),
          ]),
          _Section(title: 'http package', children: [
            _Tile(
              label: 'GET /todos/1',
              onTap: () => httpClient.get(
                  Uri.parse('https://jsonplaceholder.typicode.com/todos/1')),
            ),
            _Tile(
              label: 'POST /posts',
              onTap: () => httpClient.post(
                Uri.parse('https://jsonplaceholder.typicode.com/posts'),
                body: '{"title":"x","body":"y","userId":1}',
                headers: {'content-type': 'application/json'},
              ),
            ),
          ]),
          _Section(title: 'dart:io HttpClient', children: [
            _Tile(
              label: 'GET /users/1',
              onTap: () async {
                final c = HttpClient();
                final req = await c.getUrl(
                  Uri.parse('https://jsonplaceholder.typicode.com/users/1'),
                );
                final res = await req.close();
                await res.drain<void>();
              },
            ),
            _Tile(
              label: 'POST JSON (request headers/body capture)',
              onTap: () async {
                final c = HttpClient();
                final req =
                    await c.postUrl(Uri.parse('https://httpbin.org/post'));
                req.headers.contentType =
                    ContentType('application', 'json', charset: 'utf-8');
                req.write('{"hello":"world"}');
                final res = await req.close();
                await res.drain<void>();
              },
            ),
          ]),
          _Section(title: 'Content types', children: [
            _Tile(
              label: 'form-urlencoded (Dio POST)',
              onTap: () => dio.post(
                'https://httpbin.org/post',
                data: {'title': 'hello', 'lang': 'dart'},
                options: Options(contentType: Headers.formUrlEncodedContentType),
              ),
            ),
            _Tile(
              label: 'multipart/form-data (Dio POST)',
              onTap: () => dio.post(
                'https://httpbin.org/post',
                data: FormData.fromMap({
                  'title': 'hello',
                  'avatar': MultipartFile.fromString(
                    'fake-avatar-bytes',
                    filename: 'avatar.txt',
                  ),
                }),
              ),
            ),
            _Tile(
              label: 'multipart/form-data (http POST)',
              onTap: () async {
                final request = http.MultipartRequest(
                  'POST',
                  Uri.parse('https://httpbin.org/post'),
                )
                  ..fields['title'] = 'hello'
                  ..files.add(http.MultipartFile.fromBytes(
                    'avatar',
                    utf8.encode('fake-avatar-bytes'),
                    filename: 'avatar.txt',
                  ));
                await httpClient.send(request);
              },
            ),
            _Tile(
              label: 'text/plain (http GET)',
              onTap: () =>
                  httpClient.get(Uri.parse('https://httpbin.org/robots.txt')),
            ),
            _Tile(
              label: 'text/html (http GET)',
              onTap: () =>
                  httpClient.get(Uri.parse('https://httpbin.org/html')),
            ),
            _Tile(
              label: 'application/xml (http GET)',
              onTap: () =>
                  httpClient.get(Uri.parse('https://httpbin.org/xml')),
            ),
            _Tile(
              label: 'application/octet-stream (http GET)',
              onTap: () =>
                  httpClient.get(Uri.parse('https://httpbin.org/bytes/1024')),
            ),
            _Tile(
              label: 'image/png (http GET)',
              onTap: () =>
                  httpClient.get(Uri.parse('https://httpbin.org/image/png')),
            ),
            _Tile(
              label: 'image/jpeg (Dio GET, bytes)',
              onTap: () => dio.get(
                'https://httpbin.org/image/jpeg',
                options: Options(responseType: ResponseType.bytes),
              ),
            ),
            _Tile(
              label: 'application/pdf (manual record)',
              onTap: () {
                final id = samseer.recordRequest(
                  method: 'GET',
                  uri: 'https://example.com/files/sample.pdf',
                  client: 'Manual',
                );
                final bytes = Uint8List.fromList(utf8.encode(
                  '%PDF-1.4\n1 0 obj<< /Type /Catalog >>endobj\n'
                  'trailer<< /Root 1 0 R >>\n%%EOF',
                ));
                samseer.recordResponse(
                  id,
                  status: 200,
                  headers: {'content-type': 'application/pdf'},
                  body: SamseerBinaryBody(
                    totalSize: bytes.length,
                    bytes: bytes,
                    contentType: 'application/pdf',
                  ),
                );
              },
            ),
            _Tile(
              label: 'text/csv (manual record)',
              onTap: () {
                final id = samseer.recordRequest(
                  method: 'GET',
                  uri: 'https://example.com/files/sample.csv',
                  client: 'Manual',
                );
                samseer.recordResponse(
                  id,
                  status: 200,
                  headers: {'content-type': 'text/csv'},
                  body: 'name,age,city\n'
                      'Ada Lovelace,36,London\n'
                      'Alan Turing,41,Manchester\n',
                );
              },
            ),
          ]),
          _Section(title: 'WebView (flutter_inappwebview)', children: [
            _Tile(
              label: 'Open WebView demo',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SamseerWebViewDemoPage(samseer: samseer),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: const Icon(Icons.send),
        onTap: onTap,
      ),
    );
  }
}
