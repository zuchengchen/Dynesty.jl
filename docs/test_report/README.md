# Dynesty.jl 综合测试与基准报告

本目录包含中文 LaTeX 测试报告源码、报告表格、posterior overlay 图表资产，以及从已有 formal benchmark 输出重新生成这些资产的脚本。

## 文件结构

- `main.tex`: 报告主源码。
- `main.pdf`: 在本机 LaTeX 工具链可用时由 `latexmk` 编译生成。
- `generate_assets.py`: 从已有 benchmark 输出审计并生成报告表格，同时复制 overlay PNG；也读取空气质量 PE benchmark summary。
- `tables/`: 报告使用的 CSV、LaTeX 表格和 benchmark metadata。
- `figures/`: 从 `examples/output/parallel_cost_compare/plots/` 复制来的 9 张 `*julia_vs_python.png`，以及空气质量 PE overlay 图。

## 依赖的已有 benchmark 输出

报告默认复用已经完成的 formal benchmark 输出，不会主动重跑长 benchmark：

- `examples/output/parallel_cost_compare/summary.json`
- `examples/output/parallel_cost_compare/summary.csv`
- `examples/output/parallel_cost_compare/plot_index.csv`
- `examples/output/parallel_cost_compare/plots/*julia_vs_python.png`
- `examples/output/air_quality_pe_compare/summary.json`
- `examples/output/air_quality_pe_compare/plot_index.csv`
- `examples/output/air_quality_pe_compare/plots/air_quality_repeat1_julia_vs_python.png`

`generate_assets.py` 会审计这些文件并要求：

- `mode == "formal"`
- 18 个 run 全部 `status == "ok"`
- 9 个 plot 全部 `status == "ok"`
- plot method 全部为 `corner_overlay`
- 9 个 overlay PNG 文件存在
- 每个 run 的 `used_usr_bin_time == true`
- `process_tree_peak_rss_kb`、`process_tree_peak_pss_kb` 等内存字段存在

## 重新生成表格和复制图

在仓库根目录运行：

```sh
python3 docs/test_report/generate_assets.py
```

该命令读取 `examples/output/parallel_cost_compare/` 和 `examples/output/air_quality_pe_compare/`，并写入：

- `docs/test_report/tables/benchmark_summary.csv`
- `docs/test_report/tables/benchmark_summary.tex`
- `docs/test_report/tables/benchmark_runs.csv`
- `docs/test_report/tables/benchmark_runs.tex`
- `docs/test_report/tables/formal_benchmark_audit.csv`
- `docs/test_report/tables/formal_benchmark_audit.tex`
- `docs/test_report/tables/plot_index.csv`
- `docs/test_report/tables/plot_index.tex`
- `docs/test_report/tables/benchmark_metadata.json`
- `docs/test_report/tables/air_quality_audit.csv`
- `docs/test_report/tables/air_quality_audit.tex`
- `docs/test_report/tables/air_quality_runs.csv`
- `docs/test_report/tables/air_quality_runs.tex`
- `docs/test_report/tables/air_quality_plot_index.csv`
- `docs/test_report/tables/air_quality_plot_index.tex`
- `docs/test_report/tables/air_quality_metadata.json`
- `docs/test_report/figures/*julia_vs_python.png`

## 编译 PDF

本报告使用 `ctexart`，建议用 XeLaTeX 编译：

```sh
cd docs/test_report
latexmk -xelatex -interaction=nonstopmode -halt-on-error main.tex
```

本机已检测到 `xelatex`、`latexmk` 和 `ctexart.cls`，因此可以生成 `main.pdf`。如需清理中间文件：

```sh
cd docs/test_report
latexmk -C main.tex
```

清理后如果需要保留 PDF，可重新运行编译命令。

## benchmark 输出缺失时

如果 `examples/output/parallel_cost_compare/` 缺失或审计失败，应先确认 `/usr/bin/time -v` 可用：

```sh
/usr/bin/time -v true
```

然后在仓库根目录重新运行 formal benchmark。该命令耗时较长，会写入 `examples/output/parallel_cost_compare/`；该目录按仓库约束不提交。

```sh
julia --project=. benchmark/parallel_cost_compare.jl --mode formal --resume
```

benchmark 完成后再运行：

```sh
python3 docs/test_report/generate_assets.py
cd docs/test_report
latexmk -xelatex -interaction=nonstopmode -halt-on-error main.tex
```

空气质量 PE benchmark 的当前报告资产来自 smoke/scaled run，因为当前主机缺失 `/usr/bin/time` 和 `/bin/time`。恢复 GNU time 后，在仓库根目录运行完整或 scaled formal：

```sh
/usr/bin/time -v true
julia --project=. benchmark/air_quality_pe_compare.jl --mode formal --resume
```

如果 Python bridge initialization 或 31 worker processes 过慢，可按 benchmark prompt 降级到 documented scaled formal，例如：

```sh
julia --project=. benchmark/air_quality_pe_compare.jl --mode formal \
  --repeats 2 --nlive 500 --dlogz 0.08 --queue-size 31 --nproc 31 --resume
```

当前环境使用 PyJulia fallback；metadata 会记录 `bridge_kind=pyjulia` 和 `bridge_compiled_modules=false`。不要把 Python runner 改成 Python duplicate likelihood。

## 本次报告记录的验证命令

- `julia --project=. -e 'using Pkg; Pkg.test()'`
- `julia --project=. -e 'include("benchmark/parallel_cost_compare.jl"); println("runner ok")'`
- `python3 -m py_compile benchmark/parallel_cost_corner.py examples/pe_parallel_python.py test/reference/python/generate_reference.py`
- `python3 -m py_compile examples/air_quality_pe_python.py benchmark/air_quality_corner_overlay.py`
- `julia --project=. -e 'include("examples/air_quality_likelihood.jl"); println("air quality likelihood ok")'`
- `julia --project=. -e 'include("benchmark/air_quality_pe_compare.jl"); println("air quality runner ok")'`
- `julia --project=. benchmark/air_quality_pe_compare.jl --mode smoke --allow-missing-usr-time --smoke-nproc 4 --smoke-queue-size 4 --smoke-nlive 60 --smoke-dlogz 0.8 --work-repeats 64 --calibration-trials 5`
- formal benchmark audit via `docs/test_report/generate_assets.py`
- `latexmk -xelatex -interaction=nonstopmode -halt-on-error main.tex`
- `git diff --check`

`Manifest.toml`、`docs/build/`、`examples/output/`、`__pycache__/` 和临时日志不属于本报告提交范围。
