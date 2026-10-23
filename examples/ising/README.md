# Example: when do tiny magnets line up?

The 2D Ising model is a grid of tiny magnets, each pointing up or down. Neighbors that agree lower the energy, and
heat flips magnets at random. When it's hot, the grid is a scramble. Cool it, and below a critical temperature most
of the magnets suddenly agree: order appears out of disorder. That's a **phase change**, the same kind of event as
water freezing or iron becoming magnetic.

It's also the simplest form of the question my physics project asks: when one arrangement turns into another, how
sharp is the change, and how does the answer depend on the size of the system? The hard part there was telling a
true jump from a very steep smooth change on a small system. This example shows why that's hard.

Lars Onsager solved this model exactly in 1944, so the right answers are known in advance:

- order appears below **Tc = 2 / ln(1 + √2) ≈ 2.269**, in units where the magnets' coupling is 1;
- below Tc, an infinitely large grid has magnetization **m = (1 − sinh(2/T)⁻⁴)^(1/8)**, the share of magnets in
  excess pointing the same way; above Tc, m = 0.

So the change is continuous, with no jump, but very steep near Tc. A finite grid can't follow it exactly: its change
is smeared over a range of temperatures, and the range narrows as the grid grows.

## The batch

Four jobs, one grid size each (8 × 8, 16 × 16, 32 × 32 and 64 × 64), at 21 temperatures from 1.5 to 3.5. Each
temperature gets 1,000 warm-up sweeps (one sweep offers every magnet one chance to flip) and then 5,000 measured
sweeps. Seeds are in the configs.

```
python scripts/ising.py configs/ising_L8.json     # a few seconds; try it locally first
```

## What to expect

From one run of each config on a laptop (Python 3.12), so the numbers should match yours closely but not exactly
on other machines:

| T | Onsager (infinite grid) | 8 × 8 | 16 × 16 | 32 × 32 | 64 × 64 |
|---|---|---|---|---|---|
| 1.5 | 0.987 | 0.986 | 0.986 | 0.986 | 0.986 |
| 2.0 | 0.911 | 0.915 | 0.912 | 0.913 | 0.910 |
| 2.2 | 0.785 | 0.825 | 0.789 | 0.797 | 0.790 |
| 2.3 | 0 | 0.749 | 0.623 | 0.537 | 0.294 |
| 2.5 | 0 | 0.608 | 0.383 | 0.242 | 0.091 |
| 3.0 | 0 | 0.338 | 0.173 | 0.082 | 0.042 |
| 3.5 | 0 | 0.246 | 0.124 | 0.062 | 0.031 |

Three checks, each against something known before running:

1. **Well below Tc, every size matches Onsager.** At T ≤ 2.0, all four grids are within 0.005 of the exact value.
   A cold, ordered grid has little to smear.
2. **Just above Tc, the order fades more abruptly on bigger grids.** At T = 2.3, just past 2.269, the 8 × 8 grid
   still shows 0.75 while the 64 × 64 grid is down to 0.29. The smeared change narrows toward Onsager's sharp one.
3. **Well above Tc, the leftover order halves each time the grid's side doubles** (0.34, 0.17, 0.08, 0.04 at
   T = 3.0). That's what random fluctuations alone give: on N magnets that don't agree, the excess pointing one way
   is about √N, a share of 1/√N, which is 1/L on an L × L grid. It isn't order, it's noise, and it shrinks with size.

Near Tc, single runs are noisy, and a single-flip simulation slows down there (critical slowing down), so expect
a few hundredths of scatter between 2.2 and 2.5.

## Time and cost

On one CPU: about 7 seconds for 8 × 8, 30 seconds for 16 × 16, 2 minutes for 32 × 32 and 11 minutes for 64 × 64.
In the cloud all four run at once, so the batch takes as long as its slowest job, plus a minute or two for Fargate to
start the containers. Total cost: about a penny.

To see the change sharpen further, add a 128 × 128 config. Expect about four times the 64 × 64 time.
