import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/theme/app_theme.dart';

class PatchNotesScreen extends StatefulWidget {
  const PatchNotesScreen({super.key});

  @override
  State<PatchNotesScreen> createState() => _PatchNotesScreenState();
}

class _PatchNotesScreenState extends State<PatchNotesScreen> {
  static const _assetPath = 'assets/bootstrap/patch_notes.md';

  late final Future<List<_PatchNoteBlock>> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadPatchNotes();
  }

  Future<List<_PatchNoteBlock>> _loadPatchNotes() async {
    final raw = await rootBundle.loadString(_assetPath);
    return _parsePatchNotes(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('패치노트')),
      body: FutureBuilder<List<_PatchNoteBlock>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.live),
            );
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return const _PatchNotesError();
          }

          final blocks = snapshot.data!;
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemBuilder: (context, index) {
              final block = blocks[index];
              return switch (block.kind) {
                _PatchNoteBlockKind.title => _PatchTitle(block.text),
                _PatchNoteBlockKind.section => _PatchSectionTitle(block.text),
                _PatchNoteBlockKind.bullet => _PatchBullet(block.text),
                _PatchNoteBlockKind.paragraph => _PatchParagraph(block.text),
              };
            },
            separatorBuilder: (context, index) {
              final current = blocks[index];
              final next = blocks[index + 1];
              if (next.kind == _PatchNoteBlockKind.section) {
                return const SizedBox(height: 22);
              }
              if (current.kind == _PatchNoteBlockKind.title) {
                return const SizedBox(height: 18);
              }
              return const SizedBox(height: 10);
            },
            itemCount: blocks.length,
          );
        },
      ),
    );
  }
}

List<_PatchNoteBlock> _parsePatchNotes(String raw) {
  final blocks = <_PatchNoteBlock>[];
  for (final line in raw.split('\n')) {
    final text = line.trim();
    if (text.isEmpty) {
      continue;
    }
    if (text.startsWith('# ')) {
      blocks.add(_PatchNoteBlock(_PatchNoteBlockKind.title, text.substring(2)));
    } else if (text.startsWith('## ')) {
      blocks.add(
        _PatchNoteBlock(_PatchNoteBlockKind.section, text.substring(3)),
      );
    } else if (text.startsWith('- ')) {
      blocks.add(
        _PatchNoteBlock(_PatchNoteBlockKind.bullet, text.substring(2)),
      );
    } else {
      blocks.add(_PatchNoteBlock(_PatchNoteBlockKind.paragraph, text));
    }
  }
  return blocks;
}

class _PatchNoteBlock {
  final _PatchNoteBlockKind kind;
  final String text;

  const _PatchNoteBlock(this.kind, this.text);
}

enum _PatchNoteBlockKind { title, section, bullet, paragraph }

class _PatchTitle extends StatelessWidget {
  final String text;

  const _PatchTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w900,
        height: 1.1,
      ),
    );
  }
}

class _PatchSectionTitle extends StatelessWidget {
  final String text;

  const _PatchSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _PatchBullet extends StatelessWidget {
  final String text;

  const _PatchBullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 6, color: AppColors.live),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.42,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PatchParagraph extends StatelessWidget {
  final String text;

  const _PatchParagraph(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        color: AppColors.textSecondary,
        height: 1.45,
      ),
    );
  }
}

class _PatchNotesError extends StatelessWidget {
  const _PatchNotesError();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          '패치노트를 불러올 수 없습니다',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
