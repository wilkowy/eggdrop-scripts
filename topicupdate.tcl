# Name		Topic Update: data->jutro->dzis
# Author	wilk wilkowy
# Version	1.14 (2015..2017-07-07)
# License	GNU GPL v2 or any later version

# On/off .chanset flag.
setudef flag topicupdate

bind time - "00 00 *" topupd:update
bind dcc n|n topicupdate topupd:dcc

proc topupd:dcc {hand idx text} {
	if {$text eq "now"} {
		topupd:update logfile
		return 1
	} else {
		putdcc $idx "Usage: .topicupdate <now>"
	}
	return
}

proc topupd:update {minute hour day month year} {
	set now_day [strftime %-d]
	set now_month [strftime %-m]
	foreach chan [channels] {
		if {![channel get $chan topicupdate] || ![botisop $chan]} { continue }
		set topic [topic $chan]
		if {$topic eq ""} { continue }
		set oldtopic $topic
		set update 0
		if {[string match -nocase "*jutro*" $topic]} {
			set topic [string map -nocase {"JUTRO" "DZIS"} $topic]
			regsub -all -nocase -- "\0030?3((?:Nast|Next|Quiz)\[^:\]*?: DZIS )" $topic "\0034\\1" topic
			incr update
		}
		set matches [regexp -all -inline -nocase -- {(?:(?:\mwe? )?(?:poniedzialek|po?n\.|wtorek|wto?\.|srod[ae]|sro?\.|czwartek|czw\.|piatek|piat?\.|pt\.|sobot[ae]|sob\.|niedziel[ae]|nie\.|niedz\.) )?\(([0-3]?[0-9])[./]([01]?[0-9])\)} $topic]
		foreach {match event_day event_month} $matches {
			set event_day [scan $event_day %d]
			set event_month [scan $event_month %d]
			set prev_day [expr {$event_day - 1}]
			set prev_month $event_month
			set prev_year [strftime %Y]
			if {$prev_day == 0} {
				incr prev_month -1
				if {$prev_month == 0} {
					set prev_month 12
					incr prev_year -1
				}
				if {$prev_month == 2} {
					set prev_day 28
					if {([expr {$prev_year % 4}] == 0 && [expr {$prev_year % 100}] != 0) || [expr {$prev_year % 400}] == 0} {
						incr prev_day 1
					}
				} elseif {$prev_month in [list 1 3 5 7 8 10 12]} {
					set prev_day 31
				} else {
					set prev_day 30
				}
			}
			set soon ""
			if {$now_day == $prev_day && $now_month == $prev_month} {
				set soon "JUTRO"
			} elseif {$now_day == $event_day && $now_month == $event_month} {
				set soon "DZIS"
			}
			if {$soon ne ""} {
				set topic [string map -nocase [list $match $soon] $topic]
				regsub -nocase -- "\0030?3((?:Nast|Next|Quiz)\[^:\]*?: )" $topic "\0034\\1" topic
				incr update
			}
		}
		if {$update} {
			putlog "Topic update ($chan) from: $oldtopic"
			putlog "Topic update ($chan) to  : $topic"
			putserv "TOPIC $chan :$topic"
		}
	}
	return
}

putlog "Topic Update v1.14 by wilk"
