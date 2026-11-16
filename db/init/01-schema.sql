-- Solo se ejecuta la primera vez, con el volumen vacío.
CREATE TABLE IF NOT EXISTS visits (
    id         BIGSERIAL PRIMARY KEY,
    visited_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
