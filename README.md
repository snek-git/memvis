# memvis

Visualize process memory layout as ASCII art.

```
[■·····■··■■·····■······■··■······■···■··■·····■······■··■·····■··■·······■·······■]
```

## Usage

```bash
./memvis.sh <pid> [width]
./memvis.sh $(pgrep firefox) 120
```

## What you see

- `■` mapped memory regions  
- `·` unmapped gaps
- Colors: heap (red), stack (blue), libs (magenta), text (green), anon (cyan)

Parses `/proc/pid/maps` and scales address ranges to fit your terminal. Shows userspace only.

Requires Python 3 for 64-bit math.
