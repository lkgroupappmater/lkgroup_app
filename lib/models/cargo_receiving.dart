// lib/models/cargo_receiving.dart

enum CargoReceivingStatus {
  received,
  inspecting,
  stored,
  readyToShip,
  shipped,
  returned,
}

class CargoReceiving {
  final String receiptNo;
  final String invoiceNo;
  final String consigneeName;
  final String contact;
  final CargoReceivingStatus status;
  final String receivedDate;
  final String storageLocation;
  final String shipmentNo;

  const CargoReceiving({
    required this.receiptNo,
    required this.invoiceNo,
    required this.consigneeName,
    required this.contact,
    required this.status,
    required this.receivedDate,
    required this.storageLocation,
    required this.shipmentNo,
  });

  String get statusLabel {
    switch (status) {
      case CargoReceivingStatus.received:
        return '입고 완료';
      case CargoReceivingStatus.inspecting:
        return '검수 중';
      case CargoReceivingStatus.stored:
        return '보관 중';
      case CargoReceivingStatus.readyToShip:
        return '출고 대기';
      case CargoReceivingStatus.shipped:
        return '출고 완료';
      case CargoReceivingStatus.returned:
        return '반송';
    }
  }
}
