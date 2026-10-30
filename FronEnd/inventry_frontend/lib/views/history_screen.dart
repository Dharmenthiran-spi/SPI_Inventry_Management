import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/inventory_provider.dart';
import 'db_settings_screen.dart';

class HistoryScreen extends StatefulWidget {
  final bool isEmbedded;
  const HistoryScreen({super.key, this.isEmbedded = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<InventoryProvider>().fetchEvents();
    });
  }

  String _formatDateTime(DateTime dt) {
    // Return simple format like "2026-07-17 16:20:00"
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${pad(dt.month)}-${pad(dt.day)} ${pad(dt.hour)}:${pad(dt.minute)}:${pad(dt.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final Widget listBody = Consumer<InventoryProvider>(
      builder: (context, provider, child) {
        if (provider.loading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF2EA44F)),
          );
        }

        if (provider.error != null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFF85149),
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  provider.error!,
                  style: const TextStyle(color: Color(0xFF8B949E)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => provider.fetchEvents(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final list = provider.events;
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(
                  Icons.history_toggle_off,
                  color: Color(0xFF30363D),
                  size: 64,
                ),
                SizedBox(height: 12),
                Text(
                  'No transaction events found.',
                  style: TextStyle(color: Color(0xFF8B949E), fontSize: 15),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final ev = list[index];
            final isAdd = ev.action.toUpperCase() == 'ADD';

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Row(
                children: [
                  // Action indicator icon
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isAdd
                          ? const Color(0xFF1A3A2A)
                          : const Color(0xFF3D1A1A),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAdd ? Icons.add_circle : Icons.remove_circle,
                      color: isAdd
                          ? const Color(0xFF2EA44F)
                          : const Color(0xFFF85149),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Log details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ev.lcscPart,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(
                              Icons.account_circle,
                              size: 12,
                              color: Color(0xFF8B949E),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ev.userName,
                              style: const TextStyle(
                                color: Color(0xFF8B949E),
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.access_time,
                              size: 12,
                              color: Color(0xFF8B949E),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatDateTime(ev.dateTime),
                              style: const TextStyle(
                                color: Color(0xFF8B949E),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Changed Quantity indicator
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isAdd ? '+' : '-'}${ev.qty}',
                        style: TextStyle(
                          color: isAdd
                              ? const Color(0xFF2EA44F)
                              : const Color(0xFFF85149),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'pcs',
                        style: TextStyle(
                          color: Color(0xFF8B949E),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (widget.isEmbedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Event History',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh Logs',
                  icon: const Icon(Icons.refresh, color: Color(0xFF8B949E)),
                  onPressed: () =>
                      context.read<InventoryProvider>().fetchEvents(),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF30363D), height: 1),
          Expanded(child: listBody),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF8B949E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Event History',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings, color: Color(0xFF8B949E)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DbSettingsScreen()),
              );
            },
          ),
          IconButton(
            tooltip: 'Refresh Logs',
            icon: const Icon(Icons.refresh, color: Color(0xFF8B949E)),
            onPressed: () => context.read<InventoryProvider>().fetchEvents(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: listBody,
    );
  }
}
