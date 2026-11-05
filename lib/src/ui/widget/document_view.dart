import 'package:flutter/material.dart';

import '../../feature/text_export.dart';
import '../text/body_document.dart';
import 'body_text_sliver.dart';
import 'export_text_button.dart';

/// Scrollable tab content with the copy/download button pinned below it, so
/// the button stays reachable on bodies with thousands of lines. The
/// scrollbar thumb can be dragged to jump through very long bodies.
class BodyScrollLayout extends StatefulWidget {
  const BodyScrollLayout({
    super.key,
    required this.slivers,
    required this.button,
  });
  final List<Widget> slivers;
  final Widget button;

  @override
  State<BodyScrollLayout> createState() => _BodyScrollLayoutState();
}

class _BodyScrollLayoutState extends State<BodyScrollLayout> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SelectionArea(
            child: Scrollbar(
              controller: _scroll,
              interactive: true,
              child: CustomScrollView(
                controller: _scroll,
                slivers: [
                  ...widget.slivers,
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: widget.button,
          ),
        ),
      ],
    );
  }
}

class DocumentSectionTitle extends StatelessWidget {
  const DocumentSectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Header slivers, then a body rendered from [future] as virtualized rows,
/// with an [ExportTextButton] fed by the loaded document.
class DocumentView extends StatelessWidget {
  const DocumentView({
    super.key,
    this.header = const [],
    this.title,
    required this.future,
    required this.fallback,
    required this.copyLabel,
    required this.fileName,
    required this.copiedTitle,
    this.limitBytes = kCopyLimitBytes,
  });

  final List<Widget> header;
  final String? title;
  final Future<BodyDocument> future;
  final BodyDocument? Function() fallback;
  final String copyLabel;
  final String fileName;
  final String copiedTitle;

  /// Copy limit in UTF-8 bytes; larger text is downloaded instead.
  final int limitBytes;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<BodyDocument>(
      key: ObjectKey(future),
      future: future,
      builder: (context, snap) {
        final cs = Theme.of(context).colorScheme;
        final loaded = snap.hasData ? snap.data : null;
        var exportDoc = loaded;
        final Widget body;
        if (snap.hasError) {
          exportDoc = fallback();
          body = const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Could not render body',
                style: TextStyle(color: Color(0xFFEF4444)),
              ),
            ),
          );
        } else if (loaded == null) {
          body = const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(),
            ),
          );
        } else {
          body = SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: DecoratedSliver(
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
              ),
              sliver: SliverPadding(
                padding: const EdgeInsets.all(14),
                sliver: BodyTextSliver(document: loaded),
              ),
            ),
          );
        }
        final heading = title;
        return BodyScrollLayout(
          slivers: [
            ...header,
            if (heading != null)
              SliverToBoxAdapter(
                child: DocumentSectionTitle(
                  loaded == null
                      ? heading
                      : '$heading · ${loaded.lineCount} lines',
                ),
              ),
            body,
          ],
          button: ExportTextButton(
            copyLabel: copyLabel,
            document: exportDoc,
            fileName: fileName,
            copiedTitle: copiedTitle,
            limitBytes: limitBytes,
          ),
        );
      },
    );
  }
}
