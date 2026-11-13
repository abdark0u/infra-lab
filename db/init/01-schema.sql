-- Se ejecuta solo la primera vez que arranca PostgreSQL (volumen vacio).
CREATE TABLE IF NOT EXISTS visits (
    id         BIGSERIAL PRIMARY KEY,
    visited_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
