import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/watch_plan.dart';
import '../../core/config/app_config.dart';
import 'watch_plan_detail_screen.dart';

class WatchPlansScreen extends StatefulWidget {
  const WatchPlansScreen({super.key});

  @override
  State<WatchPlansScreen> createState() => _WatchPlansScreenState();
}

class _WatchPlansScreenState extends State<WatchPlansScreen> {
  List<WatchPlan> _plans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  List<WatchPlan> _getDefaultPlansForInstance() {
    if (AppConfig.instanceId == 'centum_tube') {
      return [
        WatchPlan(
          id: 'centum_plan_1',
          title: '100/100 Daily Mathematics Sprint',
          description: 'Master advanced calculus, linear algebra, geometry, and problem solving every day.',
          targetMinutesPerDay: 20,
          completedVideosCount: 8,
          streakDays: 5,
          createdAt: DateTime.now().subtract(const Duration(days: 5)),
        ),
        WatchPlan(
          id: 'centum_plan_2',
          title: 'STEM & Physics Intuition (30-Day Series)',
          description: 'Visualize physical phenomena, thermodynamics, quantum mechanics, and core concepts.',
          targetMinutesPerDay: 25,
          completedVideosCount: 4,
          streakDays: 3,
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
        WatchPlan(
          id: 'centum_plan_3',
          title: 'Number Theory & Puzzles Mastery',
          description: 'Deep dive into primes, higher-dimensional geometry, entropy, and mathematical beauty.',
          targetMinutesPerDay: 15,
          completedVideosCount: 6,
          streakDays: 4,
          createdAt: DateTime.now().subtract(const Duration(days: 4)),
        ),
      ];
    } else {
      return [
        WatchPlan(
          id: 'ct_plan_1',
          title: 'Morning Prayer & Worship',
          description: 'Start your morning with inspiring praise, devotionals, and scripture meditation.',
          targetMinutesPerDay: 15,
          completedVideosCount: 12,
          streakDays: 7,
          createdAt: DateTime.now().subtract(const Duration(days: 7)),
        ),
        WatchPlan(
          id: 'ct_plan_2',
          title: 'Through the Gospels (30-Day Series)',
          description: 'Deep dive into the life, teachings, and spiritual lessons of Jesus Christ.',
          targetMinutesPerDay: 20,
          completedVideosCount: 5,
          streakDays: 3,
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
        ),
      ];
    }
  }

  Future<void> _loadPlans() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'watch_plans_${AppConfig.instanceId}';
    final savedJson = prefs.getString(key);

    if (savedJson != null) {
      try {
        final List<dynamic> list = jsonDecode(savedJson);
        _plans = list.map((item) => WatchPlan.fromJson(item as Map<String, dynamic>)).toList();
      } catch (e) {
        _plans = _getDefaultPlansForInstance();
      }
    } else {
      _plans = _getDefaultPlansForInstance();
      await _savePlans();
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _savePlans() async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'watch_plans_${AppConfig.instanceId}';
    final data = _plans.map((p) => p.toJson()).toList();
    await prefs.setString(key, jsonEncode(data));
  }

  void _showCreatePlanDialog() {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    int targetMins = 20;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.playlist_add, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Create ${AppConfig.appName} Plan'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Plan Title *',
                      hintText: 'e.g. Daily Calculus Sprint',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Description (Optional)',
                      hintText: 'What are your learning goals?',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('Daily Goal: $targetMins minutes/day', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Slider(
                    value: targetMins.toDouble(),
                    min: 5,
                    max: 60,
                    divisions: 11,
                    label: '$targetMins mins',
                    onChanged: (val) {
                      setDialogState(() => targetMins = val.toInt());
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final title = titleCtrl.text.trim();
                  if (title.isNotEmpty) {
                    final newPlan = WatchPlan(
                      id: 'plan_${DateTime.now().millisecondsSinceEpoch}',
                      title: title,
                      description: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : null,
                      targetMinutesPerDay: targetMins,
                      completedVideosCount: 0,
                      streakDays: 0,
                      createdAt: DateTime.now(),
                    );
                    setState(() {
                      _plans.insert(0, newPlan);
                    });
                    _savePlans();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Created plan "$title"!')),
                    );
                  }
                },
                child: const Text('Create Plan'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${AppConfig.appName} Watch Plans'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Create Plan',
            onPressed: _showCreatePlanDialog,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreatePlanDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Plan'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school_outlined, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text('No watch plans created yet.'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _showCreatePlanDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Create Your First Plan'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _plans.length,
                  itemBuilder: (context, index) {
                    final plan = _plans[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 16),
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (ctx) => WatchPlanDetailScreen(plan: plan)),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      plan.title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.local_fire_department, size: 16, color: Colors.orange),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${plan.streakDays}d streak',
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (plan.description != null)
                                Text(
                                  plan.description!,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Icon(Icons.timer_outlined, size: 16, color: theme.colorScheme.primary),
                                  const SizedBox(width: 6),
                                  Text('${plan.targetMinutesPerDay} mins/day', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                  const SizedBox(width: 16),
                                  const Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
                                  const SizedBox(width: 6),
                                  Text('${plan.completedVideosCount} completed', style: const TextStyle(fontSize: 12)),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (ctx) => WatchPlanDetailScreen(plan: plan)),
                                      );
                                    },
                                    child: const Text('Continue Plan →'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
