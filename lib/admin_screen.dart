import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_plus/share_plus.dart'; 
import 'main.dart';
import 'worker_screen.dart';
import 'inventory_screen.dart';

final adminAnalyticsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance.collection('sales').orderBy('timestamp', descending: true).snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['doc_id'] = doc.id; 
            return data;
          }).toList());
});

final adminExpensesProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance.collection('expenses').orderBy('timestamp', descending: true).snapshots()
      .map((snapshot) => snapshot.docs.map((doc) {
            final data = doc.data();
            data['doc_id'] = doc.id;
            return data;
          }).toList());
});

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  final double dailyBreakEven = 1000.0; 

  Future<void> _exportToCSV(BuildContext context, List<Map<String, dynamic>> sales, List<Map<String, dynamic>> expenses) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Web Export blocked. Please run the app on an Android device to use the CSV Exporter.'), backgroundColor: Colors.orange)
      );
      return;
    }

    try {
      StringBuffer csvData = StringBuffer();
      
      csvData.writeln('--- SALES LEDGER ---');
      csvData.writeln('Date,Time,Worker,Item,Quantity,Base Cost,Final Price,Margin,Payment Method');

      for (var sale in sales) {
        final ts = sale['timestamp'] as Timestamp?;
        // UPDATED: Zero-padded dates for Excel parsing
        final date = ts != null ? '${ts.toDate().year}-${ts.toDate().month.toString().padLeft(2, '0')}-${ts.toDate().day.toString().padLeft(2, '0')}' : 'Pending';
        final time = ts != null ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}' : 'Pending';
        final margin = (sale['final_price'] as num) - (sale['base_cost'] as num);
        
        csvData.writeln('$date,$time,${sale['worker_id']},${sale['item_name']},${sale['quantity'] ?? 1},${sale['base_cost']},${sale['final_price']},$margin,${sale['payment_method']}');
      }

      csvData.writeln('\n--- EXPENSE LEDGER ---');
      csvData.writeln('Date,Time,Worker,Category,Amount,Reason');
      
      for (var exp in expenses) {
        final ts = exp['timestamp'] as Timestamp?;
        final date = ts != null ? '${ts.toDate().year}-${ts.toDate().month.toString().padLeft(2, '0')}-${ts.toDate().day.toString().padLeft(2, '0')}' : 'Pending';
        final time = ts != null ? '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}' : 'Pending';
        
        csvData.writeln('$date,$time,${exp['worker_id']},${exp['category']},${exp['amount']},${exp['reason']}');
      }

      final bytes = utf8.encode(csvData.toString());
      final xFile = XFile.fromData(
        Uint8List.fromList(bytes), 
        mimeType: 'text/csv', 
        name: 'Kiosk_Financial_Report_${DateTime.now().millisecondsSinceEpoch}.csv'
      );
      
      await SharePlus.instance.share(
  ShareParams(
    files: [xFile],
    text: 'Kiosk Financial Export',
  ),
);
      
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _adminCancelSale(BuildContext context, String docId, String itemId, int qty) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Sale?'),
        content: const Text('This will delete the sale from your analytics and return the stock to inventory.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(context, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete Sale')),
        ],
      )
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('sales').doc(docId).delete();
        await FirebaseFirestore.instance.collection('inventory').doc(itemId).set({
          'stock_quantity': FieldValue.increment(qty)
        }, SetOptions(merge: true));
        
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sale cancelled & stock restored.'), backgroundColor: Colors.blue));
      } catch (e) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
  }

  void _showExpensesLog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Worker Expense Log'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Consumer(
            builder: (context, ref, child) {
              final expensesAsync = ref.watch(adminExpensesProvider);
              return expensesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => Center(child: Text('Error: $err')),
                data: (expenses) {
                  if (expenses.isEmpty) return const Center(child: Text('No expenses logged yet.'));
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: expenses.length,
                    separatorBuilder: (ctx, i) => const Divider(),
                    itemBuilder: (ctx, i) {
                      final exp = expenses[i];
                      final ts = exp['timestamp'] as Timestamp?;
                      final dateStr = ts != null ? '${ts.toDate().day}/${ts.toDate().month} - ${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}' : 'Pending...';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.money_off, color: Colors.white)),
                        title: Text('${exp['amount']} ETB - ${exp['category']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('By: ${exp['worker_id']} • $dateStr\nReason: ${exp['reason'] == '' ? 'None given' : exp['reason']}'),
                        isThreeLine: true,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]
      )
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(adminAnalyticsProvider);
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiosk - Executive Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(icon: Icon(themeMode == ThemeMode.light ? Icons.dark_mode : Icons.light_mode), onPressed: () => ref.read(themeModeProvider.notifier).toggleTheme()),
          IconButton(icon: const Icon(Icons.inventory_2), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const InventoryScreen()))),
          IconButton(icon: const Icon(Icons.logout), onPressed: () async { Navigator.of(context).popUntil((r) => r.isFirst); await FirebaseAuth.instance.signOut(); }),
          const SizedBox(width: 8),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WorkerScreen())),
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Log Override Sale'),
      ),
      body: salesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (sales) {
          final expensesAsync = ref.watch(adminExpensesProvider);
          
          return expensesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, stack) => Center(child: Text('Error: $err')),
            data: (expenses) {
              if (sales.isEmpty) return const Center(child: Text('No sales data yet.'));

              DateTime oldestDate = DateTime.now();
              double allTimeGrossMargin = 0;
              double allTimeExpenses = 0;

              for (var exp in expenses) {
                allTimeExpenses += (exp['amount'] as num).toDouble();
              }

              for (var sale in sales) {
                final ts = sale['timestamp'] as Timestamp?;
                if (ts != null) {
                  if (ts.toDate().isBefore(oldestDate)) oldestDate = ts.toDate();
                }
                final margin = (sale['final_price'] as num) - (sale['base_cost'] as num);
                allTimeGrossMargin += margin;
              }

              final todayCalendar = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
              final oldestCalendar = DateTime(oldestDate.year, oldestDate.month, oldestDate.day);
              final daysActive = todayCalendar.difference(oldestCalendar).inDays + 1;
              
              final trueGrossAfterExpenses = allTimeGrossMargin - allTimeExpenses;
              final avgDailyGross = trueGrossAfterExpenses / daysActive;
              final avgDailyNetProfit = avgDailyGross - dailyBreakEven;
              final projYearlyNetProfit = avgDailyNetProfit * 365;

              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Wrap(
                    spacing: 16, runSpacing: 16, alignment: WrapAlignment.center,
                    children: [
                      _buildKpiCard(context, 'Daily Break-Even', '${dailyBreakEven.toStringAsFixed(0)} ETB', Icons.trending_flat, Colors.orange),
                      _buildKpiCard(context, 'All-Time Expenses', '${allTimeExpenses.toStringAsFixed(0)} ETB', Icons.money_off, Colors.redAccent),
                      _buildKpiCard(context, 'Gross (After Exp)', '${trueGrossAfterExpenses.toStringAsFixed(0)} ETB', Icons.account_balance_wallet, trueGrossAfterExpenses >= 0 ? Colors.green : Colors.red),
                      _buildKpiCard(context, 'Avg Daily Net', '${avgDailyNetProfit.toStringAsFixed(0)} ETB', Icons.calendar_today, avgDailyNetProfit >= 0 ? Colors.blue : Colors.red),
                      _buildKpiCard(context, 'Proj. Yearly Net', '${projYearlyNetProfit.toStringAsFixed(0)} ETB', Icons.account_balance, projYearlyNetProfit >= 0 ? Colors.purple : Colors.red),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Transaction History', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      Row(
                        children: [
                          OutlinedButton.icon(onPressed: () => _showExpensesLog(context, ref), icon: const Icon(Icons.receipt_long, color: Colors.redAccent), label: const Text('View Expenses', style: TextStyle(color: Colors.redAccent))),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await _exportToCSV(context, sales, expenses);
                            }, 
                            icon: const Icon(Icons.ios_share), 
                            label: const Text('Export Ledger')
                          ),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 16),

                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: sales.take(100).length, 
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final sale = sales[index];
                        final profit = (sale['final_price'] as num) - (sale['base_cost'] as num);
                        final qty = sale['quantity'] ?? 1;
                        
                        final ts = sale['timestamp'] as Timestamp?;
                        final dateString = ts != null ? '${ts.toDate().day}/${ts.toDate().month} - ${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}' : 'Pending...';
                        
                        final isLessThanAMonth = ts != null && DateTime.now().difference(ts.toDate()).inDays <= 30;

                        return ListTile(
                          leading: CircleAvatar(child: const Icon(Icons.receipt_long, size: 20)),
                          title: Text('${qty > 1 ? '${qty}x ' : ''}${sale['item_name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Sold by: ${sale['worker_id']} • $dateString'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${sale['final_price']} ETB', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text('${profit > 0 ? '+' : ''}${profit.toStringAsFixed(0)} ETB margin', style: TextStyle(color: profit >= 0 ? Colors.green : Colors.redAccent, fontSize: 12)),
                                ],
                              ),
                              if (isLessThanAMonth)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12.0),
                                  child: IconButton(
                                    icon: const Icon(Icons.cancel, color: Colors.redAccent),
                                    tooltip: 'Cancel Sale',
                                    onPressed: () => _adminCancelSale(context, sale['doc_id'], sale['item_id'], qty),
                                  ),
                                )
                            ],
                          ),
                        );
                      },
                    ),
                  )
                ],
              );
            }
          );
        },
      ),
    );
  }

  Widget _buildKpiCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      width: 200, 
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues( alpha:0.3), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues( alpha:0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}