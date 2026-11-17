# チーム・モダピ · MySQL前処理パッケージ&nbsp;

6種類の元データ → MySQLへの取り込み → **SQLによる**時刻の整合・欠損値処理・特徴量（X）・目的変数（y）の生成 → Pythonによる処理結果とのクロスチェック。

## ファイル一覧

| ファイル | 役割 | WBS |
| :---- | :---- | :---- |
| `sql/01_schema.sql` | データベース`jepx`と、元データを取り込むための6つのステージングテーブル（`stg_*`）を作成 | 4.1 |
| `load_raw_to_db.py` | 元のCSVを読み込み（文字コード・説明行に対応）、`stg_*`へ取り込む | 4.2 |
| `sql/02_transform.sql` | 基本となる枠組み（日付×48コマ）→ 時刻の整合 → 欠損値の補間 → データ結合 → `LAG`・移動平均・価格急騰ラベルの生成 → `fact_30min` | 4.3 |
| `sql/03_validate.sql` | 行数、1日48コマ、欠損値、データ分割別の価格急騰率、予備率区間別の価格、時間帯別の日射量を検証 | 4.2 |
| `sql/04_compare_with_python.sql` | `fact_30min`（SQL）と`py_dataset`（Python）の70列を比較 | 4.3 |

## 実行手順

```sh
# 0) 事前準備（MySQL 8.0以上）
pip install pandas sqlalchemy pymysql

# 1) テーブルの作成
mysql -u root -p < sql/01_schema.sql

# 2) 元データの取り込み（＋比較用のPython処理結果）
python load_raw_to_db.py --data ./raw_data \
  --db "mysql+pymysql://root:パスワード@localhost:3306/jepx?charset=utf8mb4" \
  --python-csv merged_30min.csv

# 3) 変換 → 検証 → 比較（Workbenchで各ファイルを開いて実行することも可能）
mysql -u root -p < sql/02_transform.sql
mysql -u root -p < sql/03_validate.sql
mysql -u root -p < sql/04_compare_with_python.sql
```

## 正常な結果（事前に確認された値）

- `fact_30min`：**45,312行**（2024-04-01 ～ 2026-10-31、944日 × 48コマ）  
- データ分割別の価格急騰率：train 3.8% · valid 6.1% · test 9.2%  
- 予備率5%以下の平均価格は30.07円 → 20%超では10.66円  
- 時間帯別の日射量は11時が最大（時刻の整合が正常であることを確認）  
- `04_compare`：`only_in_sql = 0`、`only_in_python = 0`、**すべての列で`n_mismatch = 0`**  
- 48コマの検証で東京電力の2026-11-13のデータが1行表示されるのは正常（ダウンロード当日の部分データであるため）  
- OCCTOの欠損17,520コマは正常（2025年4月より前の1年間のデータは提供されていないため）

## SQLで使用した主要構文（発表用）

- `WITH RECURSIVE`：日付×48コマの基本となる枠組みを生成  
- `LAG(x, 48) / LAG(x, 336) OVER (ORDER BY date, slot)`：前日・前週の同じコマの値を取得（データリークの防止）  
- `AVG(...) OVER (ROWS BETWEEN 30 PRECEDING AND 1 PRECEDING)`：前日までの30日間の平均  
- `LAG/LEAD`で気象データの欠損値を補間し、`DATE_SUB(..., INTERVAL 1 HOUR)`で1時間前の値に合わせる  
- `CASE WHEN`：価格急騰ラベル（30日平均の1.5倍）、カレンダーに関する変数、学習・検証・テスト用データの分割
