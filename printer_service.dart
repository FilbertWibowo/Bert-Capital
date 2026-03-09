import 'dart:io';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';

// ============================================================
// UNIVERSAL PRINTER SERVICE
// ============================================================
class PrinterService {
  bool _isConnected = false;
  String? _connectedMacAddress;

  bool get isConnected => _isConnected;
  String? get connectedMacAddress => _connectedMacAddress;

  /// Multiplier untuk add-on: mesin pakai beratCucianMesin, kiloan pakai weightOrQty
  double _getMul(LaundryTransaction t, LaundryAddOn a) {
    // ✅ FIX: Bedakan berdasarkan type
    if (a.type == 'mesin') return t.beratCucianMesin > 0 ? t.beratCucianMesin : t.weightOrQty;
    if (a.type == 'bahan') return t.weightOrQty; // ✅ TAMBAH: Bahan dikali jumlah mesin
    if (a.type == 'kiloan') return t.weightOrQty;
    return 1.0;
  }

  Future<void> initConnection() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMac = prefs.getString('saved_printer_mac');
    if (savedMac != null) await connectThermal(savedMac);
  }

  Future<List<BluetoothInfo>> getBondedDevices() async {
    return await PrintBluetoothThermal.pairedBluetooths;
  }

  Future<bool> connectThermal(String mac) async {
    try {
      final bool ok =
          await PrintBluetoothThermal.connect(macPrinterAddress: mac);
      _isConnected = ok;
      if (ok) {
        _connectedMacAddress = mac;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('saved_printer_mac', mac);
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disconnect() async {
    final ok = await PrintBluetoothThermal.disconnect;
    _isConnected = false;
    _connectedMacAddress = null;
    return ok;
  }

  /// Entry point utama.
  /// Jika printer BT terhubung → cetak thermal, jika tidak → buka dialog PDF.
  Future<void> printReceipt(LaundryTransaction t, StoreSettings s) async {
    if (_isConnected) {
      await _printThermal(t, s);
    } else {
      await _printPdf(t, s);
    }
  }

  // ──────────────────────────────────────────────────────────
  // KALKULASI NILAI DASAR
  // ──────────────────────────────────────────────────────────
  _Calc _calc(LaundryTransaction t) {
    // Hanya hitung add-on yang nilai-nya > 0
    double totalAddons = 0;
    for (final a in t.selectedAddOns) {
      final mul = _getMul(t, a);
      final price = a.price * mul;
      if (price > 0) totalAddons += price;
    }

    final baseWashTotal = t.grandTotal +
        t.discountAmount -
        t.deliveryCost -
        totalAddons -
        t.taxAmount;

    // Jika qty = 0 (data belum diisi), anggap 1 agar tidak error
    final qty = t.weightOrQty > 0 ? t.weightOrQty : 1.0;
    final pricePerUnit = baseWashTotal / qty;

    return _Calc(totalAddons, baseWashTotal, pricePerUnit);
  }

  // ──────────────────────────────────────────────────────────
  // THERMAL PRINT
  // ──────────────────────────────────────────────────────────
  Future<void> _printThermal(LaundryTransaction t, StoreSettings s) async {
    final profile = await CapabilityProfile.load();
    final paper = s.paperWidthMm == 58 ? PaperSize.mm58 : PaperSize.mm80;
    final gen = Generator(paper, profile);
    final fmt = NumberFormat('#,##0', 'id');  // format: 20.500 tanpa "Rp"
    final c = _calc(t);
    final List<int> bytes = [];

    // ── HEADER ──────────────────────────────────────────────
    bytes.addAll(gen.text(
      s.storeName,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    ));
    bytes.addAll(gen.feed(1));
    if (s.storeAddress.isNotEmpty) {
      bytes.addAll(gen.text(s.storeAddress,
          styles: const PosStyles(align: PosAlign.center)));
    }
    if (s.storePhone.isNotEmpty) {
      bytes.addAll(gen.text('Telp: ${s.storePhone}',
          styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(gen.hr(ch: '='));

    // ── INFO TRANSAKSI ───────────────────────────────────────
    bytes.addAll(_tRow(gen, 'No. Order', t.id, boldRight: true));
    bytes.addAll(_tRow(
      gen,
      'Tanggal',
      DateFormat('dd/MM/yyyy HH:mm').format(t.dateIn),
    ));
    bytes.addAll(_tRow(gen, 'Pelanggan', t.customerName, boldRight: true));
    bytes.addAll(_tRow(gen, 'Kasir', t.cashierName ?? t.workerName));
    bytes.addAll(gen.hr(ch: '='));

    // ── DETAIL PESANAN ───────────────────────────────────────
    bytes.addAll(
      gen.text('Detail Pesanan:', styles: const PosStyles(bold: true)),
    );
    bytes.addAll(gen.feed(1));

    if (t.type == OrderType.kiloan) {
      // Nama & harga di baris yang sama (kiri–kanan)
      bytes.addAll(_tRow(gen, 'Cuci Kiloan', fmt.format(c.baseWashTotal)));
      // Detail harga per kg (hanya tampil jika qty > 0)
      if (t.weightOrQty > 0) {
        bytes.addAll(gen.text(
          '   @ ${fmt.format(c.pricePerUnit)} x ${t.weightOrQty} Kg',
        ));
      }
    } else if (t.type == OrderType.perMesin) {
      bytes.addAll(_tRow(gen, 'Cuci Per Mesin${t.isExpress ? ' (Express)' : ''}', fmt.format(c.baseWashTotal)));
      // Detail hanya tampil jika qty > 0
      if (t.weightOrQty > 0) {
        bytes.addAll(gen.text(
          '   @ ${fmt.format(c.pricePerUnit)} x ${t.weightOrQty.toInt()} Mesin',
        ));
      }
    } else {
      for (final item in t.items) {
        bytes.addAll(_tRow(
          gen,
          '${item.qty}x ${item.itemName}',
          fmt.format(item.priceAtTransaction * item.qty),
        ));
        final det = [
          if (item.brand != null && item.brand!.isNotEmpty) 'Merk: ${item.brand}',
          if (item.size  != null && item.size!.isNotEmpty)  'Ukuran: ${item.size}',
          if (item.color != null && item.color!.isNotEmpty) 'Warna: ${item.color}',
        ];
        if (det.isNotEmpty) bytes.addAll(gen.text('   ${det.join(' | ')}'));
      }
    }

    // ── LAYANAN TAMBAHAN (skip jika nilai 0) ─────────────────
    final validAddons = t.selectedAddOns.where((a) {
      return a.price * _getMul(t, a) > 0;
    }).toList();

    if (validAddons.isNotEmpty) {
      bytes.addAll(gen.feed(1));
      bytes.addAll(
        gen.text('Layanan Tambahan:', styles: const PosStyles(bold: true)),
      );
      for (final a in validAddons) {
        final mul = _getMul(t, a);
        final totalPrice = a.price * mul;
        bytes.addAll(_tRow(gen, a.title, fmt.format(totalPrice)));
        if (mul > 1) {
          final unit = (a.type == 'kiloan' || a.type == 'mesin') ? ' kg' : '';
          bytes.addAll(
            gen.text('   ${fmt.format(a.price)} x ${mul.toInt()}$unit'),
          );
        }
      }
    }

    // ── RINGKASAN ────────────────────────────────────────────
    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.hr());
    bytes.addAll(
        _tRow(gen, 'Subtotal (Laundry)', fmt.format(c.baseWashTotal)));
    if (c.totalAddons > 0) {
      bytes.addAll(_tRow(gen, 'Total Add-ons', fmt.format(c.totalAddons)));
    }
    if (t.deliveryCost > 0) {
      bytes.addAll(_tRow(gen, 'Ongkos Kirim', fmt.format(t.deliveryCost)));
    }
    if (t.discountAmount > 0) {
      bytes.addAll(
          _tRow(gen, 'Diskon', '-${fmt.format(t.discountAmount)}'));
    }
    if (t.taxAmount > 0) {
      bytes.addAll(_tRow(gen, 'Pajak', fmt.format(t.taxAmount)));
    }
    bytes.addAll(gen.hr(ch: '='));

    // ── TOTAL TAGIHAN ────────────────────────────────────────
    bytes.addAll(gen.row([
      PosColumn(
        text: 'TOTAL TAGIHAN',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: fmt.format(t.grandTotal),
        width: 6,
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    ]));
    bytes.addAll(gen.feed(1));

    // ── BAYAR & KEMBALIAN ────────────────────────────────────
    bytes.addAll(
        _tRow(gen, 'Bayar (${t.paymentMethod})', fmt.format(t.amountPaid)));
    if (t.paymentStatus == PaymentStatus.lunas) {
      bytes.addAll(_tRow(gen, 'Kembalian', fmt.format(t.change)));
    } else {
      bytes.addAll(_tRow(
        gen,
        'Sisa Belum Bayar',
        fmt.format(t.remainingBalance),
        boldRight: true,
      ));
    }

    // ── CATATAN ──────────────────────────────────────────────
    if (t.note.isNotEmpty) {
      bytes.addAll(gen.hr());
      bytes.addAll(gen.text('Catatan:', styles: const PosStyles(bold: true)));
      bytes.addAll(gen.text(t.note));
    }

    // ── FOOTER ───────────────────────────────────────────────
    bytes.addAll(gen.hr());
    bytes.addAll(gen.feed(1));
    bytes.addAll(gen.text(
      'Scan untuk detail',
      styles: const PosStyles(align: PosAlign.center),
    ));
    bytes.addAll(gen.qrcode(t.id));
    bytes.addAll(gen.feed(1));
    if (s.receiptFooter.isNotEmpty) {
      bytes.addAll(gen.text(
        s.receiptFooter,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ));
    }
    bytes.addAll(gen.feed(3));
    bytes.addAll(gen.cut());

    await PrintBluetoothThermal.writeBytes(bytes);
  }

  /// Row thermal konsisten: label 7 kolom kiri, nilai 5 kolom kanan.
  List<int> _tRow(
    Generator gen,
    String label,
    String value, {
    bool boldRight = false,
  }) {
    return gen.row([
      PosColumn(text: label, width: 7),
      PosColumn(
        text: value,
        width: 5,
        styles: PosStyles(align: PosAlign.right, bold: boldRight),
      ),
    ]);
  }

  // ──────────────────────────────────────────────────────────
  // PDF PRINT — Layout sesuai Gambar 1
  // ──────────────────────────────────────────────────────────
  Future<void> _printPdf(LaundryTransaction t, StoreSettings s) async {
    final doc = pw.Document();
    final fmt =
        NumberFormat.currency(locale: 'id', symbol: 'Rp ', decimalDigits: 0);
    final double widthPt = s.paperWidthMm * 2.83465;
    final c = _calc(t);

    pw.MemoryImage? logoImage;
    if (s.logoPath.isNotEmpty && File(s.logoPath).existsSync()) {
      logoImage = pw.MemoryImage(File(s.logoPath).readAsBytesSync());
    }

    // ── Widget item pesanan ───────────────────────────────────
    final List<pw.Widget> itemWidgets = [];
    if (t.type == OrderType.kiloan) {
      itemWidgets.add(_pdfRow(
        'Cuci Kiloan (${t.isExpress ? 'Express' : 'Reguler'})',
        fmt.format(c.baseWashTotal),
        boldValue: true,
      ));
      if (t.weightOrQty > 0) {
        itemWidgets.add(_pdfSub(
            '${fmt.format(c.pricePerUnit)} x ${t.weightOrQty} Kg'));
      }
    } else if (t.type == OrderType.perMesin) {
      itemWidgets.add(_pdfRow(
        'Cuci Per Mesin (${t.isExpress ? 'Express' : 'Reguler'})',
        fmt.format(c.baseWashTotal),
        boldValue: true,
      ));
      if (t.weightOrQty > 0) {
        itemWidgets.add(_pdfSub(
            '${fmt.format(c.pricePerUnit)} x ${t.weightOrQty.toInt()} Mesin'));
      }
      if (t.machineNumber != null) {
        itemWidgets.add(_pdfSub('Mesin: ${t.machineNumber}'));
      }
    } else {
      for (final i in t.items) {
        itemWidgets.add(_pdfRow(
          '${i.qty}x ${i.itemName}',
          fmt.format(i.priceAtTransaction * i.qty),
          boldValue: true,
        ));
        final det = [
          if (i.brand != null && i.brand!.isNotEmpty) i.brand!,
          if (i.size  != null && i.size!.isNotEmpty)  'Sz: ${i.size}',
          if (i.color != null && i.color!.isNotEmpty) i.color!,
        ];
        if (det.isNotEmpty) itemWidgets.add(_pdfSub('   ${det.join(' · ')}'));
      }
    }

    // ── Widget add-ons (skip jika nilai 0) ───────────────────
    final validAddons = t.selectedAddOns.where((a) {
      return a.price * _getMul(t, a) > 0;
    }).toList();

    final List<pw.Widget> addonWidgets = [];
    if (validAddons.isNotEmpty) {
      addonWidgets.add(pw.SizedBox(height: 6));
      addonWidgets.add(pw.Text(
        'Layanan Tambahan:',
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.grey600,
        ),
      ));
      addonWidgets.add(pw.SizedBox(height: 3));
      for (final a in validAddons) {
        final mul = _getMul(t, a);
        final aTotal = a.price * mul;
        addonWidgets.add(_pdfRow(a.title, fmt.format(aTotal)));
        if (mul > 1) {
          final unit = (a.type == 'kiloan' || a.type == 'mesin') ? ' kg' : '';
          addonWidgets.add(
              _pdfSub('${fmt.format(a.price)} x ${mul.toInt()}$unit'));
        }
      }
    }

    // ── Widget ringkasan harga ────────────────────────────────
    final List<pw.Widget> summaryWidgets = [
      _pdfRow('Subtotal (Laundry)', fmt.format(c.baseWashTotal),
          boldValue: true),
    ];
    if (c.totalAddons > 0) {
      summaryWidgets
          .add(_pdfRowSmall('Total Add-ons', fmt.format(c.totalAddons)));
    }
    if (t.deliveryCost > 0) {
      summaryWidgets
          .add(_pdfRowSmall('Ongkos Kirim', fmt.format(t.deliveryCost)));
    }
    if (t.discountAmount > 0) {
      summaryWidgets.add(_pdfRow(
        'Diskon',
        '-${fmt.format(t.discountAmount)}',
        valueColor: PdfColors.red,
      ));
    }
    if (t.taxAmount > 0) {
      summaryWidgets.add(
          _pdfRow('Pajak', fmt.format(t.taxAmount), valueColor: PdfColors.orange));
    }

    // ── Widget bayar & kembalian ──────────────────────────────
    final List<pw.Widget> payWidgets = [
      _pdfRow('Bayar (${t.paymentMethod})', fmt.format(t.amountPaid),
          boldValue: true),
      if (t.paymentStatus == PaymentStatus.lunas)
        _pdfRow('Kembalian', fmt.format(t.change),
            valueColor: PdfColors.green700, boldValue: true)
      else
        _pdfRow('Sisa Belum Bayar', fmt.format(t.remainingBalance),
            valueColor: PdfColors.red, boldValue: true),
    ];

    // ── Build halaman PDF ─────────────────────────────────────
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(widthPt, double.infinity, marginAll: 14),
      build: (pw.Context ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          // LOGO & NAMA TOKO
          if (logoImage != null)
            pw.Image(logoImage, width: 56, height: 56)
          else
            pw.Icon(const pw.IconData(0xe8f8),
                color: PdfColors.blue800, size: 40),
          pw.SizedBox(height: 6),
          pw.Text(
            t.outletName.isNotEmpty ? t.outletName : s.storeName,
            style:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14),
          ),
          if (s.storeAddress.isNotEmpty)
            pw.Text(
              s.storeAddress,
              textAlign: pw.TextAlign.center,
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey600),
            ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1.5),
          pw.SizedBox(height: 6),

          // INFO TRANSAKSI
          pw.SizedBox(
            width: double.infinity,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _pdfRow('No. Order', t.id, boldValue: true),
                _pdfRow(
                  'Tanggal',
                  DateFormat('dd MMM yyyy HH:mm').format(t.dateIn),
                ),
                _pdfRow('Pelanggan', t.customerName, boldValue: true),
                _pdfRow('Kasir', t.cashierName ?? t.workerName,
                    boldValue: true),
              ],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Divider(),
          pw.SizedBox(height: 6),

          // DETAIL PESANAN
          pw.SizedBox(
            width: double.infinity,
            child: pw.Text(
              'Detail Pesanan:',
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 5),
          pw.SizedBox(
            width: double.infinity,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [...itemWidgets, ...addonWidgets],
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Divider(),

          // RINGKASAN HARGA
          pw.SizedBox(
            width: double.infinity,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: summaryWidgets,
            ),
          ),
          pw.Divider(thickness: 2),

          // TOTAL TAGIHAN
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'TOTAL TAGIHAN',
                style: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold, fontSize: 13),
              ),
              pw.Text(
                fmt.format(t.grandTotal),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 13,
                  color: PdfColors.blue800,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 8),

          // BAYAR & KEMBALIAN
          pw.SizedBox(
            width: double.infinity,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: payWidgets,
            ),
          ),

          pw.SizedBox(height: 14),
          pw.Divider(),
          pw.SizedBox(height: 8),

          // QR CODE
          pw.Text(
            'Scan untuk detail',
            style: const pw.TextStyle(
                fontSize: 8, color: PdfColors.grey600),
          ),
          pw.SizedBox(height: 4),
          pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: t.id,
            width: 70,
            height: 70,
          ),
          pw.SizedBox(height: 10),

          // FOOTER
          if (s.receiptFooter.isNotEmpty)
            pw.Text(
              s.receiptFooter,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontStyle: pw.FontStyle.italic,
                fontSize: 10,
              ),
            ),
        ],
      ),
    ));

    await Printing.layoutPdf(onLayout: (_) async => doc.save());
  }

  // ── PDF Row Helpers ───────────────────────────────────────

  /// Baris label kiri – nilai kanan
  pw.Widget _pdfRow(
    String label,
    String value, {
    bool boldValue = false,
    PdfColor? valueColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight:
                  boldValue ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Baris kecil abu-abu (sub-item seperti Total Add-ons, Ongkos Kirim)
  pw.Widget _pdfRowSmall(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey700)),
          pw.Text(value,
              style: const pw.TextStyle(
                  fontSize: 8, color: PdfColors.grey700)),
        ],
      ),
    );
  }

  /// Teks kecil abu-abu untuk sub-detail (harga per unit, dll)
  pw.Widget _pdfSub(String text) {
    return pw.Text(
      text,
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
    );
  }
}

// ── Data class kalkulasi ──────────────────────────────────
class _Calc {
  final double totalAddons;
  final double baseWashTotal;
  final double pricePerUnit;
  const _Calc(this.totalAddons, this.baseWashTotal, this.pricePerUnit);
}