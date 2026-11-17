-- =====================================================================
-- 05_analysis.sql | 発表用のSQL分析（前処理ではなく、作成済みのfact_30minを参照する）
-- 実行前提：01～04の処理が完了し、fact_30minテーブルが存在すること
-- 各クエリの実行結果をキャプチャし、「SQLで読み解く電力価格の傾向」のスライドに使用する
-- =====================================================================
USE jepx;

-- ① 月別平均価格と価格急騰率 → 「2026年4月以降、価格が上昇している」
SELECT DATE_FORMAT(date, '%Y-%m')        AS ym,
       ROUND(AVG(y_price), 2)            AS avg_price,
       ROUND(AVG(y_spike_rel) * 100, 1)  AS spike_pct
FROM fact_30min
GROUP BY ym
ORDER BY ym;

-- ② 時間帯別の平均価格と価格急騰率 → 「高値・急騰が起きやすい時間帯はいつか」
SELECT hour,
       ROUND(AVG(y_price), 2)            AS avg_price,
       ROUND(AVG(y_spike_rel) * 100, 1)  AS spike_pct
FROM fact_30min
GROUP BY hour
ORDER BY hour;

-- ③ 平日と休日の比較 → 「電力需要が少ない日は価格が低い傾向がある」
SELECT CASE WHEN is_offday = 1 THEN '休日' ELSE '平日' END AS day_type,
       COUNT(*)                          AS n_slots,
       ROUND(AVG(y_price), 2)            AS avg_price,
       ROUND(AVG(y_spike_rel) * 100, 1)  AS spike_pct
FROM fact_30min
GROUP BY day_type;

-- ④ 気温帯別の平均価格 → 「極端な高温・低温時に価格が高くなりやすい」
SELECT CASE WHEN temp_c < 5  THEN '01) 5℃未満'
            WHEN temp_c < 14 THEN '02) 5～14℃'
            WHEN temp_c < 22 THEN '03) 14～22℃'
            WHEN temp_c < 30 THEN '04) 22～30℃'
            ELSE '05) 30℃以上' END       AS temp_band,
       COUNT(*)                          AS n_slots,
       ROUND(AVG(y_price), 2)            AS avg_price,
       ROUND(AVG(y_spike_rel) * 100, 1)  AS spike_pct
FROM fact_30min
GROUP BY temp_band
ORDER BY temp_band;

-- ⑤ 予備率（供給余力）帯別の平均価格 → 「供給余力が少ないほど高価格になりやすい」（2025年4月以降のデータ）
SELECT CASE WHEN occto_reserve_rate <= 5  THEN '01) 5%以下'
            WHEN occto_reserve_rate <= 8  THEN '02) 5～8%'
            WHEN occto_reserve_rate <= 10 THEN '03) 8～10%'
            WHEN occto_reserve_rate <= 15 THEN '04) 10～15%'
            WHEN occto_reserve_rate <= 20 THEN '05) 15～20%'
            ELSE '06) 20%超' END        AS reserve_band,
       COUNT(*)                          AS n_slots,
       ROUND(AVG(y_price), 2)            AS avg_price,
       ROUND(AVG(y_spike_rel) * 100, 1)  AS spike_pct
FROM fact_30min
WHERE occto_reserve_rate IS NOT NULL
GROUP BY reserve_band
ORDER BY reserve_band;
