// Stub implementations for dart:io classes on web platform.
// These compile on web but throw if actually called.

class File {
  final String path;
  File(this.path);

  Future<String> readAsString() async =>
      throw UnsupportedError('File I/O not available on web');

  Future<List<int>> readAsBytes() async =>
      throw UnsupportedError('File I/O not available on web');

  Future<File> writeAsString(String contents) async =>
      throw UnsupportedError('File I/O not available on web');

  Future<File> writeAsBytes(List<int> bytes) async =>
      throw UnsupportedError('File I/O not available on web');

  Future<bool> exists() async => false;

  Future<int> length() async => 0;

  Directory get parent {
    final lastSlash = path.lastIndexOf('/');
    return Directory(lastSlash >= 0 ? path.substring(0, lastSlash) : '.');
  }
}

class Directory {
  final String path;
  Directory(this.path);

  Future<bool> exists() async => false;

  Future<Directory> create({bool recursive = false}) async => this;

  Stream<FileSystemEntity> list({bool recursive = false}) => const Stream.empty();
}

class FileSystemEntity {
  final String path;
  FileSystemEntity(this.path);
}

class Platform {
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;
  static bool get isAndroid => false;
  static bool get isIOS => false;
  static String get localHostname => 'web-browser';
}
