import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/samseer_core.dart';
import '../../model/console_log.dart';
import '../theme/samseer_theme.dart';
import '../widget/empty_state.dart';
import '../widget/json_viewer.dart';
import '../widget/samseer_toast.dart';

/// Pure filter used by the console list and unit-tested directly.
List<SamseerConsoleLog> applyConsoleFilter(
  List<SamseerConsoleLog> input, {
  String query = '',
  SamseerLogLevel? level,
  SamseerLogSource? source,
}) {
  var result = input;
  if (level != null) {
    result = result.where((l) => l.level == level).toList();
  }
  if (source != null) {
    result = result.where((l) => l.source == source).toList();
  }
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    result = result.where((l) => l.message.toLowerCase().contains(q)).toList();
  }
  return result;
}

String _levelLabel(SamseerLogLevel level) {
  switch (level) {
    case SamseerLogLevel.log:
      return 'Log';
    case SamseerLogLevel.info:
      return 'Info';
    case SamseerLogLevel.warn:
      return 'Warn';
    case SamseerLogLevel.error:
      return 'Error';
    case SamseerLogLevel.debug:
      return 'Debug';
  }
}

String _sourceLabel(SamseerLogSource source) =>
    source == SamseerLogSource.app ? 'App' : 'WebView';

class ConsoleView extends StatefulWidget {
  const ConsoleView({super.key, required this.core});
  final SamseerCore core;

  @override
  State<ConsoleView> createState() => _ConsoleViewState();
}

class _ConsoleViewState extends State<ConsoleView> {
  String _query = '';
  SamseerLogLevel? _level;
  SamseerLogSource? _source;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Search console messages…',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
        ),
        _LevelFilterRow(
          selected: _level,
          onSelected: (l) => setState(() => _level = l),
        ),
        _SourceFilterRow(
          selected: _source,
          onSelected: (s) => setState(() => _source = s),
        ),
        Expanded(
          child: StreamBuilder<List<SamseerConsoleLog>>(
            stream: widget.core.storage.consoleStream,
            initialData: widget.core.storage.consoleLogs,
            builder: (context, snap) {
              final logs = applyConsoleFilter(
                snap.data ?? const [],
                query: _query,
                level: _level,
                source: _source,
              );
              if (logs.isEmpty) {
                return const EmptyState(
                  title: 'No console output yet',
                  subtitle:
                      'App print()/errors and WebView console logs appear here.',
                  icon: Icons.terminal,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                itemCount: logs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) => ConsoleLogTile(
                  log: logs[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ConsoleDetailScreen(log: logs[i]),
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
}

class ConsoleLogTile extends StatelessWidget {
  const ConsoleLogTile({super.key, required this.log, required this.onTap});
  final SamseerConsoleLog log;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = SamseerColors.forLogLevel(log.level);
    final time = DateFormat('HH:mm:ss').format(log.time);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Color.alphaBlend(
            accent.withValues(alpha: 0.05),
            cs.surfaceContainerHigh,
          ),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _levelLabel(log.level).toUpperCase(),
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SourceChip(source: log.source),
                    const Spacer(),
                    Text(
                      time,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 11,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  log.message,
                  style: SamseerTheme.mono(context, size: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source});
  final SamseerLogSource source;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _sourceLabel(source),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _LevelFilterRow extends StatelessWidget {
  const _LevelFilterRow({required this.selected, required this.onSelected});
  final SamseerLogLevel? selected;
  final ValueChanged<SamseerLogLevel?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _Capsule(
            label: 'All',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final level in SamseerLogLevel.values)
            _Capsule(
              label: _levelLabel(level),
              selected: selected == level,
              onTap: () => onSelected(level),
            ),
        ],
      ),
    );
  }
}

class _SourceFilterRow extends StatelessWidget {
  const _SourceFilterRow({required this.selected, required this.onSelected});
  final SamseerLogSource? selected;
  final ValueChanged<SamseerLogSource?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _Capsule(
            label: 'All sources',
            selected: selected == null,
            onTap: () => onSelected(null),
          ),
          for (final source in SamseerLogSource.values)
            _Capsule(
              label: _sourceLabel(source),
              selected: selected == source,
              onTap: () => onSelected(source),
            ),
        ],
      ),
    );
  }
}

class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        elevation: 0,
        pressElevation: 0,
        shadowColor: Colors.transparent,
        selectedShadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        side: BorderSide.none,
        shape: const StadiumBorder(side: BorderSide.none),
        labelStyle: TextStyle(
          color: selected ? cs.onPrimary : cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ConsoleDetailScreen extends StatelessWidget {
  const ConsoleDetailScreen({super.key, required this.log});
  final SamseerConsoleLog log;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = SamseerColors.forLogLevel(log.level);
    return Theme(
      data: SamseerTheme.theme(),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            children: [
              Text(
                _levelLabel(log.level).toUpperCase(),
                style: TextStyle(color: accent, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              _SourceChip(source: log.source),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.content_copy_outlined),
              onPressed: () => _copy(context),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                log.message,
                style: SamseerTheme.mono(context),
              ),
            ),
            if (log.data != null) ...[
              const SizedBox(height: 16),
              Text(
                'DATA',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              for (final item in log.data!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: JsonViewer(value: item),
                  ),
                ),
            ],
            if (log.stackTrace != null) ...[
              const SizedBox(height: 16),
              Text(
                'STACK TRACE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cs.primary,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SelectableText(
                  log.stackTrace!,
                  style: SamseerTheme.mono(context, size: 11),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final buffer = StringBuffer(log.message);
    if (log.stackTrace != null) {
      buffer
        ..write('\n\n')
        ..write(log.stackTrace);
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!context.mounted) return;
    SamseerToast.show(
      context,
      'Console entry copied',
      variant: SamseerToastVariant.success,
    );
  }
}
