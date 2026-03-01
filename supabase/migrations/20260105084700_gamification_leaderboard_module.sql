-- Location: supabase/migrations/20260105084700_gamification_leaderboard_module.sql
-- Schema Analysis: Existing user_profiles with country field
-- Integration Type: NEW_MODULE - Gamification and leaderboard system
-- Dependencies: user_profiles

-- 1. Create enum types for gamification
CREATE TYPE public.badge_level AS ENUM (
  'peace_lover',
  'peace_gardener', 
  'peace_guide',
  'peace_guardian',
  'peace_illuminator',
  'peace_legend',
  'peace_angel'
);

-- 2. Create user_stats table for tracking gamification metrics
CREATE TABLE public.user_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  daily_actions_count INTEGER DEFAULT 0,
  total_tokens DECIMAL(10,2) DEFAULT 0.00,
  current_streak INTEGER DEFAULT 0,
  longest_streak INTEGER DEFAULT 0,
  last_action_date DATE,
  badge_level public.badge_level DEFAULT 'peace_lover'::public.badge_level,
  badge_multiplier INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_user_stats UNIQUE(user_id)
);

-- 3. Create daily_actions table for tracking daily peace actions
CREATE TABLE public.daily_actions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  action_date DATE NOT NULL DEFAULT CURRENT_DATE,
  tokens_earned DECIMAL(10,2) DEFAULT 1.00,
  badge_multiplier INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT unique_daily_action UNIQUE(user_id, action_date)
);

-- 4. Create indexes for performance
CREATE INDEX idx_user_stats_user_id ON public.user_stats(user_id);
CREATE INDEX idx_user_stats_daily_actions ON public.user_stats(daily_actions_count DESC);
CREATE INDEX idx_user_stats_total_tokens ON public.user_stats(total_tokens DESC);
CREATE INDEX idx_user_stats_longest_streak ON public.user_stats(longest_streak DESC);
CREATE INDEX idx_user_stats_badge_level ON public.user_stats(badge_level DESC);
CREATE INDEX idx_daily_actions_user_id ON public.daily_actions(user_id);
CREATE INDEX idx_daily_actions_date ON public.daily_actions(action_date DESC);
CREATE INDEX idx_daily_actions_user_date ON public.daily_actions(user_id, action_date);

-- 5. Create function to handle daily action and update stats
CREATE OR REPLACE FUNCTION public.record_daily_action(
  p_user_id UUID,
  p_base_tokens DECIMAL DEFAULT 1.00
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_stats RECORD;
  v_multiplier INTEGER;
  v_tokens_earned DECIMAL;
  v_new_streak INTEGER;
  v_action_exists BOOLEAN;
BEGIN
  -- Check if action already recorded today
  SELECT EXISTS(
    SELECT 1 FROM public.daily_actions
    WHERE user_id = p_user_id AND action_date = CURRENT_DATE
  ) INTO v_action_exists;

  IF v_action_exists THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Daily action already recorded for today'
    );
  END IF;

  -- Get or create user stats
  INSERT INTO public.user_stats (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_user_stats
  FROM public.user_stats
  WHERE user_id = p_user_id;

  v_multiplier := v_user_stats.badge_multiplier;
  v_tokens_earned := p_base_tokens * v_multiplier;

  -- Calculate streak
  IF v_user_stats.last_action_date = CURRENT_DATE - INTERVAL '1 day' THEN
    v_new_streak := v_user_stats.current_streak + 1;
  ELSIF v_user_stats.last_action_date = CURRENT_DATE THEN
    v_new_streak := v_user_stats.current_streak;
  ELSE
    v_new_streak := 1;
  END IF;

  -- Insert daily action
  INSERT INTO public.daily_actions (user_id, action_date, tokens_earned, badge_multiplier)
  VALUES (p_user_id, CURRENT_DATE, v_tokens_earned, v_multiplier);

  -- Update user stats
  UPDATE public.user_stats
  SET 
    daily_actions_count = daily_actions_count + 1,
    total_tokens = total_tokens + v_tokens_earned,
    current_streak = v_new_streak,
    longest_streak = GREATEST(longest_streak, v_new_streak),
    last_action_date = CURRENT_DATE,
    updated_at = CURRENT_TIMESTAMP
  WHERE user_id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'tokens_earned', v_tokens_earned,
    'current_streak', v_new_streak,
    'total_tokens', v_user_stats.total_tokens + v_tokens_earned
  );
END;
$$;

-- 6. Create function to update badge level
CREATE OR REPLACE FUNCTION public.update_badge_level(
  p_user_id UUID,
  p_badge_level public.badge_level
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_multiplier INTEGER;
BEGIN
  -- Determine multiplier based on badge level
  v_multiplier := CASE p_badge_level
    WHEN 'peace_lover' THEN 1
    WHEN 'peace_gardener' THEN 2
    WHEN 'peace_guide' THEN 3
    WHEN 'peace_guardian' THEN 3
    WHEN 'peace_illuminator' THEN 4
    WHEN 'peace_legend' THEN 5
    WHEN 'peace_angel' THEN 10
  END;

  -- Update user stats
  UPDATE public.user_stats
  SET 
    badge_level = p_badge_level,
    badge_multiplier = v_multiplier,
    updated_at = CURRENT_TIMESTAMP
  WHERE user_id = p_user_id;

  RETURN FOUND;
END;
$$;

-- 7. Create function to get leaderboard by category
CREATE OR REPLACE FUNCTION public.get_leaderboard(
  p_category TEXT,
  p_country TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100
)
RETURNS TABLE(
  rank INTEGER,
  user_id UUID,
  full_name TEXT,
  country TEXT,
  selected_avatar TEXT,
  is_anonymous BOOLEAN,
  value DECIMAL,
  badge_level TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH ranked_users AS (
    SELECT 
      us.user_id,
      up.full_name,
      up.country,
      up.selected_avatar,
      up.is_anonymous,
      us.badge_level::TEXT,
      CASE p_category
        WHEN 'daily_actions' THEN us.daily_actions_count::DECIMAL
        WHEN 'total_tokens' THEN us.total_tokens
        WHEN 'streak_records' THEN us.longest_streak::DECIMAL
        WHEN 'badge_levels' THEN (
          CASE us.badge_level
            WHEN 'peace_lover' THEN 1
            WHEN 'peace_gardener' THEN 2
            WHEN 'peace_guide' THEN 3
            WHEN 'peace_guardian' THEN 4
            WHEN 'peace_illuminator' THEN 5
            WHEN 'peace_legend' THEN 6
            WHEN 'peace_angel' THEN 7
          END
        )::DECIMAL
      END as metric_value
    FROM public.user_stats us
    INNER JOIN public.user_profiles up ON us.user_id = up.id
    WHERE (p_country IS NULL OR up.country = p_country)
  )
  SELECT 
    ROW_NUMBER() OVER (ORDER BY ru.metric_value DESC)::INTEGER as rank,
    ru.user_id,
    CASE WHEN ru.is_anonymous THEN 'Anonymous User' ELSE ru.full_name END as full_name,
    ru.country,
    ru.selected_avatar,
    ru.is_anonymous,
    ru.metric_value as value,
    ru.badge_level
  FROM ranked_users ru
  ORDER BY ru.metric_value DESC
  LIMIT p_limit;
END;
$$;

-- 8. Enable RLS
ALTER TABLE public.user_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_actions ENABLE ROW LEVEL SECURITY;

-- 9. Create RLS policies
CREATE POLICY "users_view_all_stats"
ON public.user_stats
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "users_manage_own_stats"
ON public.user_stats
FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "users_view_all_actions"
ON public.daily_actions
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "users_manage_own_actions"
ON public.daily_actions
FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 10. Create mock data
DO $$
DECLARE
  existing_user_ids UUID[];
  user_id_var UUID;
  i INTEGER;
  base_tokens DECIMAL;
BEGIN
  -- Get existing user IDs
  SELECT ARRAY_AGG(id) INTO existing_user_ids
  FROM public.user_profiles
  LIMIT 10;

  -- If no users exist, exit
  IF existing_user_ids IS NULL OR array_length(existing_user_ids, 1) = 0 THEN
    RAISE NOTICE 'No existing users found. Create users first.';
    RETURN;
  END IF;

  -- Create stats for existing users
  FOREACH user_id_var IN ARRAY existing_user_ids
  LOOP
    -- Create user stats with random values
    INSERT INTO public.user_stats (
      user_id,
      daily_actions_count,
      total_tokens,
      current_streak,
      longest_streak,
      last_action_date,
      badge_level,
      badge_multiplier
    ) VALUES (
      user_id_var,
      floor(random() * 50 + 10)::INTEGER,
      (random() * 500 + 100)::DECIMAL(10,2),
      floor(random() * 15 + 1)::INTEGER,
      floor(random() * 30 + 5)::INTEGER,
      CURRENT_DATE - floor(random() * 5)::INTEGER,
      (ARRAY['peace_lover', 'peace_gardener', 'peace_guide'])[floor(random() * 3 + 1)]::public.badge_level,
      floor(random() * 3 + 1)::INTEGER
    )
    ON CONFLICT (user_id) DO NOTHING;

    -- Create some daily actions for past days
    FOR i IN 1..5 LOOP
      base_tokens := 1.00;
      INSERT INTO public.daily_actions (
        user_id,
        action_date,
        tokens_earned,
        badge_multiplier
      ) VALUES (
        user_id_var,
        CURRENT_DATE - i,
        base_tokens * floor(random() * 3 + 1)::INTEGER,
        floor(random() * 3 + 1)::INTEGER
      )
      ON CONFLICT (user_id, action_date) DO NOTHING;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Mock gamification data created for % users', array_length(existing_user_ids, 1);
END $$;