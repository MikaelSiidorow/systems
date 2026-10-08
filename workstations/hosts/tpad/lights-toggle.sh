# Toggle a dark mode: minimum backlight, software dimming and no mute/mic-mute/
# power LEDs. Mute state itself is untouched. Everything resets on reboot, so
# the saved backlight lives in the runtime dir.
leds=/sys/class/leds
state="${XDG_RUNTIME_DIR:-/tmp}/lights-toggle.backlight"
output=eDP-1

set_backlight() {
  gdbus call --system --dest org.freedesktop.login1 \
    --object-path /org/freedesktop/login1/session/auto \
    --method org.freedesktop.login1.Session.SetBrightness \
    backlight intel_backlight "$1" >/dev/null
}

# LED writes need root; pkexec is setuid only in the system path.
if [[ -f "$state" ]]; then
  /usr/bin/pkexec /bin/sh -c "
    echo audio-micmute > $leds/platform::micmute/trigger
    echo audio-mute > $leds/platform::mute/trigger
    echo 255 > $leds/tpacpi::power/brightness
  "
  set_backlight "$(cat "$state")"
  rm "$state"
  xrandr --output "$output" --brightness 1
  echo "lights: normal"
else
  /usr/bin/pkexec /bin/sh -c "
    for l in micmute mute; do
      echo none > $leds/platform::\$l/trigger
      echo 0 > $leds/platform::\$l/brightness
    done
    echo 0 > $leds/tpacpi::power/brightness
  "
  cat /sys/class/backlight/intel_backlight/brightness >"$state"
  set_backlight 1
  xrandr --output "$output" --brightness 0.5
  echo "lights: dark"
fi
