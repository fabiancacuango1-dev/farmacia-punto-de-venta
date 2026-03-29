// App-wide constants
class AppConstants {
  AppConstants._();

  static const String appName = 'FarmaPos';
  static const String appVersion = '1.0.0';
  static const String dbName = 'farmapos.db';

  // SRI Ecuador
  static const String sriEnvironmentTest = '1';
  static const String sriEnvironmentProd = '2';
  static const String sriTaxRate = '15'; // IVA Ecuador 15%

  // Pagination
  static const int defaultPageSize = 50;

  // Sync
  static const Duration syncInterval = Duration(minutes: 5);
  static const int maxSyncRetries = 3;

  // Security
  static const int bcryptRounds = 12;
  static const Duration sessionTimeout = Duration(hours: 8);
  static const Duration tokenExpiry = Duration(hours: 12);

  // Stock alerts
  static const int lowStockThreshold = 10;
  static const int expiryAlertDays = 90; // 3 meses antes

  // Cash register
  static const String currencySymbol = r'$';
  static const String currencyCode = 'USD';
  static const int decimalPlaces = 2;
}
