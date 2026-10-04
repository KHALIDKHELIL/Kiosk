import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';
import 'telegram_service.dart'; // NEW: Imports the notification service

final inventoryProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance.collection('inventory').where('is_active', isEqualTo: true).snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList());
});

final recentSalesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance.collection('sales').orderBy('timestamp', descending: true).limit(200).snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['doc_id'] = doc.id; 
            return data;
          }).toList());
});

class WorkerScreen extends ConsumerStatefulWidget {
  const WorkerScreen({super.key});
  @override
  ConsumerState<WorkerScreen> createState() => _WorkerScreenState();
}

class _WorkerScreenState extends ConsumerState<WorkerScreen> {
  String? selectedItemId;
  TextEditingController? searchController; 
  final TextEditingController priceController = TextEditingController();
  String paymentMethod = 'Cash';
  bool isSubmitting = false;
  int quantity = 1;

  @override
  void dispose() {
    priceController.dispose();
    super.dispose();
  }

  Future<void> logSale(List<Map<String, dynamic>> currentInventory) async {
    if (selectedItemId == null || priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select an item and price.'), backgroundColor: Colors.orange));
      return;
    }

    final finalPrice = double.tryParse(priceController.text);
    if (finalPrice == null) return;

    setState(() => isSubmitting = true);

    try {
      final selectedItemData = currentInventory.firstWhere((item) => item['id'] == selectedItemId);
      final unitBaseCost = (selectedItemData['base_cost'] as num).toDouble();
      
      final availableStock = (selectedItemData['stock_quantity'] as num?)?.toInt() ?? 0;
      if (quantity > availableStock) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: Only $availableStock available.'), backgroundColor: Colors.red));
        setState(() => isSubmitting = false);
        return;
      }

      final totalBaseCost = unitBaseCost * quantity;
      final currentUser = FirebaseAuth.instance.currentUser;
      final sellerName = currentUser?.email?.split('@')[0] ?? 'Unknown';

      String userRole = 'worker';
      if (currentUser != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
        userRole = userDoc.data()?['role'] ?? 'worker';
      }

      if (finalPrice < totalBaseCost) {
        if (userRole != 'admin') {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: Minimum allowed price is $totalBaseCost ETB.'), backgroundColor: Colors.red));
          setState(() => isSubmitting = false);
          return;
        } else {
          final minAdminPrice = totalBaseCost * 0.5;
          if (finalPrice < minAdminPrice) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Safety Lock: Admins cannot discount below 50% ($minAdminPrice ETB).'), backgroundColor: Colors.red));
            setState(() => isSubmitting = false);
            return;
          }
        }
      }

      await FirebaseFirestore.instance.collection('sales').add({
        'timestamp': FieldValue.serverTimestamp(),
        'worker_id': sellerName,
        'item_id': selectedItemId,
        'item_name': selectedItemData['name'],
        'base_cost': totalBaseCost, 
        'final_price': finalPrice,
        'quantity': quantity,
        'payment_method': paymentMethod,
        'is_loss_override': finalPrice < totalBaseCost, 
      });

      await FirebaseFirestore.instance.collection('inventory').doc(selectedItemId).update({
        'stock_quantity': FieldValue.increment(-quantity)
      });

      // ==========================================
      // NEW: FIRE TELEGRAM ALERT FOR SALE
      // ==========================================
      TelegramNotifier.sendNotification(
        "✅ *New Sale Logged!*\n"
        "👷 Worker: $sellerName\n"
        "📦 Item: ${selectedItemData['name']}\n"
        "🔢 Qty: $quantity\n"
        "💰 Price: $finalPrice ETB\n"
        "💳 Method: $paymentMethod"
      );


      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(finalPrice < totalBaseCost ? 'Admin Override: Logged at a loss.' : 'Sale logged successfully!'), 
        backgroundColor: finalPrice < totalBaseCost ? Colors.orange : Colors.green
      ));

      setState(() { 
        selectedItemId = null; 
        priceController.clear(); 
        searchController?.clear(); 
        quantity = 1; 
      });
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> voidTransaction(String? docId, String? itemId, int qty) async {
    if (docId == null || itemId == null) return;
    try {
      await FirebaseFirestore.instance.collection('sales').doc(docId).delete();
      await FirebaseFirestore.instance.collection('inventory').doc(itemId).set({
        'stock_quantity': FieldValue.increment(qty)
      }, SetOptions(merge: true));
      
      // ==========================================
      // NEW: FIRE TELEGRAM ALERT FOR VOID
      // ==========================================
      TelegramNotifier.sendNotification("⚠️ *Transaction Voided*\nA worker has cancelled a recent sale and restored $qty stock.");
      
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transaction voided and stock returned.'), backgroundColor: Colors.blue));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error voiding: $e'), backgroundColor: Colors.red));
    }
  }

  void _showExpenseDialog(double shopTodayProfit) {
    String category = 'Food (Essential)';
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
      return AlertDialog(
        title: const Text('Log Daily Expense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              items: ['Food (Essential)', 'Transport (Essential)', 'Shop Supplies', 'Other']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setDialogState(() => category = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (ETB)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Specific Reason (Optional)', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;

              final isEssential = category.contains('Essential');
              final requiredSafeMargin = 1000 + 500; 

              if (!isEssential && shopTodayProfit < requiredSafeMargin) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Declined: Shop profit (${shopTodayProfit.toStringAsFixed(0)} ETB) must be over $requiredSafeMargin ETB for non-essential expenses.'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                ));
                return;
              }

              final currentUser = FirebaseAuth.instance.currentUser;
              final workerEmail = currentUser?.email?.split('@')[0] ?? 'Unknown';

              await FirebaseFirestore.instance.collection('expenses').add({
                'timestamp': FieldValue.serverTimestamp(),
                'worker_id': workerEmail,
                'category': category,
                'amount': amount,
                'reason': reasonCtrl.text.trim(),
              });
              
              // ==========================================
              // NEW: FIRE TELEGRAM ALERT FOR EXPENSES
              // ==========================================
              TelegramNotifier.sendNotification(
                "💸 *New Expense Logged!*\n"
                "👷 Worker: $workerEmail\n"
                "🗂 Category: $category\n"
                "💵 Amount: $amount ETB\n"
                "📝 Reason: ${reasonCtrl.text.isEmpty ? 'N/A' : reasonCtrl.text.trim()}"
              );
              
              if (ctx.mounted) Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense logged successfully.'), backgroundColor: Colors.green));
            },
            child: const Text('Submit Expense'),
          )
        ],
      );
    }));
  }

  @override
  Widget build(BuildContext context) {
    final inventoryAsync = ref.watch(inventoryProvider);
    final salesAsync = ref.watch(recentSalesProvider);
    final themeMode = ref.watch(themeModeProvider);

    final currentUser = FirebaseAuth.instance.currentUser;
    final myWorkerId = currentUser?.email?.split('@')[0] ?? 'worker';

    return Scaffold(
      appBar: AppBar(
        title: Text('Kiosk POS - ${myWorkerId.toUpperCase()}'),
        centerTitle: true,
        actions: [
          IconButton(icon: Icon(themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode), onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme()),
          IconButton(icon: const Icon(Icons.logout), onPressed: () async { Navigator.of(context).popUntil((r) => r.isFirst); await FirebaseAuth.instance.signOut(); }),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: salesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (err, stack) => Text('Error: $err'),
            data: (sales) {
              final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
              
              double myTodayProfit = 0;
              double shopTodayProfit = 0; 
              int myDealsToday = 0;
              
              Map<String, double> dailyLeaderboard = {};
              List<Map<String, dynamic>> teamWins = [];
              List<Map<String, dynamic>> myRecentSales = [];

              for (var sale in sales) {
                if (sale['worker_id'] == myWorkerId) myRecentSales.add(sale);

                final ts = sale['timestamp'] as Timestamp?;
                final date = ts != null ? ts.toDate() : DateTime.now(); 
                
                if (date.isAfter(today) || date.isAtSameMomentAs(today)) {
                  teamWins.add(sale);
                  final worker = sale['worker_id'] ?? 'Unknown';
                  final profit = (sale['final_price'] as num) - (sale['base_cost'] as num);

                  shopTodayProfit += profit;
                  dailyLeaderboard[worker] = (dailyLeaderboard[worker] ?? 0) + profit;

                  if (worker == myWorkerId) {
                    myTodayProfit += profit;
                    myDealsToday++;
                  }
                }
              }

              final sortedLeaderboard = dailyLeaderboard.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
              final motivationText = myTodayProfit >= 500 ? "You're on fire today!" : (myTodayProfit > 0 ? "Great start! Keep pushing." : "Push for a profitable margin!");

              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Wrap(
                  spacing: 24, runSpacing: 24, alignment: WrapAlignment.center,
                  children: [
                    SizedBox(
                      width: 350,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            elevation: 0,
                            color: Theme.of(context).colorScheme.primaryContainer.withValues( alpha:0.2),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                children: [
                                  Text(motivationText, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      Column(children: [ const Icon(Icons.handshake, color: Colors.blue), Text('$myDealsToday', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const Text('Deals') ]),
                                      Column(children: [ const Icon(Icons.trending_up, color: Colors.green), Text(myTodayProfit.toStringAsFixed(0), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)), const Text('Margin') ]),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () => _showExpenseDialog(shopTodayProfit),
                                      icon: const Icon(Icons.receipt_long, size: 18),
                                      label: const Text('Log Business Expense'),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Today's Top Sellers", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                  const Divider(),
                                  ...sortedLeaderboard.asMap().entries.map((entry) {
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(child: Text('#${entry.key + 1}')),
                                      title: Text(entry.value.key),
                                      trailing: Text('+${entry.value.value.toStringAsFixed(0)} ETB', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          Card(
                            elevation: 1,
                            color: Theme.of(context).scaffoldBackgroundColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.withValues( alpha:0.2))),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Live Team Feed", style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.grey)),
                                  const SizedBox(height: 8),
                                  if (teamWins.isEmpty)
                                    const Text("Waiting for incoming deals...", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  ...teamWins.take(3).map((win) {
                                    final profit = (win['final_price'] as num) - (win['base_cost'] as num);
                                    final profitColor = profit >= 0 ? Colors.green : Colors.redAccent;
                                    final profitPrefix = profit > 0 ? '+' : '';
                                    
                                    final qty = win['quantity'] ?? 1;
                                    final qtyString = qty > 1 ? '${qty}x ' : '';

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8.0),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.bolt, size: 14, color: Colors.orange),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              "${win['worker_id']} sold $qtyString${win['item_name']}",
                                              style: const TextStyle(fontSize: 12),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text("$profitPrefix${profit.toStringAsFixed(0)}", 
                                            style: TextStyle(fontSize: 12, color: profitColor, fontWeight: FontWeight.bold)),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),

                    SizedBox(
                      width: 450,
                      child: Column(
                        children: [
                          Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: inventoryAsync.when(
                                loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                                error: (err, stack) => Center(child: Text('Error: $err')),
                                data: (inventory) {
                                  if (selectedItemId != null && !inventory.any((i) => i['id'] == selectedItemId)) selectedItemId = null;
                                  int maxStock = selectedItemId != null ? (inventory.firstWhere((i) => i['id'] == selectedItemId)['stock_quantity'] as num?)?.toInt() ?? 0 : 0;

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      const Text('New Transaction', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                      const SizedBox(height: 24),
                                      
                                      Autocomplete<Map<String, dynamic>>(
                                        displayStringForOption: (item) => item['name'] as String,
                                        optionsBuilder: (TextEditingValue textEditingValue) {
                                          if (textEditingValue.text.isEmpty) return inventory;
                                          return inventory.where((item) {
                                            return (item['name'] as String).toLowerCase().contains(textEditingValue.text.toLowerCase());
                                          });
                                        },
                                        onSelected: (Map<String, dynamic> selection) {
                                          setState(() {
                                            selectedItemId = selection['id'];
                                            quantity = 1;
                                          });
                                        },
                                        fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
                                          searchController = textEditingController;
                                          return TextFormField(
                                            controller: textEditingController,
                                            focusNode: focusNode,
                                            decoration: InputDecoration(
                                              labelText: 'Search & Select Item',
                                              border: const OutlineInputBorder(),
                                              prefixIcon: const Icon(Icons.search),
                                              suffixIcon: selectedItemId != null 
                                                ? IconButton(
                                                    icon: const Icon(Icons.clear),
                                                    onPressed: () {
                                                      textEditingController.clear();
                                                      setState(() => selectedItemId = null);
                                                    },
                                                  )
                                                : null,
                                            ),
                                            onChanged: (val) {
                                              if (selectedItemId != null) setState(() => selectedItemId = null);
                                            },
                                          );
                                        },
                                        optionsViewBuilder: (context, onSelected, options) {
                                          return Align(
                                            alignment: Alignment.topLeft,
                                            child: Material(
                                              elevation: 4,
                                              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(8))),
                                              child: ConstrainedBox(
                                                constraints: const BoxConstraints(maxHeight: 250, maxWidth: 386),
                                                child: ListView.builder(
                                                  padding: EdgeInsets.zero,
                                                  itemCount: options.length,
                                                  itemBuilder: (context, index) {
                                                    final item = options.elementAt(index);
                                                    final qty = item['stock_quantity'] ?? 0;
                                                    return ListTile(
                                                      title: Text(item['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                                      subtitle: Text('Min: ${item['base_cost']} ETB | Stock: $qty',
                                                          style: TextStyle(color: qty <= 0 ? Colors.red : Theme.of(context).colorScheme.primary)),
                                                      onTap: () => onSelected(item),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 20),
                                      Row(
                                        children: [
                                          Expanded(flex: 2, child: TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total Sale Price', border: OutlineInputBorder()))),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            flex: 1,
                                            child: Container(
                                              height: 60, decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(4)),
                                              child: Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                                children: [
                                                  IconButton(icon: const Icon(Icons.remove, size: 20), onPressed: quantity > 1 ? () => setState(() => quantity--) : null),
                                                  Text('$quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                                  IconButton(icon: const Icon(Icons.add, size: 20), onPressed: (selectedItemId != null && quantity < maxStock) ? () => setState(() => quantity++) : null),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 20),
                                      DropdownButtonFormField<String>(
                                        decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder()),
                                        initialValue: paymentMethod,
                                        items: ['Cash', 'Telebirr', 'CBE Birr'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                                        onChanged: (val) => setState(() => paymentMethod = val!),
                                      ),
                                      const SizedBox(height: 32),
                                      FilledButton(
                                        onPressed: isSubmitting ? null : () => logSale(inventory),
                                        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20)),
                                        child: isSubmitting ? const CircularProgressIndicator(color: Colors.white) : const Text('LOG SALE', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          Card(
                            elevation: 2,
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text("My Recent Sales", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  const Divider(height: 24),
                                  ...myRecentSales.take(5).map((sale) {
                                    final profit = (sale['final_price'] as num) - (sale['base_cost'] as num);
                                    final qty = sale['quantity'] ?? 1;
                                    final ts = sale['timestamp'] as Timestamp?;
                                    
                                    final isRecent = ts != null && DateTime.now().difference(ts.toDate()).inMinutes <= 15;

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text('${qty > 1 ? '${qty}x ' : ''}${sale['item_name']}'),
                                      subtitle: Text('${sale['final_price']} ETB (Margin: $profit)'),
                                      trailing: isRecent ? IconButton(
                                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                                        tooltip: 'Void Transaction',
                                        onPressed: () async {
                                          final confirm = await showDialog<bool>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: const Text('Void Transaction?'),
                                              content: const Text('Are you sure you want to void this sale?'),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                                                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                                              ],
                                            )
                                          );
                                          if (confirm == true) voidTransaction(sale['doc_id'], sale['item_id'], qty);
                                        },
                                      ) : const SizedBox(),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}