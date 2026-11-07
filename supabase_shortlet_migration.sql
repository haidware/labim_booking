CREATE TABLE IF NOT EXISTS public.shortlet_listings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug text NOT NULL UNIQUE,
    title text NOT NULL,
    description text NOT NULL DEFAULT '',
    address text NOT NULL DEFAULT '',
    city text NOT NULL,
    state text NOT NULL,
    property_type text NOT NULL DEFAULT 'Shortlet apartment',
    bedrooms integer NOT NULL DEFAULT 1 CHECK (bedrooms >= 0),
    bathrooms integer NOT NULL DEFAULT 1 CHECK (bathrooms >= 0),
    nightly_rate bigint NOT NULL CHECK (nightly_rate > 0),
    manager_whatsapp text NOT NULL,
    photo_urls jsonb NOT NULL DEFAULT '[]'::jsonb
        CHECK (jsonb_typeof(photo_urls) = 'array'),
    status text NOT NULL DEFAULT 'draft'
        CHECK (status IN ('draft', 'published', 'archived')),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS shortlet_listings_public_search_idx
    ON public.shortlet_listings (status, state, city, nightly_rate);

ALTER TABLE public.shortlet_listings ENABLE ROW LEVEL SECURITY;

GRANT SELECT ON public.shortlet_listings TO anon, authenticated;

DROP POLICY IF EXISTS "Guests can view published shortlets"
    ON public.shortlet_listings;
CREATE POLICY "Guests can view published shortlets"
    ON public.shortlet_listings
    FOR SELECT
    TO anon, authenticated
    USING (status = 'published');
