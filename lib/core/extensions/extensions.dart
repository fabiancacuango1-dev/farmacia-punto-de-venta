import 'package:intl/intl.dart';

extension DateTimeX on DateTime {
  String get formatted => DateFormat('dd/MM/yyyy').format(this);
  String get formattedWithTime => DateFormat('dd/MM/yyyy HH:mm').format(this);
  String get isoDate => DateFormat('yyyy-MM-dd').format(this);
  String get timeOnly => DateFormat('HH:mm:ss').format(this);

  bool get isExpired => isBefore(DateTime.now());

  bool isExpiringWithin(int days) {
    return isBefore(DateTime.now().add(Duration(days: days)));
  }

  DateTime get startOfDay => DateTime(year, month, day);
  DateTime get endOfDay => DateTime(year, month, day, 23, 59, 59);
}

extension DoubleX on double {
  String get currency => NumberFormat.currency(
        symbol: r'$',
        decimalDigits: 2,
      ).format(this);

  String get percentage => '${toStringAsFixed(1)}%';

  double get roundTo2 => double.parse(toStringAsFixed(2));
}

extension StringX on String {
  String get capitalize =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  bool get isValidEmail => RegExp(r'^[\w\-.]+@([\w\-]+\.)+[\w\-]{2,4}$').hasMatch(this);

  bool get isValidRuc => length == 13 && RegExp(r'^\d{13}$').hasMatch(this);

  bool get isValidCedula => length == 10 && RegExp(r'^\d{10}$').hasMatch(this);
}

extension ListX<T> on List<T> {
  List<T> safeSublist(int start, [int? end]) {
    if (start >= length) return [];
    return sublist(start, end != null && end > length ? length : end);
  }
}
