CREATE UNIQUE INDEX IF NOT EXISTS accounts_account_token ON accounts (account_token) WHERE account_token IS NOT NULL
CREATE UNIQUE INDEX IF NOT EXISTS accounts_referral_code ON accounts (referral_code) WHERE referral_code IS NOT NULL
CREATE INDEX IF NOT EXISTS accounts_app_transaction ON accounts (app_transaction_id)
