import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/samseer_core.dart';
import '../../feature/exporter.dart';
import '../../model/http_call.dart';
import '../theme/samseer_theme.dart';
import '../widget/call_tile.dart';
import '../widget/empty_state.dart';
import '../widget/samseer_toast.dart';
import '../../model/console_log.dart';
import 'call_detail_screen.dart';
import 'console_view.dart';
import 'stats_screen.dart';

enum _StatusFilter { all, success, redirect, clientError, serverError, errors }

class CallListScreen extends StatefulWidget {
  const CallListScreen({super.key, required this.core});
  final SamseerCore core;

  @override
  State<CallListScreen> createState() => _CallListScreenState();
}

class _CallListScreenState extends State<CallListScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final config = widget.core.configuration;
    return Theme(
      data: SamseerTheme.theme(),
      child: Directionality(
        textDirection: config.directionality ?? Directionality.of(context),
        child: Scaffold(
          appBar: AppBar(
            title: Text(_tab == 0 ? 'Samseer' : 'Console'),
            actions: [
              IconButton(
                tooltip: 'Stats',
                icon: const Icon(Icons.insights_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StatsScreen(core: widget.core),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: _onMenu,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'export', child: Text('Copy as JSON')),
                  PopupMenuItem(value: 'clear', child: Text('Clear All')),
                ],
              ),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              _NetworkView(core: widget.core),
              ConsoleView(core: widget.core),
            ],
          ),
          bottomNavigationBar: StreamBuilder<List<SamseerConsoleLog>>(
            stream: widget.core.storage.consoleStream,
            initialData: widget.core.storage.consoleLogs,
            builder: (context, snap) {
              final count = (snap.data ?? const []).length;
              return NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.travel_explore_outlined),
                    selectedIcon: Icon(Icons.travel_explore),
                    label: 'Network',
                  ),
                  NavigationDestination(
                    icon: Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      child: const Icon(Icons.terminal_outlined),
                    ),
                    selectedIcon: Badge.count(
                      count: count,
                      isLabelVisible: count > 0,
                      child: const Icon(Icons.terminal),
                    ),
                    label: 'Console',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _onMenu(String value) async {
    switch (value) {
      case 'export':
        final calls = widget.core.storage.calls;
        if (calls.isEmpty) {
          SamseerToast.show(
            context,
            'Nothing to export',
            subtitle: 'No HTTP calls have been recorded yet.',
            variant: SamseerToastVariant.warning,
          );
          return;
        }
        final json = Exporter.buildJsonExport(calls);
        await Clipboard.setData(ClipboardData(text: json));
        if (!mounted) return;
        final size = Exporter.formatSize(json.length);
        final large = json.length > 1024 * 1024;
        SamseerToast.show(
          context,
          large ? 'Copied — large content ($size)' : 'JSON export copied',
          subtitle: large
              ? 'Some apps may truncate. ${calls.length} calls · $size'
              : '${calls.length} calls · $size',
          variant:
              large ? SamseerToastVariant.warning : SamseerToastVariant.success,
        );
      case 'clear':
        widget.core.storage.clear();
    }
  }
}

class _NetworkView extends StatefulWidget {
  const _NetworkView({required this.core});
  final SamseerCore core;

  @override
  State<_NetworkView> createState() => _NetworkViewState();
}

class _NetworkViewState extends State<_NetworkView> {
  String _query = '';
  _StatusFilter _filter = _StatusFilter.all;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchBar(onChanged: (v) => setState(() => _query = v)),
        _FilterRow(
          selected: _filter,
          onSelected: (f) => setState(() => _filter = f),
        ),
        Expanded(
          child: StreamBuilder<List<SamseerHttpCall>>(
            stream: widget.core.storage.stream,
            initialData: widget.core.storage.calls,
            builder: (context, snap) {
              final calls = _apply(snap.data ?? const []);
              if (calls.isEmpty) {
                return const EmptyState(
                  title: 'No HTTP calls yet',
                  subtitle: 'Make a network request and it will show up here.',
                  icon: Icons.travel_explore,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                itemCount: calls.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) => _AnimatedTile(
                  key: ValueKey(calls[i].id),
                  child: CallTile(
                    call: calls[i],
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CallDetailScreen(
                          core: widget.core,
                          callId: calls[i].id,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<SamseerHttpCall> _apply(List<SamseerHttpCall> input) {
    var result = input;
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      result = result.where((c) {
        return c.uri.toLowerCase().contains(q) ||
            c.endpoint.toLowerCase().contains(q) ||
            c.method.toLowerCase().contains(q) ||
            (c.status?.toString().contains(q) ?? false);
      }).toList();
    }
    result = result
        .where((c) => switch (_filter) {
              _StatusFilter.all => true,
              _StatusFilter.success => c.state == SamseerCallState.success,
              _StatusFilter.redirect => c.state == SamseerCallState.redirect,
              _StatusFilter.clientError =>
                c.state == SamseerCallState.clientError,
              _StatusFilter.serverError =>
                c.state == SamseerCallState.serverError,
              _StatusFilter.errors =>
                c.state == SamseerCallState.error || c.hasError,
            })
        .toList();
    return result;
  }
}

class _AnimatedTile extends StatefulWidget {
  const _AnimatedTile({super.key, required this.child});
  final Widget child;

  @override
  State<_AnimatedTile> createState() => _AnimatedTileState();
}

class _AnimatedTileState extends State<_AnimatedTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    final curve =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _fade = Tween<double>(begin: 0, end: 1).animate(curve);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(curve);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Search by URL, method, status…',
          prefixIcon: Icon(Icons.search),
          isDense: true,
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onSelected});
  final _StatusFilter selected;
  final ValueChanged<_StatusFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    Widget chip(_StatusFilter f, String label) {
      final isSelected = selected == f;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: isSelected,
          onSelected: (_) => onSelected(f),
          elevation: 0,
          pressElevation: 0,
          shadowColor: Colors.transparent,
          selectedShadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          side: BorderSide.none,
          shape: const StadiumBorder(side: BorderSide.none),
          labelStyle: TextStyle(
            color: isSelected
                ? Theme.of(context).colorScheme.onPrimary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          chip(_StatusFilter.all, 'All'),
          chip(_StatusFilter.success, '2xx'),
          chip(_StatusFilter.redirect, '3xx'),
          chip(_StatusFilter.clientError, '4xx'),
          chip(_StatusFilter.serverError, '5xx'),
          chip(_StatusFilter.errors, 'Errors'),
        ],
      ),
    );
  }
}
