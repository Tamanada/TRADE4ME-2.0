-- Location: supabase/migrations/20260105073452_user_onboarding_extension.sql
-- Schema Analysis: Extending user_profiles with onboarding fields
-- Integration Type: MODIFICATIVE - adding columns to existing table
-- Dependencies: user_profiles table

-- Add new columns for user onboarding
ALTER TABLE public.user_profiles
ADD COLUMN IF NOT EXISTS country TEXT,
ADD COLUMN IF NOT EXISTS gender TEXT,
ADD COLUMN IF NOT EXISTS age INTEGER,
ADD COLUMN IF NOT EXISTS peace_message TEXT,
ADD COLUMN IF NOT EXISTS selected_avatar TEXT DEFAULT 'dove',
ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN DEFAULT false;

-- Add indexes for new columns
CREATE INDEX IF NOT EXISTS idx_user_profiles_country ON public.user_profiles(country);
CREATE INDEX IF NOT EXISTS idx_user_profiles_onboarding_completed ON public.user_profiles(onboarding_completed);

-- Add check constraint for avatar selection
ALTER TABLE public.user_profiles
ADD CONSTRAINT chk_user_profiles_avatar 
CHECK (selected_avatar IN ('dove', 'sun', 'star', 'olive_branch', 'heart', 'earth'));

-- Update handle_new_user trigger function to include new fields
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
LANGUAGE plpgsql
AS $func$
BEGIN
  INSERT INTO public.user_profiles (
    id, 
    email, 
    full_name,
    avatar_url,
    is_admin,
    country,
    gender,
    age,
    peace_message,
    selected_avatar,
    is_anonymous,
    onboarding_completed
  )
  VALUES (
    NEW.id, 
    NEW.email, 
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
    COALESCE((NEW.raw_user_meta_data->>'is_admin')::boolean, false),
    COALESCE(NEW.raw_user_meta_data->>'country', null),
    COALESCE(NEW.raw_user_meta_data->>'gender', null),
    COALESCE((NEW.raw_user_meta_data->>'age')::integer, null),
    COALESCE(NEW.raw_user_meta_data->>'peace_message', null),
    COALESCE(NEW.raw_user_meta_data->>'selected_avatar', 'dove'),
    COALESCE((NEW.raw_user_meta_data->>'is_anonymous')::boolean, false),
    COALESCE((NEW.raw_user_meta_data->>'onboarding_completed')::boolean, false)
  );
  RETURN NEW;
END;
$func$;