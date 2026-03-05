defmodule TechTree.Repo.Migrations.AddSearchTriggers do
  use Ecto.Migration

  def up do
    execute("""
    CREATE OR REPLACE FUNCTION nodes_search_document_trigger() RETURNS trigger AS $$
    BEGIN
      NEW.search_document :=
        setweight(to_tsvector('english', coalesce(NEW.title, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.summary, '')), 'B') ||
        setweight(to_tsvector('english', coalesce(NEW.skill_slug, '')), 'A') ||
        setweight(to_tsvector('english', coalesce(NEW.seed, '')), 'C');
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER nodes_search_document_update
      BEFORE INSERT OR UPDATE OF title, summary, skill_slug, seed
      ON nodes
      FOR EACH ROW
      EXECUTE FUNCTION nodes_search_document_trigger();
    """)

    execute("""
    CREATE OR REPLACE FUNCTION comments_search_document_trigger() RETURNS trigger AS $$
    BEGIN
      NEW.search_document := to_tsvector('english', coalesce(NEW.body_plaintext, ''));
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """)

    execute("""
    CREATE TRIGGER comments_search_document_update
      BEFORE INSERT OR UPDATE OF body_plaintext
      ON comments
      FOR EACH ROW
      EXECUTE FUNCTION comments_search_document_trigger();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS nodes_search_document_update ON nodes")
    execute("DROP FUNCTION IF EXISTS nodes_search_document_trigger()")
    execute("DROP TRIGGER IF EXISTS comments_search_document_update ON comments")
    execute("DROP FUNCTION IF EXISTS comments_search_document_trigger()")
  end
end
