#!/sbin/sh
OUTFD=$2
ZIP=$3
MARK="cq61""tech"
LOGF=/tmp/bad_apple_log.txt
FRAMES=/tmp/ba_frames.txt
MOUNTS=${BA_MOUNTS:-/proc/mounts}
SYSIN=${BA_SYSIN:-/sys/class/input}
ROWS=28
CONTENT=19
DELAY=0.063
NOTOUCH=0
CANDS=""
LOGDIR=""
LOCKED=""

HAVE_PRINTF=0
if [ "$(printf '%s-%s' a b 2>/dev/null)" = "a-b" ]; then
  HAVE_PRINTF=1
fi

emit() {
  if [ "$HAVE_PRINTF" = 1 ]; then
    printf '%s\n' "$1"
  else
    echo "$1"
  fi
}

say() {
  emit "$*" >> "$LOGF"
}

send() {
  emit "$1" >> "/proc/self/fd/$OUTFD"
}

ui_print() {
  send "ui_print $1
ui_print"
}

: > "$LOGF"

add_cand() {
  [ -d "$1" ] || return 0
  case " $CANDS " in
    *" $1 "*) return 0 ;;
  esac
  CANDS="$CANDS $1"
}

scan_storage() {
  for d in /external_sd /sdcard1 /usb_otg /usb-otg /mnt/media_rw/* /storage/* /mnt/usb*; do
    add_cand "$d"
  done
  if [ -r "$MOUNTS" ]; then
    while read -r dev mp fs rest; do
      case "$fs" in
        vfat|exfat|sdfat|texfat|fuseblk|ntfs|ntfs3|msdos) add_cand "$mp" ;;
      esac
    done < "$MOUNTS"
  fi
  for d in /sdcard /data/media/0; do
    add_cand "$d"
  done
}

read_cfg() {
  CFGVAL=""
  for d in $CANDS; do
    if [ -f "$d/$1" ]; then
      CFGVAL=$(cat "$d/$1" 2>/dev/null)
      set -- $CFGVAL
      CFGVAL=$1
      return 0
    fi
  done
  return 1
}

has_cfg() {
  for d in $CANDS; do
    [ -f "$d/$1" ] && return 0
  done
  return 1
}

scan_storage
if read_cfg ba_rows; then ROWS=$CFGVAL; fi
if read_cfg ba_delay; then DELAY=$CFGVAL; fi
if has_cfg ba_notouchlock; then NOTOUCH=1; fi

ZNAME=${ZIP##*/}
case "$ZNAME" in
  *rows[0-9][0-9]*) ROWS=$(echo "$ZNAME" | sed -n 's/.*rows\([0-9][0-9]\).*/\1/p') ;;
esac
case "$ZNAME" in
  *notouch*) NOTOUCH=1 ;;
esac

case "$ROWS" in
  ''|*[!0-9]*) ROWS=28 ;;
esac
case "$DELAY" in
  ''|*[!0-9.]*) DELAY=0.063 ;;
esac
if [ "$ROWS" -lt "$CONTENT" ]; then ROWS=$CONTENT; fi
if [ "$ROWS" -gt 200 ]; then ROWS=200; fi

TOP=$(( (ROWS - CONTENT) / 2 ))
BOT=$(( ROWS - CONTENT - TOP ))

for d in $CANDS; do
  if [ -w "$d" ]; then
    LOGDIR=$d
    break
  fi
done

savelog() {
  if [ -n "$LOGDIR" ]; then
    cp "$LOGF" "$LOGDIR/bad_apple_log.txt" 2>/dev/null
  fi
  return 0
}

NAPMODE=none
if sleep 0.001 2>/dev/null; then
  NAPMODE=sleep
elif command -v usleep >/dev/null 2>&1; then
  NAPMODE=usleep
fi

case "$DELAY" in
  *.*) INT=${DELAY%%.*}; FRAC=${DELAY#*.} ;;
  *) INT=$DELAY; FRAC=0 ;;
esac
INT=${INT:-0}
FRAC=${FRAC}000000
FRAC=${FRAC%"${FRAC#??????}"}
US="${INT}${FRAC}"
while [ "${US#0}" != "$US" ]; do
  US=${US#0}
done
US=${US:-0}

nap() {
  case $NAPMODE in
    sleep) sleep "$DELAY" ;;
    usleep) usleep "$US" ;;
  esac
}

mkprog() {
  case $1 in
    ?) PF="0.00$1" ;;
    ??) PF="0.0$1" ;;
    ???) PF="0.$1" ;;
    *) PF="1.0" ;;
  esac
}

mkpad() {
  if [ "$1" -le 0 ]; then
    PADOUT=""
    return 0
  fi
  s="ui_print  
ui_print"
  j=1
  while [ $j -lt "$1" ]; do
    s="$s
ui_print  
ui_print"
    j=$((j+1))
  done
  PADOUT="$s"
}

lock_node() {
  p=$1
  node=$2
  label=$3
  [ -w "$p" ] || return 0
  cur=$(cat "$p" 2>/dev/null)
  case $node in
    enabled) want=0; unlocked=1 ;;
    *) want=1; unlocked=0 ;;
  esac
  [ "$cur" = "$unlocked" ] || return 0
  echo "$want" > "$p" 2>/dev/null || return 0
  LOCKED="$LOCKED $p=$cur"
  say "locked: $p ($label) $cur -> $want"
}

lock_touch() {
  if [ "$NOTOUCH" = 1 ]; then
    say "touch lock disabled"
    return 0
  fi
  for d in "$SYSIN"/input*; do
    [ -f "$d/name" ] || continue
    nm=$(cat "$d/name" 2>/dev/null)
    case "$nm" in
      *[Kk]ey*|*[Bb]utton*|*[Pp]ower*) continue ;;
    esac
    case "$nm" in
      *ouch*|*sec_ts*|*fts*|*focal*|*tsp*|*ynaptics*|*melfas*|*mxt*|*oodix*|*gt9*|*nt36*|*novatek*|*ilitek*|*himax*|*elan*|*atmel*|*cyttsp*) ;;
      *) continue ;;
    esac
    say "touch candidate: $d ($nm)"
    lock_node "$d/enabled" enabled "$nm"
    lock_node "$d/inhibited" inhibited "$nm"
  done
  lock_node /sys/class/sec/tsp/input/enabled enabled tsp
  if [ -z "$LOCKED" ]; then
    say "no touch node locked"
  fi
}

restore_touch() {
  for e in $LOCKED; do
    p=${e%=*}
    v=${e##*=}
    echo "$v" > "$p" 2>/dev/null
  done
  LOCKED=""
}

trap 'restore_touch' EXIT
trap 'restore_touch; exit 1' INT TERM HUP

say "args: $*"
say "storage:$CANDS"
say "rows=$ROWS top=$TOP bottom=$BOT content=$CONTENT delay=$DELAY nap=$NAPMODE printf=$HAVE_PRINTF"

has_marker() {
  grep -q "$MARK" "$ZIP" 2>/dev/null && return 0
  grep -aq "$MARK" "$ZIP" 2>/dev/null && return 0
  if command -v unzip >/dev/null 2>&1; then
    unzip -l "$ZIP" 2>/dev/null | grep -q "$MARK" && return 0
  fi
  return 1
}

if command -v grep >/dev/null 2>&1; then
  if has_marker; then
    say "marker ok"
  else
    ui_print "ERROR: this zip is modified or incomplete."
    say "marker missing"
    savelog
    exit 1
  fi
else
  say "marker check skipped"
fi

rm -f "$FRAMES"
for f in "$0" /tmp/updater /tmp/update-binary; do
  [ -f "$f" ] || continue
  sed '1,/^__DATA__$/d' "$f" > "$FRAMES" 2>/dev/null
  [ -s "$FRAMES" ] && break
done
if [ ! -s "$FRAMES" ] && command -v unzip >/dev/null 2>&1; then
  unzip -p "$ZIP" META-INF/com/google/android/update-binary 2>/dev/null | sed '1,/^__DATA__$/d' > "$FRAMES"
fi

NL=$(wc -l < "$FRAMES" 2>/dev/null || echo 0)
TOTAL=$((NL/CONTENT))
say "lines=$NL frames=$TOTAL"
if [ "$TOTAL" -lt 1 ]; then
  ui_print "ERROR: cannot read frame data."
  savelog
  exit 1
fi

mkpad "$TOP"; PT="$PADOUT"
mkpad "$BOT"; PB="$PADOUT"

startbuf() {
  buf=""
  if [ -n "$1" ]; then
    buf="set_progress $1"
  fi
  if [ -n "$PT" ]; then
    if [ -n "$buf" ]; then
      buf="$buf
$PT"
    else
      buf="$PT"
    fi
  fi
}

lock_touch
ui_print "BAD APPLE!!"
ui_print "TWRP ASCII - $TOTAL frames"
ui_print "Credits: cq61tech"
if [ -n "$LOCKED" ]; then
  ui_print "Touchscreen locked until playback ends"
fi
ui_print "Starting in 3"; sleep 1
ui_print "2"; sleep 1
ui_print "1"; sleep 1

A0=$(date +%s)
n=0
f=0
startbuf ""
while IFS= read -r line; do
  if [ -z "$line" ]; then line=" "; fi
  if [ -n "$buf" ]; then
    buf="$buf
"
  fi
  buf="${buf}ui_print $line
ui_print"
  n=$((n+1))
  if [ $n -ge $CONTENT ]; then
    out=$buf
    if [ -n "$PB" ]; then
      out="$out
$PB"
    fi
    send "$out"
    f=$((f+1))
    n=0
    if [ $((f % 30)) -eq 0 ]; then
      mkprog $((f*1000/TOTAL))
      startbuf "$PF"
    else
      startbuf ""
    fi
    nap
  fi
done < "$FRAMES"
A1=$(date +%s)
restore_touch
send "set_progress 1.0"
ui_print "DONE. Time: $((A1-A0))s"
say "time: $((A1-A0))s frames: $f"
savelog
exit 0
__DATA__
