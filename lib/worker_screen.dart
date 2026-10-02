import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'main.dart';

final inventoryProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('inventory')
      .where('is_active', isEqualTo: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList());
});

final recentSalesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('sales')
      .orderBy('timestamp', descending: true)
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
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
  bool isSubmitting = false;

  @override
  void dispose() {
    priceController.dispose();
    super.dispose();
  }

  Future<void> logSale(List<Map<String, dynamic>> currentInventory) async {
    if (selectedItemId == null || priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an item and enter a price.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final finalPrice = double.tryParse(priceController.text);
    if (finalPrice == null) return;

    setState(() => isSubmitting = true);

    try {
      final selectedItemData = currentInventory.firstWhere((item) => item['id'] == selectedItemId);
      final baseCost = (selectedItemData['base_cost'] as num).toDouble();
      
      final currentUser = FirebaseAuth.instance.currentUser;
      final sellerName = currentUser?.email?.split('@')[0] ?? 'Unknown';

      String userRole = 'worker';
      if (currentUser != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get();
        if (userDoc.exists) {
          userRole = userDoc.data()?['role'] ?? 'worker';
        }
      }

      if (finalPrice < baseCost && userRole != 'admin') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: Price cannot be lower than the base cost ($baseCost ETB). Manager override required.'),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        setState(() => isSubmitting = false);
        return;
      }

      await FirebaseFirestore.instance.collection('sales').add({
        'timestamp': FieldValue.serverTimestamp(),
        'worker_id': sellerName,
        'item_id': selectedItemId,
        'item_name': selectedItemData['name'],
        'base_cost': baseCost,
        'final_price': finalPrice,
        'payment_method': paymentMethod,
        'is_loss_override': finalPrice < baseCost, 
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(finalPrice < baseCost 
                ? 'Admin Override: Sale logged at a loss.' 
                : 'Sale logged successfully! Great job!'), 
            backgroundColor: finalPrice < baseCost ? Colors.orange : Colors.green, 
            behavior: SnackBarBehavior.floating
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
          SnackBar(content: Text('Error logging sale: $e'), backgroundColor: Colors.redAccent, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventoryAsync = ref.watch(inventoryProvider);
    final salesAsync = ref.watch(recentSalesProvider);
    final themeMode = ref.watch(themeModeProvider);

    final currentUser = FirebaseAuth.instance.currentUser;
    final myWorkerId = currentUser?.email?.split('@')[0] ?? 'worker';
    final workerName = myWorkerId.toUpperCase();

    return Scaffold(
      appBar: AppBar(
        title: Text('Kiosk POS - $workerName'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 2,
        actions: [
          IconButton(
            icon: Icon(themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
            tooltip: 'Toggle Theme',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              Navigator.of(context).popUntil((route) => route.isFirst);
              await FirebaseAuth.instance.signOut();
            },
            tooltip: 'Log Out',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: salesAsync.when(
            loading: () => const CircularProgressIndicator(),
            error: (err, stack) => Text('Error loading stats: $err'),
            data: (sales) {
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);
              
              double myTodaySales = 0;
              double myTodayProfit = 0;
              int myDealsToday = 0;
              
              Map<String, double> dailyLeaderboard = {};
              List<Map<String, dynamic>> teamWins = [];
              
              // NEW: Array to hold this specific worker's all-time recent sales
              List<Map<String, dynamic>> myRecentSales = [];

              for (var sale in sales) {
                // Populate personal history list regardless of date
                if (sale['worker_id'] == myWorkerId) {
                  myRecentSales.add(sale);
                }

                final ts = sale['timestamp'] as Timestamp?;
                final date = ts != null ? ts.toDate() : DateTime.now(); 
                
                // Today's metrics logic
                if (date.isAfter(today) || date.isAtSameMomentAs(today)) {
                  teamWins.add(sale);
                  
                  final worker = sale['worker_id'] ?? 'Unknown';
                  final price = (sale['final_price'] as num?)?.toDouble() ?? 0;
                  final cost = (sale['base_cost'] as num?)?.toDouble() ?? 0;
                  final profit = price - cost;

                  dailyLeaderboard[worker] = (dailyLeaderboard[worker] ?? 0) + profit;

                  if (worker == myWorkerId) {
                    myTodaySales += price;
                    myTodayProfit += profit;
                    myDealsToday++;
                  }
                }
              }

              final sortedLeaderboard = dailyLeaderboard.entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));

              final myProfitColor = myTodayProfit >= 0 ? Colors.green : Colors.redAccent;
              final myProfitIcon = myTodayProfit >= 0 ? Icons.trending_up : Icons.trending_down;
              final myProfitPrefix = myTodayProfit > 0 ? '+' : '';

              // NEW: Strict Logic for the Motivation Banner
              String motivationText = "Let's get that first sale!";
              IconData motivationIcon = Icons.star_border;
              Color motivationColor = Colors.grey;

              if (myTodayProfit >= 500) {
                motivationText = "You're on fire today!";
                motivationIcon = Icons.local_fire_department;
                motivationColor = Colors.orange;
              } else if (myTodayProfit > 0) {
                motivationText = "Great start! Keep pushing.";
                motivationIcon = Icons.trending_up;
                motivationColor = Colors.green;
              } else if (myDealsToday > 0 && myTodayProfit <= 0) {
                motivationText = "Push for a profitable margin!";
                motivationIcon = Icons.warning_amber_rounded;
                motivationColor = Colors.orange;
              }

              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  alignment: WrapAlignment.center,
                  children: [
                    
                    // LEFT COLUMN: MOTIVATION & LEADERBOARD
                    SizedBox(
                      width: 350,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                            ),
                            color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.2),
                            child: Padding(
                              padding: const EdgeInsets.all(20.0),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(motivationIcon, color: motivationColor),
                                      const SizedBox(width: 8),
                                      Text(
                                        motivationText,
                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildStatColumn(context, 'Deals', '$myDealsToday', Icons.handshake),
                                      _buildStatColumn(context, 'Revenue', '${myTodaySales.toStringAsFixed(0)}', Icons.payments),
                                      _buildStatColumn(
                                        context, 
                                        'Margin', 
                                        '$myProfitPrefix${myTodayProfit.toStringAsFixed(0)}', 
                                        myProfitIcon, 
                                        highlightColor: myProfitColor
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Daily Target (500 ETB)', style: Theme.of(context).textTheme.bodySmall),
                                      const SizedBox(height: 4),
                                      LinearProgressIndicator(
                                        value: (myTodayProfit / 500).clamp(0.0, 1.0),
                                        backgroundColor: Colors.grey.withOpacity(0.2),
                                        color: Colors.green,
                                        borderRadius: BorderRadius.circular(4),
                                        minHeight: 8,
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.emoji_events, color: Colors.amber),
                                      const SizedBox(width: 8),
                                      Text("Today's Top Sellers", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const Divider(),
                                  if (sortedLeaderboard.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(vertical: 16),
                                      child: Text("No sales yet today. Be the first!"),
                                    ),
                                  ...sortedLeaderboard.asMap().entries.map((entry) {
                                    final rank = entry.key + 1;
                                    final worker = entry.value.key;
                                    final profit = entry.value.value;
                                    
                                    final profitColor = profit >= 0 ? Colors.green : Colors.redAccent;
                                    final profitPrefix = profit > 0 ? '+' : '';

                                    Color medalColor = Colors.grey;
                                    if (rank == 1) medalColor = Colors.amber;
                                    if (rank == 2) medalColor = Colors.blueGrey;
                                    if (rank == 3) medalColor = Colors.brown.shade300;

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      leading: CircleAvatar(
                                        backgroundColor: medalColor.withOpacity(0.2),
                                        child: Text('#$rank', style: TextStyle(color: medalColor, fontWeight: FontWeight.bold)),
                                      ),
                                      title: Text(worker == myWorkerId ? '$worker (You)' : worker, 
                                        style: TextStyle(fontWeight: worker == myWorkerId ? FontWeight.bold : FontWeight.normal)
                                      ),
                                      trailing: Text('$profitPrefix${profit.toStringAsFixed(0)} ETB', 
                                        style: TextStyle(color: profitColor, fontWeight: FontWeight.bold)),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.withOpacity(0.2))),
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

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8.0),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.bolt, size: 14, color: Colors.orange),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              "${win['worker_id']} sold a ${win['item_name']}",
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

                    // RIGHT COLUMN: POS FORM & PERSONAL TRANSACTIONS
                    SizedBox(
                      width: 450,
                      child: Column(
                        children: [
                          Card(
                            elevation: 4,
                            shadowColor: Colors.black26,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: inventoryAsync.when(
                                loading: () => const SizedBox(height: 200, child: Center(child: CircularProgressIndicator())),
                                error: (err, stack) => Center(child: Text('Error: $err')),
                                data: (inventory) {
                                  if (selectedItemId != null && !inventory.any((item) => item['id'] == selectedItemId)) {
                                    selectedItemId = null;
                                  }

                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        'New Transaction',
                                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 32),
                                      DropdownButtonFormField<String>(
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Select Item',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.inventory_2_outlined),
                                        ),
                                        value: selectedItemId,
                                        items: inventory.map((item) {
                                          return DropdownMenuItem<String>(
                                            value: item['id'] as String,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(child: Text(item['name'] as String, overflow: TextOverflow.ellipsis)),
                                                Text('Min: ${item['base_cost']} ETB',
                                                    style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) => setState(() => selectedItemId = val),
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
                                        value: paymentMethod,
                                        items: ['Cash', 'Telebirr', 'CBE Birr']
                                            .map((method) => DropdownMenuItem(value: method, child: Text(method)))
                                            .toList(),
                                        onChanged: (val) => setState(() => paymentMethod = val!),
                                      ),
                                      const SizedBox(height: 40),
                                      FilledButton(
                                        onPressed: isSubmitting ? null : () => logSale(inventory),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(vertical: 20),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        ),
                                        child: isSubmitting
                                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                            : const Text('LOG SALE', style: TextStyle(fontSize: 16, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // NEW: Personal Recent Transactions List
                          Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.history),
                                      const SizedBox(width: 8),
                                      Text("My Recent Sales", style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                  const Divider(height: 24),
                                  if (myRecentSales.isEmpty)
                                    const Text("You haven't logged any sales yet.", style: TextStyle(color: Colors.grey)),
                                  ...myRecentSales.take(5).map((sale) {
                                    final profit = (sale['final_price'] as num) - (sale['base_cost'] as num);
                                    final pColor = profit >= 0 ? Colors.green : Colors.redAccent;
                                    final pPrefix = profit > 0 ? '+' : '';
                                    
                                    final ts = sale['timestamp'] as Timestamp?;
                                    final dateStr = ts != null 
                                      ? '${ts.toDate().day}/${ts.toDate().month} - ${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}' 
                                      : 'Pending...';

                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(sale['item_name'] ?? 'Unknown Item', style: const TextStyle(fontWeight: FontWeight.bold)),
                                      subtitle: Text(dateStr),
                                      trailing: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.end,
                                        children: [
                                          Text('${sale['final_price']} ETB', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          Text('$pPrefix${profit.toStringAsFixed(0)} ETB margin', style: TextStyle(color: pColor, fontSize: 12)),
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
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatColumn(BuildContext context, String label, String value, IconData icon, {Color? highlightColor}) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: highlightColor,
          ),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}