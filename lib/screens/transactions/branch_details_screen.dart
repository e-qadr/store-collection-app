import 'package:flutter/material.dart';
import 'package:store_collection_app/models/branch_model.dart';
// استيراد الشاشتين اللتين تم إنشاؤهما
import 'package:store_collection_app/screens/transactions/new_transaction_screen.dart';
import 'package:store_collection_app/screens/transactions/branch_transactions_screen.dart';

class BranchDetailsScreen extends StatelessWidget {
  final BranchModel branch;

  const BranchDetailsScreen({super.key, required this.branch});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('فرع: ${branch.name}'),
          backgroundColor: Colors.blue,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.blue.shade50,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.storefront,
                        size: 50,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        branch.name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const Text(
                        'إدارة العمليات المالية الفورية',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),

              // الخيار الأول: تسجيل عملية تحصيل جديدة
              Expanded(
                child: InkWell(
                  onTap: () {
                    // الانتقال إلى شاشة التحصيل الجديد
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => NewTransactionScreen(
                          branchId: branch.id,
                          branchName: branch.name,
                        ),
                      ),
                    );
                  },
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_box_rounded,
                          size: 60,
                          color: Colors.green,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'تسجيل تحصيل جديد',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'إدخال مبالغ كاش، شبكة، أو تحويلات',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // الخيار الثاني: سجل العمليات للفرع
              Expanded(
                child: InkWell(
                  onTap: () {
                    // الانتقال إلى شاشة السجل
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BranchTransactionsScreen(
                          branchId: branch.id,
                          branchName: branch.name,
                        ),
                      ),
                    );
                  },
                  child: Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 60,
                          color: Colors.orange,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'سجل السندات والعمليات',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'متابعة حالة السندات المعلقة والمؤكدة',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
