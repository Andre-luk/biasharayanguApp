import 'package:flutter/material.dart';
import '../models/produit.dart';

class ProductCard extends StatelessWidget {
  final Produit produit;
  final VoidCallback? onTap;

  const ProductCard({super.key, required this.produit, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(produit.nom, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text("${produit.prixVente} CDF"),
            ],
          ),
        ),
      ),
    );
  }
}
