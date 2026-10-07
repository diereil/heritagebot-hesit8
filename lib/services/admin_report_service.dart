import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/community_submission.dart';
import '../models/heritage_place.dart';
import '../models/user_profile.dart';
import 'admin_analytics_service.dart';

class AdminReportService {
  Future<void> generateSystemReport(AdminAnalyticsSnapshot snapshot) async {
    final bytes = await buildSystemReport(snapshot);
    final now = DateTime.now();

    final fileName = 'HeritageBot_System_Report_${_fileDate(now)}.pdf';

    await Printing.layoutPdf(name: fileName, onLayout: (_) async => bytes);
  }

  Future<Uint8List> buildSystemReport(AdminAnalyticsSnapshot snapshot) async {
    final document = pw.Document(
      title: 'HeritageBot System Report',
      author: 'HeritageBot Administrator',
      subject: 'System Summary and Analytics',
      creator: 'HeritageBot',
    );

    final generatedAt = DateTime.now();
    final adminEmail =
        FirebaseAuth.instance.currentUser?.email ?? 'Administrator';

    final sites = [...snapshot.sites]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final submissions = [...snapshot.submissions]
      ..sort((a, b) => b.updatedAtMillis.compareTo(a.updatedAtMillis));

    final users = [...snapshot.users]
      ..sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
        ),
        header: (context) {
          if (context.pageNumber == 1) {
            return pw.SizedBox();
          }

          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.only(bottom: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'HeritageBot System Report',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  _displayDate(generatedAt),
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'HERITAGEBOT: An AI-Based Historical Narrative Generator',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
                pw.Text(
                  'Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          );
        },
        build: (context) => [
          _titleBlock(generatedAt: generatedAt, adminEmail: adminEmail),
          pw.SizedBox(height: 20),
          _sectionTitle(
            '1. System Summary',
            'Current HeritageBot records retrieved from Cloud Firestore.',
          ),
          pw.SizedBox(height: 10),
          _summaryGrid(snapshot),
          pw.SizedBox(height: 20),
          _sectionTitle(
            '2. User Account Summary',
            'Registered HeritageBot accounts by role and current account status.',
          ),
          pw.SizedBox(height: 10),
          _table(
            headers: const ['Category', 'Count'],
            rows: [
              ['Total Users', '${snapshot.totalUsers}'],
              ['Tourists', '${snapshot.tourists}'],
              ['Community Contributors', '${snapshot.contributors}'],
              ['Administrators', '${snapshot.admins}'],
              ['Active Accounts', '${snapshot.activeUsers}'],
              ['Suspended Accounts', '${snapshot.suspendedUsers}'],
            ],
            widths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
          ),
          pw.SizedBox(height: 20),
          _sectionTitle(
            '3. Heritage Site Summary',
            'Heritage sites currently registered in the HeritageBot administrator database.',
          ),
          pw.SizedBox(height: 10),
          _table(
            headers: const ['Site Name', 'Type', 'Status', 'Location'],
            rows: sites.map((site) {
              return [
                site.name,
                site.isTesting ? 'Testing' : 'Official',
                site.isActive ? 'Active' : 'Inactive',
                site.location,
              ];
            }).toList(),
            widths: const {
              0: pw.FlexColumnWidth(2.3),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(2.6),
            },
          ),
          pw.SizedBox(height: 20),
          _sectionTitle(
            '4. Community Submission Summary',
            'Current moderation status of community-contributed heritage stories.',
          ),
          pw.SizedBox(height: 10),
          _table(
            headers: const ['Status', 'Count', 'Share'],
            rows: [
              [
                'Pending',
                '${snapshot.pendingSubmissions}',
                _percent(
                  snapshot.pendingSubmissions,
                  snapshot.totalSubmissions,
                ),
              ],
              [
                'Approved',
                '${snapshot.approvedSubmissions}',
                _percent(
                  snapshot.approvedSubmissions,
                  snapshot.totalSubmissions,
                ),
              ],
              [
                'Rejected',
                '${snapshot.rejectedSubmissions}',
                _percent(
                  snapshot.rejectedSubmissions,
                  snapshot.totalSubmissions,
                ),
              ],
              ['Total', '${snapshot.totalSubmissions}', '100%'],
            ],
            widths: const {
              0: pw.FlexColumnWidth(2),
              1: pw.FlexColumnWidth(1),
              2: pw.FlexColumnWidth(1),
            },
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Approval Rate: ${(snapshot.approvalRate * 100).round()}%',
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
          if (submissions.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _sectionTitle(
              '5. Recent Community Submissions',
              'The ten most recently updated community contributions.',
            ),
            pw.SizedBox(height: 10),
            _table(
              headers: const [
                'Title',
                'Heritage Site',
                'Contributor',
                'Status',
                'Updated',
              ],
              rows: submissions.take(10).map((submission) {
                return [
                  submission.title,
                  submission.heritagePlaceName,
                  _safeName(submission),
                  CommunitySubmissionStatus.label(submission.status),
                  _millisDate(submission.updatedAtMillis),
                ];
              }).toList(),
              widths: const {
                0: pw.FlexColumnWidth(2.2),
                1: pw.FlexColumnWidth(1.8),
                2: pw.FlexColumnWidth(1.6),
                3: pw.FlexColumnWidth(1),
                4: pw.FlexColumnWidth(1.2),
              },
              fontSize: 8.3,
            ),
          ],
          if (users.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _sectionTitle(
              submissions.isNotEmpty
                  ? '6. Registered User Overview'
                  : '5. Registered User Overview',
              'Account overview for administrative monitoring. Passwords and authentication credentials are never included.',
            ),
            pw.SizedBox(height: 10),
            _table(
              headers: const ['Name', 'Role', 'Status', 'Created'],
              rows: users.map((user) {
                return [
                  user.fullName.trim().isEmpty
                      ? 'HeritageBot User'
                      : user.fullName,
                  UserRoles.label(user.role),
                  _capitalize(user.accountStatus),
                  _millisDate(user.createdAtMillis),
                ];
              }).toList(),
              widths: const {
                0: pw.FlexColumnWidth(2.4),
                1: pw.FlexColumnWidth(1.8),
                2: pw.FlexColumnWidth(1.2),
                3: pw.FlexColumnWidth(1.3),
              },
              fontSize: 8.5,
            ),
          ],
          pw.SizedBox(height: 22),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
              borderRadius: pw.BorderRadius.circular(5),
            ),
            child: pw.Text(
              'This report was generated from the current HeritageBot Cloud Firestore data for administrative and academic project use.',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _titleBlock({
    required DateTime generatedAt,
    required String adminEmail,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: PdfColors.brown800,
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'HERITAGEBOT',
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'An AI-Based Historical Narrative Generator',
            style: const pw.TextStyle(fontSize: 12, color: PdfColors.white),
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            'SYSTEM SUMMARY AND ANALYTICS REPORT',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.amber200,
            ),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Generated: ${_displayDateTime(generatedAt)}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
          ),
          pw.Text(
            'Generated by: $adminEmail',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.white),
          ),
        ],
      ),
    );
  }

  pw.Widget _summaryGrid(AdminAnalyticsSnapshot snapshot) {
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              child: _summaryCard(
                label: 'Total Users',
                value: '${snapshot.totalUsers}',
                detail:
                    '${snapshot.activeUsers} active, ${snapshot.suspendedUsers} suspended',
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _summaryCard(
                label: 'Heritage Sites',
                value: '${snapshot.totalSites}',
                detail:
                    '${snapshot.officialSites} official, ${snapshot.testingSites} testing',
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          children: [
            pw.Expanded(
              child: _summaryCard(
                label: 'Submissions',
                value: '${snapshot.totalSubmissions}',
                detail:
                    '${snapshot.pendingSubmissions} pending, ${snapshot.approvedSubmissions} approved',
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: _summaryCard(
                label: 'Approval Rate',
                value: '${(snapshot.approvalRate * 100).round()}%',
                detail: 'Approved community contributions',
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _summaryCard({
    required String label,
    required String value,
    required String detail,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300, width: 0.7),
        borderRadius: pw.BorderRadius.circular(5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.brown800,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            label,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            detail,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  pw.Widget _sectionTitle(String title, String subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.brown800,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          subtitle,
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
        ),
      ],
    );
  }

  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, pw.TableColumnWidth> widths,
    double fontSize = 9,
  }) {
    final tableRows = <pw.TableRow>[
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.brown800),
        children: headers
            .map(
              (header) => _tableCell(
                header,
                bold: true,
                color: PdfColors.white,
                fontSize: fontSize,
              ),
            )
            .toList(),
      ),
      ...rows.asMap().entries.map((entry) {
        return pw.TableRow(
          decoration: pw.BoxDecoration(
            color: entry.key.isEven ? PdfColors.white : PdfColors.grey100,
          ),
          children: entry.value
              .map((value) => _tableCell(value, fontSize: fontSize))
              .toList(),
        );
      }),
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: widths,
      children: tableRows,
    );
  }

  pw.Widget _tableCell(
    String value, {
    bool bold = false,
    PdfColor color = PdfColors.black,
    double fontSize = 9,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color,
        ),
      ),
    );
  }

  static String _percent(int value, int total) {
    if (total <= 0) {
      return '0%';
    }

    return '${((value / total) * 100).round()}%';
  }

  static String _safeName(CommunitySubmission submission) {
    final name = submission.contributorName.trim();

    if (name.isNotEmpty) {
      return name;
    }

    return 'Community Contributor';
  }

  static String _millisDate(int millis) {
    if (millis <= 0) {
      return 'N/A';
    }

    return _displayDate(DateTime.fromMillisecondsSinceEpoch(millis));
  }

  static String _displayDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }

  static String _displayDateTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '${_displayDate(date)} $hour:$minute';
  }

  static String _fileDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');

    return '${date.year}$month${day}_$hour$minute';
  }

  static String _capitalize(String value) {
    final clean = value.trim();

    if (clean.isEmpty) {
      return 'Not Set';
    }

    return '${clean[0].toUpperCase()}${clean.substring(1).toLowerCase()}';
  }
}
