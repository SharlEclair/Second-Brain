import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:home_widget/home_widget.dart';
import '../services/api_service.dart';
import '../main.dart';
import 'debug_logs_screen.dart';
import 'analytics_dashboard_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _urlController = TextEditingController();
  final ApiService _apiService = ApiService();
  bool _isSyncing = false;
  bool _isLightTheme = false;
  
  double _widgetOpacity = 0.9;
  String _widgetTheme = "System";
  bool _widgetShowVoice = true;
  bool _widgetShowClipboard = true;
  bool _widgetShowScratchpad = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentUrl();
    _loadCurrentTheme();
    _loadWidgetSettings();
  }

  void _loadWidgetSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _widgetOpacity = prefs.getDouble('widget_opacity') ?? 0.9;
      _widgetTheme = prefs.getString('widget_theme') ?? "System";
      _widgetShowVoice = prefs.getBool('widget_show_voice') ?? true;
      _widgetShowClipboard = prefs.getBool('widget_show_clipboard') ?? true;
      _widgetShowScratchpad = prefs.getBool('widget_show_scratchpad') ?? true;
    });
  }

  void _saveWidgetSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is double) {
      await prefs.setDouble(key, value);
      await HomeWidget.saveWidgetData<double>(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
      await HomeWidget.saveWidgetData<String>(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
      await HomeWidget.saveWidgetData<bool>(key, value);
    }
    
    // Call updateWidget to paint immediately
    await HomeWidget.updateWidget(
      name: 'ThoughtSparkWidgetProvider',
      androidName: 'ThoughtSparkWidgetProvider',
    );
    await HomeWidget.updateWidget(
      name: 'FocusMissionWidgetProvider',
      androidName: 'FocusMissionWidgetProvider',
    );
  }

  void _loadCurrentUrl() async {
    final url = await _apiService.getBaseUrl();
    if (url != null) {
      _urlController.text = url;
    }
  }

  void _loadCurrentTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isLightTheme = prefs.getBool('is_light_theme') ?? false;
    });
  }

  void _toggleTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_light_theme', value);
    setState(() {
      _isLightTheme = value;
    });
    themeNotifier.value = value ? ThemeMode.light : ThemeMode.dark;
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

  void _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _urlController.text = data.text!;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL pasted from clipboard')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text found in clipboard')),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SETTINGS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 14)),
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- Appearance Settings ---
            Text(
              "Appearance",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54, 
                fontWeight: FontWeight.bold, 
                letterSpacing: 1.2, 
                fontSize: 12
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111111) : Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
              ),
              child: SwitchListTile(
                title: Text(
                  "Light Theme (Clean Lab)",
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                    fontSize: 14,
                    fontWeight: FontWeight.w500
                  ),
                ),
                subtitle: Text(
                  "Switch between Hacker Grid Dark and Clean Lab Light themes.",
                  style: TextStyle(color: isDark ? Colors.white30 : Colors.black45, fontSize: 11),
                ),
                value: _isLightTheme,
                onChanged: _toggleTheme,
                activeColor: primaryColor,
              ),
            ),
            const SizedBox(height: 32),

            // --- Network Settings ---
            Text(
              "Backend API URL",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54, 
                fontWeight: FontWeight.bold, 
                letterSpacing: 1.2, 
                fontSize: 12
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              style: TextStyle(fontFamily: 'monospace', color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                hintText: "http://192.168.1.X:8000",
                hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38),
                fillColor: isDark ? const Color(0xFF111111) : Colors.white,
                filled: true,
                suffixIcon: IconButton(
                  icon: Icon(Icons.content_paste, color: isDark ? Colors.white54 : Colors.black54, size: 20),
                  onPressed: _pasteFromClipboard,
                  tooltip: "Paste from clipboard",
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                  borderSide: BorderSide(color: primaryColor, width: 1),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveUrl,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
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
                  side: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
                  foregroundColor: isDark ? Colors.white : Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Divider(color: isDark ? Colors.white10 : Colors.black12),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const DebugLogsScreen()));
                },
                icon: Icon(Icons.bug_report_outlined, color: isDark ? Colors.white24 : Colors.black26),
                label: Text("VIEW DEBUG LOGS", style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const AnalyticsDashboardScreen()));
                },
                icon: Icon(Icons.analytics_outlined, color: isDark ? Colors.white24 : Colors.black26),
                label: Text("VIEW VAULT ANALYTICS", style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
              ),
            ),
            const SizedBox(height: 32),
            Divider(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
            const SizedBox(height: 32),
            Text(
              "Home Screen Widgets",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54, 
                fontWeight: FontWeight.bold, 
                letterSpacing: 1.2, 
                fontSize: 12
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF111111) : Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Background Transparency",
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: _widgetOpacity,
                          min: 0.1,
                          max: 1.0,
                          divisions: 9,
                          activeColor: primaryColor,
                          label: "${(_widgetOpacity * 100).round()}%",
                          onChanged: (val) {
                            setState(() => _widgetOpacity = val);
                          },
                          onChangeEnd: (val) {
                            _saveWidgetSetting('widget_opacity', val);
                          },
                        ),
                      ),
                      Text(
                        "${(_widgetOpacity * 100).round()}%",
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Widget Theme Override",
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      DropdownButton<String>(
                        value: _widgetTheme,
                        dropdownColor: isDark ? const Color(0xFF111111) : Colors.white,
                        underline: const SizedBox(),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        items: ["System", "Hacker Dark", "Clean Lab Light"].map((String themeVal) {
                          return DropdownMenuItem<String>(
                            value: themeVal,
                            child: Text(themeVal),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _widgetTheme = val);
                            _saveWidgetSetting('widget_theme', val);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Divider(color: isDark ? Colors.white10 : Colors.black12),
                  const SizedBox(height: 8),
                  Text(
                    "Thought Spark Action Shortcuts",
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  CheckboxListTile(
                    title: const Text("Show Voice Dictation Button", style: TextStyle(fontSize: 12)),
                    value: _widgetShowVoice,
                    activeColor: primaryColor,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _widgetShowVoice = val);
                        _saveWidgetSetting('widget_show_voice', val);
                      }
                    },
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text("Show Clipboard Ingest Button", style: TextStyle(fontSize: 12)),
                    value: _widgetShowClipboard,
                    activeColor: primaryColor,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _widgetShowClipboard = val);
                        _saveWidgetSetting('widget_show_clipboard', val);
                      }
                    },
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: EdgeInsets.zero,
                  ),
                  CheckboxListTile(
                    title: const Text("Show Scratchpad Button", style: TextStyle(fontSize: 12)),
                    value: _widgetShowScratchpad,
                    activeColor: primaryColor,
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _widgetShowScratchpad = val);
                        _saveWidgetSetting('widget_show_scratchpad', val);
                      }
                    },
                    controlAffinity: ListTileControlAffinity.trailing,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Divider(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
            const SizedBox(height: 32),
            Text(
              "Vault Operations",
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54, 
                fontWeight: FontWeight.bold, 
                letterSpacing: 1.2, 
                fontSize: 12
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isSyncing ? null : _triggerSync,
                icon: _isSyncing 
                  ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? Colors.white54 : Colors.black54)) 
                  : const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  _isSyncing ? "SYNCING..." : "FORCE SYNC TO GITHUB", 
                  style: const TextStyle(letterSpacing: 1.0, fontWeight: FontWeight.bold)
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: isDark ? const Color(0xFF333333) : const Color(0xFFE2E8F0)),
                  foregroundColor: isDark ? Colors.white : Colors.black87,
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
