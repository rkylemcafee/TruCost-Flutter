// defaults.dart
//
// Starting values pre-filled during onboarding. All overridable by the user.
//
// Suggested location: lib/engine/defaults.dart

import 'trucost_engine.dart';

class TruCostDefaults {
  static const double truckValue = 140000.0;
  static const double trailerValue = 40000.0;
  static const double depreciationRate = 0.20;
  static const double annualWorkingHours = 2500.0;
  static const double dieselPricePerGallon = 4.00;
  static const double emptyMpg = 8.0;
  static const double loadedMpg = 6.0;
  static const double emptySpeed = 60.0;
  static const double loadedSpeed = 55.0;
  static const double hourlyRate = 50.0;
  static const double carrierCutPercent = 0.25;
  static const double overheadPercent = 0.15;
  static const double loadHours = 4.0;
  static const double unloadHours = 4.0;

  static UnitCost get defaultTruck =>
      UnitCost.owned(value: truckValue, depreciationRate: depreciationRate);

  static UnitCost get defaultTrailer =>
      UnitCost.owned(value: trailerValue, depreciationRate: depreciationRate);
}
