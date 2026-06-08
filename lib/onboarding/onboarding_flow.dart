import 'package:flutter/material.dart';
import 'setup_step.dart';
import 'carrier_step.dart';
import 'rig_step.dart';
import 'defaults_step.dart';
import 'complete_step.dart';

/// Wizard container — manages step navigation and progress bar.
/// Skips the Carrier step for independent operators.
///
/// Goes in: lib/onboarding/onboarding_flow.dart

enum _Step { setup, carrier, rig, defaults, complete }

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingFlow({super.key, required this.onComplete});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Step _step = _Step.setup;
  bool _isLeased = true;

  void _afterSetup(bool isLeased) {
    setState(() {
      _isLeased = isLeased;
      _step = isLeased ? _Step.carrier : _Step.rig;
    });
  }

  void _afterCarrier() => setState(() => _step = _Step.rig);
  void _afterRig() => setState(() => _step = _Step.defaults);
  void _afterDefaults() => setState(() => _step = _Step.complete);

  void _back() {
    setState(() {
      switch (_step) {
        case _Step.carrier:
          _step = _Step.setup;
        case _Step.rig:
          _step = _isLeased ? _Step.carrier : _Step.setup;
        case _Step.defaults:
          _step = _Step.rig;
        case _Step.complete:
          _step = _Step.defaults;
        default:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalSteps = _isLeased ? 5 : 4;
    final currentIdx = switch (_step) {
      _Step.setup => 0,
      _Step.carrier => 1,
      _Step.rig => _isLeased ? 2 : 1,
      _Step.defaults => _isLeased ? 3 : 2,
      _Step.complete => _isLeased ? 4 : 3,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Setup'),
        leading: _step != _Step.setup
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _back,
              )
            : null,
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
            value: (currentIdx + 1) / totalSteps,
            backgroundColor: Colors.grey[200],
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: switch (_step) {
                _Step.setup => SetupStep(key: const ValueKey('setup'), onNext: _afterSetup),
                _Step.carrier => CarrierStep(key: const ValueKey('carrier'), onNext: _afterCarrier),
                _Step.rig => RigStep(key: const ValueKey('rig'), onNext: _afterRig),
                _Step.defaults => DefaultsStep(key: const ValueKey('defaults'), onNext: _afterDefaults),
                _Step.complete => CompleteStep(key: const ValueKey('complete'), onFinish: widget.onComplete),
              },
            ),
          ),
        ],
      ),
    );
  }
}
