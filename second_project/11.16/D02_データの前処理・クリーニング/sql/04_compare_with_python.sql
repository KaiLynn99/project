-- =====================================================================
-- 04_compare_with_python.sql  |  SQL結果（fact_30min）とPython結果（py_dataset）のクロスチェック
-- 事前準備: python load_raw_to_db.py ... --python-csv merged_30min.csv（py_datasetへ取り込む）
-- 判定: 全列でn_mismatch = 0なら、両手法の結果が一致することを意味する
-- =====================================================================
USE jepx;

-- 1. 片方にしか存在しない行（両方とも0であることが正常）
SELECT
  (SELECT COUNT(*) FROM fact_30min f
    WHERE NOT EXISTS (SELECT 1 FROM py_dataset p WHERE p.date = f.date AND p.slot = f.slot)) AS only_in_sql,
  (SELECT COUNT(*) FROM py_dataset p
    WHERE NOT EXISTS (SELECT 1 FROM fact_30min f WHERE f.date = p.date AND f.slot = p.slot)) AS only_in_python;

-- 2. 列ごとに値が異なるセル数（許容誤差: 1e-6 × (1 + |値|)）
WITH j AS (
  SELECT f.*, p.temp_c AS py_temp_c,
         p.humidity AS py_humidity,
         p.solar_rad_mj AS py_solar_rad_mj,
         p.sunshine_h AS py_sunshine_h,
         p.rain_mm AS py_rain_mm,
         p.occto_reserve_rate AS py_occto_reserve_rate,
         p.occto_area_demand_fc AS py_occto_area_demand_fc,
         p.occto_area_supply_fc AS py_occto_area_supply_fc,
         p.occto_area_reserve_mw AS py_occto_area_reserve_mw,
         p.occto_area_reserve_rate AS py_occto_area_reserve_rate,
         p.lng_yen_per_t_m1 AS py_lng_yen_per_t_m1,
         p.lng_yen_per_t_m2 AS py_lng_yen_per_t_m2,
         p.hour AS py_hour,
         p.weekday AS py_weekday,
         p.month AS py_month,
         p.is_holiday AS py_is_holiday,
         p.is_offday AS py_is_offday,
         p.is_yearend AS py_is_yearend,
         p.is_obon AS py_is_obon,
         p.cooling_deg AS py_cooling_deg,
         p.heating_deg AS py_heating_deg,
         p.price_tokyo_lag1d AS py_price_tokyo_lag1d,
         p.price_tokyo_lag7d AS py_price_tokyo_lag7d,
         p.price_system_lag1d AS py_price_system_lag1d,
         p.price_system_lag7d AS py_price_system_lag7d,
         p.sell_bid_kwh_lag1d AS py_sell_bid_kwh_lag1d,
         p.sell_bid_kwh_lag7d AS py_sell_bid_kwh_lag7d,
         p.buy_bid_kwh_lag1d AS py_buy_bid_kwh_lag1d,
         p.buy_bid_kwh_lag7d AS py_buy_bid_kwh_lag7d,
         p.contract_kwh_lag1d AS py_contract_kwh_lag1d,
         p.contract_kwh_lag7d AS py_contract_kwh_lag7d,
         p.demand_mw_lag1d AS py_demand_mw_lag1d,
         p.demand_mw_lag7d AS py_demand_mw_lag7d,
         p.nuclear_mw_lag1d AS py_nuclear_mw_lag1d,
         p.nuclear_mw_lag7d AS py_nuclear_mw_lag7d,
         p.lng_mw_lag1d AS py_lng_mw_lag1d,
         p.lng_mw_lag7d AS py_lng_mw_lag7d,
         p.coal_mw_lag1d AS py_coal_mw_lag1d,
         p.coal_mw_lag7d AS py_coal_mw_lag7d,
         p.oil_mw_lag1d AS py_oil_mw_lag1d,
         p.oil_mw_lag7d AS py_oil_mw_lag7d,
         p.thermal_other_mw_lag1d AS py_thermal_other_mw_lag1d,
         p.thermal_other_mw_lag7d AS py_thermal_other_mw_lag7d,
         p.hydro_mw_lag1d AS py_hydro_mw_lag1d,
         p.hydro_mw_lag7d AS py_hydro_mw_lag7d,
         p.biomass_mw_lag1d AS py_biomass_mw_lag1d,
         p.biomass_mw_lag7d AS py_biomass_mw_lag7d,
         p.solar_mw_lag1d AS py_solar_mw_lag1d,
         p.solar_mw_lag7d AS py_solar_mw_lag7d,
         p.solar_curtail_mw_lag1d AS py_solar_curtail_mw_lag1d,
         p.solar_curtail_mw_lag7d AS py_solar_curtail_mw_lag7d,
         p.wind_mw_lag1d AS py_wind_mw_lag1d,
         p.wind_mw_lag7d AS py_wind_mw_lag7d,
         p.wind_curtail_mw_lag1d AS py_wind_curtail_mw_lag1d,
         p.wind_curtail_mw_lag7d AS py_wind_curtail_mw_lag7d,
         p.pumped_mw_lag1d AS py_pumped_mw_lag1d,
         p.pumped_mw_lag7d AS py_pumped_mw_lag7d,
         p.battery_mw_lag1d AS py_battery_mw_lag1d,
         p.battery_mw_lag7d AS py_battery_mw_lag7d,
         p.interconnect_mw_lag1d AS py_interconnect_mw_lag1d,
         p.interconnect_mw_lag7d AS py_interconnect_mw_lag7d,
         p.other_mw_lag1d AS py_other_mw_lag1d,
         p.other_mw_lag7d AS py_other_mw_lag7d,
         p.price_tokyo_mean7d AS py_price_tokyo_mean7d,
         p.price_tokyo_mean30d AS py_price_tokyo_mean30d,
         p.y_price AS py_y_price,
         p.y_spike_rel AS py_y_spike_rel,
         p.has_occto AS py_has_occto,
         p.regime_2026 AS py_regime_2026,
         p.split AS py_split
  FROM fact_30min f
  JOIN py_dataset p ON p.date = f.date AND p.slot = f.slot
)
SELECT 'temp_c' AS col, SUM(CASE WHEN (j.temp_c IS NULL) <> (j.py_temp_c IS NULL) OR ABS(j.temp_c - j.py_temp_c) > 0.000001 * (1 + ABS(j.py_temp_c)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'humidity' AS col, SUM(CASE WHEN (j.humidity IS NULL) <> (j.py_humidity IS NULL) OR ABS(j.humidity - j.py_humidity) > 0.000001 * (1 + ABS(j.py_humidity)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'solar_rad_mj' AS col, SUM(CASE WHEN (j.solar_rad_mj IS NULL) <> (j.py_solar_rad_mj IS NULL) OR ABS(j.solar_rad_mj - j.py_solar_rad_mj) > 0.000001 * (1 + ABS(j.py_solar_rad_mj)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'sunshine_h' AS col, SUM(CASE WHEN (j.sunshine_h IS NULL) <> (j.py_sunshine_h IS NULL) OR ABS(j.sunshine_h - j.py_sunshine_h) > 0.000001 * (1 + ABS(j.py_sunshine_h)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'rain_mm' AS col, SUM(CASE WHEN (j.rain_mm IS NULL) <> (j.py_rain_mm IS NULL) OR ABS(j.rain_mm - j.py_rain_mm) > 0.000001 * (1 + ABS(j.py_rain_mm)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'occto_reserve_rate' AS col, SUM(CASE WHEN (j.occto_reserve_rate IS NULL) <> (j.py_occto_reserve_rate IS NULL) OR ABS(j.occto_reserve_rate - j.py_occto_reserve_rate) > 0.000001 * (1 + ABS(j.py_occto_reserve_rate)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'occto_area_demand_fc' AS col, SUM(CASE WHEN (j.occto_area_demand_fc IS NULL) <> (j.py_occto_area_demand_fc IS NULL) OR ABS(j.occto_area_demand_fc - j.py_occto_area_demand_fc) > 0.000001 * (1 + ABS(j.py_occto_area_demand_fc)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'occto_area_supply_fc' AS col, SUM(CASE WHEN (j.occto_area_supply_fc IS NULL) <> (j.py_occto_area_supply_fc IS NULL) OR ABS(j.occto_area_supply_fc - j.py_occto_area_supply_fc) > 0.000001 * (1 + ABS(j.py_occto_area_supply_fc)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'occto_area_reserve_mw' AS col, SUM(CASE WHEN (j.occto_area_reserve_mw IS NULL) <> (j.py_occto_area_reserve_mw IS NULL) OR ABS(j.occto_area_reserve_mw - j.py_occto_area_reserve_mw) > 0.000001 * (1 + ABS(j.py_occto_area_reserve_mw)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'occto_area_reserve_rate' AS col, SUM(CASE WHEN (j.occto_area_reserve_rate IS NULL) <> (j.py_occto_area_reserve_rate IS NULL) OR ABS(j.occto_area_reserve_rate - j.py_occto_area_reserve_rate) > 0.000001 * (1 + ABS(j.py_occto_area_reserve_rate)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'lng_yen_per_t_m1' AS col, SUM(CASE WHEN (j.lng_yen_per_t_m1 IS NULL) <> (j.py_lng_yen_per_t_m1 IS NULL) OR ABS(j.lng_yen_per_t_m1 - j.py_lng_yen_per_t_m1) > 0.000001 * (1 + ABS(j.py_lng_yen_per_t_m1)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'lng_yen_per_t_m2' AS col, SUM(CASE WHEN (j.lng_yen_per_t_m2 IS NULL) <> (j.py_lng_yen_per_t_m2 IS NULL) OR ABS(j.lng_yen_per_t_m2 - j.py_lng_yen_per_t_m2) > 0.000001 * (1 + ABS(j.py_lng_yen_per_t_m2)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'hour' AS col, SUM(CASE WHEN (j.hour IS NULL) <> (j.py_hour IS NULL) OR ABS(j.hour - j.py_hour) > 0.000001 * (1 + ABS(j.py_hour)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'weekday' AS col, SUM(CASE WHEN (j.weekday IS NULL) <> (j.py_weekday IS NULL) OR ABS(j.weekday - j.py_weekday) > 0.000001 * (1 + ABS(j.py_weekday)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'month' AS col, SUM(CASE WHEN (j.month IS NULL) <> (j.py_month IS NULL) OR ABS(j.month - j.py_month) > 0.000001 * (1 + ABS(j.py_month)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'is_holiday' AS col, SUM(CASE WHEN (j.is_holiday IS NULL) <> (j.py_is_holiday IS NULL) OR ABS(j.is_holiday - j.py_is_holiday) > 0.000001 * (1 + ABS(j.py_is_holiday)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'is_offday' AS col, SUM(CASE WHEN (j.is_offday IS NULL) <> (j.py_is_offday IS NULL) OR ABS(j.is_offday - j.py_is_offday) > 0.000001 * (1 + ABS(j.py_is_offday)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'is_yearend' AS col, SUM(CASE WHEN (j.is_yearend IS NULL) <> (j.py_is_yearend IS NULL) OR ABS(j.is_yearend - j.py_is_yearend) > 0.000001 * (1 + ABS(j.py_is_yearend)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'is_obon' AS col, SUM(CASE WHEN (j.is_obon IS NULL) <> (j.py_is_obon IS NULL) OR ABS(j.is_obon - j.py_is_obon) > 0.000001 * (1 + ABS(j.py_is_obon)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'cooling_deg' AS col, SUM(CASE WHEN (j.cooling_deg IS NULL) <> (j.py_cooling_deg IS NULL) OR ABS(j.cooling_deg - j.py_cooling_deg) > 0.000001 * (1 + ABS(j.py_cooling_deg)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'heating_deg' AS col, SUM(CASE WHEN (j.heating_deg IS NULL) <> (j.py_heating_deg IS NULL) OR ABS(j.heating_deg - j.py_heating_deg) > 0.000001 * (1 + ABS(j.py_heating_deg)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'price_tokyo_lag1d' AS col, SUM(CASE WHEN (j.price_tokyo_lag1d IS NULL) <> (j.py_price_tokyo_lag1d IS NULL) OR ABS(j.price_tokyo_lag1d - j.py_price_tokyo_lag1d) > 0.000001 * (1 + ABS(j.py_price_tokyo_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'price_tokyo_lag7d' AS col, SUM(CASE WHEN (j.price_tokyo_lag7d IS NULL) <> (j.py_price_tokyo_lag7d IS NULL) OR ABS(j.price_tokyo_lag7d - j.py_price_tokyo_lag7d) > 0.000001 * (1 + ABS(j.py_price_tokyo_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'price_system_lag1d' AS col, SUM(CASE WHEN (j.price_system_lag1d IS NULL) <> (j.py_price_system_lag1d IS NULL) OR ABS(j.price_system_lag1d - j.py_price_system_lag1d) > 0.000001 * (1 + ABS(j.py_price_system_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'price_system_lag7d' AS col, SUM(CASE WHEN (j.price_system_lag7d IS NULL) <> (j.py_price_system_lag7d IS NULL) OR ABS(j.price_system_lag7d - j.py_price_system_lag7d) > 0.000001 * (1 + ABS(j.py_price_system_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'sell_bid_kwh_lag1d' AS col, SUM(CASE WHEN (j.sell_bid_kwh_lag1d IS NULL) <> (j.py_sell_bid_kwh_lag1d IS NULL) OR ABS(j.sell_bid_kwh_lag1d - j.py_sell_bid_kwh_lag1d) > 0.000001 * (1 + ABS(j.py_sell_bid_kwh_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'sell_bid_kwh_lag7d' AS col, SUM(CASE WHEN (j.sell_bid_kwh_lag7d IS NULL) <> (j.py_sell_bid_kwh_lag7d IS NULL) OR ABS(j.sell_bid_kwh_lag7d - j.py_sell_bid_kwh_lag7d) > 0.000001 * (1 + ABS(j.py_sell_bid_kwh_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'buy_bid_kwh_lag1d' AS col, SUM(CASE WHEN (j.buy_bid_kwh_lag1d IS NULL) <> (j.py_buy_bid_kwh_lag1d IS NULL) OR ABS(j.buy_bid_kwh_lag1d - j.py_buy_bid_kwh_lag1d) > 0.000001 * (1 + ABS(j.py_buy_bid_kwh_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'buy_bid_kwh_lag7d' AS col, SUM(CASE WHEN (j.buy_bid_kwh_lag7d IS NULL) <> (j.py_buy_bid_kwh_lag7d IS NULL) OR ABS(j.buy_bid_kwh_lag7d - j.py_buy_bid_kwh_lag7d) > 0.000001 * (1 + ABS(j.py_buy_bid_kwh_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'contract_kwh_lag1d' AS col, SUM(CASE WHEN (j.contract_kwh_lag1d IS NULL) <> (j.py_contract_kwh_lag1d IS NULL) OR ABS(j.contract_kwh_lag1d - j.py_contract_kwh_lag1d) > 0.000001 * (1 + ABS(j.py_contract_kwh_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'contract_kwh_lag7d' AS col, SUM(CASE WHEN (j.contract_kwh_lag7d IS NULL) <> (j.py_contract_kwh_lag7d IS NULL) OR ABS(j.contract_kwh_lag7d - j.py_contract_kwh_lag7d) > 0.000001 * (1 + ABS(j.py_contract_kwh_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'demand_mw_lag1d' AS col, SUM(CASE WHEN (j.demand_mw_lag1d IS NULL) <> (j.py_demand_mw_lag1d IS NULL) OR ABS(j.demand_mw_lag1d - j.py_demand_mw_lag1d) > 0.000001 * (1 + ABS(j.py_demand_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'demand_mw_lag7d' AS col, SUM(CASE WHEN (j.demand_mw_lag7d IS NULL) <> (j.py_demand_mw_lag7d IS NULL) OR ABS(j.demand_mw_lag7d - j.py_demand_mw_lag7d) > 0.000001 * (1 + ABS(j.py_demand_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'nuclear_mw_lag1d' AS col, SUM(CASE WHEN (j.nuclear_mw_lag1d IS NULL) <> (j.py_nuclear_mw_lag1d IS NULL) OR ABS(j.nuclear_mw_lag1d - j.py_nuclear_mw_lag1d) > 0.000001 * (1 + ABS(j.py_nuclear_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'nuclear_mw_lag7d' AS col, SUM(CASE WHEN (j.nuclear_mw_lag7d IS NULL) <> (j.py_nuclear_mw_lag7d IS NULL) OR ABS(j.nuclear_mw_lag7d - j.py_nuclear_mw_lag7d) > 0.000001 * (1 + ABS(j.py_nuclear_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'lng_mw_lag1d' AS col, SUM(CASE WHEN (j.lng_mw_lag1d IS NULL) <> (j.py_lng_mw_lag1d IS NULL) OR ABS(j.lng_mw_lag1d - j.py_lng_mw_lag1d) > 0.000001 * (1 + ABS(j.py_lng_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'lng_mw_lag7d' AS col, SUM(CASE WHEN (j.lng_mw_lag7d IS NULL) <> (j.py_lng_mw_lag7d IS NULL) OR ABS(j.lng_mw_lag7d - j.py_lng_mw_lag7d) > 0.000001 * (1 + ABS(j.py_lng_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'coal_mw_lag1d' AS col, SUM(CASE WHEN (j.coal_mw_lag1d IS NULL) <> (j.py_coal_mw_lag1d IS NULL) OR ABS(j.coal_mw_lag1d - j.py_coal_mw_lag1d) > 0.000001 * (1 + ABS(j.py_coal_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'coal_mw_lag7d' AS col, SUM(CASE WHEN (j.coal_mw_lag7d IS NULL) <> (j.py_coal_mw_lag7d IS NULL) OR ABS(j.coal_mw_lag7d - j.py_coal_mw_lag7d) > 0.000001 * (1 + ABS(j.py_coal_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'oil_mw_lag1d' AS col, SUM(CASE WHEN (j.oil_mw_lag1d IS NULL) <> (j.py_oil_mw_lag1d IS NULL) OR ABS(j.oil_mw_lag1d - j.py_oil_mw_lag1d) > 0.000001 * (1 + ABS(j.py_oil_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'oil_mw_lag7d' AS col, SUM(CASE WHEN (j.oil_mw_lag7d IS NULL) <> (j.py_oil_mw_lag7d IS NULL) OR ABS(j.oil_mw_lag7d - j.py_oil_mw_lag7d) > 0.000001 * (1 + ABS(j.py_oil_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'thermal_other_mw_lag1d' AS col, SUM(CASE WHEN (j.thermal_other_mw_lag1d IS NULL) <> (j.py_thermal_other_mw_lag1d IS NULL) OR ABS(j.thermal_other_mw_lag1d - j.py_thermal_other_mw_lag1d) > 0.000001 * (1 + ABS(j.py_thermal_other_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'thermal_other_mw_lag7d' AS col, SUM(CASE WHEN (j.thermal_other_mw_lag7d IS NULL) <> (j.py_thermal_other_mw_lag7d IS NULL) OR ABS(j.thermal_other_mw_lag7d - j.py_thermal_other_mw_lag7d) > 0.000001 * (1 + ABS(j.py_thermal_other_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'hydro_mw_lag1d' AS col, SUM(CASE WHEN (j.hydro_mw_lag1d IS NULL) <> (j.py_hydro_mw_lag1d IS NULL) OR ABS(j.hydro_mw_lag1d - j.py_hydro_mw_lag1d) > 0.000001 * (1 + ABS(j.py_hydro_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'hydro_mw_lag7d' AS col, SUM(CASE WHEN (j.hydro_mw_lag7d IS NULL) <> (j.py_hydro_mw_lag7d IS NULL) OR ABS(j.hydro_mw_lag7d - j.py_hydro_mw_lag7d) > 0.000001 * (1 + ABS(j.py_hydro_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'biomass_mw_lag1d' AS col, SUM(CASE WHEN (j.biomass_mw_lag1d IS NULL) <> (j.py_biomass_mw_lag1d IS NULL) OR ABS(j.biomass_mw_lag1d - j.py_biomass_mw_lag1d) > 0.000001 * (1 + ABS(j.py_biomass_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'biomass_mw_lag7d' AS col, SUM(CASE WHEN (j.biomass_mw_lag7d IS NULL) <> (j.py_biomass_mw_lag7d IS NULL) OR ABS(j.biomass_mw_lag7d - j.py_biomass_mw_lag7d) > 0.000001 * (1 + ABS(j.py_biomass_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'solar_mw_lag1d' AS col, SUM(CASE WHEN (j.solar_mw_lag1d IS NULL) <> (j.py_solar_mw_lag1d IS NULL) OR ABS(j.solar_mw_lag1d - j.py_solar_mw_lag1d) > 0.000001 * (1 + ABS(j.py_solar_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'solar_mw_lag7d' AS col, SUM(CASE WHEN (j.solar_mw_lag7d IS NULL) <> (j.py_solar_mw_lag7d IS NULL) OR ABS(j.solar_mw_lag7d - j.py_solar_mw_lag7d) > 0.000001 * (1 + ABS(j.py_solar_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'solar_curtail_mw_lag1d' AS col, SUM(CASE WHEN (j.solar_curtail_mw_lag1d IS NULL) <> (j.py_solar_curtail_mw_lag1d IS NULL) OR ABS(j.solar_curtail_mw_lag1d - j.py_solar_curtail_mw_lag1d) > 0.000001 * (1 + ABS(j.py_solar_curtail_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'solar_curtail_mw_lag7d' AS col, SUM(CASE WHEN (j.solar_curtail_mw_lag7d IS NULL) <> (j.py_solar_curtail_mw_lag7d IS NULL) OR ABS(j.solar_curtail_mw_lag7d - j.py_solar_curtail_mw_lag7d) > 0.000001 * (1 + ABS(j.py_solar_curtail_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'wind_mw_lag1d' AS col, SUM(CASE WHEN (j.wind_mw_lag1d IS NULL) <> (j.py_wind_mw_lag1d IS NULL) OR ABS(j.wind_mw_lag1d - j.py_wind_mw_lag1d) > 0.000001 * (1 + ABS(j.py_wind_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'wind_mw_lag7d' AS col, SUM(CASE WHEN (j.wind_mw_lag7d IS NULL) <> (j.py_wind_mw_lag7d IS NULL) OR ABS(j.wind_mw_lag7d - j.py_wind_mw_lag7d) > 0.000001 * (1 + ABS(j.py_wind_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'wind_curtail_mw_lag1d' AS col, SUM(CASE WHEN (j.wind_curtail_mw_lag1d IS NULL) <> (j.py_wind_curtail_mw_lag1d IS NULL) OR ABS(j.wind_curtail_mw_lag1d - j.py_wind_curtail_mw_lag1d) > 0.000001 * (1 + ABS(j.py_wind_curtail_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'wind_curtail_mw_lag7d' AS col, SUM(CASE WHEN (j.wind_curtail_mw_lag7d IS NULL) <> (j.py_wind_curtail_mw_lag7d IS NULL) OR ABS(j.wind_curtail_mw_lag7d - j.py_wind_curtail_mw_lag7d) > 0.000001 * (1 + ABS(j.py_wind_curtail_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'pumped_mw_lag1d' AS col, SUM(CASE WHEN (j.pumped_mw_lag1d IS NULL) <> (j.py_pumped_mw_lag1d IS NULL) OR ABS(j.pumped_mw_lag1d - j.py_pumped_mw_lag1d) > 0.000001 * (1 + ABS(j.py_pumped_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'pumped_mw_lag7d' AS col, SUM(CASE WHEN (j.pumped_mw_lag7d IS NULL) <> (j.py_pumped_mw_lag7d IS NULL) OR ABS(j.pumped_mw_lag7d - j.py_pumped_mw_lag7d) > 0.000001 * (1 + ABS(j.py_pumped_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'battery_mw_lag1d' AS col, SUM(CASE WHEN (j.battery_mw_lag1d IS NULL) <> (j.py_battery_mw_lag1d IS NULL) OR ABS(j.battery_mw_lag1d - j.py_battery_mw_lag1d) > 0.000001 * (1 + ABS(j.py_battery_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'battery_mw_lag7d' AS col, SUM(CASE WHEN (j.battery_mw_lag7d IS NULL) <> (j.py_battery_mw_lag7d IS NULL) OR ABS(j.battery_mw_lag7d - j.py_battery_mw_lag7d) > 0.000001 * (1 + ABS(j.py_battery_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'interconnect_mw_lag1d' AS col, SUM(CASE WHEN (j.interconnect_mw_lag1d IS NULL) <> (j.py_interconnect_mw_lag1d IS NULL) OR ABS(j.interconnect_mw_lag1d - j.py_interconnect_mw_lag1d) > 0.000001 * (1 + ABS(j.py_interconnect_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'interconnect_mw_lag7d' AS col, SUM(CASE WHEN (j.interconnect_mw_lag7d IS NULL) <> (j.py_interconnect_mw_lag7d IS NULL) OR ABS(j.interconnect_mw_lag7d - j.py_interconnect_mw_lag7d) > 0.000001 * (1 + ABS(j.py_interconnect_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'other_mw_lag1d' AS col, SUM(CASE WHEN (j.other_mw_lag1d IS NULL) <> (j.py_other_mw_lag1d IS NULL) OR ABS(j.other_mw_lag1d - j.py_other_mw_lag1d) > 0.000001 * (1 + ABS(j.py_other_mw_lag1d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'other_mw_lag7d' AS col, SUM(CASE WHEN (j.other_mw_lag7d IS NULL) <> (j.py_other_mw_lag7d IS NULL) OR ABS(j.other_mw_lag7d - j.py_other_mw_lag7d) > 0.000001 * (1 + ABS(j.py_other_mw_lag7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'price_tokyo_mean7d' AS col, SUM(CASE WHEN (j.price_tokyo_mean7d IS NULL) <> (j.py_price_tokyo_mean7d IS NULL) OR ABS(j.price_tokyo_mean7d - j.py_price_tokyo_mean7d) > 0.000001 * (1 + ABS(j.py_price_tokyo_mean7d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'price_tokyo_mean30d' AS col, SUM(CASE WHEN (j.price_tokyo_mean30d IS NULL) <> (j.py_price_tokyo_mean30d IS NULL) OR ABS(j.price_tokyo_mean30d - j.py_price_tokyo_mean30d) > 0.000001 * (1 + ABS(j.py_price_tokyo_mean30d)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'y_price' AS col, SUM(CASE WHEN (j.y_price IS NULL) <> (j.py_y_price IS NULL) OR ABS(j.y_price - j.py_y_price) > 0.000001 * (1 + ABS(j.py_y_price)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'y_spike_rel' AS col, SUM(CASE WHEN (j.y_spike_rel IS NULL) <> (j.py_y_spike_rel IS NULL) OR ABS(j.y_spike_rel - j.py_y_spike_rel) > 0.000001 * (1 + ABS(j.py_y_spike_rel)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'has_occto' AS col, SUM(CASE WHEN (j.has_occto IS NULL) <> (j.py_has_occto IS NULL) OR ABS(j.has_occto - j.py_has_occto) > 0.000001 * (1 + ABS(j.py_has_occto)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'regime_2026' AS col, SUM(CASE WHEN (j.regime_2026 IS NULL) <> (j.py_regime_2026 IS NULL) OR ABS(j.regime_2026 - j.py_regime_2026) > 0.000001 * (1 + ABS(j.py_regime_2026)) THEN 1 ELSE 0 END) AS n_mismatch FROM j
UNION ALL
SELECT 'split' AS col, SUM(CASE WHEN j.split <> j.py_split THEN 1 ELSE 0 END) AS n_mismatch FROM j;
