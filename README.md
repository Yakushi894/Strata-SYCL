# strata-pr3607-windows-sycl

本家 Strata **PR #3607**（"[Engine] native Windows support for the Intel Arc SYCL port"、demetree/Strata `windows-sycl` ブランチ、`c99f140`）を Windows 10 上でネイティブビルドした成果物の置き場。

ビルド環境： Windows 10 22H2 / Visual Studio Build Tools 2026（MSVC 14.52）/ Intel oneAPI 2026.2（icx）

## 中身

| ファイル | 内容 |
|---|---|
| `strata-0.1.60.1-windows-x86_64-sycl.zip` | エンジン単体パッケージ（strata 0.1.60.1、自己完結・oneAPI 不要で起動可） |
| `strata-bench-kit.zip` | 純正 BENCH.bat をセットアップ無しで動かすキット（Python 同梱＋依存入り） |
| `RUN-BENCH.bat` | ベンチかんたん起動（GGUF の場所を聞いて設定を自動生成→BENCH.bat 実行）。キットの中にも同梱 |
| `strata-test.bat` | 直接 generate のテストバッチ（exe と同じフォルダに置いて使う） |
| `strata-pr3607-test-guide.md` | テスト手順書（運搬→起動確認→generate→詰まった時の対処表） |

## 使い方（最短）

1. 両方の zip を展開する
2. ベンチキット側で `RUN-BENCH.bat` をダブルクリックし、GGUF（パック）のフォルダを入力する
3. 結果は `bench/results/<日付>-community-<GPU>-<モデル>/` に標準形式（README.md＋results.json）で出る

詳細は `strata-pr3607-test-guide.md` を参照。
