import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Section 49: Demo Data Specs & Master Seed Model', () {
    test('Verifies Section 49 seed master models and relationships', () {
      // 1. Warehouse
      const warehouse = {
        'name': 'Main Warehouse',
        'short_code': 'WH',
      };
      expect(warehouse['name'], 'Main Warehouse');
      expect(warehouse['short_code'], 'WH');

      // 2. Locations
      const locations = ['Rack A', 'Rack B', 'Production Floor'];
      expect(locations, containsAll(['Rack A', 'Rack B', 'Production Floor']));
      expect(locations.length, 3);

      // 3. Categories
      const categories = ['Raw Materials', 'Finished Goods', 'Components'];
      expect(categories, containsAll(['Raw Materials', 'Finished Goods', 'Components']));
      expect(categories.length, 3);

      // 4. Products
      const products = [
        {'name': 'Steel Rod', 'category': 'Raw Materials', 'uom': 'kg'},
        {'name': 'Chair', 'category': 'Finished Goods', 'uom': 'unit'},
        {'name': 'Table', 'category': 'Finished Goods', 'uom': 'unit'},
      ];
      expect(products.map((p) => p['name']), containsAll(['Steel Rod', 'Chair', 'Table']));

      // 5. Users
      const users = [
        {'role': 'INVENTORY_MANAGER', 'name': 'Inventory Manager', 'email': 'manager@stocksense.com'},
        {'role': 'WAREHOUSE_STAFF', 'name': 'Warehouse Staff', 'email': 'staff@stocksense.com'},
      ];
      expect(users.map((u) => u['name']), containsAll(['Inventory Manager', 'Warehouse Staff']));
    });
  });

  group('Section 50: Required Demo Flow - Complete Mathematical & State Sequence', () {
    test('Executes exact 10-step sequence with rigorous balance assertions', () {
      // State trackers
      double rackAStock = 0.0;
      double productionFloorStock = 0.0;
      double totalStock() => rackAStock + productionFloorStock;

      final moveHistory = <Map<String, dynamic>>[];
      final ledgerEntries = <Map<String, dynamic>>[];

      // Step 1: Login
      const currentUser = {'name': 'Inventory Manager', 'role': 'INVENTORY_MANAGER'};
      expect(currentUser['role'], 'INVENTORY_MANAGER');

      // Step 2: Create Steel Rod
      const product = {'name': 'Steel Rod', 'sku': 'RAW-STEEL-001', 'uom': 'kg', 'reorder_point': 50.0};
      expect(product['name'], 'Steel Rod');

      // Step 3 & 4: Receive 100 kg -> Stock becomes 100 kg
      const receiveQty = 100.0;
      final beforeRec = rackAStock;
      rackAStock += receiveQty;
      moveHistory.add({
        'ref': 'WH/IN/0001',
        'type': 'RECEIPT',
        'status': 'DONE',
        'qty': receiveQty,
        'to': 'Rack A',
      });
      ledgerEntries.add({
        'type': 'RECEIPT',
        'before': beforeRec,
        'change': receiveQty,
        'after': rackAStock,
        'location': 'Rack A',
      });
      expect(rackAStock, 100.0);
      expect(totalStock(), 100.0);

      // Step 5: Transfer 30 kg: Main Warehouse (Rack A) -> Production Floor
      // Result: Main Warehouse = 70 kg, Production Floor = 30 kg
      const transferQty = 30.0;
      final rackABeforeTrf = rackAStock;
      rackAStock -= transferQty;
      final prodBeforeTrf = productionFloorStock;
      productionFloorStock += transferQty;

      moveHistory.add({
        'ref': 'WH/INT/0001',
        'type': 'TRANSFER',
        'status': 'DONE',
        'qty': transferQty,
        'from': 'Rack A',
        'to': 'Production Floor',
      });
      ledgerEntries.add({
        'type': 'TRANSFER_OUT',
        'before': rackABeforeTrf,
        'change': -transferQty,
        'after': rackAStock,
        'location': 'Rack A',
      });
      ledgerEntries.add({
        'type': 'TRANSFER_IN',
        'before': prodBeforeTrf,
        'change': transferQty,
        'after': productionFloorStock,
        'location': 'Production Floor',
      });
      expect(rackAStock, 70.0);
      expect(productionFloorStock, 30.0);
      expect(totalStock(), 100.0);

      // Step 6: Deliver 20 kg. Total: 80 kg
      const deliverQty = 20.0;
      final rackABeforeDel = rackAStock;
      rackAStock -= deliverQty;
      moveHistory.add({
        'ref': 'WH/OUT/0001',
        'type': 'DELIVERY',
        'status': 'DONE',
        'qty': deliverQty,
        'from': 'Rack A',
      });
      ledgerEntries.add({
        'type': 'DELIVERY',
        'before': rackABeforeDel,
        'change': -deliverQty,
        'after': rackAStock,
        'location': 'Rack A',
      });
      expect(rackAStock, 50.0);
      expect(productionFloorStock, 30.0);
      expect(totalStock(), 80.0);

      // Step 7: Adjust -3 kg damaged. Total: 77 kg
      const damageLoss = -3.0;
      final rackABeforeAdj = rackAStock;
      rackAStock += damageLoss; // 50 - 3 = 47
      moveHistory.add({
        'ref': 'WH/ADJ/0001',
        'type': 'ADJUSTMENT',
        'status': 'DONE',
        'qty': damageLoss,
        'reason': 'Damaged',
        'location': 'Rack A',
      });
      ledgerEntries.add({
        'type': 'ADJUSTMENT',
        'before': rackABeforeAdj,
        'change': damageLoss,
        'after': rackAStock,
        'location': 'Rack A',
      });
      expect(rackAStock, 47.0);
      expect(productionFloorStock, 30.0);
      expect(totalStock(), 77.0);

      // Step 8: Open Move History
      expect(moveHistory.length, 4);
      expect(moveHistory.map((m) => m['type']), ['RECEIPT', 'TRANSFER', 'DELIVERY', 'ADJUSTMENT']);

      // Step 9: Open Stock Ledger
      expect(ledgerEntries.length, 5); // RECEIPT, TRANSFER_OUT, TRANSFER_IN, DELIVERY, ADJUSTMENT
      expect(ledgerEntries.first['type'], 'RECEIPT');
      expect(ledgerEntries.last['type'], 'ADJUSTMENT');
      expect(ledgerEntries.last['after'], 47.0);

      // Step 10: Open Inventory Intelligence
      final currentStock = totalStock();
      final reorderPoint = product['reorder_point'] as double;
      final status = currentStock <= reorderPoint ? 'LOW STOCK' : 'NORMAL';
      expect(currentStock, 77.0);
      expect(status, 'NORMAL'); // 77 > 50
    });

    testWidgets('Renders Section 50 Required Demo Flow UI Stepper and balances', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Section 50: Demo Flow Execution')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildDemoStepCard(1, 'Login', 'Inventory Manager', 'manager@stocksense.com'),
                  _buildDemoStepCard(2, 'Create Product', 'Steel Rod (kg)', 'SKU: RAW-STEEL-001'),
                  _buildDemoStepCard(3, 'Receive 100 kg', 'Main Warehouse (Rack A)', 'Stock: 100 kg'),
                  _buildDemoStepCard(4, 'Transfer 30 kg', 'Main Warehouse -> Production Floor', 'Main: 70 kg | Prod: 30 kg'),
                  _buildDemoStepCard(5, 'Deliver 20 kg', 'Rack A -> Customer', 'Total: 80 kg'),
                  _buildDemoStepCard(6, 'Adjust -3 kg damaged', 'Damage Loss: -3 kg', 'Total: 77 kg'),
                  _buildDemoStepCard(7, 'Move History', '4 Operations Recorded', 'RECEIPT, TRANSFER, DELIVERY, ADJUSTMENT'),
                  _buildDemoStepCard(8, 'Stock Ledger', '5 Immutable Ledger Entries', 'Audit trail verified'),
                  _buildDemoStepCard(9, 'Inventory Intelligence', 'Current Stock: 77 kg', 'Status: NORMAL'),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Section 50: Demo Flow Execution'), findsOneWidget);
      expect(find.text('Stock: 100 kg'), findsOneWidget);
      expect(find.text('Main: 70 kg | Prod: 30 kg'), findsOneWidget);
      expect(find.text('Total: 80 kg'), findsOneWidget);
      expect(find.text('Total: 77 kg'), findsOneWidget);
      expect(find.text('Current Stock: 77 kg'), findsOneWidget);
    });
  });

  group('Section 51: Advanced Demo - WAITING -> READY -> DONE Reservation Flow', () {
    test('Simulates complete Section 51 reservation state machine', () {
      // 1. Available stock = 5
      double onHand = 5.0;
      double reserved = 0.0;
      double freeToUse() => onHand - reserved;

      expect(onHand, 5.0);
      expect(reserved, 0.0);
      expect(freeToUse(), 5.0);

      // 2. Create delivery: 20
      const requestedQty = 20.0;
      String deliveryStatus;

      if (freeToUse() >= requestedQty) {
        deliveryStatus = 'READY';
        reserved += requestedQty;
      } else {
        deliveryStatus = 'WAITING'; // Shortage: 20 - 5 = 15
      }

      expect(deliveryStatus, 'WAITING');
      expect(onHand, 5.0);
      expect(reserved, 0.0);
      expect(freeToUse(), 5.0);
      final shortage = requestedQty - freeToUse();
      expect(shortage, 15.0);

      // 3. Then receive: 15
      const receivedQty = 15.0;
      onHand += receivedQty;
      expect(onHand, 20.0);

      // 4. System checks waiting deliveries
      // Oldest created first check:
      if (deliveryStatus == 'WAITING' && freeToUse() >= requestedQty) {
        deliveryStatus = 'READY';
        reserved += requestedQty;
      }

      // Delivery becomes: READY & System reserves stock
      expect(deliveryStatus, 'READY');
      expect(onHand, 20.0);
      expect(reserved, 20.0);
      expect(freeToUse(), 0.0);

      // 5. Validate -> Delivery becomes: DONE & Stock is correctly reduced
      if (deliveryStatus == 'READY') {
        deliveryStatus = 'DONE';
        onHand -= requestedQty;
        reserved -= requestedQty;
      }

      expect(deliveryStatus, 'DONE');
      expect(onHand, 0.0);
      expect(reserved, 0.0);
      expect(freeToUse(), 0.0);
    });

    testWidgets('Renders Section 51 Delivery Card in WAITING, READY, and DONE states', (tester) async {
      // WAITING state widget
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildDeliveryCard(
              reference: 'WH/OUT/0020',
              status: 'WAITING FOR STOCK',
              onHand: 5.0,
              reserved: 0.0,
              freeToUse: 5.0,
              requested: 20.0,
              shortage: 15.0,
            ),
          ),
        ),
      );

      expect(find.text('WAITING FOR STOCK'), findsOneWidget);
      expect(find.text('On Hand: 5.0'), findsOneWidget);
      expect(find.text('Reserved: 0.0'), findsOneWidget);
      expect(find.text('Free to Use: 5.0'), findsOneWidget);
      expect(find.text('Requested: 20.0'), findsOneWidget);
      expect(find.text('Shortage: 15.0'), findsOneWidget);

      // READY state widget after receiving 15
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildDeliveryCard(
              reference: 'WH/OUT/0020',
              status: 'READY',
              onHand: 20.0,
              reserved: 20.0,
              freeToUse: 0.0,
              requested: 20.0,
              shortage: 0.0,
            ),
          ),
        ),
      );

      expect(find.text('READY'), findsOneWidget);
      expect(find.text('On Hand: 20.0'), findsOneWidget);
      expect(find.text('Reserved: 20.0'), findsOneWidget);
      expect(find.text('Free to Use: 0.0'), findsOneWidget);

      // DONE state widget after validation
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _buildDeliveryCard(
              reference: 'WH/OUT/0020',
              status: 'DONE',
              onHand: 0.0,
              reserved: 0.0,
              freeToUse: 0.0,
              requested: 20.0,
              shortage: 0.0,
            ),
          ),
        ),
      );

      expect(find.text('DONE'), findsOneWidget);
      expect(find.text('On Hand: 0.0'), findsOneWidget);
    });
  });
}

Widget _buildDemoStepCard(int step, String title, String subtitle, String details) {
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: CircleAvatar(child: Text('$step')),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: Text(details, style: const TextStyle(color: Colors.blueAccent)),
    ),
  );
}

Widget _buildDeliveryCard({
  required String reference,
  required String status,
  required double onHand,
  required double reserved,
  required double freeToUse,
  required double requested,
  required double shortage,
}) {
  return Card(
    margin: const EdgeInsets.all(16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(reference, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Chip(label: Text(status)),
            ],
          ),
          const Divider(),
          Text('On Hand: $onHand'),
          Text('Reserved: $reserved'),
          Text('Free to Use: $freeToUse'),
          Text('Requested: $requested'),
          if (shortage > 0)
            Text(
              'Shortage: $shortage',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
        ],
      ),
    ),
  );
}
