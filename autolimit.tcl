# Auto Limit Updater (based on Psotnic limiter)
# by wilk wilkowy // 2016..2017-01-29

# Todo: move vars to .chanset
# Todo: add dcc cmds w/o enforcing

# Limit update latency in seconds - new user (0 - instant).
set alimit_delay_up 120

# Limit update latency in seconds - gone user (0 - instant).
set alimit_delay_down 30

# Limit update latency in seconds - server mode change (netsplit, got op) (0 - instant).
set alimit_delay_server 5

# Limit update latency in seconds - owner mode change (0 - instant).
set alimit_delay_owner 15

# Limit update latency in seconds - bot mode change (0 - instant).
set alimit_delay_bot $alimit_delay_up

# Limit update latency in seconds - @ mode change (0 - instant).
set alimit_delay_op 0

# Keep this amount of free limit space for users.
set alimit_offset 5

# Limit tolerance to reduce amount of unnecessary updates (<0 - percent of offset, >0 - static, 0 - off).
set alimit_tolerance -50

# Protect against floods (inertia), in seconds (0 - off).
set alimit_protect 15

# On/off .chanset flag.
setudef flag autolimit

bind join - * alimit:join
bind part - * alimit:part
bind sign - * alimit:quit
bind kick - * alimit:kick
bind mode - *+l* alimit:mode
bind mode - *-l* alimit:mode
bind mode - *+o* alimit:mode
bind dcc n|n autolimit alimit:dccupdate

proc alimit:dccupdate {hand idx text} {
	if {$text eq "info"} {
		alimit:info $idx
	} elseif {$text eq "all"} {
		foreach chan [channels] {
			alimit:update $chan 1
		}
		return 1
	} elseif {[validchan $text]} {
		alimit:update $text 1
		return 1
	} else {
		putdcc $idx "Usage: .autolimit <info/all/#>"
	}
	return
}

proc alimit:join {nick uhost hand chan} {
	global alimit_delay_up
	alimit:change $chan $alimit_delay_up
	return
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
	global alimit_delay_server alimit_delay_owner alimit_delay_bot alimit_delay_op
	if {[isbotnick $nick] || ![botisop $chan]} { return }
	if {$mode eq "+o" && [isbotnick $whom]} {
		alimit:change $chan $alimit_delay_server 1 1
	} elseif {($mode eq "-l" || $mode eq "+l")} {
		set enforce 0
		if {$nick eq "" && $hand eq "*"} {
			set delay $alimit_delay_server
			if {$mode eq "-l"} { set enforce 1 }
		} elseif {$hand ne "" && $hand ne "*" && [matchattr $hand n|n $chan]} {
			set delay $alimit_delay_owner
		} elseif {$hand ne "" && $hand ne "*" && [matchattr $hand b|- $chan]} {
			set delay $alimit_delay_bot
		} else {
			set delay $alimit_delay_op
			if {$mode eq "-l"} { set enforce 1 }
		}
		alimit:change $chan $delay 1 $enforce
	}
	return
}

proc alimit:change {chan delay {nocheck 0} {enforce 0}} {
	global alimit_timer alimit_flood alimit_protect
	if {!$nocheck && $alimit_protect > 0} {
		if {[info exists alimit_flood($chan)] && $alimit_flood($chan)} { return }
		set alimit_flood($chan) 1
		utimer $alimit_protect [list alimit:protect $chan]
	}
	if {[info exists alimit_timer($chan)] && [lsearch -glob [utimers] "*$alimit_timer($chan)"] != -1} {
		killutimer $alimit_timer($chan)
	}
	if {$delay > 0} {
		set alimit_timer($chan) [utimer $delay [list alimit:update $chan $enforce]]
	} else {
		alimit:update $chan $enforce
	}
}

proc alimit:protect {chan} {
	global alimit_flood
	set alimit_flood($chan) 0
}

proc alimit:update {chan {enforce 0}} {
	global alimit_offset alimit_tolerance
	if {![channel get $chan autolimit] || ![botonchan $chan] || ![botisop $chan]} { return }
	set users [llength [chanlist $chan]]
	set modes [split [getchanmode $chan]]
	set limit 0
	if {[string match *l* [lindex $modes 0]]} {
		set limit [lindex $modes end]
	}
	set new_limit [expr {$users + $alimit_offset}]
	if {$new_limit == $limit && !$enforce} { return }
	if {$alimit_tolerance >= 0} {
		set tolerance $alimit_tolerance
	} else {
		set tolerance [expr {int($alimit_offset * $alimit_tolerance / -100.0)}]
	}
	if {$enforce || $limit < [expr {$users + $alimit_offset - $tolerance}] || $limit > [expr {$users + $alimit_offset + $tolerance}]} {
		putlog "Limit change ($chan/$users): $limit -> $new_limit"
		pushmode $chan +l $new_limit
		#flushmode $chan
	}
}

proc alimit:info {idx} {
	global alimit_tolerance alimit_offset alimit_timer
	foreach chan [channels] {
		if {![channel get $chan autolimit]} { continue }
		putdcc $idx "* Channel $chan:"
		if {$alimit_tolerance >= 0} {
			set tolerance $alimit_tolerance
		} else {
			set tolerance [expr {int($alimit_offset * $alimit_tolerance / -100.0)}]
		}
		set modes [split [getchanmode $chan]]
		set limit 0
		if {[string match *l* [lindex $modes 0]]} {
			set limit [lindex $modes end]
		}
		set users [llength [chanlist $chan]]
		set range "ANYONE"
		if {$limit} {
			set min [expr {$limit - $alimit_offset - $tolerance}]
			set max [expr {$limit - $alimit_offset + $tolerance}]
			set range "$min..$max"
		}
		putdcc $idx "| Users  : $users \[current limit allows: $range]"
		set exp [expr {$users + $alimit_offset}]
		set min [expr {$exp - $tolerance}]
		set max [expr {$exp + $tolerance}]
		set status "ok"
		if {$limit < $min || $limit > $max} { set status "update!" }
		putdcc $idx "| Limit  : $limit \[expected: $exp, allowed: $min..$max] ($status)"
		if {[info exists alimit_timer($chan)]} {
			set timers [utimers]
			set timer [lsearch -glob $timers "*$alimit_timer($chan)"]
			if {$timer != -1} {
				set status ""
				if {[lindex $timers $timer 1 2] == 1} { set status " (forced)" }
				putdcc $idx "| Update : [lindex $timers $timer 0]s$status"
			}
		}
	}
}

putlog "Auto Limit v1.6 by wilk"
