# Name		Topic Resync & Recovery after a netsplit
# Author	wilk wilkowy
# Version	1.13 (2015..2017-07-14)
# License	GNU GPL v2 or any later version

# Todo: move vars to .chanset

# Resync delay in minutes (0 - instant).
set topres_delay 15

# Protect against floods (inertia), in seconds (0 - off).
set topres_protect 30

# Resync topic everywhere (unless set by @ before timer runs out) [1] or only on channels where someone netsplitted [0].
set topres_everywhere 1

# Default channel topics.
#set topres_default(#channel) "Hello!"

# On/off .chanset flag.
setudef flag topicresync

bind rejn - * topres:check
bind topc o|o * topres:change
bind dcc n|n topicresync topres:dcc

if {![info exists topres_flood]} { set topres_flood 0 }

proc topres:dcc {hand idx text} {
	if {$text eq "now"} {
		topres:resync
		return 1
	} elseif {$text eq "info"} {
		topres:info $idx
	} else {
		putdcc $idx "Usage: .topicresync <info/now>"
	}
	return
}

proc topres:cleantxt {text} {
	return [string map {"\002" "B" "\003" "C" "\017" "P" "\026" "R" "\037" "U" "\035" "I"} $text]
}

proc topres:check {nick uhost hand chan} {
	global topres_timer topres_delay topres_flood topres_protect topres_resync
	set topres_resync($chan) 1
	if {$topres_protect > 0} {
		if {$topres_flood} { return }
		set topres_flood 1
		utimer $topres_protect [list set topres_flood 0]
	}
	if {[info exists topres_timer] && [lsearch -glob [timers] "*$topres_timer"] != -1} {
		killtimer $topres_timer
	}
	if {$topres_delay > 0} {
		set topres_timer [timer $topres_delay topres:resync]
	} else {
		topres:resync
	}
	return
}

proc topres:change {nick uhost hand chan topic} {
	global topres_topic topres_resync
	set topres_topic($chan) $topic
	set topres_resync($chan) 0
	return
}

proc topres:resync {} {
	global topres_topic topres_default topres_resync topres_everywhere topres_timer
	if {[info exists topres_timer]} {
		unset topres_timer
	}
	foreach chan [channels] {
		if {![channel get $chan topicresync] || ![botisop $chan]} { continue }
		if {[info exists topres_resync($chan)]} {
			set resync $topres_resync($chan)
		} else {
			set resync $topres_everywhere
		}
		set topres_resync($chan) $topres_everywhere
		if {!$resync} { continue }
		set chtopic [topic $chan]
		if {$chtopic ne ""} {
			set topic [topres:cleantxt $chtopic]
			set length [format "%03d" [string length $topic]]
			putlog "Topic resync ($chan) \[$length]: $topic"
			putserv "TOPIC $chan :$chtopic"
			set topres_topic($chan) $chtopic
		} elseif {[info exists topres_topic($chan)] && $topres_topic($chan) ne ""} {
			set topic [topres:cleantxt $topres_topic($chan)]
			set length [format "%03d" [string length $topic]]
			putlog "Topic recovery ($chan) \[$length]: $topic"
			putserv "TOPIC $chan :$topres_topic($chan)"
		} elseif {[info exists topres_default($chan)] && $topres_default($chan) ne ""} {
			set topic [topres:cleantxt $topres_default($chan)]
			set length [format "%03d" [string length $topic]]
			putlog "Topic default ($chan) \[$length]: $topic"
			putserv "TOPIC $chan :$topres_default($chan)"
			set topres_topic($chan) $topres_default($chan)
		}
	}
}

proc topres:info {idx} {
	global topres_topic topres_default
	foreach chan [channels] {
		if {![channel get $chan topicresync]} {
			putdcc $idx "* Channel $chan: (resync disabled)"
		} elseif {[channel get $chan inactive]} {
			putdcc $idx "* Channel $chan: (inactive)"
		} elseif {![botonchan $chan]} {
			putdcc $idx "* Channel $chan: (not on channel)"
		} else {
			set status ""
			if {![botisop $chan]} {
				set status " (need ops)"
			}
			putdcc $idx "* Channel $chan:$status"
			set topic [topres:cleantxt [topic $chan]]
			set length [format "%03d" [string length $topic]]
			putdcc $idx "| Topic (current) \[$length] : $topic"
			if {[info exists topres_topic($chan)]} {
				set topic [topres:cleantxt $topres_topic($chan)]
				set length [format "%03d" [string length $topic]]
				putdcc $idx "| Topic (backup) \[$length]  : $topic"
			}
			if {[info exists topres_default($chan)]} {
				set topic [topres:cleantxt $topres_default($chan)]
				set length [format "%03d" [string length $topic]]
				putdcc $idx "| Topic (default) \[$length] : $topic"
			}
		}
	}
}

putlog "Topic Resync v1.13 by wilk"
