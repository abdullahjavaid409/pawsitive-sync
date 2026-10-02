import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/logging/app_log.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/stroke_icon.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/pets/widgets/pet_form_sections.dart';
import 'package:provider/provider.dart';

/// Edits one pet's basics and health conditions after setup.
class EditPetScreen extends StatefulWidget {
  const EditPetScreen({super.key, required this.petId});

  final String petId;

  @override
  State<EditPetScreen> createState() => _EditPetScreenState();
}

class _EditPetScreenState extends State<EditPetScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  late Species _species;
  late Set<String> _conditions;
  bool _busy = false;
  bool _dirty = false;
  String? _error;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    final pet = context.read<CareRepository>().tryPetById(widget.petId);
    if (pet == null) {
      _missing = true;
      _species = Species.cat;
      _conditions = {};
      AppLog.event('pet.edit.missing', {'petId': widget.petId});
      return;
    }
    _name.text = pet.name;
    _age.text = pet.ageYears > 0 ? '${pet.ageYears}' : '';
    _weight.text = pet.weightKg > 0 ? '${pet.weightKg}' : '';
    _species = pet.species;
    _conditions = {...pet.conditions};
    _name.addListener(_markDirty);
    _age.addListener(_markDirty);
    _weight.addListener(_markDirty);
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
    if (_error != null) setState(() => _error = null);
  }

  Future<bool> _confirmLeave() async {
    if (!_dirty || _busy) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your edits have not been saved yet.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  Future<void> _save() async {
    if (_busy || _missing) return;
    final nameError = PetFormValidation.nameError(_name.text);
    final weightError = PetFormValidation.weightError(_weight.text);
    if (nameError != null || weightError != null) {
      setState(() => _error = nameError ?? weightError);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final care = context.read<CareRepository>();
    final ok = await care.updatePet(
      petId: widget.petId,
      name: _name.text,
      species: _species,
      ageYears: int.tryParse(_age.text.trim()) ?? 0,
      weightKg: PetLimits.parseWeightKg(_weight.text) ?? 0,
      conditions: _conditions.toList(),
    );

    if (!mounted) return;
    if (!ok) {
      AppLog.event('pet.update.ui_failed', {
        'petId': widget.petId,
        'error': care.lastError ?? 'unknown',
      });
      setState(() {
        _busy = false;
        _error = care.lastError ?? 'Could not save. Try again.';
      });
      return;
    }
    AppLog.event('pet.update.ui_success', {'petId': widget.petId});

    _dirty = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_name.text.trim()} was updated.')),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.pets);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (_missing) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pet not found', style: text.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'This pet may have been removed from your household.',
                  style: text.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go(AppRoutes.pets),
                  child: const Text('Back to pets'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_dirty || _busy,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.pets);
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: _busy
                          ? null
                          : () async {
                              if (await _confirmLeave() && context.mounted) {
                                if (context.canPop()) {
                                  context.pop();
                                } else {
                                  context.go(AppRoutes.pets);
                                }
                              }
                            },
                      icon: StrokeIcon(
                        StrokeIconKind.chevronLeft,
                        color: scheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Edit pet',
                        textAlign: TextAlign.center,
                        style: text.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  children: [
                    Text("What's their name?", style: text.headlineSmall),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      maxLength: PetLimits.maxNameLength,
                      decoration: const InputDecoration(
                        hintText: 'Pet name',
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('They are a…', style: text.titleSmall),
                    const SizedBox(height: 8),
                    PetSpeciesPicker(
                      species: _species,
                      onChanged: (value) => setState(() {
                        _species = value;
                        _dirty = true;
                        _error = null;
                      }),
                    ),
                    const SizedBox(height: 20),
                    PetAgeWeightFields(age: _age, weight: _weight),
                    const SizedBox(height: 28),
                    PetConditionsPicker(
                      petName: _name.text,
                      selected: _conditions,
                      onToggle: (name) => setState(() {
                        if (_conditions.contains(name)) {
                          _conditions.remove(name);
                        } else {
                          _conditions.add(name);
                        }
                        _dirty = true;
                        _error = null;
                      }),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: text.bodyMedium?.copyWith(color: scheme.error),
                      ),
                      const SizedBox(height: 8),
                    ],
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save changes'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
