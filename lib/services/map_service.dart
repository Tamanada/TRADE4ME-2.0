import '../models/map_category_model.dart';
import '../models/map_place_model.dart';
import '../models/user_location_stat_model.dart';
import './supabase_service.dart';

class MapService {
  get client => SupabaseService.instance.client;

  // Get places within bounding box
  Future<List<MapPlaceModel>> getPlacesInBbox({
    required double minLat,
    required double minLng,
    required double maxLat,
    required double maxLng,
    String? categoryId,
    String? placeType,
    String? searchText,
  }) async {
    try {
      final response = await client.rpc(
        'get_places_in_bbox',
        params: {
          'min_lat': minLat,
          'min_lng': minLng,
          'max_lat': maxLat,
          'max_lng': maxLng,
          'filter_category': categoryId,
          'filter_type': placeType,
          'search_text': searchText,
        },
      );

      return (response as List)
          .map((json) => MapPlaceModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw Exception('Failed to get places: $error');
    }
  }

  // Get all categories
  Future<List<MapCategoryModel>> getCategories() async {
    try {
      final response = await client
          .from('map_categories')
          .select()
          .eq('enabled', true)
          .order('name', ascending: true);

      return (response as List)
          .map(
            (json) => MapCategoryModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (error) {
      throw Exception('Failed to get categories: $error');
    }
  }

  // Add a new place
  Future<MapPlaceModel> addPlace(Map<String, dynamic> placeData) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final data = {...placeData, 'owner_user_id': userId, 'status': 'pending'};

      final response = await client
          .from('map_places')
          .insert(data)
          .select()
          .single();

      return MapPlaceModel.fromJson(response);
    } catch (error) {
      throw Exception('Failed to add place: $error');
    }
  }

  // Update place
  Future<MapPlaceModel> updatePlace(
    String placeId,
    Map<String, dynamic> updates,
  ) async {
    try {
      final response = await client
          .from('map_places')
          .update({...updates, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', placeId)
          .select()
          .single();

      return MapPlaceModel.fromJson(response);
    } catch (error) {
      throw Exception('Failed to update place: $error');
    }
  }

  // Get user's places
  Future<List<MapPlaceModel>> getUserPlaces() async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await client
          .from('map_places')
          .select()
          .eq('owner_user_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => MapPlaceModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw Exception('Failed to get user places: $error');
    }
  }

  // Toggle favorite
  Future<void> toggleFavorite(String placeId) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final existing = await client
          .from('map_favorites')
          .select()
          .eq('user_id', userId)
          .eq('place_id', placeId)
          .maybeSingle();

      if (existing != null) {
        await client
            .from('map_favorites')
            .delete()
            .eq('user_id', userId)
            .eq('place_id', placeId);
      } else {
        await client.from('map_favorites').insert({
          'user_id': userId,
          'place_id': placeId,
        });
      }
    } catch (error) {
      throw Exception('Failed to toggle favorite: $error');
    }
  }

  // Check if place is favorited
  Future<bool> isFavorited(String placeId) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await client
          .from('map_favorites')
          .select()
          .eq('user_id', userId)
          .eq('place_id', placeId)
          .maybeSingle();

      return response != null;
    } catch (error) {
      return false;
    }
  }

  // Report place
  Future<void> reportPlace({
    required String placeId,
    required String reason,
    String? notes,
  }) async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      await client.from('map_reports').insert({
        'place_id': placeId,
        'reported_by_user_id': userId,
        'reason': reason,
        'notes': notes,
      });
    } catch (error) {
      throw Exception('Failed to report place: $error');
    }
  }

  // Get pending places (admin only)
  Future<List<MapPlaceModel>> getPendingPlaces() async {
    try {
      final response = await client
          .from('map_places')
          .select()
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => MapPlaceModel.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (error) {
      throw Exception('Failed to get pending places: $error');
    }
  }

  // Approve place (admin only)
  Future<void> approvePlace(String placeId) async {
    try {
      await client
          .from('map_places')
          .update({
            'status': 'approved',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', placeId);
    } catch (error) {
      throw Exception('Failed to approve place: $error');
    }
  }

  // Reject place (admin only)
  Future<void> rejectPlace(String placeId) async {
    try {
      await client
          .from('map_places')
          .update({
            'status': 'rejected',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', placeId);
    } catch (error) {
      throw Exception('Failed to reject place: $error');
    }
  }

  // Suspend place (admin only)
  Future<void> suspendPlace(String placeId) async {
    try {
      await client
          .from('map_places')
          .update({
            'status': 'suspended',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', placeId);
    } catch (error) {
      throw Exception('Failed to suspend place: $error');
    }
  }

  // Get all categories for admin (including disabled)
  Future<List<MapCategoryModel>> getAllCategories() async {
    try {
      final response = await client
          .from('map_categories')
          .select()
          .order('name', ascending: true);

      return (response as List)
          .map(
            (json) => MapCategoryModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (error) {
      throw Exception('Failed to get all categories: $error');
    }
  }

  // Add category (admin only)
  Future<MapCategoryModel> addCategory({
    required String name,
    required String icon,
    bool enabled = true,
  }) async {
    try {
      final response = await client
          .from('map_categories')
          .insert({'name': name, 'icon': icon, 'enabled': enabled})
          .select()
          .single();

      return MapCategoryModel.fromJson(response);
    } catch (error) {
      throw Exception('Failed to add category: $error');
    }
  }

  // Update category (admin only)
  Future<void> updateCategory({
    required String categoryId,
    String? name,
    String? icon,
    bool? enabled,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (icon != null) updates['icon'] = icon;
      if (enabled != null) updates['enabled'] = enabled;

      if (updates.isEmpty) return;

      await client.from('map_categories').update(updates).eq('id', categoryId);
    } catch (error) {
      throw Exception('Failed to update category: $error');
    }
  }

  // Delete category (admin only)
  Future<void> deleteCategory(String categoryId) async {
    try {
      await client.from('map_categories').delete().eq('id', categoryId);
    } catch (error) {
      throw Exception('Failed to delete category: $error');
    }
  }

  // Get all reports (admin only)
  Future<List<Map<String, dynamic>>> getReports({String? status}) async {
    try {
      var query = client
          .from('map_reports')
          .select(
            '*, map_places(*), user_profiles!map_reports_reported_by_user_id_fkey(*)',
          );

      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }

      final response = await query.order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (error) {
      throw Exception('Failed to get reports: $error');
    }
  }

  // Update report status (admin only)
  Future<void> updateReportStatus(String reportId, String status) async {
    try {
      await client
          .from('map_reports')
          .update({'status': status})
          .eq('id', reportId);
    } catch (error) {
      throw Exception('Failed to update report status: $error');
    }
  }

  // Check if current user is admin
  Future<bool> isAdmin() async {
    try {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return false;

      final response = await client
          .from('user_profiles')
          .select('is_admin')
          .eq('id', userId)
          .single();

      return response['is_admin'] as bool? ?? false;
    } catch (error) {
      return false;
    }
  }

  // Get user location statistics for map visualization
  Future<List<UserLocationStatModel>> getUserLocationStats() async {
    try {
      final response = await client.rpc('get_user_location_stats');

      return (response as List)
          .map(
            (json) =>
                UserLocationStatModel.fromJson(json as Map<String, dynamic>),
          )
          .toList();
    } catch (error) {
      throw Exception('Failed to get user location stats: $error');
    }
  }
}
