-- ============================================================
-- GROUNDWORK — MATERIAL EDITABILITY
-- Prices become editable AVERAGE seeds (not pinned SKUs), links
-- optional, and every line item gains an editable description.
--
-- Two-layer model:
--   materials       = master catalog (average default + description)
--   estimate_items  = per-estimate editable copy (name/qty/price/description)
--
-- Idempotent. Run in the Supabase SQL editor anytime after the catalog.
-- ============================================================

-- Catalog: average prices (not pinned SKUs) + description + optional link
alter table materials add column if not exists description text;
alter table materials add column if not exists price_low  numeric;
alter table materials add column if not exists price_high numeric;
alter table materials alter column supplier_url drop not null;

comment on column materials.unit_price   is 'Typical/average each-price (editable default). Not a pinned SKU price.';
comment on column materials.supplier_url is 'Optional reference link only.';
comment on column materials.price_low    is 'Optional low end of typical price range (edit UI).';
comment on column materials.price_high   is 'Optional high end of typical price range (edit UI).';

-- Estimate line items: the editable layer. Add description so edits persist.
-- (name, quantity, unit_price, total already exist and are per-estimate editable)
alter table estimate_items add column if not exists description text;
