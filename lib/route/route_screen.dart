import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../config/supabase_config.dart';
import '../calculator/calculator_screen.dart';

/// Route screen: enter pickup + delivery, auto-compute deadhead + loaded miles.
/// GPS for current location (deadhead origin). Google Directions API for miles.
///
/// Goes in: lib/route/route_screen.dart

class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key});
  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  final _pickupCtrl = TextEditingController();
  final _deliveryCtrl = TextEditingController();

  String _currentLocation = '';
  double? _deadheadMiles;
  double? _loadedMiles;
  bool _gettingLocation = false;
  bool _calculatingRoute = false;
  String? _error;

  Future<void> _getGpsLocation() async {
    setState(() {
      _gettingLocation = true;
      _error = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error = 'Location services are disabled. Turn them on in Settings.';
          _gettingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _error = 'Location permission denied.';
            _gettingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Location permission permanently denied. Enable in Settings.';
          _gettingLocation = false;
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      setState(() {
        _currentLocation = '${position.latitude},${position.longitude}';
        _gettingLocation = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not get location: $e';
        _gettingLocation = false;
      });
    }
  }

  Future<void> _calculateRoute() async {
    final pickup = _pickupCtrl.text.trim();
    final delivery = _deliveryCtrl.text.trim();

    if (pickup.isEmpty || delivery.isEmpty) {
      setState(() => _error = 'Enter both pickup and delivery addresses.');
      return;
    }

    final origin = _currentLocation.isNotEmpty ? _currentLocation : pickup;
    final useWaypoint = _currentLocation.isNotEmpty;

    setState(() {
      _calculatingRoute = true;
      _error = null;
      _deadheadMiles = null;
      _loadedMiles = null;
    });

    try {
      if (useWaypoint) {
        // One call with waypoint: current -> pickup -> delivery
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json'
          '?origin=${Uri.encodeComponent(origin)}'
          '&destination=${Uri.encodeComponent(delivery)}'
          '&waypoints=${Uri.encodeComponent(pickup)}'
          '&key=$googleMapsKey',
        );

        final response = await http.get(url);
        final data = json.decode(response.body);

        if (data['status'] != 'OK') {
          setState(() {
            _error = 'Google API error: ${data['status']}. Check your addresses.';
            _calculatingRoute = false;
          });
          return;
        }

        final legs = data['routes'][0]['legs'] as List;
        final deadheadMeters = legs[0]['distance']['value'] as int;
        final loadedMeters = legs[1]['distance']['value'] as int;

        setState(() {
          _deadheadMiles = deadheadMeters / 1609.34;
          _loadedMiles = loadedMeters / 1609.34;
          _calculatingRoute = false;
        });
      } else {
        // No GPS — pickup is both deadhead origin and loaded origin
        // Deadhead = 0, just compute loaded miles
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/directions/json'
          '?origin=${Uri.encodeComponent(pickup)}'
          '&destination=${Uri.encodeComponent(delivery)}'
          '&key=$googleMapsKey',
        );

        final response = await http.get(url);
        final data = json.decode(response.body);

        if (data['status'] != 'OK') {
          setState(() {
            _error = 'Google API error: ${data['status']}. Check your addresses.';
            _calculatingRoute = false;
          });
          return;
        }

        final legs = data['routes'][0]['legs'] as List;
        final loadedMeters = legs[0]['distance']['value'] as int;

        setState(() {
          _deadheadMiles = 0;
          _loadedMiles = loadedMeters / 1609.34;
          _calculatingRoute = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Route error: $e';
        _calculatingRoute = false;
      });
    }
  }

  @override
  void dispose() {
    _pickupCtrl.dispose();
    _deliveryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route a Load')),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // GPS
            const Text('Your Location',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _currentLocation.isNotEmpty
                          ? 'GPS: $_currentLocation'
                          : 'No location set — deadhead will be 0',
                      style: TextStyle(
                        fontSize: 14,
                        color: _currentLocation.isNotEmpty
                            ? Colors.green[700]
                            : Colors.grey[500],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _gettingLocation ? null : _getGpsLocation,
                  icon: _gettingLocation
                      ? const SizedBox(
                          height: 16, width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location, size: 18),
                  label: const Text('GPS'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Pickup
            const Text('Pickup',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _pickupCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'City, State or full address',
                prefixIcon: Icon(Icons.local_shipping),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Delivery
            const Text('Delivery',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _deliveryCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'City, State or full address',
                prefixIcon: Icon(Icons.flag),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),

            // Get Miles
            ElevatedButton(
              onPressed: _calculatingRoute ? null : _calculateRoute,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blueGrey[700],
                foregroundColor: Colors.white,
              ),
              child: _calculatingRoute
                  ? const SizedBox(
                      height: 20, width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Get Miles', style: TextStyle(fontSize: 18)),
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 14)),
            ],

            // Results
            if (_deadheadMiles != null && _loadedMiles != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.blueGrey[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _mileBox('Deadhead', _deadheadMiles!),
                        Container(width: 1, height: 40, color: Colors.grey[300]),
                        _mileBox('Loaded', _loadedMiles!),
                        Container(width: 1, height: 40, color: Colors.grey[300]),
                        _mileBox('Total', _deadheadMiles! + _loadedMiles!),
                      ],
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                           builder: (_) => CalculatorScreen(
                              initialDeadhead: _deadheadMiles!.roundToDouble(),
                              initialLoaded: _loadedMiles!.roundToDouble(),
                              initialOrigin: _pickupCtrl.text.trim(),
                              initialDestination: _deliveryCtrl.text.trim(),
                            ), 
                          ),
                        );
                      },
                      icon: const Icon(Icons.calculate),
                      label: const Text('Run the Numbers',
                          style: TextStyle(fontSize: 16)),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 24),
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mileBox(String label, double miles) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(
          '${miles.round()}',
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        Text('mi', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
      ],
    );
  }
}
