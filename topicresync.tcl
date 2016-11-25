# Topic Resync & Recovery after a netsplit
# by wilk wilkowy // 2015..2016-11-16

# Todo: move vars to .chanset

# Resync delay in minutes (0 - instant).
set topres_delay 10

# Protect against floods (inertia), in seconds (0 - off).
set topres_protect 30

# Default channel topics.
#set topres_default(#channel) "Hello!"

setudef flag topicresync

bind rejn - * topres:check
bind topc o|o * topres:change
bind dcc n|n topicresync topres:dccresync

proc topres:dccresync {hand idx text} {
	if {$text eq "now"} {
		topres:resync
	} elseif {$text eq "info"} {
		topres:info
	} else {
		putlog "Usage: .topicresync <info/now>"
		return
	}
	return 1
}

proc topres:check {nick uhost hand chan} {
	global topres_timer topres_delay topres_flood topres_protect
	if {$topres_protect > 0} {
		if {[info exists topres_flood] && $topres_flood} { return }
		set topres_flood 1
		utimer $topres_protect topres:protect
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

proc topres:protect {} {
	global topres_flood
	set topres_flood 0
}

proc topres:change {nick uhost hand chan topic} {
	global topres_topic
	set topres_topic($chan) $topic
	return
}

proc topres:resync {} {
	global topres_topic topres_default
	foreach chan [channels] {
		if {![channel get $chan topicresync] || ![botisop $chan]} { continue }
		set topic [topic $chan]
		if {$topic ne ""} {
			putlog "Topic resync ($chan): $topic"
			putserv "TOPIC $chan :$topic"
			set topres_topic($chan) $topic
		} elseif {[info exists topres_topic($chan)] && $topres_topic($chan) ne ""} {
			putlog "Topic recovery ($chan): $topres_topic($chan)"
			putserv "TOPIC $chan :$topres_topic($chan)"
		} elseif {[info exists topres_default($chan)] && $topres_default($chan) ne ""} {
			putlog "Topic default ($chan): $topres_default($chan)"
			putserv "TOPIC $chan :$topres_default($chan)"
			set topres_topic($chan) $topres_default($chan)
		}
	}
}

proc topres:info {} {
	global topres_topic topres_default
	foreach chan [channels] {
		if {![channel get $chan topicresync]} { continue }
		putlog "* Channel $chan:"
		putlog "| Topic (current) : [topic $chan]"
		if {[info exists topres_topic($chan)]} {
			putlog "| Topic (backup)  : $topres_topic($chan)"
		}
		if {[info exists topres_default($chan)]} {
			putlog "| Topic (default) : $topres_default($chan)"
		}
	}
}

putlog "Topic Resync v1.7 by wilk"
