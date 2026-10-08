#!/bin/bash
# Hakee Kuopion opiskelijaravintoloiden ruokalistat Compassin API:sta
# ja kirjoittaa ne tiedostoon menus.js (window.MENUS = {...}).
# Vaatii: curl, jq
set -euo pipefail
cd "$(dirname "$0")"

# kustannuspaikka|lyhyt nimi|kampus
RESTAURANTS=(
  "0436|Canthia|Yliopistonranta"
  "0437|Snellmania|Yliopistonranta"
  "0439|Tietoteknia|Yliopistonranta"
)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

for entry in "${RESTAURANTS[@]}"; do
  IFS='|' read -r cost name campus <<<"$entry"
  if curl -sf -m 20 "https://www.compass-group.fi/menuapi/feed/json?costNumber=$cost&language=fi" -o "$tmp/raw.json" \
     && jq -e '.MenusForDays' "$tmp/raw.json" >/dev/null 2>&1; then
    jq --arg id "$cost" --arg name "$name" --arg campus "$campus" '{
      id: $id,
      name: $name,
      campus: $campus,
      url: .RestaurantUrl,
      days: [ .MenusForDays[] | {
        date: (.Date | .[0:10]),
        hours: .LunchTime,
        menus: [ .SetMenus | sort_by(.SortOrder)[] | select((.Components | length) > 0) | {
          name: (.Name // ""),
          price: (.Price // ""),
          items: .Components
        } ]
      } ]
    }' "$tmp/raw.json" >"$tmp/$cost.json"
  else
    echo "Varoitus: $name ($cost) haku epäonnistui" >&2
    jq -n --arg id "$cost" --arg name "$name" --arg campus "$campus" \
      '{id: $id, name: $name, campus: $campus, url: null, days: [], error: true}' >"$tmp/$cost.json"
  fi
done

jq -s --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{updated: $updated, restaurants: .}' \
  "$tmp"/[0-9]*.json >"$tmp/all.json"

{ printf 'window.MENUS = '; cat "$tmp/all.json"; printf ';\n'; } >menus.js
echo "Valmis: menus.js ($(jq '.restaurants | length' "$tmp/all.json") ravintolaa)"
