#!/usr/bin/env bash
# Samples Deck temperatures, clocks and power every $2 seconds into CSV $1 until killed.
set -u
out="$1"; interval="${2:-5}"
gpu=""; for h in /sys/class/hwmon/hwmon*; do [[ "$(cat "$h/name")" == amdgpu ]] && gpu="$h"; done
acpi=""; for h in /sys/class/hwmon/hwmon*; do [[ "$(cat "$h/name")" == acpitz ]] && acpi="$h"; done
sclk=$(ls /sys/class/drm/card*/device/pp_dpm_sclk 2>/dev/null | head -1)
echo "epoch,cpu_mhz_avg,gpu_edge_c,acpi_c,gpu_mhz,gpu_power_w,bat_status,bat_pct,mem_avail_mb" > "$out"
while true; do
	cpu=$(awk '{s+=$1;n++} END{printf "%d", s/n/1000}' /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null)
	gt=$([[ -n $gpu ]] && awk '{printf "%.1f",$1/1000}' "$gpu/temp1_input" 2>/dev/null)
	at=$([[ -n $acpi ]] && awk '{printf "%.1f",$1/1000}' "$acpi/temp1_input" 2>/dev/null)
	gm=$([[ -n $sclk ]] && grep '\*' "$sclk" | sed 's/.*: *\([0-9]*\)Mhz.*/\1/')
	gp=$([[ -n $gpu && -r $gpu/power1_average ]] && awk '{printf "%.2f",$1/1000000}' "$gpu/power1_average" 2>/dev/null)
	bs=$(cat /sys/class/power_supply/BAT1/status 2>/dev/null); bp=$(cat /sys/class/power_supply/BAT1/capacity 2>/dev/null)
	ma=$(awk '/MemAvailable/{printf "%d",$2/1024}' /proc/meminfo)
	echo "$(date +%s),$cpu,$gt,$at,$gm,$gp,$bs,$bp,$ma" >> "$out"
	sleep "$interval"
done
