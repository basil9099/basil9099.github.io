# Diagrams

Inline SVG diagrams, rendered by the `diagram` shortcode:

```
{{< diagram src="kdetect-architecture.svg" caption="Optional caption." >}}
```

Files here are inlined into the page rather than served as images, so their
colours can be written as CSS custom properties and follow the site's light/dark
toggle. Colours must use these six tokens, mapped to the site palette in
`assets/css/extended/terminal.css`:

| Token             | Light     | Dark      | Use                        |
| ----------------- | --------- | --------- | -------------------------- |
| `--dd-paper`      | `#ffffff` | `#10141a` | Background, label masks    |
| `--dd-paper-2`    | `#f7f8fa` | `#161b23` | Node fill                  |
| `--dd-ink`        | `#14181f` | `#e6e9ee` | Text, node stroke          |
| `--dd-muted`      | `#5a6472` | `#8792a3` | Sublabels, arrows          |
| `--dd-accent`     | `#12694a` | `#3ddc84` | Focal only — 1–2 per diagram |
| `--dd-link`       | `#6b3fa0` | `#c792ea` | Optional / external edges  |

No literal hex values. A hardcoded colour will look correct in one theme and
wrong in the other.

## Provenance

`kdetect-architecture.svg` is a tokenised copy of
[`docs/architecture-diagram.svg`](https://github.com/basil9099/kdetect/blob/main/docs/architecture-diagram.svg)
in the kdetect repo, which is dark-only. It is a copy, not a submodule — if the
upstream diagram changes, re-copy it and re-run the hex-to-token substitution.
