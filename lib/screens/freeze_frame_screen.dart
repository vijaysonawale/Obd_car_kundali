// lib/screens/freeze_frame_screen.dart
import 'package:flutter/material.dart';
import '../models/dtc_model.dart';
import '../models/vehicle_data.dart';

class FreezeFrameScreen extends StatelessWidget {
  final List<DtcModel> dtcList;
  
  const FreezeFrameScreen({
    super.key,
    required this.dtcList,
  });
  
  @override
  Widget build(BuildContext context) {
    final dtcsWithFreezeFrame = dtcList.where((dtc) => dtc.freezeFrame != null).toList();
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Freeze Frame Data'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
      ),
      body: dtcsWithFreezeFrame.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: dtcsWithFreezeFrame.length,
              itemBuilder: (context, index) {
                return _buildFreezeFrameCard(context, dtcsWithFreezeFrame[index]);
              },
            ),
    );
  }
  
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.ac_unit, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No Freeze Frame Data',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Freeze Frame data captures vehicle conditions when a DTC is set. '
              'No DTCs with freeze frame data are currently stored.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFreezeFrameCard(BuildContext context, DtcModel dtc) {
    final freezeFrame = dtc.freezeFrame!;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Color(dtc.colorCode).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Color(dtc.colorCode),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        dtc.code,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dtc.description,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Freeze Frame Info
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 8),
                    Text(
                      'Captured: ${_formatDateTime(freezeFrame.timestamp)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Vehicle State at Fault:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                
                // Parameters Grid
                ...freezeFrame.parameters.entries.map((entry) {
                  return _buildParameterRow(entry.key, entry.value);
                }).toList(),
              ],
            ),
          ),
          
          // Action Buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showDetailDialog(context, dtc),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Details'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _shareFreezeFra me(dtc),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildParameterRow(String pidCode, double value) {
    // Try to get PID info from database
    final pidInfo = _getPidName(pidCode);
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            pidInfo['name'] ?? pidCode,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '${value.toStringAsFixed(1)} ${pidInfo['unit'] ?? ''}',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade700,
            ),
          ),
        ],
      ),
    );
  }
  
  Map<String, String> _getPidName(String pidCode) {
    final paramMap = {
      '010C': {'name': 'Engine RPM', 'unit': 'rpm'},
      '010D': {'name': 'Vehicle Speed', 'unit': 'km/h'},
      '0104': {'name': 'Engine Load', 'unit': '%'},
      '0105': {'name': 'Coolant Temp', 'unit': '°C'},
      '010F': {'name': 'Intake Air Temp', 'unit': '°C'},
      '0110': {'name': 'MAF Rate', 'unit': 'g/s'},
      '0111': {'name': 'Throttle Position', 'unit': '%'},
      '010B': {'name': 'Intake Pressure', 'unit': 'kPa'},
    };
    
    return paramMap[pidCode] ?? {'name': pidCode, 'unit': ''};
  }
  
  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
  
  void _showDetailDialog(BuildContext context, DtcModel dtc) {
    final dtcInfo = EnhancedDtcDatabase.getDtcInfo(dtc.code);
    
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(dtc.code),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Description:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(dtcInfo.description),
            const SizedBox(height: 12),
            const Text(
              'Recommendation:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(dtcInfo.recommendation),
            const SizedBox(height: 12),
            const Text(
              'Priority:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              dtcInfo.priority,
              style: TextStyle(
                color: dtcInfo.priority == 'High' 
                    ? Colors.red 
                    : dtcInfo.priority == 'Medium' 
                        ? Colors.orange 
                        : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
  
  void _shareFreezeFrame(DtcModel dtc) {
    // TODO: Implement share functionality
    // Can use share_plus package to share freeze frame data
  }
}