-- Solo se ejecuta la primera vez que arranca PostgreSQL, con el volumen vacío.
-- Si el volumen ya tiene datos, el contenedor se lo salta.
CREATE TABLE IF NOT EXISTS visits (
    id         BIGSERIAL PRIMARY KEY,
    visited_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
