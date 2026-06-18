import 'package:flutter/material.dart';
import '../models/dtc_model.dart';
import '../theme/app_theme.dart';

class DtcScreen extends StatelessWidget {
  final ValueNotifier<List<DtcModel>> dtcNotifier;
  final Map<String, double> liveValues;
  final bool isConnected;
  final Future<void> Function() onScan;
  final Future<void> Function() onClear;
  final bool showAppBar;

  const DtcScreen({
    super.key,
    required this.dtcNotifier,
    required this.liveValues,
    required this.isConnected,
    required this.onScan,
    required this.onClear,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      appBar: showAppBar
          ? AppBar(
              title: const Text('Diagnostics'),
              actions: [
                IconButton(
                  tooltip: 'Scan trouble codes',
                  onPressed: onScan,
                  icon: const Icon(Icons.manage_search),
                ),
              ],
            )
          : null,
      body: ValueListenableBuilder<List<DtcModel>>(
        valueListenable: dtcNotifier,
        builder: (context, dtcs, _) {
          final confirmed = dtcs.where((d) => d.status == 'Confirmed').length;
          final pending = dtcs.where((d) => d.status == 'Pending').length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _StatusPanel(
                count: dtcs.length,
                confirmed: confirmed,
                pending: pending,
                isConnected: isConnected,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      label: 'Scan',
                      icon: Icons.radar,
                      color: AppColors.blue,
                      onTap: onScan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      label: 'Clear',
                      icon: Icons.cleaning_services_outlined,
                      color: AppColors.red,
                      onTap: isConnected ? () => _confirmClear(context) : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _FreezeFrameStrip(liveValues: liveValues),
              const SizedBox(height: 14),
              if (dtcs.isEmpty)
                const _EmptyDtcState()
              else
                ...dtcs.map((dtc) => _DtcCard(dtc: dtc)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear fault codes?'),
        content: const Text(
          'This sends OBD mode 04. It may turn off the check engine light and reset readiness monitors.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.cleaning_services_outlined),
            label: const Text('Clear'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.red),
          ),
        ],
      ),
    );
    if (ok == true) await onClear();
  }
}

class _StatusPanel extends StatelessWidget {
  final int count;
  final int confirmed;
  final int pending;
  final bool isConnected;

  const _StatusPanel({
    required this.count,
    required this.confirmed,
    required this.pending,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    final healthy = count == 0;
    final color = healthy ? AppColors.green : AppColors.red;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            height: 74,
            width: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Icon(
              healthy ? Icons.verified_outlined : Icons.report_problem_outlined,
              color: color,
              size: 34,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  healthy
                      ? 'No Codes Stored'
                      : '$count Code${count == 1 ? '' : 's'} Found',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.text,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isConnected
                      ? '$confirmed confirmed, $pending pending'
                      : 'Connect an ELM327 adapter to scan the ECU.',
                  style: const TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Future<void> Function()? onTap;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !_busy;

    return Material(
      color: enabled ? AppColors.panel : widget.color.withOpacity(0.06),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled
            ? () async {
                setState(() => _busy = true);
                try {
                  await widget.onTap!();
                } finally {
                  if (mounted) setState(() => _busy = false);
                }
              }
            : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.color.withOpacity(enabled ? 0.35 : 0.18),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_busy)
                SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.color,
                  ),
                )
              else
                Icon(
                  widget.icon,
                  color: widget.color.withOpacity(enabled ? 1 : 0.48),
                ),
              const SizedBox(width: 8),
              Text(
                _busy ? 'Loading' : widget.label,
                style: TextStyle(
                  color: widget.color.withOpacity(enabled ? 1 : 0.48),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FreezeFrameStrip extends StatelessWidget {
  final Map<String, double> liveValues;

  const _FreezeFrameStrip({required this.liveValues});

  @override
  Widget build(BuildContext context) {
    final values = [
      ('RPM', liveValues['010C']?.toStringAsFixed(0) ?? '0', 'rpm'),
      ('Speed', liveValues['010D']?.toStringAsFixed(0) ?? '0', 'km/h'),
      ('Coolant', liveValues['0105']?.toStringAsFixed(0) ?? '0', 'C'),
      ('Load', liveValues['0104']?.toStringAsFixed(0) ?? '0', '%'),
    ];

    return Row(
      children: values
          .map(
            (item) => Expanded(
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.panelSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.$2} ${item.$3}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _EmptyDtcState extends StatelessWidget {
  const _EmptyDtcState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: const Column(
        children: [
          Icon(Icons.task_alt, color: AppColors.green, size: 44),
          SizedBox(height: 10),
          Text(
            'Clean diagnostic report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 6),
          Text(
            'Confirmed and pending trouble codes will appear here after a scan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _DtcCard extends StatelessWidget {
  final DtcModel dtc;

  const _DtcCard({required this.dtc});

  @override
  Widget build(BuildContext context) {
    final info = EnhancedDtcDatabase.getDtcInfo(dtc.code);
    final color = dtc.status == 'Confirmed' ? AppColors.red : AppColors.amber;
    final system = _systemFor(dtc.code);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  dtc.code,
                  style: TextStyle(
                    color: color,
                    fontFamily: 'monospace',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dtc.status,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            dtc.description,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _DetailRow(label: 'System', value: system),
          _DetailRow(label: 'Priority', value: info.priority),
          _DetailRow(label: 'Recommended check', value: info.recommendation),
          _DetailRow(label: 'Code type', value: dtc.severity),
        ],
      ),
    );
  }

  String _systemFor(String code) {
    if (code.startsWith('P')) return 'Powertrain';
    if (code.startsWith('C')) return 'Chassis';
    if (code.startsWith('B')) return 'Body';
    if (code.startsWith('U')) return 'Network / communication';
    return 'Unknown';
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(label, style: const TextStyle(color: AppColors.muted)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.text)),
          ),
        ],
      ),
    );
  }
}
