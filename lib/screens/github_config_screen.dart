import 'package:flutter/material.dart';
import '../services/prefs_service.dart';
import '../widgets/config_panel.dart';

/// Dedicated Settings screen — reached via the gear icon on the File Manager.
/// Holds the GitHub PAT / Repo / Branch defaults, autosaved as you type.
class GithubConfigScreen extends StatefulWidget {
  const GithubConfigScreen({super.key});

  @override
  State<GithubConfigScreen> createState() => _GithubConfigScreenState();
}

class _GithubConfigScreenState extends State<GithubConfigScreen> {
  final _tokenController = TextEditingController();
  final _repoController = TextEditingController();
  final _branchController = TextEditingController();
  final _prefsService = PrefsService();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await _prefsService.load();
    if (!mounted) return;
    _tokenController.text = config.token;
    _repoController.text = config.repo;
    _branchController.text = config.branch;
    setState(() => _loading = false);
  }

  Future<void> _persist([String? _]) async {
    await _prefsService.save(GaxConfig(
      token: _tokenController.text.trim(),
      repo: _repoController.text.trim(),
      branch: _branchController.text.trim(),
    ));
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _repoController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GitHub Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: ConfigPanel(
                  tokenController: _tokenController,
                  repoController: _repoController,
                  branchController: _branchController,
                  onAnyFieldChanged: _persist,
                ),
              ),
            ),
    );
  }
}
