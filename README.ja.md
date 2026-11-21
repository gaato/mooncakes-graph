# mooncakes-graph

MoonBit のエコシステムがいちばん頼っている [mooncakes.io](https://mooncakes.io) のモジュールはどれでしょうか。これは、レジストリの依存グラフを対話的に見られる地図と、`tree(1)` のように依存の木を表示するコマンドラインの道具です。

非公式で、mooncakes.io や MoonBit チームとは関係ありません。

[English](README.md)

## Web

[地図](https://gaato.github.io/mooncakes-graph/)はレジストリの索引から毎日作り直しています。大きいノードほど、それに依存するモジュールが多いことを表します。モジュールをクリックすると、何がそれに依存し、それが何に依存しているかが見られます。`?m=owner/name` で一つのモジュールへ直接リンクできます。

地図の元データはただのファイルとして配信していて、`llms.txt` に一覧があります。データは mooncakes.io のレジストリの索引から作ったもので、モジュールの説明文はそれぞれの作者のものです。

## CLI

```sh
moon update
moonx gaato/mooncakes-graph/cmd/mooncakes-graph dependents OWNER/MODULE
```

```
owner/module
├── someone/app
│   └── someone/app-cli
└── other/tool
3 modules (index as of <when moon update last ran>)
```

コマンドとライブラリの説明は [`mooncakes-graph/README.md`](mooncakes-graph/README.md) にあります。

## モジュール

| ディレクトリ | モジュール | |
|---|---|---|
| `mooncakes-graph/` | [`gaato/mooncakes-graph`](https://mooncakes.io/docs/gaato/mooncakes-graph) | グラフ、その指標、CLI |
| `mooncakes_index/` | [`gaato/mooncakes_index`](https://mooncakes.io/docs/gaato/mooncakes_index) | レジストリの索引を読むもの |
| `force/` | [`gaato/force`](https://mooncakes.io/docs/gaato/force) | 力学モデルによるレイアウト。地図で使用 |
| `site/` | (未公開) | 地図 |

不具合や要望は [Issues](https://github.com/gaato/mooncakes-graph/issues) へどうぞ。

## サイトのビルド

手順は英語版の [Building the site](README.md#building-the-site) にあります。

## ライセンス

Apache-2.0 です。
