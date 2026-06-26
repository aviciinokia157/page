import 'dart:math';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xls;
import 'package:file_saver/file_saver.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final options = DefaultFirebaseOptions.currentPlatform;
  var firebaseReady = false;
  if (!options.apiKey.startsWith('SUBSTITUA')) {
    try {
      await Firebase.initializeApp(options: options);
      firebaseReady = true;
    } catch (_) {
      firebaseReady = false;
    }
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(firebaseReady: firebaseReady)..bootstrap(),
      child: const ReservaDeConvidadosApp(),
    ),
  );
}

enum UserRole { mainAdmin, admin, user }
enum GuestTableStatus { free, reserved, blocked }
enum ReservationStatus { pending, confirmed, changed, cancelled, checkedIn }

class AppUser {
  AppUser({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.email,
    required this.createdAt,
    this.photoUrl,
    this.role = UserRole.user,
    this.blocked = false,
  });

  final String id;
  String fullName;
  String phone;
  String email;
  String? photoUrl;
  UserRole role;
  bool blocked;
  final DateTime createdAt;

  bool get isAdmin => role == UserRole.admin || role == UserRole.mainAdmin;
  bool get isMainAdmin => role == UserRole.mainAdmin;
}

class DiningTable {
  DiningTable({
    required this.id,
    required this.number,
    required this.capacity,
    required this.x,
    required this.y,
    this.blocked = false,
  });

  final String id;
  int number;
  int capacity;
  double x;
  double y;
  bool blocked;
}

class GuestReservation {
  GuestReservation({
    required this.id,
    required this.userId,
    required this.responsibleName,
    required this.phone,
    required this.email,
    required this.tableId,
    required this.tableNumber,
    required this.date,
    required this.time,
    required this.guests,
    required this.status,
    required this.createdAt,
    this.notes = '',
  });

  final String id;
  final String userId;
  String responsibleName;
  String phone;
  String email;
  String tableId;
  int tableNumber;
  DateTime date;
  TimeOfDay time;
  int guests;
  String notes;
  ReservationStatus status;
  final DateTime createdAt;
}

class AuditLog {
  AuditLog({required this.message, required this.userName, required this.at});

  final String message;
  final String userName;
  final DateTime at;
}

class AppNotification {
  AppNotification({
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
  });

  final String title;
  final String body;
  final DateTime createdAt;
  bool read;
}

class BrandSettings {
  String venueName = 'Reserva de Convidados';
  String logoUrl = '';
  String coverUrl = '';
  Color seedColor = const Color(0xFF0F766E);
  TimeOfDay opensAt = const TimeOfDay(hour: 18, minute: 0);
  TimeOfDay closesAt = const TimeOfDay(hour: 23, minute: 30);
  bool usersCanEditReservations = true;
}

class AppState extends ChangeNotifier {
  AppState({required this.firebaseReady});

  final bool firebaseReady;
  final settings = BrandSettings();
  final users = <AppUser>[];
  final tables = <DiningTable>[];
  final reservations = <GuestReservation>[];
  final waitList = <GuestReservation>[];
  final logs = <AuditLog>[];
  final notifications = <AppNotification>[];

  AppUser? currentUser;
  bool darkMode = false;
  String search = '';

  bool get isLoggedIn => currentUser != null;
  bool get isAdmin => currentUser?.isAdmin ?? false;
  bool get isMainAdmin => currentUser?.isMainAdmin ?? false;

  void bootstrap() {
    if (users.isNotEmpty) return;
    final now = DateTime.now();
    users.addAll([
      AppUser(
        id: 'u-main',
        fullName: 'Administrador Principal',
        phone: '(11) 90000-0000',
        email: 'admin@reserva.app',
        role: UserRole.mainAdmin,
        createdAt: now.subtract(const Duration(days: 90)),
      ),
      AppUser(
        id: 'u-ana',
        fullName: 'Ana Martins',
        phone: '(21) 98888-1122',
        email: 'ana@email.com',
        createdAt: now.subtract(const Duration(days: 18)),
      ),
      AppUser(
        id: 'u-caio',
        fullName: 'Caio Souza',
        phone: '(31) 97777-4433',
        email: 'caio@email.com',
        createdAt: now.subtract(const Duration(days: 9)),
      ),
    ]);
    currentUser = users.first;

    for (var i = 0; i < 18; i++) {
      tables.add(
        DiningTable(
          id: 't-' + i.toString(),
          number: i + 1,
          capacity: const [2, 4, 4, 6, 8, 10][i % 6],
          x: (i % 6) / 5,
          y: (i ~/ 6) / 2,
          blocked: i == 13,
        ),
      );
    }

    _seedReservation('u-ana', 'Ana Martins', 2, 4, 20, 0,
        ReservationStatus.confirmed, 'Aniversario com mesa proxima a janela.');
    _seedReservation('u-caio', 'Caio Souza', 6, 6, 21, 30,
        ReservationStatus.pending, 'Chegara com duas criancas.');
    _seedReservation('u-ana', 'Ana Martins', 8, 2, 19, 0,
        ReservationStatus.changed, 'Preferencia por area silenciosa.');
    log('Sistema iniciado com dados de demonstracao.');
  }

  void _seedReservation(String userId, String name, int tableNumber, int guests,
      int hour, int minute, ReservationStatus status, String notes) {
    final user = users.firstWhere((item) => item.id == userId);
    final table = tables.firstWhere((item) => item.number == tableNumber);
    reservations.add(
      GuestReservation(
        id: 'r-' + (reservations.length + 1).toString(),
        userId: userId,
        responsibleName: name,
        phone: user.phone,
        email: user.email,
        tableId: table.id,
        tableNumber: table.number,
        date: DateTime.now(),
        time: TimeOfDay(hour: hour, minute: minute),
        guests: guests,
        status: status,
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        notes: notes,
      ),
    );
  }

  List<GuestReservation> get visibleReservations {
    final base = isAdmin
        ? reservations
        : reservations.where((item) => item.userId == currentUser?.id).toList();
    final term = search.trim().toLowerCase();
    if (term.isEmpty) return base;
    return base.where((item) {
      return item.responsibleName.toLowerCase().contains(term) ||
          item.phone.toLowerCase().contains(term) ||
          item.email.toLowerCase().contains(term) ||
          item.tableNumber.toString().contains(term) ||
          dateLabel(item.date).contains(term) ||
          timeLabel(item.time).contains(term) ||
          reservationStatusLabel(item.status).toLowerCase().contains(term);
    }).toList();
  }

  GuestTableStatus tableStatus(DiningTable table, DateTime date, TimeOfDay time) {
    if (table.blocked) return GuestTableStatus.blocked;
    final taken = reservations.any((item) =>
        item.tableId == table.id &&
        sameDay(item.date, date) &&
        sameTime(item.time, time) &&
        item.status != ReservationStatus.cancelled);
    return taken ? GuestTableStatus.reserved : GuestTableStatus.free;
  }

  bool createAccount({
    required String fullName,
    required String phone,
    required String email,
  }) {
    if (users.any((item) => item.email.toLowerCase() == email.toLowerCase())) {
      return false;
    }
    final role = users.isEmpty ? UserRole.mainAdmin : UserRole.user;
    final user = AppUser(
      id: 'u-' + DateTime.now().microsecondsSinceEpoch.toString(),
      fullName: fullName.trim().isEmpty ? 'Novo usuario' : fullName.trim(),
      phone: phone.trim(),
      email: email.trim(),
      role: role,
      createdAt: DateTime.now(),
    );
    users.add(user);
    currentUser = user;
    log('Conta criada para ' + user.fullName + '.');
    notifyListeners();
    return true;
  }

  bool login(String email) {
    final matches = users.where(
      (item) => item.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (matches.isEmpty || matches.first.blocked) return false;
    currentUser = matches.first;
    log('Login realizado por ' + currentUser!.fullName + '.');
    notifyListeners();
    return true;
  }

  void logout() {
    currentUser = null;
    notifyListeners();
  }

  bool createReservation({
    required DiningTable table,
    required DateTime date,
    required TimeOfDay time,
    required int guests,
    required String name,
    required String notes,
  }) {
    if (currentUser == null) return false;
    if (!insideBusinessHours(time)) return false;
    if (guests > table.capacity) return false;

    final status = tableStatus(table, date, time);
    if (status != GuestTableStatus.free) {
      waitList.add(
        GuestReservation(
          id: 'w-' + DateTime.now().microsecondsSinceEpoch.toString(),
          userId: currentUser!.id,
          responsibleName: name,
          phone: currentUser!.phone,
          email: currentUser!.email,
          tableId: table.id,
          tableNumber: table.number,
          date: date,
          time: time,
          guests: guests,
          status: ReservationStatus.pending,
          createdAt: DateTime.now(),
          notes: notes,
        ),
      );
      log(name + ' entrou na lista de espera.');
      pushNotification('Lista de espera', 'Avisaremos quando houver uma mesa livre.');
      notifyListeners();
      return false;
    }

    reservations.add(
      GuestReservation(
        id: 'r-' + DateTime.now().microsecondsSinceEpoch.toString(),
        userId: currentUser!.id,
        responsibleName: name.trim().isEmpty ? currentUser!.fullName : name.trim(),
        phone: currentUser!.phone,
        email: currentUser!.email,
        tableId: table.id,
        tableNumber: table.number,
        date: date,
        time: time,
        guests: guests,
        status: ReservationStatus.confirmed,
        createdAt: DateTime.now(),
        notes: notes.trim(),
      ),
    );
    log('Reserva criada na mesa ' + table.number.toString() + '.');
    pushNotification('Reserva confirmada', 'Sua reserva foi confirmada para ' + dateLabel(date) + ' as ' + timeLabel(time) + '.');
    notifyListeners();
    return true;
  }

  void cancelReservation(GuestReservation reservation) {
    reservation.status = ReservationStatus.cancelled;
    log('Reserva de ' + reservation.responsibleName + ' cancelada.');
    pushNotification('Reserva cancelada', 'A reserva da mesa ' + reservation.tableNumber.toString() + ' foi cancelada.');
    notifyListeners();
  }

  void checkIn(GuestReservation reservation) {
    reservation.status = ReservationStatus.checkedIn;
    log('Presenca confirmada por QR Code para ' + reservation.responsibleName + '.');
    notifyListeners();
  }

  void upsertTable(DiningTable table) {
    final index = tables.indexWhere((item) => item.id == table.id);
    if (index == -1) {
      tables.add(table);
      log('Mesa ' + table.number.toString() + ' criada.');
    } else {
      tables[index] = table;
      log('Mesa ' + table.number.toString() + ' atualizada.');
    }
    notifyListeners();
  }

  void removeTable(DiningTable table) {
    tables.removeWhere((item) => item.id == table.id);
    log('Mesa ' + table.number.toString() + ' excluida.');
    notifyListeners();
  }

  void toggleTableBlock(DiningTable table) {
    table.blocked = !table.blocked;
    log(table.blocked ? 'Mesa bloqueada.' : 'Mesa liberada.');
    notifyListeners();
  }

  void moveTable(DiningTable table, double dx, double dy) {
    table.x = (table.x + dx).clamp(0.0, 1.0);
    table.y = (table.y + dy).clamp(0.0, 1.0);
    notifyListeners();
  }

  void toggleUserBlock(AppUser user) {
    if (user.isMainAdmin) return;
    user.blocked = !user.blocked;
    log(user.blocked ? 'Usuario bloqueado.' : 'Usuario desbloqueado.');
    notifyListeners();
  }

  void deleteUser(AppUser user) {
    if (user.isMainAdmin) return;
    users.removeWhere((item) => item.id == user.id);
    log('Usuario ' + user.fullName + ' excluido.');
    notifyListeners();
  }

  void setUserRole(AppUser user, UserRole role) {
    if (!isMainAdmin || user.isMainAdmin) return;
    user.role = role;
    log('Permissao de ' + user.fullName + ' alterada.');
    notifyListeners();
  }

  void updateProfile(String name, String phone) {
    currentUser?.fullName = name.trim();
    currentUser?.phone = phone.trim();
    log('Perfil atualizado.');
    notifyListeners();
  }

  void updateSettings({
    String? venueName,
    TimeOfDay? opensAt,
    TimeOfDay? closesAt,
    bool? usersCanEditReservations,
    Color? color,
  }) {
    settings.venueName = venueName ?? settings.venueName;
    settings.opensAt = opensAt ?? settings.opensAt;
    settings.closesAt = closesAt ?? settings.closesAt;
    settings.usersCanEditReservations = usersCanEditReservations ?? settings.usersCanEditReservations;
    settings.seedColor = color ?? settings.seedColor;
    log('Configuracoes atualizadas.');
    notifyListeners();
  }

  void updateSearch(String value) {
    search = value;
    notifyListeners();
  }

  void toggleTheme() {
    darkMode = !darkMode;
    notifyListeners();
  }

  bool insideBusinessHours(TimeOfDay time) {
    final current = time.hour * 60 + time.minute;
    final open = settings.opensAt.hour * 60 + settings.opensAt.minute;
    final close = settings.closesAt.hour * 60 + settings.closesAt.minute;
    return current >= open && current <= close;
  }

  void pushNotification(String title, String body) {
    notifications.insert(0, AppNotification(title: title, body: body, createdAt: DateTime.now()));
  }

  void log(String message) {
    logs.insert(0, AuditLog(message: message, userName: currentUser?.fullName ?? 'Sistema', at: DateTime.now()));
  }

  Future<void> exportPdf() async {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(level: 0, text: 'Relatorio - ' + settings.venueName),
          pw.Text('Reservas totais: ' + reservations.length.toString()),
          pw.SizedBox(height: 12),
          pw.TableHelper.fromTextArray(
            headers: ['Nome', 'Data', 'Hora', 'Mesa', 'Pessoas', 'Status'],
            data: reservations.map((item) => [
              item.responsibleName,
              dateLabel(item.date),
              timeLabel(item.time),
              item.tableNumber.toString(),
              item.guests.toString(),
              reservationStatusLabel(item.status),
            ]).toList(),
          ),
        ],
      ),
    );
    await FileSaver.instance.saveFile(
      name: 'relatorio_reservas',
      bytes: await doc.save(),
      ext: 'pdf',
      mimeType: MimeType.pdf,
    );
  }

  Future<void> exportExcel() async {
    final excel = xls.Excel.createExcel();
    final sheet = excel['Reservas'];
    sheet.appendRow([
      xls.TextCellValue('Nome'),
      xls.TextCellValue('Telefone'),
      xls.TextCellValue('Email'),
      xls.TextCellValue('Data'),
      xls.TextCellValue('Hora'),
      xls.TextCellValue('Mesa'),
      xls.TextCellValue('Convidados'),
      xls.TextCellValue('Status'),
    ]);
    for (final item in reservations) {
      sheet.appendRow([
        xls.TextCellValue(item.responsibleName),
        xls.TextCellValue(item.phone),
        xls.TextCellValue(item.email),
        xls.TextCellValue(dateLabel(item.date)),
        xls.TextCellValue(timeLabel(item.time)),
        xls.IntCellValue(item.tableNumber),
        xls.IntCellValue(item.guests),
        xls.TextCellValue(reservationStatusLabel(item.status)),
      ]);
    }
    await FileSaver.instance.saveFile(
      name: 'relatorio_reservas',
      bytes: Uint8List.fromList(excel.encode() ?? []),
      ext: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
  }
}

class ReservaDeConvidadosApp extends StatelessWidget {
  const ReservaDeConvidadosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Reserva de Convidados',
          themeMode: state.darkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: state.settings.seedColor,
            brightness: Brightness.light,
            inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorSchemeSeed: state.settings.seedColor,
            brightness: Brightness.dark,
            inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
          ),
          home: state.isLoggedIn ? const HomeShell() : const AuthScreen(),
        );
      },
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final name = TextEditingController(text: 'Novo Convidado');
  final phone = TextEditingController(text: '(11) 95555-0000');
  final email = TextEditingController(text: 'admin@reserva.app');
  final password = TextEditingController(text: '123456');
  var creating = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.secondaryContainer,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1120),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  final card = _buildAuthCard(state);
                  if (wide) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      const Expanded(flex: 6, child: AuthHero()),
                      const SizedBox(width: 28),
                      Expanded(flex: 4, child: card),
                    ]);
                  }
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    const AuthHero(),
                    const SizedBox(height: 20),
                    card,
                  ]);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthCard(AppState state) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.login_rounded), label: Text('Entrar')),
                ButtonSegment(value: true, icon: Icon(Icons.person_add_rounded), label: Text('Cadastrar')),
              ],
              selected: {creating},
              onSelectionChanged: (value) => setState(() => creating = value.first),
            ),
            const SizedBox(height: 16),
            if (creating) ...[
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome completo', prefixIcon: Icon(Icons.badge_rounded))),
              const SizedBox(height: 12),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Telefone', prefixIcon: Icon(Icons.phone_rounded))),
              const SizedBox(height: 12),
            ],
            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_rounded))),
            const SizedBox(height: 12),
            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Senha', prefixIcon: Icon(Icons.lock_rounded))),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => showSnack(context, 'Redefinicao de senha pronta para Firebase Auth.'),
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Esqueci a senha'),
              ),
            ),
            FilledButton.icon(
              onPressed: () {
                final ok = creating
                    ? state.createAccount(fullName: name.text, phone: phone.text, email: email.text)
                    : state.login(email.text);
                if (!ok) showSnack(context, 'Nao foi possivel concluir. Confira os dados.');
              },
              icon: Icon(creating ? Icons.person_add_alt_rounded : Icons.login_rounded),
              label: Text(creating ? 'Criar conta' : 'Entrar com e-mail'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(onPressed: () => showSnack(context, 'Login Google pronto para ativar.'), icon: const Icon(Icons.g_mobiledata_rounded), label: const Text('Continuar com Google')),
            OutlinedButton.icon(onPressed: defaultTargetPlatform == TargetPlatform.iOS || kIsWeb ? () => showSnack(context, 'Login Apple pronto para iOS.') : null, icon: const Icon(Icons.apple_rounded), label: const Text('Continuar com Apple')),
          ],
        ),
      ),
    );
  }
}

class AuthHero extends StatelessWidget {
  const AuthHero({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.restaurant_rounded, color: Colors.white, size: 38),
        ),
        const SizedBox(height: 18),
        Text('Reserva de Convidados', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text('Reservas, mapa de mesas, QR Code, relatorios e painel administrativo em uma experiencia unica para Android, iOS e Web.', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 22),
        Wrap(spacing: 10, runSpacing: 10, children: const [
          FeaturePill(icon: Icons.security_rounded, label: 'Firebase Auth'),
          FeaturePill(icon: Icons.cloud_done_rounded, label: 'Firestore'),
          FeaturePill(icon: Icons.notifications_rounded, label: 'Notificacoes'),
          FeaturePill(icon: Icons.qr_code_2_rounded, label: 'QR Code'),
        ]),
        const SizedBox(height: 22),
        Row(children: [
          Icon(state.firebaseReady ? Icons.check_circle_rounded : Icons.info_outline_rounded, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(state.firebaseReady ? 'Firebase conectado.' : 'Modo demonstracao ativo ate inserir as credenciais Firebase.')),
        ]),
      ],
    );
  }
}

class FeaturePill extends StatelessWidget {
  const FeaturePill({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(avatar: Icon(icon, size: 18), label: Text(label));
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var index = 0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final destinations = buildDestinations(state.isAdmin);
    if (index >= destinations.length) index = 0;
    final selected = destinations[index];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        return Scaffold(
          drawer: wide ? null : Drawer(
            child: SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.restaurant_rounded)),
                    title: Text(state.settings.venueName),
                    subtitle: Text(roleLabel(state.currentUser!.role)),
                  ),
                  const Divider(),
                  for (var i = 0; i < destinations.length; i++)
                    ListTile(
                      selected: i == index,
                      leading: Icon(destinations[i].icon),
                      title: Text(destinations[i].label),
                      onTap: () {
                        setState(() => index = i);
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
            ),
          ),
          appBar: AppBar(
            title: Row(children: [
              if (wide) CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary, child: const Icon(Icons.restaurant_rounded, color: Colors.white)),
              if (wide) const SizedBox(width: 12),
              Expanded(child: Text(state.settings.venueName)),
            ]),
            actions: [
              IconButton(tooltip: 'Pesquisar', onPressed: () => showSearchSheet(context), icon: const Icon(Icons.search_rounded)),
              IconButton(tooltip: 'Notificacoes', onPressed: () => showNotifications(context), icon: const Icon(Icons.notifications_rounded)),
              IconButton(tooltip: 'Modo claro/escuro', onPressed: state.toggleTheme, icon: Icon(state.darkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded)),
              if (wide) Padding(padding: const EdgeInsets.only(right: 12), child: Chip(label: Text(roleLabel(state.currentUser!.role)))),
            ],
          ),
          body: Row(children: [
            if (wide)
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (value) => setState(() => index = value),
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final item in destinations)
                    NavigationRailDestination(icon: Icon(item.icon), label: Text(item.label)),
                ],
              ),
            Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: selected.page)),
          ]),
        );
      },
    );
  }
}

class AppDestination {
  AppDestination(this.label, this.icon, this.page);
  final String label;
  final IconData icon;
  final Widget page;
}

List<AppDestination> buildDestinations(bool admin) => [
  AppDestination('Dashboard', Icons.dashboard_rounded, const DashboardScreen()),
  AppDestination('Nova reserva', Icons.add_circle_outline_rounded, const ReserveScreen()),
  AppDestination('Reservas', Icons.event_seat_rounded, const ReservationsScreen()),
  AppDestination('Calendario', Icons.calendar_month_rounded, const CalendarScreen()),
  if (admin) AppDestination('Mesas', Icons.table_bar_rounded, const TablesScreen()),
  if (admin) AppDestination('Usuarios', Icons.group_rounded, const UsersScreen()),
  if (admin) AppDestination('Relatorios', Icons.bar_chart_rounded, const ReportsScreen()),
  AppDestination('Perfil', Icons.settings_rounded, const SettingsScreen()),
];

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.title, required this.subtitle, required this.child, this.action});
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      key: ValueKey(title),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle),
              ])),
              if (action != null) action!,
            ]),
          ),
        ),
        SliverPadding(padding: const EdgeInsets.all(20), sliver: SliverToBoxAdapter(child: child)),
      ],
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final today = state.reservations.where((item) => sameDay(item.date, DateTime.now())).length;
    final future = state.reservations.where((item) => item.date.isAfter(DateTime.now())).length;
    final blocked = state.tables.where((item) => item.blocked).length;
    final occupied = state.tables.where((table) => state.tableStatus(table, DateTime.now(), const TimeOfDay(hour: 20, minute: 0)) == GuestTableStatus.reserved).length;

    return PageFrame(
      title: state.isAdmin ? 'Dashboard' : 'Minhas reservas',
      subtitle: state.isAdmin ? 'Visao geral operacional em tempo real.' : 'Acompanhe suas reservas, QR Codes e notificacoes.',
      action: FilledButton.icon(onPressed: () => showSearchSheet(context), icon: const Icon(Icons.search_rounded), label: const Text('Pesquisar')),
      child: Column(children: [
        ResponsiveGrid(children: [
          MetricCard(label: 'Total de reservas', value: state.reservations.length.toString(), icon: Icons.event_available_rounded),
          MetricCard(label: 'Reservas do dia', value: today.toString(), icon: Icons.today_rounded),
          MetricCard(label: 'Reservas futuras', value: future.toString(), icon: Icons.upcoming_rounded),
          MetricCard(label: 'Usuarios', value: state.users.length.toString(), icon: Icons.group_rounded),
          MetricCard(label: 'Mesas livres', value: (state.tables.length - occupied - blocked).toString(), icon: Icons.event_seat_rounded),
          MetricCard(label: 'Mesas bloqueadas', value: blocked.toString(), icon: Icons.block_rounded),
        ]),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth > 850;
          final chart = SizedBox(height: 310, child: ReservationsChart(state: state));
          final activity = ActivityPanel(logs: state.logs);
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: chart),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: activity),
            ]);
          }
          return Column(children: [chart, const SizedBox(height: 16), activity]);
        }),
      ]),
    );
  }
}

class ReserveScreen extends StatefulWidget {
  const ReserveScreen({super.key});

  @override
  State<ReserveScreen> createState() => _ReserveScreenState();
}

class _ReserveScreenState extends State<ReserveScreen> {
  DateTime date = DateTime.now();
  TimeOfDay time = const TimeOfDay(hour: 20, minute: 0);
  DiningTable? selectedTable;
  final guests = TextEditingController(text: '4');
  final name = TextEditingController();
  final notes = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.read<AppState>().currentUser;
    if (name.text.isEmpty) name.text = user?.fullName ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    selectedTable ??= state.tables.where((table) => state.tableStatus(table, date, time) == GuestTableStatus.free).firstOrNull;
    return PageFrame(
      title: 'Nova reserva',
      subtitle: 'Escolha data, horario, mesa livre e quantidade de convidados.',
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth > 920;
        final map = TableMap(date: date, time: time, selected: selectedTable, onSelect: (table) => setState(() => selectedTable = table));
        final form = ReservationForm(
          date: date,
          time: time,
          selectedTable: selectedTable,
          guests: guests,
          name: name,
          notes: notes,
          onDate: (value) => setState(() => date = value),
          onTime: (value) => setState(() => time = value),
        );
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: map),
            const SizedBox(width: 18),
            Expanded(flex: 2, child: form),
          ]);
        }
        return Column(children: [map, const SizedBox(height: 18), form]);
      }),
    );
  }
}

class ReservationForm extends StatelessWidget {
  const ReservationForm({
    super.key,
    required this.date,
    required this.time,
    required this.selectedTable,
    required this.guests,
    required this.name,
    required this.notes,
    required this.onDate,
    required this.onTime,
  });

  final DateTime date;
  final TimeOfDay time;
  final DiningTable? selectedTable;
  final TextEditingController guests;
  final TextEditingController name;
  final TextEditingController notes;
  final ValueChanged<DateTime> onDate;
  final ValueChanged<TimeOfDay> onTime;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final canReserve = selectedTable != null && state.tableStatus(selectedTable!, date, time) == GuestTableStatus.free;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Detalhes da reserva', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: date);
                if (picked != null) onDate(picked);
              },
              icon: const Icon(Icons.calendar_month_rounded),
              label: Text(dateLabel(date)),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showTimePicker(context: context, initialTime: time);
                if (picked != null) onTime(picked);
              },
              icon: const Icon(Icons.schedule_rounded),
              label: Text(timeLabel(time)),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome da reserva', prefixIcon: Icon(Icons.badge_rounded))),
          const SizedBox(height: 12),
          TextField(controller: guests, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantidade de convidados', prefixIcon: Icon(Icons.groups_rounded))),
          const SizedBox(height: 12),
          TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Observacoes', prefixIcon: Icon(Icons.notes_rounded))),
          const SizedBox(height: 12),
          if (selectedTable != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.table_bar_rounded),
              title: Text('Mesa ' + selectedTable!.number.toString()),
              subtitle: Text('Capacidade maxima: ' + selectedTable!.capacity.toString()),
            ),
          FilledButton.icon(
            onPressed: selectedTable == null ? null : () {
              final ok = state.createReservation(
                table: selectedTable!,
                date: date,
                time: time,
                guests: int.tryParse(guests.text) ?? 1,
                name: name.text,
                notes: notes.text,
              );
              showSnack(context, ok ? 'Reserva criada e notificacao enviada.' : 'Nao foi possivel reservar. Verifique mesa, horario ou capacidade.');
            },
            icon: const Icon(Icons.check_circle_rounded),
            label: Text(canReserve ? 'Confirmar reserva' : 'Solicitar lista de espera'),
          ),
        ]),
      ),
    );
  }
}

class TableMap extends StatelessWidget {
  const TableMap({
    super.key,
    required this.date,
    required this.time,
    this.selected,
    this.onSelect,
    this.adminMode = false,
  });

  final DateTime date;
  final TimeOfDay time;
  final DiningTable? selected;
  final ValueChanged<DiningTable>? onSelect;
  final bool adminMode;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Mapa de mesas', style: Theme.of(context).textTheme.titleLarge),
            LegendDot(label: 'Livre', color: tableColor(GuestTableStatus.free, context)),
            LegendDot(label: 'Reservada', color: tableColor(GuestTableStatus.reserved, context)),
            LegendDot(label: 'Bloqueada', color: tableColor(GuestTableStatus.blocked, context)),
          ]),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: DecoratedBox(
              decoration: BoxDecoration(border: Border.all(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(8)),
              child: LayoutBuilder(builder: (context, constraints) {
                return Stack(children: [
                  Positioned.fill(child: CustomPaint(painter: DiningRoomPainter(color: Theme.of(context).colorScheme.outlineVariant))),
                  for (final table in state.tables)
                    Positioned(
                      left: 16 + table.x * max(1, constraints.maxWidth - 88),
                      top: 16 + table.y * max(1, constraints.maxHeight - 88),
                      child: TableButton(
                        table: table,
                        status: state.tableStatus(table, date, time),
                        selected: selected?.id == table.id,
                        adminMode: adminMode,
                        onTap: onSelect,
                        onMove: adminMode ? (details) {
                          state.moveTable(table, details.delta.dx / max(1, constraints.maxWidth - 88), details.delta.dy / max(1, constraints.maxHeight - 88));
                        } : null,
                      ),
                    ),
                ]);
              }),
            ),
          ),
          if (adminMode) ...[
            const SizedBox(height: 8),
            Text('Arraste as mesas para alterar o layout do salao.', style: Theme.of(context).textTheme.bodySmall),
          ],
        ]),
      ),
    );
  }
}

class TableButton extends StatelessWidget {
  const TableButton({super.key, required this.table, required this.status, required this.selected, required this.adminMode, this.onTap, this.onMove});

  final DiningTable table;
  final GuestTableStatus status;
  final bool selected;
  final bool adminMode;
  final ValueChanged<DiningTable>? onTap;
  final ValueChanged<DragUpdateDetails>? onMove;

  @override
  Widget build(BuildContext context) {
    final available = status == GuestTableStatus.free || adminMode;
    return Tooltip(
      message: 'Mesa ' + table.number.toString() + ' - ' + table.capacity.toString() + ' lugares',
      child: GestureDetector(
        onPanUpdate: onMove,
        child: InkWell(
          onTap: available ? () => onTap?.call(table) : null,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 72 : 64,
            height: selected ? 72 : 64,
            decoration: BoxDecoration(
              color: tableColor(status, context),
              borderRadius: BorderRadius.circular(8),
              boxShadow: selected ? [BoxShadow(color: Theme.of(context).colorScheme.primary.withOpacity(.28), blurRadius: 18, spreadRadius: 2)] : null,
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(table.number.toString(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
              Text(table.capacity.toString() + 'p', style: const TextStyle(color: Colors.white, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}

class DiningRoomPainter extends CustomPainter {
  DiningRoomPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withOpacity(.45)..strokeWidth = 1;
    for (var i = 1; i < 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var i = 1; i < 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant DiningRoomPainter oldDelegate) => oldDelegate.color != color;
}

class ReservationsScreen extends StatelessWidget {
  const ReservationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final reservations = state.visibleReservations;
    return PageFrame(
      title: 'Reservas',
      subtitle: 'Historico completo, status, QR Code e acoes rapidas.',
      child: Column(children: [
        SearchField(onChanged: state.updateSearch),
        const SizedBox(height: 14),
        if (reservations.isEmpty) const EmptyState(icon: Icons.event_busy_rounded, title: 'Nenhuma reserva encontrada'),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: reservations.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) => ReservationTile(reservation: reservations[index]),
        ),
      ]),
    );
  }
}

class ReservationTile extends StatelessWidget {
  const ReservationTile({super.key, required this.reservation});
  final GuestReservation reservation;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth > 720;
          final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(reservation.responsibleName, style: Theme.of(context).textTheme.titleMedium),
              StatusChip(label: reservationStatusLabel(reservation.status)),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 8, children: [
              InfoLine(icon: Icons.phone_rounded, label: reservation.phone),
              InfoLine(icon: Icons.mail_rounded, label: reservation.email),
              InfoLine(icon: Icons.calendar_month_rounded, label: dateLabel(reservation.date)),
              InfoLine(icon: Icons.schedule_rounded, label: timeLabel(reservation.time)),
              InfoLine(icon: Icons.table_bar_rounded, label: 'Mesa ' + reservation.tableNumber.toString()),
              InfoLine(icon: Icons.groups_rounded, label: reservation.guests.toString() + ' convidados'),
            ]),
            if (reservation.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(reservation.notes),
            ],
          ]);
          final actions = Wrap(spacing: 8, runSpacing: 8, children: [
            IconButton.filledTonal(tooltip: 'QR Code', onPressed: () => showQrDialog(context, reservation), icon: const Icon(Icons.qr_code_2_rounded)),
            IconButton.filledTonal(tooltip: 'Confirmar presenca', onPressed: () => state.checkIn(reservation), icon: const Icon(Icons.how_to_reg_rounded)),
            IconButton.filledTonal(tooltip: 'Cancelar', onPressed: () => state.cancelReservation(reservation), icon: const Icon(Icons.cancel_rounded)),
          ]);
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: details), const SizedBox(width: 16), actions]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [details, const SizedBox(height: 12), actions]);
        }),
      ),
    );
  }
}

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final days = List.generate(30, (index) => DateTime.now().add(Duration(days: index)));
    return PageFrame(
      title: 'Calendario inteligente',
      subtitle: 'Dias com reservas, horarios e quantidade de mesas livres.',
      child: ResponsiveGrid(minWidth: 220, ratio: 1.45, children: [
        for (final day in days)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(DateFormat('EEE, dd/MM').format(day), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                LinearProgressIndicator(value: min(1, state.reservations.where((item) => sameDay(item.date, day)).length / max(1, state.tables.length))),
                const SizedBox(height: 10),
                Text(state.reservations.where((item) => sameDay(item.date, day)).length.toString() + ' reservas'),
                Text(state.tables.where((item) => !item.blocked).length.toString() + ' mesas disponiveis'),
              ]),
            ),
          ),
      ]),
    );
  }
}

class TablesScreen extends StatelessWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return PageFrame(
      title: 'Gerenciamento de mesas',
      subtitle: 'Crie, bloqueie, libere e reorganize o mapa de mesas.',
      action: FilledButton.icon(onPressed: () => showTableEditor(context), icon: const Icon(Icons.add_rounded), label: const Text('Nova mesa')),
      child: Column(children: [
        TableMap(date: DateTime.now(), time: const TimeOfDay(hour: 20, minute: 0), adminMode: true, onSelect: (table) => showTableEditor(context, table: table)),
        const SizedBox(height: 16),
        ResponsiveGrid(children: [
          for (final table in state.tables)
            Card(
              elevation: 0,
              child: ListTile(
                leading: CircleAvatar(child: Text(table.number.toString())),
                title: Text('Mesa ' + table.number.toString()),
                subtitle: Text('Capacidade ' + table.capacity.toString() + ' pessoas'),
                trailing: Wrap(children: [
                  IconButton(tooltip: table.blocked ? 'Liberar' : 'Bloquear', onPressed: () => state.toggleTableBlock(table), icon: Icon(table.blocked ? Icons.lock_open_rounded : Icons.block_rounded)),
                  IconButton(tooltip: 'Editar', onPressed: () => showTableEditor(context, table: table), icon: const Icon(Icons.edit_rounded)),
                ]),
              ),
            ),
        ]),
      ]),
    );
  }
}

class UsersScreen extends StatelessWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return PageFrame(
      title: 'Usuarios',
      subtitle: 'Permissoes, bloqueios, exclusao e historico de reservas.',
      child: Column(children: [
        SearchField(onChanged: state.updateSearch),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.users.length,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final user = state.users[index];
            final count = state.reservations.where((item) => item.userId == user.id).length;
            return Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: CircleAvatar(child: Text(user.fullName.isEmpty ? '?' : user.fullName[0].toUpperCase())),
                  title: Text(user.fullName),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.phone + ' - ' + user.email),
                    Text('Cadastro: ' + dateLabel(user.createdAt) + ' - ' + count.toString() + ' reservas'),
                  ]),
                  trailing: Wrap(spacing: 4, children: [
                    StatusChip(label: user.blocked ? 'Bloqueado' : roleLabel(user.role)),
                    IconButton(tooltip: user.blocked ? 'Desbloquear' : 'Bloquear', onPressed: () => state.toggleUserBlock(user), icon: Icon(user.blocked ? Icons.lock_open_rounded : Icons.block_rounded)),
                    if (state.isMainAdmin && !user.isMainAdmin)
                      IconButton(tooltip: user.isAdmin ? 'Remover administrador' : 'Tornar administrador', onPressed: () => state.setUserRole(user, user.isAdmin ? UserRole.user : UserRole.admin), icon: const Icon(Icons.admin_panel_settings_rounded)),
                    if (!user.isMainAdmin)
                      IconButton(tooltip: 'Excluir', onPressed: () => state.deleteUser(user), icon: const Icon(Icons.delete_outline_rounded)),
                  ]),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final popularHours = <int, int>{};
    for (final reservation in state.reservations) {
      popularHours.update(reservation.time.hour, (value) => value + 1, ifAbsent: () => 1);
    }
    final sortedHours = popularHours.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return PageFrame(
      title: 'Relatorios',
      subtitle: 'Exportacao PDF/Excel, estatisticas e auditoria completa.',
      action: Wrap(spacing: 8, children: [
        FilledButton.icon(onPressed: state.exportPdf, icon: const Icon(Icons.picture_as_pdf_rounded), label: const Text('PDF')),
        FilledButton.tonalIcon(onPressed: state.exportExcel, icon: const Icon(Icons.table_view_rounded), label: const Text('Excel')),
      ]),
      child: Column(children: [
        ResponsiveGrid(children: [
          MetricCard(label: 'Lista de espera', value: state.waitList.length.toString(), icon: Icons.pending_actions_rounded),
          MetricCard(label: 'Mesa mais usada', value: mostUsedTable(state), icon: Icons.star_rounded),
          MetricCard(label: 'Horario pico', value: sortedHours.isEmpty ? '--' : sortedHours.first.key.toString().padLeft(2, '0') + ':00', icon: Icons.schedule_rounded),
          MetricCard(label: 'Historico', value: state.logs.length.toString(), icon: Icons.history_rounded),
        ]),
        const SizedBox(height: 18),
        ActivityPanel(logs: state.logs, title: 'Historico de alteracoes'),
      ]),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController venue;
  late final TextEditingController name;
  late final TextEditingController phone;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    venue = TextEditingController(text: state.settings.venueName);
    name = TextEditingController(text: state.currentUser?.fullName ?? '');
    phone = TextEditingController(text: state.currentUser?.phone ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return PageFrame(
      title: 'Perfil e configuracoes',
      subtitle: 'Personalizacao, horario de funcionamento, backup e permissoes.',
      child: Column(children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                title: Text(state.currentUser!.fullName),
                subtitle: Text(state.currentUser!.phone + ' - ' + state.currentUser!.email),
                trailing: FilledButton.tonalIcon(onPressed: state.logout, icon: const Icon(Icons.logout_rounded), label: const Text('Sair')),
              ),
              const Divider(),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome completo', prefixIcon: Icon(Icons.badge_rounded))),
              const SizedBox(height: 12),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Telefone', prefixIcon: Icon(Icons.phone_rounded))),
              const SizedBox(height: 12),
              FilledButton.icon(onPressed: () => state.updateProfile(name.text, phone.text), icon: const Icon(Icons.save_rounded), label: const Text('Salvar perfil')),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Administracao do estabelecimento', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              TextField(controller: venue, enabled: state.isAdmin, decoration: const InputDecoration(labelText: 'Nome do estabelecimento', prefixIcon: Icon(Icons.store_rounded))),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(onPressed: state.isAdmin ? () async {
                  final picked = await showTimePicker(context: context, initialTime: state.settings.opensAt);
                  if (picked != null) state.updateSettings(opensAt: picked);
                } : null, icon: const Icon(Icons.lock_open_rounded), label: Text('Abre ' + timeLabel(state.settings.opensAt))),
                OutlinedButton.icon(onPressed: state.isAdmin ? () async {
                  final picked = await showTimePicker(context: context, initialTime: state.settings.closesAt);
                  if (picked != null) state.updateSettings(closesAt: picked);
                } : null, icon: const Icon(Icons.lock_clock_rounded), label: Text('Fecha ' + timeLabel(state.settings.closesAt))),
              ]),
              const SizedBox(height: 12),
              SwitchListTile(
                value: state.settings.usersCanEditReservations,
                onChanged: state.isAdmin ? (value) => state.updateSettings(usersCanEditReservations: value) : null,
                title: const Text('Usuarios podem editar reservas'),
                secondary: const Icon(Icons.edit_calendar_rounded),
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                ColorChoice(color: const Color(0xFF0F766E), selected: state.settings.seedColor == const Color(0xFF0F766E), onTap: state.isAdmin ? () => state.updateSettings(color: const Color(0xFF0F766E)) : null),
                ColorChoice(color: const Color(0xFF2563EB), selected: state.settings.seedColor == const Color(0xFF2563EB), onTap: state.isAdmin ? () => state.updateSettings(color: const Color(0xFF2563EB)) : null),
                ColorChoice(color: const Color(0xFF7C3AED), selected: state.settings.seedColor == const Color(0xFF7C3AED), onTap: state.isAdmin ? () => state.updateSettings(color: const Color(0xFF7C3AED)) : null),
                ColorChoice(color: const Color(0xFFBE123C), selected: state.settings.seedColor == const Color(0xFFBE123C), onTap: state.isAdmin ? () => state.updateSettings(color: const Color(0xFFBE123C)) : null),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(onPressed: state.isAdmin ? () => state.updateSettings(venueName: venue.text) : null, icon: const Icon(Icons.save_rounded), label: const Text('Salvar configuracoes')),
                OutlinedButton.icon(onPressed: () => showSnack(context, 'Backup automatico pronto para Firebase Storage.'), icon: const Icon(Icons.backup_rounded), label: const Text('Backup')),
                OutlinedButton.icon(onPressed: () => showSnack(context, 'Upload de logo e capa pronto para Firebase Storage.'), icon: const Icon(Icons.image_rounded), label: const Text('Logo e capa')),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class ColorChoice extends StatelessWidget {
  const ColorChoice({super.key, required this.color, required this.selected, this.onTap});
  final Color color;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Cor do aplicativo',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: selected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
          ),
          child: selected ? const Icon(Icons.check_rounded, color: Colors.white) : null,
        ),
      ),
    );
  }
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({super.key, required this.children, this.minWidth = 260, this.ratio = 2.65});
  final List<Widget> children;
  final double minWidth;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final count = max(1, constraints.maxWidth ~/ minWidth);
      return GridView.count(
        crossAxisCount: count,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: ratio,
        children: children,
      );
    });
  }
}

class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          CircleAvatar(child: Icon(icon)),
          const SizedBox(width: 12),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, overflow: TextOverflow.ellipsis),
          ])),
        ]),
      ),
    );
  }
}

class ReservationsChart extends StatelessWidget {
  const ReservationsChart({super.key, required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final bars = List.generate(7, (index) {
      final day = DateTime.now().add(Duration(days: index));
      return state.reservations.where((item) => sameDay(item.date, day)).length;
    });
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Reservas por dia', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Expanded(
            child: BarChart(
              BarChartData(
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                titlesData: const FlTitlesData(show: false),
                barGroups: [
                  for (var i = 0; i < bars.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(toY: max(1, bars[i]).toDouble(), color: Theme.of(context).colorScheme.primary, width: 22, borderRadius: BorderRadius.circular(6)),
                    ]),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class ActivityPanel extends StatelessWidget {
  const ActivityPanel({super.key, required this.logs, this.title = 'Atividade recente'});
  final List<AuditLog> logs;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (logs.isEmpty) const EmptyState(icon: Icons.history_rounded, title: 'Sem historico'),
          for (final log in logs.take(9))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded),
              title: Text(log.message),
              subtitle: Text(DateFormat('dd/MM HH:mm').format(log.at) + ' - ' + log.userName),
            ),
        ]),
      ),
    );
  }
}

class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged});
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: const InputDecoration(labelText: 'Pesquisar por nome, mesa, data, horario ou telefone', prefixIcon: Icon(Icons.search_rounded)),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label), side: BorderSide.none, backgroundColor: Theme.of(context).colorScheme.secondaryContainer);
  }
}

class LegendDot extends StatelessWidget {
  const LegendDot({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label),
    ]);
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({super.key, required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 17), const SizedBox(width: 4), Text(label)]);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 42), const SizedBox(height: 8), Text(title)])),
    );
  }
}

void showTableEditor(BuildContext context, {DiningTable? table}) {
  final state = context.read<AppState>();
  final number = TextEditingController(text: table?.number.toString() ?? (state.tables.length + 1).toString());
  final capacity = TextEditingController(text: table?.capacity.toString() ?? '4');
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(table == null ? 'Nova mesa' : 'Editar mesa'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: number, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Numero da mesa')),
        const SizedBox(height: 12),
        TextField(controller: capacity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Capacidade')),
      ]),
      actions: [
        if (table != null)
          TextButton.icon(onPressed: () { state.removeTable(table); Navigator.pop(context); }, icon: const Icon(Icons.delete_outline_rounded), label: const Text('Excluir')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          state.upsertTable(DiningTable(
            id: table?.id ?? 't-' + DateTime.now().microsecondsSinceEpoch.toString(),
            number: int.tryParse(number.text) ?? 1,
            capacity: int.tryParse(capacity.text) ?? 4,
            x: table?.x ?? Random().nextDouble(),
            y: table?.y ?? Random().nextDouble(),
            blocked: table?.blocked ?? false,
          ));
          Navigator.pop(context);
        }, child: const Text('Salvar')),
      ],
    ),
  );
}

void showQrDialog(BuildContext context, GuestReservation reservation) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('QR Code da reserva'),
      content: SizedBox(
        width: 260,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          QrImageView(data: reservation.id + '|' + reservation.tableNumber.toString() + '|' + dateLabel(reservation.date) + '|' + timeLabel(reservation.time), version: QrVersions.auto, size: 220),
          const SizedBox(height: 10),
          Text(reservation.responsibleName),
        ]),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
    ),
  );
}

void showSearchSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: Consumer<AppState>(builder: (context, state, child) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Pesquisa rapida', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        SearchField(onChanged: state.updateSearch),
        const SizedBox(height: 12),
        Text(state.visibleReservations.length.toString() + ' resultado(s) em reservas'),
      ])),
    ),
  );
}

void showNotifications(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => Consumer<AppState>(builder: (context, state, child) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Notificacoes', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (state.notifications.isEmpty) const EmptyState(icon: Icons.notifications_none_rounded, title: 'Nenhuma notificacao'),
        for (final item in state.notifications.take(6))
          ListTile(leading: const Icon(Icons.notifications_rounded), title: Text(item.title), subtitle: Text(item.body)),
      ]),
    )),
  );
}

Color tableColor(GuestTableStatus status, BuildContext context) {
  switch (status) {
    case GuestTableStatus.free:
      return const Color(0xFF0F766E);
    case GuestTableStatus.reserved:
      return const Color(0xFFB45309);
    case GuestTableStatus.blocked:
      return Theme.of(context).colorScheme.error;
  }
}

String roleLabel(UserRole role) {
  switch (role) {
    case UserRole.mainAdmin:
      return 'Administrador Principal';
    case UserRole.admin:
      return 'Administrador';
    case UserRole.user:
      return 'Usuario';
  }
}

String reservationStatusLabel(ReservationStatus status) {
  switch (status) {
    case ReservationStatus.pending:
      return 'Pendente';
    case ReservationStatus.confirmed:
      return 'Confirmada';
    case ReservationStatus.changed:
      return 'Alterada';
    case ReservationStatus.cancelled:
      return 'Cancelada';
    case ReservationStatus.checkedIn:
      return 'Presenca confirmada';
  }
}

String mostUsedTable(AppState state) {
  if (state.reservations.isEmpty) return '--';
  final counts = <int, int>{};
  for (final reservation in state.reservations) {
    counts.update(reservation.tableNumber, (value) => value + 1, ifAbsent: () => 1);
  }
  final sorted = counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return 'Mesa ' + sorted.first.key.toString();
}

String dateLabel(DateTime date) => DateFormat('dd/MM/yyyy').format(date);

String timeLabel(TimeOfDay time) => time.hour.toString().padLeft(2, '0') + ':' + time.minute.toString().padLeft(2, '0');

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

bool sameTime(TimeOfDay a, TimeOfDay b) => a.hour == b.hour && a.minute == b.minute;

void showSnack(BuildContext context, String message) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
