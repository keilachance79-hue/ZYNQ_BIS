set root [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint [file join $root build reports capture_synth.dcp]
set outdir [file join $root verification]
file mkdir $outdir
set f [open [file join $outdir package_pins.txt] w]
foreach pin {U18 W8 U8 V13 U13 R18 P15 P16 R16 R17 R19 N17 P18 P19 N18 P20 N20 U20 T20 T19 U19 T11 T12 U12 P14 R14 T17 U17 T16 T15 T14 U15 U14 U9 T9 U10 T10 J20 H20 K19 J19 G19 G20 J18 H18 M20 M19 L19 L20 M18 M17 G17 G18 E19} {
  puts $f "$pin [get_property PIN_FUNC [get_package_pins $pin]]"
}
close $f
puts PHASE2_PIN_DATABASE_PASS
