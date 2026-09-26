import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../shared/providers/inventory_providers.dart';

class PhysicalReceiptVerificationCard extends ConsumerStatefulWidget {
  final int receiptId;
  final String reference;
  final String productName;
  final double quantity;
  final String? supplier;
  final bool isImmutable;
  final VoidCallback? onValidatedReceipt;

  const PhysicalReceiptVerificationCard({
    super.key,
    required this.receiptId,
    required this.reference,
    required this.productName,
    required this.quantity,
    this.supplier,
    this.isImmutable = false,
    this.onValidatedReceipt,
  });

  @override
  ConsumerState<PhysicalReceiptVerificationCard> createState() =>
      _PhysicalReceiptVerificationCardState();
}

class _PhysicalReceiptVerificationCardState
    extends ConsumerState<PhysicalReceiptVerificationCard> {
  bool _isLoading = false;
  String _processingStep = '';
  ReceiptDocumentMeta? _document;
  ReceiptVerificationResult? _verification;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadExistingVerification();
  }

  Future<void> _loadExistingVerification() async {
    final repo = ref.read(receiptsRepositoryProvider);
    try {
      final doc = await repo.getReceiptDocument(widget.receiptId);
      final ver = await repo.getReceiptVerification(widget.receiptId);
      if (mounted) {
        setState(() {
          _document = doc;
          _verification = ver;
        });
      }
    } catch (_) {
      // Non-blocking: Document might not be uploaded yet
    }
  }

  Future<void> _pickAndUploadReceipt() async {
    try {
      final pickedFiles = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );

      if (pickedFiles.isEmpty) return;

      final file = pickedFiles.first;
      final fileBytes = await file.xFile.readAsBytes();

      if (!mounted) return;

      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _processingStep = 'Uploading physical receipt document...';
      });


      final repo = ref.read(receiptsRepositoryProvider);

      // 1. Upload Document
      final docMeta = await repo.uploadReceiptDocument(
        widget.receiptId,
        fileName: file.name,
        bytes: fileBytes,
        mimeType: file.extension?.toLowerCase() == 'pdf'
            ? 'application/pdf'
            : 'image/${file.extension?.toLowerCase() ?? 'jpeg'}',
      );

      setState(() {
        _document = docMeta;
        _processingStep = 'Extracting text and line items via OCR...';
      });

      // 2. Perform OCR and Verification
      setState(() {
        _processingStep = 'Comparing OCR data against StockSense receipt...';
      });

      final verResult = await repo.verifyReceiptDocument(widget.receiptId);

      if (mounted) {
        setState(() {
          _verification = verResult;
          _processingStep = 'Verification complete.';
          _isLoading = false;
        });

        final isMatch = verResult.isMatch;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isMatch
                  ? 'Physical receipt verified: All fields MATCH!'
                  : 'Review Required: Discrepancies detected between physical and digital records.',
            ),
            backgroundColor:
                isMatch ? AppColors.statusDone : AppColors.statusDraft,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document verification error: $e'),
            backgroundColor: AppColors.statusCancelled,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.1),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: const Icon(Icons.document_scanner_rounded,
                    color: AppColors.brand, size: 22),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Physical Receipt Verification',
                      style: AppTextStyles.headlineSmall,
                    ),
                    Text(
                      'Assistive OCR verification against physical supplier receipt',
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              if (_verification != null)
                _buildVerificationBadge(_verification!.status),
            ],
          ),

          const SizedBox(height: AppSpacing.md),

          // Loading / Processing State
          if (_isLoading) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: AppSpacing.borderRadiusMd,
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                children: [
                  const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _processingStep,
                    style: AppTextStyles.bodyMedium
                        .copyWith(fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'OCR is verifying supplier, invoice #, and quantities safely...',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.inkSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.statusCancelledBg,
                borderRadius: AppSpacing.borderRadiusMd,
                border: Border.all(
                    color: AppColors.statusCancelled.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.statusCancelled, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_errorMessage!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.statusCancelled)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Document Details if uploaded
          if (_document != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(color: AppColors.line),
              ),
              child: Row(
                children: [
                  Icon(
                    _document!.mimeType.contains('pdf')
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined,
                    color: AppColors.inkSecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _document!.originalFilename,
                      style: AppTextStyles.labelMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _document!.formattedFileSize,
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.inkSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],

          // Verification Results
          if (_verification != null) ...[
            if (_verification!.isMatch)
              _buildMatchView(_verification!)
            else
              _buildMismatchView(_verification!),
            const SizedBox(height: AppSpacing.md),
          ] else if (!_isLoading) ...[
            // Prompt to upload
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.canvas,
                borderRadius: AppSpacing.borderRadiusMd,
                border: Border.all(
                    color: AppColors.line, style: BorderStyle.solid),
              ),
              child: Column(
                children: [
                  const Icon(Icons.cloud_upload_outlined,
                      size: 32, color: AppColors.inkSecondary),
                  const SizedBox(height: 6),
                  Text(
                    'Upload Physical Receipt (PDF or Image)',
                    style: AppTextStyles.headlineSmall.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'StockSense will read the document, verify supplier, receipt #, and compare received quantities.',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.inkSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // Actions
          if (!widget.isImmutable) ...[
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    label: _document == null
                        ? 'Upload & Verify Receipt'
                        : 'Re-upload / Re-verify',
                    icon: Icons.upload_file_rounded,
                    variant: _verification?.isMatch == true
                        ? AppButtonVariant.outline
                        : AppButtonVariant.primary,
                    isLoading: _isLoading,
                    onPressed: _pickAndUploadReceipt,
                  ),
                ),
              ],
            ),
          ],

          // Mandatory Architecture Disclaimer
          const SizedBox(height: 8),
          Center(
            child: Text(
              'OCR is an assistive verification layer only. Inventory is modified only upon official Receipt Validation.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.inkTertiary,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationBadge(String status) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (status.toUpperCase()) {
      case 'MATCH':
        bg = AppColors.statusDoneBg;
        fg = AppColors.statusDone;
        label = 'MATCH';
        icon = Icons.check_circle_rounded;
        break;
      case 'REVIEW_REQUIRED':
        bg = AppColors.statusDraftBg;
        fg = AppColors.statusDraft;
        label = 'REVIEW REQUIRED';
        icon = Icons.warning_amber_rounded;
        break;
      case 'LOW_CONFIDENCE':
        bg = AppColors.statusWaitingBg;
        fg = AppColors.statusWaiting;
        label = 'LOW CONFIDENCE';
        icon = Icons.help_outline_rounded;
        break;
      default:
        bg = AppColors.statusCancelledBg;
        fg = AppColors.statusCancelled;
        label = status;
        icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppSpacing.borderRadiusSm,
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg, size: 14),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTextStyles.labelSmall
                .copyWith(color: fg, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchView(ReceiptVerificationResult ver) {
    final confPct = (ver.confidence * 100).toInt();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.statusDoneBg,
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: AppColors.statusDone.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_rounded,
                  color: AppColors.statusDone, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Physical Receipt Matches Digital Order',
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: AppColors.statusDone,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppSpacing.borderRadiusSm,
                  border: Border.all(
                      color: AppColors.statusDone.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'Confidence: $confPct%',
                  style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.statusDone, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const Divider(height: 18),
          _buildFieldRow(
            'Supplier',
            ver.supplierOcr ?? ver.supplierSystem ?? widget.supplier ?? 'Verified',
            true,
          ),
          _buildFieldRow(
            'Receipt / Invoice #',
            ver.receiptNumberOcr ?? widget.reference,
            true,
          ),
          if (ver.receiptDate != null)
            _buildFieldRow('Receipt Date', ver.receiptDate!, true),
          _buildFieldRow(
            'Product',
            widget.productName,
            true,
          ),
          _buildFieldRow(
            'Received Quantity',
            '${widget.quantity.toInt()} units (Matches physical record)',
            true,
          ),
        ],
      ),
    );
  }

  Widget _buildMismatchView(ReceiptVerificationResult ver) {
    final confPct = (ver.confidence * 100).toInt();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.statusDraftBg,
        borderRadius: AppSpacing.borderRadiusMd,
        border: Border.all(color: AppColors.statusDraft.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppColors.statusDraft, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'REVIEW REQUIRED: Physical Mismatch',
                  style: AppTextStyles.headlineSmall.copyWith(
                    color: AppColors.statusDraft,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: AppSpacing.borderRadiusSm,
                  border: Border.all(
                      color: AppColors.statusDraft.withValues(alpha: 0.4)),
                ),
                child: Text(
                  'Confidence: $confPct%',
                  style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.statusDraft, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'A discrepancy was detected between the physical receipt and the StockSense record. Review the values below before validating:',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.ink),
          ),
          const Divider(height: 18),

          // Items comparison table
          for (final item in ver.items) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppSpacing.borderRadiusSm,
                border: Border.all(color: AppColors.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(widget.productName, style: AppTextStyles.labelLarge),
                      StatusBadge(
                          status: item.isMismatch ? 'DRAFT' : 'DONE'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('SYSTEM QUANTITY',
                              style: AppTextStyles.labelSmall),
                          Text('${item.systemQuantity.toInt()} ${item.unit ?? "units"}',
                              style: AppTextStyles.headlineSmall),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('PHYSICAL RECEIPT',
                              style: AppTextStyles.labelSmall),
                          Text(
                            item.ocrQuantity != null
                                ? '${item.ocrQuantity!.toInt()} ${item.unit ?? "units"}'
                                : 'Not Found',
                            style: AppTextStyles.headlineSmall.copyWith(
                              color: item.isMismatch
                                  ? AppColors.statusCancelled
                                  : AppColors.statusDone,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('DIFFERENCE', style: AppTextStyles.labelSmall),
                          Text(
                            item.difference != null
                                ? '${item.difference! > 0 ? "+" : ""}${item.difference!.toInt()} ${item.unit ?? "units"}'
                                : '--',
                            style: AppTextStyles.headlineSmall.copyWith(
                              color: item.isMismatch
                                  ? AppColors.statusCancelled
                                  : AppColors.statusDone,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // Issues list
          if (ver.issues.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Discrepancy Notes:',
                style: AppTextStyles.labelSmall
                    .copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            for (final issue in ver.issues) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style: TextStyle(
                            color: AppColors.statusDraft,
                            fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        issue,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, String value, bool isMatched) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isMatched
                ? Icons.check_circle_outline_rounded
                : Icons.cancel_outlined,
            size: 16,
            color:
                isMatched ? AppColors.statusDone : AppColors.statusCancelled,
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: AppTextStyles.bodySmall
                  .copyWith(color: AppColors.inkSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
