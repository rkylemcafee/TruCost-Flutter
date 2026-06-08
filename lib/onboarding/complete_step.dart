import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Final step: marks onboarding complete and exits to the main app.
///
/// Goes in: lib/onboarding/complete_step.dart

class CompleteStep extends StatefulWidget {
  final VoidCallback onFinish;
  const CompleteStep({super.key, required this.onFinish});

  @override
  State<CompleteStep> createState() => _CompleteStepState();
}

class _CompleteStepState extends State<CompleteStep> {
  bool _loading = false;

  Future<void> _finish() async {
    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      await supabase.from('profiles').update({
        'onboarding_complete': true,
      }).eq('user_id', user.id);

      widget.onFinish();
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 96, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            "You're Set!",
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Your rig, defaults, and carrier deal are saved.\n'
            'Update them anytime in Settings.\n\n'
            "Let's run your first load.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 48),
          ElevatedButton(
            onPressed: _loading ? null : _finish,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: _loading
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text("Let's Go", style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
}
