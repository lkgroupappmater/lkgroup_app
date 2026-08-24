// lib/models/shipping_schedule.dart

enum TransportMode { sea, air, land, rail }

enum ShipmentStatus {
  inTransit,
  scheduled,
  atPort,
  customs,
  delivered,
  delayed,
}

class ShippingSchedule {
  final String id;
  final String routeName;
  final TransportMode transportMode;
  final String origin;
  final String destination;
  final String departureDate;
  final String arrivalDate;
  final ShipmentStatus status;
  final String referenceNo;

  const ShippingSchedule({
    required this.id,
    required this.routeName,
    required this.transportMode,
    required this.origin,
    required this.destination,
    required this.departureDate,
    required this.arrivalDate,
    required this.status,
    required this.referenceNo,
  });

  String get modeLabel {
    switch (transportMode) {
      case TransportMode.sea:
        return '해운';
      case TransportMode.air:
        return '항공';
      case TransportMode.land:
        return '육운';
      case TransportMode.rail:
        return '철도';
    }
  }

  String get statusLabel {
    switch (status) {
      case ShipmentStatus.inTransit:
        return '운송 중';
      case ShipmentStatus.scheduled:
        return '예정';
      case ShipmentStatus.atPort:
        return '항구 대기';
      case ShipmentStatus.customs:
        return '통관 중';
      case ShipmentStatus.delivered:
        return '배송 완료';
      case ShipmentStatus.delayed:
        return '지연';
    }
  }
}
