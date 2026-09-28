import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/mic_button.dart';
import '../controller/search_controller.dart';
import '../model/search_models.dart';
import 'widgets/search_hit_tile.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _run() {
    FocusScope.of(context).unfocus();
    ref.read(searchControllerProvider.notifier).search(_input.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchControllerProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: TextField(
            controller: _input,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              hintText: 'Search documents…',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: MicButton(
                controller: _input,
                onFinal: (_) => _run(),
              ),
            ),
          ),
        ),
        Expanded(child: _body(state)),
      ],
    );
  }

  Widget _body(SearchState state) {
    switch (state.phase) {
      case SearchPhase.initial:
        return const _Message(
          icon: Icons.manage_search,
          text: 'Search across your indexed documents.\nType a query or tap the mic.',
        );
      case SearchPhase.loading:
        return const Center(child: CircularProgressIndicator());
      case SearchPhase.failure:
        return _Message(icon: Icons.cloud_off, text: state.message ?? 'Search failed.');
      case SearchPhase.success:
        if (state.hits.isEmpty) {
          return _Message(
            icon: Icons.search_off,
            text: state.indexing
                ? 'No matches yet — documents are still being indexed.'
                : 'No matching documents found.',
          );
        }
        return Column(
          children: [
            if (state.indexing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('Indexing — results may be incomplete.',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Top ${state.hits.length} results',
                    style: Theme.of(context).textTheme.labelMedium),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                itemCount: state.hits.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => SearchHitTile(hit: state.hits[i]),
              ),
            ),
          ],
        );
    }
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}
