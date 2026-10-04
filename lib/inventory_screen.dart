import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final inventoryStreamProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance.collection('inventory').where('is_active', isEqualTo: true).snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            data['stock_quantity'] = data['stock_quantity'] ?? 0; 
            return data;
          }).toList());
});

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  void _showAddOrEditDialog(BuildContext context, {Map<String, dynamic>? existingItem}) {
    final isEditing = existingItem != null;
    final nameController = TextEditingController(text: isEditing ? existingItem['name'] : '');
    final costController = TextEditingController(text: isEditing ? existingItem['base_cost'].toString() : '');
    final qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEditing ? 'Restock / Edit Item' : 'Add New Product'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Product Name')),
            const SizedBox(height: 12),
            TextField(controller: costController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Wholesale Base Cost (ETB)')),
            const SizedBox(height: 12),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: isEditing ? 'Add Quantity (Restock)' : 'Initial Stock Quantity',
                helperText: isEditing ? 'Current stock: ${existingItem['stock_quantity']}' : null,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              final cost = double.tryParse(costController.text);
              final qtyInput = int.tryParse(qtyController.text) ?? 0;

              if (name.isEmpty || cost == null) return;

              final db = FirebaseFirestore.instance.collection('inventory');

              try {
                if (isEditing) {
                  // NEW: Uses merge to guarantee it doesn't fail if fields are missing
                  await db.doc(existingItem['id']).set({
                    'name': name,
                    'base_cost': cost,
                    if (qtyInput != 0) 'stock_quantity': FieldValue.increment(qtyInput),
                  }, SetOptions(merge: true));
                } else {
                  await db.add({
                    'name': name,
                    'base_cost': cost,
                    'stock_quantity': qtyInput,
                    'is_active': true,
                  });
                }
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved successfully!'), backgroundColor: Colors.green));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(inventoryStreamProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory Manager'), centerTitle: true),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _showAddOrEditDialog(context), icon: const Icon(Icons.add_box), label: const Text('Add Product')),
      body: inventoryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (inventory) {
          final lowStock = inventory.where((item) => (item['stock_quantity'] as int) <= 5).toList();
          final normalStock = inventory.where((item) => (item['stock_quantity'] as int) > 5).toList();

          double totalCapital = 0;
          double lowStockCapital = 0;

          for (var item in inventory) {
            final qty = item['stock_quantity'] as int;
            final cost = (item['base_cost'] as num).toDouble();
            if (qty > 0) {
              final value = qty * cost;
              totalCapital += value;
              if (qty <= 5) lowStockCapital += value;
            }
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 4,
                color: Theme.of(context).colorScheme.primaryContainer,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          Text('Total Capital Value', style: Theme.of(context).textTheme.labelLarge),
                          const SizedBox(height: 4),
                          Text('${totalCapital.toStringAsFixed(0)} ETB', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          Text('All active inventory', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ],
                      ),
                      Container(width: 1, height: 50, color: Colors.grey.withValues( alpha:0.3)),
                      Column(
                        children: [
                          Text('Low Stock Value', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.orange.shade700)),
                          const SizedBox(height: 4),
                          Text('${lowStockCapital.toStringAsFixed(0)} ETB', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                          const Text('Capital in basket', style: TextStyle(fontSize: 12, color: Colors.orange)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (lowStock.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                    const SizedBox(width: 8),
                    Text('Low Stock Basket', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.orange, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 12),
                ...lowStock.map((item) => _buildInventoryTile(context, item, isLowStock: true)),
                const Divider(height: 40),
              ],

              Text('Active Inventory', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...normalStock.map((item) => _buildInventoryTile(context, item, isLowStock: false)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInventoryTile(BuildContext context, Map<String, dynamic> item, {required bool isLowStock}) {
    final qty = item['stock_quantity'] as int;
    return Card(
      elevation: isLowStock ? 2 : 0,
      color: isLowStock ? Colors.orange.withValues( alpha:0.1) : Theme.of(context).colorScheme.surfaceContainerHighest.withValues( alpha:0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: isLowStock ? BorderSide(color: Colors.orange.withValues( alpha:0.5)) : BorderSide.none),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('Base Cost: ${item['base_cost']} ETB'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: isLowStock ? (qty <= 0 ? Colors.red : Colors.orange) : Colors.green, borderRadius: BorderRadius.circular(20)),
              child: Text('$qty in stock', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.edit), onPressed: () => _showAddOrEditDialog(context, existingItem: item), tooltip: 'Edit / Restock'),
          ],
        ),
      ),
    );
  }
}