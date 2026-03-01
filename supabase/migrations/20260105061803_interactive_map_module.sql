-- Location: supabase/migrations/20260105061803_interactive_map_module.sql
-- Schema Analysis: Database appears empty - Fresh project setup
-- Integration Type: NEW_MODULE - Interactive Map functionality
-- Dependencies: None - Creating complete map module from scratch

-- 1. Custom Types
CREATE TYPE public.place_type AS ENUM ('person', 'business', 'community', 'event');
CREATE TYPE public.place_visibility AS ENUM ('public', 'members_only', 'private');
CREATE TYPE public.place_status AS ENUM ('pending', 'approved', 'rejected', 'suspended');
CREATE TYPE public.report_status AS ENUM ('pending', 'reviewed', 'resolved', 'dismissed');

-- 2. Core Tables

-- Map Categories
CREATE TABLE public.map_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    icon TEXT NOT NULL,
    enabled BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- User Profiles (intermediary table for PostgREST compatibility)
CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    avatar_url TEXT,
    is_admin BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Map Places
CREATE TABLE public.map_places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    place_type public.place_type NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    category_id UUID REFERENCES public.map_categories(id) ON DELETE SET NULL,
    tags TEXT[],
    lat DECIMAL(10, 8) NOT NULL,
    lng DECIMAL(11, 8) NOT NULL,
    geo_hash TEXT,
    address_text TEXT,
    country TEXT,
    city TEXT,
    contact JSONB DEFAULT '{}',
    images TEXT[],
    visibility public.place_visibility DEFAULT 'public',
    status public.place_status DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Map Reports
CREATE TABLE public.map_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    place_id UUID REFERENCES public.map_places(id) ON DELETE CASCADE,
    reported_by_user_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    notes TEXT,
    status public.report_status DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- Map Favorites
CREATE TABLE public.map_favorites (
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE CASCADE,
    place_id UUID REFERENCES public.map_places(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, place_id)
);

-- 3. Indexes
CREATE INDEX idx_map_places_status ON public.map_places(status);
CREATE INDEX idx_map_places_visibility ON public.map_places(visibility);
CREATE INDEX idx_map_places_category ON public.map_places(category_id);
CREATE INDEX idx_map_places_geo_hash ON public.map_places(geo_hash);
CREATE INDEX idx_map_places_lat_lng ON public.map_places(lat, lng);
CREATE INDEX idx_map_reports_place ON public.map_reports(place_id);
CREATE INDEX idx_map_reports_status ON public.map_reports(status);
CREATE INDEX idx_map_favorites_user ON public.map_favorites(user_id);
CREATE INDEX idx_map_favorites_place ON public.map_favorites(place_id);

-- 4. Functions

-- Function to check if user is admin
CREATE OR REPLACE FUNCTION public.is_admin_from_auth()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
SELECT EXISTS (
    SELECT 1 FROM public.user_profiles up
    WHERE up.id = auth.uid() AND up.is_admin = true
)
$$;

-- Function to get places within bounding box
CREATE OR REPLACE FUNCTION public.get_places_in_bbox(
    min_lat DECIMAL,
    min_lng DECIMAL,
    max_lat DECIMAL,
    max_lng DECIMAL,
    filter_category UUID DEFAULT NULL,
    filter_type public.place_type DEFAULT NULL,
    search_text TEXT DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    owner_user_id UUID,
    place_type public.place_type,
    title TEXT,
    description TEXT,
    category_id UUID,
    tags TEXT[],
    lat DECIMAL,
    lng DECIMAL,
    address_text TEXT,
    country TEXT,
    city TEXT,
    contact JSONB,
    images TEXT[],
    visibility public.place_visibility,
    status public.place_status,
    created_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $func$
BEGIN
    RETURN QUERY
    SELECT 
        mp.id,
        mp.owner_user_id,
        mp.place_type,
        mp.title,
        mp.description,
        mp.category_id,
        mp.tags,
        mp.lat,
        mp.lng,
        mp.address_text,
        mp.country,
        mp.city,
        mp.contact,
        mp.images,
        mp.visibility,
        mp.status,
        mp.created_at,
        mp.updated_at
    FROM public.map_places mp
    WHERE mp.status = 'approved'
      AND mp.lat >= min_lat
      AND mp.lat <= max_lat
      AND mp.lng >= min_lng
      AND mp.lng <= max_lng
      AND (filter_category IS NULL OR mp.category_id = filter_category)
      AND (filter_type IS NULL OR mp.place_type = filter_type)
      AND (search_text IS NULL OR mp.title ILIKE '%' || search_text || '%' 
           OR mp.description ILIKE '%' || search_text || '%')
    ORDER BY mp.created_at DESC
    LIMIT 100;
END;
$func$;

-- Function to handle new user profile creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
SECURITY DEFINER
LANGUAGE plpgsql
AS $trigger$
BEGIN
    INSERT INTO public.user_profiles (id, email, full_name, avatar_url, is_admin)
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
        COALESCE((NEW.raw_user_meta_data->>'is_admin')::boolean, false)
    );
    RETURN NEW;
END;
$trigger$;

-- 5. Enable RLS
ALTER TABLE public.map_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.map_places ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.map_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.map_favorites ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies

-- Map Categories: Public read, admin write
CREATE POLICY "public_can_read_map_categories"
ON public.map_categories
FOR SELECT
TO public
USING (enabled = true);

CREATE POLICY "admin_can_manage_map_categories"
ON public.map_categories
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

-- User Profiles: Users manage own profile
CREATE POLICY "users_manage_own_user_profiles"
ON public.user_profiles
FOR ALL
TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Map Places: Public read approved, users manage own
CREATE POLICY "public_can_read_approved_map_places"
ON public.map_places
FOR SELECT
TO public
USING (status = 'approved' AND visibility = 'public');

CREATE POLICY "users_can_create_map_places"
ON public.map_places
FOR INSERT
TO authenticated
WITH CHECK (owner_user_id = auth.uid());

CREATE POLICY "users_can_update_own_map_places"
ON public.map_places
FOR UPDATE
TO authenticated
USING (owner_user_id = auth.uid())
WITH CHECK (owner_user_id = auth.uid());

CREATE POLICY "users_can_delete_own_map_places"
ON public.map_places
FOR DELETE
TO authenticated
USING (owner_user_id = auth.uid());

CREATE POLICY "admin_can_manage_all_map_places"
ON public.map_places
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

-- Map Reports: Users manage own, admin can view all
CREATE POLICY "users_can_create_map_reports"
ON public.map_reports
FOR INSERT
TO authenticated
WITH CHECK (reported_by_user_id = auth.uid());

CREATE POLICY "users_can_view_own_map_reports"
ON public.map_reports
FOR SELECT
TO authenticated
USING (reported_by_user_id = auth.uid());

CREATE POLICY "admin_can_manage_map_reports"
ON public.map_reports
FOR ALL
TO authenticated
USING (public.is_admin_from_auth())
WITH CHECK (public.is_admin_from_auth());

-- Map Favorites: Users manage own
CREATE POLICY "users_manage_own_map_favorites"
ON public.map_favorites
FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- 7. Triggers
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_user();

-- 8. Mock Data
DO $$
DECLARE
    admin_uuid UUID := gen_random_uuid();
    user_uuid UUID := gen_random_uuid();
    category1_uuid UUID := gen_random_uuid();
    category2_uuid UUID := gen_random_uuid();
    place1_uuid UUID := gen_random_uuid();
    place2_uuid UUID := gen_random_uuid();
BEGIN
    -- Create auth users
    INSERT INTO auth.users (
        id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
        created_at, updated_at, raw_user_meta_data, raw_app_meta_data,
        is_sso_user, is_anonymous, confirmation_token, confirmation_sent_at,
        recovery_token, recovery_sent_at, email_change_token_new, email_change,
        email_change_sent_at, email_change_token_current, email_change_confirm_status,
        reauthentication_token, reauthentication_sent_at, phone, phone_change,
        phone_change_token, phone_change_sent_at
    ) VALUES
        (admin_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'admin@navapeace.com', crypt('admin123', gen_salt('bf', 10)), now(), now(), now(),
         '{"full_name": "Admin User", "is_admin": true}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb,
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null),
        (user_uuid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
         'user@navapeace.com', crypt('user123', gen_salt('bf', 10)), now(), now(), now(),
         '{"full_name": "Regular User", "is_admin": false}'::jsonb, '{"provider": "email", "providers": ["email"]}'::jsonb,
         false, false, '', null, '', null, '', '', null, '', 0, '', null, null, '', '', null);

    -- Create categories
    INSERT INTO public.map_categories (id, name, icon, enabled) VALUES
        (category1_uuid, 'Community Center', 'community', true),
        (category2_uuid, 'Peace Initiative', 'peace', true),
        (gen_random_uuid(), 'Business', 'business', true),
        (gen_random_uuid(), 'Event Space', 'event', true);

    -- Create places
    INSERT INTO public.map_places (
        id, owner_user_id, place_type, title, description, category_id,
        tags, lat, lng, address_text, city, country, contact, images, status
    ) VALUES
        (place1_uuid, admin_uuid, 'community', 'NAVA Peace Center',
         'Central hub for peace initiatives and community engagement',
         category1_uuid, ARRAY['peace', 'community', 'education'],
         40.7580, -73.9855, '123 Peace Street', 'New York', 'USA',
         '{"phone": "+1-555-0123", "website": "https://navapeace.org", "instagram": "@navapeace"}'::jsonb,
         ARRAY['https://images.pexels.com/photos/3184291/pexels-photo-3184291.jpeg'],
         'approved'),
        (place2_uuid, user_uuid, 'event', 'Unity Festival 2026',
         'Annual celebration of diversity and peace',
         category2_uuid, ARRAY['festival', 'peace', 'unity'],
         40.7489, -73.9680, '456 Unity Plaza', 'New York', 'USA',
         '{"phone": "+1-555-0456", "website": "https://unityfest.org"}'::jsonb,
         ARRAY['https://images.pexels.com/photos/1190297/pexels-photo-1190297.jpeg'],
         'approved');

    -- Create favorites
    INSERT INTO public.map_favorites (user_id, place_id) VALUES
        (user_uuid, place1_uuid);
END $$;