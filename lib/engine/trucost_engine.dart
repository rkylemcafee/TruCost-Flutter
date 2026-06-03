// trucost_engine.dart
//
// Pure-Dart port of TruCost (Owner Operators) v1.3 `TruCostSettings.compute()`.
// No Flutter dependencies — it's just math, so it can be unit-tested in
// isolation and reused by the manual calculator, the voice co-pilot, and the
// receipts/actuals comparison alike.
//
// Faithful to v1.3 to the penny, with ONE v2.0 addition: each unit (truck or
// trailer) can be OWNED (daily cost from depreciation on purchase price) or
// FINANCED (daily cost from the monthly payment). Both produce the same thing
// the old engine needed — a daily equipment burden — just two ways to get it.
//
// Suggested location in your project: lib/engine/trucost_engine.dart

/// How a unit's cost is carried.
enum CostMode { owned, financed }

/// One piece of equipment (truck or trailer) and how it costs money per day.
class UnitCost {
  final CostMode mode;

  /// Purchase price — used when [mode] is [CostMode.owned].
  final double purchasePrice;

  /// Monthly loan/lease payment — used when [mode] is [CostMode.financed].
  final double monthlyPayment;

  /// Annual depreciation rate (e.g. 0.20 = 20%/yr) — used when owned.
  final double depreciationRate;

  /// Working days per year the driver actually runs (e.g. 200).
  final double workingDaysPerYear;

  const UnitCost({
    required this.mode,
    this.purchasePrice = 0.0,
    this.monthlyPayment = 0.0,
    this.depreciationRate = 0.20,
    required this.workingDaysPerYear,
  });

  /// Convenience: an owned unit (matches v1.3's depreciation model exactly).
  factory UnitCost.owned({
    required double value,
    double depreciationRate = 0.20,
    required double workingDaysPerYear,
  }) =>
      UnitCost(
        mode: CostMode.owned,
        purchasePrice: value,
        depreciationRate: depreciationRate,
        workingDaysPerYear: workingDaysPerYear,
      );

  /// Convenience: a financed unit (the new v2.0 path).
  factory UnitCost.financed({
    required double monthlyPayment,
    required double workingDaysPerYear,
  }) =>
      UnitCost(
        mode: CostMode.financed,
        monthlyPayment: monthlyPayment,
        workingDaysPerYear: workingDaysPerYear,
      );

  /// The daily cost burden this unit contributes.
  double get dailyCost {
    final days = workingDaysPerYear <= 0 ? 1.0 : workingDaysPerYear;
    switch (mode) {
      case CostMode.owned:
        return (purchasePrice * depreciationRate) / days;
      case CostMode.financed:
        return (monthlyPayment * 12) / days;
    }
  }
}

/// Everything the engine needs for one load evaluation.
///
/// Mirrors the inputs `TruCostSettings.compute()` read in v1.3. Note that for
/// an owner-operator, "driver pay rate" and "target rate" are the same number
/// (what you want to earn IS what your labor costs), so this is a single
/// [hourlyRate] — exactly as v1.3 aliased driverHourlyRate to desiredHourlyRate.
class TruCostInputs {
  // Trip
  final double deadheadMiles;
  final double loadedMiles;
  final double tollsOtherCost;
  final double grossPay;

  // Speeds (mph)
  final double emptySpeed;
  final double loadedSpeed;

  // Fuel
  final double emptyMpg;
  final double loadedMpg;
  final double dieselPricePerGallon;

  // Labor — single rate for both pay and target (owner-operator)
  final double hourlyRate;

  // Time at shipper + consignee combined (hours)
  final double loadUnloadHours;

  // Equipment
  final UnitCost truck;
  final UnitCost trailer;

  // Percentages (0.25 = 25%)
  final double carrierCutPercent;
  final double overheadPercent;

  // Hours-of-service productive day (v1.3 constant = 11.0)
  final double productiveHoursPerDay;

  const TruCostInputs({
    required this.deadheadMiles,
    required this.loadedMiles,
    this.tollsOtherCost = 0.0,
    required this.grossPay,
    required this.emptySpeed,
    required this.loadedSpeed,
    required this.emptyMpg,
    required this.loadedMpg,
    required this.dieselPricePerGallon,
    required this.hourlyRate,
    required this.loadUnloadHours,
    required this.truck,
    required this.trailer,
    required this.carrierCutPercent,
    required this.overheadPercent,
    this.productiveHoursPerDay = 11.0,
  });

  /// Share the operator keeps after the carrier's cut.
  double get operatorSharePercent => 1.0 - carrierCutPercent;
}

/// The full breakdown of one load evaluation — port of v1.3's TripResult.
class TripResult {
  final double grossPay;
  final double carrierCut;
  final double operatorGross;

  final double emptyFuelCost;
  final double loadedFuelCost;
  final double totalFuelCost;

  final double driverCost;

  final double truckCost;
  final double trailerCost;
  final double equipmentCost;

  final double tollsCost;
  final double overheadCost;
  final double totalCosts;

  final double netToOperator;
  final double effectiveHourlyRate;
  final double costPerMile;

  final double totalMiles;
  final double deadheadMiles;
  final double loadedMiles;

  final double emptyDriveHours;
  final double loadedDriveHours;
  final double driveHours;
  final double loadUnloadHours;
  final double totalHours;

  final double offerPerMile;
  final double minimumGrossNeeded;
  final double minimumPerMile;
  final double targetHourly;

  const TripResult({
    required this.grossPay,
    required this.carrierCut,
    required this.operatorGross,
    required this.emptyFuelCost,
    required this.loadedFuelCost,
    required this.totalFuelCost,
    required this.driverCost,
    required this.truckCost,
    required this.trailerCost,
    required this.equipmentCost,
    required this.tollsCost,
    required this.overheadCost,
    required this.totalCosts,
    required this.netToOperator,
    required this.effectiveHourlyRate,
    required this.costPerMile,
    required this.totalMiles,
    required this.deadheadMiles,
    required this.loadedMiles,
    required this.emptyDriveHours,
    required this.loadedDriveHours,
    required this.driveHours,
    required this.loadUnloadHours,
    required this.totalHours,
    required this.offerPerMile,
    required this.minimumGrossNeeded,
    required this.minimumPerMile,
    required this.targetHourly,
  });

  /// True when the load clears the driver's target hourly rate.
  bool get isWinner => effectiveHourlyRate >= targetHourly;
}

/// The deterministic math engine. This is the soul of the app — and the part
/// the voice co-pilot must call as a TOOL rather than ever computing itself.
class TruCostEngine {
  static TripResult compute(TruCostInputs i) {
    final deadhead = i.deadheadMiles < 0 ? 0.0 : i.deadheadMiles;
    final loaded = i.loadedMiles < 0 ? 0.0 : i.loadedMiles;
    final totalMiles = deadhead + loaded;

    // --- Time ---
    final emptyDriveHours = deadhead / (i.emptySpeed < 1.0 ? 1.0 : i.emptySpeed);
    final loadedDriveHours = loaded / (i.loadedSpeed < 1.0 ? 1.0 : i.loadedSpeed);
    final driveHours = emptyDriveHours + loadedDriveHours;
    final loadUnload = i.loadUnloadHours < 0 ? 0.0 : i.loadUnloadHours;
    final totalHours = driveHours + loadUnload;

    // --- Fuel ---
    final emptyGallons = deadhead / (i.emptyMpg < 0.1 ? 0.1 : i.emptyMpg);
    final loadedGallons = loaded / (i.loadedMpg < 0.1 ? 0.1 : i.loadedMpg);
    final emptyFuelCost = emptyGallons * i.dieselPricePerGallon;
    final loadedFuelCost = loadedGallons * i.dieselPricePerGallon;
    final totalFuelCost = emptyFuelCost + loadedFuelCost;

    // --- Driver pay (ALL hours — drive + load/unload) ---
    final driverCost = totalHours * i.hourlyRate;

    // --- Equipment (fractional trip-days) ---
    final tripDays = totalHours / i.productiveHoursPerDay;
    final truckCost = tripDays * i.truck.dailyCost;
    final trailerCost = tripDays * i.trailer.dailyCost;
    final equipmentCost = truckCost + trailerCost;

    // --- Tolls / other ---
    final tollsCost = i.tollsOtherCost < 0 ? 0.0 : i.tollsOtherCost;

    // --- Base costs, then overhead on top ---
    final baseCosts = totalFuelCost + driverCost + equipmentCost + tollsCost;
    final overheadCost = baseCosts * (i.overheadPercent < 0 ? 0.0 : i.overheadPercent);
    final totalCosts = baseCosts + overheadCost;

    // --- Revenue flow ---
    final operatorShare = i.operatorSharePercent;
    final operatorGross = i.grossPay * operatorShare;
    final netToOperator = operatorGross - totalCosts;
    final effectiveHourlyRate = totalHours > 0 ? netToOperator / totalHours : 0.0;
    final costPerMile = totalMiles > 0 ? totalCosts / totalMiles : 0.0;

    // --- Minimum gross needed to cover costs AND hit the target hourly ---
    final targetEarnings = i.hourlyRate * totalHours;
    final minimumNetNeeded = totalCosts + targetEarnings;
    final minimumGrossNeeded =
        operatorShare > 0 ? minimumNetNeeded / operatorShare : minimumNetNeeded;
    final minimumPerMile = totalMiles > 0 ? minimumGrossNeeded / totalMiles : 0.0;

    return TripResult(
      grossPay: i.grossPay,
      carrierCut: i.grossPay * i.carrierCutPercent,
      operatorGross: operatorGross,
      emptyFuelCost: emptyFuelCost,
      loadedFuelCost: loadedFuelCost,
      totalFuelCost: totalFuelCost,
      driverCost: driverCost,
      truckCost: truckCost,
      trailerCost: trailerCost,
      equipmentCost: equipmentCost,
      tollsCost: tollsCost,
      overheadCost: overheadCost,
      totalCosts: totalCosts,
      netToOperator: netToOperator,
      effectiveHourlyRate: effectiveHourlyRate,
      costPerMile: costPerMile,
      totalMiles: totalMiles,
      deadheadMiles: deadhead,
      loadedMiles: loaded,
      emptyDriveHours: emptyDriveHours,
      loadedDriveHours: loadedDriveHours,
      driveHours: driveHours,
      loadUnloadHours: loadUnload,
      totalHours: totalHours,
      offerPerMile: totalMiles > 0 ? i.grossPay / totalMiles : 0.0,
      minimumGrossNeeded: minimumGrossNeeded,
      minimumPerMile: minimumPerMile,
      targetHourly: i.hourlyRate,
    );
  }
}
