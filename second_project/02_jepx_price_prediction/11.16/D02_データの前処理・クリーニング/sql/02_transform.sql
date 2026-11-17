-- =====================================================================
-- 02_transform.sql  |  ステージングテーブル → 30分単位の分析テーブル（fact_30min）
-- 手順: ① 基準枠の作成 → ② 時刻の整合 → ③ 欠損値処理 → ④ データ結合
--       → ⑤ 特徴量（X、データリーク防止）→ ⑥ 目的変数（y）→ ⑦ 対象期間・データ分割
-- 時間枠番号（slot）: 1 = 0:00～0:30 … 48 = 23:30～24:00
-- MySQL 8.0以降（WITH RECURSIVE、ウィンドウ関数）
-- =====================================================================
USE jepx;
SET SESSION cte_max_recursion_depth = 5000;

-- ---------------------------------------------------------------------
-- ① 基準枠の作成: 日付 × 48枠
--    分析開始日（2024-04-01）の40日前から作成 → 30日平均・前週の値を算出するための余裕期間
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS dim_day;
CREATE TABLE dim_day (date DATE PRIMARY KEY);
INSERT INTO dim_day (date)
WITH RECURSIVE d AS (
    SELECT DATE('2024-02-21') AS date
    UNION ALL
    SELECT DATE_ADD(date, INTERVAL 1 DAY) FROM d WHERE date < '2026-10-31'
)
SELECT date FROM d;

DROP TABLE IF EXISTS dim_slot;
CREATE TABLE dim_slot (slot INT PRIMARY KEY);
INSERT INTO dim_slot (slot)
WITH RECURSIVE s AS (
    SELECT 1 AS slot
    UNION ALL
    SELECT slot + 1 FROM s WHERE slot < 48
)
SELECT slot FROM s;

-- ---------------------------------------------------------------------
-- ② 時刻の整合: データごとに異なる時刻表記を（date, slot）に統一
-- ---------------------------------------------------------------------
-- 東京電力: TIME = 枠の開始時刻 → 時×2 + 分/30 + 1（00:00 → 1、23:30 → 48）
DROP TABLE IF EXISTS t_tepco;
CREATE TABLE t_tepco AS
SELECT CAST(date AS DATE) AS date,
       CAST(SUBSTR(time_hhmm, 1, 2) AS UNSIGNED) * 2 + CAST(SUBSTR(time_hhmm, 4, 2) AS UNSIGNED) DIV 30 + 1 AS slot,
       demand_mw, nuclear_mw, lng_mw, coal_mw, oil_mw, thermal_other_mw, hydro_mw, biomass_mw,
       solar_mw, solar_curtail_mw, wind_mw, wind_curtail_mw, pumped_mw, battery_mw,
       interconnect_mw, other_mw
FROM stg_tepco;
CREATE INDEX ix_t_tepco ON t_tepco (date, slot);

-- OCCTO: 時刻 = 枠の終了時刻 → 時×2 + 分/30（00:30 → 1、24:00 → 48）、東京のみ
DROP TABLE IF EXISTS t_occto;
CREATE TABLE t_occto AS
SELECT CAST(date AS DATE) AS date,
       CAST(SUBSTR(time_end, 1, 2) AS UNSIGNED) * 2 + CAST(SUBSTR(time_end, 4, 2) AS UNSIGNED) DIV 30 AS slot,
       reserve_rate                          AS occto_reserve_rate,
       area_demand_fc                        AS occto_area_demand_fc,
       area_supply_fc                        AS occto_area_supply_fc,
       area_reserve_mw                       AS occto_area_reserve_mw,
       area_reserve_mw / area_demand_fc * 100 AS occto_area_reserve_rate
FROM stg_occto
WHERE area_name = '東京';
CREATE INDEX ix_t_occto ON t_occto (date, slot);

-- 気象データ: まず時間単位で欠損値を補間（前後1時間の平均）
DROP TABLE IF EXISTS t_weather_h;
CREATE TABLE t_weather_h AS
SELECT obs_time,
       COALESCE(temp_c,       (LAG(temp_c)       OVER w + LEAD(temp_c)       OVER w) / 2) AS temp_c,
       COALESCE(humidity,     (LAG(humidity)     OVER w + LEAD(humidity)     OVER w) / 2) AS humidity,
       COALESCE(solar_rad_mj, (LAG(solar_rad_mj) OVER w + LEAD(solar_rad_mj) OVER w) / 2) AS solar_rad_mj,
       COALESCE(sunshine_h,   (LAG(sunshine_h)   OVER w + LEAD(sunshine_h)   OVER w) / 2) AS sunshine_h,
       COALESCE(rain_mm,      (LAG(rain_mm)      OVER w + LEAD(rain_mm)      OVER w) / 2) AS rain_mm
FROM stg_weather
WINDOW w AS (ORDER BY obs_time);

-- 気温・湿度 = その時刻の瞬間値 → その時刻から始まる30分枠2つにそのまま割り当てる
DROP TABLE IF EXISTS t_weather_inst;
CREATE TABLE t_weather_inst AS
SELECT CAST(DATE(h.obs_time) AS DATE)                AS date,
       CAST(HOUR(h.obs_time) * 2 + 1 + k.k AS UNSIGNED) AS slot,
       h.temp_c, h.humidity
FROM t_weather_h h
CROSS JOIN (SELECT 0 AS k UNION ALL SELECT 1) k;
CREATE INDEX ix_t_w_inst ON t_weather_inst (date, slot);

-- 日射量・日照時間・降水量 = 前1時間（直前1時間の集計）→ 1時間前にずらして2枠に割り当て、積算量は半分ずつに分ける
DROP TABLE IF EXISTS t_weather_acc;
CREATE TABLE t_weather_acc AS
SELECT CAST(DATE(DATE_SUB(h.obs_time, INTERVAL 1 HOUR)) AS DATE)                AS date,
       CAST(HOUR(DATE_SUB(h.obs_time, INTERVAL 1 HOUR)) * 2 + 1 + k.k AS UNSIGNED) AS slot,
       h.solar_rad_mj / 2 AS solar_rad_mj,
       h.sunshine_h       AS sunshine_h,     -- 比率（0～1）のため2分割しない
       h.rain_mm / 2      AS rain_mm
FROM t_weather_h h
CROSS JOIN (SELECT 0 AS k UNION ALL SELECT 1) k;
CREATE INDEX ix_t_w_acc ON t_weather_acc (date, slot);

-- LNG: トン当たり単価 = 金額（千円）× 1000 / 数量（トン）
DROP TABLE IF EXISTS t_lng;
CREATE TABLE t_lng AS
SELECT month_idx, value_kyen * 1000 / qty_t AS lng_yen_per_t
FROM stg_lng;

-- ---------------------------------------------------------------------
-- ③④ データ結合: 基準枠にLEFT JOIN（欠落した枠はNULLとして判別できる）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS t_base;
CREATE TABLE t_base AS
SELECT d.date, s.slot,
       j.price_tokyo, j.price_system, j.sell_bid_kwh, j.buy_bid_kwh, j.contract_kwh,
       tp.demand_mw, tp.nuclear_mw, tp.lng_mw, tp.coal_mw, tp.oil_mw, tp.thermal_other_mw,
       tp.hydro_mw, tp.biomass_mw, tp.solar_mw, tp.solar_curtail_mw, tp.wind_mw,
       tp.wind_curtail_mw, tp.pumped_mw, tp.battery_mw, tp.interconnect_mw, tp.other_mw,
       wi.temp_c, wi.humidity, wa.solar_rad_mj, wa.sunshine_h, wa.rain_mm,
       o.occto_reserve_rate, o.occto_area_demand_fc, o.occto_area_supply_fc,
       o.occto_area_reserve_mw, o.occto_area_reserve_rate,
       l1.lng_yen_per_t AS lng_yen_per_t_m1,   -- 1か月前（参考用: 月末以降でなければ把握できない）
       l2.lng_yen_per_t AS lng_yen_per_t_m2    -- 2か月前（モデル用: データリークなし）
FROM dim_day d
CROSS JOIN dim_slot s
LEFT JOIN stg_jepx       j  ON j.date  = d.date AND j.slot  = s.slot
LEFT JOIN t_tepco        tp ON tp.date = d.date AND tp.slot = s.slot
LEFT JOIN t_weather_inst wi ON wi.date = d.date AND wi.slot = s.slot
LEFT JOIN t_weather_acc  wa ON wa.date = d.date AND wa.slot = s.slot
LEFT JOIN t_occto        o  ON o.date  = d.date AND o.slot  = s.slot
LEFT JOIN t_lng          l1 ON l1.month_idx = YEAR(d.date) * 12 + MONTH(d.date) - 1
LEFT JOIN t_lng          l2 ON l2.month_idx = YEAR(d.date) * 12 + MONTH(d.date) - 2;
CREATE INDEX ix_t_base ON t_base (date, slot);

-- 日別平均価格 → 前日までの7日・30日平均（必要な日数がそろわなければNULL）
DROP TABLE IF EXISTS t_daily_price;
CREATE TABLE t_daily_price AS
SELECT date,
       CASE WHEN COUNT(p) OVER w7  = 7  THEN AVG(p) OVER w7  END AS price_tokyo_mean7d,
       CASE WHEN COUNT(p) OVER w30 = 30 THEN AVG(p) OVER w30 END AS price_tokyo_mean30d
FROM (SELECT date, AVG(price_tokyo) AS p FROM t_base GROUP BY date) dp
WINDOW w7  AS (ORDER BY date ROWS BETWEEN 7  PRECEDING AND 1 PRECEDING),
       w30 AS (ORDER BY date ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING);
CREATE INDEX ix_t_daily ON t_daily_price (date);

-- ---------------------------------------------------------------------
-- ⑤⑥⑦ 最終分析テーブル
--   X: 実績データは前日（48枠前）・前週（336枠前）の値のみ使用 → データリークを防止
--   y: y_price（回帰）、y_spike_rel（分類: 30日平均の1.5倍以上）
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS fact_30min;
CREATE TABLE fact_30min AS
SELECT x.*,
        -- 冷暖房負荷の指標（気温を補完してから計算）
       CASE WHEN x.temp_c > 22 THEN x.temp_c - 22 ELSE 0 END AS cooling_deg,
       CASE WHEN x.temp_c < 14 THEN 14 - x.temp_c ELSE 0 END AS heating_deg
FROM (
    SELECT
        b.date, b.slot,
        -- 気象データ（完全な天気予報が得られると仮定）。対象期間の初日0時台の2枠は後続の値で補完
        COALESCE(b.temp_c,   LEAD(b.temp_c, 1)   OVER o, LEAD(b.temp_c, 2)   OVER o) AS temp_c,
        COALESCE(b.humidity, LEAD(b.humidity, 1) OVER o, LEAD(b.humidity, 2) OVER o) AS humidity,
        b.solar_rad_mj, b.sunshine_h, b.rain_mm,
        -- 供給予備力（2日前に公表されるため、そのまま利用）
        b.occto_reserve_rate, b.occto_area_demand_fc, b.occto_area_supply_fc,
        b.occto_area_reserve_mw, b.occto_area_reserve_rate,
        -- 燃料費
        b.lng_yen_per_t_m1, b.lng_yen_per_t_m2,
        -- カレンダー
        (b.slot - 1) DIV 2                                         AS hour,
        WEEKDAY(b.date)                                            AS weekday,   -- 0=月曜 … 6=日曜
        MONTH(b.date)                                              AS month,
        CASE WHEN h.date IS NOT NULL THEN 1 ELSE 0 END             AS is_holiday,
        CASE WHEN WEEKDAY(b.date) >= 5 OR h.date IS NOT NULL THEN 1 ELSE 0 END AS is_offday,
        CASE WHEN DATE_FORMAT(b.date, '%m-%d') >= '12-29'
               OR DATE_FORMAT(b.date, '%m-%d') <= '01-03' THEN 1 ELSE 0 END    AS is_yearend,
        CASE WHEN DATE_FORMAT(b.date, '%m-%d') BETWEEN '08-13' AND '08-16'
             THEN 1 ELSE 0 END                                     AS is_obon,
        -- 前日・前週の同じ時間枠の値（LAG 48 = 1日前、336 = 1週間前）
        LAG(b.price_tokyo, 48)       OVER o AS price_tokyo_lag1d,
        LAG(b.price_tokyo, 336)      OVER o AS price_tokyo_lag7d,
        LAG(b.price_system, 48)      OVER o AS price_system_lag1d,
        LAG(b.price_system, 336)     OVER o AS price_system_lag7d,
        LAG(b.sell_bid_kwh, 48)      OVER o AS sell_bid_kwh_lag1d,
        LAG(b.sell_bid_kwh, 336)     OVER o AS sell_bid_kwh_lag7d,
        LAG(b.buy_bid_kwh, 48)       OVER o AS buy_bid_kwh_lag1d,
        LAG(b.buy_bid_kwh, 336)      OVER o AS buy_bid_kwh_lag7d,
        LAG(b.contract_kwh, 48)      OVER o AS contract_kwh_lag1d,
        LAG(b.contract_kwh, 336)     OVER o AS contract_kwh_lag7d,
        LAG(b.demand_mw, 48)         OVER o AS demand_mw_lag1d,
        LAG(b.demand_mw, 336)        OVER o AS demand_mw_lag7d,
        LAG(b.nuclear_mw, 48)        OVER o AS nuclear_mw_lag1d,
        LAG(b.nuclear_mw, 336)       OVER o AS nuclear_mw_lag7d,
        LAG(b.lng_mw, 48)            OVER o AS lng_mw_lag1d,
        LAG(b.lng_mw, 336)           OVER o AS lng_mw_lag7d,
        LAG(b.coal_mw, 48)           OVER o AS coal_mw_lag1d,
        LAG(b.coal_mw, 336)          OVER o AS coal_mw_lag7d,
        LAG(b.oil_mw, 48)            OVER o AS oil_mw_lag1d,
        LAG(b.oil_mw, 336)           OVER o AS oil_mw_lag7d,
        LAG(b.thermal_other_mw, 48)  OVER o AS thermal_other_mw_lag1d,
        LAG(b.thermal_other_mw, 336) OVER o AS thermal_other_mw_lag7d,
        LAG(b.hydro_mw, 48)          OVER o AS hydro_mw_lag1d,
        LAG(b.hydro_mw, 336)         OVER o AS hydro_mw_lag7d,
        LAG(b.biomass_mw, 48)        OVER o AS biomass_mw_lag1d,
        LAG(b.biomass_mw, 336)       OVER o AS biomass_mw_lag7d,
        LAG(b.solar_mw, 48)          OVER o AS solar_mw_lag1d,
        LAG(b.solar_mw, 336)         OVER o AS solar_mw_lag7d,
        LAG(b.solar_curtail_mw, 48)  OVER o AS solar_curtail_mw_lag1d,
        LAG(b.solar_curtail_mw, 336) OVER o AS solar_curtail_mw_lag7d,
        LAG(b.wind_mw, 48)           OVER o AS wind_mw_lag1d,
        LAG(b.wind_mw, 336)          OVER o AS wind_mw_lag7d,
        LAG(b.wind_curtail_mw, 48)   OVER o AS wind_curtail_mw_lag1d,
        LAG(b.wind_curtail_mw, 336)  OVER o AS wind_curtail_mw_lag7d,
        LAG(b.pumped_mw, 48)         OVER o AS pumped_mw_lag1d,
        LAG(b.pumped_mw, 336)        OVER o AS pumped_mw_lag7d,
        LAG(b.battery_mw, 48)        OVER o AS battery_mw_lag1d,
        LAG(b.battery_mw, 336)       OVER o AS battery_mw_lag7d,
        LAG(b.interconnect_mw, 48)   OVER o AS interconnect_mw_lag1d,
        LAG(b.interconnect_mw, 336)  OVER o AS interconnect_mw_lag7d,
        LAG(b.other_mw, 48)          OVER o AS other_mw_lag1d,
        LAG(b.other_mw, 336)         OVER o AS other_mw_lag7d,
        dp.price_tokyo_mean7d, dp.price_tokyo_mean30d,
        -- 目的変数
        b.price_tokyo AS y_price,
        CASE WHEN dp.price_tokyo_mean30d IS NULL THEN NULL
             WHEN b.price_tokyo >= 1.5 * dp.price_tokyo_mean30d THEN 1 ELSE 0 END AS y_spike_rel,
        CASE WHEN b.occto_reserve_rate IS NOT NULL THEN 1 ELSE 0 END AS has_occto,
        CASE WHEN b.date >= '2026-04-01' THEN 1 ELSE 0 END           AS regime_2026,
        CASE WHEN b.date <  '2025-05-01' THEN 'train'
             WHEN b.date <  '2025-11-01' THEN 'valid'
             ELSE 'test' END                                          AS split
    FROM t_base b
    LEFT JOIN stg_holiday   h  ON h.date  = b.date
    LEFT JOIN t_daily_price dp ON dp.date = b.date
    WINDOW o AS (ORDER BY b.date, b.slot)
) x
WHERE x.date BETWEEN '2024-04-01' AND '2026-10-31';

ALTER TABLE fact_30min ADD PRIMARY KEY (date, slot);
