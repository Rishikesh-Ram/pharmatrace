import 'package:flutter/material.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _Org {
  final String name, role;
  String status;
  _Org(this.name, this.role, this.status);
}

class _AdminScreenState extends State<AdminScreen> {
  final _orgs = <_Org>[];

  Color _color(String s) => s == 'Approved'
      ? Colors.green
      : s == 'Rejected'
      ? Colors.red
      : Colors.orange;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin: organizations')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_orgs.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No organizations registered yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              for (final o in _orgs)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.business),
                    title: Text(o.name),
                    subtitle: Text(
                      '${o.role} • ${o.status}',
                      style: TextStyle(color: _color(o.status)),
                    ),
                    trailing: o.status == 'Pending'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.green,
                                ),
                                onPressed: () =>
                                    setState(() => o.status = 'Approved'),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    setState(() => o.status = 'Rejected'),
                              ),
                            ],
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
