import 'package:supabase_flutter/supabase_flutter.dart';

const Map<String, String> _stateToPadd = {
  'CT':'R1X','ME':'R1X','MA':'R1X','NH':'R1X','RI':'R1X','VT':'R1X',
  'DE':'R1Y','DC':'R1Y','MD':'R1Y','NJ':'R1Y','NY':'R1Y','PA':'R1Y',
  'FL':'R1Z','GA':'R1Z','NC':'R1Z','SC':'R1Z','VA':'R1Z','WV':'R1Z',
  'IL':'R20','IN':'R20','IA':'R20','KS':'R20','KY':'R20','MI':'R20',
  'MN':'R20','MO':'R20','NE':'R20','ND':'R20','OH':'R20','OK':'R20',
  'SD':'R20','TN':'R20','WI':'R20',
  'AL':'R30','AR':'R30','LA':'R30','MS':'R30','NM':'R30','TX':'R30',
  'CO':'R40','ID':'R40','MT':'R40','UT':'R40','WY':'R40',
  'AK':'R50','AZ':'R50','HI':'R50','NV':'R50','OR':'R50','WA':'R50',
  'CA':'R5XCA',
};

const Map<String, String> _paddFallback = {
  'R1X':'R10','R1Y':'R10','R1Z':'R10','R5XCA':'R50',
};

class FuelPriceService {
  final _supabase = Supabase.instance.client;
  Map<String, double> _regionPrices = {};
  double _nationalAvg = 0;
  bool _loaded = false;

  Future<void> loadPrices() async {
    if (_loaded) return;
    try {
      final rows = await _supabase
          .from('fuel_cache_regions')
          .select('region_code, price')
          .eq('cache_id', 'eia-diesel-weekly')
          .order('fetched_at', ascending: false);
      final Map<String, double> prices = {};
      for (final r in rows) {
        final code = r['region_code']?.toString() ?? '';
        final price = double.tryParse(r['price']?.toString() ?? '') ?? 0;
        if (code.isNotEmpty && !prices.containsKey(code)) prices[code] = price;
      }
      _regionPrices = prices;
      _nationalAvg = prices['NUS'] ?? 5.35;
      _loaded = true;
    } catch (e) {
      _nationalAvg = 5.35;
      _loaded = true;
    }
  }

  double priceForState(String stateAbbr) {
    final region = _stateToPadd[stateAbbr.toUpperCase()];
    if (region != null && _regionPrices.containsKey(region)) return _regionPrices[region]!;
    if (region != null) {
      final parent = _paddFallback[region];
      if (parent != null && _regionPrices.containsKey(parent)) return _regionPrices[parent]!;
    }
    return _nationalAvg;
  }

  double get nationalAverage => _nationalAvg;

  static String? extractState(String address) {
    final re = RegExp(r',\s*([A-Za-z]{2})\b');
    final match = re.firstMatch(address);
    if (match != null) return match.group(1)!.toUpperCase();
    final words = address.trim().split(RegExp(r'\s+'));
    if (words.isNotEmpty && words.last.length == 2) return words.last.toUpperCase();
    return null;
  }

  double averageForRoute({required String pickupAddress, required String deliveryAddress, required double deadheadMiles, required double loadedMiles}) {
    final pickupState = extractState(pickupAddress);
    final deliveryState = extractState(deliveryAddress);

    final pickupRegion = pickupState != null ? _stateToPadd[pickupState.toUpperCase()] : null;
    final deliveryRegion = deliveryState != null ? _stateToPadd[deliveryState.toUpperCase()] : null;

    if (pickupRegion != null && pickupRegion == deliveryRegion) {
      return priceForState(pickupState!);
    }

    final pickupParent = pickupRegion != null ? (_paddFallback[pickupRegion] ?? pickupRegion) : null;
    final deliveryParent = deliveryRegion != null ? (_paddFallback[deliveryRegion] ?? deliveryRegion) : null;
    if (pickupParent != null && pickupParent == deliveryParent) {
      final p1 = pickupState != null ? priceForState(pickupState) : _nationalAvg;
      final p2 = deliveryState != null ? priceForState(deliveryState) : _nationalAvg;
      return (p1 + p2) / 2;
    }

    return _nationalAvg;
  }
}