import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/laundry_provider.dart';
import '../models/models.dart';
// 🔥 Pastikan import halaman PrinterTab lu bener ya path-nya:
import '../screens/settings_subscreens/printer_tab.dart'; // Sesuaikan kalau file printer_tab.dart lu ada di folder lain

class PrinterButtonWidget extends StatelessWidget {
  const PrinterButtonWidget({super.key});

  @override
  Widget build(BuildContext context) {
    // Tarik data user yang lagi login
    final currentUser = context.watch<LaundryProvider>().currentUser;

    // 🔥 LOGIC PERMISSION (HAK AKSES)
    // Misalnya: Cuma Owner, Admin, dan Kasir yang boleh lihat tombol Printer.
    // Staff cuci/lipat biasa gak bakal bisa lihat tombol ini.
    if (currentUser == null || currentUser.role == UserRole.staff) {
      return const SizedBox.shrink(); // Sembunyikan tombolnya!
    }

    return InkWell(
      onTap: () {
        // Aksi pas tombol dipencet -> Pindah ke halaman Printer
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const PrinterTab()),
        );
      },
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 90, // Ukuran disesuaikan kayak di screenshot lu
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            )
          ],
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              backgroundColor: Color(0xFFE8F0FE), // Warna biru muda khas icon lu
              radius: 25,
              child: Icon(Icons.print, color: Colors.blueGrey, size: 28),
            ),
            SizedBox(height: 8),
            Text(
              "Printer",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}