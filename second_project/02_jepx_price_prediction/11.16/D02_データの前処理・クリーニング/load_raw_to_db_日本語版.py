"""
元データ6種類のCSV → MySQLのステージングテーブル（stg_*）へロード

Pythonはファイル読み込み（文字コードの判定と冒頭の説明行の処理）のみを担当し、
時刻の整合・欠損値処理・特徴量・目的変数の生成は、すべてSQL（02_transform.sql）で行う。

準備:  pip install pandas sqlalchemy pymysql
実行:  mysql -u root -p < sql/01_schema.sql
       python load_raw_to_db.py --data ./raw_data --db "mysql+pymysql://root:password@localhost:3306/jepx"
比較用: python load_raw_to_db.py --data ./raw_data --db "..." --python-csv merged_30min.csv
"""
import argparse
import glob
import os
import sqlite3

import pandas as pd


def read_text(path):
    raw = open(path, "rb").read()
    try:
        return raw.decode("utf-8-sig"), "utf-8-sig"
    except UnicodeDecodeError:
        return raw.decode("cp932"), "cp932"


def classify(data_dir):
    kinds = {k: [] for k in ["jepx", "tepco", "weather", "holiday", "occto", "lng"]}
    for p in glob.glob(os.path.join(data_dir, "**", "*.csv"), recursive=True):
        txt, enc = read_text(p)
        head = txt[:600]
        if "システムプライス" in head:
            kinds["jepx"].append((p, enc))
        elif "エリア需要" in head and "太陽光発電実績" in head:
            kinds["tepco"].append((p, enc))
        elif "ダウンロードした時刻" in head:
            kinds["weather"].append((p, enc))
        elif "広域予備率(%)" in head:
            kinds["occto"].append((p, enc))
        elif "2711.11" in txt[:3000]:
            kinds["lng"].append((p, enc))
        elif "国民の祝日" in head:
            kinds["holiday"].append((p, enc))
    for k, v in kinds.items():
        print(f"  {k:8s} {len(v):3d}件のファイル")
        if not v:
            raise SystemExit(f"[エラー] {k} のファイルが見つかりません。")
    return kinds


def ymd(s):
    return pd.to_datetime(s, format="%Y/%m/%d").dt.strftime("%Y-%m-%d")


def stg_jepx(files):
    df = pd.concat([pd.read_csv(p, encoding=e) for p, e in files], ignore_index=True)
    out = pd.DataFrame({
        "date": ymd(df["受渡日"]), "slot": df["時刻コード"].astype(int),
        "price_tokyo": df["エリアプライス東京(円/kWh)"], "price_system": df["システムプライス(円/kWh)"],
        "sell_bid_kwh": df["売り入札量(kWh)"], "buy_bid_kwh": df["買い入札量(kWh)"],
        "contract_kwh": df["約定総量(kWh)"]})
    return out.drop_duplicates(["date", "slot"])


TEPCO = {"エリア需要": "demand_mw", "原子力": "nuclear_mw", "火力(LNG)": "lng_mw", "火力(石炭)": "coal_mw",
         "火力(石油)": "oil_mw", "火力(その他)": "thermal_other_mw", "水力": "hydro_mw", "バイオマス": "biomass_mw",
         "太陽光発電実績": "solar_mw", "太陽光出力制御量": "solar_curtail_mw", "風力発電実績": "wind_mw",
         "風力出力制御量": "wind_curtail_mw", "揚水": "pumped_mw", "蓄電池": "battery_mw",
         "連系線": "interconnect_mw", "その他": "other_mw"}


def stg_tepco(files):
    df = pd.concat([pd.read_csv(p, encoding=e, skiprows=1) for p, e in files], ignore_index=True)
    hm = df["TIME"].str.split(":", expand=True).astype(int)
    out = pd.DataFrame({"date": ymd(df["DATE"]),
                        "time_hhmm": hm[0].map("{:02d}".format) + ":" + hm[1].map("{:02d}".format)})
    for jp, en in TEPCO.items():
        out[en] = df[jp]
    return out.drop_duplicates(["date", "time_hhmm"])


def stg_weather(files):
    frames = []
    for p, e in files:
        w = pd.read_csv(p, encoding=e, skiprows=5, header=None)
        frames.append(pd.DataFrame({
            "obs_time": pd.to_datetime(w[0].astype(str).str.strip(), format="mixed"),
            "temp_c": w[1], "humidity": w[4], "solar_rad_mj": w[7], "sunshine_h": w[10], "rain_mm": w[14]}))
    w = pd.concat(frames).drop_duplicates("obs_time").sort_values("obs_time")
    w["obs_time"] = w["obs_time"].dt.strftime("%Y-%m-%d %H:%M:%S")
    return w


def stg_holiday(files):
    p, e = files[0]
    h = pd.read_csv(p, encoding=e)
    return pd.DataFrame({"date": ymd(h.iloc[:, 0]), "holiday_name": h.iloc[:, 1]})


def stg_occto(files):
    df = pd.concat([pd.read_csv(p, encoding=e, skiprows=1) for p, e in files], ignore_index=True)
    out = pd.DataFrame({
        "date": ymd(df["対象年月日"]), "time_end": df["時刻"], "area_name": df["エリア名"],
        "reserve_rate": df["広域予備率(%)"], "area_demand_fc": df["エリア需要(MW)"],
        "area_supply_fc": df["エリア供給力(MW)"], "area_reserve_mw": df["エリア予備力(MW)"]})
    return out.drop_duplicates(["date", "time_end", "area_name"])


def stg_lng(files):
    p, e = files[0]
    raw = pd.read_csv(p, encoding=e, skiprows=10, header=0)
    raw.columns = ["item", "ym", "u1", "u2", "q1", "qty_t", "value_kyen", "cq1", "cq2", "cvalue"]
    raw = raw.dropna(subset=["qty_t"])
    ym = raw["ym"].astype(str).str.strip("'")
    y, m = ym.str[:4].astype(int), ym.str[5:7].astype(int)
    return pd.DataFrame({"month_idx": y * 12 + m, "ym": ym.str.replace("/", "-"),
                         "qty_t": raw["qty_t"], "value_kyen": raw["value_kyen"]})


def connect(url):
    if url.startswith("sqlite:///"):
        return sqlite3.connect(url[len("sqlite:///"):])
    from sqlalchemy import create_engine
    return create_engine(url)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--db", required=True, help='mysql+pymysql://user:pw@localhost:3306/jepx')
    ap.add_argument("--python-csv", default=None, help="比較用のPython出力（merged_30min.csv）")
    a = ap.parse_args()

    k = classify(a.data)
    con = connect(a.db)
    tables = {"stg_jepx": stg_jepx(k["jepx"]), "stg_tepco": stg_tepco(k["tepco"]),
              "stg_weather": stg_weather(k["weather"]), "stg_holiday": stg_holiday(k["holiday"]),
              "stg_occto": stg_occto(k["occto"]), "stg_lng": stg_lng(k["lng"])}
    for name, df in tables.items():
        df.to_sql(name, con, if_exists="append", index=False, chunksize=5000)
        print(f"  {name:12s} {len(df):>8,}行をロード")
    if a.python_csv:
        py = pd.read_csv(a.python_csv)
        py.to_sql("py_dataset", con, if_exists="replace", index=False, chunksize=5000)
        if isinstance(con, sqlite3.Connection):
            con.execute("CREATE INDEX ix_py ON py_dataset (date, slot)")
            con.commit()
        else:
            from sqlalchemy import text
            with con.begin() as c:
                c.execute(text("ALTER TABLE py_dataset MODIFY date DATE, MODIFY slot INT"))
                c.execute(text("CREATE INDEX ix_py ON py_dataset (date, slot)"))
        print(f"  py_dataset   {len(py):>8,}行をロード（比較用）")
    print("完了")
