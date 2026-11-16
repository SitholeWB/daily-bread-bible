import 'package:flutter/material.dart';
import '../models/bible_models.dart';
import '../services/bible_repository.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';

class SettingsPage extends StatefulWidget {
  final BibleRepository repo;
  final StorageService storage;
  final NotificationService notifications;
  final VoidCallback onThemeChanged;
  final VoidCallback onReadingSettingsChanged;
  final VoidCallback onOpenPacks;
  final VoidCallback onExportBackup;
  final VoidCallback onOpenFeedback;
  final VoidCallback onClose;

  const SettingsPage({
    super.key,
    required this.repo,
    required this.storage,
    required this.notifications,
    required this.onThemeChanged,
    required this.onReadingSettingsChanged,
    required this.onOpenPacks,
    required this.onExportBackup,
    required this.onOpenFeedback,
    required this.onClose,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _primaryLanguage;
  bool _downloadingTranslation = false;

  @override
  void initState() {
    super.initState();
    _syncLanguageFromTranslation();
  }

  Future<void> _selectOrDownloadPrimary(TranslationInfo info) async {
    if (!widget.repo.isTranslationAvailable(info.id)) {
      setState(() => _downloadingTranslation = true);
      try {
        await widget.repo.downloadTranslation(info);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to download ${info.shortName}: $e')),
          );
        }
        if (mounted) setState(() => _downloadingTranslation = false);
        return;
      }
      if (mounted) setState(() => _downloadingTranslation = false);
    }
    setState(() => widget.storage.translationId = info.id);
    await widget.storage.save();
    widget.onReadingSettingsChanged();
  }

  void _syncLanguageFromTranslation() {
    final active = widget.repo.catalog
        .where((t) => t.id == widget.storage.translationId)
        .toList();
    _primaryLanguage =
        active.isNotEmpty ? active.first.language : 'English';
  }

  String _formatInterval(int totalMinutes) {
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  Future<void> _setIntervalMinutes(int minutes) async {
    final clamped = minutes.clamp(1, 1440);
    setState(() {
      widget.storage.rotationIntervalMinutes = clamped;
    });
    await widget.storage.save();
  }

  Future<void> _addScheduledTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    if (!widget.storage.scheduledTimes.contains(formatted)) {
      setState(() {
        widget.storage.scheduledTimes = [
          ...widget.storage.scheduledTimes,
          formatted,
        ]..sort();
      });
      await widget.storage.save();
    }
  }

  Future<void> _editScheduledTime(String oldTime) async {
    final parts = oldTime.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      final updated = [...widget.storage.scheduledTimes]..remove(oldTime);
      if (!updated.contains(formatted)) updated.add(formatted);
      updated.sort();
      widget.storage.scheduledTimes = updated;
    });
    await widget.storage.save();
  }

  Future<void> _removeScheduledTime(String time) async {
    if (widget.storage.scheduledTimes.length <= 1) return;
    setState(() {
      widget.storage.scheduledTimes =
          widget.storage.scheduledTimes.where((t) => t != time).toList();
    });
    await widget.storage.save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allLanguages = widget.repo.getAvailableLanguages();
    final langCounts = <String, int>{};
    for (final t in widget.repo.catalog) {
      langCounts[t.language] = (langCounts[t.language] ?? 0) + 1;
    }
    if (!allLanguages.contains(_primaryLanguage) && allLanguages.isNotEmpty) {
      _primaryLanguage = allLanguages.first;
    }

    final translationsForLang = widget.repo.catalog
        .where((t) => t.language == _primaryLanguage)
        .toList();
    final selectedTranslation = translationsForLang
            .where((t) => t.id == widget.storage.translationId)
            .isNotEmpty
        ? widget.storage.translationId
        : null;

    final intervalHours = widget.storage.rotationIntervalMinutes ~/ 60;
    final intervalMins = widget.storage.rotationIntervalMinutes % 60;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          color: theme.colorScheme.surface,
          child: Row(
            children: [
              Icon(Icons.settings_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                'Settings',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: widget.onClose,
                icon: const Icon(Icons.menu_book_outlined, size: 17),
                label: const Text('Back to Reader'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SectionCard(
                      title: 'Appearance & Reading',
                      icon: Icons.palette_outlined,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Theme Mode',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            SegmentedButton<ThemeMode>(
                              segments: const [
                                ButtonSegment(
                                  value: ThemeMode.system,
                                  label: Text('System'),
                                  icon: Icon(Icons.brightness_auto, size: 16),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.light,
                                  label: Text('Light'),
                                  icon: Icon(Icons.light_mode, size: 16),
                                ),
                                ButtonSegment(
                                  value: ThemeMode.dark,
                                  label: Text('Dark'),
                                  icon: Icon(Icons.dark_mode, size: 16),
                                ),
                              ],
                              selected: {widget.storage.themeMode},
                              onSelectionChanged: (sel) async {
                                widget.storage.themeMode = sel.first;
                                await widget.storage.save();
                                widget.onThemeChanged();
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Text(
                              'Reader Font Size (${widget.storage.fontSize.round()} px)',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Expanded(
                              child: Slider(
                                min: 13,
                                max: 28,
                                divisions: 15,
                                value: widget.storage.fontSize,
                                onChanged: (v) async {
                                  setState(() => widget.storage.fontSize = v);
                                  await widget.storage.save();
                                  widget.onReadingSettingsChanged();
                                },
                              ),
                            ),
                          ],
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Show Daily Bread Verse Banner'),
                          subtitle: const Text(
                              'Display the active scheduled verse at the top of the reader.'),
                          value: widget.storage.showDailyBanner,
                          onChanged: (v) async {
                            setState(() => widget.storage.showDailyBanner = v);
                            await widget.storage.save();
                            widget.onReadingSettingsChanged();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Language & Bible Translations',
                      icon: Icons.translate,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue:
                                    allLanguages.contains(_primaryLanguage)
                                        ? _primaryLanguage
                                        : null,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText:
                                      '1. Select Language (${allLanguages.length})',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: allLanguages
                                    .map((lang) => DropdownMenuItem(
                                          value: lang,
                                          child: Text(
                                              '$lang (${langCounts[lang] ?? 0})'),
                                        ))
                                    .toList(),
                                onChanged: _downloadingTranslation
                                    ? null
                                    : (lang) async {
                                        if (lang == null) return;
                                        setState(() => _primaryLanguage = lang);
                                        final downloadedMatch = widget
                                            .repo.availableTranslations
                                            .where((t) => t.language == lang)
                                            .toList();
                                        if (downloadedMatch.isNotEmpty &&
                                            !downloadedMatch.any((t) =>
                                                t.id ==
                                                widget.storage.translationId)) {
                                          widget.storage.translationId =
                                              downloadedMatch.first.id;
                                          await widget.storage.save();
                                          widget.onReadingSettingsChanged();
                                        }
                                      },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: selectedTranslation,
                                isExpanded: true,
                                hint: const Text('Choose translation...'),
                                decoration: InputDecoration(
                                  labelText:
                                      '2. Available Translation (${translationsForLang.length})',
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                  suffixIcon: _downloadingTranslation
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                        )
                                      : null,
                                ),
                                items: translationsForLang.map((t) {
                                  final isOffline = widget.repo
                                      .isTranslationAvailable(t.id);
                                  final suffix = isOffline
                                      ? 'Offline'
                                      : 'Download ${(t.sizeKB / 1024).toStringAsFixed(1)} MB';
                                  return DropdownMenuItem(
                                    value: t.id,
                                    child: Text(
                                      '${t.shortName} — ${t.name} ($suffix)',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  );
                                }).toList(),
                                onChanged: _downloadingTranslation
                                    ? null
                                    : (id) async {
                                        if (id == null) return;
                                        final info = translationsForLang
                                            .firstWhere((t) => t.id == id);
                                        await _selectOrDownloadPrimary(info);
                                      },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String?>(
                                initialValue: widget.storage.compareTranslationId,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Parallel Comparison Translation',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('None (Single Column)'),
                                  ),
                                  ...widget.repo.availableTranslations.map(
                                    (t) => DropdownMenuItem<String?>(
                                      value: t.id,
                                      child: Text(
                                          '${t.language}: ${t.shortName} — ${t.name}'),
                                    ),
                                  ),
                                ],
                                onChanged: (id) async {
                                  setState(() =>
                                      widget.storage.compareTranslationId = id);
                                  await widget.storage.save();
                                  widget.onReadingSettingsChanged();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: widget.onOpenPacks,
                              icon: const Icon(Icons.download_outlined,
                                  size: 17),
                              label: const Text('Manage 60+ Packs'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Verse Rotation & High-Priority Notifications',
                      icon: Icons.notifications_active_outlined,
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Enable Desktop Notifications'),
                          subtitle: const Text(
                              'Send a high-priority desktop notification when the verse changes.'),
                          value: widget.storage.dailyNotificationsEnabled,
                          onChanged: (v) async {
                            setState(() =>
                                widget.storage.dailyNotificationsEnabled = v);
                            await widget.storage.save();
                          },
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                              'High-Priority Notification Alert'),
                          subtitle: const Text(
                              'Use urgent/critical notification priority so Ubuntu displays the new verse prominently.'),
                          value:
                              widget.storage.rotationHighPriorityNotification,
                          onChanged: widget.storage.dailyNotificationsEnabled
                              ? (v) async {
                                  setState(() => widget.storage
                                      .rotationHighPriorityNotification = v);
                                  await widget.storage.save();
                                }
                              : null,
                        ),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          'Schedule Mode',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'manual',
                              label: Text('Manual'),
                              icon: Icon(Icons.touch_app_outlined, size: 16),
                            ),
                            ButtonSegment(
                              value: 'interval',
                              label: Text('Every X Time'),
                              icon: Icon(Icons.timer_outlined, size: 16),
                            ),
                            ButtonSegment(
                              value: 'times',
                              label: Text('Specific Times'),
                              icon: Icon(Icons.schedule_outlined, size: 16),
                            ),
                          ],
                          selected: {widget.storage.scheduleMode},
                          onSelectionChanged: (sel) async {
                            setState(() =>
                                widget.storage.scheduleMode = sel.first);
                            await widget.storage.save();
                          },
                        ),
                        if (widget.storage.scheduleMode == 'interval') ...[
                          const SizedBox(height: 16),
                          Text(
                            'Rotate every ${_formatInterval(widget.storage.rotationIntervalMinutes)}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [5, 15, 30, 60, 120, 240, 360, 720]
                                .map((mins) {
                              final selected =
                                  widget.storage.rotationIntervalMinutes ==
                                      mins;
                              return ChoiceChip(
                                label: Text(_formatInterval(mins)),
                                selected: selected,
                                onSelected: (_) => _setIntervalMinutes(mins),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: intervalHours.clamp(0, 23),
                                  decoration: const InputDecoration(
                                    labelText: 'Custom Hours',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: List.generate(
                                    24,
                                    (h) => DropdownMenuItem(
                                      value: h,
                                      child: Text('$h hr${h == 1 ? '' : 's'}'),
                                    ),
                                  ),
                                  onChanged: (h) {
                                    if (h == null) return;
                                    final total = h * 60 + intervalMins;
                                    _setIntervalMinutes(
                                        total == 0 ? 1 : total);
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  initialValue: intervalMins.clamp(0, 59),
                                  decoration: const InputDecoration(
                                    labelText: 'Custom Minutes',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: List.generate(
                                    60,
                                    (m) => DropdownMenuItem(
                                      value: m,
                                      child: Text('$m min'),
                                    ),
                                  ),
                                  onChanged: (m) {
                                    if (m == null) return;
                                    final total = intervalHours * 60 + m;
                                    _setIntervalMinutes(
                                        total == 0 ? 1 : total);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (widget.storage.scheduleMode == 'times') ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Daily Scheduled Times',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _addScheduledTime,
                                icon: const Icon(Icons.add, size: 17),
                                label: const Text('Add Time'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: widget.storage.scheduledTimes.map((t) {
                              return InputChip(
                                avatar: const Icon(Icons.schedule, size: 16),
                                label: Text(t),
                                onPressed: () => _editScheduledTime(t),
                                onDeleted:
                                    widget.storage.scheduledTimes.length > 1
                                        ? () => _removeScheduledTime(t)
                                        : null,
                              );
                            }).toList(),
                          ),
                        ],
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: widget.storage.rotationTopic == 'all' ||
                                  widget.repo.topics.any((t) =>
                                      t.id == widget.storage.rotationTopic)
                              ? widget.storage.rotationTopic
                              : 'all',
                          decoration: const InputDecoration(
                            labelText: 'Scripture Topic / Mood Filter',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('All Curated Verses'),
                            ),
                            ...widget.repo.topics.map(
                              (t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(t.name),
                              ),
                            ),
                          ],
                          onChanged: (topic) async {
                            if (topic == null) return;
                            setState(
                                () => widget.storage.rotationTopic = topic);
                            await widget.storage.save();
                          },
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonalIcon(
                              onPressed: () async {
                                await widget.notifications.rotateVerseNow(
                                  notify:
                                      widget.storage.dailyNotificationsEnabled,
                                  slotLabel: 'Daily Bread',
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Rotated to next verse!'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.refresh, size: 17),
                              label: const Text('Rotate Verse Now'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final ok = await widget.notifications
                                    .sendTestNotification();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(ok
                                          ? 'Sent high-priority system notification!'
                                          : 'Could not reach desktop notification service.'),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.send_outlined, size: 17),
                              label: const Text('Send Test Notification'),
                            ),
                            if (widget.notifications.unreadCount > 0)
                              OutlinedButton.icon(
                                onPressed: () =>
                                    widget.notifications.clearUnreadBadge(),
                                icon: const Icon(Icons.mark_chat_read_outlined,
                                    size: 17),
                                label: Text(
                                    'Clear Badge (${widget.notifications.unreadCount})'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Backup & Support',
                      icon: Icons.support_agent_outlined,
                      children: [
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: widget.onExportBackup,
                              icon: const Icon(Icons.save_alt, size: 17),
                              label:
                                  const Text('Export Notes & Bookmarks JSON'),
                            ),
                            OutlinedButton.icon(
                              onPressed: widget.onOpenFeedback,
                              icon:
                                  const Icon(Icons.feedback_outlined, size: 17),
                              label: const Text('Send Feedback'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Daily Bread Desktop • v2.0.1 • 100% Offline Core',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
