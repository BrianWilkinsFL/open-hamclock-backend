#!/usr/bin/env bash
# lib_sizes.sh - shared size selection for OHB map generators

# Canonical default list (keep in sync with HamClock)
DEFAULT_SIZES=( \
  "660x330" \
  "1320x660" \
  "1980x990" \
  "2640x1320" \
  "3960x1980" \
  "5280x2640" \
  "5940x2970" \
  "7920x3960" \
)

# Validate a single token looks like WxH.
ohb_is_size() {
  [[ "$1" =~ ^[0-9]+x[0-9]+$ ]]
}

# Load sizes into global bash array SIZES=()
#
# Inputs (in order of precedence):
#  1) OHB_SIZES env var: "660x330,1320x660"
#  2) An optional config file: /opt/hamclock-backend/etc/ohb-sizes.conf
#  3) DEFAULT_SIZES
#
# Outputs:
#  - Global array: SIZES=( "660x330" ... )
#  - Global string: OHB_SIZES_NORM="660x330,1320x660,..."
ohb_load_sizes() {
  local cfg="/opt/hamclock-backend/etc/ohb-sizes.conf"
  local raw=""

  # If OHB_SIZES not already set, try config file.
  if [[ -z "${OHB_SIZES:-}" && -r "$cfg" ]]; then
    # shellcheck disable=SC1090
    source "$cfg" 2>/dev/null || true
  fi

  raw="${OHB_SIZES:-}"

  # If still empty, use defaults.
  if [[ -z "$raw" ]]; then
    SIZES=( "${DEFAULT_SIZES[@]}" )
    OHB_SIZES_NORM="$(IFS=','; echo "${SIZES[*]}")"
    return 0
  fi

  # Normalize: remove whitespace, split on commas, dedupe preserving order, validate.
  raw="${raw//[[:space:]]/}"
  IFS=',' read -r -a _tmp <<< "$raw"

  declare -A _seen=()
  SIZES=()
  local s
  for s in "${_tmp[@]}"; do
    [[ -n "$s" ]] || continue
    if ! ohb_is_size "$s"; then
      echo "ERROR: invalid size '$s' (expected WxH like 660x330)" >&2
      return 1
    fi
    if [[ -z "${_seen[$s]:-}" ]]; then
      _seen[$s]=1
      SIZES+=( "$s" )
    fi
  done

  if [[ ${#SIZES[@]} -eq 0 ]]; then
    echo "ERROR: empty size list after parsing OHB_SIZES='$raw'" >&2
    return 1
  fi

  OHB_SIZES_NORM="$(IFS=','; echo "${SIZES[*]}")"
  return 0
}
