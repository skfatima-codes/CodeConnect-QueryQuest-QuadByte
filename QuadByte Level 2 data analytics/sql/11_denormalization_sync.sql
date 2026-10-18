-- ============================================================================
-- PROJECT: "You Hungry" Multi-City Food Delivery Platform
-- FILE: sql/11_denormalization_sync.sql
-- DIALECT: PostgreSQL 15+ / ANSI SQL Compliant
-- DESCRIPTION: Controlled denormalization: Schema DDL, trigger sync, & reconciliation.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SCHEMA MODIFICATION (ALTER TABLE)
-- Add denormalized rating aggregates directly to the Restaurant entity.
-- ----------------------------------------------------------------------------
ALTER TABLE Restaurant 
    ADD COLUMN IF NOT EXISTS avg_rating DECIMAL(3, 2) NOT NULL DEFAULT 0.00,
    ADD COLUMN IF NOT EXISTS total_reviews INT NOT NULL DEFAULT 0;

-- Domain constraints
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_restaurant_avg_rating') THEN
        ALTER TABLE Restaurant ADD CONSTRAINT chk_restaurant_avg_rating CHECK (avg_rating >= 0.00 AND avg_rating <= 5.00);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_restaurant_total_reviews') THEN
        ALTER TABLE Restaurant ADD CONSTRAINT chk_restaurant_total_reviews CHECK (total_reviews >= 0);
    END IF;
END
$$;

-- Composite B-Tree index for instantaneous merchant search and catalog ranking
CREATE INDEX IF NOT EXISTS idx_restaurant_rating_reviews 
    ON Restaurant (avg_rating DESC, total_reviews DESC);


-- ----------------------------------------------------------------------------
-- 2. HISTORICAL DATA BACKFILL
-- Populates aggregates from existing verified review records.
-- ----------------------------------------------------------------------------
UPDATE Restaurant r
SET 
    total_reviews = COALESCE(sub.review_count, 0),
    avg_rating    = COALESCE(ROUND(sub.calculated_avg, 2), 0.00)
FROM (
    SELECT 
        restaurant_id,
        COUNT(rating_id) AS review_count,
        AVG(score) AS calculated_avg
    FROM RestaurantRating
    WHERE score IS NOT NULL
    GROUP BY restaurant_id
) AS sub
WHERE r.restaurant_id = sub.restaurant_id;


-- ----------------------------------------------------------------------------
-- 3. REAL-TIME SYNCHRONIZATION TRIGGER FUNCTION
-- Maintains running average via O(1) incremental arithmetic:
-- New_Avg = ((Old_Avg * Count) + New_Score) / (Count + 1)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_SyncRestaurantRatings()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE Restaurant
        SET 
            avg_rating = ROUND(((avg_rating * total_reviews) + NEW.score) / (total_reviews + 1), 2),
            total_reviews = total_reviews + 1
        WHERE restaurant_id = NEW.restaurant_id;
        RETURN NEW;

    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.score != NEW.score THEN
            UPDATE Restaurant
            SET 
                avg_rating = ROUND(((avg_rating * total_reviews) - OLD.score + NEW.score) / NULLIF(total_reviews, 0), 2)
            WHERE restaurant_id = NEW.restaurant_id;
        END IF;
        RETURN NEW;

    ELSIF TG_OP = 'DELETE' THEN
        UPDATE Restaurant
        SET 
            avg_rating = CASE 
                WHEN total_reviews <= 1 THEN 0.00
                ELSE ROUND(((avg_rating * total_reviews) - OLD.score) / (total_reviews - 1), 2)
            END,
            total_reviews = GREATEST(0, total_reviews - 1)
        WHERE restaurant_id = OLD.restaurant_id;
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_SyncRestaurantRatings ON RestaurantRating;

CREATE TRIGGER trg_SyncRestaurantRatings
AFTER INSERT OR UPDATE OR DELETE ON RestaurantRating
FOR EACH ROW
EXECUTE FUNCTION fn_SyncRestaurantRatings();


-- ----------------------------------------------------------------------------
-- 4. SCHEDULED RECONCILIATION PROCEDURE (NIGHTLY DRIFT CORRECTION)
-- Corrects any potential floating-point accumulation error.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ReconcileRestaurantRatings()
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE Restaurant r
    SET 
        total_reviews = COALESCE(agg.cnt, 0),
        avg_rating    = COALESCE(ROUND(agg.avg_score, 2), 0.00)
    FROM (
        SELECT 
            restaurant_id, 
            COUNT(rating_id) AS cnt, 
            AVG(score) AS avg_score 
        FROM RestaurantRating 
        GROUP BY restaurant_id
    ) AS agg
    WHERE r.restaurant_id = agg.restaurant_id
      AND (r.total_reviews != agg.cnt OR r.avg_rating != ROUND(agg.avg_score, 2));

    RAISE NOTICE 'Restaurant rating denormalization reconciliation finished successfully.';
END;
$$;
