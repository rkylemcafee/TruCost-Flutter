import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Step 1: Are you leased to a carrier or independent?
///
/// Goes in: lib/onboarding/setup_step.dart

class SetupStep extends StatelessWidget {
  final void Function(bool isLeased) onNext;
  const SetupStep({super.key, required this.onNext});

  Future<void> _select(BuildContext context, bool isLeased) async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;
    if (user == null) return;

    await supabase.from('profiles').update({
      'lease_status': isLeased ? 'leased' : 'independent',
      'carrier_cut_pct': isLeased ? 25 : 0,
      'overhead_pct': isLeased ? 15 : 25,
    }).eq('user_id', user.id);

    onNext(isLeased);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.local_shipping, size: 64, color: Colors.blueGrey),
          const SizedBox(height: 24),
          const Text(
            'How do you run?',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'This helps us calculate your real take-home.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          ElevatedButton.icon(
            onPressed: () => _select(context, true),
            icon: const Icon(Icons.handshake),
            label: const Text('Leased to a Carrier'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 20),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _select(context, false),
            icon: const Icon(Icons.person),
            label: const Text('Independent / Own Authority'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 20),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
    );
  }
}
