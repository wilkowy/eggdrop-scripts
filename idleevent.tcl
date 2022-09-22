# Name			Idle Event
# Author		wilk wilkowy
# Description	Sends messages to channel when some user is idling too long
# Version		1.1 (2018..2019-04-23)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: idleevent

namespace eval idleevent::c {

# CRON line to execute idle check routine.
variable cron "*/30 14-23"

# Array of list of idlers to monitor for inactivity per channel. Use *lowercase* channel names!
# Format: [list [list handle idle_mins message] ...]
# Inactivity in minutes. (0 - off)
# Available placeholders: #NICK#, #HAND#, #CHAN#, #IDLE#, #USERIDLE#
variable idlers
#set idlers(#...) [list [list "..." 120 "..."]]

}

# #################################################################### #

namespace eval idleevent {

	variable version "1.1"
	variable changed "2019-04-23"
	variable author "wilk"

	proc on_cron_sendmsg {minute hour day month weekday} {
		foreach chan [channels] {
			set lchan [string tolower $chan]
			if {![channel get $chan idleevent] || ![info exists c::idlers($lchan)]} { continue }

			foreach idler $c::idlers($lchan) {
				lassign $idler hand idle msg

				set nick [hand2nick $hand $chan]
				if {$nick eq "" || $idle <= 0 || $msg eq ""} { continue }

				set uidle [getchanidle $nick $chan]
				if {$uidle >= $idle} {
					set hand [nick2hand $nick $chan]
					putlog "IdleEvent: sending message for $nick on $chan who is idling for $uidle minutes"
					sendmsg $chan [string map [list "#NICK#" $nick "#HAND#" $hand "#CHAN#" $chan "#IDLE#" $idle "#USERIDLE#" $uidle] $msg]
				}
			}
		}
	}

# -=-=-=-=-=-

	proc init {} {
		variable version; variable author
		set ns [namespace current]

		if {![info exists ::wilk::version]} {
			uplevel #0 source [file dirname [info script]]/wilk.tcl
		}
		namespace import ::wilk::*
		::wilk::register $ns

		setudef flag idleevent

		bind cron - $c::cron ${ns}::on_cron_sendmsg

		putlog "IdleEvent v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind cron - $c::cron ${ns}::on_cron_sendmsg }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag idleevent
	}

	init
}
