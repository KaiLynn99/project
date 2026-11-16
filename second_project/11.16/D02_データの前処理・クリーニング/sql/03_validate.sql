-- =====================================================================
-- 03_validate.sql  |  取込・変換結果の検証（結果表をキャプチャしてレポートに使用）
-- =====================================================================
USE jepx;

-- 1. ステージングテーブルごとの行数と対象期間
SELECT 'stg_jepx'    AS tbl, COUNT(*) AS n_rows, MIN(date) AS first_day, MAX(date) AS last_day FROM stg_jepx
UNION ALL SELECT 'stg_tepco',   COUNT(*), MIN(date), MAX(date) FROM stg_tepco
UNION ALL SELECT 'stg_weather', COUNT(*), MIN(DATE(obs_time)), MAX(DATE(obs_time)) FROM stg_weather
UNION ALL SELECT 'stg_holiday', COUNT(*), MIN(date), MAX(date) FROM stg_holiday
UNION ALL SELECT 'stg_occto',   COUNT(*), MIN(date), MAX(date) FROM stg_occto
UNION ALL SELECT 'stg_lng',     COUNT(*), MIN(ym),   MAX(ym)   FROM stg_lng
UNION ALL SELECT 'fact_30min',  COUNT(*), MIN(date), MAX(date) FROM fact_30min;

-- 2. 1日48枠ではない日（東京電力の2026-11-13の1行だけなら正常: ダウンロード当日のため部分データ）
SELECT 'jepx' AS src, date, COUNT(*) AS n FROM stg_jepx  GROUP BY date HAVING COUNT(*) <> 48
UNION ALL
SELECT 'tepco', date, COUNT(*) FROM stg_tepco GROUP BY date HAVING COUNT(*) <> 48
UNION ALL
SELECT 'occto(東京)', date, COUNT(*) FROM stg_occto WHERE area_name = '東京' GROUP BY date HAVING COUNT(*) <> 48;

-- 3. 最終テーブル: 行数 = 日数 × 48かを確認（944日 × 48 = 45,312）
SELECT COUNT(*) AS n_rows, COUNT(DISTINCT date) AS n_days, COUNT(DISTINCT date) * 48 AS expected
FROM fact_30min;

-- 4. 主要列の欠損数（OCCTOは2025-04以前の1年間が欠損するのが正常: 17,520枠）
SELECT SUM(y_price IS NULL)            AS null_y_price,
       SUM(y_spike_rel IS NULL)        AS null_y_spike,
       SUM(temp_c IS NULL)             AS null_temp,
       SUM(solar_rad_mj IS NULL)       AS null_solar_rad,
       SUM(price_tokyo_lag7d IS NULL)  AS null_price_lag7d,
       SUM(demand_mw_lag7d IS NULL)    AS null_demand_lag7d,
       SUM(lng_yen_per_t_m2 IS NULL)   AS null_lng_m2,
       SUM(occto_reserve_rate IS NULL) AS null_occto
FROM fact_30min;

-- 5. 分割ごとの行数と価格急騰率（学習3.8% / 検証6.1% / テスト9.2%程度なら正常）
SELECT split, COUNT(*) AS n_rows, ROUND(AVG(y_spike_rel) * 100, 1) AS spike_pct,
       ROUND(AVG(y_price), 2) AS avg_price
FROM fact_30min
GROUP BY split
ORDER BY MIN(date);

-- 6. 予備率の区分別平均価格（探索的データ分析のプレビュー: 予備率が低いほど高値になる想定）
SELECT CASE WHEN occto_reserve_rate <= 5  THEN '01) 5%以下'
            WHEN occto_reserve_rate <= 8  THEN '02) 5~8%'
            WHEN occto_reserve_rate <= 10 THEN '03) 8~10%'
            WHEN occto_reserve_rate <= 15 THEN '04) 10~15%'
            WHEN occto_reserve_rate <= 20 THEN '05) 15~20%'
            ELSE '06) 20%超' END AS reserve_band,
       COUNT(*) AS n_slots, ROUND(AVG(y_price), 2) AS avg_price
FROM fact_30min
WHERE occto_reserve_rate IS NOT NULL
GROUP BY reserve_band
ORDER BY reserve_band;

-- 7. 時刻の整合性を確認: 日射量は正午前後に最大となるはず
SELECT hour, ROUND(AVG(solar_rad_mj), 3) AS avg_solar_rad
FROM fact_30min
GROUP BY hour
ORDER BY hour;
