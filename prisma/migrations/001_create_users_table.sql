-- Migration: 001_create_users_table
-- Description: Create users table for authentication
-- Date: 2026-02-01

-- Create role enum type
DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('ADMIN', 'USER', 'VIEWER');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

-- Create users table
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email VARCHAR(255) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL,
  first_name VARCHAR(255),
  last_name VARCHAR(255),
  role user_role NOT NULL DEFAULT 'USER',
  is_active BOOLEAN NOT NULL DEFAULT true,
  refresh_token TEXT,
  created_at TIMESTAMP(6) NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP(6) NOT NULL DEFAULT NOW()
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_email ON public.users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON public.users(role);
CREATE INDEX IF NOT EXISTS idx_users_is_active ON public.users(is_active);

-- Add comment to table
COMMENT ON TABLE public.users IS 'Application users for authentication and authorization';

-- Create trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_users_updated_at ON public.users;
CREATE TRIGGER update_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Insert default admin user
INSERT INTO public.users (email, password, first_name, last_name, role, is_active)
VALUES (
  'admin@ex.com',
  '$2b$10$FjTHBw.rR63TM6gq9xIp4uJaYW6zCY25f9ObGY7bnLiKKQ3B7/rCy',
  'admin',
  'admin',
  'ADMIN',
  true
)
ON CONFLICT (email) DO NOTHING;
