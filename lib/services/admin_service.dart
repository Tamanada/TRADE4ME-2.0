import './supabase_service.dart';

/// Service for admin-specific operations including place moderation,
/// category management, and report handling
class AdminService {
  static get _supabase => SupabaseService.instance.client;

  // ==================== DASHBOARD STATS ====================

  /// Get dashboard statistics for admin overview
  static Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      // Count pending places
      final pendingPlacesResponse = await _supabase
          .from('map_places')
          .select('id')
          .eq('status', 'pending');

      // Count total active users
      final activeUsersResponse = await _supabase
          .from('user_profiles')
          .select('id');

      // Count total approved listings
      final totalListingsResponse = await _supabase
          .from('map_places')
          .select('id')
          .eq('status', 'approved');

      // Count pending reports
      final flaggedContentResponse = await _supabase
          .from('map_reports')
          .select('id')
          .eq('status', 'pending');

      return {
        'pending_places': (pendingPlacesResponse as List).length,
        'active_users': (activeUsersResponse as List).length,
        'total_listings': (totalListingsResponse as List).length,
        'flagged_content': (flaggedContentResponse as List).length,
      };
    } catch (e) {
      throw Exception('Failed to load dashboard stats: $e');
    }
  }

  /// Get recent activity feed for admin dashboard
  static Future<List<Map<String, dynamic>>> getRecentActivity({
    int limit = 10,
  }) async {
    try {
      final response = await _supabase
          .from('map_places')
          .select(
            'id, title, status, created_at, owner_user_id, user_profiles(full_name)',
          )
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to load recent activity: $e');
    }
  }

  // ==================== PLACE MANAGEMENT ====================

  /// Get places with filters for admin management
  static Future<List<Map<String, dynamic>>> getPlacesForManagement({
    String? statusFilter,
    String? categoryId,
    String? searchQuery,
    int limit = 50,
  }) async {
    try {
      var query = _supabase.from('map_places').select('''
            id, title, description, status, place_type, created_at, 
            images, lat, lng, city, country, address_text,
            category_id, owner_user_id,
            map_categories(id, name, icon),
            user_profiles(full_name, email)
          ''');

      if (statusFilter != null) {
        query = query.eq('status', statusFilter);
      }

      if (categoryId != null) {
        query = query.eq('category_id', categoryId);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
          'title.ilike.%$searchQuery%,description.ilike.%$searchQuery%',
        );
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to load places: $e');
    }
  }

  /// Approve a place listing
  static Future<void> approvePlace(String placeId) async {
    try {
      await _supabase
          .from('map_places')
          .update({
            'status': 'approved',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', placeId);
    } catch (e) {
      throw Exception('Failed to approve place: $e');
    }
  }

  /// Reject a place listing
  static Future<void> rejectPlace(String placeId) async {
    try {
      await _supabase
          .from('map_places')
          .update({
            'status': 'rejected',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', placeId);
    } catch (e) {
      throw Exception('Failed to reject place: $e');
    }
  }

  /// Suspend a place listing
  static Future<void> suspendPlace(String placeId) async {
    try {
      await _supabase
          .from('map_places')
          .update({
            'status': 'suspended',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', placeId);
    } catch (e) {
      throw Exception('Failed to suspend place: $e');
    }
  }

  /// Bulk approve multiple places
  static Future<void> bulkApprovePlaces(List<String> placeIds) async {
    try {
      await _supabase
          .from('map_places')
          .update({
            'status': 'approved',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .inFilter('id', placeIds);
    } catch (e) {
      throw Exception('Failed to bulk approve places: $e');
    }
  }

  /// Bulk reject multiple places
  static Future<void> bulkRejectPlaces(List<String> placeIds) async {
    try {
      await _supabase
          .from('map_places')
          .update({
            'status': 'rejected',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .inFilter('id', placeIds);
    } catch (e) {
      throw Exception('Failed to bulk reject places: $e');
    }
  }

  // ==================== CATEGORY MANAGEMENT ====================

  /// Get all categories including disabled ones
  static Future<List<Map<String, dynamic>>> getAllCategories() async {
    try {
      final response = await _supabase
          .from('map_categories')
          .select('*')
          .order('name', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to load categories: $e');
    }
  }

  /// Toggle category enabled status
  static Future<void> toggleCategoryStatus(
    String categoryId,
    bool enabled,
  ) async {
    try {
      await _supabase
          .from('map_categories')
          .update({'enabled': enabled})
          .eq('id', categoryId);
    } catch (e) {
      throw Exception('Failed to update category status: $e');
    }
  }

  /// Create new category
  static Future<void> createCategory({
    required String name,
    required String icon,
    bool enabled = true,
  }) async {
    try {
      await _supabase.from('map_categories').insert({
        'name': name,
        'icon': icon,
        'enabled': enabled,
      });
    } catch (e) {
      throw Exception('Failed to create category: $e');
    }
  }

  /// Update existing category
  static Future<void> updateCategory({
    required String categoryId,
    required String name,
    required String icon,
  }) async {
    try {
      await _supabase
          .from('map_categories')
          .update({'name': name, 'icon': icon})
          .eq('id', categoryId);
    } catch (e) {
      throw Exception('Failed to update category: $e');
    }
  }

  // ==================== REPORT MANAGEMENT ====================

  /// Get user reports with filters
  static Future<List<Map<String, dynamic>>> getReports({
    String? statusFilter,
    int limit = 50,
  }) async {
    try {
      var query = _supabase.from('map_reports').select('''
            id, reason, notes, status, created_at,
            place_id, reported_by_user_id,
            map_places(id, title, status),
            user_profiles(full_name, email)
          ''');

      if (statusFilter != null) {
        query = query.eq('status', statusFilter);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to load reports: $e');
    }
  }

  /// Update report status
  static Future<void> updateReportStatus(String reportId, String status) async {
    try {
      await _supabase
          .from('map_reports')
          .update({'status': status})
          .eq('id', reportId);
    } catch (e) {
      throw Exception('Failed to update report status: $e');
    }
  }

  /// Dismiss a report
  static Future<void> dismissReport(String reportId) async {
    try {
      await updateReportStatus(reportId, 'dismissed');
    } catch (e) {
      throw Exception('Failed to dismiss report: $e');
    }
  }

  /// Resolve a report and suspend the place
  static Future<void> resolveReportAndSuspendPlace(
    String reportId,
    String placeId,
  ) async {
    try {
      // Suspend the place
      await suspendPlace(placeId);

      // Mark report as resolved
      await updateReportStatus(reportId, 'resolved');
    } catch (e) {
      throw Exception('Failed to resolve report: $e');
    }
  }

  // ==================== USER MANAGEMENT ====================

  /// Get all users with admin status
  static Future<List<Map<String, dynamic>>> getAllUsers({
    bool? adminFilter,
    String? searchQuery,
  }) async {
    try {
      var query = _supabase.from('user_profiles').select('*');

      if (adminFilter != null) {
        query = query.eq('is_admin', adminFilter);
      }

      if (searchQuery != null && searchQuery.isNotEmpty) {
        query = query.or(
          'full_name.ilike.%$searchQuery%,email.ilike.%$searchQuery%',
        );
      }

      final response = await query.order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      throw Exception('Failed to load users: $e');
    }
  }

  /// Check if current user is admin
  static Future<bool> isCurrentUserAdmin() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await _supabase
          .from('user_profiles')
          .select('is_admin')
          .eq('id', userId)
          .single();

      return response['is_admin'] == true;
    } catch (e) {
      return false;
    }
  }
}
