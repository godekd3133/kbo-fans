enum TicketSource { official, inferred }

class TicketInfo {
  final String vendorKey;
  final String vendorName;
  final String? vendorUrl;
  final DateTime? openAt;
  final TicketSource source;
  final String? note;

  const TicketInfo({
    required this.vendorKey,
    required this.vendorName,
    this.vendorUrl,
    this.openAt,
    this.source = TicketSource.inferred,
    this.note,
  });

  bool get isInferred => source == TicketSource.inferred;
}
