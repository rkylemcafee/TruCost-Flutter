// trucost_engine.dart
//
// Pure-Dart TruCost engine. v2.0 model: equipment cost is spread over the
// operation's ANNUAL WORKING HOURS.
//
//   equipment cost for this trip
//     = annual cost (depreciation OR payments) x (trip hours / annual hours)
//
// Suggested location: lib/engine/trucost_engine.dart

/// How a unit's cost is carried.
enum CostMode { owned, financed }

/// One piece of equipment (truck or trailer) and what it costs per year.
class UnitCost {
  final CostMode mode;
  final double purchasePrice;
  final double monthlyPayment;
  final double depreciationRate;

  const UnitCost({
    required this.mode,
    this.purchasePrice = 0.0,
    this.monthlyPayment = 0.0,
    this.depreciationRate = 0.20,
  });

  factory UnitCost.owned({
    required double value,
    double depreciationRate = 0.20,
  }) =>
      UnitCost(
        mode: CostMode.owned,
        purchasePrice: value,
        depreciationRate: depreciationRate,
      );

  factory UnitCost.financed({required double monthlyPayment}) =>
      UnitCost(mode: CostMode.financed, monthlyPayment: monthlyPayment);

  double get annualCost {
    switch (mode) {
      case CostMode.owned:
        return purchasePrice * depreciationRate;
      case CostMode.financed:
        return monthlyPayment * 12;
    }
  }
}

/// Everything the engine needs for one load evaluation.
class TruCostInputs {
  final double deadheadMiles;
  final double loadedMiles;
  final double tollsOtherCost;
  final double grossPay;
  final double emptySpeed;
  final double loadedSpeed;
  final double emptyMpg;
  final double loadedMpg;
  final double dieselPricePerGallon;
  final double hourlyRate;
  final double loadUnloadHours;
  final UnitCost truck;
  final UnitCost trailer;
  final double carrierCutPercent;
  final double overheadPercent;
  final double annualWorkingHours;

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
    this.annualWorkingHours = 2500,
  });

  double get operatorSharePercent => 1.0 - carrierCutPercent;
}

/// The full breakdown of one load evaluation.
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

  bool get isWinner => effectiveHourlyRate >= targetHourly;
}

/// The deterministic math engine.
class TruCostEngine {
  static TripResult compute(TruCostInputs i) {
    final deadhead = i.deadheadMiles < 0 ? 0.0 : i.deadheadMiles;
    final loaded = i.loadedMiles < 0 ? 0.0 : i.loadedMiles;
    final totalMiles = deadhead + loaded;

    // Time
    final emptyDriveHours = deadhead / (i.emptySpeed < 1.0 ? 1.0 : i.emptySpeed);
    final loadedDriveHours = loaded / (i.loadedSpeed < 1.0 ? 1.0 : i.loadedSpeed);
    final driveHours = emptyDriveHours + loadedDriveHours;
    final loadUnload = i.loadUnloadHours < 0 ? 0.0 : i.loadUnloadHours;
    final totalHours = driveHours + loadUnload;

    // Fuel
    final emptyGallons = deadhead / (i.emptyMpg < 0.1 ? 0.1 : i.emptyMpg);
    final loadedGallons = loaded / (i.loadedMpg < 0.1 ? 0.1 : i.loadedMpg);
    final emptyFuelCost = emptyGallons * i.dieselPricePerGallon;
    final loadedFuelCost = loadedGallons * i.dieselPricePerGallon;
    final totalFuelCost = emptyFuelCost + loadedFuelCost;

    // Driver pay
    final driverCost = totalHours * i.hourlyRate;

    // Equipment: trip's share of annual hours
    final annualHours = i.annualWorkingHours <= 0 ? 1.0 : i.annualWorkingHours;
    final hoursFraction = totalHours / annualHours;
    final truckCost = i.truck.annualCost * hoursFraction;
    final trailerCost = i.trailer.annualCost * hoursFraction;
    final equipmentCost = truckCost + trailerCost;

    // Tolls
    final tollsCost = i.tollsOtherCost < 0 ? 0.0 : i.tollsOtherCost;

    // Costs
    final baseCosts = totalFuelCost + driverCost + equipmentCost + tollsCost;
    final overheadCost = baseCosts * (i.overheadPercent < 0 ? 0.0 : i.overheadPercent);
    final totalCosts = baseCosts + overheadCost;

    // Revenue
    final operatorShare = i.operatorSharePercent;
    final operatorGross = i.grossPay * operatorShare;
    final netToOperator = operatorGross - totalCosts;
    final effectiveHourlyRate = totalHours > 0 ? netToOperator / totalHours : 0.0;
    final costPerMile = totalMiles > 0 ? totalCosts / totalMiles : 0.0;

    // Minimum gross to hit target hourly
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
