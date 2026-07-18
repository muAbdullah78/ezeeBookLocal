/// SQL commands to run in Supabase SQL Editor.
/// Copy-paste each block into the Supabase dashboard → SQL Editor → Run.
class SubscriptionSQL {
  SubscriptionSQL._();

  static const String createTables = '''
-- =============================================
-- EZEEBOOK SUBSCRIPTION TABLES
-- Run this in Supabase SQL Editor
-- =============================================

-- 1. Subscription plans (pre-populated, read-only for users)
CREATE TABLE subscription_plans (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  duration_months INTEGER NOT NULL,
  price_pkr REAL NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true
);

-- Insert the 3 plans
INSERT INTO subscription_plans (id, name, duration_months, price_pkr, is_active) VALUES
('monthly', 'Monthly', 1, 950, true),
('quarterly', '3 Months', 3, 2500, true),
('yearly', 'Yearly', 12, 9000, true);

-- Allow all authenticated users to read plans
ALTER TABLE subscription_plans ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read plans" ON subscription_plans FOR SELECT USING (true);

-- 2. User subscriptions
CREATE TABLE user_subscriptions (
  id TEXT PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  start_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  end_date TIMESTAMPTZ NOT NULL,
  payment_method TEXT DEFAULT 'manual',
  promo_code_used TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can read own subscription" ON user_subscriptions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own subscription" ON user_subscriptions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own subscription" ON user_subscriptions FOR UPDATE USING (auth.uid() = user_id);

-- 3. Promo codes
CREATE TABLE promo_codes (
  id TEXT PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  discount_percent INTEGER NOT NULL DEFAULT 0,
  discount_amount_pkr REAL NOT NULL DEFAULT 0,
  valid_from TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  valid_until TIMESTAMPTZ NOT NULL,
  max_uses INTEGER NOT NULL DEFAULT 100,
  current_uses INTEGER NOT NULL DEFAULT 0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  applicable_plans TEXT DEFAULT 'all'
);

-- All users can read active promo codes (to validate codes)
-- Only admin can insert/update — done via Supabase dashboard manually
ALTER TABLE promo_codes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read active promo codes" ON promo_codes FOR SELECT USING (is_active = true);
''';
}
