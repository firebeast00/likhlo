import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n/app_strings.dart';
import '../services/voice_diagnostics_service.dart';

String _label(String key) => AppStrings.current.text('diagnostics_$key');

class VoiceDiagnosticsScreen extends StatefulWidget {
  final VoiceDiagnosticsService? service;
  const VoiceDiagnosticsScreen({super.key, this.service});
  @override
  State<VoiceDiagnosticsScreen> createState() => _VoiceDiagnosticsScreenState();
}

class _VoiceDiagnosticsScreenState extends State<VoiceDiagnosticsScreen> {
  late final service = widget.service ?? VoiceDiagnosticsService.instance;
  final selected = <String>{};
  bool selecting = false;
  String filter = 'all';
  String period = 'all';

  @override
  void initState() {
    super.initState();
    service.addListener(_refresh);
    service.initialize();
  }
  void _refresh() { if (mounted) setState(() {}); }
  @override
  void dispose() { service.removeListener(_refresh); super.dispose(); }

  Future<void> _enable(bool value) async {
    if (value) {
      final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
        title: Text(_label('enable')),
        content: Text(_label('consent')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_label('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_label('enable'))),
        ],
      ));
      if (accepted != true) return;
    }
    try { await service.setEnabled(value); } catch (_) { _error(); }
  }

  void _error() {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_label('error'))));
  }

  List<Map<String, dynamic>> _visible() {
    final now = DateTime.now();
    return service.summaries.where((r) {
      if (period != 'all' && now.difference(DateTime.parse(r['started_at'] as String)).inDays >= int.parse(period)) return false;
      if (filter == 'issues') return r['review']['assessment'] == 'wrong' ||
          VoiceDiagnosticsService.terminalOutcomes.contains(r['outcome']) && r['outcome'] != 'completed';
      if (filter == 'unreviewed') return r['review']['assessment'] == 'unreviewed';
      return filter == 'all' || r['outcome'] == filter;
    }).toList();
  }

  Future<void> _clear() async {
    final accepted = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(_label('clear')), content: Text(_label('clear_confirm')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_label('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_label('clear')))],
    ));
    if (accepted == true) { await service.clear(); selected.clear(); _refresh(); }
  }

  Iterable<String> _knownNames() sync* {
    // Only existing labels; no new device identifier or contacts access.
    for (final boxName in ['wallets', 'debts']) {
      if (!Hive.isBoxOpen(boxName)) continue;
      for (final dynamic entry in Hive.box(boxName).values) {
        try {
          final String name = boxName == 'wallets' ? entry.name : entry.borrowerName;
          if (name.trim().isNotEmpty) yield name;
        } catch (_) {}
      }
    }
  }

  Future<void> _export() async {
    final visible = _visible();
    final ids = visible.map((r) => r['id'] as String).where((id) => !selecting || selected.contains(id)).toList();
    if (ids.isEmpty) return;
    await service.flush();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _DiagnosticExportScreen(
      service: service, ids: ids, names: _knownNames().toList(),
    )));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible();
    return Scaffold(
      appBar: AppBar(title: Text(_label('title')), actions: [IconButton(
        tooltip: _label('clear'), onPressed: service.recordCount == 0 ? null : _clear, icon: const Icon(Icons.delete_outline)),
      ]),
      body: Column(children: [
        SwitchListTile(title: Text(_label('capture')), subtitle: Text(_label('local_only')),
          value: service.enabled, onChanged: _enable),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6), child: Text(_label('retention'))),
        if (service.storageError != null) Padding(padding: const EdgeInsets.all(12), child: Text(_label('storage_error'), style: TextStyle(color: Theme.of(context).colorScheme.error))),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          Expanded(child: DropdownButton<String>(isExpanded: true, value: filter,
            items: ['all', 'issues', 'unreviewed', ...VoiceDiagnosticsService.terminalOutcomes, 'awaiting_confirmation']
                .map((v) => DropdownMenuItem(value: v, child: Text(_label(v), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) => setState(() { filter = v!; selected.clear(); selecting = false; }))),
          const SizedBox(width: 16),
          Expanded(child: DropdownButton<String>(isExpanded: true, value: period,
            items: ['all', '1', '7', '30'].map((v) => DropdownMenuItem(value: v,
              child: Text(_label(v == 'all' ? 'all_dates' : 'days_$v')))).toList(),
            onChanged: (v) => setState(() { period = v!; selected.clear(); selecting = false; }))),
        ])),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: visible.isEmpty ? null : () => setState(() {
            selecting = true; selected..clear()..addAll(visible.map((r) => r['id'] as String));
          }), child: Text(_label('select_all'))),
          TextButton(onPressed: !selecting ? null : () => setState(() { selecting = false; selected.clear(); }),
            child: Text(_label('use_filtered'))),
        ]),
        Expanded(child: visible.isEmpty ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_label('empty')))) :
          ListView.builder(itemCount: visible.length, itemBuilder: (context, index) {
            final r = visible[index]; final id = r['id'] as String;
            return ListTile(
              leading: Checkbox(value: selected.contains(id), onChanged: (v) => setState(() { selecting = true; if (v == true) { selected.add(id); } else { selected.remove(id); } })),
              title: Text((r['submitted_transcript'] ?? r['raw_transcript']).toString().isEmpty ? _label('no_speech') :
                (r['submitted_transcript'] ?? r['raw_transcript']).toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${_label(r['outcome'] as String)} · ${_label(r['review']['assessment'] as String)}\n${DateTime.parse(r['started_at'] as String).toLocal()}'),
              isThreeLine: true,
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => _DiagnosticReviewScreen(service: service, id: id))),
            );
          })),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: SizedBox(width: double.infinity,
          child: FilledButton.icon(onPressed: visible.isEmpty || selecting && selected.isEmpty ? null : _export,
            icon: const Icon(Icons.ios_share), label: Text(_label(selecting ? 'export_selected' : 'export_visible')))))),
      ]),
    );
  }
}

class _DiagnosticReviewScreen extends StatefulWidget {
  final VoiceDiagnosticsService service;
  final String id;
  const _DiagnosticReviewScreen({required this.service, required this.id});
  @override
  State<_DiagnosticReviewScreen> createState() => _DiagnosticReviewScreenState();
}

class _DiagnosticReviewScreenState extends State<_DiagnosticReviewScreen> {
  late final initial = widget.service.record(widget.id)!;
  late String assessment = initial['review']['assessment'] as String;
  late String failureStage = initial['review']['failure_stage'] as String? ?? 'unsure';
  late final spoken = TextEditingController(text: initial['review']['actually_spoken'] as String? ?? '');
  late final expected = TextEditingController(text: initial['review']['expected_result'] as String? ?? '');
  late final notes = TextEditingController(text: initial['review']['notes'] as String? ?? '');
  @override
  void dispose() { spoken.dispose(); expected.dispose(); notes.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final record = widget.service.record(widget.id) ?? initial;
    return Scaffold(appBar: AppBar(title: Text(_label('review'))), body: ListView(padding: const EdgeInsets.all(16), children: [
      Text(_label('review_hint')),
      const SizedBox(height: 16),
      Wrap(spacing: 8, children: ['correct', 'wrong', 'unsure'].map((v) => ChoiceChip(
        label: Text(_label(v)), selected: assessment == v, onSelected: (_) => setState(() => assessment = v))).toList()),
      DropdownButtonFormField<String>(initialValue: failureStage,
        decoration: InputDecoration(labelText: _label('failure_stage')),
        items: ['unsure', 'recognition', 'normalization', 'parse', 'execution', 'tts'].map((v) => DropdownMenuItem(value: v, child: Text(_label(v)))).toList(),
        onChanged: (v) => failureStage = v!),
      TextField(controller: spoken, maxLines: 2, maxLength: VoiceDiagnosticsService.maxTextLength, decoration: InputDecoration(labelText: _label('actually_spoken'))),
      TextField(controller: expected, maxLines: 3, maxLength: VoiceDiagnosticsService.maxTextLength, decoration: InputDecoration(labelText: _label('expected'))),
      TextField(controller: notes, maxLines: 2, maxLength: VoiceDiagnosticsService.maxTextLength, decoration: InputDecoration(labelText: _label('notes'))),
      FilledButton(onPressed: () async {
        await widget.service.review(widget.id, assessment: assessment, failureStage: failureStage == 'unsure' ? null : failureStage,
          spoken: spoken.text, expected: expected.text, notes: notes.text);
        if (context.mounted) Navigator.pop(context);
      }, child: Text(_label('save_review'))),
      const SizedBox(height: 16),
      for (final key in ['raw_transcript', 'submitted_transcript', 'context', 'normalization', 'parse', 'confidence', 'execution', 'response', 'tts', 'events'])
        if (record[key] != null) ExpansionTile(title: Text(_label(key)), children: [
          Padding(padding: const EdgeInsets.all(12), child: SelectableText(const JsonEncoder.withIndent('  ').convert(record[key]), style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        ]),
    ]));
  }
}

class _DiagnosticExportScreen extends StatefulWidget {
  final VoiceDiagnosticsService service;
  final List<String> ids;
  final List<String> names;
  const _DiagnosticExportScreen({required this.service, required this.ids, required this.names});
  @override
  State<_DiagnosticExportScreen> createState() => _DiagnosticExportScreenState();
}

class _DiagnosticExportScreenState extends State<_DiagnosticExportScreen> {
  bool mask = true;
  bool busy = false;
  String json = '';
  int generation = 0;
  @override
  void initState() { super.initState(); _prepare(); }
  Future<void> _prepare() async {
    final attempt = ++generation;
    setState(() => busy = true);
    final report = widget.service.export(ids: widget.ids, maskNames: mask, deferMasking: true, additionalNames: widget.names);
    final result = await compute(encodeVoiceDiagnosticExport, report);
    if (mounted && attempt == generation) setState(() { json = result; busy = false; });
  }
  Future<void> _send(bool share) async {
    setState(() => busy = true);
    try {
      final bytes = Uint8List.fromList(utf8.encode(json));
      final name = 'likhlo-nlp-${DateTime.now().toUtc().millisecondsSinceEpoch}.json';
      if (share) {
        final box = context.findRenderObject() as RenderBox?;
        await Share.shareXFiles([XFile.fromData(bytes, mimeType: 'application/json')], fileNameOverrides: [name],
          subject: 'Likhlo NLP diagnostics', sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size);
      } else {
        await FilePicker.platform.saveFile(dialogTitle: _label('save_json'), fileName: name,
          type: FileType.custom, allowedExtensions: ['json'], bytes: bytes);
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_label('error'))));
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(_label('preview'))), body: Column(children: [
    SwitchListTile(title: Text(_label('mask')), subtitle: Text(_label('mask_hint')), value: mask,
      onChanged: busy ? null : (v) { mask = v; _prepare(); }),
    Padding(padding: const EdgeInsets.all(12), child: Text(_label('preview_hint'))),
    Expanded(child: busy ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(padding: const EdgeInsets.all(16),
      child: SelectableText(json, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)))),
    SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
      Expanded(child: OutlinedButton(onPressed: busy ? null : () => _send(false), child: Text(_label('save_json')))),
      const SizedBox(width: 12), Expanded(child: FilledButton(onPressed: busy ? null : () => _send(true), child: Text(_label('share_json')))),
    ]))),
  ]));
}
