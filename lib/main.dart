import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await localDataStore.load(workflow, evidenceStore, caseStore);
  runApp(const PleaGuardApp());
}

const navy = Color(0xFF102A4C);
const ink = Color(0xFF101B33);
const blue = Color(0xFF2563EB);
const teal = Color(0xFF168F83);
const bg = Color(0xFFF4F7FA);
const gold = Color(0xFFC39A4A);

/// State demo lokal. Pada produksi, seluruh transisi, approval, dan audit harus
/// divalidasi API server sesuai policy version dan RBAC.
final workflow = WorkflowController();
final evidenceStore = EvidenceStore();
final localDataStore = LocalDataStore();
final caseStore = CaseStore();

class EvidenceItem {
  EvidenceItem(
      {required this.title,
      required this.category,
      required this.date,
      required this.size,
      this.bytes,
      this.extension,
      this.localPath,
      this.caseId,
      this.sha256});
  final String title, category, date, size;
  final Uint8List? bytes;
  final String? extension;
  final String? localPath;
  final String? caseId;
  final String? sha256;
  bool get isImage =>
      ['jpg', 'jpeg', 'png', 'webp'].contains((extension ?? '').toLowerCase());
  IconData get icon => isImage
      ? Icons.image_outlined
      : category == 'Video'
          ? Icons.play_arrow
          : Icons.picture_as_pdf;
  Color get color => isImage
      ? teal
      : category == 'Video'
          ? Colors.deepPurple
          : Colors.red;

  Map<String, dynamic> toJson() => {
        'title': title,
        'category': category,
        'date': date,
        'size': size,
        'extension': extension,
        'localPath': localPath,
        'caseId': caseId,
        'sha256': sha256,
      };

  factory EvidenceItem.fromJson(Map<String, dynamic> json) => EvidenceItem(
        title: json['title'] as String? ?? 'Bukti tanpa nama',
        category: json['category'] as String? ?? 'Dokumen',
        date: json['date'] as String? ?? '-',
        size: json['size'] as String? ?? '-',
        extension: json['extension'] as String?,
        localPath: json['localPath'] as String?,
        caseId: json['caseId'] as String?,
        sha256: json['sha256'] as String?,
      );
}

class EvidenceStore extends ChangeNotifier {
  final items = <EvidenceItem>[];
  void add(EvidenceItem item) {
    items.insert(0, item);
    notifyListeners();
    unawaited(localDataStore.save(workflow, this));
  }
}

class CaseRecord {
  CaseRecord(
      {required this.id,
      required this.number,
      required this.category,
      required this.law,
      required this.defendant,
      required this.createdAt});
  final String id, number, category, law, defendant;
  final DateTime createdAt;
  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'category': category,
        'law': law,
        'defendant': defendant,
        'createdAt': createdAt.toIso8601String()
      };
  factory CaseRecord.fromJson(Map<String, dynamic> json) => CaseRecord(
      id: json['id'] as String,
      number: json['number'] as String,
      category: json['category'] as String,
      law: json['law'] as String,
      defendant: json['defendant'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now());
}

class CaseStore extends ChangeNotifier {
  final items = <CaseRecord>[];
  String? activeId;
  CaseRecord? get active {
    for (final item in items) {
      if (item.id == activeId) return item;
    }
    return null;
  }

  void add(CaseRecord item) {
    items.insert(0, item);
    activeId = item.id;
    workflow.selectCase(item.id);
    notifyListeners();
    unawaited(localDataStore.save(workflow, evidenceStore));
  }

  void select(CaseRecord item) {
    activeId = item.id;
    workflow.selectCase(item.id);
    notifyListeners();
    unawaited(localDataStore.save(workflow, evidenceStore));
  }
}

class WorkflowController extends ChangeNotifier {
  int _fallbackCurrent = 0;
  String? activeCaseId;
  final stageByCase = <String, int>{};
  int get current => activeCaseId == null
      ? _fallbackCurrent
      : (stageByCase[activeCaseId] ?? 0);
  set current(int value) {
    _fallbackCurrent = value;
    if (activeCaseId != null) stageByCase[activeCaseId!] = value;
  }

  void selectCase(String id) {
    activeCaseId = id;
    recordAudit('Perkara aktif dipilih');
    notifyListeners();
  }

  bool isStoppedFor(String id) => _stoppedCases.contains(id);
  bool isCompletedFor(String id) => _completedCases.contains(id);
  int get stoppedCaseCount => _stoppedCases.length;
  int get completedCaseCount => _completedCases.length;

  final _voluntaryByCase = <String, bool>{};
  bool get voluntary =>
      activeCaseId == null ? false : (_voluntaryByCase[activeCaseId] ?? false);
  set voluntary(bool value) {
    if (activeCaseId != null) _voluntaryByCase[activeCaseId!] = value;
  }

  final _gatePassedByCase = <String, bool>{};
  bool get gatePassed =>
      activeCaseId == null ? false : (_gatePassedByCase[activeCaseId] ?? false);
  set gatePassed(bool value) {
    if (activeCaseId != null) _gatePassedByCase[activeCaseId!] = value;
  }

  final _stoppedCases = <String>{};
  bool get stoppedForStandardProcess =>
      activeCaseId != null && _stoppedCases.contains(activeCaseId);
  set stoppedForStandardProcess(bool value) {
    if (activeCaseId == null) return;
    if (value) {
      _stoppedCases.add(activeCaseId!);
    } else {
      _stoppedCases.remove(activeCaseId);
    }
  }

  final _completedCases = <String>{};
  bool get completed =>
      activeCaseId != null && _completedCases.contains(activeCaseId);
  set completed(bool value) {
    if (activeCaseId == null) return;
    if (value) {
      _completedCases.add(activeCaseId!);
    } else {
      _completedCases.remove(activeCaseId);
    }
  }

  final stageRecords = <String, Map<String, dynamic>>{};
  final restitutionPayments = <String, List<Map<String, dynamic>>>{};
  String _caseKey() => activeCaseId ?? 'tanpa-perkara';
  int get restitutionPaidTotal =>
      (restitutionPayments[_caseKey()] ?? const []).fold(
          0,
          (total, payment) =>
              total + ((payment['amount'] as num?)?.toInt() ?? 0));

  bool restitutionDueMatches(int due) {
    final payments = restitutionPayments[_caseKey()] ?? const [];
    return payments.isEmpty || (payments.first['due'] as num?)?.toInt() == due;
  }

  void recordRestitutionPayment(int amount, int due, String proof,
      {required bool proofVerified, required bool victimConfirmed}) {
    final payments = restitutionPayments.putIfAbsent(_caseKey(), () => []);
    final payment = {
      'amount': amount,
      'due': due,
      'proof': proof,
      'proofVerified': proofVerified,
      'victimConfirmed': victimConfirmed,
      'recordedAt': DateTime.now().toIso8601String(),
      'actor': 'Pengguna Demo'
    };
    payments.add(payment);
    recordAudit('Cicilan restitusi dicatat ${jsonEncode(payment)}');
    unawaited(localDataStore.save(this, evidenceStore));
  }

  final stages = const [
    'SARING · Registrasi & Penyaringan',
    'SINAR · Skor Kelayakan',
    'JANGKAR · Uji Bukti',
    'NURANI · Kesukarelaan',
    'SUARA KORBAN · Dampak & Kebutuhan',
    'TIMBANG · Proporsionalitas',
    'GERBANG · Lima Gerbang Integritas',
    'FORUM VERITAS · Konferensi',
    'AKTA · Kesepakatan',
    'SAMBUNG · Pelimpahan Pengadilan',
    'PUTUSAN · Penetapan Hakim',
    'PULIH · Pemulihan Korban',
    'CAKRAWALA · Kendali Mutu'
  ];
  final audit = <String>[];
  final auditHashes = <String>[];
  bool auditIntegrityValid = true;
  String get auditHead => auditHashes.isEmpty ? 'GENESIS' : auditHashes.last;

  String recordAudit(String action) {
    if (!verifyAudit()) {
      auditIntegrityValid = false;
      return auditHead;
    }
    final now = DateTime.now().toIso8601String();
    final event = '$now | perkara=${activeCaseId ?? "-"} | $action';
    final hash = sha256.convert(utf8.encode('$auditHead|$event')).toString();
    audit.add(event);
    auditHashes.add(hash);
    unawaited(localDataStore.save(this, evidenceStore));
    return hash;
  }

  bool verifyAudit() {
    if (audit.length != auditHashes.length) return false;
    var previous = 'GENESIS';
    for (var i = 0; i < audit.length; i++) {
      previous =
          sha256.convert(utf8.encode('$previous|${audit[i]}')).toString();
      if (previous != auditHashes[i]) return false;
    }
    return true;
  }

  String hashStageRecord(Map<String, dynamic> record) {
    final payload = Map<String, dynamic>.from(record)..remove('recordHash');
    final canonical = jsonEncode(_canonicalize(payload));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return {for (final key in keys) key: _canonicalize(value[key])};
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  bool verifyStageRecords() => stageRecords.values.every((record) =>
      record['recordHash'] != null &&
      record['recordHash'] == hashStageRecord(record));

  void rebuildLegacyAuditChain() {
    auditHashes.clear();
    var previous = 'GENESIS';
    for (final event in audit) {
      previous = sha256.convert(utf8.encode('$previous|$event')).toString();
      auditHashes.add(previous);
    }
    auditIntegrityValid = true;
  }

  void advance(String actor) {
    if (stoppedForStandardProcess ||
        completed ||
        !verifyAudit() ||
        !verifyStageRecords()) {
      return;
    }
    if (current < stages.length - 1) {
      recordAudit('$actor menyelesaikan ${stages[current]}');
      current++;
      recordAudit('Workflow berpindah ke ${stages[current]}');
      notifyListeners();
      unawaited(localDataStore.save(this, evidenceStore));
    } else {
      completed = true;
      recordAudit('$actor menyelesaikan tinjauan mutu CAKRAWALA');
      notifyListeners();
      unawaited(localDataStore.save(this, evidenceStore));
    }
  }

  void returnToStandard(String reason) {
    recordAudit('Plea dihentikan: $reason');
    stoppedForStandardProcess = true;
    notifyListeners();
    unawaited(localDataStore.save(this, evidenceStore));
  }

  void setVoluntary(bool value) {
    voluntary = value;
    recordAudit(
        'Status kesukarelaan NURANI diubah: ${value ? "ya" : "belum/tidak"}');
    notifyListeners();
    unawaited(localDataStore.save(this, evidenceStore));
  }

  void setGatePassed(bool value) {
    gatePassed = value;
    recordAudit(
        'Status lima Gerbang Integritas diubah: ${value ? "lolos" : "belum lolos"}');
    notifyListeners();
    unawaited(localDataStore.save(this, evidenceStore));
  }
}

/// Penyimpanan lokal persisten untuk perangkat. Berkas asli berada di folder
/// Documents aplikasi, dan manifest JSON menyimpan metadata, audit, serta status.
class LocalDataStore {
  static const _manifestName = 'plea_guard_manifest.json';
  Future<void> _saveQueue = Future<void>.value();

  Future<Directory> get _root async {
    final documents = await getApplicationDocumentsDirectory();
    final root = Directory('${documents.path}${Platform.pathSeparator}VERITAS');
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  Future<String> get evidenceDirectory async {
    final root = await _root;
    final evidence = Directory('${root.path}${Platform.pathSeparator}evidence');
    if (!await evidence.exists()) await evidence.create(recursive: true);
    return evidence.path;
  }

  Future<void> load(WorkflowController workflow, EvidenceStore evidence,
      CaseStore cases) async {
    try {
      final root = await _root;
      final manifest =
          File('${root.path}${Platform.pathSeparator}$_manifestName');
      if (!await manifest.exists()) return;
      final data =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;
      final workflowData = data['workflow'] as Map<String, dynamic>?;
      if (workflowData != null) {
        workflow.current = ((workflowData['current'] as num?)?.toInt() ?? 0)
            .clamp(0, workflow.stages.length - 1);
        final activeId = workflowData['activeCaseId'] as String?;
        if (activeId != null) workflow.activeCaseId = activeId;
        final stages = workflowData['stageByCase'] as Map?;
        if (stages != null) {
          workflow.stageByCase.addAll(stages.map((key, value) => MapEntry(
              key.toString(),
              (value as num).toInt().clamp(0, workflow.stages.length - 1))));
        }
        for (final id
            in (workflowData['voluntaryCaseIds'] as List? ?? const [])) {
          workflow._voluntaryByCase[id.toString()] = true;
        }
        for (final id
            in (workflowData['gatePassedCaseIds'] as List? ?? const [])) {
          workflow._gatePassedByCase[id.toString()] = true;
        }
        workflow._stoppedCases.addAll(
            (workflowData['stoppedCaseIds'] as List? ?? const [])
                .map((e) => e.toString()));
        workflow._completedCases.addAll(
            (workflowData['completedCaseIds'] as List? ?? const [])
                .map((e) => e.toString()));
        final records = workflowData['stageRecords'] as Map?;
        workflow.stageRecords
          ..clear()
          ..addEntries((records ?? const {}).entries.map((entry) => MapEntry(
              entry.key.toString(),
              Map<String, dynamic>.from(entry.value as Map))));
        final payments = workflowData['restitutionPayments'] as Map?;
        if (payments != null) {
          workflow.restitutionPayments.addAll(payments.map((key, value) =>
              MapEntry(
                  key.toString(),
                  (value as List)
                      .whereType<Map>()
                      .map((payment) => Map<String, dynamic>.from(payment))
                      .toList())));
        }
        workflow.audit
          ..clear()
          ..addAll((workflowData['audit'] as List? ?? const [])
              .map((e) => e.toString()));
        final hashes = workflowData['auditHashes'] as List?;
        workflow.auditHashes
          ..clear()
          ..addAll((hashes ?? const []).map((e) => e.toString()));
        if (hashes == null || hashes.isEmpty) {
          workflow.rebuildLegacyAuditChain();
        } else {
          workflow.auditIntegrityValid = workflow.verifyAudit();
        }
      }
      final savedEvidence = data['evidence'] as List?;
      if (savedEvidence != null) {
        evidence.items
          ..clear()
          ..addAll(savedEvidence
              .whereType<Map>()
              .map((e) => EvidenceItem.fromJson(Map<String, dynamic>.from(e))));
      }
      final savedCases = data['cases'] as List?;
      if (savedCases != null) {
        cases.items
          ..clear()
          ..addAll(savedCases
              .whereType<Map>()
              .map((e) => CaseRecord.fromJson(Map<String, dynamic>.from(e))));
      }
      cases.activeId = workflow.activeCaseId;
    } catch (_) {
      // Jika manifest rusak, data bukti di HDD tidak dihapus dan aplikasi tetap berjalan.
    }
  }

  Future<void> save(WorkflowController workflow, EvidenceStore evidence,
      [CaseStore? cases]) {
    final next =
        _saveQueue.then((_) => _writeManifest(workflow, evidence, cases));
    _saveQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeManifest(WorkflowController workflow,
      EvidenceStore evidence, CaseStore? cases) async {
    final root = await _root;
    final manifest =
        File('${root.path}${Platform.pathSeparator}$_manifestName');
    final data = {
      'updatedAt': DateTime.now().toIso8601String(),
      'workflow': {
        'current': workflow.current,
        'activeCaseId': workflow.activeCaseId,
        'stageByCase': workflow.stageByCase,
        'voluntaryCaseIds': workflow._voluntaryByCase.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList(),
        'gatePassedCaseIds': workflow._gatePassedByCase.entries
            .where((e) => e.value)
            .map((e) => e.key)
            .toList(),
        'stoppedCaseIds': workflow._stoppedCases.toList(),
        'completedCaseIds': workflow._completedCases.toList(),
        'stageRecords':
            workflow.stageRecords.map((key, value) => MapEntry(key, value)),
        'restitutionPayments': workflow.restitutionPayments,
        'audit': workflow.audit,
        'auditHashes': workflow.auditHashes,
        'auditIntegrityValid': workflow.auditIntegrityValid,
      },
      'evidence': evidence.items.map((item) => item.toJson()).toList(),
      'cases': (cases ?? caseStore).items.map((item) => item.toJson()).toList(),
    };
    await manifest.writeAsString(jsonEncode(data), flush: true);
  }

  Future<String> copyEvidence(PlatformFile file) async {
    final folder = await evidenceDirectory;
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final target = File(
        '$folder${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}_$safeName');
    if (file.path != null) {
      await File(file.path!).copy(target.path);
    } else if (file.bytes != null) {
      await target.writeAsBytes(file.bytes!, flush: true);
    } else {
      throw StateError('Berkas tidak dapat dibaca dari perangkat.');
    }
    return target.path;
  }
}

class SmoothPageTransitions extends PageTransitionsBuilder {
  const SmoothPageTransitions();
  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
        opacity: curved,
        child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(.04, 0), end: Offset.zero)
                    .animate(curved),
            child: child));
  }
}

class PleaGuardApp extends StatelessWidget {
  const PleaGuardApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'VERITAS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(seedColor: navy, primary: navy),
          fontFamily: 'Arial',
          pageTransitionsTheme: const PageTransitionsTheme(builders: {
            TargetPlatform.android: SmoothPageTransitions(),
            TargetPlatform.iOS: SmoothPageTransitions(),
            TargetPlatform.macOS: SmoothPageTransitions(),
            TargetPlatform.windows: SmoothPageTransitions(),
            TargetPlatform.linux: SmoothPageTransitions()
          }),
          cardTheme: CardThemeData(
            color: Colors.white,
            elevation: 0,
            margin: EdgeInsets.zero,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
        home: const LoginPage(),
      );
}

class DemoSession {
  static String name = 'Andi Pratama';
  static String identifier = 'andi.demo';
  static String role = 'JPU';
  static String unit = 'Kejaksaan RI · Unit demo';
  static bool authenticated = false;
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool obscure = true;
  final email = TextEditingController();
  final password = TextEditingController();

  void _startSso() => Navigator.push(
      context, MaterialPageRoute(builder: (_) => const DemoSsoPage()));

  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF4F7FA), Color(0xFFE5EDF6)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset('assets/kejaksaan_logo.png',
                            width: 86, height: 96, fit: BoxFit.contain),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Image.asset('assets/veritas_logo.png',
                              width: 210, height: 62, fit: BoxFit.contain),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    const Text('Veritas ante Confessionem',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF63758D))),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Masuk ke ruang kerja',
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: ink)),
                            const SizedBox(height: 6),
                            const Text(
                                'Gunakan akun simulasi untuk menjelajahi alur VERITAS.',
                                style: TextStyle(color: Color(0xFF63758D))),
                            const SizedBox(height: 18),
                            const SoftBanner(
                                text:
                                    'DEMO LOKAL · Tidak terhubung ke SSO Kejaksaan. Data dan sesi hanya simulasi.',
                                icon: Icons.science_outlined),
                            const SizedBox(height: 20),
                            const Text(
                                'Akun uji: andi.demo  ·  Kata sandi: veritas123',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF63758D))),
                            const SizedBox(height: 14),
                            TextField(
                              controller: email,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Email institusi atau NRP',
                                prefixIcon: Icon(Icons.person_outline),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: password,
                              obscureText: obscure,
                              onSubmitted: (_) => _startSso(),
                              decoration: InputDecoration(
                                labelText: 'Kata sandi',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  onPressed: () =>
                                      setState(() => obscure = !obscure),
                                  icon: Icon(obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined),
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const ForgotPasswordPage())),
                                child: const Text('Lupa kata sandi?'),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: () {
                                if (email.text.trim() != 'andi.demo' ||
                                    password.text != 'veritas123') {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Kredensial demo tidak cocok. Gunakan andi.demo / veritas123.')));
                                  return;
                                }
                                _startSso();
                              },
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('Lanjut melalui SSO demo'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: navy,
                                  minimumSize: const Size.fromHeight(52)),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: () {
                                email.text = 'andi.demo';
                                password.text = 'veritas123';
                                setState(() {});
                              },
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: const Text('Isi akun uji'),
                              style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const RegistrationPage())),
                      child: const Text('Belum punya akses? Ajukan akun demo'),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                        'KEJAKSAAN REPUBLIK INDONESIA · PROTOTIPE VERITAS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Color(0xFF91A3BB),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: .6)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class DemoSsoPage extends StatefulWidget {
  const DemoSsoPage({super.key});
  @override
  State<DemoSsoPage> createState() => _DemoSsoPageState();
}

class _DemoSsoPageState extends State<DemoSsoPage> {
  int step = 0;
  String role = 'JPU';
  final otp = TextEditingController();

  void _continue() {
    if (step == 0) {
      setState(() => step = 1);
      return;
    }
    if (otp.text.trim() != '246810') {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kode demo salah. Gunakan 246810.')));
      return;
    }
    DemoSession.authenticated = true;
    DemoSession.role = role;
    DemoSession.name =
        role == 'Korban / Pendamping' ? 'Rina Demo' : 'Andi Pratama';
    DemoSession.identifier = 'andi.demo';
    DemoSession.unit =
        role == 'JPU' ? 'Kejaksaan RI · Unit demo' : 'Akses simulasi VERITAS';
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const AppShell()), (_) => false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('SSO Kejaksaan · Demo')),
        body: SafeArea(
            child: Center(
                child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(padding: const EdgeInsets.all(22), children: [
            const ScaleMark(size: 56),
            const SizedBox(height: 18),
            Text(step == 0 ? 'Pilih konteks akses' : 'Verifikasi dua langkah',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: ink)),
            const SizedBox(height: 8),
            Text(
                step == 0
                    ? 'Simulasi alur pengalihan ke penyedia identitas institusi.'
                    : 'Pada sistem nyata, kode dikirim lewat kanal terdaftar. Di demo ini kode tampil di bawah.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF63758D))),
            const SizedBox(height: 22),
            const SoftBanner(
                text:
                    'PENYEDIA IDENTITAS SIMULASI · Kredensial tidak dikirim ke server dan tidak disimpan.',
                icon: Icons.info_outline),
            const SizedBox(height: 18),
            if (step == 0) ...[
              Card(
                  child: ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEAF0F8),
                    child: Icon(Icons.account_balance_outlined, color: navy)),
                title: const Text('Kejaksaan Republik Indonesia',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('SSO institusi · sandbox lokal'),
                trailing: const Icon(Icons.check_circle, color: teal),
              )),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(
                      labelText: 'Profil peran simulasi',
                      border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'JPU', child: Text('Jaksa Penuntut Umum')),
                    DropdownMenuItem(value: 'Advokat', child: Text('Advokat')),
                    DropdownMenuItem(
                        value: 'Auditor',
                        child: Text('Auditor / Quality Reviewer')),
                    DropdownMenuItem(
                        value: 'Court Liaison', child: Text('Court Liaison')),
                    DropdownMenuItem(
                        value: 'Korban / Pendamping',
                        child: Text('Korban / Pendamping')),
                  ],
                  onChanged: (value) => setState(() => role = value ?? role)),
              const SizedBox(height: 12),
              const Text('Akun uji: andi.demo · Kata sandi: veritas123',
                  style: TextStyle(color: Color(0xFF63758D))),
            ] else ...[
              TextField(
                  controller: otp,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                      labelText: 'Kode verifikasi 6 digit',
                      hintText: '246810',
                      prefixIcon: Icon(Icons.password),
                      border: OutlineInputBorder())),
              const SoftBanner(
                  text:
                      'KODE DEMO: 246810 · Kode ini hanya untuk prototipe lokal.',
                  icon: Icons.key_outlined),
              const SizedBox(height: 14),
              Text('Akun: andi.demo  ·  Peran: $role',
                  style: const TextStyle(color: Color(0xFF63758D))),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
                onPressed: _continue,
                icon: Icon(
                    step == 0 ? Icons.open_in_new : Icons.lock_open_outlined),
                label: Text(step == 0
                    ? 'Lanjutkan ke verifikasi'
                    : 'Verifikasi & masuk'),
                style: FilledButton.styleFrom(
                    backgroundColor: navy,
                    minimumSize: const Size.fromHeight(54))),
            if (step == 1)
              TextButton(
                  onPressed: () => setState(() => step = 0),
                  child: const Text('Kembali ke pilihan akses')),
          ]),
        ))),
      );
}

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});
  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final email = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(24), children: [
        pageHeader(context, 'Pulihkan Kata Sandi'),
        const SizedBox(height: 35),
        const ScaleMark(size: 62),
        const SizedBox(height: 22),
        const Text('Reset kata sandi',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text(
            'Masukkan email atau NRP untuk mencoba alur pemulihan. Mode demo tidak mengirim pesan.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF63758D))),
        const SizedBox(height: 26),
        TextField(
            controller: email,
            decoration: const InputDecoration(
                labelText: 'Email institusi atau NRP',
                border: OutlineInputBorder())),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: () {
              if (email.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Masukkan email atau NRP.')));
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Simulasi: instruksi pemulihan akan dikirim setelah SSO institusi dihubungkan.')));
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
                backgroundColor: navy, padding: const EdgeInsets.all(17)),
            child: const Text('Kirim instruksi'))
      ])));
}

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({super.key});
  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  String role = 'JPU';
  final name = TextEditingController();
  final email = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Pendaftaran Akun'),
        const SizedBox(height: 16),
        const SoftBanner(
            text:
                'Pendaftaran akun produksi memerlukan verifikasi institusi dan approval administrator.',
            icon: Icons.verified_user_outlined),
        const SizedBox(height: 18),
        TextField(
            controller: name,
            decoration: const InputDecoration(
                labelText: 'Nama lengkap', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(
            controller: email,
            decoration: const InputDecoration(
                labelText: 'Email institusi', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
            initialValue: role,
            decoration: const InputDecoration(
                labelText: 'Peran pengajuan', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'JPU', child: Text('JPU')),
              DropdownMenuItem(value: 'Advokat', child: Text('Advokat')),
              DropdownMenuItem(
                  value: 'Auditor', child: Text('Auditor / Quality Reviewer')),
              DropdownMenuItem(
                  value: 'Court Liaison', child: Text('Court Liaison'))
            ],
            onChanged: (v) => setState(() => role = v!)),
        const SizedBox(height: 22),
        FilledButton(
            onPressed: () {
              if (name.text.isEmpty || email.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Lengkapi nama dan email institusi.')));
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                      'Simulasi: pengajuan akun dicatat sebagai demo; belum dikirim ke administrator.')));
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
                backgroundColor: navy, padding: const EdgeInsets.all(17)),
            child: const Text('Ajukan Pendaftaran'))
      ])));
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  void open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(open: open, goToTab: (value) => setState(() => tab = value)),
      CasesPage(open: open),
      EvidencePage(open: open),
      NotificationsPage(open: open),
      ProfilePage(
          open: open,
          onSignOut: () {
            DemoSession.authenticated = false;
            Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
                (_) => false);
          })
    ];
    return Scaffold(
        body: SafeArea(
            child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                        position: Tween<Offset>(
                                begin: const Offset(.025, 0), end: Offset.zero)
                            .animate(animation),
                        child: child)),
                child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]))),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (v) => setState(() => tab = v),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Beranda'),
              NavigationDestination(
                  icon: Icon(Icons.business_center_outlined),
                  selectedIcon: Icon(Icons.business_center),
                  label: 'Kasus'),
              NavigationDestination(
                  icon: Icon(Icons.description_outlined),
                  selectedIcon: Icon(Icons.description),
                  label: 'Bukti'),
              NavigationDestination(
                  icon: Icon(Icons.notifications_none),
                  selectedIcon: Icon(Icons.notifications),
                  label: 'Notifikasi'),
              NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person),
                  label: 'Profil')
            ]));
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.open, required this.goToTab});
  final ValueChanged<Widget> open;
  final ValueChanged<int> goToTab;
  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
        Row(children: [
          IconButton(
              onPressed: () => showModalBottomSheet(
                  context: context,
                  builder: (_) => SafeArea(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(
                            leading: const Icon(Icons.business_center_outlined),
                            title: const Text('Daftar perkara'),
                            onTap: () {
                              Navigator.pop(context);
                              goToTab(1);
                            }),
                        ListTile(
                            leading: const Icon(Icons.history),
                            title: const Text('Audit trail'),
                            onTap: () {
                              Navigator.pop(context);
                              open(const AuditTrailPage());
                            }),
                        ListTile(
                            leading: const Icon(Icons.help_outline),
                            title: const Text('Pusat bantuan'),
                            onTap: () {
                              Navigator.pop(context);
                              open(const HelpPage());
                            })
                      ]))),
              icon: const Icon(Icons.menu, color: navy)),
          const Spacer(),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Image.asset('assets/kejaksaan_logo.png',
                width: 26, height: 30, fit: BoxFit.contain),
            const SizedBox(width: 6),
            const Text('Beranda',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
          ]),
          const Spacer(),
          IconButton(
              onPressed: () => goToTab(3),
              icon: Badge(
                  backgroundColor: Colors.amber,
                  child: const Icon(Icons.notifications_none, color: navy))),
          const SizedBox(width: 12),
          InkWell(
              onTap: () => goToTab(4),
              borderRadius: BorderRadius.circular(30),
              child: const CircleAvatar(
                  backgroundColor: Color(0xFF174495),
                  child: Text('AS',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold))))
        ]),
        const SizedBox(height: 34),
        const Text('Selamat pagi,',
            style: TextStyle(color: Color(0xFF63758D), fontSize: 18)),
        const SizedBox(height: 4),
        Text(DemoSession.name,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 30, color: ink)),
        Text('Peran simulasi · ${DemoSession.role} ⌄',
            style: const TextStyle(color: Color(0xFF63758D), fontSize: 17)),
        const SizedBox(height: 28),
        InkWell(
            onTap: () => open(const CaseDetailPage()),
            child: SoftBanner(
                text:
                    'Mari wujudkan peradilan yang lebih\nefektif dan berkeadilan.',
                icon: Icons.arrow_forward)),
        InkWell(
            onTap: () => goToTab(1),
            child: sectionTitle('Ringkasan Kasus', action: 'Lihat Semua')),
        const SizedBox(height: 12),
        AnimatedBuilder(
            animation: Listenable.merge([workflow, caseStore]),
            builder: (_, __) => Row(children: [
                  Expanded(
                      child: StatCard('${caseStore.items.length}', 'Perkara',
                          Icons.description_outlined, blue)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard(
                          '${workflow.stoppedCaseCount}',
                          'Proses\nBiasa',
                          Icons.reply_outlined,
                          Colors.orange)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: StatCard('${workflow.completedCaseCount}',
                          'Tuntas', Icons.check, Colors.green))
                ])),
        const SizedBox(height: 28),
        AnimatedBuilder(
            animation: Listenable.merge([workflow, caseStore]),
            builder: (_, __) {
              final selected = caseStore.active;
              final progress = selected == null
                  ? 0.0
                  : (workflow.current / workflow.stages.length).clamp(0.0, 1.0);
              return Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Status perkara aktif',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800, fontSize: 18)),
                            const SizedBox(height: 8),
                            Text(
                                selected == null
                                    ? 'Belum ada perkara dipilih'
                                    : '${selected.number} · ${workflow.stages[workflow.current]}',
                                style:
                                    const TextStyle(color: Color(0xFF63758D))),
                            const SizedBox(height: 14),
                            LinearProgressIndicator(
                                value: progress,
                                color: teal,
                                backgroundColor: const Color(0xFFE4EAF2)),
                            const SizedBox(height: 16),
                            Row(children: [
                              Icon(
                                  workflow.verifyAudit() &&
                                          workflow.verifyStageRecords()
                                      ? Icons.verified_outlined
                                      : Icons.gpp_bad_outlined,
                                  color: workflow.verifyAudit() &&
                                          workflow.verifyStageRecords()
                                      ? Colors.green
                                      : Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(
                                      !workflow.verifyAudit() ||
                                              !workflow.verifyStageRecords()
                                          ? 'JEJAK GAGAL VERIFIKASI · workflow terkunci'
                                          : workflow.auditHashes.isEmpty
                                              ? 'JEJAK SHA-256 · belum ada catatan'
                                              : 'JEJAK SHA-256 · ${workflow.auditHead.substring(0, 12)}…',
                                      style: TextStyle(
                                          color: workflow.verifyAudit() &&
                                                  workflow.verifyStageRecords()
                                              ? Colors.green
                                              : Colors.red,
                                          fontWeight: FontWeight.w700)))
                            ])
                          ])));
            }),
        sectionTitle('Akses Cepat'),
        Row(children: [
          Quick('Buat\nPerkara', Icons.add_business_outlined,
              () => open(const CreateCasePage())),
          Quick('Workflow\nVERITAS', Icons.account_tree_outlined,
              () => open(const WorkflowPage())),
          Quick('Manajemen\nBukti', Icons.inventory_2_outlined,
              () => open(EvidencePage(open: open))),
          Quick(
              'Audit\nJEJAK', Icons.history, () => open(const AuditTrailPage()))
        ]),
        const SizedBox(height: 24),
        InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => open(const WorkflowPage()),
            child: Container(
                decoration: BoxDecoration(
                    color: navy, borderRadius: BorderRadius.circular(22)),
                padding: const EdgeInsets.all(20),
                child: const Row(children: [
                  Icon(Icons.account_tree_outlined,
                      color: Color(0xFFE4C16D), size: 30),
                  SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Pipa Integritas VERITAS',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 5),
                        Text(
                            '13 tahap · Bukti lebih dahulu · Semua tindakan tercatat di JEJAK',
                            style: TextStyle(
                                color: Color(0xFFD0D9E5), height: 1.35))
                      ])),
                  Icon(Icons.chevron_right, color: Colors.white)
                ]))),
        const SizedBox(height: 18),
        const SoftBanner(
            text:
                'SUAR · Tidak ada perkara yang dapat melanjutkan bila bukti tanpa pengakuan tidak cukup atau kesukarelaan gagal.',
            icon: Icons.shield_outlined),
      ]);
}

class CasesPage extends StatefulWidget {
  const CasesPage({super.key, required this.open});
  final ValueChanged<Widget> open;
  @override
  State<CasesPage> createState() => _CasesPageState();
}

class _CasesPageState extends State<CasesPage> {
  String query = '';
  bool needsActionOnly = false;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
        animation: Listenable.merge([caseStore, workflow]),
        builder: (context, _) {
          final filtered = caseStore.items
              .where((item) =>
                  '${item.number} ${item.category} ${item.defendant}'
                      .toLowerCase()
                      .contains(query.toLowerCase()) &&
                  (!needsActionOnly ||
                      (!workflow.isStoppedFor(item.id) &&
                          !workflow.isCompletedFor(item.id))))
              .toList();
          return ListView(padding: const EdgeInsets.all(20), children: [
            Row(children: [
              Expanded(child: pageHeader(context, 'Kasus')),
              IconButton(
                  onPressed: () => widget.open(const CreateCasePage()),
                  icon: const Icon(Icons.add_circle, color: navy))
            ]),
            const SizedBox(height: 18),
            TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                    hintText: 'Cari nomor perkara atau kategori',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isNotEmpty
                        ? IconButton(
                            onPressed: () => setState(() => query = ''),
                            icon: const Icon(Icons.clear))
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none))),
            const SizedBox(height: 12),
            Row(children: [
              FilterChip(
                  label: const Text('Semua'),
                  selected: !needsActionOnly,
                  onSelected: (_) => setState(() => needsActionOnly = false)),
              const SizedBox(width: 8),
              FilterChip(
                  label: const Text('Perlu tindakan'),
                  selected: needsActionOnly,
                  onSelected: (_) => setState(() => needsActionOnly = true))
            ]),
            const SizedBox(height: 12),
            if (filtered.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                      child: Text(caseStore.items.isEmpty
                          ? 'Belum ada perkara. Buat perkara baru untuk memulai alur VERITAS.'
                          : 'Tidak ada perkara yang sesuai dengan filter.'))),
            ...filtered.map((item) {
              final status = workflow.isStoppedFor(item.id)
                  ? 'Proses biasa'
                  : workflow.isCompletedFor(item.id)
                      ? 'Tuntas'
                      : 'Tahap ${(workflow.stageByCase[item.id] ?? 0) + 1}';
              return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                      onTap: () {
                        caseStore.select(item);
                        widget.open(const CaseDetailPage());
                      },
                      child: CaseTile(
                          number: item.number,
                          title: '${item.category} · ${item.defendant}',
                          status: status)));
            })
          ]);
        });
  }
}

class CreateCasePage extends StatefulWidget {
  const CreateCasePage({super.key});
  @override
  State<CreateCasePage> createState() => _CreateCasePageState();
}

class _CreateCasePageState extends State<CreateCasePage> {
  String category = 'Pencurian';
  final number = TextEditingController();
  final law = TextEditingController();
  final defendant = TextEditingController();
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Buat Perkara'),
        const SizedBox(height: 20),
        const SoftBanner(
            text: 'Data awal menjadi dasar screening dan audit trail perkara.',
            icon: Icons.info_outline),
        const SizedBox(height: 18),
        TextField(
            controller: number,
            decoration: InputDecoration(
                labelText: 'Nomor perkara',
                hintText: 'PN.JKT.SEL/124/2024',
                border: OutlineInputBorder())),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
            initialValue: category,
            decoration: const InputDecoration(
                labelText: 'Kategori perkara', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'Pencurian', child: Text('Pencurian')),
              DropdownMenuItem(
                  value: 'Penggelapan', child: Text('Penggelapan')),
              DropdownMenuItem(value: 'Lainnya', child: Text('Lainnya'))
            ],
            onChanged: (v) => setState(() => category = v!)),
        const SizedBox(height: 14),
        TextField(
            controller: law,
            decoration: InputDecoration(
                labelText: 'Dasar hukum',
                hintText: 'Pasal 362 KUHP',
                border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(
            controller: defendant,
            decoration: InputDecoration(
                labelText: 'Terdakwa',
                hintText: 'Nama lengkap',
                border: OutlineInputBorder())),
        const SizedBox(height: 22),
        FilledButton(
            onPressed: () {
              if (number.text.trim().isEmpty ||
                  law.text.trim().isEmpty ||
                  defendant.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Nomor perkara, dasar hukum, dan nama terdakwa wajib diisi.')));
                return;
              }
              final record = CaseRecord(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  number: number.text.trim(),
                  category: category,
                  law: law.text.trim(),
                  defendant: defendant.text.trim(),
                  createdAt: DateTime.now());
              caseStore.add(record);
              workflow.recordAudit(
                  'Perkara dibuat sebagai draft oleh Pengguna Demo · ${jsonEncode(record.toJson())}');
              unawaited(localDataStore.save(workflow, evidenceStore));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                      Text('Draft perkara dibuat dan siap untuk SARING.')));
            },
            style: FilledButton.styleFrom(
                backgroundColor: navy, padding: const EdgeInsets.all(16)),
            child: const Text('Buat Draft Perkara'))
      ])));
}

class CaseDetailPage extends StatelessWidget {
  const CaseDetailPage({super.key});
  @override
  Widget build(BuildContext context) {
    final record = caseStore.active;
    return Scaffold(
        body: SafeArea(
            child: AnimatedBuilder(
      animation: workflow,
      builder: (context, _) =>
          ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Detail Perkara'),
        const SizedBox(height: 20),
        if (record == null)
          const SoftBanner(
              text: 'Pilih perkara dari daftar untuk melihat status alur.',
              icon: Icons.info_outline)
        else ...[
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(record.number,
                            style: const TextStyle(
                                color: Color(0xFF63758D),
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(record.category,
                            style: const TextStyle(
                                fontSize: 23, fontWeight: FontWeight.w800)),
                        Text(record.law,
                            style: const TextStyle(color: Color(0xFF63758D))),
                        const Divider(height: 28),
                        InfoText('Terdakwa', record.defendant),
                        const SizedBox(height: 12),
                        InfoText('Dibuat',
                            '${record.createdAt.day}/${record.createdAt.month}/${record.createdAt.year}'),
                        const SizedBox(height: 12),
                        InfoText(
                            'Status',
                            workflow.stoppedForStandardProcess
                                ? 'Dikembalikan ke proses biasa'
                                : workflow.completed
                                    ? 'Tuntas'
                                    : workflow.stages[workflow.current]),
                      ]))),
          const SizedBox(height: 18),
          Text('Alur perkara',
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          ...workflow.stages.asMap().entries.map((entry) => _WorkflowStage(
              index: entry.key,
              label: entry.value,
              active: entry.key == workflow.current &&
                  !workflow.completed &&
                  !workflow.stoppedForStandardProcess,
              done: entry.key < workflow.current || workflow.completed)),
          const SizedBox(height: 18),
          if (!workflow.stoppedForStandardProcess && !workflow.completed)
            FilledButton.icon(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const WorkflowPage())),
                icon: const Icon(Icons.play_arrow),
                label: Text(workflow.stageByCase[record.id] == null ||
                        workflow.stageByCase[record.id] == 0
                    ? 'Mulai SARING'
                    : 'Lanjutkan workflow'),
                style: FilledButton.styleFrom(
                    backgroundColor: navy, padding: const EdgeInsets.all(17))),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DossierPage())),
              icon: const Icon(Icons.folder_outlined),
              label: const Text('Buka dossier perkara')),
        ]
      ]),
    )));
  }
}

class EvidencePage extends StatelessWidget {
  const EvidencePage({super.key, required this.open});
  final ValueChanged<Widget> open;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: AnimatedBuilder(
        animation: Listenable.merge([evidenceStore, workflow, caseStore]),
        builder: (_, __) =>
            ListView(padding: const EdgeInsets.all(20), children: [
          pageHeader(context, 'Bukti & Dampak Korban'),
          const SizedBox(height: 16),
          const TabRow(labels: ['Alat Bukti', 'Dampak Korban']),
          const SizedBox(height: 20),
          Builder(builder: (context) {
            final caseEvidence = evidenceStore.items
                .where((item) => item.caseId == workflow.activeCaseId)
                .toList();
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(
                        child: SoftBanner(
                            text:
                                'Kelola seluruh bukti secara\ndigital dan terdokumentasi.',
                            icon: Icons.description_outlined)),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                        onPressed: caseStore.active == null
                            ? null
                            : () => showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => const AddEvidenceSheet()),
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah Bukti'),
                        style: FilledButton.styleFrom(backgroundColor: navy))
                  ]),
                  const SizedBox(height: 18),
                  Text('${caseEvidence.length} bukti untuk perkara aktif',
                      style: const TextStyle(
                          color: Color(0xFF63758D),
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ...caseEvidence.map((item) => FileTile(
                      title: item.title,
                      icon: item.icon,
                      color: item.color,
                      meta:
                          '${item.date} • ${item.size} • SHA-256 ${item.sha256?.substring(0, 12) ?? "belum ada"}',
                      onTap: () => showEvidencePreview(context, item))),
                  if (caseStore.active == null)
                    const SoftBanner(
                        text: 'Pilih perkara sebelum menambahkan bukti.',
                        icon: Icons.info_outline),
                ]);
          }),
          const SizedBox(height: 24),
          const Text('SUARA KORBAN · Asesmen Dampak',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
          const SizedBox(height: 12),
          Builder(builder: (context) {
            final record = workflow.stageRecords['${workflow.activeCaseId}:4'];
            return Card(
                child: ListTile(
              leading:
                  const Icon(Icons.volunteer_activism_outlined, color: teal),
              title: Text(record == null ? 'Belum diisi' : 'Asesmen tersimpan'),
              subtitle: Text(
                  record == null
                      ? 'Lengkapi dampak, perlindungan, dan preferensi korban pada tahap SUARA KORBAN di workflow.'
                      : 'Dampak: ${record['victimImpact']}\nPerlindungan: ${record['victimProtection']}\nPreferensi: ${record['victimPreference']}',
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis),
            ));
          })
        ]),
      )));
}

// Shared visual components
Widget pageHeader(BuildContext context, String title) => Row(children: [
      IconButton(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_ios_new, color: navy)),
      Expanded(
          child: Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 21, fontWeight: FontWeight.w800, color: ink))),
      IconButton(
          onPressed: () => showModalBottomSheet(
              context: context,
              builder: (_) => SafeArea(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ListTile(
                        leading: const Icon(Icons.history),
                        title: const Text('Audit trail'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const AuditTrailPage()));
                        }),
                    ListTile(
                        leading: Icon(Icons.share_outlined),
                        title: const Text('Bagikan ringkasan'),
                        onTap: () {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Ringkasan perkara siap dibagikan sesuai izin akses.')));
                        }),
                    const SizedBox(height: 10)
                  ]))),
          icon: const Icon(Icons.more_horiz, color: navy))
    ]);
Widget sectionTitle(String title, {String? action}) => Padding(
    padding: const EdgeInsets.only(top: 25),
    child: Row(children: [
      Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 20, color: ink))),
      if (action != null)
        Text(action,
            style: const TextStyle(color: blue, fontWeight: FontWeight.w700))
    ]));

class ScaleMark extends StatelessWidget {
  const ScaleMark({super.key, this.size = 52});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: navy,
          borderRadius: BorderRadius.circular(size * .25),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 8))
          ]),
      child: Icon(Icons.balance,
          color: const Color(0xFFFFC233), size: size * .52));
}

class SoftBanner extends StatelessWidget {
  const SoftBanner(
      {super.key,
      required this.text,
      required this.icon,
      this.goldStyle = false,
      this.greenStyle = false});
  final String text;
  final IconData icon;
  final bool goldStyle, greenStyle;
  @override
  Widget build(BuildContext context) {
    final c = greenStyle
        ? Colors.green
        : goldStyle
            ? gold
            : blue;
    return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: c.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.withValues(alpha: .22))),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: c.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(13)),
              child: Icon(icon, color: c)),
          const SizedBox(width: 14),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, height: 1.35)))
        ]));
  }
}

class StatCard extends StatelessWidget {
  const StatCard(this.value, this.label, this.icon, this.color, {super.key});
  final String value, label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color)),
            const SizedBox(height: 22),
            Text(value,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, fontSize: 30)),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(color: Color(0xFF63758D), height: 1.35))
          ])));
}

class Quick extends StatelessWidget {
  const Quick(this.label, this.icon, this.tap, {super.key});
  final String label;
  final IconData icon;
  final VoidCallback tap;
  @override
  Widget build(BuildContext context) => Expanded(
      child: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: InkWell(
              onTap: tap,
              borderRadius: BorderRadius.circular(18),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 6),
                      child: Column(children: [
                        Icon(icon, color: navy),
                        const SizedBox(height: 9),
                        Text(label,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600))
                      ]))))));
}

class CaseTile extends StatelessWidget {
  const CaseTile(
      {super.key,
      required this.number,
      required this.title,
      required this.status});
  final String number, title, status;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            const ScaleMark(size: 44),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(number,
                      style: const TextStyle(
                          color: Color(0xFF63758D), fontSize: 12)),
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 16)),
                  const SizedBox(height: 6),
                  StatusPill(
                      status,
                      status == 'Tuntas'
                          ? Colors.green
                          : status == 'Proses biasa'
                              ? Colors.orange
                              : blue)
                ])),
            const Icon(Icons.chevron_right, color: Color(0xFF94A3B8))
          ])));
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, this.color, {super.key});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withValues(alpha: .25))),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w700, fontSize: 12)));
}

class InfoText extends StatelessWidget {
  const InfoText(this.label, this.value, {super.key});
  final String label, value;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 15)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))
      ]);
}

class TabRow extends StatelessWidget {
  const TabRow({super.key, required this.labels});
  final List<String> labels;
  @override
  Widget build(BuildContext context) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: labels
          .asMap()
          .entries
          .map((e) => Column(children: [
                Text(e.value,
                    style: TextStyle(
                        color: e.key == 0 ? navy : const Color(0xFF94A3B8),
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Container(
                    width: 54,
                    height: 3,
                    color: e.key == 0 ? blue : Colors.transparent)
              ]))
          .toList());
}

class Param extends StatelessWidget {
  const Param(this.label, this.value, this.color, {super.key});
  final String label;
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
          Text('${(value * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w800))
        ]),
        const SizedBox(height: 9),
        LinearProgressIndicator(
            value: value,
            minHeight: 9,
            borderRadius: BorderRadius.circular(8),
            color: color,
            backgroundColor: const Color(0xFFEAF0F5))
      ]));
}

class RIcon extends StatelessWidget {
  const RIcon(this.label, this.icon, this.color, {super.key});
  final String label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
      width: 54,
      child: Column(children: [
        Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(15)),
            child: Icon(icon, color: Colors.white, size: 20)),
        const SizedBox(height: 7),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9))
      ]));
}

class FileTile extends StatelessWidget {
  const FileTile(
      {super.key,
      required this.title,
      required this.icon,
      required this.color,
      required this.meta,
      this.onTap});
  final String title, meta;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
          child: ListTile(
              onTap: onTap,
              contentPadding: const EdgeInsets.all(16),
              leading: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(15)),
                  child: Icon(icon, color: color)),
              title: Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 18)),
              subtitle:
                  Text(meta, style: const TextStyle(color: Color(0xFF94A3B8))),
              trailing: Icon(
                  onTap == null ? Icons.more_vert : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8)))));
}

void showEvidencePreview(BuildContext context, EvidenceItem item) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                    child: Text(item.title,
                        style: const TextStyle(
                            fontSize: 21, fontWeight: FontWeight.w800))),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close))
              ]),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 360),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(18)),
                child: item.isImage && item.bytes != null
                    ? InteractiveViewer(
                        minScale: .8,
                        maxScale: 4,
                        child: Image.memory(item.bytes!, fit: BoxFit.contain))
                    : Center(
                        child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(item.icon, size: 62, color: item.color),
                                  const SizedBox(height: 12),
                                  Text(item.bytes == null
                                      ? 'Preview berkas contoh belum tersedia.'
                                      : 'Preview visual untuk format ${item.extension?.toUpperCase() ?? item.category} belum didukung.'),
                                  const SizedBox(height: 6),
                                  const Text(
                                      'Metadata dan jejak akses tersedia pada audit trail.',
                                      textAlign: TextAlign.center,
                                      style:
                                          TextStyle(color: Color(0xFF63758D))),
                                ]))),
              ),
              const SizedBox(height: 14),
              Text(
                  'Kategori: ${item.category}\nUkuran: ${item.size}\nTanggal: ${item.date}',
                  style:
                      const TextStyle(color: Color(0xFF52657C), height: 1.6)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text(
                              'Akses preview dicatat pada audit trail demo.'))),
                  icon: const Icon(Icons.history),
                  label: const Text('Catat akses preview'))
            ]),
      )),
    );

class DossierPage extends StatelessWidget {
  const DossierPage({super.key});
  @override
  Widget build(BuildContext context) {
    final active = caseStore.active;
    final savedPayments = active == null
        ? const <Map<String, dynamic>>[]
        : workflow.restitutionPayments[active.id] ?? const [];
    final savedRecords = workflow.stageRecords.entries
        .where(
            (entry) => active != null && entry.key.startsWith('${active.id}:'))
        .toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    const folders = [
      ('Profil Perkara & Pihak', Icons.badge_outlined),
      ('Matriks Bukti JANGKAR', Icons.folder_copy_outlined),
      ('Penilaian SINAR & NURANI', Icons.fact_check_outlined),
      ('SUARA KORBAN & Restitusi', Icons.volunteer_activism_outlined),
      ('Lima Gerbang Integritas', Icons.shield_outlined),
      ('AKTA Kesepakatan', Icons.draw_outlined),
      ('SAMBUNG & Penetapan Hakim', Icons.account_balance_outlined),
      ('Pemulihan PULIH', Icons.handshake_outlined),
      ('Tinjauan CAKRAWALA', Icons.verified_outlined)
    ];
    return Scaffold(
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
      pageHeader(context, 'Digital Plea Dossier'),
      const SizedBox(height: 8),
      Text(
          active == null
              ? 'Tidak ada perkara aktif.'
              : 'Perkara aktif: ${active.number}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      const Text(
          'Dokumen dikelompokkan berdasarkan tahap. Akses dan ekspor pada produksi mengikuti RBAC serta klasifikasi data.',
          style: TextStyle(color: Color(0xFF63758D))),
      const SizedBox(height: 18),
      if (savedRecords.isEmpty)
        const SoftBanner(
            text:
                'Keputusan tahap dan alasan akan muncul di dossier setelah formulir tahap diselesaikan.',
            icon: Icons.info_outline),
      ...savedRecords.map((entry) => Card(
              child: ListTile(
            leading: Icon(
                entry.value['recordHash'] ==
                        workflow.hashStageRecord(entry.value)
                    ? Icons.fact_check_outlined
                    : Icons.gpp_bad_outlined,
                color: entry.value['recordHash'] ==
                        workflow.hashStageRecord(entry.value)
                    ? navy
                    : Colors.red),
            title: Text(
                '${entry.value['stage']?.toString() ?? 'Tahap workflow'}${entry.value['recordHash'] == workflow.hashStageRecord(entry.value) ? '' : ' · HASH TIDAK VALID'}'),
            subtitle: Text(
                '${entry.value['recordedAt'] ?? ''}\nAlasan: ${entry.value['reason'] ?? ''}',
                maxLines: 4,
                overflow: TextOverflow.ellipsis),
          ))),
      if (savedPayments.isNotEmpty)
        const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text('Riwayat cicilan restitusi',
                style: TextStyle(fontWeight: FontWeight.w800))),
      ...savedPayments.map((payment) => Card(
              child: ListTile(
            leading: const Icon(Icons.payments_outlined, color: teal),
            title: Text('Rp ${payment['amount']} · ${payment['recordedAt']}'),
            subtitle: Text(
                'Bukti: ${payment['proof']} · konfirmasi korban: ${payment['victimConfirmed'] == true ? "Ya" : "Tidak"}'),
          ))),
      ...folders.map((item) => Card(
              child: ListTile(
            onTap: () => _openFolder(context, item.$1),
            leading: Icon(item.$2, color: navy),
            title: Text(item.$1,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Dokumen dan riwayat versi'),
            trailing: const Icon(Icons.chevron_right),
          ))),
      const SizedBox(height: 16),
      OutlinedButton.icon(
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Permintaan ekspor dicatat dalam audit trail demo.'))),
          icon: const Icon(Icons.ios_share),
          label: const Text('Minta ekspor dossier'))
    ])));
  }

  void _openFolder(BuildContext context, String name) => showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                const Text(
                    'Dokumen demo tersedia untuk ditinjau. Pada backend, daftar ini memuat versi, hash SHA-256, klasifikasi, dan signed URL berumur pendek.'),
                const SizedBox(height: 18),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    style: FilledButton.styleFrom(backgroundColor: navy),
                    child: const Text('Tutup')),
              ]),
        )),
      );
}

class AddEvidenceSheet extends StatefulWidget {
  const AddEvidenceSheet({super.key});
  @override
  State<AddEvidenceSheet> createState() => _AddEvidenceSheetState();
}

class _AddEvidenceSheetState extends State<AddEvidenceSheet> {
  String category = 'Dokumen';
  final title = TextEditingController();
  PlatformFile? selected;
  Future<void> _pickFile() async {
    final result =
        await FilePicker.platform.pickFiles(withData: true, type: FileType.any);
    if (result == null) return;
    setState(() {
      selected = result.files.single;
      if (title.text.trim().isEmpty) {
        title.text = selected!.name.split('.').first;
      }
      final ext = (selected!.extension ?? '').toLowerCase();
      if (['jpg', 'jpeg', 'png', 'webp'].contains(ext)) category = 'Foto';
      if (['mp4', 'mov', 'avi'].contains(ext)) category = 'Video';
    });
  }

  String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) => SafeArea(
      child: Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tambah Bukti',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 16),
                TextField(
                    controller: title,
                    decoration: InputDecoration(
                        labelText: 'Nama bukti', border: OutlineInputBorder())),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: category,
                    items: const [
                      DropdownMenuItem(
                          value: 'Dokumen', child: Text('Dokumen')),
                      DropdownMenuItem(value: 'Foto', child: Text('Foto')),
                      DropdownMenuItem(value: 'Video', child: Text('Video'))
                    ],
                    onChanged: (v) => setState(() => category = v!),
                    decoration: const InputDecoration(
                        labelText: 'Jenis bukti',
                        border: OutlineInputBorder())),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.upload_file),
                    label: Text(
                        selected == null ? 'Pilih berkas' : 'Ganti berkas')),
                if (selected != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                              ['jpg', 'jpeg', 'png', 'webp'].contains(
                                      (selected!.extension ?? '').toLowerCase())
                                  ? Icons.image
                                  : Icons.description,
                              color: navy),
                          title: Text(selected!.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${selected!.extension?.toUpperCase() ?? 'FILE'} • ${_size(selected!.size)}'))),
                const SizedBox(height: 16),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                        onPressed: selected == null || title.text.trim().isEmpty
                            ? null
                            : () async {
                                try {
                                  final localPath = await localDataStore
                                      .copyEvidence(selected!);
                                  final checksum = selected!.bytes != null
                                      ? sha256
                                          .convert(selected!.bytes!)
                                          .toString()
                                      : (await sha256
                                              .bind(File(localPath).openRead())
                                              .first)
                                          .toString();
                                  final now = DateTime.now();
                                  evidenceStore.add(EvidenceItem(
                                      title: title.text.trim(),
                                      category: category,
                                      date:
                                          '${now.day.toString().padLeft(2, '0')} ${[
                                        'Jan',
                                        'Feb',
                                        'Mar',
                                        'Apr',
                                        'Mei',
                                        'Jun',
                                        'Jul',
                                        'Agu',
                                        'Sep',
                                        'Okt',
                                        'Nov',
                                        'Des'
                                      ][now.month - 1]} ${now.year}',
                                      size: _size(selected!.size),
                                      bytes: selected!.bytes,
                                      extension: selected!.extension,
                                      localPath: localPath,
                                      caseId: workflow.activeCaseId,
                                      sha256: checksum));
                                  workflow.recordAudit(
                                      'Bukti ${title.text.trim()} ditambahkan · SHA-256 $checksum');
                                  await localDataStore.save(
                                      workflow, evidenceStore);
                                  if (!context.mounted) return;
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Bukti disalin dan tersimpan di penyimpanan perangkat.')));
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Berkas gagal disimpan ke penyimpanan perangkat.')));
                                }
                              },
                        style: FilledButton.styleFrom(
                            backgroundColor: navy,
                            padding: const EdgeInsets.all(16)),
                        child: const Text('Simpan Draft')))
              ])));
}

class WorkflowPage extends StatelessWidget {
  const WorkflowPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: AnimatedBuilder(
        animation: workflow,
        builder: (_, __) =>
            ListView(padding: const EdgeInsets.all(20), children: [
          pageHeader(context, 'Workflow Perkara'),
          const SizedBox(height: 12),
          const Text(
              'Flow decision-support. Tahap sensitif memerlukan data lengkap, kewenangan role, dan validasi server.',
              style: TextStyle(color: Color(0xFF63758D))),
          if (caseStore.active == null)
            const SoftBanner(
                text:
                    'Pilih atau buat perkara terlebih dahulu. Workflow dan keputusan akan terikat pada perkara aktif.',
                icon: Icons.info_outline),
          if (workflow.stoppedForStandardProcess)
            const SoftBanner(
                text:
                    'JALUR PENGAKUAN DIHENTIKAN. Perkara kembali ke proses biasa; catatan keputusan tetap tersimpan.',
                icon: Icons.stop_circle_outlined),
          if (workflow.completed)
            const SoftBanner(
                text: 'VERITAS TUNTAS. Tinjauan mutu telah diselesaikan.',
                icon: Icons.verified_outlined,
                greenStyle: true),
          if (!workflow.verifyAudit() || !workflow.verifyStageRecords())
            const SoftBanner(
                text:
                    'JEJAK tidak lolos verifikasi. Tindakan workflow dikunci dan perlu peninjauan.',
                icon: Icons.gpp_bad_outlined),
          const SizedBox(height: 20),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(children: [
                    const Icon(Icons.account_tree_outlined,
                        color: navy, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Tahap aktif',
                              style: TextStyle(color: Color(0xFF63758D))),
                          Text(
                              '${workflow.current + 1}. ${workflow.stages[workflow.current]}',
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800))
                        ]))
                  ]))),
          const SizedBox(height: 18),
          ...workflow.stages.asMap().entries.map((entry) => _WorkflowStage(
              index: entry.key,
              label: entry.value,
              active: entry.key == workflow.current,
              done: entry.key < workflow.current)),
          const SizedBox(height: 16),
          if (workflow.current == 3)
            SwitchListTile(
                value: workflow.voluntary,
                onChanged: workflow.setVoluntary,
                title: const Text('Pengakuan dilakukan sukarela'),
                subtitle: const Text(
                    'Jika tidak, flow plea harus dihentikan sesuai policy.')),
          if (workflow.current == 6)
            SwitchListTile(
                value: workflow.gatePassed,
                onChanged: workflow.setGatePassed,
                title: const Text('Lima integrity gates telah passed'),
                subtitle: const Text(
                    'Gate gagal memblokir conference dan approval.')),
          if (caseStore.active != null &&
              !workflow.stoppedForStandardProcess &&
              !workflow.completed)
            SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const StageActionPage())),
                    icon: const Icon(Icons.assignment_outlined),
                    label: const Text('Buka form tahap aktif'))),
          const SizedBox(height: 10),
          if (caseStore.active != null &&
              !workflow.stoppedForStandardProcess &&
              !workflow.completed)
            OutlinedButton.icon(
                onPressed: () {
                  final reason = TextEditingController();
                  showDialog<void>(
                      context: context,
                      builder: (dialogContext) => StatefulBuilder(
                          builder: (dialogContext, setDialogState) =>
                              AlertDialog(
                                title: const Text('Hentikan jalur pengakuan'),
                                content: TextField(
                                  controller: reason,
                                  minLines: 2,
                                  maxLines: 4,
                                  onChanged: (_) => setDialogState(() {}),
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Alasan dan dasar keputusan (min. 20 karakter)',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                      onPressed: () =>
                                          Navigator.pop(dialogContext),
                                      child: const Text('Batal')),
                                  FilledButton(
                                    onPressed: reason.text.trim().length < 20
                                        ? null
                                        : () {
                                            workflow.returnToStandard(
                                                reason.text.trim());
                                            Navigator.pop(dialogContext);
                                          },
                                    child:
                                        const Text('Kembali ke proses biasa'),
                                  )
                                ],
                              ))).whenComplete(reason.dispose);
                },
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Hentikan dan kembalikan ke proses biasa')),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AuditTrailPage())),
              icon: const Icon(Icons.history),
              label: const Text('Lihat audit trail'))
        ]),
      )));
}

Future<void> _promptToStopWorkflow(BuildContext context,
    {required String title, required String prefix}) async {
  final reason = TextEditingController();
  await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
                title: Text(title),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Jalur pengakuan akan dihentikan dan perkara kembali ke proses biasa. Pada prototipe ini laporan hanya dicatat lokal; belum dikirim secara rahasia ke Bidang Pengawasan.'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    minLines: 2,
                    maxLines: 4,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: const InputDecoration(
                      labelText:
                          'Alasan dan dasar keputusan (min. 20 karakter)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Batal')),
                  FilledButton(
                    onPressed: reason.text.trim().length < 20
                        ? null
                        : () {
                            workflow.returnToStandard(
                                '$prefix: ${reason.text.trim()}');
                            Navigator.pop(dialogContext);
                          },
                    child: const Text('Hentikan jalur'),
                  )
                ],
              ))).whenComplete(reason.dispose);
}

class StageActionPage extends StatefulWidget {
  const StageActionPage({super.key});
  @override
  State<StageActionPage> createState() => _StageActionPageState();
}

class _StageActionPageState extends State<StageActionPage> {
  bool checked = false;
  bool secondChecked = false;
  final screeningChecks = List<bool>.filled(4, false);
  final sinarTouched = List<bool>.filled(8, false);
  final gateChecks = List<bool>.filled(5, false);
  final evidenceElements = <TextEditingController>[TextEditingController()];
  final evidenceMappings = <List<String?>>[
    [null, null]
  ];
  final sinarValues = List<double>.filled(8, 0);
  final sinarReasons = List.generate(8, (_) => TextEditingController());
  final conferenceChecks = List<bool>.filled(9, false);
  final admission = TextEditingController();
  final consequence = TextEditingController();
  final harmRepair = TextEditingController();
  final courtReference = TextEditingController();
  final restitutionDue = TextEditingController();
  final restitutionPaid = TextEditingController();
  final restitutionProof = TextEditingController();
  final nuraniSessionRef = TextEditingController();
  final victimDamage = TextEditingController();
  final victimProtection = TextEditingController();
  final victimPreference = TextEditingController();
  final rangeLow = TextEditingController();
  final rangeHigh = TextEditingController();
  final proposedPenalty = TextEditingController();
  final sinarSupervisorRef = TextEditingController();
  final kasiApprovalRef = TextEditingController();
  final kajariApprovalRef = TextEditingController();
  String courtOutcome = 'Pilih hasil';
  bool paymentProofVerified = false;
  bool victimConfirmed = false;
  static const sinarLabels = [
    'Pengakuan sukarela',
    'Kekuatan alat bukti',
    'Pelaku pertama',
    'Sikap kooperatif',
    'Ancaman pidana memenuhi syarat',
    'Kerugian dapat dipulihkan',
    'Bebas tekanan/paksaan',
    'Kepentingan umum'
  ];
  static const sinarWeights = [20, 20, 15, 10, 10, 10, 10, 5];
  int get sinarScore =>
      List.generate(8, (i) => (sinarValues[i] * sinarWeights[i]).round())
          .fold(0, (total, value) => total + value);
  List<EvidenceItem> get caseEvidence => evidenceStore.items
      .where((item) => item.caseId == workflow.activeCaseId)
      .toList();
  String _evidenceKey(EvidenceItem item) =>
      item.localPath ?? '${item.title}|${item.date}';
  bool get jangkarValid =>
      evidenceElements.isNotEmpty &&
      List.generate(
              evidenceElements.length,
              (i) =>
                  evidenceElements[i].text.trim().isNotEmpty &&
                  evidenceMappings[i][0] != null &&
                  evidenceMappings[i][1] != null &&
                  evidenceMappings[i][0] != evidenceMappings[i][1])
          .every((valid) => valid);
  bool get timbangValid {
    final low = double.tryParse(rangeLow.text);
    final high = double.tryParse(rangeHigh.text);
    final proposal = double.tryParse(proposedPenalty.text);
    if (low == null || high == null || proposal == null || low > high) {
      return false;
    }
    final inRange = proposal >= low && proposal <= high;
    return inRange ||
        (kasiApprovalRef.text.trim().isNotEmpty &&
            kajariApprovalRef.text.trim().isNotEmpty);
  }

  static const gateLabels = [
    'Kelayakan hukum',
    'Kecukupan bukti tanpa pengakuan',
    'Kesukarelaan dengan pendampingan advokat',
    'Korban dan kepentingan umum',
    'Proporsionalitas dan integritas'
  ];
  static const conferenceLabels = [
    'JPU mempresentasikan fakta dan matriks bukti',
    'Hak terdakwa dan korban dijelaskan',
    'Pengakuan dikonfirmasi di hadapan advokat',
    'Advokat dapat menanggapi bukti',
    'Dampak dan harapan korban dicatat',
    'Konsekuensi hukum dan rentang dijelaskan',
    'Draf akta ditinjau bersama',
    'Kendali mutu pejabat pengawas dilakukan',
    'Paket siap diajukan ke pengadilan'
  ];
  static const screeningLabels = [
    'Ancaman pidana memenuhi parameter hukum yang berlaku',
    'Status pelaku pertama telah diverifikasi pada sumber berwenang',
    'Pernyataan kesiapan pemulihan telah diterima melalui advokat',
    'Advokat telah ditunjuk dan identitasnya diverifikasi'
  ];
  @override
  void initState() {
    super.initState();
    final payments =
        workflow.restitutionPayments[workflow.activeCaseId] ?? const [];
    if (payments.isNotEmpty) restitutionDue.text = '${payments.first['due']}';
  }

  @override
  void dispose() {
    note.dispose();
    admission.dispose();
    consequence.dispose();
    harmRepair.dispose();
    courtReference.dispose();
    restitutionDue.dispose();
    restitutionPaid.dispose();
    restitutionProof.dispose();
    nuraniSessionRef.dispose();
    victimDamage.dispose();
    victimProtection.dispose();
    victimPreference.dispose();
    rangeLow.dispose();
    rangeHigh.dispose();
    proposedPenalty.dispose();
    sinarSupervisorRef.dispose();
    for (final controller in sinarReasons) {
      controller.dispose();
    }
    kasiApprovalRef.dispose();
    kajariApprovalRef.dispose();
    for (final controller in evidenceElements) {
      controller.dispose();
    }
    super.dispose();
  }

  final note = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final stage = workflow.stages[workflow.current];
    final config = _stageConfig(stage);
    return Scaffold(
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
      pageHeader(context, stage),
      const SizedBox(height: 14),
      SoftBanner(
          text: config.$1, icon: config.$2, greenStyle: workflow.current > 10),
      const SizedBox(height: 20),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(config.$3,
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    TextField(
                        controller: note,
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                            labelText: config.$4,
                            hintText:
                                'Wajib: catat fakta, alasan, dan dasar dokumen (minimal 20 karakter)',
                            border: const OutlineInputBorder())),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                        value: checked,
                        onChanged: (v) => setState(() => checked = v!),
                        contentPadding: EdgeInsets.zero,
                        title: Text(config.$5),
                        subtitle: const Text(
                            'Konfirmasi ini dicatat sebagai draft dan harus divalidasi server pada produksi.')),
                    if (workflow.current == 0)
                      ...List.generate(
                          screeningLabels.length,
                          (i) => CheckboxListTile(
                              value: screeningChecks[i],
                              onChanged: (value) => setState(
                                  () => screeningChecks[i] = value ?? false),
                              contentPadding: EdgeInsets.zero,
                              title: Text(screeningLabels[i]))),
                    if (workflow.current == 1) ...[
                      const Divider(height: 28),
                      Row(children: [
                        const Expanded(
                            child: Text('Skor SINAR',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18))),
                        Text('$sinarScore / 100',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, color: navy))
                      ]),
                      Text(
                          sinarScore >= 88
                              ? 'HIJAU · Layak'
                              : sinarScore >= 50
                                  ? 'KUNING · Perlu tinjauan atasan'
                                  : 'MERAH · Jangan lanjutkan',
                          style: TextStyle(
                              color: sinarScore >= 88
                                  ? Colors.green
                                  : sinarScore >= 50
                                      ? Colors.orange
                                      : Colors.red,
                              fontWeight: FontWeight.bold)),
                      ...List.generate(
                          8,
                          (i) => Column(children: [
                                Row(children: [
                                  Expanded(child: Text(sinarLabels[i])),
                                  Text('${sinarWeights[i]} poin')
                                ]),
                                Slider(
                                    value: sinarValues[i],
                                    onChanged: (value) => setState(() {
                                          sinarValues[i] = value;
                                          sinarTouched[i] = true;
                                        }),
                                    activeColor: navy),
                                TextField(
                                    controller: sinarReasons[i],
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                        labelText:
                                            'Alasan dan sumber bukti/halaman untuk ${sinarLabels[i]}',
                                        border: const OutlineInputBorder()))
                              ])),
                      if (sinarScore >= 50 && sinarScore < 88)
                        TextField(
                            controller: sinarSupervisorRef,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText:
                                    'Referensi persetujuan Kasi Pidum dan alasan tertulis',
                                border: OutlineInputBorder())),
                      if (sinarScore < 50)
                        const Text(
                            'Skor di bawah 50 menghentikan jalur pengakuan bersalah dan mengembalikan perkara ke proses biasa.',
                            style: TextStyle(
                                color: Colors.red, fontWeight: FontWeight.w600))
                    ],
                    if (workflow.current == 2)
                      Column(children: [
                        Text(
                            'Setiap unsur harus memiliki sekurangnya dua alat bukti berbeda. Berkas tersedia untuk perkara ini: ${caseEvidence.length}.'),
                        ...List.generate(
                            evidenceElements.length,
                            (i) => Card(
                                color: const Color(0xFFF8FAFC),
                                child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(children: [
                                      TextField(
                                          controller: evidenceElements[i],
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                              labelText: 'Unsur pasal ${i + 1}',
                                              border:
                                                  const OutlineInputBorder())),
                                      const SizedBox(height: 8),
                                      ...List.generate(
                                          2,
                                          (slot) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 8),
                                              child: DropdownButtonFormField<
                                                  String>(
                                                initialValue:
                                                    evidenceMappings[i][slot],
                                                decoration: InputDecoration(
                                                    labelText:
                                                        'Alat bukti sah ${slot + 1}'),
                                                items: caseEvidence
                                                    .map((item) => DropdownMenuItem(
                                                        value:
                                                            _evidenceKey(item),
                                                        child: Text(
                                                            '${item.title} · ${item.sha256?.substring(0, 10) ?? "tanpa hash"}',
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis)))
                                                    .toList(),
                                                onChanged: (key) => setState(
                                                    () => evidenceMappings[i]
                                                        [slot] = key),
                                              ))),
                                      if (evidenceElements.length > 1)
                                        TextButton.icon(
                                            onPressed: () => setState(() {
                                                  evidenceElements
                                                      .removeAt(i)
                                                      .dispose();
                                                  evidenceMappings.removeAt(i);
                                                }),
                                            icon: const Icon(
                                                Icons.remove_circle_outline),
                                            label:
                                                const Text('Hapus unsur ini')),
                                      if (evidenceMappings[i][0] != null &&
                                          evidenceMappings[i][0] ==
                                              evidenceMappings[i][1])
                                        const Text(
                                            'Pilih dua bukti yang berbeda.',
                                            style: TextStyle(color: Colors.red))
                                    ])))),
                        TextButton.icon(
                            onPressed: () => setState(() {
                                  evidenceElements.add(TextEditingController());
                                  evidenceMappings.add([null, null]);
                                }),
                            icon: const Icon(Icons.add),
                            label: const Text('Tambah unsur pasal')),
                        CheckboxListTile(
                            value: secondChecked,
                            onChanged: (v) =>
                                setState(() => secondChecked = v!),
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                                'Saya telah memetakan unsur dan menguji perkara tanpa pengakuan'),
                            subtitle: const Text(
                                'Konfirmasi JPU tidak menggantikan persetujuan substansi atasan pada gerbang berikutnya.'))
                      ]),
                    if (workflow.current == 3)
                      Column(children: [
                        SwitchListTile(
                            value: workflow.voluntary,
                            onChanged: workflow.setVoluntary,
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Pengakuan dinyatakan sukarela'),
                            subtitle: const Text(
                                'Jika tidak, proses dihentikan. Tersedia kanal LAPOR kepada Bidang Pengawasan.')),
                        TextField(
                            controller: nuraniSessionRef,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText:
                                    'Referensi sesi NURANI (rekaman belum terhubung pada prototipe)',
                                border: OutlineInputBorder()))
                      ]),
                    if (workflow.current == 3)
                      OutlinedButton.icon(
                          onPressed: () => _promptToStopWorkflow(context,
                              title: 'LAPOR dugaan tekanan',
                              prefix: 'SUAR MERAH · LAPOR dugaan tekanan'),
                          icon: const Icon(Icons.report_gmailerrorred_outlined),
                          label: const Text(
                              'LAPOR dugaan tekanan dan hentikan jalur')),
                    if (workflow.current == 6)
                      ...List.generate(
                          gateLabels.length,
                          (i) => CheckboxListTile(
                              value: gateChecks[i],
                              onChanged: (value) => setState(
                                  () => gateChecks[i] = value ?? false),
                              contentPadding: EdgeInsets.zero,
                              title:
                                  Text('Gerbang ${i + 1} · ${gateLabels[i]}'))),
                    if (workflow.current == 7)
                      ...List.generate(
                          conferenceLabels.length,
                          (i) => CheckboxListTile(
                              value: conferenceChecks[i],
                              onChanged: (value) => setState(
                                  () => conferenceChecks[i] = value ?? false),
                              contentPadding: EdgeInsets.zero,
                              title: Text('${i + 1}. ${conferenceLabels[i]}'))),
                    if (workflow.current == 8) ...[
                      TextField(
                          controller: admission,
                          maxLines: 3,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: '1 · Pengakuan perbuatan dan pasal',
                              border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                      TextField(
                          controller: consequence,
                          maxLines: 3,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText:
                                  '2 · Konsekuensi pidana dan legal reasoning',
                              border: OutlineInputBorder())),
                      const SizedBox(height: 12),
                      TextField(
                          controller: harmRepair,
                          maxLines: 3,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: '3 · Pemulihan korban dan jadwal',
                              border: OutlineInputBorder()))
                    ],
                    if (workflow.current == 10) ...[
                      const Text(
                          'Demo integrasi: keputusan dan nomor penetapan harus diverifikasi dari dokumen resmi.'),
                      DropdownButtonFormField<String>(
                          initialValue: courtOutcome,
                          decoration: const InputDecoration(
                              labelText: 'Hasil penetapan hakim'),
                          items: const [
                            DropdownMenuItem(
                                value: 'Pilih hasil',
                                child: Text('Pilih hasil')),
                            DropdownMenuItem(
                                value: 'Disahkan', child: Text('Disahkan')),
                            DropdownMenuItem(
                                value: 'Ditolak', child: Text('Ditolak')),
                            DropdownMenuItem(
                                value: 'Pengakuan dicabut',
                                child: Text('Pengakuan dicabut'))
                          ],
                          onChanged: (value) => setState(
                              () => courtOutcome = value ?? 'Pilih hasil')),
                      TextField(
                          controller: courtReference,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: 'Nomor penetapan / referensi berkas',
                              border: OutlineInputBorder()))
                    ],
                    if (workflow.current == 9)
                      TextField(
                          controller: courtReference,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText:
                                  'Nomor paket / tanda terima pengadilan (simulasi)',
                              border: OutlineInputBorder())),
                    if (workflow.current == 11) ...[
                      const Text(
                          'Gunakan jumlah pembayaran yang didukung bukti transaksi melalui kanal resmi dan konfirmasi penerimaan korban.'),
                      Text(
                          'Pembayaran terverifikasi sejauh ini: Rp ${workflow.restitutionPaidTotal}'),
                      TextField(
                          controller: restitutionDue,
                          readOnly: (workflow
                                  .restitutionPayments[workflow.activeCaseId]
                                  ?.isNotEmpty ??
                              false),
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: 'Total pemulihan dalam akta (Rp)',
                              border: OutlineInputBorder())),
                      TextField(
                          controller: restitutionPaid,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText: 'Pembayaran terverifikasi (Rp)',
                              border: OutlineInputBorder())),
                      CheckboxListTile(
                          value: paymentProofVerified,
                          onChanged: (value) => setState(
                              () => paymentProofVerified = value ?? false),
                          title: const Text(
                              'Bukti transaksi kanal resmi telah diperiksa')),
                      CheckboxListTile(
                          value: victimConfirmed,
                          onChanged: (value) =>
                              setState(() => victimConfirmed = value ?? false),
                          title: const Text(
                              'Penerimaan cicilan dikonfirmasi korban / pendamping')),
                      TextField(
                          controller: restitutionProof,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                              labelText:
                                  'Nomor bukti transfer / konfirmasi korban',
                              border: OutlineInputBorder()))
                    ],
                    if (workflow.current == 4) ...[
                      TextField(
                          controller: victimDamage,
                          onChanged: (_) => setState(() {}),
                          maxLines: 3,
                          decoration: const InputDecoration(
                              labelText:
                                  'Dampak / nilai kerugian atau catatan belum terukur',
                              border: OutlineInputBorder())),
                      TextField(
                          controller: victimProtection,
                          onChanged: (_) => setState(() {}),
                          maxLines: 2,
                          decoration: const InputDecoration(
                              labelText: 'Kebutuhan perlindungan korban',
                              border: OutlineInputBorder())),
                      TextField(
                          controller: victimPreference,
                          onChanged: (_) => setState(() {}),
                          maxLines: 2,
                          decoration: const InputDecoration(
                              labelText:
                                  'Preferensi kehadiran dan bentuk pemulihan',
                              border: OutlineInputBorder()))
                    ],
                    if (workflow.current == 5) ...[
                      const Text(
                          'Masukkan batas dan usulan menurut jenis sanksi yang ditetapkan kebijakan. Angka demo tidak boleh dipakai sebagai rekomendasi pidana.'),
                      TextField(
                          controller: rangeLow,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Batas bawah (satuan kebijakan)',
                              border: OutlineInputBorder())),
                      TextField(
                          controller: rangeHigh,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Batas atas (satuan kebijakan)',
                              border: OutlineInputBorder())),
                      TextField(
                          controller: proposedPenalty,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'Usulan JPU (satuan yang sama)',
                              border: OutlineInputBorder())),
                      if (double.tryParse(proposedPenalty.text) != null &&
                          double.tryParse(rangeLow.text) != null &&
                          double.tryParse(rangeHigh.text) != null &&
                          (double.parse(proposedPenalty.text) <
                                  double.parse(rangeLow.text) ||
                              double.parse(proposedPenalty.text) >
                                  double.parse(rangeHigh.text))) ...[
                        TextField(
                            controller: kasiApprovalRef,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText:
                                    'Referensi persetujuan Kasi Pidum (pemberi persetujuan berbeda)',
                                border: OutlineInputBorder())),
                        TextField(
                            controller: kajariApprovalRef,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                labelText:
                                    'Referensi persetujuan Kajari / pejabat berwenang berbeda',
                                border: OutlineInputBorder()))
                      ]
                    ],
                  ]))),
      const SizedBox(height: 18),
      FilledButton.icon(
          onPressed: checked &&
                  note.text.trim().length >= 20 &&
                  workflow.verifyAudit() &&
                  (workflow.current != 0 || screeningChecks.every((v) => v)) &&
                  (workflow.current != 1 ||
                      (sinarTouched.every((v) => v) &&
                          sinarReasons.every(
                              (reason) => reason.text.trim().length >= 8) &&
                          sinarScore >= 50 &&
                          (sinarScore >= 88 ||
                              sinarSupervisorRef.text.trim().isNotEmpty))) &&
                  (workflow.current != 2 || (secondChecked && jangkarValid)) &&
                  (workflow.current != 6 || gateChecks.every((v) => v)) &&
                  (workflow.current != 7 || conferenceChecks.every((v) => v)) &&
                  (workflow.current != 8 ||
                      (admission.text.trim().isNotEmpty &&
                          consequence.text.trim().isNotEmpty &&
                          harmRepair.text.trim().isNotEmpty)) &&
                  (workflow.current != 9 ||
                      courtReference.text.trim().isNotEmpty) &&
                  (workflow.current != 10 ||
                      (courtReference.text.trim().isNotEmpty &&
                          courtOutcome != 'Pilih hasil')) &&
                  (workflow.current != 4 ||
                      (victimDamage.text.trim().isNotEmpty &&
                          victimProtection.text.trim().isNotEmpty &&
                          victimPreference.text.trim().isNotEmpty)) &&
                  (workflow.current != 3 ||
                      !workflow.voluntary ||
                      nuraniSessionRef.text.trim().isNotEmpty) &&
                  (workflow.current != 5 || timbangValid) &&
                  (workflow.current != 7 || conferenceChecks.every((v) => v)) &&
                  (workflow.current != 11 ||
                      (restitutionDue.text.trim().isNotEmpty &&
                          restitutionPaid.text.trim().isNotEmpty &&
                          restitutionProof.text.trim().isNotEmpty &&
                          paymentProofVerified &&
                          victimConfirmed &&
                          int.tryParse(restitutionPaid.text) != null &&
                          int.tryParse(restitutionDue.text) != null &&
                          int.parse(restitutionPaid.text) > 0 &&
                          workflow.restitutionDueMatches(
                              int.parse(restitutionDue.text)) &&
                          workflow.restitutionPaidTotal +
                                  int.parse(restitutionPaid.text) <=
                              int.parse(restitutionDue.text)))
              ? () {
                  if (workflow.current == 3 && !workflow.voluntary) {
                    workflow.returnToStandard(
                        'NURANI menyatakan pengakuan tidak sukarela');
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'SUAR MERAH · Proses plea dihentikan dan dikembalikan ke proses biasa.')));
                    return;
                  }
                  if (workflow.current == 10 && courtOutcome != 'Disahkan') {
                    workflow.returnToStandard(
                        'Pengadilan $courtOutcome · ${courtReference.text.trim()} · ${note.text.trim()} · Firewall Pengakuan diterapkan');
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Plea dihentikan. Pengakuan dan rekaman NURANI dipisahkan dari proses biasa.')));
                    return;
                  }
                  if (workflow.current == 11) {
                    final amount = int.parse(restitutionPaid.text);
                    final due = int.parse(restitutionDue.text);
                    workflow.recordRestitutionPayment(
                        amount, due, restitutionProof.text.trim(),
                        proofVerified: paymentProofVerified,
                        victimConfirmed: victimConfirmed);
                    if (workflow.restitutionPaidTotal < due) {
                      setState(() {
                        restitutionPaid.clear();
                        restitutionProof.clear();
                        paymentProofVerified = false;
                        victimConfirmed = false;
                        checked = false;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(
                              'Cicilan tersimpan (${workflow.restitutionPaidTotal}/$due). Catat cicilan berikutnya untuk melanjutkan.')));
                      return;
                    }
                  }
                  if (workflow.current == 6) workflow.setGatePassed(true);
                  final record = <String, dynamic>{
                    'stage': stage,
                    'actor': 'Pengguna Demo',
                    'recordedAt': DateTime.now().toIso8601String(),
                    'reason': note.text.trim(),
                  };
                  if (workflow.current == 1) {
                    record['score'] = sinarScore;
                    record['ratings'] = sinarValues;
                    record['ratingReasons'] = sinarReasons
                        .map((reason) => reason.text.trim())
                        .toList();
                    record['signal'] = sinarScore >= 88
                        ? 'HIJAU'
                        : sinarScore >= 50
                            ? 'KUNING'
                            : 'MERAH';
                    record['supervisorApprovalReference'] =
                        sinarSupervisorRef.text.trim();
                  }
                  if (workflow.current == 2) {
                    record['evidence'] = evidenceStore.items
                        .where((item) => item.caseId == workflow.activeCaseId)
                        .map((item) =>
                            {'title': item.title, 'sha256': item.sha256})
                        .toList();
                    record['testedWithoutConfession'] = secondChecked;
                    record['evidenceMatrix'] = List.generate(
                        evidenceElements.length,
                        (i) => {
                              'element': evidenceElements[i].text.trim(),
                              'evidence': evidenceMappings[i]
                                  .whereType<String>()
                                  .map((key) => caseEvidence
                                      .where(
                                          (item) => _evidenceKey(item) == key)
                                      .first)
                                  .map((item) => {
                                        'title': item.title,
                                        'sha256': item.sha256
                                      })
                                  .toList()
                            });
                  }
                  if (workflow.current == 3) {
                    record['voluntary'] = workflow.voluntary;
                    record['lawyerPresent'] = checked;
                    record['sessionReference'] = nuraniSessionRef.text.trim();
                  }
                  if (workflow.current == 4) {
                    record['victimImpact'] = victimDamage.text.trim();
                    record['victimProtection'] = victimProtection.text.trim();
                    record['victimPreference'] = victimPreference.text.trim();
                  }
                  if (workflow.current == 5) {
                    record['rangeLow'] = rangeLow.text.trim();
                    record['rangeHigh'] = rangeHigh.text.trim();
                    record['proposedPenalty'] = proposedPenalty.text.trim();
                    record['kasiApprovalReference'] =
                        kasiApprovalRef.text.trim();
                    record['kajariApprovalReference'] =
                        kajariApprovalRef.text.trim();
                  }
                  if (workflow.current == 6) {
                    record['gates'] = gateLabels;
                    record['allGatesPassed'] = true;
                  }
                  if (workflow.current == 7) {
                    record['conferenceSteps'] = conferenceLabels;
                  }
                  if (workflow.current == 8) {
                    record['admission'] = admission.text.trim();
                    record['consequence'] = consequence.text.trim();
                    record['harmRepair'] = harmRepair.text.trim();
                  }
                  if (workflow.current == 9 || workflow.current == 10) {
                    record['courtReference'] = courtReference.text.trim();
                    record['courtOutcome'] = courtOutcome;
                  }
                  if (workflow.current == 11) {
                    record['restitutionDue'] = restitutionDue.text.trim();
                    record['restitutionPaid'] = workflow.restitutionPaidTotal;
                    record['payments'] =
                        workflow.restitutionPayments[workflow.activeCaseId];
                  }
                  record['recordHash'] = workflow.hashStageRecord(record);
                  workflow.stageRecords[
                          '${workflow.activeCaseId ?? 'tanpa-perkara'}:${workflow.current}'] =
                      record;
                  workflow.recordAudit(
                      'Keputusan tahap $stage disimpan oleh Pengguna Demo · SHA-256 ${record['recordHash']} · ${jsonEncode(record)}');
                  workflow.advance('Pengguna Demo');
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content:
                          Text('$stage tersimpan dan workflow diperbarui.')));
                }
              : null,
          style: FilledButton.styleFrom(
              backgroundColor: navy, padding: const EdgeInsets.all(17)),
          icon: const Icon(Icons.save_outlined),
          label: Text(workflow.current == 11
              ? (int.tryParse(restitutionPaid.text) != null &&
                      int.tryParse(restitutionDue.text) != null &&
                      workflow.restitutionPaidTotal +
                              int.parse(restitutionPaid.text) >=
                          int.parse(restitutionDue.text)
                  ? 'Konfirmasi PULIH lunas dan lanjut'
                  : 'Catat cicilan pemulihan')
              : 'Simpan dan lanjutkan')),
      const SizedBox(height: 10),
      OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kembali tanpa menyelesaikan tahap')),
      if (workflow.current == 1 && sinarScore < 50)
        FilledButton.tonalIcon(
            onPressed: note.text.trim().length < 20 ||
                    !workflow.verifyAudit() ||
                    !workflow.verifyStageRecords()
                ? null
                : () {
                    workflow.returnToStandard(
                        'SINAR MERAH · skor $sinarScore · ${note.text.trim()}');
                    Navigator.pop(context);
                  },
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Hentikan dan kembali ke proses biasa'))
    ])));
  }

  (String, IconData, String, String, String) _stageConfig(String stage) =>
      switch (workflow.current) {
        0 => (
            'Periksa syarat formil dan kelengkapan identitas perkara.',
            Icons.screen_search_desktop_outlined,
            'SARING · Penyaringan awal',
            'Hasil pemeriksaan dan dasar dokumen',
            'Syarat formil telah diverifikasi'
          ),
        1 => (
            'Nilai delapan parameter. Skor SINAR hanya alat bantu; nilai harus beralasan dan tertaut bukti.',
            Icons.fact_check_outlined,
            'SINAR · Indeks kelayakan',
            'Alasan penilaian',
            'Skor dan dokumen pendukung telah ditinjau'
          ),
        2 => (
            'Apakah perkara tetap berdiri bila pengakuan dicabut? Petakan unsur pasal ke sekurangnya dua alat bukti.',
            Icons.anchor_outlined,
            'JANGKAR · Bukti tanpa pengakuan',
            'Matriks unsur dan alat bukti',
            'Kecukupan bukti tanpa pengakuan dikonfirmasi'
          ),
        3 => (
            'Sesi kesukarelaan wajib dihadiri advokat. Gagal berarti plea dihentikan.',
            Icons.record_voice_over_outlined,
            'NURANI · Uji kesukarelaan',
            'Catatan sesi dan pernyataan advokat',
            'Advokat hadir dan hak terdakwa dijelaskan'
          ),
        4 => (
            'Catat dampak, klaim kerugian, kebutuhan perlindungan, dan preferensi keterlibatan korban.',
            Icons.volunteer_activism_outlined,
            'SUARA KORBAN · Asesmen dampak',
            'Ringkasan dampak dan klaim',
            'Pendapat serta kebutuhan korban dicatat'
          ),
        5 => (
            'Tinjau rentang konsekuensi dan alasan hukum. Usulan di luar rentang memerlukan persetujuan berjenjang.',
            Icons.balance_outlined,
            'TIMBANG · Proporsionalitas',
            'Legal reasoning',
            'Rentang dan dasar proporsionalitas ditinjau'
          ),
        6 => (
            'Lima gerbang: hukum, bukti, kesukarelaan, korban/kepentingan umum, proporsionalitas/integritas.',
            Icons.shield_outlined,
            'GERBANG · Lima pemeriksaan',
            'Catatan pemeriksaan gerbang',
            'Semua gerbang telah dikonfirmasi pejabat berwenang'
          ),
        7 => (
            'Ikuti sembilan langkah konferensi. Rekam peserta, konfirmasi hak, bukti, korban, dan kendali mutu.',
            Icons.groups_outlined,
            'FORUM VERITAS · Konferensi',
            'Notula konferensi',
            'Agenda dan peserta forum telah diverifikasi'
          ),
        8 => (
            'Akta wajib memuat pengakuan perbuatan, konsekuensi pidana, dan pemulihan korban.',
            Icons.draw_outlined,
            'AKTA · Kesepakatan',
            'Catatan draf dan persetujuan',
            'Tiga komponen akta telah ditinjau'
          ),
        9 => (
            'Siapkan pelimpahan elektronik ke pengadilan. Dokumen pengakuan dipisahkan bila kesepakatan ditolak.',
            Icons.account_balance_outlined,
            'SAMBUNG · Pelimpahan',
            'Nomor paket pengadilan',
            'Paket pelimpahan telah diverifikasi'
          ),
        10 => (
            'Catat penetapan hakim. Putusan pengadilan menjadi dasar tahap pemulihan.',
            Icons.gavel_outlined,
            'PUTUSAN · Penetapan hakim',
            'Ringkasan penetapan',
            'Salinan penetapan telah diverifikasi'
          ),
        11 => (
            'Pantau pembayaran melalui kanal resmi dan konfirmasi penerimaan korban.',
            Icons.handshake_outlined,
            'PULIH · Pemulihan korban',
            'Status pemulihan dan bukti',
            'Pemenuhan kewajiban telah diperiksa'
          ),
        _ => (
            'Tinjau kepatuhan prosedur dan temuan mutu sebelum perkara ditutup.',
            Icons.verified_outlined,
            'CAKRAWALA · Kendali mutu',
            'Temuan dan tindak lanjut',
            'Tinjauan mutu telah diselesaikan'
          ),
      };
}

class _WorkflowStage extends StatelessWidget {
  const _WorkflowStage(
      {required this.index,
      required this.label,
      required this.active,
      required this.done});
  final int index;
  final String label;
  final bool active, done;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          SizedBox(
              width: 36,
              child: Column(children: [
                CircleAvatar(
                    radius: 14,
                    backgroundColor: done
                        ? Colors.green
                        : active
                            ? navy
                            : const Color(0xFFE2E8F0),
                    child: Icon(
                        done
                            ? Icons.check
                            : active
                                ? Icons.radio_button_checked
                                : Icons.circle_outlined,
                        color: done || active
                            ? Colors.white
                            : const Color(0xFF94A3B8),
                        size: 16)),
                if (index < workflow.stages.length - 1)
                  Container(
                      width: 2,
                      height: 28,
                      color: done ? Colors.green : const Color(0xFFE2E8F0)),
              ])),
          const SizedBox(width: 12),
          Expanded(
              child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.only(
                      bottom: 22, left: 8, right: 8, top: 6),
                  decoration: BoxDecoration(
                      color:
                          active ? const Color(0xFFEFF6FF) : Colors.transparent,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('${index + 1}. $label',
                      style: TextStyle(
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w500,
                          color: active
                              ? navy
                              : done
                                  ? const Color(0xFF247A50)
                                  : const Color(0xFF64748B))))),
        ]),
      );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, required this.open});
  final ValueChanged<Widget> open;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final notices = <_Notice>[];
  @override
  void initState() {
    super.initState();
    final active = caseStore.active;
    if (active != null &&
        !workflow.completed &&
        !workflow.stoppedForStandardProcess) {
      notices.add(_Notice(
          'Tahap menunggu tindakan',
          '${active.number} · ${workflow.stages[workflow.current]}',
          Icons.pending_actions_outlined,
          Colors.orange,
          false));
    }
    if (!workflow.verifyAudit() || !workflow.verifyStageRecords()) {
      notices.add(_Notice(
          'Integritas perlu ditinjau',
          'Rantai JEJAK tidak cocok. Transisi workflow dikunci.',
          Icons.gpp_bad_outlined,
          Colors.red,
          false));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          Row(children: [
            const Expanded(
                child: Text('Notifikasi',
                    style:
                        TextStyle(fontSize: 25, fontWeight: FontWeight.w800))),
            TextButton(
                onPressed: () => setState(() {
                      for (final n in notices) {
                        n.read = true;
                      }
                    }),
                child: const Text('Tandai semua dibaca'))
          ]),
          const Text('Pemberitahuan mengikuti akses perkara dan peran Anda.',
              style: TextStyle(color: Color(0xFF63758D))),
          const SizedBox(height: 18),
          if (notices.isEmpty)
            const SoftBanner(
                text:
                    'Tidak ada notifikasi perkara. Notifikasi push dari layanan server belum terhubung.',
                icon: Icons.notifications_none),
          ...notices.map((n) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                    color: n.read ? Colors.white : const Color(0xFFF0F7FF),
                    child: ListTile(
                      onTap: () {
                        setState(() => n.read = true);
                        widget.open(const CaseDetailPage());
                      },
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                              color: n.color.withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(13)),
                          child: Icon(n.icon, color: n.color)),
                      title: Text(n.title,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Text(n.message)),
                      trailing: n.read
                          ? const Icon(Icons.chevron_right)
                          : const Badge(smallSize: 9),
                    )),
              )),
          const SizedBox(height: 10),
          OutlinedButton.icon(
              onPressed: () => widget.open(const AuditTrailPage()),
              icon: const Icon(Icons.history),
              label: const Text('Lihat Audit Trail'))
        ])),
      );
}

class _Notice {
  _Notice(this.title, this.message, this.icon, this.color, this.read);
  final String title, message;
  final IconData icon;
  final Color color;
  bool read;
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, required this.open, required this.onSignOut});
  final ValueChanged<Widget> open;
  final VoidCallback onSignOut;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        const Text('Profil',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
        const SizedBox(height: 22),
        Card(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  const CircleAvatar(
                      radius: 32,
                      backgroundColor: navy,
                      child: Text('PD',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800))),
                  const SizedBox(width: 16),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(DemoSession.name,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text('Peran simulasi · ${DemoSession.role}'),
                        const SizedBox(height: 5),
                        const StatusPill('Mode prototipe', Colors.orange)
                      ])),
                  IconButton(
                      onPressed: () => open(const EditProfilePage()),
                      icon: const Icon(Icons.edit_outlined, color: navy))
                ]))),
        sectionTitle('Akun & Keamanan'),
        ProfileRow(
            Icons.person_outline,
            'Data profil',
            'Nama, kontak, dan unit kerja',
            () => open(const EditProfilePage())),
        ProfileRow(Icons.shield_outlined, 'Keamanan',
            'Biometrik, PIN, dan perangkat', () => open(const SecurityPage())),
        ProfileRow(Icons.devices_outlined, 'Sesi aktif', '1 perangkat aktif',
            () => open(const SessionsPage())),
        sectionTitle('Aplikasi'),
        ProfileRow(
            Icons.tune_outlined,
            'Preferensi notifikasi',
            'Atur pengingat dan alert',
            () => open(const NotificationSettingsPage())),
        ProfileRow(Icons.help_outline, 'Pusat bantuan',
            'Panduan alur dan kontak dukungan', () => open(const HelpPage())),
        ProfileRow(Icons.policy_outlined, 'Kebijakan & privasi',
            'Klasifikasi data dan penggunaan', () => open(const PolicyPage())),
        const SizedBox(height: 18),
        OutlinedButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Keluar dari akun'),
            style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                minimumSize: const Size.fromHeight(54),
                side: const BorderSide(color: Color(0xFFFFCDD2))))
      ])));
}

class ProfileRow extends StatelessWidget {
  const ProfileRow(this.icon, this.title, this.detail, this.tap, {super.key});
  final IconData icon;
  final String title, detail;
  final VoidCallback tap;
  @override
  Widget build(BuildContext context) => Card(
      child: ListTile(
          onTap: tap,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
          leading: Icon(icon, color: navy),
          title:
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(detail),
          trailing: const Icon(Icons.chevron_right)));
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final name = TextEditingController(text: 'Pengguna Demo');
  final phone = TextEditingController(text: '+62 812 3456 7890');
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Data Profil'),
        const SizedBox(height: 20),
        const Center(
            child: CircleAvatar(
                radius: 42,
                backgroundColor: navy,
                child: Text('AS',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold)))),
        const SizedBox(height: 24),
        TextField(
            controller: name,
            decoration: const InputDecoration(
                labelText: 'Nama lengkap', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        TextField(
            decoration: InputDecoration(
                labelText: 'Email institusi', border: OutlineInputBorder()),
            controller:
                TextEditingController(text: 'andi.saputra@kejaksaan.go.id')),
        const SizedBox(height: 14),
        TextField(
            controller: phone,
            decoration: const InputDecoration(
                labelText: 'Nomor telepon', border: OutlineInputBorder())),
        const SizedBox(height: 14),
        const TextField(
            readOnly: true,
            decoration: InputDecoration(
                labelText: 'Unit kerja',
                border: OutlineInputBorder(),
                hintText: 'Kejaksaan Negeri Jakarta Selatan')),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Data profil tersimpan.')));
              Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
                backgroundColor: navy, padding: const EdgeInsets.all(16)),
            child: const Text('Simpan Perubahan'))
      ])));
}

class SecurityPage extends StatefulWidget {
  const SecurityPage({super.key});
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  bool biometric = true, mfa = true;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Keamanan'),
        const SizedBox(height: 20),
        SwitchListTile(
            value: biometric,
            onChanged: (v) => setState(() => biometric = v),
            title: const Text('Masuk dengan biometrik'),
            subtitle:
                const Text('Gunakan Face ID atau Touch ID pada perangkat ini')),
        SwitchListTile(
            value: mfa,
            onChanged: (v) => setState(() => mfa = v),
            title: const Text('Verifikasi dua langkah'),
            subtitle: const Text('Wajib untuk tindakan sensitif')),
        const Divider(),
        ListTile(
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    'Link penggantian kata sandi dikirim ke email institusi.'))),
            leading: const Icon(Icons.password, color: navy),
            title: const Text('Ubah kata sandi'),
            trailing: const Icon(Icons.chevron_right)),
        const SizedBox(height: 20),
        const SoftBanner(
            text:
                'Aksi persetujuan, tanda tangan, dan pengajuan tetap memerlukan verifikasi server.',
            icon: Icons.info_outline)
      ])));
}

class SessionsPage extends StatelessWidget {
  const SessionsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Sesi Aktif'),
        const SizedBox(height: 20),
        const Card(
            child: ListTile(
                contentPadding: EdgeInsets.all(18),
                leading: Icon(Icons.phone_iphone, color: navy),
                title: Text('iPhone perangkat ini',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('Aktif sekarang • Jakarta, Indonesia'),
                trailing: StatusPill('Aktif', Colors.green))),
        const SizedBox(height: 16),
        OutlinedButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Tidak ada sesi lain yang dapat dicabut.'))),
            child: const Text('Kelola perangkat lain'))
      ])));
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool push = true, review = true, deadline = true;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Preferensi Notifikasi'),
        const SizedBox(height: 16),
        SwitchListTile(
            value: push,
            onChanged: (v) => setState(() => push = v),
            title: const Text('Notifikasi aplikasi'),
            subtitle: const Text('Tugas dan pembaruan perkara')),
        SwitchListTile(
            value: review,
            onChanged: (v) => setState(() => review = v),
            title: const Text('Review dan persetujuan'),
            subtitle: const Text('Status supervisor, court, dan signature')),
        SwitchListTile(
            value: deadline,
            onChanged: (v) => setState(() => deadline = v),
            title: const Text('Pengingat tenggat'),
            subtitle: const Text('Restitusi, conference, dan quality review'))
      ])));
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Pusat Bantuan'),
        const SizedBox(height: 20),
        const SoftBanner(
            text:
                'Alur perkara mengikuti policy aktif dan selalu membutuhkan konfirmasi manusia.',
            icon: Icons.support_agent),
        const SizedBox(height: 16),
        ...[
          'Memulai assessment perkara',
          'Mengunggah dan memverifikasi bukti',
          'Mengelola restitution dan dampak korban',
          'Mengajukan supervisor review'
        ].map((x) => Card(
            child: ListTile(
                title: Text(x),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                            title: Text(x),
                            content: const Text(
                                'Panduan demo: lengkapi data pada tahap aktif, simpan draft, lalu kirim untuk review sesuai peran.'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Tutup'))
                            ])))))
      ])));
}

class PolicyPage extends StatelessWidget {
  const PolicyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
        pageHeader(context, 'Kebijakan & Privasi'),
        const SizedBox(height: 20),
        const Text(
            'Data perkara, bukti, identitas korban, dan dokumen kesepakatan termasuk data sensitif.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        const Text(
            'Aplikasi demo ini menyimpan state hanya di perangkat. Implementasi produksi wajib memakai RBAC, audit log immutable, storage privat, enkripsi, serta policy server-side seperti pada PRD.'),
        const SizedBox(height: 20),
        const Card(
            child: ListTile(
                leading: Icon(Icons.policy, color: navy),
                title: Text('Policy version MVP-2026.1'),
                subtitle: Text(
                    'Threshold dan approval chain hanya contoh konfigurasi')))
      ])));
}

class AuditTrailPage extends StatelessWidget {
  const AuditTrailPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: AnimatedBuilder(
              animation: workflow,
              builder: (_, __) =>
                  ListView(padding: const EdgeInsets.all(20), children: [
                    pageHeader(context, 'Audit Trail'),
                    const SizedBox(height: 12),
                    const Text(
                        'Catatan lokal berantai SHA-256. Ini menunjukkan perubahan terdeteksi pada manifest perangkat, tetapi bukan pengganti ledger append-only server.',
                        style: TextStyle(color: Color(0xFF63758D))),
                    const SizedBox(height: 16),
                    SoftBanner(
                        text: workflow.verifyAudit() &&
                                workflow.verifyStageRecords()
                            ? 'Rantai terverifikasi · ${workflow.auditHashes.length} kejadian · head ${workflow.auditHashes.isEmpty ? "GENESIS" : workflow.auditHead.substring(0, 16)}'
                            : 'RANTAI AUDIT TIDAK VALID · Pengajuan tahap berikutnya dikunci.',
                        icon: workflow.verifyAudit() &&
                                workflow.verifyStageRecords()
                            ? Icons.verified_outlined
                            : Icons.gpp_bad_outlined,
                        greenStyle: workflow.verifyAudit() &&
                            workflow.verifyStageRecords()),
                    const SizedBox(height: 12),
                    ...workflow.audit.reversed.map((e) => Card(
                        child: ListTile(
                            leading: const Icon(Icons.history, color: navy),
                            title: Text(e))))
                  ]))));
}
