import 'package:pawsitive_sync/domain/models.dart';
import 'package:pawsitive_sync/ui/meds/medicine_forms.dart';

/// Well-known vet medicines searched on the phone first: instant, offline,
/// and no server call. Only when nothing here matches does the name step ask
/// the server (Groq) for more. Names as printed on labels; the form is the
/// usual one and can be changed on the next step. Convenience only — the
/// screen says to follow the vet's instructions.
///
/// One line each: name | form | use | species (c = cat, d = dog, r = rabbit).
const _table = '''
Meloxicam|liquid|Pain & joints|cdr
Metacam|liquid|Pain & joints|cdr
Rimadyl|chew|Pain & joints|d
Galliprant|tablet|Arthritis pain|d
Previcox|chew|Pain & joints|d
Deramaxx|chew|Pain & joints|d
Onsior|tablet|Pain & inflammation|cd
Tramadol|tablet|Pain|cd
Buprenorphine|liquid|Pain|cdr
Solensia|injection|Arthritis pain|c
Librela|injection|Arthritis pain|d
Cytopoint|injection|Itching & allergies|d
Oclacitinib|tablet|Itching & allergies|d
Zenrelia|tablet|Itching & allergies|d
Atopica|capsule|Allergies & skin|cd
Cyclosporine|capsule|Allergies & skin|cd
Prednisone|tablet|Inflammation|d
Dexamethasone|tablet|Inflammation|cd
Budesonide|capsule|Bowel inflammation|cd
Cetirizine|tablet|Allergies|cd
Clavamox|tablet|Infections|cd
Amoxicillin-clavulanate|tablet|Infections|cd
Doxycycline|tablet|Infections|cd
Cephalexin|capsule|Infections|cd
Clindamycin|capsule|Infections|cd
Metronidazole|tablet|Diarrhea & infections|cd
Enrofloxacin|tablet|Infections|cdr
Baytril|tablet|Infections|cdr
Marbofloxacin|tablet|Infections|cd
Veraflox|liquid|Infections|cd
Convenia|injection|Infections|cd
Trimethoprim-sulfa|tablet|Infections|dr
Azithromycin|liquid|Infections|cd
Itraconazole|liquid|Fungal infections|cd
Itrafungol|liquid|Ringworm|c
Terbinafine|tablet|Ringworm|cd
Famciclovir|tablet|Cat flu & eyes|c
Pimobendan|tablet|Heart|d
Vetmedin|chew|Heart|d
Enalapril|tablet|Heart & blood pressure|cd
Benazepril|tablet|Heart & kidneys|cd
Fortekor|tablet|Heart & kidneys|cd
Furosemide|tablet|Fluid & heart|cd
Spironolactone|tablet|Heart|d
Amlodipine|tablet|Blood pressure|c
Semintra|liquid|Blood pressure & kidneys|c
Telmisartan|liquid|Blood pressure & kidneys|c
Clopidogrel|tablet|Blood clots|c
Atenolol|tablet|Heart rhythm|cd
Diltiazem|tablet|Heart rhythm|cd
Sub-Q fluids|injection|Kidney support|cd
Calcitriol|capsule|Kidneys|cd
Mirtazapine|tablet|Appetite|cd
Mirataz|topical|Appetite|c
Elura|liquid|Weight & appetite|c
Entyce|liquid|Appetite|d
Cerenia|tablet|Nausea|cd
Maropitant|tablet|Nausea|cd
Ondansetron|tablet|Nausea|cd
Famotidine|tablet|Stomach acid|cd
Omeprazole|capsule|Stomach acid|cd
Sucralfate|tablet|Stomach ulcers|cd
Lactulose|liquid|Constipation|cd
Cisapride|capsule|Gut movement|cr
Metoclopramide|tablet|Nausea & gut|cdr
Simethicone|liquid|Gas & bloat|r
Critical Care|other|Recovery feeding|r
Proin|chew|Urine leaks|d
Phenylpropanolamine|chew|Urine leaks|d
Incurin|tablet|Urine leaks|d
Prazosin|capsule|Urinary|c
Vetsulin|injection|Diabetes|cd
ProZinc|injection|Diabetes|cd
Caninsulin|injection|Diabetes|cd
Lantus|injection|Diabetes|c
Bexacat|tablet|Diabetes|c
Senvelgo|liquid|Diabetes|c
Felimazole|tablet|Thyroid|c
Methimazole gel|topical|Thyroid|c
Levothyroxine|tablet|Thyroid|d
Thyro-Tabs|tablet|Thyroid|d
Vetoryl|capsule|Cushing’s|d
Trilostane|capsule|Cushing’s|d
Zycortal|injection|Addison’s|d
Percorten-V|injection|Addison’s|d
Fludrocortisone|tablet|Addison’s|d
Phenobarbital|tablet|Seizures|cd
Levetiracetam|tablet|Seizures|cd
Keppra|tablet|Seizures|cd
Zonisamide|capsule|Seizures|d
Potassium bromide|liquid|Seizures|d
Fluoxetine|capsule|Anxiety|cd
Reconcile|chew|Anxiety|d
Clomicalm|tablet|Anxiety|d
Trazodone|tablet|Anxiety & calming|cd
Sileo|other|Noise anxiety|d
Bonqat|liquid|Vet & travel stress|c
Selegiline|tablet|Senior brain health|d
NexGard|chew|Flea & tick|d
NexGard Plus|chew|Flea, tick & worm|d
NexGard Spectra|chew|Flea, tick & worm|d
Simparica|chew|Flea & tick|d
Credelio|chew|Flea & tick|cd
Bravecto|chew|Flea & tick|d
Bravecto Plus|topical|Flea, tick & worm|c
Revolution|topical|Flea & worm|cd
Advantage II|topical|Fleas|cd
Advantage Multi|topical|Flea & heartworm|cd
Frontline Plus|topical|Flea & tick|cd
Seresto|other|Flea & tick collar|cd
Capstar|tablet|Fleas|cd
Heartgard Plus|chew|Heartworm|d
Interceptor Plus|chew|Heartworm & worms|d
Sentinel Spectrum|chew|Heartworm & worms|d
ProHeart 12|injection|Heartworm|d
Drontal|tablet|Worms|cd
Milbemax|tablet|Worms|cd
Profender|topical|Worms|c
Fenbendazole|liquid|Worms|cdr
Panacur|liquid|Worms|cdr
Praziquantel|tablet|Tapeworms|cd
Pyrantel|liquid|Worms|cd
Ponazuril|liquid|Coccidia|cd
Ivermectin|liquid|Mites & worms|dr
Neo-Poly-Dex|drops|Eye inflammation|cd
Tobramycin|drops|Eye infections|cd
Terramycin|drops|Eye infections|cdr
Optimmune|drops|Dry eye|d
Latanoprost|drops|Glaucoma|d
Dorzolamide|drops|Glaucoma|cd
Osurnia|drops|Ear infections|d
Claro|drops|Ear infections|d
Mometamax|drops|Ear infections|d
Otomax|drops|Ear infections|d
Posatex|drops|Ear infections|d
Surolan|drops|Ears & skin|cd
Ursodiol|capsule|Liver & bile|cd
Denamarin|tablet|Liver support|cd
Cobalamin|injection|Vitamin B12|cd
Dasuquin|chew|Joint support|cd
Cosequin|chew|Joint support|cd
FortiFlora|other|Gut health|cd
Fish oil|capsule|Skin & joints|cd
''';

/// Parsed once, on the first search.
final List<CommonMedicine> medicineLibrary = [
  for (final line in _table.trim().split('\n'))
    if (line.split('|') case [final name, final form, final use, final kinds])
      CommonMedicine(name, MedicineForm.values.byName(form), use, {
        if (kinds.contains('c')) Species.cat,
        if (kinds.contains('d')) Species.dog,
        if (kinds.contains('r')) Species.rabbit,
      }),
];
