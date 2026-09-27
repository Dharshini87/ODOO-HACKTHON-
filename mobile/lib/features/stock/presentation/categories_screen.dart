import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/loading_view.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/empty_view.dart';
import '../../../core/widgets/access_denied_view.dart';
import '../../../core/widgets/system_feedback.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../shared/providers/inventory_providers.dart';
import '../../auth/presentation/auth_provider.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  final _searchController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddEditDialog({Map<String, dynamic>? category}) {
    final isEditing = category != null;
    final nameCtrl = TextEditingController(text: category?['name']?.toString() ?? '');
    final descCtrl = TextEditingController(text: category?['description']?.toString() ?? '');
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand.withValues(alpha: 0.12),
                  borderRadius: AppSpacing.borderRadiusSm,
                ),
                child: Icon(
                  isEditing ? Icons.edit_note_rounded : Icons.create_new_folder_outlined,
                  color: AppColors.brand,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Text(isEditing ? 'Edit Category' : 'New Category', style: AppTextStyles.headlineMedium),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  controller: nameCtrl,
                  label: 'Category Name',
                  hintText: 'e.g., Raw Materials, Electronics',
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: descCtrl,
                  label: 'Description (Optional)',
                  hintText: 'Brief explanation of category contents',
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isSaving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        AppFeedback.showError(ctx, 'Category name cannot be empty');
                        return;
                      }

                      setDialogState(() => isSaving = true);
                      try {
                        final repo = ref.read(masterDataRepositoryProvider);
                        if (isEditing) {
                          final catId = category['id'] as int;
                          await repo.updateCategory(catId, {
                            'name': name,
                            'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                            'is_active': category['is_active'] ?? true,
                          });
                        } else {
                          await repo.createCategory({
                            'name': name,
                            'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                            'is_active': true,
                          });
                        }

                        ref.invalidate(categoriesFutureProvider);
                        ref.invalidate(productsFutureProvider);

                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          AppFeedback.showSuccess(
                            context,
                            isEditing ? 'Category "$name" updated' : 'Category "$name" created',
                          );
                        }
                      } catch (e) {
                        setDialogState(() => isSaving = false);
                        if (mounted) {
                          AppFeedback.showError(context, 'Failed to save: $e');
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isEditing ? 'Save Changes' : 'Create Category'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).user;
    if (user != null && !user.isManager) {
      return const AccessRestrictedScaffold(
        title: 'Category Management',
        message: 'Only Inventory Managers have permission to create and manage product categories.',
      );
    }

    final categoriesAsync = ref.watch(categoriesFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text('Categories', style: AppTextStyles.headlineLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Categories',
            onPressed: () => ref.invalidate(categoriesFutureProvider),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.brand,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Category'),
        onPressed: () => _showAddEditDialog(),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _filter = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search categories...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _filter = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(categoriesFutureProvider),
              child: categoriesAsync.when(
                loading: () => const LoadingView(message: 'Loading categories...'),
                error: (err, _) => ErrorView(
                  message: err.toString(),
                  onRetry: () => ref.invalidate(categoriesFutureProvider),
                ),
                data: (list) {
                  final filtered = list.where((c) {
                    final name = (c['name'] ?? '').toString().toLowerCase();
                    final desc = (c['description'] ?? '').toString().toLowerCase();
                    return name.contains(_filter) || desc.contains(_filter);
                  }).toList();

                  if (filtered.isEmpty) {
                    return const EmptyView(
                      title: 'No Categories Found',
                      subtitle: 'Add categories to organize inventory and product catalog',
                    );
                  }

                  return ListView.separated(
                    padding: AppSpacing.pagePadding,
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, i) {
                      final cat = filtered[i] as Map<String, dynamic>;
                      final name = cat['name'] as String? ?? 'Category';
                      final desc = cat['description'] as String? ?? 'No description';
                      final isActive = (cat['is_active'] as bool?) ?? true;

                      return AppCard(
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.brand.withValues(alpha: 0.1),
                                borderRadius: AppSpacing.borderRadiusMd,
                              ),
                              child: const Icon(Icons.category_rounded, color: AppColors.brand, size: 22),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name,
                                          style: AppTextStyles.headlineMedium,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isActive ? AppColors.statusDone : AppColors.statusCancelled)
                                              .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isActive ? 'ACTIVE' : 'INACTIVE',
                                          style: AppTextStyles.labelSmall.copyWith(
                                            color: isActive ? AppColors.statusDone : AppColors.statusCancelled,
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    desc,
                                    style: AppTextStyles.bodySmall,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.inkTertiary),
                              tooltip: 'Edit Category',
                              onPressed: () => _showAddEditDialog(category: cat),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
