import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'worker_screen.dart'; 

// Fetch shop settings (rent, tax)
final shopSettingsProvider = StreamProvider<Map<String, dynamic>>((ref) {
  return FirebaseFirestore.instance
      .collection('shop_settings')
      .doc('config')
      .snapshots()
      .map((doc) => doc.data() ?? {});
});

// Fetch all sales, ordered by newest
final allSalesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('sales')
      .orderBy('timestamp', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['id'] = doc.id;
            return data;
          }).toList());
});

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(shopSettingsProvider);
    final salesAsync = ref.watch(allSalesProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiosk - Admin Dashboard'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode),
            onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme(),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const WorkerScreen()));
        },
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Log New Sale'),
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Settings Error: $err')),
        data: (settings) {
          return salesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Sales Error: $err')),
            data: (sales) {
              
              // --- 1. CORE MATH & AGGREGATIONS ---
              double totalRevenue = 0;
              double totalBaseCost = 0;
              
              for (var sale in sales) {
                totalRevenue += (sale['final_price'] as num?)?.toDouble() ?? 0;
                totalBaseCost += (sale['base_cost'] as num?)?.toDouble() ?? 0;
              }
              
              final double grossProfitAllTime = totalRevenue - totalBaseCost;

              // Fixed Costs calculations
              final double monthlyRent = (settings['monthly_rent'] as num?)?.toDouble() ?? 0;
              final double yearlyTax = (settings['yearly_tax'] as num?)?.toDouble() ?? 0;
              final double yearlyFixedCosts = (monthlyRent * 12) + yearlyTax;
              final double dailyBreakEven = yearlyFixedCosts / 365;

              // Run-rate calculations (Assuming 1 day active for now if no dates differ)
              int daysActive = 1;
              if (sales.isNotEmpty) {
                final firstSaleTimestamp = sales.last['timestamp'] as Timestamp?;
                if (firstSaleTimestamp != null) {
                  final firstSaleDate = firstSaleTimestamp.toDate();
                  final difference = DateTime.now().difference(firstSaleDate).inDays;
                  daysActive = difference > 0 ? difference : 1;
                }
              }

              final double avgDailyProfit = grossProfitAllTime / daysActive;
              final double projectedYearlyNet = (avgDailyProfit * 365) - yearlyFixedCosts;

              // --- 2. UI RENDERING ---
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000), // Wider for admin panels
                  child: ListView(
                    padding: const EdgeInsets.all(24.0),
                    children: [
                      
                      // METRICS GRID
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildMetricCard(context, 'Daily Break-Even', '${dailyBreakEven.toStringAsFixed(0)} ETB', Icons.show_chart, Colors.orange),
                          _buildMetricCard(context, 'Avg Daily Profit', '${avgDailyProfit.toStringAsFixed(0)} ETB', Icons.calendar_today, Colors.blue),
                          _buildMetricCard(context, 'All-Time Gross Profit', '${grossProfitAllTime.toStringAsFixed(0)} ETB', Icons.account_balance_wallet, Colors.green),
                          _buildMetricCard(context, 'Proj. Yearly Net Profit', '${projectedYearlyNet.toStringAsFixed(0)} ETB', Icons.account_balance, projectedYearlyNet >= 0 ? Colors.green : Colors.red),
                        ],
                      ),
                      
                      const SizedBox(height: 40),
                      
                      Text(
                        'Recent Transactions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      
                      // TRANSACTIONS FEED
                      Card(
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: sales.take(10).length, // Show latest 10
                          separatorBuilder: (context, index) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final sale = sales[index];
                            final profit = (sale['final_price'] as num) - (sale['base_cost'] as num);
                            final timestamp = sale['timestamp'] as Timestamp?;
                            final dateString = timestamp != null 
                              ? '${timestamp.toDate().day}/${timestamp.toDate().month} - ${timestamp.toDate().hour}:${timestamp.toDate().minute.toString().padLeft(2, '0')}' 
                              : 'Pending...';

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                child: const Icon(Icons.receipt_long, size: 20),
                              ),
                              title: Text(sale['item_name'] ?? 'Unknown Item', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Sold by: ${sale['worker_id']} • $dateString'),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${sale['final_price']} ETB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text('+${profit.toStringAsFixed(0)} ETB margin', style: const TextStyle(color: Colors.green, fontSize: 12)),
                                ],
                              ),
                            );
                          },
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Helper widget for rendering standard stat cards
  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon, Color iconColor) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 28),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color, fontSize: 14)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}