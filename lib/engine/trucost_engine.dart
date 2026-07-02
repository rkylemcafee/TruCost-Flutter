// trucost_engine.dart
//
// Pure-Dart TruCost engine.
//
// THE MODEL (the "ugly truth"):
//   Real costs come out of the load — nothing is pretended away:
//     fuel + equipment (the truck/trailer nut) + tolls + overhead
//   Equipment cost is the iron's annual cost spread over the operator's
//   ANNUAL WORKING HOURS, then charged for this trip's hours:
//     equipment for trip = annual cost (depreciation OR payments)
//                          x (trip hours / annual hours)
//   What's LEFT after carrier cut and all real costs is the operator's
//   take-home. Divide by hours and that's the real $/hr.
//
//   The operator's hourly rate is the TARGET BAR they set in onboarding,
//   NOT a wage we subtract. A load "wins" when real $/hr clears that bar.
//   The bar is always the operator's own number — never hard-coded.
//
// Suggested location: lib/engine/trucost_engine.dart

/// How a unit's cost is carried.
enum CostMode { owned, financed }

/// One piece of equipment (truck or trailer) and what it costs per year.
class UnitCost {
  final CostMode mode;
  final double purchasePrice;
  final double residualValue; // what the iron is still worth at the end
  final double monthlyPayment;
  final double depreciationRate;

  const UnitCost({
    required this.mode,
    this.purchasePrice = 0.0,
    this.residualValue = 0.0,
    this.monthlyPayment = 0.0,
    this.depreciationRate = 0.20,
  });

  factory UnitCost.owned({
    required double value,
    double residualValue = 0.0,
    double depreciationRate = 0.20,
  }) =>
      UnitCost(
        mode: CostMode.owned,
        purchasePrice: value,
        residualValue: residualValue,
        depreciationRate: depreciationRate,
      );

  factory UnitCost.financed({required double monthlyPayment}) =>
      UnitCost(mode: CostMode.financed, monthlyPayment: monthlyPayment);

  double get annualCost {
    switch (mode) {
      case CostMode.owned:
        // Only the value the truck actually LOSES is depreciated — purchase
        // price down to its residual (resale/salvage) value, never to zero.
        final depreciable = purchasePrice - residualValue;
        final base = depreciable < 0 ? 0.0 : depreciable;
        return base * depreciationRate;
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
  final double hourlyRate; // operator's TARGET $/hr (the bar), not a wage
  final double loadUnloadHours;
  final UnitCost truck;
  final UnitCost trailer;
  final double carrierCutPercent;
  final double overheadPercent;
  final double annualWorkingHours;
  final bool hasSleeper;       // truck has a sleeper berth → no hotel cost
  final double hotelRate;      // nightly hotel rate for non-sleeper operators

  // Fuel surcharge. FSC is a slice of the gross the carrier does NOT take a cut
  // of — it's passed through to the operator. fscPercent is that slice as a
  // fraction of gross (default 6%). fscPercentReceived is how much of the FSC
  // the operator actually keeps (default 100%). For independents (carrier cut
  // 0) these have no effect; they only matter when a carrier takes a cut.
  final double fscPercent;
  final double fscPercentReceived;

  // Carrier insurance taken as a % of gross (default 3%). Like FSC it comes off
  // the top before the carrier-cut split, but the operator keeps NONE of it —
  // the carrier keeps it. Only applies when leased (carrier cut > 0).
  final double insurancePercent;

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
    this.hasSleeper = true,
    this.hotelRate = 0.0,
    this.fscPercent = 0.06,
    this.fscPercentReceived = 1.0,
    this.insurancePercent = 0.03,
  });

  double get operatorSharePercent => 1.0 - carrierCutPercent;
}

/// The full breakdown of one load evaluation.
class TripResult {
  final double grossPay;
  final double carrierCut;
  final double insuranceAmount; // carrier insurance taken off the top
  final double fscAmount;       // fuel surcharge the operator keeps
  final double operatorGross;
  final double emptyFuelCost;
  final double loadedFuelCost;
  final double totalFuelCost;
  final double truckCost;
  final double trailerCost;
  final double equipmentCost;
  final double tollsCost;
  final double hotelCost;
  final double hotelNights;
  final double overheadCost;
  final double totalCosts;
  final double netToOperator; // operator take-home after all real costs
  final double effectiveHourlyRate; // real take-home per hour
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
  final double targetHourly; // the operator's own bar

  const TripResult({
    required this.grossPay,
    required this.carrierCut,
    this.insuranceAmount = 0.0,
    this.fscAmount = 0.0,
    required this.operatorGross,
    required this.emptyFuelCost,
    required this.loadedFuelCost,
    required this.totalFuelCost,
    required this.truckCost,
    required this.trailerCost,
    required this.equipmentCost,
    required this.tollsCost,
    required this.hotelCost,
    required this.hotelNights,
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

  /// A winner clears the operator's own hourly bar.
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

    // Equipment: the iron's annual nut, this trip's share of annual hours
    final annualHours = i.annualWorkingHours <= 0 ? 1.0 : i.annualWorkingHours;
    final hoursFraction = totalHours / annualHours;
    final truckCost = i.truck.annualCost * hoursFraction;
    final trailerCost = i.trailer.annualCost * hoursFraction;
    final equipmentCost = truckCost + trailerCost;

    // Tolls
    final tollsCost = i.tollsOtherCost < 0 ? 0.0 : i.tollsOtherCost;

    // Hotels — only for non-sleeper trucks. Count the days on the road
    // (~11 legal driving hours = one day, rounded up) and bill nights as
    // task-days minus 1: you sleep away every night except the last, when
    // you finish the run. Matches the enterprise per-diem/hotel logic.
    double hotelNights = 0.0;
    double hotelCost = 0.0;
    if (!i.hasSleeper && i.hotelRate > 0 && totalHours > 0) {
      final taskDays = (totalHours / 11.0).ceilToDouble();
      hotelNights = taskDays > 1 ? taskDays - 1 : 0.0;
      hotelCost = hotelNights * i.hotelRate;
    }

    // Costs — fuel + equipment + tolls + hotels, then overhead on top.
    // The operator's own driving time is NOT a cost here; it's what the
    // take-home pays for. The hourly target is a bar, applied below.
    final baseCosts = totalFuelCost + equipmentCost + tollsCost + hotelCost;
    final overheadCost = baseCosts * (i.overheadPercent < 0 ? 0.0 : i.overheadPercent);
    final totalCosts = baseCosts + overheadCost;

    // Revenue → take-home
    // Fuel surcharge is passed through: the carrier's cut applies only to the
    // line-haul portion of the gross (gross minus FSC), and the operator keeps
    // their share of the FSC on top. So the operator's effective share of the
    // gross is higher than the raw (1 - carrier cut) whenever FSC > 0.
    //   line haul   = gross x (1 - fscPercent)
    //   FSC kept    = gross x fscPercent x fscPercentReceived
    //   operator    = line haul x (1 - carrierCut) + FSC kept
    final operatorShare = i.operatorSharePercent; // 1 - carrier cut
    final fscPct = i.fscPercent < 0 ? 0.0 : i.fscPercent;
    final fscKeptPct = i.fscPercentReceived < 0 ? 0.0 : i.fscPercentReceived;
    final insPct = i.carrierCutPercent <= 0
        ? 0.0
        : (i.insurancePercent < 0 ? 0.0 : i.insurancePercent);

    // Settlement waterfall. Both the carrier insurance and the FSC are taken as
    // a % of the ORIGINAL gross; what's left is the line haul, and the carrier
    // cut hits that. The operator keeps their share of the line haul plus their
    // kept share of the FSC. FSC/insurance only bite when leased (cut > 0).
    //   insurance   = gross x insPct                 (carrier keeps)
    //   fsc (raw)   = gross x fscPct
    //   fsc kept    = fsc x fscPercentReceived        (operator keeps)
    //   line haul   = gross - insurance - fsc(raw)    (= gross x (1 - ins - fsc))
    //   carrier cut = line haul x carrierCut          (carrier keeps)
    //   operator    = line haul x (1 - cut) + fsc kept
    final insuranceAmount = i.grossPay * insPct;
    final fscRaw = i.grossPay * fscPct;
    final fscAmount = fscRaw * fscKeptPct; // FSC the operator keeps
    var lineHaul = i.grossPay - insuranceAmount - fscRaw;
    if (lineHaul < 0) lineHaul = 0.0;
    final carrierCutAmount = lineHaul * i.carrierCutPercent;
    final operatorGross = lineHaul * operatorShare + fscAmount;
    // Effective share MUST be a pure ratio (independent of grossPay) — the quote
    // screen computes the floor at grossPay = 0, so dividing operatorGross by
    // grossPay would collapse to operatorShare and under-price the load.
    var lineHaulFrac = 1.0 - insPct - fscPct;
    if (lineHaulFrac < 0) lineHaulFrac = 0.0;
    final effectiveShare = lineHaulFrac * operatorShare + fscPct * fscKeptPct;
    final netToOperator = operatorGross - totalCosts;
    final effectiveHourlyRate = totalHours > 0 ? netToOperator / totalHours : 0.0;
    final costPerMile = totalMiles > 0 ? totalCosts / totalMiles : 0.0;

    // Minimum gross to clear the operator's hourly bar as take-home
    final targetEarnings = i.hourlyRate * totalHours;
    final minimumNetNeeded = totalCosts + targetEarnings;
    final minimumGrossNeeded =
        effectiveShare > 0 ? minimumNetNeeded / effectiveShare : minimumNetNeeded;
    final minimumPerMile = totalMiles > 0 ? minimumGrossNeeded / totalMiles : 0.0;

    return TripResult(
      grossPay: i.grossPay,
      carrierCut: carrierCutAmount,
      insuranceAmount: insuranceAmount,
      fscAmount: fscAmount,
      operatorGross: operatorGross,
      emptyFuelCost: emptyFuelCost,
      loadedFuelCost: loadedFuelCost,
      totalFuelCost: totalFuelCost,
      truckCost: truckCost,
      trailerCost: trailerCost,
      equipmentCost: equipmentCost,
      tollsCost: tollsCost,
      hotelCost: hotelCost,
      hotelNights: hotelNights,
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
