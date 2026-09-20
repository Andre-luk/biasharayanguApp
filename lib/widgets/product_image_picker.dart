// lib/widgets/product_image_picker.dart
import 'package:biashara_yangu/utils/image_locale.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/permissions.dart';

typedef OnImagePicked = Future<void> Function(String path);

class ProductImagePicker extends StatefulWidget {
  final String? initialPath;
  final OnImagePicked onImagePicked; // callback pour sauvegarder le path
  final double size;
  const ProductImagePicker({super.key, this.initialPath, required this.onImagePicked, this.size = 96});

  @override
  State<ProductImagePicker> createState() => _ProductImagePickerState();
}

class _ProductImagePickerState extends State<ProductImagePicker> {
  String? _path;
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _path = widget.initialPath;
  }

  Future<void> _pick(ImageSource source) async {
    // demander permissions
    final ok = await PermissionHelper.requestCameraAndStorage();
    if (!ok) {
      if (await PermissionHelper.isPermanentlyDenied()) {
        // demander d'ouvrir paramètres
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Permissions requises. Ouvrir les paramètres ?'),
            action: SnackBarAction(label: 'Paramètres', onPressed: () => PermissionHelper.openAppSettingsIfNeeded()),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permissions nécessaires pour accéder à la caméra/galerie')));
      }
      return;
    }

    final XFile? file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null) return;
    setState(() => _path = file.path);
    await widget.onImagePicked(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => _showPickOptions(),
          child: _path != null && _path!.isNotEmpty
              ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: imageFichierLocal(_path!, width: widget.size, height: widget.size, fit: BoxFit.cover),
          )
              : Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.photo_camera, size: widget.size * 0.5, color: theme.colorScheme.primary),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: _showPickOptions, child: const Text('Changer la photo')),
      ],
    );
  }

  void _showPickOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galerie'), onTap: () { Navigator.pop(ctx); _pick(ImageSource.gallery); }),
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Caméra'), onTap: () { Navigator.pop(ctx); _pick(ImageSource.camera); }),
            ListTile(leading: const Icon(Icons.close), title: const Text('Annuler'), onTap: () => Navigator.pop(ctx)),
          ],
        ),
      ),
    );
  }
}
