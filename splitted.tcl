# Name			Splitted
# Author		wilk wilkowy
# Description	Displays nicks still on netsplit
# Version		1.1 (2019..2019-08-21)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: splitted

# Partyline commands: .splitted
# .splitted		- display nicks on split, if any

# Channel commands: !split

# ToDo:
# - too many hardcoded strings

namespace eval splitted::c {

# Users having such flags can trigger channel commands. (use - or -|- to allow all)
variable allowed_users "o|o"

# Users having such flags cannot trigger channel commands. (use "" to disable)
variable ignored_users "I|I"

# Channel command prefix.
variable cmd_prefix "!"

# Channel command name.
variable cmd_name "split"

# Protect against !split command floods, in seconds. (0 - off)
variable antiflood_delay 2

}

# #################################################################### #

namespace eval splitted {

	variable version "1.1"
	variable changed "2019-08-21"
	variable author "wilk"

	namespace eval v {
		variable flood_gate
	}

	proc on_dcc_cmd {hand idx text} {
		foreach chan [channels] {
			if {[channel get $chan inactive]} {
				putdcc $idx "* Channel $chan: (inactive)"
			} elseif {![botonchan $chan]} {
				putdcc $idx "* Channel $chan: (not on channel)"
			} else {
				set nicks [list]
				foreach nick [chanlist $chan] {
					if {[onchansplit $nick $chan]} {
						lappend nicks $nick
					}
				}

				if {[llength $nicks] == 0} {
					putdcc $idx "* Channel $chan: -"
				} else {
					putdcc $idx "* Channel $chan: [join $nicks ", "]"
				}
			}
		}
		return 1
	}

	proc on_pub_cmd {nick uhost hand chan text} {
		set now [unixtime]
		if {![channel get $chan splitted] ||
			($c::ignored_users ne "" && [matchattr $hand $c::ignored_users $chan]) ||
			([info exists v::flood_gate($chan)] && ($now - $v::flood_gate($chan) < $c::antiflood_delay))} { return }
		set v::flood_gate($chan) $now

		set nicks [list]
		foreach user [chanlist $chan] {
			if {[onchansplit $user $chan]} {
				lappend nicks "\002$user\002"
			}
		}

		if {[llength $nicks] == 0} {
			#sendnotc $nick "Nikt z kanału nie jest teraz na splicie."
			sendmsg $chan "Nikt z kanału nie jest teraz na splicie."
		} else {
			sendmsg $chan "Nicki z kanału obecnie na splicie: [join $nicks ", "]."
		}
		return 1
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

		setudef flag splitted

		bind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name} ${ns}::on_pub_cmd

		bind dcc n|- splitted ${ns}::on_dcc_cmd

		putlog "Splitted v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind pub $c::allowed_users ${c::cmd_prefix}${c::cmd_name} ${ns}::on_pub_cmd }
		catch { unbind dcc n|- splitted ${ns}::on_dcc_cmd }

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag splitted
	}

	init
}
