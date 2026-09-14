// lib/services/image_service.dart
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

class ImageService {
  static final ImagePicker _picker = ImagePicker();

  /// Demande les permissions (camera + storage/photos) et renvoie true si ok.
  static Future<bool> _ensurePermissions() async {
    // Demander CAMERA et stockage/PHOTOS
    final statuses = await [
      Permission.camera,
      Permission.photos, // iOS & Android 13+
      Permission.storage, // Android legacy
    ].request();

    final cameraOk = statuses[Permission.camera]?.isGranted ?? false;
    final photosOk = (statuses[Permission.photos]?.isGranted ?? false) || (statuses[Permission.storage]?.isGranted ?? false);

    return cameraOk && photosOk;
  }

  /// Ouvre la galerie, renvoie le path local ou null si annulation / erreur.
  static Future<String?> pickFromGallery() async {
    final ok = await _ensurePermissions();
    if (!ok) {
      // permission non accordée
      return null;
    }
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null) return null;
    return file.path;
  }

  /// Ouvre la caméra, renvoie le path local ou null si annulation / erreur.
  static Future<String?> pickFromCamera() async {
    final ok = await _ensurePermissions();
    if (!ok) {
      return null;
    }
    final XFile? file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (file == null) return null;
    return file.path;
  }
}
