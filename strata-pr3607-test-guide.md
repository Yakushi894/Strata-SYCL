# 本家 Strata PR #3607 Windows SYCL exe — メイン PC（B60）実機テスト手順

ビルド： demetree/Strata `windows-sycl` ブランチ（PR #3607、head `c99f140b`）
エンジン版数： **strata 0.1.60.1** ／ oneAPI 2026.2 ／ VS 2026 Build Tools でビルド（Win10 VPS、約1時間18分）

## 0. 成果物（VPS 側に用意済み）

Win10 VPS（209.209.8.181）の `C:\muse-build\strata-pr3607\` に：

| 物 | 場所 |
|---|---|
| 配布 zip（推奨） | `strata-0.1.60.1-windows-x86_64-sycl.zip`（74,737,195 バイト） |
| 展開済みパッケージ | `package\0.1.60.1-windows-x86_64-sycl\`（18ファイル、213.6 MiB） |

パッケージの中身は `strata.exe` ＋ 実行に要る DLL 一式（sycl9／libmmd／UR アダプタ／oneMKL／TBB／UMF／MSVC ランタイム）。公式のパッケージ化ツールで依存を全解決し、`--verify`（ハッシュ照合）と **oneAPI の無い環境変数での `--version` 起動**を確認済み。メイン PC に oneAPI を入れる必要はない（Level Zero ローダだけは B60 のグラフィックドライバ側が持っている）。

メイン PC では zip を好きな場所に展開する（例： `D:\strata-pr3607\`）。以下のコマンドの `<PKG>` は展開先の `0.1.60.1-windows-x86_64-sycl` フォルダ。

**近道**： 同梱の `strata-test.bat` をそのフォルダに置いてダブルクリックすれば、§1〜§2 を対話式に全部やってくれる（GGUF フォルダを聞く → シャード番号を選ぶ → 環境変数を設定 → 実行 → 2回目を提案）。手打ちしたい場合だけ以下を読む。

## 1. 起動確認（30秒）

```bat
<PKG>\strata.exe --version
```
→ `strata 0.1.60.1` と出れば DLL 解決は OK。

## 2. 本番テスト：直接 generate（B60 で推論が回るか＋速度）

サブコマンドは**無い**（`generate` や `serve` を引数に付けると `unknown argument` になる）。フラグを直接渡す。

まず環境変数（cmd の場合）。**この3つが要点**：

```bat
set SYCL_CACHE_PERSISTENT=0
set STRATA_VERIFY_DEVICE_PLAN=1
set STRATA_VERIFY_NO_HOST=1
```

- `SYCL_CACHE_PERSISTENT=0` … **必須**。永続 JIT キャッシュは Xe2 で初回コンパイル時に segfault する（作者の docs/INTEL.md 明記）
- `STRATA_VERIFY_NO_HOST=1` … エキスパートの一部が VRAM 外にある構成では必須。無いと数トークンで logits が NaN 化する
- `STRATA_VERIFY_DEVICE_PLAN=1` … GPU 側でレイヤ計画を作る指定（作者の標準構成）

実行（モデルは手持ちの **IQ3_S パック**を想定）：

```bat
<PKG>\strata.exe --pack <パックのフォルダ> --native <第1シャード.gguf> --ple-gguf <第2シャード.gguf> ^
  --stream-experts --expert-cache auto --prefill auto ^
  --spec 4 --spec-min-p 0.5 --max-context 8192 ^
  --tokens 1,2,3 --max-new 64 --greedy --stats
```

引数の見分け方：

- `--pack` … XeStrata で使っているパックのフォルダそのもの
- `--native` … 本体シャード（dense 重み入り、第1シャード）
- `--ple-gguf` … `per_layer_token_embd.weight` を含むシャード（PLE／engram 用、第2シャード）。**省略すると PLE が黙って無効化され、以降の数値が全部変わる**ので実測では必ず付ける
- `--tokens` はトークン ID の列。スモークテストでは `1,2,3` のような適当な列でも機械的には回る（出力の意味は見ない）。意味のある文章での確認は §4 の serve で
- `--spec` は native（IQ）パックでは **2 以上必須**（0／1 はエンジンが拒否する）。作者標準は `4` ＋ `--spec-min-p 0.5`
- 初回はエキスパートの入り方が学習されるため、同条件で **2回目**の数値を本命にする

### 判定と詰まったときの対処

| 症状 | 対処 |
|---|---|
| トークンが生成され、`--stats` の段別内訳と ms/token が出る | **成功**。decode の tok/s（＝1000÷ms/token）を控える |
| `REFUSED: N experts are neither in VRAM nor mirrored` | VRAM キャッシュ＋ピン留め RAM ミラーで全エキスパートを覆えていない。`set STRATA_MIRROR_MIB=61440` を足すか、`--max-context` を下げる（RAM 96GB あるのでミラー拡大が本命） |
| 起動直後に落ちる／デバイスが無い系のエラー | ログ全文を回収。UR アダプタ（同梱済み）と B60 ドライバの Level Zero が噛んでいない可能性を切り分ける |
| 数トークンで NaN／文字化け状の崩壊 | `STRATA_VERIFY_NO_HOST=1` が効いているか再確認 |
| **マシンごと固まる** | **要注意**： xe ドライバは VRAM を超える確保を失敗にせずホスト RAM へ退避するため、過大な要求はライブロック→ウォッチドッグでリセットされ得る。`--max-context` と KV を盛らない。VRAM は **1.5GB 以上**空けるのが作者の目安 |

### 物差し（作者実測、B70 32GB・IQ3_S・MTP 有効時）

- Decode： 物語文 30.5 tok/s ／ コード 40.8 tok/s（`--spec 4 --spec-min-p 0.5 --mtp`、INT8 KV）
- Prefill： 4K プロンプトで約 1,000 tok/s
- B60 は VRAM 24GB で常駐エキスパート数が減るぶん、これより遅くなるのが前提。XeStrata の実測と並べて見る

MTP を使う場合は `--mtp <MTP の rt フォルダ>` を追加（パック側に MTP が含まれていればその場所）。

## 3. 報告してほしいもの

- 起動直後のデバイス表示部分を含む**ログ全文**
- `--stats` の出力（特に ms/token）
- エラー時はエラー文そのまま（要約しない）

## 4. （任意）serve で実チャット

実文での確認は Python サーバ経由になる：

```
python sycl\serve\server_intel.py --engine strata --config strata-<model>.json --port 8080
```

これにはメイン PC 側に **repo のチェックアウト一式＋Python** が要る（エンジン exe はパッケージ版を config で指す）。初回テストの範囲外。§2 が通ってから別途組む。

## 5. BENCH キット（純正 BENCH.bat で標準レポートを出す）

イシューに貼れる標準形式のレポート（`bench/results/<日付>-community-<GPU>-<モデル>/` に README.md＋results.json）が要る場合は、VPS の `C:\muse-build\strata-pr3607\strata-bench-kit.zip`（約46MB）を使う。

- 中身： 純正 BENCH.bat（無改造）＋ .venv 位置に置いた Python 3.12.10 同梱ランタイム（jinja2／jsonschema／psutil／numpy 等の依存インストール済み）＋ repo の tools／serve／strata_control／strata_cli ＋ SYCL 用設定 `strata-iq3_s-sycl.json`
- 使い方： 展開 → **`RUN-BENCH.bat` をダブルクリック**。GGUF フォルダを聞かれるので入力すると、シャード／tokenizer／exe の場所から設定 JSON を自動生成して BENCH.bat まで実行する（exe が見つからない時だけパッケージフォルダも聞かれる）。設定 JSON の手編集（`EDIT-ME` 5か所書き換え→BENCH.bat 実行）でも可。サーバ自動起動→固定テスト一式（chat／4K／16K／agent、中央値）→レポート生成まで自動
- 検証範囲： VPS で「ベンチが設定を読みサーバを起動し、tokenizer（vocab.json）を探しに行く」ところまで到達確認済み。実モデルでの完走はメイン PC の初回実行が初検証
- 詳細はキット内の `README-BENCH-KIT.txt`
