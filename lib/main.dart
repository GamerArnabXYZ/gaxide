import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:highlight/languages/javascript.dart'; // Default language JS rakh rahe hain

void main() {
  runApp(const GaxIdeApp());
}

class GaxIdeApp extends StatelessWidget {
  const GaxIdeApp({super.key});

  @super
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAX IDE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6200EE),
          brightness: Brightness.dark, // Clean dark theme for long coding sessions
        ),
      ),
      home: const IdeHomeScreen(),
    );
  }
}

class IdeHomeScreen extends StatefulWidget {
  const IdeHomeScreen({super.key});

  @super
  State<IdeHomeScreen> createState() => _IdeHomeScreenState();
}

class _IdeHomeScreenState extends State<IdeHomeScreen> {
  // Controllers for Configuration Inputs
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _repoController = TextEditingController();
  final TextEditingController _pathController = TextEditingController();
  final TextEditingController _commitController = TextEditingController();

  // Code Field Controller (Lines & Syntax Handle)
  late CodeController _codeController;

  String _statusLog = "System Ready. Open/Write a file and push.";
  bool _isLoading = false;

  @super
  void initState() {
    super.initState();
    // Initialize the advanced code editor field
    _codeController = CodeController(
      text: "// Write your code here...\nfunction helloWorld() {\n  console.log('Hello from GAX IDE');\n}",
      language: javascript,
    );
  }

  @super
  void dispose() {
    _tokenController.dispose();
    _repoController.dispose();
    _pathController.dispose();
    _commitController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // --- GIT PUSH VIA GITHUB REST API LOGIC ---
  Future<void> _pushToGithub() async {
    final token = _tokenController.text.trim();
    final repo = _repoController.text.trim();
    final filePath = _pathController.text.trim();
    final codeContent = _codeController.text;
    final commitMsg = _commitController.text.trim().isEmpty 
        ? "Update via GAX IDE Mobile" 
        : _commitController.text.trim();

    if (token.isEmpty || repo.isEmpty || filePath.isEmpty) {
      setState(() {
        _statusLog = "❌ Error: Token, Repo, and File Path are strictly required!";
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _statusLog = "⏳ Fetching repository metadata (checking file SHA)...";
    });

    final url = Uri.parse("https://api.github.com/repos/$repo/contents/$filePath");
    final headers = {
      "Authorization": "token $token",
      "Accept": "application/vnd.github.v3+json",
      "Content-Type": "application/json",
    };

    try {
      // Step 1: Remote file check karte hain taaki agar file pehle se ho toh uska SHA mil sake
      String? sha;
      final getResponse = await http.get(url, headers: headers);
      
      if (getResponse.statusCode == 200) {
        final decodedData = jsonDecode(getResponse.body);
        sha = decodedData['sha'];
      }

      // Step 2: Content ko base64 standard mein encode karna (GitHub API requirement)
      final bytes = utf8.encode(codeContent);
      final base64Content = base64.encode(bytes);

      // Step 3: Payload structure set karna
      final Map<String, dynamic> requestBody = {
        "message": commitMsg,
        "content": base64Content,
      };
      if (sha != null) {
        requestBody["sha"] = sha; // Mandatory parameter if file already exists
      }

      setState(() {
        _statusLog = "⏳ Uploading source payload to GitHub branch...";
      });

      // Step 4: PUT Request launch karna
      final putResponse = await http.put(
        url,
        headers: headers,
        body: jsonEncode(requestBody),
      );

      if (putResponse.statusCode == 200 || putResponse.statusCode == 201) {
        setState(() {
          _statusLog = "🚀 SUCCESS! Script pushed safely to GitHub tree.";
        });
      } else {
        setState(() {
          _statusLog = "❌ FAILED!\nCode: ${putResponse.statusCode}\nResponse: ${putResponse.body}";
        });
      }
    } catch (e) {
      setState(() {
        _statusLog = "❌ Network Exception: ${e.toString()}";
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @super
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('GAX IDE v1.0', style: GoogleFonts.orbitron(letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            // Configuration Panel
            ExpansionTile(
              title: const Text("GitHub Configuration Tools", style: TextStyle(fontWeight: FontWeight.bold)),
              initiallyExpanded: true,
              children: [
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Personal Access Token (PAT)', isDense: true),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _repoController,
                  decoration: const InputDecoration(hintText: 'username/repo-name (e.g., GamerArnabXYZ/GAX-Forge)', isDense: true),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pathController,
                        decoration: const InputDecoration(hintText: 'filename (e.g., index.js)', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _commitController,
                        decoration: const InputDecoration(hintText: 'Commit msg (Optional)', isDense: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
            
            const SizedBox(height: 10),
            
            // Code Editor Box
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CodeField(
                    controller: _codeController,
                    textStyle: GoogleFonts.firaCode(fontSize: 14),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 10),

            // Logger & Action Button
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _statusLog,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            const SizedBox(height: 10),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isLoading ? null : _pushToGithub,
                icon: _isLoading 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.cloud_upload),
                label: const Text("EXECUTE REMOTE PUSH", style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[700],
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
