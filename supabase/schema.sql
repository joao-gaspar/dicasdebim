-- =============================================
-- Schema Supabase: dicasdebim
-- Migração do WordPress para PostgreSQL
-- =============================================

-- Extensões necessárias
CREATE EXTENSION IF NOT EXISTS "unaccent";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- =============================================
-- TABELA: authors
-- Migrado de: wp_users + wp_usermeta
-- =============================================
CREATE TABLE IF NOT EXISTS authors (
  id         SERIAL PRIMARY KEY,
  wp_id      INTEGER,           -- ID original do WordPress (para migração)
  name       TEXT NOT NULL,
  email      TEXT UNIQUE NOT NULL,
  avatar_url TEXT,
  bio        TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- TABELA: categories
-- Migrado de: wp_terms + wp_term_taxonomy (taxonomy='category')
-- =============================================
CREATE TABLE IF NOT EXISTS categories (
  id          SERIAL PRIMARY KEY,
  wp_id       INTEGER,
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL UNIQUE,
  description TEXT,
  parent_id   INTEGER REFERENCES categories(id),
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- TABELA: tags
-- Migrado de: wp_terms + wp_term_taxonomy (taxonomy='post_tag')
-- =============================================
CREATE TABLE IF NOT EXISTS tags (
  id   SERIAL PRIMARY KEY,
  wp_id INTEGER,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE
);

-- =============================================
-- TABELA: posts
-- Migrado de: wp_posts (post_type='post', post_status='publish')
-- =============================================
CREATE TABLE IF NOT EXISTS posts (
  id           SERIAL PRIMARY KEY,
  wp_id        INTEGER,           -- ID original do WordPress
  title        TEXT NOT NULL,
  slug         TEXT NOT NULL UNIQUE,
  excerpt      TEXT,
  content      TEXT NOT NULL,
  cover_image  TEXT,             -- URL no Supabase Storage ou URL externa
  author_id    INTEGER REFERENCES authors(id),
  category_id  INTEGER REFERENCES categories(id),
  status       TEXT DEFAULT 'published' CHECK (status IN ('draft', 'published', 'archived')),
  published_at TIMESTAMPTZ,
  updated_at   TIMESTAMPTZ DEFAULT NOW(),
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  -- Full-text search
  search_vector TSVECTOR GENERATED ALWAYS AS (
    setweight(to_tsvector('portuguese', coalesce(title, '')), 'A') ||
    setweight(to_tsvector('portuguese', coalesce(excerpt, '')), 'B') ||
    setweight(to_tsvector('portuguese', coalesce(content, '')), 'C')
  ) STORED
);

-- =============================================
-- TABELA: post_tags (relação N:N)
-- =============================================
CREATE TABLE IF NOT EXISTS post_tags (
  post_id INTEGER REFERENCES posts(id) ON DELETE CASCADE,
  tag_id  INTEGER REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (post_id, tag_id)
);

-- =============================================
-- TABELA: media
-- Migrado de: wp-content/uploads → Supabase Storage
-- =============================================
CREATE TABLE IF NOT EXISTS media (
  id          SERIAL PRIMARY KEY,
  wp_id       INTEGER,
  filename    TEXT NOT NULL,
  url         TEXT NOT NULL,
  alt_text    TEXT,
  mime_type   TEXT,
  size_bytes  BIGINT,
  post_id     INTEGER REFERENCES posts(id),
  uploaded_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- INDEXES
-- =============================================
CREATE INDEX IF NOT EXISTS posts_slug_idx ON posts(slug);
CREATE INDEX IF NOT EXISTS posts_category_idx ON posts(category_id);
CREATE INDEX IF NOT EXISTS posts_author_idx ON posts(author_id);
CREATE INDEX IF NOT EXISTS posts_status_idx ON posts(status);
CREATE INDEX IF NOT EXISTS posts_published_at_idx ON posts(published_at DESC);
CREATE INDEX IF NOT EXISTS posts_search_idx ON posts USING GIN(search_vector);
CREATE INDEX IF NOT EXISTS categories_slug_idx ON categories(slug);
CREATE INDEX IF NOT EXISTS tags_slug_idx ON tags(slug);

-- =============================================
-- ROW LEVEL SECURITY (RLS)
-- =============================================
ALTER TABLE posts      ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE authors    ENABLE ROW LEVEL SECURITY;
ALTER TABLE tags       ENABLE ROW LEVEL SECURITY;
ALTER TABLE media      ENABLE ROW LEVEL SECURITY;

-- Leitura pública de posts publicados
CREATE POLICY "Posts publicos visíveis" ON posts
  FOR SELECT USING (status = 'published');

CREATE POLICY "Categorias visíveis" ON categories
  FOR SELECT USING (true);

CREATE POLICY "Tags visíveis" ON tags
  FOR SELECT USING (true);

CREATE POLICY "Autores visíveis" ON authors
  FOR SELECT USING (true);

CREATE POLICY "Media visível" ON media
  FOR SELECT USING (true);

-- Admin pode fazer tudo (usando service role ou auth.uid check)
CREATE POLICY "Admin gerencia posts" ON posts
  FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Admin gerencia categorias" ON categories
  FOR ALL USING (auth.role() = 'service_role');

CREATE POLICY "Admin gerencia autores" ON authors
  FOR ALL USING (auth.role() = 'service_role');

-- =============================================
-- VIEW: posts_with_details (join conveniente)
-- =============================================
CREATE OR REPLACE VIEW posts_with_details AS
SELECT
  p.*,
  a.name    AS author_name,
  a.avatar_url AS author_avatar,
  c.name    AS category_name,
  c.slug    AS category_slug
FROM posts p
LEFT JOIN authors a ON p.author_id = a.id
LEFT JOIN categories c ON p.category_id = c.id
WHERE p.status = 'published'
ORDER BY p.published_at DESC;

-- =============================================
-- DADOS INICIAIS (seed)
-- =============================================
INSERT INTO categories (name, slug, description) VALUES
  ('BIM', 'bim', 'Conteúdo sobre Building Information Modeling'),
  ('Revit', 'revit', 'Dicas e tutoriais sobre Autodesk Revit'),
  ('ArchiCAD', 'archicad', 'Conteúdo sobre GRAPHISOFT ArchiCAD'),
  ('IFC', 'ifc', 'Industry Foundation Classes - padrão aberto BIM'),
  ('Coordenação', 'coordenacao', 'Coordenação e compatibilização de projetos')
ON CONFLICT (slug) DO NOTHING;
