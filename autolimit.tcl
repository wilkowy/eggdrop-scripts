# Name		Auto-Limit (based on Psotnic limiter)
# Author	wilk wilkowy
# Version	1.12 (2016..2018-01-29)
# License	GNU GPL v2 or any later version

# Limit update latency in seconds - new user (0 - instant, min:max notation allowed).
set alimit_delay_up 120

# Limit update latency in seconds - gone user (0 - instant, min:max notation allowed).
set alimit_delay_down 30

# Limit update latency in seconds - bot got opped (0 - instant, -1 - ignore, min:max notation allowed).
set alimit_delay_gotop 5

# Limit update latency in seconds - server mode change (netsplit) (0 - instant, -1 - ignore, min:max notation allowed).
set alimit_delay_server 5

# Limit update latency in seconds - owner mode change (0 - instant, -1 - ignore, min:max notation allowed).
set alimit_delay_owner -1

# Limit update latency in seconds - bot mode change (0 - instant, -1 - ignore, min:max notation allowed).
set alimit_delay_bot 120

# Limit update latency in seconds - @ mode change (0 - instant, -1 - ignore, min:max notation allowed).
set alimit_delay_op 0

# Limit update latency in seconds - someone else mode change (0 - instant, -1 - ignore, min:max notation allowed).
set alimit_delay_unknown 0

# Keep this amount of free limit space for users.
set alimit_offset 5

# Limit tolerance to reduce amount of unnecessary updates (<0 - percent of offset, >0 - static, 0 - off).
set alimit_tolerance -50

# Protect against event floods, in seconds (0 - off).
set alimit_antiflood 15

# Lockdown duration in seconds (0 - off). Lockdown closes the channel (+i) to prevent join/part floods with clones.
set alimit_lockdown_time 15

# On/off .chanset flags.
setudef flag autolimit
setudef flag lockdown

bind join - * alimit:join
#bind rejn - * alimit:netjoin
bind part - * alimit:part
bind sign - * alimit:quit
bind kick - * alimit:kick
bind mode - *+l* alimit:mode
bind mode - *-l* alimit:mode
bind mode - *+o* alimit:mode
bind dcc n|n autolimit alimit:dcc

proc alimit:dcc {hand idx text} {
	if {$text eq "info"} {
		alimit:info $idx
	} elseif {$text eq "now"} {
		foreach chan [channels] {
			alimit:update $chan
		}
		return 1
	} elseif {$text eq "now!"} {
		foreach chan [channels] {
			alimit:update $chan 1
		}
		return 1
	} elseif {[validchan $text]} {
		alimit:update $text 1
		return 1
	} else {
		putdcc $idx "Usage: .autolimit <info/now/now!/#>"
	}
	return
}

proc alimit:getdelay {value} {
	set time [split $value ":"]
	if {[llength $time] > 1} {
		set min [lindex $time 0]
		set max [lindex $time 1]
		if {$min > $max} {
			foreach {min max} [list $max $min] {break}
		}
		return [expr {[rand [expr {$max + 1 - $min}]] + $min}]
	} else {
		return $value
	}
}

proc alimit:getlimit {chan} {
	set modes [split [getchanmode $chan]]
	if {[string match *l* [lindex $modes 0]]} {
		return [lindex $modes end]
	} else {
		return ""
	}
}

proc alimit:islocked {chan} {
	return [string match *i* [lindex [split [getchanmode $chan]] 0]]
}

proc alimit:join {nick uhost hand chan} {
	global alimit_delay_up alimit_lockdown_time alimit_lockdown
	set users [llength [chanlist $chan]]
	set limit [alimit:getlimit $chan]
	if {$limit ne "" && $users >= $limit} {
		if {$alimit_lockdown_time > 0 && [channel get $chan lockdown] && [botisop $chan] && ![alimit:islocked $chan] && (![info exists alimit_lockdown($chan)] || $alimit_lockdown($chan) == 0)} {
			set alimit_lockdown($chan) 1
			pushmode $chan +i
			flushmode $chan
			putlog "Channel is full ($chan/$users:$limit) - lockdown!"
			utimer $alimit_lockdown_time [list alimit:unlock $chan]
		} else {
			putlog "Channel is full ($chan/$users:$limit)!"
		}
	}
	alimit:change $chan $alimit_delay_up
	return
}

proc alimit:unlock {chan} {
	global alimit_lockdown
	set alimit_lockdown($chan) 0
	pushmode $chan -i
	set users [llength [chanlist $chan]]
	set limit [alimit:getlimit $chan]
	putlog "Lockdown lifted ($chan/$users:$limit)"
}

proc alimit:part {nick uhost hand chan {msg ""}} {
	global alimit_delay_down
	alimit:change $chan $alimit_delay_down
	return
}

proc alimit:quit {nick uhost hand chan why} {
	global alimit_delay_down
	alimit:change $chan $alimit_delay_down
	return
}

proc alimit:kick {nick uhost hand chan whom why} {
	global alimit_delay_down
	alimit:change $chan $alimit_delay_down
	return
}

proc alimit:mode {nick uhost hand chan mode whom} {
	global alimit_delay_server alimit_delay_gotop alimit_delay_owner alimit_delay_bot alimit_delay_op alimit_delay_unknown
	if {[isbotnick $nick] || ![botisop $chan]} { return }
	if {$mode eq "+o" && [isbotnick $whom]} {
		if {$alimit_delay_gotop < 0} { return }
		alimit:change $chan $alimit_delay_gotop 1
	} elseif {($mode eq "-l" || $mode eq "+l")} {
		set enforce 0
		if {$nick eq "" && $hand eq "*"} {
			if {$alimit_delay_server < 0} { return }
			set delay $alimit_delay_server
			if {$mode eq "-l"} { set enforce 1 }
		} elseif {$hand ne "" && $hand ne "*" && [matchattr $hand b|- $chan]} {
			if {$alimit_delay_bot < 0} { return }
			set delay $alimit_delay_bot
		} elseif {$hand ne "" && $hand ne "*" && [matchattr $hand n|n $chan]} {
			if {$alimit_delay_owner < 0} { return }
			set delay $alimit_delay_owner
		} elseif {$hand ne "" && $hand ne "*" && [matchattr $hand o|o $chan]} {
			if {$alimit_delay_op < 0} { return }
			set delay $alimit_delay_op
			if {$mode eq "-l"} { set enforce 1 }
		} else {
			if {$alimit_delay_unknown < 0} { return }
			set delay $alimit_delay_unknown
			if {$mode eq "-l"} { set enforce 1 }
		}
		alimit:change $chan $delay 1 $enforce
	}
	return
}

proc alimit:change {chan delay {nocheck 0} {enforce 0}} {
	global alimit_timer alimit_flood alimit_antiflood
	set now [unixtime]
	if {!$nocheck && [info exists alimit_flood($chan)] && ($now - $alimit_flood($chan)) < $alimit_antiflood} { return }
	set alimit_flood($chan) $now
	if {[info exists alimit_timer($chan)] && [lsearch -glob [utimers] "*$alimit_timer($chan)"] != -1} {
		killutimer $alimit_timer($chan)
	}
	set delay [alimit:getdelay $delay]
	if {$delay > 0} {
		set alimit_timer($chan) [utimer $delay [list alimit:update $chan $enforce]]
	} else {
		alimit:update $chan $enforce
	}
}

proc alimit:update {chan {enforce 0}} {
	global alimit_offset alimit_tolerance alimit_limit alimit_timer
	if {[info exists alimit_timer($chan)]} {
		unset alimit_timer($chan)
	}
	if {![channel get $chan autolimit] || ![botisop $chan]} { return }
	set users [llength [chanlist $chan]]
	set limit [alimit:getlimit $chan]
	set new_limit [expr {$users + $alimit_offset}]
	if {$limit ne "" && $new_limit == $limit && !$enforce} { return }
	if {$alimit_tolerance >= 0} {
		set tolerance $alimit_tolerance
	} else {
		set tolerance [expr {int($alimit_offset * $alimit_tolerance / -100.0)}]
	}
	if {$enforce || $limit eq "" || $limit < $users + $alimit_offset - $tolerance || $limit > $users + $alimit_offset + $tolerance} {
		if {$limit eq ""} {
			set limit "none"
		}
		putlog "Limit change ($chan/$users): $limit -> $new_limit"
		pushmode $chan +l $new_limit
		set alimit_limit($chan) $new_limit
		#flushmode $chan
	}
}

proc alimit:info {idx} {
	global alimit_tolerance alimit_offset alimit_timer
	foreach chan [channels] {
		if {![channel get $chan autolimit]} {
			putdcc $idx "* Channel $chan: (autolimit disabled)"
		} elseif {[channel get $chan inactive]} {
			putdcc $idx "* Channel $chan: (inactive)"
		} elseif {![botonchan $chan]} {
			putdcc $idx "* Channel $chan: (not on channel)"
		} else {
			set info "* Channel $chan:"
			if {![botisop $chan]} {
				append info " (need ops)"
			}
			putdcc $idx $info
			if {$alimit_tolerance >= 0} {
				set tolerance $alimit_tolerance
			} else {
				set tolerance [expr {int($alimit_offset * $alimit_tolerance / -100.0)}]
			}
			set limit [alimit:getlimit $chan]
			set users [llength [chanlist $chan]]
			set range "NOONE"
			if {$limit eq ""} {
				set range "ANYONE"
			} elseif {$limit > 0} {
				set min [expr {$limit - $alimit_offset - $tolerance}]
				set max [expr {$limit - $alimit_offset + $tolerance}]
				set range "$min..$max"
			}
			putdcc $idx "| Users : $users \[current limit allows: $range]"
			set exp [expr {$users + $alimit_offset}]
			set min [expr {$exp - $tolerance}]
			set max [expr {$exp + $tolerance}]
			set status "ok"
			if {$limit eq "" || $limit < $min || $limit > $max} { set status "update required" }
			if {[info exists alimit_timer($chan)]} {
				set timers [utimers]
				set timer [lsearch -glob $timers "*$alimit_timer($chan)"]
				if {$timer != -1} {
					append status ", update in [lindex $timers $timer 0]s"
					if {[lindex $timers $timer 1 2] == 1} { append status ", forced" }
				}
			}
			if {$limit eq ""} {
				set limit "none"
			}
			putdcc $idx "| Limit : $limit \[expected: $exp, tolerance: $min..$max] ($status)"
		}
	}
}

putlog "Auto Limit v1.12 by wilk"
