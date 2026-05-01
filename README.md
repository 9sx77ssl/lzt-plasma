# LZT Market Balance — KDE Plasma 6 Widget

Plasmoid that shows your [Lolzteam Market](https://lzt.market) balance in the panel.

![Plasma 6](https://img.shields.io/badge/Plasma-6.0+-blue) ![License](https://img.shields.io/badge/License-MIT-green)

## Features

- Live balance in panel with auto-refresh
- Currency conversion (RUB, USD, EUR, UAH, GBP, BYN, KZT, BTC)
- Fallback API server if primary fails
- Right-click → Transfer Money (send funds to other users)
- Right-click → Refresh Balance
- Silent background updates, no UI flicker
- Native Plasma config dialog (right-click → Configure)

## Install

One-line install (always latest version):

```bash
sh -c "$(curl -sS https://raw.githubusercontent.com/9sx77ssl/lzt-plasma/main/install.sh)"
```

Or manual install:

```bash
git clone https://github.com/9sx77ssl/lzt-plasma.git
cd lzt-plasma
chmod +x install.sh
./install.sh
```

Restart Plasma:

```bash
kquitapp6 plasmashell && kstart plasmashell
```

Add the widget: right-click panel → Add Widgets → search "LZT Market Balance".

## Settings

Right-click widget → Configure:

- **API Key** — get it at [lolz.live/account/api](https://lolz.live/account/api)
- **API Server** — prod-api or api (auto-fallback)
- **Balance refresh interval** — default 30 sec
- **Display currency** — RUB/USD/EUR/UAH/GBP/BYN/KZT/BTC
- **Currency rate refresh** — default 5 min

## Uninstall

```bash
kpackagetool6 -t Plasma/Applet -r org.kde.plasma.lztbalance
```

## Author

[gay1234](https://lolz.live/gay1234)
