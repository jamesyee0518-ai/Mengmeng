import 'package:flutter/material.dart';

import '../../core/network/memory_client.dart';
import 'memory_item.dart';

class MemoryPanel extends StatefulWidget {
  const MemoryPanel({super.key, this.client});

  final MemoryClient? client;

  @override
  State<MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<MemoryPanel> {
  late final MemoryClient _client;
  late final TextEditingController _searchController;
  List<MemoryItem> _items = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _client = widget.client ?? MemoryClient();
    _searchController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({String? keyword}) async {
    setState(() => _isLoading = true);
    final items = await _client.query(keyword: keyword);
    if (!mounted) {
      return;
    }
    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  Future<void> _clear() async {
    await _client.delete();
    if (!mounted) {
      return;
    }
    _searchController.clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, size: 20),
                const SizedBox(width: 8),
                Text('记忆', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Tooltip(
                  message: '刷新',
                  child: IconButton(
                    key: const ValueKey('refreshMemory'),
                    onPressed: _isLoading ? null : () => _load(),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                Tooltip(
                  message: '清空记忆',
                  child: IconButton(
                    key: const ValueKey('clearMemory'),
                    onPressed: _isLoading || _items.isEmpty ? null : _clear,
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('memorySearchInput'),
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) => _load(keyword: value.trim()),
                    decoration: InputDecoration(
                      hintText: '搜索记忆',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('searchMemory'),
                  onPressed: _isLoading
                      ? null
                      : () => _load(keyword: _searchController.text.trim()),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: _MemoryList(isLoading: _isLoading, items: _items),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryList extends StatelessWidget {
  const _MemoryList({required this.isLoading, required this.items});

  final bool isLoading;
  final List<MemoryItem> items;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '暂无记忆',
            key: const ValueKey('emptyMemory'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: items.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        return ListTile(
          key: ValueKey('memory_${item.id}'),
          leading: const Icon(Icons.bookmark_border),
          title: Text(item.content),
          subtitle: Text('${item.type} · ${item.source}'),
          dense: true,
        );
      },
    );
  }
}
