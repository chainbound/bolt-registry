-- postgres database schema

-- Create the source_enum type if it does not exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'source_enum') THEN
        CREATE TYPE source_enum AS ENUM ('lido', 'none');
    END IF;
END $$;

-- Create the protocol_enum type if it does not exist
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'protocol_enum') THEN
        CREATE TYPE protocol_enum AS ENUM ('lido', 'none');
    END IF;
END $$;

-- Create the operators table if it does not exist
CREATE TABLE IF NOT EXISTS operators (
    signer BYTEA PRIMARY KEY,             -- Unique identifier for the operator
    rpc TEXT NOT NULL,                    -- RPC endpoint
    protocol protocol_enum,               -- Protocol type (optional)
    source source_enum NOT NULL,          -- Source of the operator data
    collateral_tokens BYTEA[] NOT NULL,   -- Array of collateral token identifiers
    collateral_amounts BYTEA[] NOT NULL,  -- Array of collateral token amounts
    last_update TIMESTAMP NOT NULL        -- Last time this record was updated
);

-- Create the validator_registrations table if it does not exist
CREATE TABLE IF NOT EXISTS validator_registrations (
    pubkey BYTEA PRIMARY KEY,                              -- BLS public key of the validator
    signature BYTEA NOT NULL,                              -- Signature of the registration
    expiry BIGINT NOT NULL,                                -- Expiry timestamp of the registration
    gas_limit BIGINT NOT NULL,                             -- Gas limit for the validator
    operator BYTEA NOT NULL REFERENCES operators(signer),  -- Operator address (foreign key)
    priority SMALLINT NOT NULL,                            -- Priority level of this registration
    source source_enum NOT NULL,                           -- Source of the registration data
    last_update TIMESTAMP NOT NULL                         -- Last time this record was updated
);
