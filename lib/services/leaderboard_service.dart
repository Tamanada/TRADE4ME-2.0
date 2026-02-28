import './supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LeaderboardService {
  SupabaseClient get _client => SupabaseService.instance.client;

  Future<List<Map<String, dynamic>>> getLeaderboard({
    required String category,
    String? country,
    int limit = 100,
  }) async {
    try {
      final response = await _client.rpc(
        'get_leaderboard',
        params: {
          'p_category': category,
          'p_country': country,
          'p_limit': limit,
        },
      );

      return List<Map<String, dynamic>>.from(response);
    } catch (error) {
      throw Exception('Failed to fetch leaderboard: $error');
    }
  }

  Future<Map<String, dynamic>?> getUserRanking({
    required String userId,
    required String category,
    String? country,
  }) async {
    try {
      final leaderboard = await getLeaderboard(
        category: category,
        country: country,
        limit: 1000,
      );

      final userRank = leaderboard.indexWhere(
        (entry) => entry['user_id'] == userId,
      );

      if (userRank == -1) return null;

      return leaderboard[userRank];
    } catch (error) {
      throw Exception('Failed to fetch user ranking: $error');
    }
  }

  Future<Map<String, dynamic>?> getUserStats(String userId) async {
    try {
      final response = await _client
          .from('user_stats')
          .select(
            '*, user_profiles!inner(full_name, country, selected_avatar, is_anonymous)',
          )
          .eq('user_id', userId)
          .single();

      return response;
    } catch (error) {
      throw Exception('Failed to fetch user stats: $error');
    }
  }

  Future<Map<String, dynamic>> recordDailyAction({
    required String userId,
    double baseTokens = 1.00,
  }) async {
    try {
      final response = await _client.rpc(
        'record_daily_action',
        params: {'p_user_id': userId, 'p_base_tokens': baseTokens},
      );

      return Map<String, dynamic>.from(response);
    } catch (error) {
      throw Exception('Failed to record daily action: $error');
    }
  }

  Future<bool> updateBadgeLevel({
    required String userId,
    required String badgeLevel,
  }) async {
    try {
      final response = await _client.rpc(
        'update_badge_level',
        params: {'p_user_id': userId, 'p_badge_level': badgeLevel},
      );

      return response == true;
    } catch (error) {
      throw Exception('Failed to update badge level: $error');
    }
  }

  Future<List<String>> getAvailableCountries() async {
    try {
      final response = await _client
          .from('user_profiles')
          .select('country')
          .not('country', 'is', null)
          .order('country');

      final countries = response
          .map((row) => row['country'] as String)
          .toSet()
          .toList();

      return countries;
    } catch (error) {
      throw Exception('Failed to fetch countries: $error');
    }
  }
}