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

/// Adds another pet to the household after setup.
class AddPetScreen extends StatefulWidget {
  const AddPetScreen({super.key});

  @override
  State<AddPetScreen> createState() => _AddPetScreenState();
}

class _AddPetScreenState extends State<AddPetScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _weight = TextEditingController();
  Species _species = Species.dog;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _error = null));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final care = context.read<CareRepository>();
      if (!care.canAddPet) {
        AppLog.event('pet.add.blocked', {'source': 'add_pet_screen'});
        context.go(AppRoutes.paywall);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    final nameError = PetFormValidation.nameError(_name.text);
    final weightError = PetFormValidation.weightError(_weight.text);
    if (nameError != null || weightError != null) {
      setState(() => _error = nameError ?? weightError);
      return;
    }
    setState(() => _busy = true);
    final care = context.read<CareRepository>();
    final id = await care.addPet(
      name: _name.text,
      species: _species,
      ageYears: int.tryParse(_age.text.trim()) ?? 0,
      weightKg: PetLimits.parseWeightKg(_weight.text) ?? 0,
    );
    if (!mounted) return;
    if (id == null) {
      AppLog.event('pet.add.ui_failed', {
        'error': care.lastError ?? 'unknown',
      });
      setState(() {
        _busy = false;
        _error = care.lastError ?? 'Could not save. Try again.';
      });
      return;
    }
    AppLog.event('pet.add.ui_success', {'petId': id, 'species': _species.name});
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('${_name.text.trim()} was added.'),
        action: SnackBarAction(
          label: 'Add medicine',
          onPressed: () => router.push('${AppRoutes.schedule}?pet=$id'),
        ),
      ),
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

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back',
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.pets),
                    icon: StrokeIcon(
                      StrokeIconKind.chevronLeft,
                      color: scheme.onSurface,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Add a pet',
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
                    autofocus: true,
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
                    onChanged: (value) => setState(() => _species = value),
                  ),
                  const SizedBox(height: 20),
                  PetAgeWeightFields(age: _age, weight: _weight),
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
                        : const Text('Save pet'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
