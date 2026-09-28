import '../models/debt_model.dart';

List<DebtEntry> filterActiveUdharEntries(
  Iterable<DebtEntry> entries, {
  String query = '',
  String direction = 'all',
}) {
  final name = query.trim().toLowerCase();
  return entries.where((entry) =>
      entry.deletedAt == null &&
      entry.settledAt == null &&
      (direction == 'all' || entry.type == direction) &&
      (name.isEmpty || entry.borrowerName.toLowerCase().contains(name)))
      .toList(growable: false);
}
