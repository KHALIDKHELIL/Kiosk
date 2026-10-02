import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'package:firebase_auth/firebase_auth.dart';

final inventoryProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('inventory')
      .where('is_active', isEqualTo: true)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList(),
      );
});

class WorkerScreen extends ConsumerStatefulWidget {
  const WorkerScreen({super.key});

  @override
  ConsumerState<WorkerScreen> createState() => _WorkerScreenState();
}

class _WorkerScreenState extends ConsumerState<WorkerScreen> {
  String? selectedItemId;
  final TextEditingController priceController = TextEditingController();
  String paymentMethod = 'Cash';

  bool isSeeding = false;
  bool isSubmitting = false;

  @override
  void dispose() {
    priceController.dispose();
    super.dispose();
  }

  Future<void> seedDatabase() async {
    setState(() => isSeeding = true);
    final db = FirebaseFirestore.instance;

    final inventoryJson = [
      {"name": "Samsung 43-inch TV", "base_cost": 12000, "is_active": true},
      {"name": "Tecno Spark 20", "base_cost": 8500, "is_active": true},
      {"name": "HDMI Cable 2m", "base_cost": 150, "is_active": true},
      {"name": "USB-C Charger", "base_cost": 300, "is_active": true},
    ];

    final settingsJson = {
      "monthly_rent": 16000,
      "yearly_tax": 150000,
      "shop_name": "Kiosk",
    };

    try {
      for (var item in inventoryJson) {
        final docRef = db.collection('inventory').doc();
        item['id'] = docRef.id;
        await docRef.set(item);
      }

      await db.collection('shop_settings').doc('config').set(settingsJson);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Database seeded successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error seeding: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isSeeding = false);
    }
  }

  Future<void> logSale(List<Map<String, dynamic>> currentInventory) async {
    if (selectedItemId == null || priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select an item and enter a price.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final finalPrice = double.tryParse(priceController.text);
    if (finalPrice == null) return;

    setState(() => isSubmitting = true);

    try {
      final selectedItemData = currentInventory.firstWhere(
        (item) => item['id'] == selectedItemId,
      );

      final baseCost = (selectedItemData['base_cost'] as num).toDouble();

      if (finalPrice < baseCost) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Error: Price cannot be lower than the base cost ($baseCost ETB). Manager override required.',
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        setState(() => isSubmitting = false);
        return;
      }

      // 1. Get the actual logged-in user
      final currentUser = FirebaseAuth.instance.currentUser;
      // Extract just the name part of the email (e.g., 'admin' from 'admin@kiosk.com')
      final sellerName = currentUser?.email?.split('@')[0] ?? 'Unknown';

      await FirebaseFirestore.instance.collection('sales').add({
        'timestamp': FieldValue.serverTimestamp(),
        'worker_id': sellerName, // 2. UPDATED: No more hardcoded 'worker_123'
        'item_id': selectedItemId,
        'item_name': selectedItemData['name'],
        'base_cost': baseCost,
        'final_price': finalPrice,
        'payment_method': paymentMethod,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sale logged successfully!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }

      setState(() {
        selectedItemId = null;
        priceController.clear();
        paymentMethod = 'Cash';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging sale: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryAsync = ref.watch(inventoryProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiosk POS'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        actions: [
          IconButton(
            icon: Icon(
              themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode,
            ),
            onPressed: () {
              ref.read(themeModeProvider.notifier).toggleTheme();
            },
            tooltip: 'Toggle Theme',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              // 1. Clear any screens that were pushed on top (like the Admin's FAB click)
              Navigator.of(context).popUntil((route) => route.isFirst);

              // 2. Log out of Firebase
              await FirebaseAuth.instance.signOut();
            },
            tooltip: 'Log Out',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  shadowColor: Colors.black26,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: inventoryAsync.when(
                      loading: () => const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (err, stack) => Center(child: Text('Error: $err')),
                      data: (inventory) {
                        if (selectedItemId != null &&
                            !inventory.any(
                              (item) => item['id'] == selectedItemId,
                            )) {
                          selectedItemId = null;
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'New Transaction',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),

                            // UPDATED DROPDOWN WITH PRICE DISPLAY
                            DropdownButtonFormField<String>(
                              isExpanded:
                                  true, // Prevents overflow if item names are too long
                              decoration: const InputDecoration(
                                labelText: 'Select Item',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.inventory_2_outlined),
                              ),
                              initialValue: selectedItemId,
                              items: inventory.map((item) {
                                return DropdownMenuItem<String>(
                                  value: item['id'] as String,
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['name'] as String,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        'Min: ${item['base_cost']} ETB',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) =>
                                  setState(() => selectedItemId = val),
                            ),
                            const SizedBox(height: 20),

                            TextField(
                              controller: priceController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Final Sale Price (ETB)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.attach_money),
                              ),
                            ),
                            const SizedBox(height: 20),

                            DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Payment Method',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.payment),
                              ),
                              initialValue: paymentMethod,
                              items: ['Cash', 'Telebirr', 'CBE Birr']
                                  .map(
                                    (method) => DropdownMenuItem(
                                      value: method,
                                      child: Text(method),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) =>
                                  setState(() => paymentMethod = val!),
                            ),
                            const SizedBox(height: 40),

                            FilledButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () => logSale(inventory),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'LOG SALE',
                                      style: TextStyle(
                                        fontSize: 16,
                                        letterSpacing: 1.2,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 48),

                OutlinedButton.icon(
                  onPressed: isSeeding ? null : seedDatabase,
                  icon: isSeeding
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    isSeeding
                        ? 'Seeding Database...'
                        : 'Dev: Seed Database with JSON',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
