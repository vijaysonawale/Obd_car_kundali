// lib/screens/freeze_frame_screen.dart
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../models/dtc_model.dart';
import '../models/vehicle_data.dart';

class FreezeFrameScreen extends StatelessWidget {
  final List<DtcModel> dtcList;

  const FreezeFrameScreen({super.key, required this.dtcList});

  @override
  Widget build(BuildContext context) {
    final dtcsWithFF = dtcList.where((d) => d.freezeFrame != null).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Freeze Frame Data'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: dtcsWithFF.isEmpty ? _emptyState() : ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: dtcsWithFF.length,
        itemBuilder: (context, i) => _buildCard(context, dtcsWithFF[i]),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.ac_unit, size: 80, color: Colors.grey.shade300),
      const SizedBox(height: 16),
      Text('No Freeze Frame Data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
      const SizedBox(height: 8),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          'Freeze Frame data is captured when a DTC is set. Connect and scan DTCs to check.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
      ),
    ]),
  );

  Widget _buildCard(BuildContext context, DtcModel dtc) {
    final ff = dtc.freezeFrame!;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(dtc.colorCode).withOpacity(0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(children: [
              Icon(Icons.error_outline, color: Color(dtc.colorCode), size: 28),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dtc.code, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                const SizedBox(height: 2),
                Text(dtc.description, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: Color(dtc.colorCode), borderRadius: BorderRadius.circular(6)),
                child: Text(dtc.status, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text('Captured: ${_fmtDt(ff.timestamp)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
              const SizedBox(height: 14),
              const Text('Vehicle State at Fault:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              ...ff.parameters.entries.map((e) => _paramRow(e.key, e.value)).toList(),
            ]),
          ),
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton.icon(
                onPressed: () => _showDetail(context, dtc),
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('Details'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: () => _shareFreezeFrame(dtc),  // ← Fixed typo
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Share'),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _paramRow(String pidCode, double value) {
    final info = _getPidInfo(pidCode);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(info['name'] ?? pidCode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        Text('${value.toStringAsFixed(1)} ${info['unit'] ?? ''}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
      ]),
    );
  }

  Map<String, String> _getPidInfo(String pidCode) {
    const map = {
      '010C': {'name': 'Engine RPM', 'unit': 'rpm'},
      '010D': {'name': 'Vehicle Speed', 'unit': 'km/h'},
      '0104': {'name': 'Engine Load', 'unit': '%'},
      '0105': {'name': 'Coolant Temp', 'unit': '°C'},
      '010F': {'name': 'Intake Air Temp', 'unit': '°C'},
      '0110': {'name': 'MAF Rate', 'unit': 'g/s'},
      '0111': {'name': 'Throttle Position', 'unit': '%'},
      '010B': {'name': 'Intake Pressure', 'unit': 'kPa'},
      '0106': {'name': 'STFT B1', 'unit': '%'},
      '0107': {'name': 'LTFT B1', 'unit': '%'},
    };
    return map[pidCode] ?? {'name': pidCode, 'unit': ''};
  }

  String _fmtDt(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}  ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';

  void _showDetail(BuildContext context, DtcModel dtc) {
    final info = EnhancedDtcDatabase.getDtcInfo(dtc.code);
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(dtc.code),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(info.description),
        const SizedBox(height: 10),
        const Text('Recommendation:', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(info.recommendation),
        const SizedBox(height: 10),
        const Text('Priority:', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(info.priority, style: TextStyle(color: info.priority == 'High' ? Colors.red : Colors.orange, fontWeight: FontWeight.bold)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    ));
  }

  void _shareFreezeFrame(DtcModel dtc) {  // ← Fixed method name
    final ff = dtc.freezeFrame;
    final sb = StringBuffer()
      ..writeln('=== Freeze Frame Report ===')
      ..writeln('Code: ${dtc.code}')
      ..writeln('Status: ${dtc.status}')
      ..writeln('Description: ${dtc.description}')
      ..writeln('Captured: ${ff != null ? _fmtDt(ff.timestamp) : "N/A"}')
      ..writeln()
      ..writeln('Vehicle Parameters:');
    ff?.parameters.forEach((k, v) {
      final info = _getPidInfo(k);
      sb.writeln('  ${info['name']}: ${v.toStringAsFixed(1)} ${info['unit']}');
    });
    Share.share(sb.toString());
  }
}