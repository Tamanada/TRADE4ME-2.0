-- Migration: User Location Visualization
-- Description: Adds functionality to display user locations on the world map based on their country

-- Create a function to get user counts by country with approximate coordinates
-- This function returns country names with user counts and approximate center coordinates
CREATE OR REPLACE FUNCTION get_user_location_stats()
RETURNS TABLE (
  country TEXT,
  user_count BIGINT,
  lat DOUBLE PRECISION,
  lng DOUBLE PRECISION
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH country_coords AS (
    -- Approximate coordinates for countries (center points)
    -- This is a simplified mapping - in production, use a proper geocoding service
    SELECT 'United States'::TEXT as name, 37.0902::DOUBLE PRECISION as lat, -95.7129::DOUBLE PRECISION as lng
    UNION ALL SELECT 'Canada', 56.1304, -106.3468
    UNION ALL SELECT 'United Kingdom', 55.3781, -3.4360
    UNION ALL SELECT 'France', 46.2276, 2.2137
    UNION ALL SELECT 'Germany', 51.1657, 10.4515
    UNION ALL SELECT 'Italy', 41.8719, 12.5674
    UNION ALL SELECT 'Spain', 40.4637, -3.7492
    UNION ALL SELECT 'Australia', -25.2744, 133.7751
    UNION ALL SELECT 'Japan', 36.2048, 138.2529
    UNION ALL SELECT 'China', 35.8617, 104.1954
    UNION ALL SELECT 'India', 20.5937, 78.9629
    UNION ALL SELECT 'Brazil', -14.2350, -51.9253
    UNION ALL SELECT 'Mexico', 23.6345, -102.5528
    UNION ALL SELECT 'South Africa', -30.5595, 22.9375
    UNION ALL SELECT 'Russia', 61.5240, 105.3188
    UNION ALL SELECT 'Netherlands', 52.1326, 5.2913
    UNION ALL SELECT 'Belgium', 50.5039, 4.4699
    UNION ALL SELECT 'Switzerland', 46.8182, 8.2275
    UNION ALL SELECT 'Sweden', 60.1282, 18.6435
    UNION ALL SELECT 'Norway', 60.4720, 8.4689
    UNION ALL SELECT 'Denmark', 56.2639, 9.5018
    UNION ALL SELECT 'Poland', 51.9194, 19.1451
    UNION ALL SELECT 'Portugal', 39.3999, -8.2245
    UNION ALL SELECT 'Greece', 39.0742, 21.8243
    UNION ALL SELECT 'Turkey', 38.9637, 35.2433
    UNION ALL SELECT 'South Korea', 35.9078, 127.7669
    UNION ALL SELECT 'Indonesia', -0.7893, 113.9213
    UNION ALL SELECT 'Thailand', 15.8700, 100.9925
    UNION ALL SELECT 'Vietnam', 14.0583, 108.2772
    UNION ALL SELECT 'Philippines', 12.8797, 121.7740
    UNION ALL SELECT 'Malaysia', 4.2105, 101.9758
    UNION ALL SELECT 'Singapore', 1.3521, 103.8198
    UNION ALL SELECT 'New Zealand', -40.9006, 174.8860
    UNION ALL SELECT 'Argentina', -38.4161, -63.6167
    UNION ALL SELECT 'Chile', -35.6751, -71.5430
    UNION ALL SELECT 'Colombia', 4.5709, -74.2973
    UNION ALL SELECT 'Peru', -9.1900, -75.0152
    UNION ALL SELECT 'Egypt', 26.8206, 30.8025
    UNION ALL SELECT 'Nigeria', 9.0820, 8.6753
    UNION ALL SELECT 'Kenya', -0.0236, 37.9062
    UNION ALL SELECT 'Israel', 31.0461, 34.8516
    UNION ALL SELECT 'United Arab Emirates', 23.4241, 53.8478
    UNION ALL SELECT 'Saudi Arabia', 23.8859, 45.0792
    UNION ALL SELECT 'Pakistan', 30.3753, 69.3451
    UNION ALL SELECT 'Bangladesh', 23.6850, 90.3563
    UNION ALL SELECT 'Ukraine', 48.3794, 31.1656
    UNION ALL SELECT 'Ireland', 53.4129, -8.2439
    UNION ALL SELECT 'Austria', 47.5162, 14.5501
    UNION ALL SELECT 'Czech Republic', 49.8175, 15.4730
    UNION ALL SELECT 'Finland', 61.9241, 25.7482
    UNION ALL SELECT 'Hungary', 47.1625, 19.5033
  )
  SELECT 
    up.country,
    COUNT(*)::BIGINT as user_count,
    COALESCE(cc.lat, 0.0) as lat,
    COALESCE(cc.lng, 0.0) as lng
  FROM user_profiles up
  LEFT JOIN country_coords cc ON LOWER(TRIM(up.country)) = LOWER(TRIM(cc.name))
  WHERE up.country IS NOT NULL 
    AND up.country != ''
    AND up.onboarding_completed = true
  GROUP BY up.country, cc.lat, cc.lng
  HAVING COUNT(*) > 0
  ORDER BY user_count DESC;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_user_location_stats() TO authenticated;

-- Create index on onboarding_completed if it doesn't exist (it should from previous migration)
-- This will help optimize the query performance
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes 
    WHERE indexname = 'idx_user_profiles_onboarding_completed'
  ) THEN
    CREATE INDEX idx_user_profiles_onboarding_completed 
    ON user_profiles(onboarding_completed);
  END IF;
END $$;

-- Add comment to function
COMMENT ON FUNCTION get_user_location_stats() IS 
'Returns aggregated user location statistics by country with approximate coordinates for map visualization. Only includes users who completed onboarding.';