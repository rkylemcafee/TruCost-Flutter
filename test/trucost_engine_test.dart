// trucost_engine_test.dart
//
// Tests for the ported TruCost engine. Two kinds of checks:
//
//   1. ANCHOR VALUES   — a known load run against the v1.3 default settings,
//                        with the dollar/hour results I hand-calculated from
//                        the same formulas. These confirm the Dart math lands
//                        where it should.
//   2. CONSISTENCY     — relationships that must ALWAYS hold (totals equal the
//                        sum of their parts, etc.). These are exact and catch
//                        any structural mistake.
//
// THE REAL PARITY CHECK is still on you: punch these same inputs into the
// Swift v1.3 app and confirm identical numbers. The Dart tests prove the
// engine is internally correct; the Swift cross-check proves it matches v1.3.
//
// Suggested location: test/trucost_engine_test.dart
// Run with:  flutter test

import 'package:flutter_test/flutter_test.dart';
import 'package:trucost_flutter/engine/trucost_engine.dart';

/// Builds inputs using the v1.3 factory defaults, owned truck + trailer.
TruCostInputs defaultInputs({
  required double deadhead,
  required double loaded,
  required double gross,
  double tolls = 0.0,
}) {
  return TruCostInputs(
    deadheadMiles: deadhead,
    loadedMiles: loaded,
    grossPay: gross,
    tollsOtherCost: tolls,
    emptySpeed: 60.0,
    loadedSpeed: 55.0,
    emptyMpg: 8.0,
    loadedMpg: 6.0,
    dieselPricePerGallon: 4.00,
    hourlyRate: 50.0,
    loadUnloadHours: 8.0, // 4 load + 4 unload
    truck: UnitCost.owned(value: 150000, workingDaysPerYear: 200),
    trailer: UnitCost.owned(value: 39000, workingDaysPerYear: 200),
    carrierCutPercent: 0.25,
    overheadPercent: 0.15,
  );
}

void main() {
  group('Anchor values — 100 deadhead, 500 loaded, \$3000 gross, defaults', () {
    final r = TruCostEngine.compute(
      defaultInputs(deadhead: 100, loaded: 500, gross: 3000),
    );

    test('hours', () {
      expect(r.totalHours, closeTo(18.7576, 0.01));
    });
    test('fuel', () {
      expect(r.totalFuelCost, closeTo(383.33, 0.05));
    });
    test('driver pay', () {
      expect(r.driverCost, closeTo(937.88, 0.05));
    });
    test('equipment', () {
      expect(r.equipmentCost, closeTo(322.29, 0.05));
    });
    test('total trip cost', () {
      expect(r.totalCosts, closeTo(1890.03, 0.1));
    });
    test('net to operator', () {
      expect(r.netToOperator, closeTo(359.97, 0.1));
    });
    test('effective hourly rate (~\$19/hr — a pass)', () {
      expect(r.effectiveHourlyRate, closeTo(19.19, 0.05));
    });
    test('cost per mile', () {
      expect(r.costPerMile, closeTo(3.150, 0.01));
    });
    test('minimum gross needed to hit \$50/hr', () {
      expect(r.minimumGrossNeeded, closeTo(3770.54, 0.2));
    });
    test('this load is NOT a winner at \$3000', () {
      expect(r.isWinner, isFalse);
    });
  });

  group('Internal consistency (must always hold)', () {
    final r = TruCostEngine.compute(
      defaultInputs(deadhead: 137, loaded: 642, gross: 4250, tolls: 38.50),
    );

    test('total miles = deadhead + loaded', () {
      expect(r.totalMiles, closeTo(r.deadheadMiles + r.loadedMiles, 1e-9));
    });
    test('carrier cut + operator gross = gross pay', () {
      expect(r.carrierCut + r.operatorGross, closeTo(r.grossPay, 1e-9));
    });
    test('total fuel = empty + loaded fuel', () {
      expect(r.totalFuelCost, closeTo(r.emptyFuelCost + r.loadedFuelCost, 1e-9));
    });
    test('equipment cost = truck + trailer', () {
      expect(r.equipmentCost, closeTo(r.truckCost + r.trailerCost, 1e-9));
    });
    test('net to operator = operator gross - total costs', () {
      expect(r.netToOperator, closeTo(r.operatorGross - r.totalCosts, 1e-9));
    });
    test('effective hourly = net / total hours', () {
      expect(r.effectiveHourlyRate, closeTo(r.netToOperator / r.totalHours, 1e-9));
    });
    test('offer per mile = gross / total miles', () {
      expect(r.offerPerMile, closeTo(r.grossPay / r.totalMiles, 1e-9));
    });
  });

  group('Cost modes — owned vs financed', () {
    test('owned: (value * rate) / workingDays', () {
      final truck =
          UnitCost.owned(value: 150000, depreciationRate: 0.20, workingDaysPerYear: 200);
      expect(truck.dailyCost, closeTo(150.0, 1e-9)); // 30000 / 200
    });

    test('financed: (monthlyPayment * 12) / workingDays', () {
      final truck =
          UnitCost.financed(monthlyPayment: 2400, workingDaysPerYear: 200);
      expect(truck.dailyCost, closeTo(144.0, 1e-9)); // 28800 / 200
    });

test('financed equipment cost is computed from the monthly payment', () {
      final financed = TruCostInputs(
        deadheadMiles: 100, loadedMiles: 500, grossPay: 3000,
        emptySpeed: 60, loadedSpeed: 55, emptyMpg: 8, loadedMpg: 6,
        dieselPricePerGallon: 4.00, hourlyRate: 50, loadUnloadHours: 8,
        truck: UnitCost.financed(monthlyPayment: 2400, workingDaysPerYear: 200),
        trailer: UnitCost.financed(monthlyPayment: 700, workingDaysPerYear: 200),
        carrierCutPercent: 0.25, overheadPercent: 0.15,
      );
      // truck $144/day + trailer $42/day = $186/day over ~1.705 trip-days
      expect(TruCostEngine.compute(financed).equipmentCost, closeTo(317.17, 0.05));
    });

    test('a high monthly payment DOES cost more than owning outright', () {
      final owned = defaultInputs(deadhead: 100, loaded: 500, gross: 3000);
      final pricey = TruCostInputs(
        deadheadMiles: 100, loadedMiles: 500, grossPay: 3000,
        emptySpeed: 60, loadedSpeed: 55, emptyMpg: 8, loadedMpg: 6,
        dieselPricePerGallon: 4.00, hourlyRate: 50, loadUnloadHours: 8,
        truck: UnitCost.financed(monthlyPayment: 3500, workingDaysPerYear: 200),
        trailer: UnitCost.financed(monthlyPayment: 900, workingDaysPerYear: 200),
        carrierCutPercent: 0.25, overheadPercent: 0.15,
      );
      expect(
        TruCostEngine.compute(pricey).equipmentCost,
        greaterThan(TruCostEngine.compute(owned).equipmentCost),
      );
    });
  });

  group('Winner logic and edge cases', () {
    test('a fat \$8000 gross clears the \$50/hr target', () {
      final r = TruCostEngine.compute(
        defaultInputs(deadhead: 100, loaded: 500, gross: 8000),
      );
      expect(r.isWinner, isTrue);
    });

    test('zero miles does not divide by zero or produce NaN', () {
      final r = TruCostEngine.compute(
        defaultInputs(deadhead: 0, loaded: 0, gross: 0),
      );
      expect(r.totalMiles, 0.0);
      expect(r.costPerMile, 0.0);
      expect(r.offerPerMile, 0.0);
      expect(r.effectiveHourlyRate.isNaN, isFalse);
      expect(r.effectiveHourlyRate.isFinite, isTrue);
    });
  });
}
