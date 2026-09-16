// lib/widgets/app_dropdown_field.dart
import 'package:flutter/material.dart';

/// Champ de sélection avec le style des `TextField` de l'application
/// (bordure arrondie, label flottant, message d'erreur intégré).
///
/// Pourquoi ne pas utiliser `DropdownButtonFormField` :
/// 1. son paramètre `value` est déprécié depuis Flutter 3.33 au profit de
///    `initialValue`, qui ne réagit pas aux changements programmés de la
///    sélection (cas de la présélection automatique du groupe tarifaire) ;
/// 2. `InputDecorator` + `DropdownButton` donne un contrôle total sur la
///    valeur affichée et sur l'état désactivé.
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.errorText,
    this.prefixIcon,
    this.enabled = true,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? hint;
  final String? errorText;
  final IconData? prefixIcon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool actif = enabled && onChanged != null;

    return InputDecorator(
      isEmpty: value == null,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        enabled: actif,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          hint: hint == null
              ? null
              : Text(
                  hint!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
          onChanged: actif ? onChanged : null,
          items: items,
        ),
      ),
    );
  }
}
