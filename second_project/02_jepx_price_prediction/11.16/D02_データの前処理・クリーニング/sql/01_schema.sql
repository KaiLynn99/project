-- =====================================================================
-- 01_schema.sql  |  チーム・モダピ · JEPX電力価格の急騰予測
-- 6種類の元データを格納するステージングテーブル（stg_）を作成
-- 実行順序: 01_schema.sql → load_raw_to_db.py → 02_transform.sql
--           → 03_validate.sql → 04_compare_with_python.sql
-- MySQL 8.0以降
-- =====================================================================

CREATE DATABASE IF NOT EXISTS jepx DEFAULT CHARACTER SET utf8mb4;
USE jepx;

-- ① JEPXスポット価格（30分単位、時刻コード1～48）
DROP TABLE IF EXISTS stg_jepx;
CREATE TABLE stg_jepx (
    date            DATE    NOT NULL,
    slot            INT     NOT NULL,      -- 1 = 0:00~0:30, 48 = 23:30~24:00
    price_tokyo     DOUBLE,                -- エリアプライス東京 (円/kWh)
    price_system    DOUBLE,                -- システムプライス (円/kWh)
    sell_bid_kwh    DOUBLE,
    buy_bid_kwh     DOUBLE,
    contract_kwh    DOUBLE,
    PRIMARY KEY (date, slot)
);

-- ② 東京電力エリア需給実績（30分単位、TIME = 時間枠の「開始」時刻、MW）
DROP TABLE IF EXISTS stg_tepco;
CREATE TABLE stg_tepco (
    date             DATE        NOT NULL,
    time_hhmm        CHAR(5)     NOT NULL,  -- '00:00' ~ '23:30'
    demand_mw        DOUBLE,
    nuclear_mw       DOUBLE,
    lng_mw           DOUBLE,
    coal_mw          DOUBLE,
    oil_mw           DOUBLE,
    thermal_other_mw DOUBLE,
    hydro_mw         DOUBLE,
    biomass_mw       DOUBLE,
    solar_mw         DOUBLE,
    solar_curtail_mw DOUBLE,
    wind_mw          DOUBLE,
    wind_curtail_mw  DOUBLE,
    pumped_mw        DOUBLE,                -- 負値 = 揚水運転（蓄電）
    battery_mw       DOUBLE,                -- 負値 = 充電
    interconnect_mw  DOUBLE,                -- 負値 = 他エリアへの送電
    other_mw         DOUBLE,
    PRIMARY KEY (date, time_hhmm)
);

-- ③ 気象庁の東京の時別値（obs_time = 観測時刻。1:00～24:00の表記を通常の時刻に変換して取り込む）
DROP TABLE IF EXISTS stg_weather;
CREATE TABLE stg_weather (
    obs_time     DATETIME NOT NULL,
    temp_c       DOUBLE,                   -- 気温: その時刻の瞬間値
    humidity     DOUBLE,                   -- 相対湿度: 瞬間値
    solar_rad_mj DOUBLE,                   -- 全天日射量（前1時間）: 直前1時間の積算値
    sunshine_h   DOUBLE,                   -- 日照時間（前1時間）: 直前1時間の日照時間
    rain_mm      DOUBLE,                   -- 降水量（前1時間）: 直前1時間の積算値
    PRIMARY KEY (obs_time)
);

-- ④ 内閣府の国民の祝日
DROP TABLE IF EXISTS stg_holiday;
CREATE TABLE stg_holiday (
    date         DATE NOT NULL,
    holiday_name VARCHAR(50),
    PRIMARY KEY (date)
);

-- ⑤ OCCTO広域予備率（翌々日分の公表、時刻 = 時間枠の「終了」時刻、10エリア）
DROP TABLE IF EXISTS stg_occto;
CREATE TABLE stg_occto (
    date             DATE        NOT NULL,
    time_end         CHAR(5)     NOT NULL,  -- '00:30' ~ '24:00'
    area_name        VARCHAR(10) NOT NULL,  -- 東京など
    reserve_rate     DOUBLE,                -- 広域予備率(%)
    area_demand_fc   DOUBLE,                -- エリア需要(MW)
    area_supply_fc   DOUBLE,                -- エリア供給力(MW)
    area_reserve_mw  DOUBLE,                -- エリア予備力(MW)
    PRIMARY KEY (date, time_end, area_name)
);

-- ⑥ 財務省のLNG輸入データ（月別）
DROP TABLE IF EXISTS stg_lng;
CREATE TABLE stg_lng (
    month_idx   INT     NOT NULL,          -- 年×12 + 月（月単位の計算を容易にするための番号）
    ym          CHAR(7) NOT NULL,          -- '2026-07'
    qty_t       DOUBLE,                    -- 当月数量 (MT)
    value_kyen  DOUBLE,                    -- 当月金額 (千円)
    PRIMARY KEY (month_idx)
);
