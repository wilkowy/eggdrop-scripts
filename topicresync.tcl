# Name		Topic Resync & Recovery after a netsplit
# Author	wilk wilkowy
# Version	1.14 (2015..2018-01-29)
# License	GNU GPL v2 or any later version

# Resync delay, in minutes (0 - instant).
set topres_delay 15

# Protect against floods, in seconds (0 - off).
set topres_antiflood 15

# Resync topic everywhere?
# 1: unless set by @ before timer runs out
# 0: only on channels where someone netsplitted
set topres_everywhere 1

# Default channel topics.
#set topres_default(#channel) "Hello!"

# On/off .chanset flag.
setudef flag topicresync

bind rejn - * topres:check
bind topc o|o * topres:change
bind dcc n|n topicresync topres:dcc

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
	global topres_timer topres_delay topres_flood topres_antiflood topres_resync
	set topres_resync($chan) 1
	set now [unixtime]
	if {[info exists topres_flood] && ($now - $topres_flood) < $topres_antiflood} { return }
	set topres_flood $now
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
		set topic [topic $chan]
		if {$topic ne ""} {
			set ctopic [topres:cleantxt $topic]
			set length [format "%03d" [string length $ctopic]]
			putlog "Topic resync ($chan) \[$length]: $ctopic"
			putserv "TOPIC $chan :$topic"
			set topres_topic($chan) $topic
		} elseif {[info exists topres_topic($chan)] && $topres_topic($chan) ne ""} {
			set ctopic [topres:cleantxt $topres_topic($chan)]
			set length [format "%03d" [string length $ctopic]]
			putlog "Topic recovery ($chan) \[$length]: $ctopic"
			putserv "TOPIC $chan :$topres_topic($chan)"
		} elseif {[info exists topres_default($chan)] && $topres_default($chan) ne ""} {
			set ctopic [topres:cleantxt $topres_default($chan)]
			set length [format "%03d" [string length $ctopic]]
			putlog "Topic default ($chan) \[$length]: $ctopic"
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
			set info "* Channel $chan:"
			if {![botisop $chan]} {
				append info " (need ops)"
			}
			putdcc $idx $info
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

putlog "Topic Resync v1.14 by wilk"
