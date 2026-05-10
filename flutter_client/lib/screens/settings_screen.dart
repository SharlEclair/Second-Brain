import 'package:flutter/material.dart';
import '../services/api_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUrl();
  }

  void _loadCurrentUrl() async {
    final url = await _apiService.getBaseUrl();
    if (url != null) {
      _urlController.text = url;
    }
  }

  void _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isNotEmpty) {
      await _apiService.setBaseUrl(url);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backend URL saved successfully')),
        );
      }
    }
  }

  void _testConnection() async {
    final error = await _apiService.checkConnectivity();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error == null ? '✓ Connected to backend!' : '✗ $error'),
          backgroundColor: error == null ? const Color(0xFF22C55E) : Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _triggerSync() async {
    setState(() => _isSyncing = true);
    try {
      await _apiService.syncVault();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vault synced successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SETTINGS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 14)),
        backgroundColor: const Color(0xFF111111),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Backend API URL",
              style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              style: const TextStyle(fontFamily: 'monospace', color: Colors.white),
              decoration: InputDecoration(
                hintText: "http://192.168.1.X:8000",
                hintStyle: const TextStyle(color: Colors.white24),
                fillColor: const Color(0xFF111111),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: Color(0xFF333333)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: const BorderSide(color: Color(0xFF222222)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveUrl,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
                child: const Text("SAVE NETWORK SETTINGS", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testConnection,
                icon: const Icon(Icons.wifi_find, size: 18),
                label: const Text("TEST CONNECTION", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFF333333)),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
              ),
            ),
            const SizedBox(height: 48),
            const Divider(color: Color(0xFF222222)),
            const SizedBox(height: 32),
            const Text(
              "Vault Operations",
              style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSyncing ? null : _triggerSync,
                icon: _isSyncing 
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)) 
                  : const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  _isSyncing ? "SYNCING..." : "FORCE SYNC TO GITHUB", 
                  style: const TextStyle(letterSpacing: 1.0, fontWeight: FontWeight.bold)
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: const BorderSide(color: Color(0xFF333333)),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
