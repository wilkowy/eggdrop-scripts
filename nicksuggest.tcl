# Name			Nick Suggest
# Author		wilk wilkowy
# Description	Suggests nick change for visitors with unregistered, irc web gate or common app nicks
# Version		1.1 (2018..2019-04-20)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: nicksuggest

namespace eval nicksuggest::c {

# Users having such flags are ignored and receive no nick suggestion. (use "" to disable)
variable ignored_users "I|I"

# Protect against join floods, in seconds. (0 - off)
variable antiflood_delay 2

# Messages sent when matching nick joins a channel (use empty string to ignore match).
# Available placeholders: #NICK#, #HAND#, #CHAN#
variable message_webchat_our "..."
variable message_webchat "..."
variable message_unregistered ""
variable message_uid "..."
variable message_match "..."

# List of other uncommon nick patterns to send message to.
variable nick_match [list "AndroUser*" "FREAKUser*" "ATWUser*"]

}

# #################################################################### #

namespace eval nicksuggest {

	variable version "1.1"
	variable changed "2019-04-20"
	variable author "wilk"

	namespace eval v {
		variable flood_gate
	}

	proc on_join {nick uhost hand chan} {
		set now [unixtime]
		if {![channel get $chan nicksuggest] ||
			($c::ignored_users ne "" && [matchattr $hand $c::ignored_users $chan]) ||
			([info exists v::flood_gate($chan)] && ($now - $v::flood_gate($chan) < $c::antiflood_delay))} { return }
		set v::flood_gate($chan) $now

		if {[regexp {^Gracz_[0-9]{3}$} $nick]} {
			set msg $c::message_webchat_our
		} elseif {[regexp {^mib_.{6}$} $nick] || [regexp {^Guest_?[0-9]+$} $nick]} {
			set msg $c::message_webchat
		} elseif {[regexp {^Niezident[0-9]+$} $nick]} {
			set msg $c::message_unregistered
		} elseif {[regexp {^[0-9]} $nick]} {
			set msg $c::message_uid
		} elseif {[lmatch $nick $c::nick_match]} {
			set msg $c::message_match
		} else {
			return
		}

		if {$msg ne ""} {
			putlog "NickSuggest: suggestion for $nick on $chan"
			sendmsg $chan [string map [list "#NICK#" $nick "#HAND#" $hand "#CHAN#" $chan] $msg]
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

		setudef flag nicksuggest

		bind join - * ${ns}::on_join

		putlog "NickSuggest v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind join - * ${ns}::on_join }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag nicksuggest
	}

	init
}
