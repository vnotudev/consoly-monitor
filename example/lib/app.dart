import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _api = 'https://jsonplaceholder.typicode.com';

/// The app knows nothing about consoly_monitor; the dev entrypoint injects
/// the observer and builder.
class ExampleApp extends StatelessWidget {
  const ExampleApp({
    super.key,
    this.navigatorObservers = const [],
    this.builder,
  });

  final List<NavigatorObserver> navigatorObservers;
  final TransitionBuilder? builder;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Consoly Monitor Example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo),
      navigatorObservers: navigatorObservers,
      builder: builder,
      routes: {
        '/': (_) => const PostsPage(),
        '/users': (_) => const UsersPage(),
      },
    );
  }
}

Future<List<dynamic>> _getList(String path) async {
  final res = await http.get(Uri.parse('$_api$path'));
  return jsonDecode(res.body) as List<dynamic>;
}

class PostsPage extends StatefulWidget {
  const PostsPage({super.key});

  @override
  State<PostsPage> createState() => _PostsPageState();
}

class _PostsPageState extends State<PostsPage> {
  late Future<List<dynamic>> _posts = _getList('/posts?_limit=20');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Posts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                setState(() => _posts = _getList('/posts?_limit=20')),
          ),
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: () => Navigator.pushNamed(context, '/users'),
          ),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _posts,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              for (final p in snap.data!)
                ListTile(
                  title: Text(p['title'] as String),
                  // Unnamed route: the monitor names it "PostDetailPage".
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PostDetailPage(id: p['id'] as int),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class PostDetailPage extends StatefulWidget {
  const PostDetailPage({super.key, required this.id});

  final int id;

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  late final Future<List<dynamic>> _data = Future.wait([
    http
        .get(Uri.parse('$_api/posts/${widget.id}'))
        .then((r) => jsonDecode(r.body)),
    _getList('/posts/${widget.id}/comments'),
  ]);

  Future<void> _like() async {
    await http.post(
      Uri.parse('$_api/posts/${widget.id}/likes'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'liked': true}),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Post ${widget.id}'),
        actions: [
          IconButton(icon: const Icon(Icons.favorite), onPressed: _like),
        ],
      ),
      body: FutureBuilder<List<dynamic>>(
        future: _data,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final post = snap.data![0] as Map<String, dynamic>;
          final comments = snap.data![1] as List<dynamic>;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                post['title'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(post['body'] as String),
              const Divider(height: 32),
              for (final c in comments)
                ListTile(
                  title: Text(c['email'] as String),
                  subtitle: Text(c['body'] as String),
                ),
            ],
          );
        },
      ),
    );
  }
}

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      body: FutureBuilder<List<dynamic>>(
        future: _getList('/users'),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            children: [
              for (final u in snap.data!)
                ListTile(
                  title: Text(u['name'] as String),
                  subtitle: Text(u['email'] as String),
                ),
            ],
          );
        },
      ),
    );
  }
}
