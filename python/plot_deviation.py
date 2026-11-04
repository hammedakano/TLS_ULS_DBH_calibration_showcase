"""Figure: deviation of modelled stand mean DBH from the field (tape) mean, per unseen plot.
Run after R/calibration_transfer.R:  python python/plot_deviation.py"""
import pandas as pd
import matplotlib.pyplot as plt

t = pd.read_csv("results/plot_table.csv")
plots = ["BR01", "BR03", "BR05", "KA09", "KA11", "KA10"]
methods = [("pooled", "Drone model from other plots", "#5f6b66", "o"),
           ("size_dependent", "Calibration transfer (this design)", "#26783a", "D"),
           ("additive_tls", "Additive TLS distribution", "#b81414", "s")]
fig, ax = plt.subplots(figsize=(8, 4.6), dpi=200)
ax.axvspan(-1.5, 1.5, color="#8cc63f", alpha=0.18, lw=0, label="Within 1.5 cm of the field mean")
ax.axvline(0, color="#111111", lw=1)
for k, (m, lab, c, mk) in enumerate(methods):
    for i, p in enumerate(plots):
        v = t[(t["plot"] == p) & (t.method == m)].dev_cm.iloc[0]
        ax.plot(v, i + (k - 1) * 0.22, mk, color=c, ms=7, alpha=0.45 if p == "KA10" else 1,
                label=lab if i == 0 else None)
ax.set_yticks(range(len(plots)), [p if p != "KA10" else "KA10 (3 trees)" for p in plots])
ax.invert_yaxis()
ax.set_xlabel("Modelled minus field stand mean DBH (cm)")
ax.set_title("Each plot predicted by a model trained on the other plots", fontsize=11)
ax.legend(frameon=False, fontsize=8, loc="upper left")
for s in ("top", "right"):
    ax.spines[s].set_visible(False)
fig.tight_layout()
fig.savefig("results/deviation_by_plot.png")
