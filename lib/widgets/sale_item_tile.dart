import 'package:flutter/material.dart';
import '../models/produit.dart';

class SaleItemTile extends StatelessWidget {
  final Produit produit;
  final VoidCallback? onAdd;

  const SaleItemTile({super.key, required this.produit, this.onAdd});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text("${produit.nom} - ${produit.prixVente} CDF"),
      trailing: IconButton(
        icon: const Icon(Icons.add, color: Colors.green),
        onPressed: onAdd,
      ),
    );
  }
}
