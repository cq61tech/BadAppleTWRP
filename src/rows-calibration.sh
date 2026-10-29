#!/sbin/sh
OUTFD=$2
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
ui_print() {
  emit "ui_print $1
ui_print" >> "/proc/self/fd/$OUTFD"
}
ui_print "CALIBRATION"
ui_print "Columns: read the last digit visible before the line wraps"
ui_print "         1         2         3         4         5         6         7         8         9        10"
ui_print "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890"
ui_print "Rows test starts in 15 seconds"
sleep 15
i=1
while [ $i -le 80 ]; do
  ui_print "$i"
  i=$((i+1))
done
ui_print "END. Count the fully visible numbered lines (this is ba_rows)"
exit 0
