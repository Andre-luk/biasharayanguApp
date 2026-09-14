// lib/utils/permissions.dart
import 'package:permission_handler/permission_handler.dart';

class PermissionHelper {
  /// Demande les permissions nécessaires caméra + gallery (Android & iOS).
  /// Retourne true si permissions accordées (au moins celles nécessaires).
  static Future<bool> requestCameraAndStorage() async {
    // Sur Android 13+, permission_handler mappe photos => READ_MEDIA_IMAGES
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.photos,    // iOS / Android 13
      Permission.storage,   // legacy Android
    ].request();

    final cameraOk = statuses[Permission.camera]?.isGranted ?? false;
    final photosOk = (statuses[Permission.photos]?.isGranted ?? false) || (statuses[Permission.storage]?.isGranted ?? false);

    return cameraOk && photosOk;
  }

  /// Vérifie si permissions sont définitivement refusées.
  static Future<bool> isPermanentlyDenied() async {
    final cam = await Permission.camera.status;
    final photos = await Permission.photos.status;
    final storage = await Permission.storage.status;
    return cam.isPermanentlyDenied || photos.isPermanentlyDenied || storage.isPermanentlyDenied;
  }

  static Future<void> openAppSettingsIfNeeded() async {
    if (await isPermanentlyDenied()) {
      await openAppSettings();
    }
  }
}
