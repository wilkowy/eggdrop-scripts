# Name			VoiceAll
# Author		wilk wilkowy
# Description	Voices everyone joining an enabled channel after a delay
# Version		1.2 (2019..2021-06-29)
# License		GNU GPL v2 or any later version
# Support		https://www.quizpl.net

# Channel flags: voiceall

# Info:
# - voices are given on user join, bot gets +o or someone gets -v
# - voices are not given to cuttent +%@, users receiving +autovoice/halfop/op, users with a/y/g/q/k flags (autoop/autohalfop/autovoice/quiet/autokick)
# - bots/helpers are chosen randomly for each voice
# - if use_botnet is 1 then you need to have this script loaded on all bots and enabled for the same channels

# ToDo: per user timers?

namespace eval voiceall::c {

# Delay of giving +v to prevent voice-floods, in seconds. (0 - instant, min:max notation is allowed)
variable voice_delay 5

# While during $voice_delay interval:
# 1: join1 ... join2 ... join3
#  only join1 starts timer (subsequent joins are ignored) and after $voice_delay seconds all apt users will be voiced, even if join3 will be voiced after shorter period than $voice_delay
# 2: join1 ... join2 ... join3
#  every join will reset timer and start $voice_delay timer over again; abuse from malicious users (join/part) could cause situation where users will not be voiced for a long time
variable voice_mode 1

# Protect against join floods, in seconds. (0 - off)
variable antiflood_delay 2

# Users having such flags are ignored and receive no voice. (use "" to disable)
variable ignored_users "I|I"

# Set to 1 if you have a linked botnet so the bot to voice will be rolled by a dice.
# This requires all bots to have voiceall.tcl loaded and +voiceall channel flag, otherwise put them in ignored_bots.
variable use_botnet 1

# This bots will be removed from dice roll if use_botnet == 1.
variable ignored_bots [list]

# Put here *handles* of other bots considered as master voicers for this one, while any of them is present on channel with @ then this bot will not voice newcomers.
variable master_bots [list]

}

# #################################################################### #

namespace eval voiceall {

	variable version "1.2"
	variable changed "2021-06-29"
	variable author "wilk"

	namespace eval v {
		variable flood_gate
		variable voice_timer
	}

	proc on_join {nick uhost hand chan} {
		set now [unixtime]
		if {![channel get $chan voiceall] ||
			[isbotnick $nick] ||
			([info exists v::flood_gate($chan)] && ($now - $v::flood_gate($chan) < $c::antiflood_delay))
		} then { return }
		set v::flood_gate($chan) $now

		init_voice_all $chan
	}

	proc on_mode_op {nick uhost hand chan mode whom} {
		if {![channel get $chan voiceall] ||
			$mode ne "+o" ||
			![isbotnick $whom] ||
			[wasop $whom $chan]
		} then { return }

		init_voice_all $chan
	}

	proc on_mode_devoice {nick uhost hand chan mode whom} {
		set now [unixtime]
		if {![channel get $chan voiceall] ||
			$mode ne "-v" ||
			([info exists v::flood_gate($chan)] && ($now - $v::flood_gate($chan) < $c::antiflood_delay))
		} then { return }
		set v::flood_gate($chan) $now

		init_voice_all $chan
	}

	proc init_voice_all {chan} {
		if {[info exists v::voice_timer($chan)] && $c::voice_mode == 1} { return }

		kill_utimer [namespace current]::v::voice_timer($chan)
		set delay [minmax_delay $c::voice_delay]
		if {$delay > 0} {
			set v::voice_timer($chan) [utimer $delay [list [namespace current]::voice_all $chan]]
		} else {
			voice_all $chan
		}
	}

	proc voice_all {chan} {
		unset -nocomplain v::voice_timer($chan)

		if {![botisop $chan] || (!$c::use_botnet && [chanhasop $chan $c::master_bots])} { return }

		set voiced 0
		foreach nick [chanlist $chan] {
			set hand [nick2hand $nick $chan]
			if {($c::ignored_users ne "" && [matchattr $hand $c::ignored_users $chan]) ||
				[isvoice $nick $chan] ||
				[ishalfop $nick $chan] ||
				[isop $nick $chan] ||
				[matchattr $hand "aygqk|aygqk" $chan] ||
				([channel get $chan autoop] && [matchattr $hand "o|o" $chan]) ||
				([channel get $chan autohalfop] && [matchattr $hand "l|l" $chan]) ||
				([channel get $chan autovoice] && [matchattr $hand "v|v" $chan])
			} then { continue }

			if {!$c::use_botnet || [myturn "voiceall$nick" $chan 1 1 $c::ignored_bots]} {
				pushmode $chan "+v" $nick
				incr voiced
			}
		}

		if {$voiced > 0} {
			set uword [flex $voiced "user" "users" "users"]
			putlog "VoiceAll: voicing $voiced $uword on $chan"
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

		setudef flag voiceall

		bind join - * ${ns}::on_join
		bind mode - *+o* ${ns}::on_mode_op
		bind mode - *-v* ${ns}::on_mode_devoice

		putlog "VoiceAll v$version by $author"
	}

	proc unload {{keepns 0}} {
		set ns [namespace current]

		catch { unbind join - * ${ns}::on_join }
		catch { unbind mode - *+o* ${ns}::on_mode_op }
		catch { unbind mode - *-v* ${ns}::on_mode_devoice }

		kill_utimers ${ns}::v::voice_timer

		if {!$keepns} {
			namespace delete $ns
		}
	}

	proc uninstall {} {
		unload
		deludef flag voiceall
	}

	init
}
