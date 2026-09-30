import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plea_guard/main.dart';

void main() {
  testWidgets('menampilkan halaman masuk PLEA GUARD', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const PleaGuardApp());

    expect(find.text('Email atau NRP'), findsOneWidget);
    expect(find.text('Masuk'), findsOneWidget);

    await tester.enterText(
        find.byType(TextField).first, 'andi.saputra@kejaksaan.go.id');
    await tester.enterText(find.byType(TextField).at(1), 'demo123');
    await tester.tap(find.text('Masuk'));
    await tester.pumpAndSettle();
    expect(find.text('Beranda'), findsNWidgets(2));
    expect(find.text('Andi Saputra'), findsOneWidget);

    await tester.tap(find.text('Notifikasi'));
    await tester.pumpAndSettle();
    expect(find.text('Tandai semua dibaca'), findsOneWidget);

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Akun & Keamanan'), findsOneWidget);
  });
}
