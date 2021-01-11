#!/bin/bash
set -x

LIB=/usr/lib/libjamulus-os-utils
source $LIB

declare -A soundcards

SOUND_CARDS="$(cat /proc/asound/cards | perl -n -e 's/^\s*([0-9])+\s+\[(.*?)\s*\]:\ (.*)$//g &&  printf("%d:%02d:%s:%s\n", $1,$1,$2,$3);')"
LIST_STRING=""

while read SOUND_CARD;
do
  ID="$(echo "$SOUND_CARD" | cut -d":" -f1)"
  NUM="$(echo "$SOUND_CARD" | cut -d":" -f2)"
  CARD_NAME="$(echo "$SOUND_CARD" | cut -d":" -f3)"
  CARD_LONGNAME="$(echo "$SOUND_CARD" | cut -d":" -f4)"
  if [ "$(cat /proc/asound/pcm | grep -E "^$NUM" | grep -i "usb")" != "" ]; then USB="usb"; else USB="internal"; fi

  ANSWER="$ID:$USB:$CARD_NAME:$CARD_LONGNAME"
  key="$CARD_LONGNAME ($USB)"

  soundcards[$key]=$ANSWER
done < <(echo "$SOUND_CARDS")

# check for existing config file
CONFIG=0
if [ -f ~/.sound-card-settings ]; then
  IFS='|' ans=( $(cat ~/.sound-card-settings) )
  SETTINGS_OUT=${ans[0]}
  SETTINGS_IN=${ans[1]}
  SETTINGS_PERIOD=${ans[2]}
  if [ "${soundcards[$SETTINGS_OUT]}" != "" ] && [ "${soundcards[$SETTINGS_IN]}" != "" ]; then
    yad --borders=20 --title "Einstellungen" --button=gtk-yes:0 --button=gtk-no:1 --text "<b>Es wurde eine alte Konfiguration gefunden:</b>\n\n* Ausgabe: $SETTINGS_OUT\n* Eingabe: $SETTINGS_IN\n* Puffergröße: $SETTINGS_PERIOD\n\nMöchtest du mit diesen Einstellungen Jamulus starten?"
    if [ $? -eq 0 ]; then
      CONFIG=1
    fi
  fi
fi

if [ $CONFIG -ne 1 ]; then
  COMBOSTRING=""
  for card in "${!soundcards[@]}"; do COMBOSTRING+="$card\!"; done
  COMBOSTRING1=${COMBOSTRING%\\!}

  IFS='|' ans=( $(yad --geometry=800x400 --borders=20 --title "Einstellungen" --text "Bitte wähle hier dein Ein- und Ausgabegerät für Jamulus.\n" --form --field="Ausgabegerät:CB" "$COMBOSTRING1" --field="Eingabegerät:CB" "$COMBOSTRING1" --field="Puffergröße (Frames/Periode):CB" "64!^128!256!512") )

  if [ $? -eq 0 ]; then
    SETTINGS_OUT=${ans[0]}
    SETTINGS_IN=${ans[1]}
    SETTINGS_PERIOD=${ans[2]}
  else
    rm -f ~/.sound-card-settings
    exit 1
  fi
fi

OPTIMAL_CARD_PARAM="${soundcards[$SETTINGS_OUT]}:$SETTINGS_PERIOD:48000"

$JACK_CONTROL eps realtime-priority 85
set_default_jack_server "" "$OPTIMAL_CARD_PARAM"

if [ "$SETTINGS_OUT" != "$SETTINGS_IN" ]; then
  ans="$(echo ${soundcards[$SETTINGS_IN]} | perl -n -e 's/^([0-9])+//g &&  printf("%d\n", $1);')"
  alsa_in -j alsa_in -d hw:$ans &
  INPUT_DEVICE1=alsa_in:capture_1
  INPUT_DEVICE2=alsa_in:capture_2
else
  INPUT_DEVICE1=system:capture_1
  INPUT_DEVICE2=system:capture_2
fi

/usr/bin/Jamulus -j &
PID=$!
jack_mixer -c ~/.jamulus_mixer.conf &
PID2=$!
sleep 5
jack_connect $INPUT_DEVICE1 "jack_mixer:Jam In L"
jack_connect $INPUT_DEVICE2 "jack_mixer:Jam In R"
jack_connect "jack_mixer:Jam In Out L" "Jamulus:input left"
jack_connect "jack_mixer:Jam In Out R" "Jamulus:input right"

jack_connect "Jamulus:output left" "jack_mixer:Jam Out L"
jack_connect "Jamulus:output right" "jack_mixer:Jam Out R"
jack_connect "jack_mixer:Jam Out Out L" system:playback_1
jack_connect "jack_mixer:Jam Out Out R" system:playback_2

# save settings to file
echo "$SETTINGS_OUT|$SETTINGS_IN|$SETTINGS_PERIOD" > ~/.sound-card-settings

wait $PID
echo "Jamulus process has ended"
kill $PID2
stop_jack
