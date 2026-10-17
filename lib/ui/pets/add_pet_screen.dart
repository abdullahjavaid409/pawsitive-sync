import 'package:flutter/material.dart';
import 'package:pawsitive_sync/core/widgets/care_widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:pawsitive_sync/core/constants/pet_limits.dart';
import 'package:pawsitive_sync/core/routing/routes.dart';
import 'package:pawsitive_sync/core/widgets/post_frame.dart';
import 'package:pawsitive_sync/core/widgets/paws_widgets.dart';
import 'package:pawsitive_sync/data/care_repository.dart';
import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/pets/widgets/pet_form_sections.dart';
import 'package:provider/provider.dart';
import 'package:pawsitive_sync/core/widgets/system_menu.dart';

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

  /// Unpicked until tapped: we don't guess the kind of pet.
  Species? _species;
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
        // billing.paywall.opened from=add_pet_screen.
        context.go(
          AppRoutes.paywallWith(reason: 'second_pet', from: 'add_pet_screen'),
        );
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
    final ageError = PetFormValidation.ageError(_age.text);
    final weightError = PetFormValidation.weightError(_weight.text);
    final speciesError = _species == null
        ? 'Pick cat, dog, rabbit or other.'
        : null;
    if (nameError != null ||
        speciesError != null ||
        ageError != null ||
        weightError != null) {
      setState(
        () => _error = nameError ?? speciesError ?? ageError ?? weightError,
      );
      return;
    }
    setState(() => _busy = true);
    final care = context.read<CareRepository>();
    final id = await care.addPet(
      name: _name.text,
      species: _species!,
      ageYears: int.tryParse(_age.text.trim()) ?? 0,
      weightKg: PetLimits.parseWeightKg(_weight.text) ?? 0,
    );
    if (!mounted) return;
    // pet.add.completed / rejected / blocked are logged by the repository.
    if (id == null) {
      setState(() {
        _busy = false;
        _error = care.lastError ?? 'Could not save. Try again.';
      });
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final voiceOver = MediaQuery.accessibleNavigationOf(context);
    messenger.showSnackBar(
      SnackBar(
        // Flutter keeps a toast with an action until it's dismissed; this
        // one closes itself (VoiceOver users keep it to reach the button).
        persist: voiceOver,
        duration: const Duration(seconds: 6),
        content: Text('${_name.text.trim()} was added.'),
        action: SnackBarAction(
          label: 'Add medicine',
          onPressed: () => router.push('${AppRoutes.schedule}?pet=$id'),
        ),
      ),
    );
    afterThisFrame(context, () {
      if (context.canPop()) {
        // The new id, so Pets switches to the pet just added.
        context.pop(id);
      } else {
        context.go(AppRoutes.pets);
      }
    });
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
                  // Shared back button: caret on the content edge.
                  const CareBackButton(fallbackRoute: AppRoutes.pets),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  const FieldLabel('Name'),
                  TextField(
                    contextMenuBuilder: appContextMenuBuilder,
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
                  const FieldLabel('Species'),
                  PetSpeciesPicker(
                    species: _species,
                    onChanged: (value) => setState(() {
                      _species = value;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 20),
                  PetAgeWeightFields(age: _age, weight: _weight),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
