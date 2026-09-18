import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/app_theme.dart';
import '../../models/schedule.dart';
import '../../providers/schedule_provider.dart';

class AddEditScheduleScreen extends StatefulWidget {
  final Schedule? existing;
  const AddEditScheduleScreen({super.key, this.existing});

  @override
  State<AddEditScheduleScreen> createState() => _AddEditScheduleScreenState();
}

class _AddEditScheduleScreenState extends State<AddEditScheduleScreen> {
  final _nameCtrl = TextEditingController();
  List<int> _selectedDays = [];
  TimeOfDay _selectedTime = TimeOfDay.now();
  int _duration = 20; // minutos

  bool _loading = false;
  bool get _isEditing => widget.existing != null;

  static const _dayLabels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
  static const _dayFull = [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final s = widget.existing!;
      _nameCtrl.text = s.name;
      _selectedDays = List.from(s.days);
      _selectedTime = TimeOfDay(hour: s.startHour, minute: s.startMinute);
      _duration = s.durationMinutes;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppTheme.primary,
            surface: AppTheme.bgCard,
            onSurface: AppTheme.textPrimary,
          ),
          dialogBackgroundColor: AppTheme.bgSecondary,
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack('Ingresa un nombre para la programación');
      return;
    }
    if (_selectedDays.isEmpty) {
      _showSnack('Selecciona al menos un día');
      return;
    }

    setState(() => _loading = true);
    final provider = context.read<ScheduleProvider>();

    if (_isEditing) {
      final updated = widget.existing!.copyWith(
        name: _nameCtrl.text.trim(),
        days: _selectedDays,
        startHour: _selectedTime.hour,
        startMinute: _selectedTime.minute,
        durationMinutes: _duration,
      );
      await provider.updateSchedule(updated);
    } else {
      final s = provider.buildNew(
        name: _nameCtrl.text.trim(),
        days: _selectedDays,
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        duration: _duration,
      );
      await provider.addSchedule(s);
    }

    if (mounted) Navigator.pop(context);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  String get _timeDisplay {
    final h = _selectedTime.hour.toString().padLeft(2, '0');
    final m = _selectedTime.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _durationDisplay {
    if (_duration < 60) return '$_duration min';
    final h = _duration ~/ 60;
    final m = _duration % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.bgPrimary,
        title: Text(_isEditing ? 'Editar programación' : 'Nueva programación'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: const Text('Guardar',
                style: TextStyle(
                    color: AppTheme.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nombre
            _sectionTitle('Nombre'),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: 'Ej: Riego matutino',
                prefixIcon: Icon(Icons.label_outline_rounded),
              ),
            ),

            const SizedBox(height: 28),

            // Días
            _sectionTitle('Días de riego'),
            const SizedBox(height: 12),
            _DaySelector(
              selected: _selectedDays,
              onChanged: (days) => setState(() => _selectedDays = days),
            ),

            const SizedBox(height: 12),

            // Presets de días rápidos
            Wrap(
              spacing: 8,
              children: [
                _QuickChip(
                  label: 'Todos',
                  onTap: () => setState(
                      () => _selectedDays = List.generate(7, (i) => i)),
                ),
                _QuickChip(
                  label: 'Lun–Vie',
                  onTap: () =>
                      setState(() => _selectedDays = [0, 1, 2, 3, 4]),
                ),
                _QuickChip(
                  label: 'Fin de semana',
                  onTap: () =>
                      setState(() => _selectedDays = [5, 6]),
                ),
                _QuickChip(
                  label: 'Ninguno',
                  onTap: () => setState(() => _selectedDays = []),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Hora
            _sectionTitle('Hora de inicio'),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _pickTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 18),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        color: AppTheme.textSecondary, size: 20),
                    const SizedBox(width: 14),
                    Text(
                      _timeDisplay,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right_rounded,
                        color: AppTheme.textMuted),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Duración
            _sectionTitle('Duración: $_durationDisplay'),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Column(
                children: [
                  Slider(
                    value: _duration.toDouble(),
                    min: 5,
                    max: 120,
                    divisions: 23,
                    activeColor: AppTheme.primary,
                    inactiveColor: AppTheme.divider,
                    label: _durationDisplay,
                    onChanged: (v) =>
                        setState(() => _duration = v.round()),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text('5 min',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 11)),
                        Text('2 horas',
                            style: TextStyle(
                                color: AppTheme.textMuted, fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Presets de duración
            Wrap(
              spacing: 8,
              children: [10, 15, 20, 30, 45, 60].map((d) {
                final label = d < 60 ? '$d min' : '${d ~/ 60}h';
                return _QuickChip(
                  label: label,
                  selected: _duration == d,
                  onTap: () => setState(() => _duration = d),
                );
              }).toList(),
            ),

            const SizedBox(height: 40),

            // Botón guardar
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _save,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEditing
                        ? 'Guardar cambios'
                        : 'Crear programación'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      );
}

// ══════════════════════════════════════════════════════════════════════════════
// Selector de días
// ══════════════════════════════════════════════════════════════════════════════
class _DaySelector extends StatelessWidget {
  final List<int> selected;
  final ValueChanged<List<int>> onChanged;

  static const _labels = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  const _DaySelector({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(7, (i) {
        final isSelected = selected.contains(i);
        return GestureDetector(
          onTap: () {
            final updated = List<int>.from(selected);
            if (isSelected) {
              updated.remove(i);
            } else {
              updated.add(i);
              updated.sort();
            }
            onChanged(updated);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? AppTheme.primary
                  : AppTheme.bgCard,
              border: Border.all(
                color: isSelected ? AppTheme.primary : AppTheme.divider,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                _labels[i],
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

// Chip rápido
class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool selected;

  const _QuickChip({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary.withOpacity(0.2)
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppTheme.primary : AppTheme.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.primary : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
