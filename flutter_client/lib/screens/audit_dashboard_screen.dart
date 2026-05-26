import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AuditDashboardScreen extends StatefulWidget {
  const AuditDashboardScreen({super.key});

  @override
  State<AuditDashboardScreen> createState() => _AuditDashboardScreenState();
}

class _AuditDashboardScreenState extends State<AuditDashboardScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String? _error;
  
  List<dynamic> _ghostTopics = [];
  List<dynamic> _inconsistencies = [];
  List<dynamic> _gaps = [];

  @override
  void initState() {
    super.initState();
    _triggerAudit();
  }

  Future<void> _triggerAudit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await _apiService.runAudit();
      setState(() {
        _ghostTopics = results['ghost_topics'] ?? [];
        _inconsistencies = results['inconsistencies'] ?? [];
        _gaps = results['gaps'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _resolveItem(String title, String suggestedCategory) async {
    final categoryController = TextEditingController(text: suggestedCategory);
    final BuildContext currentContext = context;

    showDialog(
      context: currentContext,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
          ),
          title: Text(
            "Resolve Topic",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Create note for: '$title'",
                style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: categoryController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 13),
                decoration: InputDecoration(
                  labelText: "Category (e.g. Recipe, Event)",
                  labelStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black45),
                  filled: true,
                  fillColor: isDark ? const Color(0xFF050505) : const Color(0xFFF1F5F9),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
            ),
            TextButton(
              onPressed: () async {
                final category = categoryController.text.trim();
                Navigator.pop(context);
                if (category.isNotEmpty) {
                  showDialog(
                    context: currentContext,
                    barrierDismissible: false,
                    builder: (context) => Center(
                      child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    ),
                  );

                  try {
                    await _apiService.createNote(title, category);
                    if (currentContext.mounted) {
                      Navigator.pop(currentContext); // Dismiss progress spinner
                      ScaffoldMessenger.of(currentContext).showSnackBar(
                        SnackBar(
                          content: Text("✓ Note '$title' created!"),
                          backgroundColor: const Color(0xFF22C55E),
                        ),
                      );
                      _triggerAudit(); // Refresh the list
                    }
                  } catch (e) {
                    if (currentContext.mounted) {
                      Navigator.pop(currentContext); // Dismiss progress spinner
                      ScaffoldMessenger.of(currentContext).showSnackBar(
                        SnackBar(
                          content: Text("❌ Failed: $e"),
                          backgroundColor: Colors.redAccent,
                        ),
                      );
                    }
                  }
                }
              },
              child: Text(
                "Create Note",
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'VAULT AUDIT & HYGIENE',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 13),
        ),
        backgroundColor: isDark ? const Color(0xFF111111) : Colors.white,
        elevation: 0,
        shape: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0),
            width: 1,
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  const Text(
                    "Analyzing Vault Integrity...",
                    style: TextStyle(color: Colors.white30, fontSize: 12, fontFamily: 'monospace'),
                  ),
                ],
              ),
            )
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning, color: Colors.redAccent, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _triggerAudit,
                          icon: const Icon(Icons.refresh),
                          label: const Text("RETRY AUDIT"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: Theme.of(context).colorScheme.primary,
                  onRefresh: _triggerAudit,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildHeaderStats(isDark),
                      const SizedBox(height: 20),
                      _buildSectionTitle(
                        "Contradictions & Inconsistencies",
                        Icons.crisis_alert,
                        Colors.redAccent,
                        isDark,
                      ),
                      const SizedBox(height: 8),
                      _buildInconsistenciesList(isDark),
                      const SizedBox(height: 24),
                      _buildSectionTitle(
                        "Ghost Topics (Missing Notes)",
                        Icons.explore_off_outlined,
                        Colors.orangeAccent,
                        isDark,
                      ),
                      const SizedBox(height: 8),
                      _buildGhostTopicsList(isDark),
                      const SizedBox(height: 24),
                      _buildSectionTitle(
                        "Suggested Knowledge Gaps",
                        Icons.lightbulb,
                        Colors.indigoAccent,
                        isDark,
                      ),
                      const SizedBox(height: 8),
                      _buildGapsList(isDark),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLoading ? null : _triggerAudit,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.black,
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildHeaderStats(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF111111) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified, color: Color(0xFF10B981), size: 20),
              const SizedBox(width: 8),
              Text(
                "LIBRARIAN VAULT INTEGRITY",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: isDark ? Colors.white70 : const Color(0xFF0F172A),
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem("CONTRADICTIONS", "${_inconsistencies.length}", Colors.redAccent),
              _buildStatItem("GHOST TOPICS", "${_ghostTopics.length}", Colors.orangeAccent),
              _buildStatItem("GAPS", "${_gaps.length}", Colors.indigoAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String val, Color col) {
    return Column(
      children: [
        Text(
          val,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: col),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 9, color: Colors.white30, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Color color, bool isDark) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: isDark ? Colors.white70 : const Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  Widget _buildInconsistenciesList(bool isDark) {
    if (_inconsistencies.isEmpty) {
      return _buildEmptyCard("No claim contradictions detected.", Colors.redAccent.withOpacity(0.1), isDark);
    }

    return Column(
      children: _inconsistencies.map((inc) {
        final articles = inc['articles'] as List? ?? [];
        final conflict = inc['conflict'] ?? '';
        return Card(
          color: isDark ? const Color(0xFF111111) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.redAccent, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Conflict: ${articles.join(' ↔ ')}",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  conflict,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54, height: 1.4),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGhostTopicsList(bool isDark) {
    if (_ghostTopics.isEmpty) {
      return _buildEmptyCard("No ghost topics found.", Colors.orangeAccent.withOpacity(0.1), isDark);
    }

    return Column(
      children: _ghostTopics.map((g) {
        final title = g['title'] ?? '';
        final sources = g['sources'] as List? ?? [];
        String suggestedCategory = "Inbox";
        if (sources.isNotEmpty) {
          final firstSource = sources.first.toString();
          if (firstSource.contains('/')) {
            suggestedCategory = firstSource.split('/').first;
          }
        }

        return Card(
          color: isDark ? const Color(0xFF111111) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
          ),
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.link_off, color: Colors.orangeAccent),
            title: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            subtitle: Text(
              "Referenced in: ${sources.join(', ')}",
              style: const TextStyle(fontSize: 10, color: Colors.white30),
            ),
            trailing: TextButton.icon(
              onPressed: () => _resolveItem(title, suggestedCategory),
              icon: const Icon(Icons.add, size: 14),
              label: const Text("CREATE", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.orangeAccent,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildGapsList(bool isDark) {
    if (_gaps.isEmpty) {
      return _buildEmptyCard("No coverage gaps detected.", Colors.indigoAccent.withOpacity(0.1), isDark);
    }

    return Column(
      children: _gaps.map((gap) {
        final suggestedTitle = gap['suggested_title'] ?? '';
        final reason = gap['reason'] ?? '';
        
        return Card(
          color: isDark ? const Color(0xFF111111) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: isDark ? const Color(0xFF222222) : const Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.lightbulb_outline, color: Colors.indigoAccent),
              title: Text(
                suggestedTitle,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  reason,
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                ),
              ),
              trailing: TextButton.icon(
                onPressed: () => _resolveItem(suggestedTitle, "General"),
                icon: const Icon(Icons.add, size: 14),
                label: const Text("ADD", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.indigoAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyCard(String msg, Color tint, bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0C0C0C) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF1F5F9),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(color: isDark ? Colors.white30 : Colors.black45, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
